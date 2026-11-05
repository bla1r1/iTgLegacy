#import "TGStoryViewerViewController.h"
#import "TGClient.h"
#import "TGTheme.h"
#import "TGStyle.h"
#import "TGAlertSheet.h"
#import "TGIcons.h"
#import "TGStoryInfoViewController.h"
#import "TGStoryAlbumsViewController.h"
#import "TGStoryComposerViewController.h"
#import "TGLiveStoryViewController.h"
#import <AVFoundation/AVFoundation.h>
#import <QuartzCore/QuartzCore.h>

/// How long a still story stays up. Videos use their own duration when TDLib
/// knows it; a story without a duration falls back to the same five seconds.
static const NSTimeInterval kStoryStillSeconds = 5.0;
/// The progress bars repaint twenty times a second: smooth on a 4S, and less
/// than a frame a tick on a 3GS.
static const NSTimeInterval kStoryTick = 0.05;
static const NSInteger kStoryReactionChoices = 6;

/// A story's timestamp as the header says it: seconds, minutes or hours ago.
/// Telegram uses the short form because the header has one line for it.
static NSString *TGStoryRelativeTime(NSTimeInterval timestamp) {
	if (timestamp <= 0)
		return @"";
	NSTimeInterval age = [[NSDate date] timeIntervalSince1970] - timestamp;
	if (age < 60)
		return @"now";
	if (age < 3600)
		return [NSString stringWithFormat:@"%ldm", (long)(age / 60)];
	if (age < 86400)
		return [NSString stringWithFormat:@"%ldh", (long)(age / 3600)];
	return [NSString stringWithFormat:@"%ldd", (long)(age / 86400)];
}

@interface TGStoryViewerViewController () <UIGestureRecognizerDelegate>
@property (nonatomic, assign) int64_t chatId;
@property (nonatomic, copy) NSString *storyTitle;
@property (nonatomic, strong) NSMutableArray *stories;
@property (nonatomic, assign) NSInteger index;
@property (nonatomic, assign) BOOL canManage;
@property (nonatomic, strong) UIView *progressHost;
@property (nonatomic, strong) NSMutableArray *progressFills;
@property (nonatomic, strong) UIImageView *picture;
@property (nonatomic, strong) UIView *topShade;
@property (nonatomic, strong) UIView *bottomShade;
@property (nonatomic, strong) AVPlayer *player;
@property (nonatomic, strong) AVPlayerLayer *playerLayer;
@property (nonatomic, strong) UILabel *senderLabel;
@property (nonatomic, strong) UILabel *timeLabel;
@property (nonatomic, strong) UIImageView *authorAvatar;
@property (nonatomic, strong) UIButton *infoButton;
@property (nonatomic, strong) UILabel *captionLabel;
@property (nonatomic, strong) UILabel *infoLabel;
@property (nonatomic, strong) UIView *reactionRail;
@property (nonatomic, strong) NSTimer *timer;
@property (nonatomic, assign) NSTimeInterval elapsed;
@property (nonatomic, assign) NSTimeInterval duration;
@property (nonatomic, assign) BOOL paused;
@property (nonatomic, assign) CGPoint dragStart;
@property (nonatomic, strong) NSArray *reactionEmojis;
@property (nonatomic, assign) BOOL closed;
@end

@implementation TGStoryViewerViewController

- (instancetype)initWithChatId:(int64_t)chatId
						title:(NSString *)title
					   stories:(NSArray *)stories
					startIndex:(NSInteger)startIndex
					  canManage:(BOOL)canManage {
	self = [super initWithNibName:nil bundle:nil];
	if (self){
		_chatId = chatId;
		_storyTitle = [title copy];
		_stories = [stories mutableCopy] ?: [NSMutableArray array];
		_index = MAX(0, MIN(startIndex, (NSInteger)_stories.count - 1));
		_canManage = canManage;
		_progressFills = [NSMutableArray array];
		self.wantsFullScreenLayout = YES;
		self.hidesBottomBarWhenPushed = YES;
	}
	return self;
}

- (void)viewDidLoad {
	[super viewDidLoad];
	self.view.backgroundColor = [[TGTheme shared] mediaViewerBackdropColour];

	_picture = [[UIImageView alloc] initWithFrame:self.view.bounds];
	_picture.contentMode = UIViewContentModeScaleAspectFit;
	_picture.backgroundColor = [UIColor clearColor];
	[self.view addSubview:_picture];

	_topShade = [self shadeViewFromTop:YES];
	_bottomShade = [self shadeViewFromTop:NO];
	[self.view addSubview:_topShade];
	[self.view addSubview:_bottomShade];

	_progressHost = [[UIView alloc] initWithFrame:CGRectZero];
	_progressHost.backgroundColor = [UIColor clearColor];
	[self.view addSubview:_progressHost];

	_senderLabel = [[UILabel alloc] initWithFrame:CGRectZero];
	_senderLabel.font = TGFontSubheadStrong();
	_senderLabel.textColor = [[TGTheme shared] onMediaColour];
	_senderLabel.backgroundColor = [UIColor clearColor];
	_senderLabel.lineBreakMode = NSLineBreakByTruncatingTail;
	[self.view addSubview:_senderLabel];

	_timeLabel = [[UILabel alloc] initWithFrame:CGRectZero];
	_timeLabel.font = TGFontMicro();
	_timeLabel.textColor = [[TGTheme shared] secondaryTextColour];
	_timeLabel.backgroundColor = [UIColor clearColor];
	[self.view addSubview:_timeLabel];

	_authorAvatar = [[UIImageView alloc] initWithFrame:CGRectZero];
	_authorAvatar.contentMode = UIViewContentModeScaleAspectFill;
	_authorAvatar.clipsToBounds = YES;
	_authorAvatar.layer.cornerRadius = TGHalf(TGMetricStoryHeaderAvatar);
	_authorAvatar.backgroundColor = [[TGTheme shared] fileTileColour];
	[self.view addSubview:_authorAvatar];

	_captionLabel = [[UILabel alloc] initWithFrame:CGRectZero];
	_captionLabel.font = TGFontBody();
	_captionLabel.textColor = [[TGTheme shared] onMediaColour];
	_captionLabel.backgroundColor = [UIColor clearColor];
	_captionLabel.numberOfLines = 4;
	[self.view addSubview:_captionLabel];

	_infoLabel = [[UILabel alloc] initWithFrame:CGRectZero];
	_infoLabel.font = TGFontMeta();
	_infoLabel.textColor = [[TGTheme shared] secondaryTextColour];
	_infoLabel.backgroundColor = [UIColor clearColor];
	[self.view addSubview:_infoLabel];

	UIButton *close = [UIButton buttonWithType:UIButtonTypeCustom];
	close.frame = CGRectMake(0, 0, TGMetricStoryCloseSide, TGMetricStoryCloseSide);
	[close setImage:[TGIcons glyphNamed:@"close" colour:[[TGTheme shared] onMediaColour]
								  side:TGMetricStoryCloseSide - TGMetricPadSmall]
		   forState:UIControlStateNormal];
	[close addTarget:self action:@selector(closeTapped) forControlEvents:UIControlEventTouchUpInside];
	[self.view addSubview:close];
	close.tag = 9001;

	UIButton *menu = [UIButton buttonWithType:UIButtonTypeCustom];
	menu.frame = CGRectMake(0, 0, TGMetricStoryCloseSide, TGMetricStoryCloseSide);
	[menu setImage:[TGIcons glyphNamed:@"more" colour:[[TGTheme shared] onMediaColour]
								 side:TGMetricStoryCloseSide - TGMetricPadSmall]
		  forState:UIControlStateNormal];
	[menu addTarget:self action:@selector(menuTapped) forControlEvents:UIControlEventTouchUpInside];
	[self.view addSubview:menu];
	menu.tag = 9002;

	// The views line under the picture is a button: it is where the viewer
	// list and the story's counters live, and Telegram makes it open them.
	_infoButton = [UIButton buttonWithType:UIButtonTypeCustom];
	_infoButton.backgroundColor = [UIColor clearColor];
	[_infoButton addTarget:self action:@selector(openInfo)
		  forControlEvents:UIControlEventTouchUpInside];
	[self.view addSubview:_infoButton];

	// A flick down puts the story away and goes back where it came from.
	UIPanGestureRecognizer *drag = [[UIPanGestureRecognizer alloc]
			initWithTarget:self action:@selector(storyDragged:)];
	drag.delegate = self;
	[self.view addGestureRecognizer:drag];

	UITapGestureRecognizer *tap = [[UITapGestureRecognizer alloc]
			initWithTarget:self action:@selector(tapAt:)];
	tap.delegate = self;
	[self.view addGestureRecognizer:tap];

	UILongPressGestureRecognizer *hold = [[UILongPressGestureRecognizer alloc]
			initWithTarget:self action:@selector(held:)];
	hold.minimumPressDuration = 0.18;
	[self.view addGestureRecognizer:hold];

	[self.view bringSubviewToFront:close];
	[self.view bringSubviewToFront:menu];
	[self.view bringSubviewToFront:_infoButton];

	// A story edited or deleted on another client arrives while this viewer
	// is open. The row handles its own copy; here the story id decides
	// whether the picture on screen or the count behind it moved.
	__weak typeof(self) weakSelf = self;
	[[NSNotificationCenter defaultCenter] addObserverForName:TGStoriesChangedNotification
			object:nil queue:[NSOperationQueue mainQueue]
		usingBlock:^(NSNotification *note){
		TGStoryViewerViewController *me = weakSelf;
		if (!me || me.closed)
			return;
		if ([note.userInfo[@"chatId"] longLongValue] != me.chatId)
			return;
		NSDictionary *story = note.userInfo[@"story"];
		if ([story isKindOfClass:NSDictionary.class]){
			NSInteger at = [me indexOfStoryId:[story[@"storyId"] intValue]];
			if (at < 0){
				[me.stories addObject:story];
				at = (NSInteger)me.stories.count - 1;
			} else {
				me.stories[at] = story;
			}
			if (at == me.index)
				[me showCurrentStory];
			return;
		}
		NSNumber *deleted = note.userInfo[@"deletedStoryId"];
		if (![deleted isKindOfClass:NSNumber.class])
			return;
		NSInteger at = [me indexOfStoryId:deleted.intValue];
		if (at < 0)
			return;
		[me.stories removeObjectAtIndex:at];
		if (!me.stories.count){
			[me finish];
			return;
		}
		if (at < me.index)
			me.index--;
		else if (at == me.index)
			me.index = MIN(me.index, (NSInteger)me.stories.count - 1);
		[me showCurrentStory];
	}];

	[self loadReactions];
	[self showCurrentStory];
}

- (NSInteger)indexOfStoryId:(int32_t)storyId {
	for (NSInteger i = 0; i < (NSInteger)self.stories.count; i++){
		id entry = self.stories[i];
		if ([entry isKindOfClass:NSDictionary.class] &&
			[entry[@"storyId"] intValue] == storyId)
			return i;
		if ([entry isKindOfClass:NSNumber.class] && [entry intValue] == storyId)
			return i;
	}
	return -1;
}

- (UIView *)shadeViewFromTop:(BOOL)top {
	UIView *view = [[UIView alloc] initWithFrame:CGRectZero];
	view.userInteractionEnabled = NO;
	view.backgroundColor = [UIColor clearColor];
	CAGradientLayer *gradient = [CAGradientLayer layer];
	gradient.colors = @[(id)[[TGTheme shared] scrimColour].CGColor,
						(id)[UIColor clearColor].CGColor];
	gradient.startPoint = CGPointMake(0.5,
									  top ? TGMetricZero : TGMetricScaleFull);
	gradient.endPoint = CGPointMake(0.5,
									top ? TGMetricScaleFull : TGMetricZero);
	[view.layer addSublayer:gradient];
	return view;
}

- (void)layoutShade:(UIView *)shade {
	for (CALayer *layer in shade.layer.sublayers)
		if ([layer isKindOfClass:CAGradientLayer.class])
			layer.frame = shade.bounds;
}

- (void)viewWillLayoutSubviews {
	[super viewWillLayoutSubviews];
	CGFloat width = self.view.bounds.size.width;
	CGFloat height = self.view.bounds.size.height;
	_picture.frame = self.view.bounds;
	self.topShade.frame = CGRectMake(0, 0, width, TGMetricStoryShadeTop);
	self.bottomShade.frame = CGRectMake(0, height - TGMetricStoryShadeBottom,
										width, TGMetricStoryShadeBottom);
	[self layoutShade:self.topShade];
	[self layoutShade:self.bottomShade];
	if (_playerLayer)
		_playerLayer.frame = _picture.bounds;

	CGFloat top = TGMetricStoryProgressTop;
	CGFloat side = TGMetricStoryCloseSide + TGMetricStoryCloseInset;
	self.progressHost.frame = CGRectMake(TGMetricStoryProgressGap, top,
			width - TGDoubled(TGMetricStoryProgressGap),
			TGMetricStoryProgressHeight);
	UIView *close = [self.view viewWithTag:9001];
	UIView *menu = [self.view viewWithTag:9002];
	CGFloat headerY = top + TGMetricStoryProgressHeight + TGMetricPadSmall;
	if (close)
		close.frame = CGRectMake(width - side - TGMetricStoryCloseSide, headerY,
								 TGMetricStoryCloseSide, TGMetricStoryCloseSide);
	if (menu)
		menu.frame = CGRectMake(CGRectGetMinX(close.frame) -
								TGMetricStoryHeaderGap - TGMetricStoryCloseSide,
								headerY, TGMetricStoryCloseSide,
								TGMetricStoryCloseSide);
	_authorAvatar.frame = CGRectMake(side,
			headerY + TGCenteredOrigin(TGMetricStoryCloseSide,
									   TGMetricStoryHeaderAvatar),
			TGMetricStoryHeaderAvatar, TGMetricStoryHeaderAvatar);
	CGFloat nameX = CGRectGetMaxX(_authorAvatar.frame) + TGMetricStoryHeaderGap;
	CGFloat nameW = CGRectGetMinX(menu.frame) - nameX - TGMetricStoryHeaderGap;
	if (nameW < 0)
		nameW = 0;
	_senderLabel.frame = CGRectMake(nameX, headerY, nameW,
			TGMetricStoryViewerNameHeight);
	_timeLabel.frame = CGRectMake(nameX, CGRectGetMaxY(_senderLabel.frame),
			nameW, TGMetricLineMicro);
	_captionLabel.frame = CGRectMake(TGMetricPadLarge,
			height - TGMetricStoryReactionRow - TGMetricStoryCaptionBottomOffset,
			width - TGDoubled(TGMetricPadLarge), TGMetricStoryCaptionHeight);
	_infoLabel.frame = CGRectMake(TGMetricPadLarge,
			height - TGMetricStoryReactionRow - TGMetricPadLarge, width -
			TGDoubled(TGMetricPadLarge), TGMetricLineCaption);
	_infoButton.frame = _infoLabel.frame;
	self.reactionRail.frame = CGRectMake(TGMetricPadLarge,
			height - TGMetricStoryReactionRow - TGMetricPadSmall,
			width - TGDoubled(TGMetricPadLarge), TGMetricStoryReactionRow);
	[self rebuildProgressBars];
}

- (void)rebuildProgressBars {
	for (UIView *old in self.progressHost.subviews)
		[old removeFromSuperview];
	[self.progressFills removeAllObjects];
	NSInteger count = MAX(1, (NSInteger)self.stories.count);
	CGFloat total = self.progressHost.bounds.size.width -
			(count - 1) * TGMetricStoryProgressGap;
	CGFloat each = total / (CGFloat)count;
	for (NSInteger i = 0; i < count; i++){
		UIView *track = [[UIView alloc] initWithFrame:CGRectMake(
				i * (each + TGMetricStoryProgressGap), 0, each,
				TGMetricStoryProgressHeight)];
		track.backgroundColor = [[TGTheme shared] scrimColour];
		track.layer.cornerRadius = TGHalf(TGMetricStoryProgressHeight);
		[track setClipsToBounds:YES];
		UIView *fill = [[UIView alloc] initWithFrame:track.bounds];
		fill.backgroundColor = [[TGTheme shared] onMediaColour];
		fill.layer.cornerRadius = TGHalf(TGMetricStoryProgressHeight);
		[track addSubview:fill];
		[self.progressHost addSubview:track];
		[self.progressFills addObject:fill];
	}
}

- (void)showCurrentStory {
	[self stopTimer];
	[self stopVideo];
	[self removePlayerLayer];
	_picture.image = nil;
	[self rebuildProgressBars];
	for (NSInteger i = 0; i < self.index && i < (NSInteger)self.progressFills.count; i++){
		UIView *fill = self.progressFills[i];
		CGRect frame = fill.frame;
		frame.size.width = fill.superview.bounds.size.width;
		fill.frame = frame;
	}
	if (self.index < 0 || self.index >= (NSInteger)self.stories.count){
		[self finish];
		return;
	}
	id entry = self.stories[self.index];
	self.senderLabel.text = self.storyTitle.length ? self.storyTitle : @"Story";
	[self refreshAuthorAvatar];
	[self updateHeaderCounterForStory:nil];
	if ([entry isKindOfClass:NSNumber.class]){
		[self loadStoryId:[entry intValue]];
		return;
	}
	[self showStory:entry];
}

- (void)refreshAuthorAvatar {
	NSString *title = self.senderLabel.text.length ? self.senderLabel.text : @"Story";
	NSString *initial = [TGIcons initialsForTitle:title];
	self.authorAvatar.image = [TGIcons avatarWithInitials:initial
												   size:TGMetricStoryHeaderAvatar
											   colourId:self.chatId];

	NSNumber *fileId = [[TGClient shared] photoFileIdForChat:self.chatId];
	if (![fileId isKindOfClass:NSNumber.class] || fileId.integerValue <= 0)
		return;
	__weak typeof(self) weakSelf = self;
	__weak UIImageView *weakAvatar = self.authorAvatar;
	[[TGClient shared] downloadFile:fileId.integerValue
						   priority:TGDownloadPriorityAvatar
						 completion:^(NSString *path){
		if (!path.length)
			return;
		dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_LOW, 0), ^{
			UIImage *image = [UIImage imageWithContentsOfFile:path];
			if (!image)
				return;
			image = [TGIcons decodedImage:image
					fittingSize:CGSizeMake(TGMetricStoryHeaderAvatar,
										   TGMetricStoryHeaderAvatar)
							 fill:YES scale:[UIScreen mainScreen].scale];
			if (!image)
				return;
			dispatch_async(dispatch_get_main_queue(), ^{
				TGStoryViewerViewController *me = weakSelf;
				if (me && !me.closed)
					weakAvatar.image = image;
			});
		});
	}];
}

/// "2 of 5 · 3h" under the name: the segment row is the count, this says it
/// in words and adds when the story was posted.
- (void)updateHeaderCounterForStory:(NSDictionary *)story {
	NSMutableArray *bits = [NSMutableArray array];
	if (self.stories.count > 1)
		[bits addObject:[NSString stringWithFormat:@"%ld of %lu",
				(long)(self.index + 1), (unsigned long)self.stories.count]];
	NSString *when = TGStoryRelativeTime([story[@"date"] doubleValue]);
	if (when.length)
		[bits addObject:when];
	self.timeLabel.text = [bits componentsJoinedByString:@" · "];
}

- (void)loadStoryId:(int32_t)storyId {
	__weak typeof(self) weakSelf = self;
	[[TGClient shared] story:storyId fromChat:self.chatId completion:^(NSDictionary *story){
		TGStoryViewerViewController *me = weakSelf;
		if (!me || me.closed)
			return;
		if (!story){
			[me advance:1];
			return;
		}
		me.stories[me.index] = story;
		[me showStory:story];
	}];
}

- (void)showStory:(NSDictionary *)story {
	_picture.image = nil;
	self.senderLabel.text = story[@"title"] ?: self.storyTitle;
	[self refreshAuthorAvatar];
	[self updateHeaderCounterForStory:story];
	NSString *caption = story[@"caption"] ?: @"";
	self.captionLabel.text = caption;
	NSInteger viewers = [story[@"viewers"] integerValue];
	NSInteger reactions = [story[@"reactions"] integerValue];
	NSMutableArray *bits = [NSMutableArray array];
	if ([story[@"isLive"] boolValue])
		[bits addObject:@"LIVE"];
	if ([story[@"isLive"] boolValue])
		[bits addObject:@"tap More to open the live story"];
	else {
		[bits addObject:[NSString stringWithFormat:@"%ld views", (long)viewers]];
		if (reactions > 0)
			[bits addObject:[NSString stringWithFormat:@"%ld reactions", (long)reactions]];
	}
	if ([story[@"isPostedToChatPage"] boolValue])
		[bits addObject:@"on profile"];
	self.infoLabel.text = [bits componentsJoinedByString:@" · "];

	[self loadReactionsForStory:story];
	[self startProgressForStory:story];
	[self openCurrent];

	NSNumber *photoId = story[@"thumbPhotoId"] ?: story[@"photoId"];
	if ([story[@"isVideo"] boolValue] || [story[@"isLive"] boolValue])
		photoId = story[@"thumbPhotoId"];
	if ([photoId isKindOfClass:NSNumber.class] && photoId.integerValue > 0){
		__weak typeof(self) weakSelf = self;
		[[TGClient shared] downloadFile:photoId.integerValue
							   priority:TGDownloadPriorityOnScreen
							 completion:^(NSString *path){
			TGStoryViewerViewController *me = weakSelf;
			if (!me || !path.length)
				return;
			[me.picture setImage:[UIImage imageWithContentsOfFile:path]];
		}];
	}

	NSNumber *videoId = story[@"videoId"];
	if ([videoId isKindOfClass:NSNumber.class] && videoId.integerValue > 0)
		[self playVideoId:videoId.integerValue];
}

- (void)playVideoId:(NSInteger)videoId {
	__weak typeof(self) weakSelf = self;
	[[TGClient shared] downloadFile:videoId completion:^(NSString *path){
		TGStoryViewerViewController *me = weakSelf;
		if (!me || !path.length || me.closed)
			return;
		NSError *sessionError = nil;
		[[AVAudioSession sharedInstance] setCategory:AVAudioSessionCategoryPlayback
											   error:&sessionError];
		[[AVAudioSession sharedInstance] setActive:YES error:NULL];
		AVPlayer *player = [AVPlayer playerWithURL:[NSURL fileURLWithPath:path]];
		AVPlayerLayer *layer = [AVPlayerLayer playerLayerWithPlayer:player];
		layer.videoGravity = AVLayerVideoGravityResizeAspect;
		layer.frame = me.picture.bounds;
		[me.picture.layer addSublayer:layer];
		me.player = player;
		me.playerLayer = layer;
		[player play];
	}];
}

- (void)removePlayerLayer {
	[self.player pause];
	[self.playerLayer removeFromSuperlayer];
	self.player = nil;
	self.playerLayer = nil;
}

- (void)stopVideo {
	[self removePlayerLayer];
}

#pragma mark - progress

- (void)startProgressForStory:(NSDictionary *)story {
	if ([story[@"isLive"] boolValue]){
		[self markProgressComplete:YES];
		return;
	}
	double known = [story[@"duration"] doubleValue];
	self.duration = [story[@"isVideo"] boolValue] && known > 0
			? known : kStoryStillSeconds;
	self.elapsed = 0;
	self.paused = NO;
	self.timer = [NSTimer scheduledTimerWithTimeInterval:kStoryTick
												 target:self
											   selector:@selector(tick)
											   userInfo:nil
												repeats:YES];
}

- (void)tick {
	if (self.paused || self.closed)
		return;
	self.elapsed += kStoryTick;
	CGFloat fraction = self.duration > 0
			? (CGFloat)(self.elapsed / self.duration) : 1;
	[self updateProgress:fraction];
	if (fraction >= 1){
		[self stopTimer];
		[self advance:1];
	}
}

- (void)updateProgress:(CGFloat)fraction {
	if (self.index < 0 || self.index >= (NSInteger)self.progressFills.count)
		return;
	UIView *fill = self.progressFills[self.index];
	CGRect frame = fill.frame;
	frame.size.width = fill.superview.bounds.size.width *
			MAX(0, MIN(1, fraction));
	fill.frame = frame;
}

- (void)markProgressComplete:(BOOL)complete {
	for (NSInteger i = 0; i < (NSInteger)self.progressFills.count; i++){
		UIView *fill = self.progressFills[i];
		CGRect frame = fill.frame;
		frame.size.width = (i < self.index || complete)
				? fill.superview.bounds.size.width : 0;
		fill.frame = frame;
	}
}

- (void)stopTimer {
	[self.timer invalidate];
	self.timer = nil;
}

- (void)pause {
	if (self.paused)
		return;
	self.paused = YES;
	[self.player pause];
}

- (void)resume {
	if (!self.paused)
		return;
	self.paused = NO;
	[self.player play];
}

#pragma mark - reactions

- (void)loadReactions {
	__weak typeof(self) weakSelf = self;
	[[TGClient shared] storyAvailableReactionsWithCompletion:^(NSDictionary *reactions){
		TGStoryViewerViewController *me = weakSelf;
		if (!me || !reactions)
			return;
		me.reactionEmojis = reactions[@"emojis"] ?: @[];
		[me rebuildReactionRail];
	}];
}

- (void)loadReactionsForStory:(NSDictionary *)story {
	NSString *chosen = story[@"chosenReaction"];
	if (chosen.length && self.reactionEmojis.count){
		NSMutableArray *ordered = [NSMutableArray arrayWithObject:chosen];
		for (NSString *emoji in self.reactionEmojis)
			if (![emoji isEqualToString:chosen])
				[ordered addObject:emoji];
		self.reactionEmojis = ordered;
	}
	[self rebuildReactionRail];
}

- (void)rebuildReactionRail {
	if (self.reactionRail)
		[self.reactionRail removeFromSuperview];
	self.reactionRail = [[UIView alloc] initWithFrame:CGRectZero];
	self.reactionRail.backgroundColor = [UIColor clearColor];
	[self.view addSubview:self.reactionRail];

	NSArray *emojis = self.reactionEmojis;
	NSInteger shown = MIN((NSInteger)emojis.count, kStoryReactionChoices);
	for (NSInteger i = 0; i < shown; i++){
		UIButton *button = [UIButton buttonWithType:UIButtonTypeCustom];
		button.frame = CGRectMake(i * (TGMetricStoryReactionButton +
									   TGMetricStoryReactionGap), 0,
								   TGMetricStoryReactionButton,
								   TGMetricStoryReactionButton);
		button.backgroundColor = [[TGTheme shared] scrimColour];
		button.layer.cornerRadius = TGHalf(TGMetricStoryReactionButton);
		button.tag = 100 + i;
		[button addTarget:self action:@selector(reactionTapped:)
				forControlEvents:UIControlEventTouchUpInside];
		UILongPressGestureRecognizer *remove = [[UILongPressGestureRecognizer alloc]
				initWithTarget:self action:@selector(reactionHeld:)];
		[button addGestureRecognizer:remove];
		UILabel *glyph = [[UILabel alloc] initWithFrame:button.bounds];
		glyph.text = emojis[i];
		glyph.font = TGFontEmoji();
		glyph.textAlignment = NSTextAlignmentCenter;
		glyph.backgroundColor = [UIColor clearColor];
		[button addSubview:glyph];
		[self.reactionRail addSubview:button];
	}
	if (!shown){
		UILabel *hint = [[UILabel alloc] initWithFrame:CGRectMake(0, 0,
				TGMetricScreenWidth, TGMetricStoryReactionButton)];
		hint.text = @"No reaction available";
		hint.font = TGFontMeta();
		hint.textColor = [[TGTheme shared] secondaryTextColour];
		hint.backgroundColor = [UIColor clearColor];
		[self.reactionRail addSubview:hint];
	}
	[self.view setNeedsLayout];
}

- (void)reactionTapped:(UIButton *)button {
	NSInteger i = button.tag - 100;
	if (i < 0 || i >= (NSInteger)self.reactionEmojis.count)
		return;
	NSString *emoji = self.reactionEmojis[i];
	NSDictionary *story = self.currentStory;
	if ([story[@"isLive"] boolValue]){
		int32_t callId = [story[@"groupCallId"] intValue];
		__weak typeof(self) weakSelf = self;
		[[TGClient shared] addPendingLiveStoryReactionInCall:callId stars:1
				completion:^(BOOL ok, NSString *error){
			TGStoryViewerViewController *me = weakSelf;
			if (!me)
				return;
			if (!ok){
				[TGAlertSheet showMessage:error ?: @"Telegram refused the reaction."
									title:@"Live Reaction" inView:me.view];
				return;
			}
			// The undo window is two seconds; committing after it is what
			// makes the star count on the server, not in this screen.
			[me performSelector:@selector(commitLiveReaction:)
					 withObject:@(callId) afterDelay:2.0];
		}];
		return;
	}
	NSString *chosen = story[@"chosenReaction"];
	BOOL remove = [chosen isEqualToString:emoji];
	__weak typeof(self) weakSelf = self;
	[[TGClient shared] setStoryReaction:remove ? nil : emoji
								onStory:[story[@"storyId"] intValue]
							   fromChat:self.chatId
							   completion:^(BOOL ok, NSString *error){
		TGStoryViewerViewController *me = weakSelf;
		if (!me)
			return;
		if (!ok){
			[TGAlertSheet showMessage:error ?: @"Telegram refused the reaction."
								title:@"Story Reaction" inView:me.view];
			return;
		}
		NSMutableDictionary *changed = [me.currentStory mutableCopy];
		changed[@"chosenReaction"] = remove ? @"" : emoji;
		me.stories[me.index] = changed;
		if (me.onStoriesChanged)
			me.onStoriesChanged();
	}];
}

- (void)reactionHeld:(UILongPressGestureRecognizer *)hold {
	if (hold.state != UIGestureRecognizerStateBegan)
		return;
	NSDictionary *story = self.currentStory;
	if (![story[@"isLive"] boolValue])
		return;
	__weak typeof(self) weakSelf = self;
	[[TGClient shared] removePendingLiveStoryReactionsInCall:
			[story[@"groupCallId"] intValue]
			completion:^(BOOL ok, NSString *error){
		TGStoryViewerViewController *me = weakSelf;
		if (!me)
			return;
		[TGAlertSheet showMessage:ok
				? @"Pending live reactions were cancelled."
				: (error ?: @"Telegram refused that.")
				title:@"Live Reaction" inView:me.view];
	}];
}

- (void)commitLiveReaction:(NSNumber *)callId {
	__weak typeof(self) weakSelf = self;
	[[TGClient shared] commitPendingLiveStoryReactionsInCall:callId.intValue
			completion:^(BOOL ok, NSString *error){
		TGStoryViewerViewController *me = weakSelf;
		if (!me || !ok)
			return;
		[TGAlertSheet showMessage:@"The reaction was sent."
							title:@"Live Reaction" inView:me.view];
	}];
}

#pragma mark - navigation

- (NSDictionary *)currentStory {
	if (self.index < 0 || self.index >= (NSInteger)self.stories.count)
		return @{};
	id entry = self.stories[self.index];
	return [entry isKindOfClass:NSDictionary.class] ? entry : @{};
}

- (void)advance:(NSInteger)delta {
	NSInteger next = self.index + delta;
	NSDictionary *current = self.currentStory;
	if (current[@"storyId"]){
		[[TGClient shared] closeStory:[current[@"storyId"] intValue]
							 fromChat:self.chatId completion:nil];
	}
	if (next < 0){
		[self finish];
		return;
	}
	if (next >= (NSInteger)self.stories.count){
		[self finish];
		return;
	}
	self.index = next;
	[self showCurrentStory];
}

- (void)openCurrent {
	NSDictionary *story = self.currentStory;
	if (!story[@"storyId"])
		return;
	[[TGClient shared] openStory:[story[@"storyId"] intValue]
						fromChat:self.chatId completion:nil];
}

- (void)tapAt:(UITapGestureRecognizer *)tap {
	CGPoint point = [tap locationInView:self.view];
	// The left third goes back and the rest goes on, as Telegram's stories
	// do - a 320 pt phone gives 107 pt to each side.
	[self advance:(point.x < self.view.bounds.size.width / 3.0f) ? -1 : 1];
}

/// A drag down carries the story with the finger; letting go before the
/// threshold puts it back and resumes the timer.
- (void)storyDragged:(UIPanGestureRecognizer *)drag {
	CGPoint moved = [drag translationInView:self.view];

	if (drag.state == UIGestureRecognizerStateBegan){
		self.dragStart = self.view.center;
		[self pause];
		return;
	}
	if (drag.state == UIGestureRecognizerStateChanged){
		self.view.center = CGPointMake(self.dragStart.x,
				self.dragStart.y + MAX(0, moved.y));
		return;
	}
	if (drag.state != UIGestureRecognizerStateEnded &&
		drag.state != UIGestureRecognizerStateCancelled)
		return;

	CGFloat velocity = [drag velocityInView:self.view].y;
	if (moved.y > TGMetricViewerDismissDistance ||
		velocity > TGMetricViewerDismissVelocity){
		[UIView animateWithDuration:TGAnimationDurationFast animations:^{
			self.view.center = CGPointMake(self.dragStart.x,
					self.dragStart.y + self.view.bounds.size.height);
			self.view.alpha = TGAlphaTransparent;
		} completion:^(BOOL done){
			[self finish];
		}];
		return;
	}

	[UIView animateWithDuration:TGAnimationDurationFast animations:^{
		self.view.center = self.dragStart;
	} completion:^(BOOL done){
		[self resume];
	}];
}

- (BOOL)gestureRecognizerShouldBegin:(UIGestureRecognizer *)gesture {
	if ([gesture isKindOfClass:UIPanGestureRecognizer.class]){
		CGPoint velocity = [(UIPanGestureRecognizer *)gesture velocityInView:self.view];
		return fabs(velocity.y) > fabs(velocity.x);
	}
	return YES;
}

- (BOOL)gestureRecognizer:(UIGestureRecognizer *)gestureRecognizer
		shouldReceiveTouch:(UITouch *)touch {
	UIView *view = touch.view;
	while (view){
		if ([view isKindOfClass:UIControl.class])
			return NO;
		if (view == self.view)
			break;
		view = view.superview;
	}
	return YES;
}

- (void)held:(UILongPressGestureRecognizer *)hold {
	if (hold.state == UIGestureRecognizerStateBegan)
		[self pause];
	else if (hold.state == UIGestureRecognizerStateEnded ||
			 hold.state == UIGestureRecognizerStateCancelled)
		[self resume];
}

- (void)viewWillAppear:(BOOL)animated {
	[super viewWillAppear:animated];
	[self.navigationController setNavigationBarHidden:YES animated:NO];
}

- (void)viewWillDisappear:(BOOL)animated {
	[super viewWillDisappear:animated];
	[self.navigationController setNavigationBarHidden:NO animated:NO];
}

- (void)viewDidAppear:(BOOL)animated {
	[super viewDidAppear:animated];
}

- (void)closeTapped {
	[self finish];
}

- (void)finish {
	if (self.closed)
		return;
	self.closed = YES;
	[self stopTimer];
	[self stopVideo];
	NSDictionary *story = self.currentStory;
	if (story[@"storyId"])
		[[TGClient shared] closeStory:[story[@"storyId"] intValue]
							 fromChat:self.chatId completion:nil];
	if (self.onStoriesChanged)
		self.onStoriesChanged();
	UIViewController *presenter = self.presentingViewController
			?: self.navigationController.presentingViewController;
	if (presenter)
		[presenter dismissViewControllerAnimated:YES completion:nil];
	else
		[self.navigationController popViewControllerAnimated:YES];
}

- (void)dealloc {
	[self stopTimer];
	[self stopVideo];
}

#pragma mark - the own story menu

- (void)menuTapped {
	NSDictionary *story = self.currentStory;
	if (!story[@"storyId"])
		return;
	NSMutableArray *titles = [NSMutableArray arrayWithObjects:
			@"Story Info", @"Report Story", nil];
	if (self.canManage || [story[@"canBeEdited"] boolValue] ||
		[story[@"canBeDeleted"] boolValue]){
		[titles addObject:@"Edit Caption"];
		[titles addObject:@"Change Cover Frame"];
		[titles addObject:@"Delete Story"];
		[titles addObject:[story[@"isPostedToChatPage"] boolValue]
				? @"Remove from Profile" : @"Keep on Profile"];
		[titles addObject:@"Pin to Chat Page"];
		[titles addObject:@"Story Privacy"];
		[titles addObject:@"Add to Album"];
		[titles addObject:@"Albums"];
		[titles addObject:@"Edit as Business Story"];
		[titles addObject:@"Delete as Business Story"];
	}
	if ([story[@"isLive"] boolValue])
		[titles addObject:@"Open Live Story"];
	[titles addObject:@"Add Story"];

	__weak typeof(self) weakSelf = self;
	[TGAlertSheet showChoices:titles title:@"Story" destructiveIndex:-1
					   inView:self.view onChoice:^(NSInteger choice){
		TGStoryViewerViewController *me = weakSelf;
		if (!me)
			return;
		NSString *title = titles[choice];
		if ([title isEqualToString:@"Story Info"])
			[me openInfo];
		else if ([title isEqualToString:@"Report Story"])
			[me openReport];
		else if ([title isEqualToString:@"Edit Caption"])
			[me editCaption];
		else if ([title isEqualToString:@"Change Cover Frame"])
			[me changeCover];
		else if ([title isEqualToString:@"Delete Story"])
			[me confirmDelete];
		else if ([title isEqualToString:@"Keep on Profile"] ||
				 [title isEqualToString:@"Remove from Profile"])
			[me toggleProfile:![story[@"isPostedToChatPage"] boolValue]];
		else if ([title isEqualToString:@"Pin to Chat Page"])
			[me pinToChatPage];
		else if ([title isEqualToString:@"Story Privacy"])
			[me choosePrivacy];
		else if ([title isEqualToString:@"Add to Album"])
			[me addToAlbum];
		else if ([title isEqualToString:@"Albums"])
			[me openAlbums];
		else if ([title isEqualToString:@"Edit as Business Story"])
			[me editBusiness];
		else if ([title isEqualToString:@"Delete as Business Story"])
			[me deleteBusiness];
		else if ([title isEqualToString:@"Open Live Story"])
			[me openLive];
		else if ([title isEqualToString:@"Add Story"])
			[me addStory];
	}];
}

- (void)openInfo {
	NSDictionary *story = self.currentStory;
	TGStoryInfoViewController *info = [[TGStoryInfoViewController alloc]
			initWithChatId:self.chatId
				   storyId:[story[@"storyId"] intValue]
					  story:story
					  mode:TGStoryInfoModeInfo];
	info.hidesBottomBarWhenPushed = YES;
	[self.navigationController pushViewController:info animated:YES];
}

- (void)openReport {
	NSDictionary *story = self.currentStory;
	TGStoryInfoViewController *info = [[TGStoryInfoViewController alloc]
			initWithChatId:self.chatId
				   storyId:[story[@"storyId"] intValue]
					  story:story
					  mode:TGStoryInfoModeReport];
	info.hidesBottomBarWhenPushed = YES;
	[self.navigationController pushViewController:info animated:YES];
}

- (void)editCaption {
	NSDictionary *story = self.currentStory;
	__weak typeof(self) weakSelf = self;
	[TGAlertSheet showInput:@"Edit Caption"
					message:@"Leave it empty to remove the caption."
				placeholder:@"Caption"
					   text:story[@"caption"]
					 action:@"Save"
					 inView:self.view
				   onSubmit:^(NSString *text){
		TGStoryViewerViewController *me = weakSelf;
		if (!me)
			return;
		[[TGClient shared] editStory:[story[@"storyId"] intValue]
							fromChat:me.chatId
								path:nil
							 isVideo:NO
							duration:0
							 caption:text
						  completion:^(BOOL ok, NSString *error){
			if (!ok)
				[TGAlertSheet showMessage:error ?: @"Telegram refused the edit."
									title:@"Edit Story" inView:me.view];
			else
				[me reloadCurrent];
		}];
	}];
}

- (void)changeCover {
	NSDictionary *story = self.currentStory;
	__weak typeof(self) weakSelf = self;
	[TGAlertSheet showInput:@"Change Cover Frame"
					message:@"The frame is a number of seconds from the start."
				placeholder:@"0.0"
					   text:@"0"
					 action:@"Save"
					 inView:self.view
				   onSubmit:^(NSString *text){
		TGStoryViewerViewController *me = weakSelf;
		if (!me)
			return;
		double stamp = text.doubleValue;
		[[TGClient shared] editStoryCover:[story[@"storyId"] intValue]
								 fromChat:me.chatId
						  coverTimestamp:stamp
							  completion:^(BOOL ok, NSString *error){
			[TGAlertSheet showMessage:ok ? @"The cover frame was changed."
					: (error ?: @"Telegram refused that.")
								title:@"Story Cover" inView:me.view];
		}];
	}];
}

- (void)confirmDelete {
	NSDictionary *story = self.currentStory;
	__weak typeof(self) weakSelf = self;
	[TGAlertSheet showConfirm:@"Delete this story?"
						title:@"Delete Story"
					   action:@"Delete"
				  destructive:YES
					   inView:self.view
					onConfirm:^{
		TGStoryViewerViewController *me = weakSelf;
		if (!me)
			return;
		[[TGClient shared] deleteStory:[story[@"storyId"] intValue]
							  fromChat:me.chatId
							completion:^(BOOL ok, NSString *error){
			if (!ok){
				[TGAlertSheet showMessage:error ?: @"Telegram refused the delete."
									title:@"Delete Story" inView:me.view];
				return;
			}
			if (me.onStoriesChanged)
				me.onStoriesChanged();
			[me advance:1];
		}];
	}];
}

- (void)toggleProfile:(BOOL)posted {
	NSDictionary *story = self.currentStory;
	__weak typeof(self) weakSelf = self;
	[[TGClient shared] toggleStory:[story[@"storyId"] intValue]
						  fromChat:self.chatId
				   postedToChatPage:posted
					   completion:^(BOOL ok, NSString *error){
		TGStoryViewerViewController *me = weakSelf;
		if (!me)
			return;
		if (!ok){
			[TGAlertSheet showMessage:error ?: @"Telegram refused that."
								title:@"Story Profile" inView:me.view];
			return;
		}
		NSMutableDictionary *changed = [me.currentStory mutableCopy];
		changed[@"isPostedToChatPage"] = @(posted);
		me.stories[me.index] = changed;
		if (me.onStoriesChanged)
			me.onStoriesChanged();
	}];
}

- (void)pinToChatPage {
	NSDictionary *story = self.currentStory;
	__weak typeof(self) weakSelf = self;
	[[TGClient shared] setPinnedStoryIds:@[story[@"storyId"] ?: @(0)]
								  inChat:self.chatId
							  completion:^(BOOL ok, NSString *error){
		TGStoryViewerViewController *me = weakSelf;
		if (!me)
			return;
		[TGAlertSheet showMessage:ok ? @"The story is pinned to the chat page."
				: (error ?: @"Telegram refused the pin.")
							title:@"Pinned Story" inView:me.view];
	}];
}

- (void)choosePrivacy {
	NSDictionary *story = self.currentStory;
	NSArray *choices = @[@"Everybody", @"My Contacts", @"Close Friends", @"Selected Users"];
	__weak typeof(self) weakSelf = self;
	[TGAlertSheet showChoices:choices title:@"Story Privacy" destructiveIndex:-1
					   inView:self.view onChoice:^(NSInteger choice){
		TGStoryViewerViewController *me = weakSelf;
		if (!me)
			return;
		NSString *mode = choice == 1 ? @"contacts"
				: (choice == 2 ? @"closeFriends"
				: (choice == 3 ? @"selected" : @"everyone"));
		if (choice == 3){
			[TGAlertSheet showInput:@"Selected Users"
							message:@"Comma-separated user ids."
						placeholder:@"123, 456"
							   text:nil
							 action:@"Save"
							 inView:me.view
						 onSubmit:^(NSString *text){
				NSMutableArray *ids = [NSMutableArray array];
				for (NSString *part in [text componentsSeparatedByString:@","]){
					NSString *trimmed = [part stringByTrimmingCharactersInSet:
							[NSCharacterSet whitespaceCharacterSet]];
					if (trimmed.longLongValue > 0)
						[ids addObject:@(trimmed.longLongValue)];
				}
				[me applyPrivacy:mode userIds:ids];
			}];
			return;
		}
		[me applyPrivacy:mode userIds:@[]];
	}];
}

- (void)applyPrivacy:(NSString *)mode userIds:(NSArray *)userIds {
	NSDictionary *story = self.currentStory;
	__weak typeof(self) weakSelf = self;
	[[TGClient shared] setStoryPrivacySettings:[story[@"storyId"] intValue]
									   privacy:mode
									   userIds:userIds
									completion:^(BOOL ok, NSString *error){
		TGStoryViewerViewController *me = weakSelf;
		if (!me)
			return;
		[TGAlertSheet showMessage:ok ? @"The privacy settings were changed."
				: (error ?: @"Telegram refused that.")
							title:@"Story Privacy" inView:me.view];
	}];
}

- (void)addToAlbum {
	NSDictionary *story = self.currentStory;
	TGStoryAlbumsViewController *albums = [[TGStoryAlbumsViewController alloc]
			initWithChatId:self.chatId storyToAdd:[story[@"storyId"] intValue]];
	albums.hidesBottomBarWhenPushed = YES;
	[self.navigationController pushViewController:albums animated:YES];
}

- (void)openAlbums {
	TGStoryAlbumsViewController *albums = [[TGStoryAlbumsViewController alloc]
			initWithChatId:self.chatId storyToAdd:0];
	albums.hidesBottomBarWhenPushed = YES;
	[self.navigationController pushViewController:albums animated:YES];
}

- (void)editBusiness {
	NSDictionary *story = self.currentStory;
	__weak typeof(self) weakSelf = self;
	[TGAlertSheet showInput:@"Edit as Business Story"
					message:@"New caption. Telegram decides whether this account may."
				placeholder:@"Caption"
					   text:story[@"caption"]
					 action:@"Save"
					 inView:self.view
				   onSubmit:^(NSString *text){
		TGStoryViewerViewController *me = weakSelf;
		if (!me)
			return;
		[[TGClient shared] editBusinessStory:[story[@"storyId"] intValue]
									fromChat:me.chatId
										path:nil
									 isVideo:NO
									duration:0
									 caption:text
								  completion:^(BOOL ok, NSString *error){
			[TGAlertSheet showMessage:ok ? @"Telegram accepted the business edit."
					: (error ?: @"Telegram refused the business edit.")
								title:@"Business Story" inView:me.view];
		}];
	}];
}

- (void)deleteBusiness {
	NSDictionary *story = self.currentStory;
	__weak typeof(self) weakSelf = self;
	[TGAlertSheet showConfirm:@"Delete as a business story?"
						title:@"Business Story"
					   action:@"Delete"
				  destructive:YES
					   inView:self.view
					onConfirm:^{
		TGStoryViewerViewController *me = weakSelf;
		if (!me)
			return;
		[[TGClient shared] deleteBusinessStory:[story[@"storyId"] intValue]
									  fromChat:me.chatId
									completion:^(BOOL ok, NSString *error){
			[TGAlertSheet showMessage:ok ? @"Telegram deleted the business story."
					: (error ?: @"Telegram refused the business delete.")
								title:@"Business Story" inView:me.view];
		}];
	}];
}

- (void)openLive {
	NSDictionary *story = self.currentStory;
	TGLiveStoryViewController *live = [[TGLiveStoryViewController alloc]
			initWithChatId:self.chatId
			   groupCallId:[story[@"groupCallId"] intValue]];
	live.hidesBottomBarWhenPushed = YES;
	[self.navigationController pushViewController:live animated:YES];
}

- (void)addStory {
	__weak typeof(self) weakSelf = self;
	[TGStoryComposerViewController openFromController:self chatId:self.chatId
												title:@"Your Story" onPosted:^{
		TGStoryViewerViewController *me = weakSelf;
		if (me.onStoriesChanged)
			me.onStoriesChanged();
	}];
}

- (void)reloadCurrent {
	NSDictionary *story = self.currentStory;
	if (!story[@"storyId"])
		return;
	__weak typeof(self) weakSelf = self;
	[[TGClient shared] story:[story[@"storyId"] intValue]
					fromChat:self.chatId
				  completion:^(NSDictionary *fresh){
		TGStoryViewerViewController *me = weakSelf;
		if (!me || !fresh)
			return;
		me.stories[me.index] = fresh;
		[me showStory:fresh];
	}];
}

@end
