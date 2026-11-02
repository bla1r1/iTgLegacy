#import "TGChatViewControllerInternal.h"
#import "TGVideoNoteRecorder.h"
#import "TGVideoNoteViewController.h"
#import "TGVoiceRecorder.h"
#import "TGVoiceDecoder.h"
#import "TGMusicPlayer.h"
#import "TGStyle.h"
#import "TGPlayerView.h"

static CGPoint sTouchStart;
static CGFloat sDragDeltaX;
static BOOL sIsLocked;
static BOOL sIsCancelled;
static BOOL sSendInFlight;

/// The tap-to-toggle threshold: release before it and the touch was a mode
/// switch, not a recording - Telegram waits the same beat before it starts
/// writing, so a tap never produces a stray shard of audio.
static const NSTimeInterval kRecordToggleTapSeconds = 0.25;
/// How long the hint under a mode switch stays readable.
static const NSTimeInterval kRecordHintSeconds = 1.6;

@implementation TGChatViewController (Audio)

#pragma mark - voice

/// Send is for typed text, the microphone for everything else - showing both
/// at once would leave one of them dead.
/// Send takes the microphone's place once there is something to send, and
/// the two cross over with a quick scale rather than blinking.
- (void)inputChanged {
	[self reportTyping];
	// Asked after the typing settles rather than per keystroke: one request
	// per link, and the answer is thrown away if the text moved on.
	[NSObject cancelPreviousPerformRequestsWithTarget:self
											 selector:@selector(refreshLinkPreview)
											   object:nil];
	[self performSelector:@selector(refreshLinkPreview) withObject:nil
			   afterDelay:0.7];
	BOOL hasText = self.input.text.length > 0;
	UIButton *coming = hasText ? self.sendButton : self.micButton;
	UIButton *going = hasText ? self.micButton : self.sendButton;
	if (!coming.hidden && going.hidden)
		return;

	if (!self.view.window){
		coming.hidden = NO;
		going.hidden = YES;
		return;
	}
	CGAffineTransform small = CGAffineTransformMakeScale(TGTransformScaleSmall, TGTransformScaleSmall);
	coming.hidden = NO;
	coming.alpha = TGAlphaTransparent;
	coming.transform = small;
	[UIView animateWithDuration:TGAnimationDurationFast animations:^{
		coming.alpha = TGAlphaOpaque;
		coming.transform = CGAffineTransformIdentity;
		going.alpha = TGAlphaTransparent;
		going.transform = small;
	} completion:^(BOOL finished){
		// Settle on whatever the text says now; it may have changed again
		// while this ran.
		BOOL text = self.input.text.length > 0;
		self.sendButton.hidden = !text;
		self.micButton.hidden = text;
		for (UIButton *button in @[self.sendButton, self.micButton]){
			button.alpha = 1;
			button.transform = CGAffineTransformIdentity;
		}
	}];
}

/// Their recording panel: a red dot, the running time, "Slide to cancel", and
/// the microphone grown into a disc with a halo around it.
- (void)showRecordPanel {
	CGRect bar = self.inputBar.frame;
	TGTheme *theme = [TGTheme shared];
	if (!self.recordPanel){
		self.recordPanel = [[TGRecordBar alloc] initWithFrame:bar];

		self.recordCancelSlideLabel = [[UILabel alloc] initWithFrame:
				CGRectMake(kRecordSlideX, TGCenteredOrigin(kInputHeight, TGMetricLineRow),
						bar.size.width - kRecordSlideRoom, TGMetricLineRow)];
		self.recordCancelSlideLabel.text = @"‹ Slide to cancel";
		self.recordCancelSlideLabel.font = TGFontBody();
		self.recordCancelSlideLabel.textColor = [theme secondaryTextColour];
		self.recordCancelSlideLabel.backgroundColor = [UIColor clearColor];
		self.recordCancelSlideLabel.autoresizingMask = UIViewAutoresizingFlexibleWidth;
		[self.recordPanel addSubview:self.recordCancelSlideLabel];

		// Cancel, send and pause wait for the lock: until then a finger is
		// welded to the mic and none of them can be reached.
		self.recordCancelButton = self.recordPanel.cancelButton;
		[self.recordCancelButton addTarget:self action:@selector(recordCancel) forControlEvents:UIControlEventTouchUpInside];
		self.recordSendButton = self.recordPanel.sendButton;
		[self.recordSendButton addTarget:self action:@selector(recordFinish) forControlEvents:UIControlEventTouchUpInside];
		self.recordPauseButton = self.recordPanel.pauseButton;
		[self.recordPauseButton addTarget:self action:@selector(recordPauseToggled)
				  forControlEvents:UIControlEventTouchUpInside];

		// Classic halo and disc (original design)
		CGFloat halo = TGMetricRecordHaloSide, disc = TGMetricRow;
		UIView *ring = [[UIView alloc] initWithFrame:
				CGRectMake(bar.size.width - halo + TGMetricPadSmall, TGCenteredOrigin(kInputHeight, halo), halo, halo)];
		ring.backgroundColor = [theme accentColour];
		ring.alpha = TGAlphaRingTrack;
		ring.layer.cornerRadius = TGHalf(TGMetricRecordHaloSide);
		ring.tag = 0x81C1;
		ring.autoresizingMask = UIViewAutoresizingFlexibleLeftMargin;
		[self.recordPanel addSubview:ring];

		UIImageView *button = [[UIImageView alloc] initWithFrame:CGRectMake(
				CGRectGetMidX(ring.frame) - TGHalf(disc), TGCenteredOrigin(kInputHeight, disc), disc, disc)];
		button.backgroundColor = [theme accentColour];
		button.layer.cornerRadius = TGHalf(TGMetricRow);
		button.tag = 0x81C2;
		button.autoresizingMask = UIViewAutoresizingFlexibleLeftMargin;
		[self.recordPanel addSubview:button];
	}

	sIsLocked = NO;
	sIsCancelled = NO;
	sDragDeltaX = 0;
	sSendInFlight = NO;
	self.recordCancelButton.hidden = YES;
	self.recordSendButton.hidden = YES;
	if (self.recordPauseButton){
		self.recordPauseButton.hidden = YES;
		// The pause disc keeps the state of the last recording on it; a fresh
		// one starts unpaused.
		[self.recordPauseButton setImage:[TGIcons pause] forState:UIControlStateNormal];
	}
	self.recordCancelSlideLabel.hidden = NO;
	self.recordCancelSlideLabel.transform = CGAffineTransformIdentity;
	self.recordCancelSlideLabel.alpha = TGAlphaOpaque;
	[self.recordPanel viewWithTag:0x81C1].hidden = NO;
	[self.recordPanel viewWithTag:0x81C2].hidden = NO;
	// From the first hundredth of the hold the disc says what is being recorded.
	((UIImageView *)[self.recordPanel viewWithTag:0x81C2]).image = self.videoNoteMode
			? [TGIcons glyphNamed:@"video" colour:[theme onAccentColour] side:TGMetricMenuGlyph]
			: [TGIcons microphoneOfSide:TGMetricRow colour:[theme onAccentColour]];

	self.recordPanel.frame = bar;
	[self.recordPanel showSeconds:0 paused:NO];
	self.recordPanel.userInteractionEnabled = NO;
	[self.view addSubview:self.recordPanel];

	// The "Rice Grain" lock capsule directly above mic button (Image 2)
	if (!self.recordLockView) {
		CGFloat pillW = TGMetricVoicePillWidth, pillH = TGMetricVoicePillHeight;
		CGFloat pillX = bar.origin.x + bar.size.width - pillW - TGMetricVoiceLockMaxShift;
		CGFloat pillY = bar.origin.y - pillH - TGMetricPadMedium;
		UIView *pill = [[UIView alloc] initWithFrame:CGRectMake(pillX, pillY, pillW, pillH)];
		pill.backgroundColor = [[TGTheme shared] recordLockColour];
		pill.layer.cornerRadius = TGHalf(pillW); // Rounded rice grain capsule
		pill.clipsToBounds = YES;

		UIImageView *lockIcon = [[UIImageView alloc] initWithFrame:
				CGRectMake(TGCenteredOrigin(pillW, kRecordLockGlyph), TGMetricPad,
						kRecordLockGlyph, kRecordLockGlyph)];
		lockIcon.image = [TGIcons lockOfSide:kRecordLockGlyph
									  colour:[[TGTheme shared] onMediaColour]];
		lockIcon.backgroundColor = [UIColor clearColor];
		[pill addSubview:lockIcon];

		UIImageView *arrow = [[UIImageView alloc] initWithFrame:
				CGRectMake(TGCenteredOrigin(pillW, kRecordLockArrow), kRecordLockArrowY,
						kRecordLockArrow, kRecordLockArrow)];
		arrow.image = [TGIcons glyphNamed:@"chevronUp"
									  colour:[[TGTheme shared] secondaryTextColour]
										side:kRecordLockArrow];
		arrow.backgroundColor = [UIColor clearColor];
		[pill addSubview:arrow];

		self.recordLockView = pill;
	}
	if (!self.recordOnceButton){
		self.recordOnceButton = [TGRecordBar onceButton];
		[self.recordOnceButton addTarget:self action:@selector(toggleRecordOnce)
						forControlEvents:UIControlEventTouchUpInside];
	}
	// Above the lock, where Telegram puts the one-time choice: tapping it
	// makes the note self-destruct ten seconds after it is opened.
	CGFloat onceSide = TGMetricRow;
	CGFloat pillH = TGMetricVoicePillHeight;
	CGFloat onceY = bar.origin.y - pillH - TGMetricPadMedium - onceSide - TGMetricPadSmall;
	self.recordOnceButton.frame = CGRectMake(
			bar.origin.x + bar.size.width - onceSide - TGMetricVoiceLockMaxShift,
			onceY, onceSide, onceSide);
	[self.view addSubview:self.recordOnceButton];

	self.recordLockView.alpha = TGAlphaTransparent;
	self.recordLockView.transform = CGAffineTransformMakeTranslation(0, kRecordLockRest);
	[self.view addSubview:self.recordLockView];
	[UIView animateWithDuration:TGAnimationDurationNormal animations:^{
		self.recordLockView.alpha = TGAlphaOpaque;
		self.recordLockView.transform = CGAffineTransformIdentity;
	}];
}

- (void)hideRecordPanel {
	self.table.scrollEnabled = YES;
	[self.recordPanel removeFromSuperview];
	[self.recordLockView removeFromSuperview];
	self.recordLockView = nil;
	[self.recordOnceButton removeFromSuperview];
	self.recordOnceButton = nil;
	sIsLocked = NO;
	sIsCancelled = NO;
	sDragDeltaX = 0;
	self.recordCancelSlideLabel.transform = CGAffineTransformIdentity;
	self.recordCancelSlideLabel.alpha = TGAlphaOpaque;
}

- (void)lockRecording {
	if (sIsLocked) return;
	sIsLocked = YES;
	self.table.scrollEnabled = YES;
	self.recordPanel.userInteractionEnabled = YES;

	[UIView animateWithDuration:TGAnimationDurationNormal animations:^{
		self.recordLockView.alpha = TGAlphaTransparent;
		self.recordLockView.transform = CGAffineTransformMakeTranslation(0, -kRecordLockLift);
	} completion:^(BOOL finished) {
		[self.recordLockView removeFromSuperview];
		self.recordLockView = nil;
	}];

	self.recordCancelSlideLabel.hidden = YES;
	[self.recordPanel viewWithTag:0x81C1].hidden = YES;
	[self.recordPanel viewWithTag:0x81C2].hidden = YES;

	self.recordCancelButton.hidden = NO;
	self.recordSendButton.hidden = NO;
	self.recordPauseButton.hidden = NO;
}

- (void)updateRecordModeIcon {
	UIImage *video = [TGIcons glyphNamed:@"video"
								  colour:[[TGTheme shared] secondaryTextColour]
									side:TGMetricMenuGlyph];
	[self.micButton setImage:(self.videoNoteMode ? video : [TGIcons microphone])
					forState:UIControlStateNormal];
}

/// The mode outlives the chat: Telegram writes it down the moment it changes,
/// and the next chat opens on whatever the last recording was.
- (void)toggleRecordMode {
	self.videoNoteMode = !self.videoNoteMode;
	[[NSUserDefaults standardUserDefaults] setBool:self.videoNoteMode
											forKey:kRecordVideoModeKey];
	[UIView transitionWithView:self.micButton duration:TGAnimationDurationNormal
					   options:UIViewAnimationOptionTransitionFlipFromLeft
					animations:^{ [self updateRecordModeIcon]; }
					completion:nil];
	[self showRecordModeHint];
}

/// A tap that changed nothing a person could read would look like a dead button.
- (void)showRecordModeHint {
	UILabel *hint = [[UILabel alloc] init];
	hint.text = self.videoNoteMode ? @"Hold to record video. Tap for voice."
								   : @"Hold to record voice. Tap for video.";
	hint.font = TGFontCaption();
	hint.textColor = [[TGTheme shared] onMediaColour];
	hint.backgroundColor = [[TGTheme shared] mediaOverlayColour];
	hint.textAlignment = NSTextAlignmentCenter;
	hint.layer.cornerRadius = TGMetricCornerMedium;
	CGFloat width = [hint.text sizeWithFont:hint.font].width + TGDoubled(TGMetricPadLarge);
	CGRect bar = self.inputBar.frame;
	hint.frame = CGRectMake(bar.size.width - width - TGMetricPad,
			CGRectGetMinY(bar) - TGMetricTextFieldH, width, TGMetricButtonSmallH);
	hint.alpha = TGAlphaTransparent;
	[self.view addSubview:hint];
	[UIView animateWithDuration:TGAnimationDurationFast animations:^{
		hint.alpha = TGAlphaOpaque;
	} completion:^(BOOL finished){
		[UIView animateWithDuration:TGAnimationDurationSlow delay:kRecordHintSeconds options:0 animations:^{
			hint.alpha = TGAlphaTransparent;
		} completion:^(BOOL gone){
			[hint removeFromSuperview];
		}];
	}];
}

/// Telegram waits a beat before it starts writing, and so do we: the touch
/// lands, the clock runs, and only a finger still down kRecordToggleTapSeconds
/// later becomes a recording. A tap never touches the recorder at all.
- (void)recordTouchDown:(UIButton *)btn withEvent:(UIEvent *)event {
	self.recordBeganAt = [NSDate date];
	sIsCancelled = NO;
	sIsLocked = NO;
	sDragDeltaX = 0;
	UITouch *touch = [[event allTouches] anyObject];
	if (touch) {
		sTouchStart = [touch locationInView:self.view];
	} else {
		sTouchStart = CGPointMake(self.view.bounds.size.width - TGMetricVoiceDragDeadzone, CGRectGetMidY(self.inputBar.frame));
	}
	// The recorder waits for Telegram's beat; the composer does not. Making
	// the strip and sweeping any open keyboard away is instant, so the hold
	// reads from the first hundredth of it.
	[self.input resignFirstResponder];
	if (self.stickerPanel && !self.stickerPanel.hidden)
		[self hideStickerPanel];
	[self showRecordPanel];

	// The block-taking timer name is iOS 10+, which this app is older than:
	// the selector form is the one the device has, and a one-shot timer
	// invalidates itself, so its hold on self lasts the beat and no longer.
	[self.recordStartPendingTimer invalidate];
	self.recordStartPendingTimer = [NSTimer timerWithTimeInterval:kRecordToggleTapSeconds
			target:self
			selector:@selector(recordStartPendingFired:)
			userInfo:nil
			repeats:NO];
	[[NSRunLoop currentRunLoop] addTimer:self.recordStartPendingTimer
			forMode:NSRunLoopCommonModes];
}

- (void)recordStartPendingFired:(NSTimer *)timer {
	if (timer != self.recordStartPendingTimer)
		return;
	self.recordStartPendingTimer = nil;
	if (sIsCancelled)
		return;   // the touch was taken away while the beat ran
	self.table.scrollEnabled = NO;
	[self recordStart];
}

- (void)recordTouchUp:(UIButton *)btn withEvent:(UIEvent *)event {
	if (self.videoNoteOverlayActive)
		return;
	self.table.scrollEnabled = YES;
	[self invalidatePendingRecordStart];
	if (sIsLocked || sIsCancelled)
		return;
	if (sSendInFlight)
		return;

	NSTimeInterval held = self.recordBeganAt
			? -[self.recordBeganAt timeIntervalSinceNow] : 1.0;
	self.recordBeganAt = nil;

	// A tap, not a hold: the recorder was never given the signal, so the
	// touch is free to mean what Telegram's short tap means - voice note
	// recording and round video recording trade places.
	if (held < kRecordToggleTapSeconds && sDragDeltaX < TGMetricVoiceDragDeadzone
			&& ![[TGVoiceRecorder shared] recording]){
		[self hideRecordPanel];
		[self toggleRecordMode];
		return;
	}

	// Released while dragged towards cancel -> cancel
	if (sDragDeltaX >= TGMetricVoiceDragDeadzone) {
		[self recordCancel];
		return;
	}

	[self recordFinish];
}

- (void)recordTouchCancel {
	self.table.scrollEnabled = YES;
	[self invalidatePendingRecordStart];
	if (sIsLocked) return;
	[self recordCancel];
}

- (void)recordDrag:(UIButton *)btn withEvent:(UIEvent *)event {
	if (self.videoNoteOverlayActive || sIsCancelled) return;
	UITouch *touch = [[event allTouches] anyObject];
	if (!touch) return;
	CGPoint pt = [touch locationInView:self.view];

	if (!sIsLocked) {
		CGFloat deltaX = sTouchStart.x - pt.x;
		CGFloat deltaY = sTouchStart.y - pt.y;
		sDragDeltaX = deltaX;

		// A long slide left while the recorder is still waiting is a cancel
		// of the intent.
		if (deltaX >= TGMetricVoiceSlideCancelDistance
				&& ![[TGVoiceRecorder shared] recording]){
			[self invalidatePendingRecordStart];
			return;
		}

		// 1. Slide UP into the rice grain to lock
		if (deltaY >= TGMetricVoiceLockDistance || pt.y <= CGRectGetMinY(self.inputBar.frame) - TGMetricVoiceLockMargin) {
			if ([self recorderIsRecording])
				[self lockRecording];
			return;
		} else if (deltaY > TGMetricZero && self.recordLockView) {
			CGFloat shift = -MIN(deltaY * TGDampingVoiceLock, TGMetricVoiceLockMaxShift);
			self.recordLockView.transform = CGAffineTransformMakeTranslation(0, shift);
		}

		// 2. Slide LEFT to cancel
		if (deltaX >= TGMetricVoiceSlideCancelDistance) {
			sIsCancelled = YES;
			[self recordCancel];
			return;
		} else if (deltaX > TGMetricZero) {
			CGFloat shift = MIN(deltaX * TGDampingVoiceCancel, TGMetricVoiceSlideMaxShift);
			self.recordCancelSlideLabel.transform = CGAffineTransformMakeTranslation(-shift, 0);
			self.recordCancelSlideLabel.alpha = MAX(TGAlphaVoiceCancelMin, TGAlphaOpaque - (deltaX / TGMetricVoiceSlideCancelDistance));
		} else {
			self.recordCancelSlideLabel.transform = CGAffineTransformIdentity;
			self.recordCancelSlideLabel.alpha = TGAlphaOpaque;
		}
	}
}

- (void)recordStart {
	if (self.videoNoteMode){
		NSLog(@"TGVideoNote: recordStart video mode");
		if (![[TGVideoNoteRecorder shared] start]){
			[self hideRecordPanel];
			[self showPlaybackFailure];
			return;
		}
		self.inputBar.hidden = YES;
		self.recordPanel.hidden = YES;
		// The overlay covers the navigation bar too, so the backdrop has to
		// hold it: a shot of the chat alone came out stretched to fit.
		UIView *shown = (self.tabBarController ?: self.navigationController ?: self).view;
		CGRect covered = [shown convertRect:[UIScreen mainScreen].applicationFrame fromView:nil];
		UIGraphicsBeginImageContextWithOptions(covered.size, YES, 0.0f);
		CGContextTranslateCTM(UIGraphicsGetCurrentContext(), -covered.origin.x, -covered.origin.y);
		[shown.layer renderInContext:UIGraphicsGetCurrentContext()];
		UIImage *background = UIGraphicsGetImageFromCurrentImageContext();
		UIGraphicsEndImageContext();
		self.videoNoteOverlayActive = YES;
		self.inputBar.hidden = YES;
		self.recordPanel.hidden = YES;
		NSLog(@"TGVideoNote: presenting overlay");
		TGVideoNoteViewController *recorder = [[TGVideoNoteViewController alloc]
				initWithChatId:self.chatId threadId:self.threadId background:background];
		__weak typeof(self) weakSelf = self;
		recorder.onDismiss = ^{
			weakSelf.videoNoteOverlayActive = NO;
			weakSelf.inputBar.hidden = NO;
			// The hold that led here left the voice strip, the lock and the "1"
			// behind the overlay; the next voice note needs them back in order.
			[weakSelf hideRecordPanel];
			weakSelf.recordPanel.hidden = NO;
			weakSelf.table.scrollEnabled = YES;
			// Not from here: this block belongs to the recorder being released.
			dispatch_async(dispatch_get_main_queue(), ^{
				weakSelf.videoNoteOverlay = nil;
			});
		};
		// Over the whole app, tab bar included: this is a part of the chat, not
		// a place of its own, and a child added to a navigation controller
		// would land in its stack.
		UIView *hostView = (self.tabBarController ?: self.navigationController ?: self).view;
		// Under the status bar, whatever the host's own view does about it.
		recorder.overlayFrame = covered;
		[hostView addSubview:recorder.view];
		recorder.view.autoresizingMask = UIViewAutoresizingFlexibleWidth |
				UIViewAutoresizingFlexibleHeight;
		self.videoNoteOverlay = recorder;
		return;
	}
	if (![[TGVoiceRecorder shared] start]){
		[self hideRecordPanel];
		[self showPlaybackFailure];
		return;
	}
	if (!self.recordPanel.superview)
		[self showRecordPanel];   // the beat fired late; the strip is already up
	self.recordTimer = [NSTimer timerWithTimeInterval:0.1
											   target:self
											 selector:@selector(recordTick)
											 userInfo:nil
											  repeats:YES];
	[[NSRunLoop currentRunLoop] addTimer:self.recordTimer forMode:NSRunLoopCommonModes];
}

- (void)recordTick {
	BOOL paused = [[TGVoiceRecorder shared] paused];
	NSTimeInterval d = self.videoNoteMode
			? [TGVideoNoteRecorder shared].duration
			: [TGVoiceRecorder shared].duration;
	[self.recordPanel showSeconds:d paused:paused];
	if (((NSInteger)(d * 10)) % 10 < 1)
		NSLog(@"TGVoiceRecorder: clock %.1f s (recording=%d paused=%d)",
				d, [[TGVoiceRecorder shared] recording], paused);

	if (!sIsLocked && !paused) {
		UIView *ring = [self.recordPanel viewWithTag:0x81C1];
		if (ring) {
			CGFloat pulse = TGAlphaOpaque + TGAnimationPulseAmplitude * fabsf(sinf((float)d * (float)M_PI));
			ring.transform = CGAffineTransformMakeScale(pulse, pulse);
		}
	}
}

- (void)recordFinish {
	// The touch-up path and the send disc can race; the first one in sends,
	// the second finds the recorder already closed and does nothing.
	if (sSendInFlight)
		return;
	sSendInFlight = YES;
	self.table.scrollEnabled = YES;
	[self.recordTimer invalidate];
	self.recordTimer = nil;
	[self hideRecordPanel];

	BOOL video = self.videoNoteMode;
	__weak typeof(self) weakSelf = self;
	void (^done)(NSString *, NSTimeInterval) = ^(NSString *path, NSTimeInterval seconds){
		TGChatViewController *me = weakSelf;
		if (!me || !path || seconds < 0.5)
			return;   // a stray tap is not a message (me == nil after the send)
		[me clearComposeState];
		if (video)
			[[TGClient shared] sendVideoNoteAtPath:path
										  duration:(NSInteger)ceil(seconds)
											length:[TGVideoNoteRecorder shared].noteSide
											toChat:me.chatId
											thread:me.threadId
										  viewOnce:me.recordOnce];
		else
			[[TGClient shared] sendVoiceAtPath:path
									  duration:(NSInteger)seconds
										toChat:me.chatId
										thread:me.threadId
									  viewOnce:me.recordOnce];
	};
	if (video)
		[[TGVideoNoteRecorder shared] stopWithCompletion:done];
	else
		[[TGVoiceRecorder shared] stopWithCompletion:done];
	sSendInFlight = NO;
}

/// The one-time choice from above the record lock acts on what is being
/// recorded right now: view once is what Telegram sends when "1" is picked,
/// a messageTelegram keeps only until the other side opened it - not a
/// countdown timer of its own.
- (void)toggleRecordOnce {
	self.recordOnce = !self.recordOnce;
	[TGRecordBar setOnce:self.recordOnce onButton:self.recordOnceButton];
}

/// The pause disc beside send. Both halves the pause has: the first tap stops
/// the encoder and the clock, the second carries on where it stopped - one
/// note comes out of it either way.
- (void)recordPauseToggled {
	TGVoiceRecorder *recorder = [TGVoiceRecorder shared];
	if (!recorder.recording)
		return;
	if (recorder.paused){
		[recorder resume];
		[self.recordPauseButton setImage:[TGIcons pause] forState:UIControlStateNormal];
	} else {
		[recorder pause];
		[self.recordPauseButton setImage:[TGIcons play] forState:UIControlStateNormal];
	}
}

- (void)recordCancel {
	self.table.scrollEnabled = YES;
	[self invalidatePendingRecordStart];
	if (![self recorderIsRecording]){
		// Nothing was ever committed to disk - the touch went away before
		// the recorder did.
		return;
	}
	sIsCancelled = YES;
	[self.recordTimer invalidate];
	self.recordTimer = nil;
	[self hideRecordPanel];
	if (self.videoNoteMode)
		[[TGVideoNoteRecorder shared] cancel];
	else
		[[TGVoiceRecorder shared] cancel];
	[self clearComposeState];
}

- (BOOL)recorderIsRecording {
	return [[TGVoiceRecorder shared] recording]
			|| [[TGVideoNoteRecorder shared] recording];
}

- (void)invalidatePendingRecordStart {
	[self.recordStartPendingTimer invalidate];
	self.recordStartPendingTimer = nil;
}

#pragma mark - video notes

/// Plays a round note over the circle it belongs to, clipped to the same shape.
/// MPMoviePlayerController is the only decoder iOS 7 offers, but it does not
/// have to own the screen: its view goes in a mask of our own.
- (void)playVideoNoteAtPath:(NSString *)path row:(NSInteger)row {
	[self stopVideoNote];

	if (row >= 0 && row < (NSInteger)self.messages.count){
		NSDictionary *played = self.messages[row];
		if (![played[@"outgoing"] boolValue])
			[[TGClient shared] openContentOfMessage:[played[@"id"] longLongValue]
											 inChat:self.chatId];
	}

	CGFloat side = TGMetricRoundVideoSide;
	CGRect inTable = [self.table rectForRowAtIndexPath:
			[NSIndexPath indexPathForRow:row inSection:0]];
	NSDictionary *m = self.messages[row];
	CGFloat x = [m[@"outgoing"] boolValue]
			? (self.table.bounds.size.width - side - TGMetricPad) : TGMetricPad;

	UIView *circle = [[UIView alloc] initWithFrame:
			CGRectMake(x, inTable.origin.y + TGMetricBubbleRowInset, side, side)];
	circle.layer.cornerRadius = TGHalf(side);
	circle.clipsToBounds = YES;
	circle.layer.masksToBounds = YES;
	circle.backgroundColor = [[TGTheme shared] mediaViewerBackdropColour];
	circle.tag = 0xF119;

	[[AVAudioSession sharedInstance] setCategory:AVAudioSessionCategoryPlayback error:nil];
	[[AVAudioSession sharedInstance] setActive:YES error:nil];

	MPMoviePlayerController *player = [[MPMoviePlayerController alloc]
			initWithContentURL:[NSURL fileURLWithPath:path]];
	player.controlStyle = MPMovieControlStyleNone;
	player.scalingMode = MPMovieScalingModeAspectFill;
	player.view.frame = circle.bounds;
	player.view.clipsToBounds = YES;
	player.view.userInteractionEnabled = NO;
	player.shouldAutoplay = YES;
	[circle addSubview:player.view];

	// Add progress ring
	self.videoNoteProgressLayer = [CAShapeLayer layer];
	self.videoNoteProgressLayer.frame = circle.bounds;
	self.videoNoteProgressLayer.path = [UIBezierPath bezierPathWithArcCenter:CGPointMake(TGHalf(side), TGHalf(side))
																	  radius:TGHalf(side) - TGMetricPadTiny
																  startAngle:-M_PI_2
																	endAngle:M_PI_2 * 3
																   clockwise:YES].CGPath;
	self.videoNoteProgressLayer.strokeColor = [[TGTheme shared] accentColour].CGColor;
	self.videoNoteProgressLayer.fillColor = [UIColor clearColor].CGColor;
	self.videoNoteProgressLayer.lineWidth = TGMetricPadSmall;
	self.videoNoteProgressLayer.strokeEnd = 0.0;
	[circle.layer addSublayer:self.videoNoteProgressLayer];

	[self.table addSubview:circle];
	self.videoNotePlayer = player;

	[circle addGestureRecognizer:[[UITapGestureRecognizer alloc]
			initWithTarget:self action:@selector(togglePlayback)]];

	[[NSNotificationCenter defaultCenter] addObserver:self
			selector:@selector(videoNoteLoopNotification:)
				name:MPMoviePlayerPlaybackDidFinishNotification
			  object:player];
	[player prepareToPlay];
	[player play];

	self.playingMessageId = [m[@"id"] longLongValue];
	[self showPlayerBar];
	self.playerLabel.text = @"Video message";
	[self startPlaybackTimer];
	[self.table reloadData];
}

- (void)videoNoteLoopNotification:(NSNotification *)note {
	[self stopVideoNote];
}

- (void)stopVideoNote {
	if (!self.videoNotePlayer)
		return;
	[[NSNotificationCenter defaultCenter] removeObserver:self
			name:MPMoviePlayerPlaybackDidFinishNotification
		  object:self.videoNotePlayer];
	[self.videoNotePlayer stop];
	[[self.table viewWithTag:0xF119] removeFromSuperview];
	[[self.view viewWithTag:0xF119] removeFromSuperview];
	self.videoNotePlayer = nil;
	self.videoNoteProgressLayer = nil;

	[self.playbackTimer invalidate];
	self.playbackTimer = nil;
	if (!self.voicePlayer) {
		self.playingMessageId = 0;
		[self hidePlayerBar];
	}
	[self.table reloadData];
}

#pragma mark - playback

/// Their player strip: an arrow, what is playing, a way out, and a line along
/// the bottom that fills as it goes. It sits under the header, which is where
/// a client puts it so the chat stays readable while something plays.
- (void)showPlayerBar {
	CGRect b = self.view.bounds;
	TGTheme *theme = [TGTheme shared];
	if (!self.playerBar){
		self.playerBar = [[UIView alloc] initWithFrame:
				CGRectMake(0, 0, b.size.width, kPlayerBarHeight)];
		self.playerBar.backgroundColor = [theme listBackgroundColour];
		self.playerBar.autoresizingMask = UIViewAutoresizingFlexibleWidth;

		// Album art where their player has it. A voice note has none, and
		// the view simply stays hidden for one.
		self.playerArtwork = [[UIImageView alloc] initWithFrame:
				CGRectMake(kPlayerArtX, TGCenteredOrigin(kPlayerBarHeight, kPlayerArt) - kPlayerArtLift,
						   kPlayerArt, kPlayerArt)];
		self.playerArtwork.contentMode = UIViewContentModeScaleAspectFill;
		self.playerArtwork.clipsToBounds = YES;
		self.playerArtwork.layer.cornerRadius = TGMetricCornerSmall;
		self.playerArtwork.hidden = YES;
		self.playerArtwork.userInteractionEnabled = YES;
		[self.playerArtwork addGestureRecognizer:[[UITapGestureRecognizer alloc]
				initWithTarget:self action:@selector(openFullPlayerTapped)]];
		[self.playerBar addSubview:self.playerArtwork];

		self.playerToggle = [UIButton buttonWithType:UIButtonTypeCustom];
		self.playerToggle.tintColor = [theme accentColour];
		[self.playerToggle addTarget:self action:@selector(togglePlayback)
					forControlEvents:UIControlEventTouchUpInside];
		[self.playerBar addSubview:self.playerToggle];

		// Two lines, not one: "performer - title" on a 320pt screen truncated
		// both halves and told you neither.
		self.playerLabel = [[UILabel alloc] init];
		self.playerLabel.font = TGFontCaptionStrong();
		self.playerLabel.backgroundColor = [UIColor clearColor];
		self.playerLabel.autoresizingMask = UIViewAutoresizingFlexibleWidth;
		self.playerLabel.userInteractionEnabled = YES;
		[self.playerLabel addGestureRecognizer:[[UITapGestureRecognizer alloc]
				initWithTarget:self action:@selector(openFullPlayerTapped)]];
		[self.playerBar addSubview:self.playerLabel];

		self.playerDetail = [[UILabel alloc] init];
		self.playerDetail.font = TGFontMeta();
		self.playerDetail.textColor = [theme secondaryTextColour];
		self.playerDetail.backgroundColor = [UIColor clearColor];
		self.playerDetail.autoresizingMask = UIViewAutoresizingFlexibleWidth;
		[self.playerBar addSubview:self.playerDetail];

		// Elapsed over total, which the strip never said at all.
		self.playerClock = [[UILabel alloc] init];
		self.playerClock.font = TGFontMicro();
		self.playerClock.textColor = [theme secondaryTextColour];
		self.playerClock.textAlignment = NSTextAlignmentRight;
		self.playerClock.backgroundColor = [UIColor clearColor];
		self.playerClock.autoresizingMask = UIViewAutoresizingFlexibleLeftMargin;
		[self.playerBar addSubview:self.playerClock];

		self.musicPrevious = [UIButton buttonWithType:UIButtonTypeCustom];
		self.musicPrevious.tintColor = [theme accentColour];
		self.musicPrevious.autoresizingMask = UIViewAutoresizingFlexibleLeftMargin;
		[self.musicPrevious addTarget:self action:@selector(musicPreviousTapped)
					 forControlEvents:UIControlEventTouchUpInside];
		[self.playerBar addSubview:self.musicPrevious];

		self.musicNext = [UIButton buttonWithType:UIButtonTypeCustom];
		self.musicNext.tintColor = [theme accentColour];
		self.musicNext.autoresizingMask = UIViewAutoresizingFlexibleLeftMargin;
		[self.musicNext addTarget:self action:@selector(musicNextTapped)
				 forControlEvents:UIControlEventTouchUpInside];
		[self.playerBar addSubview:self.musicNext];

		self.playerSpeed = [UIButton buttonWithType:UIButtonTypeCustom];
		self.playerSpeed.titleLabel.font = TGFontCaption();
		self.playerSpeed.autoresizingMask = UIViewAutoresizingFlexibleLeftMargin;
		[self.playerSpeed setTitle:@"1x" forState:UIControlStateNormal];
		[self.playerSpeed setTitleColor:[theme accentColour]
							   forState:UIControlStateNormal];
		[self.playerSpeed addTarget:self action:@selector(cyclePlaybackSpeed)
				   forControlEvents:UIControlEventTouchUpInside];
		[self.playerBar addSubview:self.playerSpeed];

		self.playerClose = [UIButton buttonWithType:UIButtonTypeCustom];
		[self.playerClose setImage:[TGIcons glyphNamed:@"close"
											colour:[theme secondaryTextColour]
											  side:kRecordLockArrow]
						  forState:UIControlStateNormal];
		self.playerClose.autoresizingMask = UIViewAutoresizingFlexibleLeftMargin;
		[self.playerClose addTarget:self action:@selector(stopPlayback)
				   forControlEvents:UIControlEventTouchUpInside];
		[self.playerClose setTitleColor:[theme secondaryTextColour]
							   forState:UIControlStateNormal];
		[self.playerBar addSubview:self.playerClose];

		UIView *track = [[UIView alloc] initWithFrame:
				CGRectMake(0, kPlayerBarHeight - kPlayerProgressH, b.size.width, kPlayerProgressH)];
		track.backgroundColor = [theme separatorColour];
		track.autoresizingMask = UIViewAutoresizingFlexibleWidth;
		[self.playerBar addSubview:track];

		self.playerProgress = [[UIView alloc] initWithFrame:
				CGRectMake(0, kPlayerBarHeight - kPlayerProgressH, 0, kPlayerProgressH)];
		self.playerProgress.backgroundColor = [theme accentColour];
		[self.playerBar addSubview:self.playerProgress];

		// A 2pt line is nothing to aim at, so the whole strip is the target
		// and the thumb says where the finger landed.
		self.playerThumb = [[UIView alloc] initWithFrame:
				CGRectMake(-TGMetricPadSmall, kPlayerBarHeight - TGMetricPadSmall - kPlayerArtLift,
						   TGMetricPlayerThumbSide, TGMetricPlayerThumbSide)];
		self.playerThumb.backgroundColor = [theme accentColour];
		self.playerThumb.layer.cornerRadius = TGHalf(TGMetricPlayerThumbSide);
		[self.playerBar addSubview:self.playerThumb];

		[self.playerBar addGestureRecognizer:[[UITapGestureRecognizer alloc]
				initWithTarget:self action:@selector(playerBarScrubbed:)]];
		[self.playerBar addGestureRecognizer:[[UIPanGestureRecognizer alloc]
				initWithTarget:self action:@selector(playerBarScrubbed:)]];

		[self layoutPlayerBarForMusic:NO];
	}

	[self layoutPlayerBarForMusic:NO];
	self.playerLabel.textColor = [[TGTheme shared] primaryTextColour];
	self.playerLabel.text = @"Voice message";
	self.playerDetail.text = @"";
	self.playerClock.text = @"";
	self.playerArtwork.image = nil;
	self.playerProgress.frame = CGRectMake(0, kPlayerBarHeight - kPlayerProgressH,
			0, kPlayerProgressH);
	[self.playerToggle setImage:[TGIcons pause] forState:UIControlStateNormal];
	// A video note has no rate to change.
	self.playerSpeed.hidden = (self.voicePlayer == nil);
	[self.playerSpeed setTitle:@"1x" forState:UIControlStateNormal];
	[self.view addSubview:self.playerBar];

	// Push the messages down so the strip does not cover the newest one.
	UIEdgeInsets insets = self.table.contentInset;
	insets.top += kPlayerBarHeight;
	self.table.contentInset = insets;
	self.table.scrollIndicatorInsets = insets;
}

/// Two arrangements of the same strip. A voice note has no queue and no
/// cover, so its text starts at the arrow and the corner carries the speed;
/// a track has art, previous and next, and no speed - the corner cannot hold
/// both and the queue is what a track needs.
- (void)layoutPlayerBarForMusic:(BOOL)music {
	CGFloat width = self.playerBar.bounds.size.width;
	CGFloat mid = TGCenteredOrigin(kPlayerBarHeight, kPlayerButton) - kPlayerArtLift;

	self.playerArtwork.hidden = !music;
	CGFloat textX;
	if (music){
		self.playerToggle.frame = CGRectMake(kPlayerArtX + kPlayerArt + kPlayerArtGap, mid,
				kPlayerButton, kPlayerButton);
		textX = kPlayerArtX + kPlayerArt + kPlayerArtGap + kPlayerButton + kPlayerButtonGap;
	} else {
		self.playerToggle.frame = CGRectMake(kPlayerArtX, mid, kPlayerButton, kPlayerButton);
		textX = kPlayerArtX + kPlayerButton + kPlayerArtGap;
	}

	// Right to left: close, then the queue or the speed, then the clock.
	self.playerClose.frame = CGRectMake(width - kPlayerCloseW - kPlayerButtonGap, mid,
			kPlayerCloseW, kPlayerButton);
	CGFloat rightEdge = width - kPlayerRightEdge;

	self.musicPrevious.hidden = !music;
	self.musicNext.hidden = !music;
	self.playerSpeed.hidden = music;
	if (music){
		self.musicNext.frame = CGRectMake(rightEdge - kPlayerCloseW, mid,
				kPlayerCloseW, kPlayerButton);
		self.musicPrevious.frame = CGRectMake(rightEdge - TGDoubled(kPlayerCloseW) - TGMetricPadTiny,
				mid, kPlayerCloseW, kPlayerButton);
		rightEdge -= TGDoubled(kPlayerCloseW) + TGMetricPadSmall;
	} else {
		self.playerSpeed.frame = CGRectMake(rightEdge - kPlayerSpeedW, mid,
				kPlayerSpeedW, kPlayerButton);
		rightEdge -= kPlayerSpeedW + TGMetricPadTiny;
	}

	CGFloat clockW = kPlayerClockW;
	self.playerClock.frame = CGRectMake(rightEdge - clockW, mid + kPlayerClockDrop,
			clockW, TGMetricLineMicro);
	CGFloat textW = MAX(kPlayerTextMin, rightEdge - clockW - textX - TGMetricPadSmall);

	self.playerLabel.frame = CGRectMake(textX, mid + kPlayerArtLift, textW, kPlayerTitleLine);
	self.playerDetail.frame = CGRectMake(textX, mid + kPlayerTitleLine, textW,
			kPlayerDetailLine);
}

/// "1:07 / 3:42", or just the elapsed time while the length is unknown.
static NSString *TGClockText(NSTimeInterval position, NSTimeInterval duration) {
	NSInteger at = (NSInteger)MAX(0.0, position);
	NSString *elapsed = [NSString stringWithFormat:@"%ld:%02ld",
			(long)(at / 60), (long)(at % 60)];
	if (duration <= 0)
		return elapsed;
	NSInteger total = (NSInteger)duration;
	return [NSString stringWithFormat:@"%@ / %ld:%02ld", elapsed,
			(long)(total / 60), (long)(total % 60)];
}

- (void)hidePlayerBar {
	if (!self.playerBar.superview)
		return;
	[self.playerBar removeFromSuperview];
	UIEdgeInsets insets = self.table.contentInset;
	insets.top -= kPlayerBarHeight;
	self.table.contentInset = insets;
	self.table.scrollIndicatorInsets = insets;
}

/// Five ticks a second is enough for the eye, and a tick now costs one layer
/// frame per playing row - the waveform itself is not redrawn (TGBubbleCell
/// -setWavePlayed:).
- (void)startPlaybackTimer {
	[self.playbackTimer invalidate];
	self.playbackTimer = [NSTimer scheduledTimerWithTimeInterval:0.2
														 target:self
													   selector:@selector(playbackTick)
													   userInfo:nil
														repeats:YES];
}

- (CGFloat)playedFraction {
    TGMusicPlayer *music = [TGMusicPlayer shared];
    if (music.current && music.duration > 0)
        return (CGFloat)(music.position / music.duration);
    if (self.voicePlayer && self.voicePlayer.duration > 0)
        return (CGFloat)(self.voicePlayer.currentTime / self.voicePlayer.duration);
    if (self.videoNotePlayer && self.videoNotePlayer.duration > 0)
        return (CGFloat)(self.videoNotePlayer.currentPlaybackTime / self.videoNotePlayer.duration);
    return 0;
}

- (void)playbackTick {
	if (self.videoNotePlayer && self.videoNotePlayer.duration > 0) {
		if (self.videoNotePlayer.currentPlaybackTime >= self.videoNotePlayer.duration - 0.05) {
			[self stopVideoNote];
			return;
		}
	}
	CGFloat played = [self playedFraction];
	CGFloat barWidth = self.playerBar.bounds.size.width;
	self.playerProgress.frame = CGRectMake(0, kPlayerBarHeight - kPlayerProgressH,
			barWidth * played, kPlayerProgressH);
	self.playerThumb.center = CGPointMake(barWidth * played,
										  kPlayerBarHeight - kPlayerArtLift);

	TGMusicPlayer *music = [TGMusicPlayer shared];
	if (music.current)
		self.playerClock.text = TGClockText(music.position, music.duration);
	else if (self.voicePlayer)
		self.playerClock.text = TGClockText(self.voicePlayer.currentTime,
											self.voicePlayer.duration);
            
    if (self.videoNoteProgressLayer) {
        self.videoNoteProgressLayer.strokeEnd = played;
    }

	// Only the row being played changes, and reloading the whole table five
	// times a second on this hardware is visible as a stutter.
	for (UITableViewCell *cell in self.table.visibleCells){
		if (![cell isKindOfClass:TGBubbleCell.class])
			continue;
		TGBubbleCell *bubble = (TGBubbleCell *)cell;
		if (bubble.voiceMessageId != self.playingMessageId || bubble.wave.hidden)
			continue;
		[bubble setWavePlayed:played];
	}
}

/// The music strip: the same place as the voice strip, but it names the track
/// and carries the two buttons that only mean something with a queue behind
/// them. Their player puts previous and next either side of play.
- (void)showMusicBar {
	[self showPlayerBar];
	[self layoutPlayerBarForMusic:YES];
	[self.musicPrevious setImage:[TGIcons previousTrack] forState:UIControlStateNormal];
	[self.musicNext setImage:[TGIcons nextTrack] forState:UIControlStateNormal];
	[self musicChanged];
	[self startPlaybackTimer];
}

- (void)musicPreviousTapped { [[TGMusicPlayer shared] previous]; }
- (void)musicNextTapped     { [[TGMusicPlayer shared] next]; }

- (void)openFullPlayerTapped {
	if ([TGMusicPlayer shared].current) {
		[TGPlayerModalViewController presentFromViewController:self animated:YES];
	}
}

/// Called on the notification as well as directly, so the strip follows a
/// track change that came from the lock screen rather than from this screen.
- (void)musicChanged {
	TGMusicPlayer *music = [TGMusicPlayer shared];
	if (!music.current){
		if (self.musicPrevious && !self.musicPrevious.hidden)
			[self stopPlayback];
		return;
	}

	NSString *title = [music.current[@"audioTitle"] length]
			? music.current[@"audioTitle"]
			: (music.current[@"docName"] ?: @"Audio");
	self.playerLabel.textColor = [[TGTheme shared] primaryTextColour];
	self.playerLabel.text = title;
	self.playerDetail.text = [music.current[@"audioPerformer"] length]
			? music.current[@"audioPerformer"] : @"";
	self.playerClock.text = TGClockText(music.position, music.duration);

	// The cover is the one the bubble already fetched, so switching tracks
	// shows it at once rather than after a second download.
	self.playerArtwork.image = [self artworkForTrack:music.current];
	self.playerArtwork.backgroundColor = self.playerArtwork.image
			? [UIColor clearColor] : [[TGTheme shared] fileTileColour];

	[self.playerToggle setImage:(music.playing ? [TGIcons pause] : [TGIcons play])
					   forState:UIControlStateNormal];
	[self.table reloadData];
}

- (void)waveformScrubbed:(UIGestureRecognizer *)gesture {
	UIView *wave = gesture.view;
	TGBubbleCell *cell = nil;
	for (UIView *view = wave; view; view = view.superview)
		if ([view isKindOfClass:TGBubbleCell.class]){
			cell = (TGBubbleCell *)view;
			break;
		}
	if (!cell)
		return;

	NSIndexPath *ip = [self.table indexPathForCell:cell];
	if (!ip || ip.row >= (NSInteger)self.messages.count)
		return;
	NSDictionary *m = self.messages[ip.row];

	if (!self.voicePlayer || cell.voiceMessageId != self.playingMessageId){
		if (gesture.state == UIGestureRecognizerStateEnded){
			[self playVoiceNoteForMessage:m atRow:ip.row];
		}
		return;
	}

	CGFloat x = [gesture locationInView:wave].x;
	CGFloat fraction = MIN(MAX(x / MAX(TGMetricScaleFull, wave.bounds.size.width), TGAlphaTransparent), TGAlphaOpaque);
	self.voicePlayer.currentTime = fraction * self.voicePlayer.duration;
	[self playbackTick];
}

- (void)voiceDiscTapped:(UITapGestureRecognizer *)gesture {
	UIView *disc = gesture.view;
	TGBubbleCell *cell = nil;
	for (UIView *view = disc; view; view = view.superview)
		if ([view isKindOfClass:TGBubbleCell.class]){
			cell = (TGBubbleCell *)view;
			break;
		}
	if (!cell)
		return;

	NSIndexPath *ip = [self.table indexPathForCell:cell];
	if (!ip || ip.row >= (NSInteger)self.messages.count)
		return;
	NSDictionary *m = self.messages[ip.row];
	[self playVoiceNoteForMessage:m atRow:ip.row];
}

- (void)videoNoteDiscTapped:(UITapGestureRecognizer *)gesture {
	UIView *disc = gesture.view;
	TGBubbleCell *cell = nil;
	for (UIView *view = disc; view; view = view.superview)
		if ([view isKindOfClass:TGBubbleCell.class]){
			cell = (TGBubbleCell *)view;
			break;
		}
	if (!cell)
		return;

	NSIndexPath *ip = [self.table indexPathForCell:cell];
	if (!ip || ip.row >= (NSInteger)self.messages.count)
		return;
	[self tableView:self.table didSelectRowAtIndexPath:ip];
}

/// 1x, 1.5x, 2x - the three their player offers. AVAudioPlayer will not change
/// rate unless it was told to expect it before playing, which is why
/// enableRate is set when the player is built rather than here.
- (void)cyclePlaybackSpeed {
	if (!self.voicePlayer)
		return;
	float rate = self.voicePlayer.rate;
	float next = (rate < TGPlaybackSpeedThresholdFast) ? TGPlaybackSpeedFast : ((rate < TGPlaybackSpeedThresholdDouble) ? TGPlaybackSpeedDouble : TGPlaybackSpeedNormal);
	self.voicePlayer.rate = next;
	[self.playerSpeed setTitle:(next == TGPlaybackSpeedNormal ? @"1x" :
			(next == TGPlaybackSpeedFast ? @"1.5x" : @"2x")) forState:UIControlStateNormal];
}

/// Tapping anywhere along the strip's line jumps there.
- (void)playerBarScrubbed:(UIGestureRecognizer *)gesture {
	CGFloat width = self.playerBar.bounds.size.width;
	CGFloat fraction = MIN(MAX([gesture locationInView:self.playerBar].x /
			MAX(TGMetricScaleFull, width), TGAlphaTransparent), TGAlphaOpaque);
	if ([TGMusicPlayer shared].current)
		[[TGMusicPlayer shared] seekToFraction:fraction];
	else if (self.voicePlayer)
		self.voicePlayer.currentTime = fraction * self.voicePlayer.duration;
	else if (self.videoNotePlayer && self.videoNotePlayer.duration > 0)
		self.videoNotePlayer.currentPlaybackTime = fraction * self.videoNotePlayer.duration;
	[self playbackTick];
}

- (void)togglePlayback {
	if ([TGMusicPlayer shared].current){
		[[TGMusicPlayer shared] togglePlayPause];
		return;
	}
	if (self.voicePlayer) {
        if (self.voicePlayer.playing){
            [self.voicePlayer pause];
            [self.playbackTimer invalidate];
            self.playbackTimer = nil;
            [self.playerToggle setImage:[TGIcons play] forState:UIControlStateNormal];
        } else {
            [self.voicePlayer play];
            [self startPlaybackTimer];
            [self.playerToggle setImage:[TGIcons pause] forState:UIControlStateNormal];
        }
        [self.table reloadData];
    } else if (self.videoNotePlayer) {
        if (self.videoNotePlayer.playbackState == MPMoviePlaybackStatePlaying) {
            [self.videoNotePlayer pause];
            [self.playbackTimer invalidate];
            self.playbackTimer = nil;
            [self.playerToggle setImage:[TGIcons play] forState:UIControlStateNormal];
        } else {
            [self.videoNotePlayer play];
            [self startPlaybackTimer];
            [self.playerToggle setImage:[TGIcons pause] forState:UIControlStateNormal];
        }
    }
}

- (void)stopPlayback {
	if ([TGMusicPlayer shared].current)
		[[TGMusicPlayer shared] stop];
	[self.voicePlayer stop];
	self.voicePlayer = nil;
	if (self.videoNotePlayer)
		[self stopVideoNote];
	[self.playbackTimer invalidate];
	self.playbackTimer = nil;
	self.playingMessageId = 0;
	[self hidePlayerBar];
	[self.table reloadData];
}

- (void)audioPlayerDidFinishPlaying:(id)player successfully:(BOOL)flag {
	int64_t currentId = self.playingMessageId;
	[self stopPlayback];

	if (!flag || currentId == 0)
		return;

	// Automatically play the next voice note in the chat (in chronological order: row + 1 ...)
	NSInteger currentRow = NSNotFound;
	for (NSInteger i = 0; i < (NSInteger)self.messages.count; i++) {
		if ([self.messages[i][@"id"] longLongValue] == currentId) {
			currentRow = i;
			break;
		}
	}

	if (currentRow != NSNotFound) {
		for (NSInteger i = currentRow + 1; i < (NSInteger)self.messages.count; i++) {
			NSDictionary *nextMsg = self.messages[i];
			if ([nextMsg[@"type"] isEqualToString:@"voice"] && nextMsg[@"docId"]) {
				[self playVoiceNoteForMessage:nextMsg atRow:i];
				break;
			}
		}
	}
}

- (void)playVoiceNoteForMessage:(NSDictionary *)m atRow:(NSInteger)row {
	NSNumber *docId = m[@"docId"];
	if (![docId isKindOfClass:NSNumber.class])
		return;

	// Telling Telegram it was played is what turns the sender's dot blue, and
	// nothing else does it - reading the chat does not count as listening.
	if (![m[@"outgoing"] boolValue])
		[[TGClient shared] openContentOfMessage:[m[@"id"] longLongValue]
										 inChat:self.chatId];

	// Tapping the one already playing is how you stop it; without this the
	// only way out was to leave the chat.
	if (self.playingMessageId == [m[@"id"] longLongValue] && self.voicePlayer){
		[self togglePlayback];
		return;
	}
	if (self.voicePlayer)
		[self stopPlayback];
	[self beginDownloadHUDForFile:[docId integerValue]];
	__weak typeof(self) weakSelf = self;
	[[TGClient shared] downloadFile:[docId integerValue] priority:32 completion:^(NSString *path){
		dispatch_async(dispatch_get_main_queue(), ^{
			[weakSelf endDownloadHUD];
			TGChatViewController *me = weakSelf;
			if (!me) return;
			NSLog(@"voice: file %@", path.lastPathComponent ?: @"(not downloaded)");
			if (!path){
				[me showPlaybackFailure];
				return;
			}
			NSError *err = nil;
			[[AVAudioSession sharedInstance]
					setCategory:AVAudioSessionCategoryPlayback error:nil];
			[[AVAudioSession sharedInstance] setActive:YES error:nil];
			me.voicePlayer = [[TGStreamingVoicePlayer alloc] initWithPath:path error:&err];
			if (err || !me.voicePlayer){
				NSLog(@"voice playback: %@", err);
				[me showPlaybackFailure];
				return;
			}
			NSLog(@"voice: playing %.1f s (streaming)", me.voicePlayer.duration);
			me.voicePlayer.delegate = (id<TGStreamingVoicePlayerDelegate>)me;
			me.voicePlayer.enableRate = YES;   // for the speed button
			me.playingMessageId = [m[@"id"] longLongValue];
			[me.voicePlayer play];
			[me showPlayerBar];
			[me startPlaybackTimer];
			[me.table reloadData];
		});
	}];
}

@end
