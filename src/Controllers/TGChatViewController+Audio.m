#import "TGChatViewControllerInternal.h"
#import "TGVoiceRecorder.h"
#import "TGVoiceDecoder.h"
#import "TGMusicPlayer.h"

@implementation TGChatViewController (Audio)

#pragma mark - voice

/// Send is for typed text, the microphone for everything else - showing both
/// at once would leave one of them dead.
- (void)inputChanged {
	BOOL hasText = self.input.text.length > 0;
	self.sendButton.hidden = !hasText;
	self.micButton.hidden = hasText;
}

/// Their recording panel: a red dot, the running time, "Slide to cancel", and
/// the microphone grown into a disc with a halo around it. It takes over the
/// composer for as long as the finger is down.
- (void)showRecordPanel {
	CGRect bar = self.inputBar.frame;
	if (!self.recordPanel){
		TGTheme *theme = [TGTheme shared];
		self.recordPanel = [[UIView alloc] initWithFrame:bar];
		self.recordPanel.backgroundColor = [theme inputBarColour];
		self.recordPanel.autoresizingMask = UIViewAutoresizingFlexibleWidth |
											UIViewAutoresizingFlexibleTopMargin;

		UIView *hair = [[UIView alloc] initWithFrame:CGRectMake(0, 0, bar.size.width, 1)];
		hair.backgroundColor = [theme separatorColour];
		hair.autoresizingMask = UIViewAutoresizingFlexibleWidth;
		[self.recordPanel addSubview:hair];

		// 10dp in their panel, and it blinks the way a recorder's does.
		self.recordDot = [[UIView alloc] initWithFrame:
				CGRectMake(14, (kInputHeight - 9) / 2, 9, 9)];
		self.recordDot.backgroundColor = [theme destructiveColour];
		self.recordDot.layer.cornerRadius = 4.5f;
		[self.recordPanel addSubview:self.recordDot];

		self.recordClock = [[UILabel alloc] initWithFrame:
				CGRectMake(32, (kInputHeight - 20) / 2, 62, 20)];
		self.recordClock.font = [UIFont systemFontOfSize:16];
		self.recordClock.textColor = [theme primaryTextColour];
		self.recordClock.backgroundColor = [UIColor clearColor];
		[self.recordPanel addSubview:self.recordClock];

		UILabel *cancel = [[UILabel alloc] initWithFrame:
				CGRectMake(100, (kInputHeight - 20) / 2, bar.size.width - 180, 20)];
		cancel.text = @"‹ Slide to cancel";
		cancel.font = [UIFont systemFontOfSize:15];
		cancel.textColor = [theme secondaryTextColour];
		cancel.backgroundColor = [UIColor clearColor];
		cancel.autoresizingMask = UIViewAutoresizingFlexibleWidth;
		[self.recordPanel addSubview:cancel];

		// 89dp with the button itself at 63 inside it; scaled to fit the strip.
		CGFloat halo = kInputHeight + 12, disc = 44;
		UIView *ring = [[UIView alloc] initWithFrame:
				CGRectMake(bar.size.width - halo + 4, (kInputHeight - halo) / 2, halo, halo)];
		ring.backgroundColor = [theme accentColour];
		ring.alpha = 0.25f;
		ring.layer.cornerRadius = halo / 2;
		ring.autoresizingMask = UIViewAutoresizingFlexibleLeftMargin;
		[self.recordPanel addSubview:ring];

		UIImageView *button = [[UIImageView alloc] initWithFrame:CGRectMake(
				CGRectGetMidX(ring.frame) - disc / 2, (kInputHeight - disc) / 2, disc, disc)];
		button.backgroundColor = [theme accentColour];
		button.layer.cornerRadius = disc / 2;
		button.image = [TGIcons microphoneOfSide:disc colour:[UIColor whiteColor]];
		button.autoresizingMask = UIViewAutoresizingFlexibleLeftMargin;
		[self.recordPanel addSubview:button];
	}

	self.recordPanel.frame = bar;
	self.recordClock.text = @"0:00,0";
	self.recordDot.alpha = 1.0f;
	[self.view addSubview:self.recordPanel];
}

- (void)hideRecordPanel {
	[self.recordPanel removeFromSuperview];
}

- (void)recordStart {
	if (![[TGVoiceRecorder shared] start]){
		[self showPlaybackFailure];
		return;
	}
	[self showRecordPanel];
	self.recordTimer = [NSTimer scheduledTimerWithTimeInterval:0.5
													   target:self
													 selector:@selector(recordTick)
													 userInfo:nil
													  repeats:YES];
}

- (void)recordTick {
	NSTimeInterval d = [TGVoiceRecorder shared].duration;
	// Their panel shows tenths, which is what makes it read as running.
	self.recordClock.text = [NSString stringWithFormat:@"%ld:%02ld,%ld",
			(long)(d / 60), (long)((NSInteger)d % 60), (long)((NSInteger)(d * 10) % 10)];
	self.recordDot.alpha = (self.recordDot.alpha < 1.0f) ? 1.0f : 0.25f;
}

- (void)recordFinish {
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

	CGFloat side = 178.0f;
	CGRect inTable = [self.table rectForRowAtIndexPath:
			[NSIndexPath indexPathForRow:row inSection:0]];
	NSDictionary *m = self.messages[row];
	CGFloat x = [m[@"outgoing"] boolValue]
			? (self.table.bounds.size.width - side - 8) : 8;

	UIView *circle = [[UIView alloc] initWithFrame:
			CGRectMake(x, inTable.origin.y + 3, side, side)];
	circle.layer.cornerRadius = side / 2;
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
	self.videoNoteProgressLayer.path = [UIBezierPath bezierPathWithArcCenter:CGPointMake(side/2, side/2)
																	  radius:side/2 - 2
																  startAngle:-M_PI_2
																	endAngle:M_PI_2 * 3
																   clockwise:YES].CGPath;
	self.videoNoteProgressLayer.strokeColor = [[TGTheme shared] accentColour].CGColor;
	self.videoNoteProgressLayer.fillColor = [UIColor clearColor].CGColor;
	self.videoNoteProgressLayer.lineWidth = 4.0;
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
	if (!self.playerBar){
		self.playerBar = [[UIView alloc] initWithFrame:CGRectMake(0, 0, b.size.width, 36)];
		self.playerBar.backgroundColor = [[TGTheme shared] listBackgroundColour];
		self.playerBar.autoresizingMask = UIViewAutoresizingFlexibleWidth;

		self.playerToggle = [UIButton buttonWithType:UIButtonTypeCustom];
		self.playerToggle.frame = CGRectMake(8, 4, 28, 28);
		self.playerToggle.tintColor = [[TGTheme shared] accentColour];
		[self.playerToggle addTarget:self action:@selector(togglePlayback)
					forControlEvents:UIControlEventTouchUpInside];
		[self.playerBar addSubview:self.playerToggle];

		self.playerLabel = [[UILabel alloc] initWithFrame:
				CGRectMake(40, 8, b.size.width - 128, 20)];
		self.playerLabel.font = [UIFont systemFontOfSize:14];
		self.playerLabel.backgroundColor = [UIColor clearColor];
		self.playerLabel.autoresizingMask = UIViewAutoresizingFlexibleWidth;
		[self.playerBar addSubview:self.playerLabel];

		UIButton *close = [UIButton buttonWithType:UIButtonTypeCustom];
		close.frame = CGRectMake(b.size.width - 38, 4, 34, 28);
		[close setTitle:@"×" forState:UIControlStateNormal];
		close.titleLabel.font = [UIFont systemFontOfSize:24];
		close.autoresizingMask = UIViewAutoresizingFlexibleLeftMargin;
		[close addTarget:self action:@selector(stopPlayback)
		forControlEvents:UIControlEventTouchUpInside];
		[self.playerBar addSubview:close];
		[close setTitleColor:[[TGTheme shared] secondaryTextColour]
					forState:UIControlStateNormal];

		self.playerSpeed = [UIButton buttonWithType:UIButtonTypeCustom];
		self.playerSpeed.frame = CGRectMake(b.size.width - 82, 4, 42, 28);
		self.playerSpeed.titleLabel.font = [UIFont systemFontOfSize:13];
		self.playerSpeed.autoresizingMask = UIViewAutoresizingFlexibleLeftMargin;
		[self.playerSpeed setTitle:@"1x" forState:UIControlStateNormal];
		[self.playerSpeed setTitleColor:[[TGTheme shared] accentColour]
							   forState:UIControlStateNormal];
		[self.playerSpeed addTarget:self action:@selector(cyclePlaybackSpeed)
				   forControlEvents:UIControlEventTouchUpInside];
		[self.playerBar addSubview:self.playerSpeed];

		[self.playerBar addGestureRecognizer:[[UITapGestureRecognizer alloc]
				initWithTarget:self action:@selector(playerBarScrubbed:)]];
		[self.playerBar addGestureRecognizer:[[UIPanGestureRecognizer alloc]
				initWithTarget:self action:@selector(playerBarScrubbed:)]];

		UIView *track = [[UIView alloc] initWithFrame:CGRectMake(0, 34, b.size.width, 2)];
		track.backgroundColor = [[TGTheme shared] separatorColour];
		track.autoresizingMask = UIViewAutoresizingFlexibleWidth;
		[self.playerBar addSubview:track];

		self.playerProgress = [[UIView alloc] initWithFrame:CGRectMake(0, 34, 0, 2)];
		self.playerProgress.backgroundColor = [[TGTheme shared] accentColour];
		[self.playerBar addSubview:self.playerProgress];
	}

	self.playerLabel.textColor = [[TGTheme shared] primaryTextColour];
	self.playerLabel.text = @"Voice message";
	self.playerProgress.frame = CGRectMake(0, 34, 0, 2);
	[self.playerToggle setImage:[TGIcons pause] forState:UIControlStateNormal];
	self.playerSpeed.hidden = (self.voicePlayer == nil);   // video notes have no rate
	[self.playerSpeed setTitle:@"1x" forState:UIControlStateNormal];
	self.musicPrevious.hidden = YES;
	self.musicNext.hidden = YES;
	[self.view addSubview:self.playerBar];

	// Push the messages down so the strip does not cover the newest one.
	UIEdgeInsets insets = self.table.contentInset;
	insets.top += 36;
	self.table.contentInset = insets;
	self.table.scrollIndicatorInsets = insets;
}

- (void)hidePlayerBar {
	if (!self.playerBar.superview)
		return;
	[self.playerBar removeFromSuperview];
	UIEdgeInsets insets = self.table.contentInset;
	insets.top -= 36;
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
	self.playerProgress.frame = CGRectMake(0, 34,
			self.playerBar.bounds.size.width * played, 2);
            
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

	if (!self.musicPrevious){
		CGFloat width = self.playerBar.bounds.size.width;

		self.musicPrevious = [UIButton buttonWithType:UIButtonTypeCustom];
		self.musicPrevious.frame = CGRectMake(width - 120, 4, 28, 28);
		self.musicPrevious.titleLabel.font = [UIFont systemFontOfSize:18];
		[self.musicPrevious setTitle:@"◀" forState:UIControlStateNormal];
		self.musicPrevious.autoresizingMask = UIViewAutoresizingFlexibleLeftMargin;
		[self.musicPrevious addTarget:self action:@selector(musicPreviousTapped)
					 forControlEvents:UIControlEventTouchUpInside];
		[self.playerBar addSubview:self.musicPrevious];

		self.musicNext = [UIButton buttonWithType:UIButtonTypeCustom];
		self.musicNext.frame = CGRectMake(width - 92, 4, 28, 28);
		self.musicNext.titleLabel.font = [UIFont systemFontOfSize:18];
		[self.musicNext setTitle:@"▶" forState:UIControlStateNormal];
		self.musicNext.autoresizingMask = UIViewAutoresizingFlexibleLeftMargin;
		[self.musicNext addTarget:self action:@selector(musicNextTapped)
				 forControlEvents:UIControlEventTouchUpInside];
		[self.playerBar addSubview:self.musicNext];
	}

	UIColor *accent = [[TGTheme shared] accentColour];
	[self.musicPrevious setTitleColor:accent forState:UIControlStateNormal];
	[self.musicNext setTitleColor:accent forState:UIControlStateNormal];
	self.musicPrevious.hidden = NO;
	self.musicNext.hidden = NO;
	self.playerSpeed.hidden = YES;      // the two buttons take that corner

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
	NSString *performer = music.current[@"audioPerformer"];
	self.playerLabel.text = performer.length
			? [NSString stringWithFormat:@"%@ - %@", performer, title] : title;
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
	CGFloat fraction = MIN(MAX(x / MAX(1.0f, wave.bounds.size.width), 0.0f), 1.0f);
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
	float next = (rate < 1.25f) ? 1.5f : ((rate < 1.75f) ? 2.0f : 1.0f);
	self.voicePlayer.rate = next;
	[self.playerSpeed setTitle:(next == 1.0f ? @"1x" :
			(next == 1.5f ? @"1.5x" : @"2x")) forState:UIControlStateNormal];
}

/// Tapping anywhere along the strip's line jumps there.
- (void)playerBarScrubbed:(UIGestureRecognizer *)gesture {
	CGFloat width = self.playerBar.bounds.size.width;
	CGFloat fraction = MIN(MAX([gesture locationInView:self.playerBar].x /
			MAX(1.0f, width), 0.0f), 1.0f);
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
