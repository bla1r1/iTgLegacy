#import "TGChatViewControllerInternal.h"
#import "TGVoiceRecorder.h"
#import "TGVoiceDecoder.h"
#import "TGMusicPlayer.h"
#import "TGStyle.h"

static CGPoint sTouchStart;
static CGFloat sDragDeltaX;
static BOOL sIsLocked;
static BOOL sIsCancelled;

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
		self.recordPanel = [[UIView alloc] initWithFrame:bar];
		self.recordPanel.backgroundColor = [theme inputBarColour];
		self.recordPanel.autoresizingMask = UIViewAutoresizingFlexibleWidth |
											UIViewAutoresizingFlexibleTopMargin;

		UIView *hair = [[UIView alloc] initWithFrame:CGRectMake(0, 0, bar.size.width,
				TGMetricBorderWidth)];
		hair.backgroundColor = [theme separatorColour];
		hair.autoresizingMask = UIViewAutoresizingFlexibleWidth;
		[self.recordPanel addSubview:hair];

		self.recordDot = [[UIView alloc] initWithFrame:
				CGRectMake(kRecordDotX, TGCenteredOrigin(kInputHeight, TGMetricRecordDotSide),
						TGMetricRecordDotSide, TGMetricRecordDotSide)];
		self.recordDot.backgroundColor = [theme destructiveColour];
		self.recordDot.layer.cornerRadius = TGHalf(TGMetricRecordDotSide);
		[self.recordPanel addSubview:self.recordDot];

		self.recordClock = [[UILabel alloc] initWithFrame:
				CGRectMake(kRecordClockX, TGCenteredOrigin(kInputHeight, TGMetricLineRow),
						kRecordClockW, TGMetricLineRow)];
		self.recordClock.font = TGFontRow();
		self.recordClock.textColor = [theme primaryTextColour];
		self.recordClock.backgroundColor = [UIColor clearColor];
		[self.recordPanel addSubview:self.recordClock];

		self.recordCancelSlideLabel = [[UILabel alloc] initWithFrame:
				CGRectMake(kRecordSlideX, TGCenteredOrigin(kInputHeight, TGMetricLineRow),
						bar.size.width - kRecordSlideRoom, TGMetricLineRow)];
		self.recordCancelSlideLabel.text = @"‹ Slide to cancel";
		self.recordCancelSlideLabel.font = TGFontBody();
		self.recordCancelSlideLabel.textColor = [theme secondaryTextColour];
		self.recordCancelSlideLabel.backgroundColor = [UIColor clearColor];
		self.recordCancelSlideLabel.autoresizingMask = UIViewAutoresizingFlexibleWidth;
		[self.recordPanel addSubview:self.recordCancelSlideLabel];

		// Cancel text button for locked mode (centered, like TG Desktop / Mobile)
		self.recordCancelButton = [UIButton buttonWithType:UIButtonTypeCustom];
		self.recordCancelButton.frame =
				CGRectMake(TGCenteredOrigin(bar.size.width, kRecordCancelW),
						TGCenteredOrigin(kInputHeight, kRecordCancelH),
						kRecordCancelW, kRecordCancelH);
		[self.recordCancelButton setTitle:@"Cancel" forState:UIControlStateNormal];
		[self.recordCancelButton setTitleColor:[theme accentColour] forState:UIControlStateNormal];
		self.recordCancelButton.titleLabel.font = TGFontRow();
		[self.recordCancelButton addTarget:self action:@selector(recordCancel) forControlEvents:UIControlEventTouchUpInside];
		self.recordCancelButton.hidden = YES;
		[self.recordPanel addSubview:self.recordCancelButton];

		// Circular Send button for locked mode (right side, like TG Desktop / Mobile)
		self.recordSendButton = [UIButton buttonWithType:UIButtonTypeCustom];
		self.recordSendButton.frame = CGRectMake(bar.size.width - TGMetricRow, TGCenteredOrigin(kInputHeight, TGMetricCallControlSide), TGMetricCallControlSide, TGMetricCallControlSide);
		self.recordSendButton.backgroundColor = [theme accentColour];
		self.recordSendButton.layer.cornerRadius = TGHalf(TGMetricCallControlSide);
		self.recordSendButton.layer.masksToBounds = YES;
		[self.recordSendButton setImage:[TGIcons send] forState:UIControlStateNormal];
		self.recordSendButton.tintColor = [UIColor whiteColor];
		self.recordSendButton.imageEdgeInsets = UIEdgeInsetsZero;
		self.recordSendButton.autoresizingMask = UIViewAutoresizingFlexibleLeftMargin;
		[self.recordSendButton addTarget:self action:@selector(recordFinish) forControlEvents:UIControlEventTouchUpInside];
		self.recordSendButton.hidden = YES;
		[self.recordPanel addSubview:self.recordSendButton];

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
		button.image = [TGIcons microphoneOfSide:disc colour:[UIColor whiteColor]];
		button.tag = 0x81C2;
		button.autoresizingMask = UIViewAutoresizingFlexibleLeftMargin;
		[self.recordPanel addSubview:button];
	}

	sIsLocked = NO;
	sIsCancelled = NO;
	sDragDeltaX = 0;
	self.recordCancelButton.hidden = YES;
	self.recordSendButton.hidden = YES;
	self.recordCancelSlideLabel.hidden = NO;
	self.recordCancelSlideLabel.transform = CGAffineTransformIdentity;
	self.recordCancelSlideLabel.alpha = TGAlphaOpaque;
	[self.recordPanel viewWithTag:0x81C1].hidden = NO;
	[self.recordPanel viewWithTag:0x81C2].hidden = NO;
	self.recordDot.frame = CGRectMake(TGMetricPadLarge,
			TGCenteredOrigin(kInputHeight, TGMetricRecordDotSide),
			TGMetricRecordDotSide, TGMetricRecordDotSide);
	self.recordClock.frame = CGRectMake(kRecordClockX,
			TGCenteredOrigin(kInputHeight, TGMetricLineRow), kRecordClockW, TGMetricLineRow);

	self.recordPanel.frame = bar;
	self.recordClock.text = @"0:00,0";
	self.recordDot.alpha = TGAlphaOpaque;
	self.recordPanel.userInteractionEnabled = NO;
	[self.view addSubview:self.recordPanel];

	// The "Rice Grain" lock capsule directly above mic button (Image 2)
	if (!self.recordLockView) {
		CGFloat pillW = TGMetricVoicePillWidth, pillH = TGMetricVoicePillHeight;
		CGFloat pillX = bar.origin.x + bar.size.width - pillW - TGMetricSectionHeaderEmpty;
		CGFloat pillY = bar.origin.y - pillH - TGMetricPadMedium;
		UIView *pill = [[UIView alloc] initWithFrame:CGRectMake(pillX, pillY, pillW, pillH)];
		pill.backgroundColor = [[TGTheme shared] recordLockColour];
		pill.layer.cornerRadius = TGHalf(pillW); // Rounded rice grain capsule
		pill.clipsToBounds = YES;

		UIImageView *lockIcon = [[UIImageView alloc] initWithFrame:
				CGRectMake(TGCenteredOrigin(pillW, kRecordLockGlyph), TGMetricPad,
						kRecordLockGlyph, kRecordLockGlyph)];
		lockIcon.image = [TGIcons lockOfSide:kRecordLockGlyph
									  colour:[UIColor whiteColor]];
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
}

- (void)recordTouchDown:(UIButton *)btn withEvent:(UIEvent *)event {
	sIsCancelled = NO;
	sIsLocked = NO;
	sDragDeltaX = 0;
	UITouch *touch = [[event allTouches] anyObject];
	if (touch) {
		sTouchStart = [touch locationInView:self.view];
	} else {
		sTouchStart = CGPointMake(self.view.bounds.size.width - TGMetricVoiceDragDeadzone, CGRectGetMidY(self.inputBar.frame));
	}
	self.table.scrollEnabled = NO;
	[self recordStart];
}

- (void)recordTouchUp:(UIButton *)btn withEvent:(UIEvent *)event {
	self.table.scrollEnabled = YES;
	if (sIsLocked || sIsCancelled)
		return;

	// Released while dragged towards cancel -> cancel
	if (sDragDeltaX >= TGMetricVoiceDragDeadzone) {
		[self recordCancel];
		return;
	}

	[self recordFinish];
}

- (void)recordTouchCancel {
	self.table.scrollEnabled = YES;
	if (sIsLocked) return;
	[self recordCancel];
}

- (void)recordDrag:(UIButton *)btn withEvent:(UIEvent *)event {
	if (sIsCancelled) return;
	UITouch *touch = [[event allTouches] anyObject];
	if (!touch) return;
	CGPoint pt = [touch locationInView:self.view];

	if (!sIsLocked) {
		CGFloat deltaX = sTouchStart.x - pt.x;
		CGFloat deltaY = sTouchStart.y - pt.y;
		sDragDeltaX = deltaX;

		// 1. Slide UP into the rice grain to lock
		if (deltaY >= TGMetricVoiceLockDistance || pt.y <= CGRectGetMinY(self.inputBar.frame) - TGMetricVoiceLockMargin) {
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
	if (![[TGVoiceRecorder shared] start]){
		[self showPlaybackFailure];
		return;
	}
	[self showRecordPanel];
	self.recordTimer = [NSTimer timerWithTimeInterval:0.1
											   target:self
											 selector:@selector(recordTick)
											 userInfo:nil
											  repeats:YES];
	[[NSRunLoop currentRunLoop] addTimer:self.recordTimer forMode:NSRunLoopCommonModes];
}

- (void)recordTick {
	NSTimeInterval d = [TGVoiceRecorder shared].duration;
	// Shows tenths of seconds smoothly updated every 100ms
	self.recordClock.text = [NSString stringWithFormat:@"%ld:%02ld,%ld",
			(long)(d / 60), (long)((NSInteger)d % 60), (long)((NSInteger)(d * 10) % 10)];
	self.recordDot.alpha = ((NSInteger)(d * 2) % 2 == 0) ? TGAlphaOpaque : TGAlphaRingTrack;

	if (!sIsLocked) {
		UIView *ring = [self.recordPanel viewWithTag:0x81C1];
		if (ring) {
			CGFloat pulse = TGAlphaOpaque + TGAnimationPulseAmplitude * fabsf(sinf((float)d * (float)M_PI));
			ring.transform = CGAffineTransformMakeScale(pulse, pulse);
		}
	}
}

- (void)recordFinish {
	self.table.scrollEnabled = YES;
	[self.recordTimer invalidate];
	self.recordTimer = nil;
	[self hideRecordPanel];

	__weak typeof(self) weakSelf = self;
	[[TGVoiceRecorder shared] stopWithCompletion:^(NSString *path, NSTimeInterval seconds){
		TGChatViewController *me = weakSelf;
		[me clearComposeState];
		if (!me || !path || seconds < 0.5)
			return;   // a stray tap is not a voice message
		[[TGClient shared] sendVoiceAtPath:path
								  duration:(NSInteger)seconds
									toChat:me.chatId
									thread:me.threadId];
	}];
}

- (void)recordCancel {
	self.table.scrollEnabled = YES;
	sIsCancelled = YES;
	[self.recordTimer invalidate];
	self.recordTimer = nil;
	[self hideRecordPanel];
	[[TGVoiceRecorder shared] cancel];
	[self clearComposeState];
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
	circle.backgroundColor = [UIColor blackColor];
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

/// Five ticks a second is enough for the eye and cheap enough for a 4S: the
/// waveform is redrawn each tick, and redrawing it sixty times would not be.
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
		bubble.wave.image = [TGIcons waveform:bubble.waveformData
										 size:bubble.wave.bounds.size
									   played:played
									   colour:[[TGTheme shared] accentColour]];
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

- (void)audioPlayerDidFinishPlaying:(AVAudioPlayer *)player successfully:(BOOL)flag {
	[self stopPlayback];
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
	[[TGClient shared] downloadFile:[docId integerValue] completion:^(NSString *path){
		dispatch_async(dispatch_get_main_queue(), ^{
			[weakSelf endDownloadHUD];
		});
		NSLog(@"voice: file %@", path.lastPathComponent ?: @"(not downloaded)");
		if (!path){
			dispatch_async(dispatch_get_main_queue(), ^{
				[weakSelf showPlaybackFailure];
			});
			return;
		}
		dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
			NSString *wav = [TGVoiceDecoder wavFromOpusFile:path];
			NSLog(@"voice: decoded to %@ (%llu bytes)", wav.lastPathComponent ?: @"nothing",
					[[[NSFileManager defaultManager] attributesOfItemAtPath:wav ?: @""
																	  error:nil] fileSize]);
			dispatch_async(dispatch_get_main_queue(), ^{
				TGChatViewController *me = weakSelf;
				if (!me) return;
				if (!wav){
					[me showPlaybackFailure];
					return;
				}
				NSError *err = nil;
				[[AVAudioSession sharedInstance]
						setCategory:AVAudioSessionCategoryPlayback error:nil];
				[[AVAudioSession sharedInstance] setActive:YES error:nil];
				me.voicePlayer = [[AVAudioPlayer alloc]
						initWithContentsOfURL:[NSURL fileURLWithPath:wav] error:&err];
				if (err){
					NSLog(@"voice playback: %@", err);
					[me showPlaybackFailure];
					return;
				}
				NSLog(@"voice: playing %.1f s", me.voicePlayer.duration);
				me.voicePlayer.delegate = me;
				me.voicePlayer.enableRate = YES;   // for the speed button
				me.playingMessageId = [m[@"id"] longLongValue];
				[me.voicePlayer play];
				[me showPlayerBar];
				[me startPlaybackTimer];
				[me.table reloadData];
			});
		});
	}];
}

@end
