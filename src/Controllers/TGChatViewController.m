#import "TGChatViewController.h"
#import "TGClient.h"
#import "TGTheme.h"
#import "TGIcons.h"
#import "TGForwardPicker.h"
#import "TGVoiceRecorder.h"
#import "TGProfileViewController.h"
#import "TGThemeFile.h"
#import "TGCapabilities.h"
#import <AddressBookUI/AddressBookUI.h>
#import <CoreLocation/CoreLocation.h>
#import <AssetsLibrary/AssetsLibrary.h>
#import <MobileCoreServices/MobileCoreServices.h>
#import <QuartzCore/QuartzCore.h>
#import <MediaPlayer/MediaPlayer.h>
#import <MapKit/MapKit.h>
#import <AVFoundation/AVFoundation.h>
#import "TGVoiceDecoder.h"
#import "UIImage+WebP.h"
#import "TGLottieView.h"
#import "TGCallViewController.h"
#import "TGPopupMenu.h"
#import "TGSnackbar.h"
#import "TGMediaViewer.h"
#import "TGMusicPlayer.h"

#import "TGMessageLayout.h"
#import "TGBubbleCell.h"

#import "TGChatViewControllerInternal.h"

#pragma mark - controller

@implementation TGChatViewController

@synthesize isEditingMessages = _isEditingMessages;
@synthesize selectedMessageIds = _selectedMessageIds;

#pragma mark - layout

- (void)viewDidLoad {
	[super viewDidLoad];

	if ([self respondsToSelector:@selector(setEdgesForExtendedLayout:)])
		self.edgesForExtendedLayout = UIRectEdgeNone;

	[[TGTheme shared] styleNavigationBar:self.navigationController.navigationBar];
	[self buildTitleView];
	self.messages = @[];
	self.layoutCache = [NSMutableDictionary dictionary];
	self.senderAvatars = [NSMutableDictionary dictionary];
	self.senderAvatarsRequested = [NSMutableSet set];
	self.images = [NSMutableDictionary dictionary];
	self.imagesRequested = [NSMutableSet set];
	self.lottiePaths = [NSMutableDictionary dictionary];
	self.maps = [NSMutableDictionary dictionary];
	self.mapsRequested = [NSMutableSet set];
	self.quotes = [NSMutableDictionary dictionary];
	self.quotesRequested = [NSMutableSet set];
	self.selectedMessageIds = [NSMutableSet set];
	self.view.backgroundColor = [[TGTheme shared] chatBackgroundColour];

	CGRect b = self.view.bounds;

	self.table = [[UITableView alloc] initWithFrame:
			CGRectMake(0, 0, b.size.width, b.size.height - kInputHeight)];
	self.table.dataSource = self;
	self.table.delegate = self;
	self.table.separatorStyle = UITableViewCellSeparatorStyleNone;
	self.table.backgroundColor = [UIColor clearColor];
	self.table.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
	// The wallpaper goes behind the table, which is transparent over it.
	self.wallpaperView = [[UIImageView alloc] initWithFrame:self.view.bounds];
	self.wallpaperView.contentMode = UIViewContentModeScaleAspectFill;
	self.wallpaperView.clipsToBounds = YES;
	self.wallpaperView.autoresizingMask = UIViewAutoresizingFlexibleWidth |
										  UIViewAutoresizingFlexibleHeight;
	if ([TGCapabilities canShowWallpaper])
		self.wallpaperView.image = [[TGTheme shared] wallpaper];
	[self.view addSubview:self.wallpaperView];

	// Hold a message for the things a chat needs and a tap cannot carry.
	[self.table addGestureRecognizer:[[UILongPressGestureRecognizer alloc]
			initWithTarget:self action:@selector(messageHeld:)]];

	[self.view addSubview:self.table];

	[self buildInputBar:b];

	[[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(keyboardWillShow:)
			name:UIKeyboardWillShowNotification object:nil];
	[[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(keyboardWillHide:)
			name:UIKeyboardWillHideNotification object:nil];

	// Live updates: append instead of waiting for the screen to be reopened.
	__weak typeof(self) weakSelf = self;
	[TGClient shared].onMessage = ^(int64_t chatId, NSDictionary *message, int64_t deletedId){
		TGChatViewController *me = weakSelf;
		if (!me || chatId != me.chatId)
			return;

		if (message){
			NSMutableArray *nextRaw = [(me.rawMessages ?: me.messages) mutableCopy];
			[nextRaw addObject:message];
			me.rawMessages = nextRaw;
			me.messages = [me groupedMessagesFromMessages:nextRaw];
			[me.table reloadData];
			[me scrollToBottomAnimated:YES];
			[me fetchMissingImages];
			[[TGClient shared] markRead:@[message[@"id"]] inChat:chatId];
			return;
		}
		// deleted or edited - cheapest correct answer is to re-read
		[me reload];
	};

	[[NSNotificationCenter defaultCenter] addObserver:self
			selector:@selector(musicChanged)
				name:TGMusicPlayerChangedNotification object:nil];

	[self reload];
}

/// A two-line header: the chat name with member count or status beneath it,
/// which is what tells you where you are in a group.
- (void)buildTitleView {
	UIView *header = [[UIView alloc] initWithFrame:CGRectMake(0, 0, 200, 40)];

	UILabel *name = [[UILabel alloc] initWithFrame:CGRectMake(0, 1, 200, 20)];
	name.text = self.chatTitle ?: @"Chat";
	name.font = [UIFont boldSystemFontOfSize:17];
	name.textColor = [[TGTheme shared] barTitleColour];
	name.backgroundColor = [UIColor clearColor];
	name.textAlignment = NSTextAlignmentCenter;
	if (![TGTheme shared].isFlat){
		name.shadowColor = [UIColor colorWithWhite:0.0f alpha:0.4f];
		name.shadowOffset = CGSizeMake(0, -1);
	}
	[header addSubview:name];
	self.titleNameLabel = name;

	UILabel *subtitle = [[UILabel alloc] initWithFrame:CGRectMake(0, 21, 200, 14)];
	subtitle.font = [UIFont systemFontOfSize:12];
	subtitle.textColor = [[TGTheme shared] barSubtitleColour];
	subtitle.backgroundColor = [UIColor clearColor];
	subtitle.textAlignment = NSTextAlignmentCenter;
	[header addSubview:subtitle];
	self.titleSubtitleLabel = subtitle;

	header.userInteractionEnabled = YES;
	[header addGestureRecognizer:[[UITapGestureRecognizer alloc]
			initWithTarget:self action:@selector(openProfile)]];
	self.navigationItem.titleView = header;
	[self buildAvatarButton];

	// "typing..." takes the subtitle over while it lasts, then hands it back.
	__weak typeof(self) weakSelf = self;
	__block NSString *restingSubtitle = @"";
	[TGClient shared].onChatAction = ^(int64_t chatId, NSString *action){
		if (chatId != weakSelf.chatId)
			return;
		subtitle.text = action ?: restingSubtitle;
	};

	// An imported theme can arrive while a chat is open - repaint rather than
	// wait for the screen to be pushed again.
	__weak typeof(self) weakChat = self;
	[[NSNotificationCenter defaultCenter] addObserverForName:TGThemeChangedNotification
			object:nil queue:[NSOperationQueue mainQueue]
		 usingBlock:^(NSNotification *note){
		[TGIcons flush];
		TGChatViewController *me = weakChat;
		TGTheme *theme = [TGTheme shared];
		[me.layoutCache removeAllObjects];
		me.view.backgroundColor = [theme chatBackgroundColour];
		me.table.backgroundColor = [UIColor clearColor];
		me.inputBar.backgroundColor = [theme inputBarColour];
		me.input.backgroundColor = [theme listBackgroundColour];
		me.input.textColor = [theme primaryTextColour];
		me.input.layer.borderColor = [theme separatorColour].CGColor;
		me.input.keyboardAppearance = theme.isDark ? UIKeyboardAppearanceDark : UIKeyboardAppearanceLight;
		me.sendButton.backgroundColor = [theme accentColour];
		me.wallpaperView.image = [theme wallpaper];
		me.titleNameLabel.textColor = [theme barTitleColour];
		me.titleSubtitleLabel.textColor = [theme barSubtitleColour];
		if (me.pinnedBannerView) {
			me.pinnedBannerView.backgroundColor = [theme inputBarColour];
			me.pinnedBannerHair.backgroundColor = [theme separatorColour];
		}
		if (me.recordPanel) {
			me.recordPanel.backgroundColor = [theme inputBarColour];
		}
		if (me.editToolbar) {
			me.editToolbar.backgroundColor = [theme inputBarColour];
			[me.editDeleteButton setTitleColor:[theme destructiveColour] forState:UIControlStateNormal];
			[me.editForwardButton setTitleColor:[theme accentColour] forState:UIControlStateNormal];
		}
		[theme styleNavigationBar:me.navigationController.navigationBar];
		[me.table reloadData];
	}];

	[self loadPinnedMessage];
	[self applyPostingRights];

	if (self.chatId == [[TGClient shared] savedMessagesChatId]){
		subtitle.hidden = YES;
		return;
	}

	if (!self.isGroup){
		[[TGClient shared] statusForUser:self.chatId completion:^(NSString *status){
			if (!status.length)
				return;
			restingSubtitle = status;
			if (!subtitle.text.length)
				subtitle.text = status;
		}];
		return;
	}

	[[TGClient shared] memberCountForChat:self.chatId completion:^(NSInteger count){
		if (count > 0){
			restingSubtitle = [NSString stringWithFormat:@"%ld members", (long)count];
			subtitle.text = restingSubtitle;
		}
	}];
}

- (void)buildInputBar:(CGRect)b {
	CGFloat scale = [UIScreen mainScreen].scale;

	self.inputBar = [[UIView alloc] initWithFrame:
			CGRectMake(0, b.size.height - kInputHeight, b.size.width, kInputHeight)];
	self.inputBar.backgroundColor = [[TGTheme shared] inputBarColour];
	self.inputBar.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleTopMargin;

	UIView *hair = [[UIView alloc] initWithFrame:CGRectMake(0, 0, b.size.width, 1)];
	hair.backgroundColor = [[TGTheme shared] separatorColour];
	hair.autoresizingMask = UIViewAutoresizingFlexibleWidth;
	[self.inputBar addSubview:hair];

	CGFloat sendY = (kInputHeight - kSendSide) / 2;

	UIButton *attach = [UIButton buttonWithType:UIButtonTypeCustom];
	attach.frame = CGRectMake(4, sendY, 34, kSendSide);
	[attach setImage:[TGIcons attach] forState:UIControlStateNormal];
	attach.tintColor = [[TGTheme shared] accentColour];
	[attach addTarget:self action:@selector(attachTapped)
			forControlEvents:UIControlEventTouchUpInside];
	[self.inputBar addSubview:attach];

	self.input = [[UITextField alloc] initWithFrame:
			CGRectMake(40, 7, b.size.width - 120, kInputHeight - 14)];
	self.input.borderStyle = UITextBorderStyleNone;
	self.input.background = nil;
	self.input.backgroundColor = [[TGTheme shared] listBackgroundColour];
	self.input.layer.cornerRadius = (kInputHeight - 14) / 2;
	self.input.layer.borderWidth = 1.0f;
	self.input.layer.borderColor = [[TGTheme shared] separatorColour].CGColor;
	self.input.layer.shouldRasterize = YES;
	self.input.layer.rasterizationScale = scale;
	self.input.leftView = [[UIView alloc] initWithFrame:CGRectMake(0, 0, 10, 1)];
	self.input.leftViewMode = UITextFieldViewModeAlways;
	self.input.placeholder = @"Message";
	self.input.textColor = [[TGTheme shared] primaryTextColour];
	self.input.font = [UIFont systemFontOfSize:15];
	self.input.returnKeyType = UIReturnKeySend;
	self.input.keyboardAppearance = [TGTheme shared].isDark
			? UIKeyboardAppearanceAlert : UIKeyboardAppearanceDefault;
	self.input.delegate = self;
	self.input.autoresizingMask = UIViewAutoresizingFlexibleWidth;
	[self.inputBar addSubview:self.input];

	self.sendButton = [UIButton buttonWithType:UIButtonTypeCustom];
	self.sendButton.frame = CGRectMake(b.size.width - kSendSide - 6, sendY,
									   kSendSide, kSendSide);
	self.sendButton.backgroundColor = [[TGTheme shared] accentColour];
	self.sendButton.layer.cornerRadius = kSendSide / 2;
	self.sendButton.layer.shouldRasterize = YES;
	self.sendButton.layer.rasterizationScale = scale;
	[self.sendButton setImage:[TGIcons send] forState:UIControlStateNormal];
	self.sendButton.tintColor = [UIColor whiteColor];
	self.sendButton.imageEdgeInsets = UIEdgeInsetsMake(0, 2, 0, 0);
	self.sendButton.autoresizingMask = UIViewAutoresizingFlexibleLeftMargin;
	[self.sendButton addTarget:self action:@selector(sendTapped)
			forControlEvents:UIControlEventTouchUpInside];
	[self.inputBar addSubview:self.sendButton];

	// A sticker button beside the composer, as clients place it.
	self.stickerButton = [UIButton buttonWithType:UIButtonTypeCustom];
	self.stickerButton.frame = CGRectMake(b.size.width - kSendSide - 42, sendY,
										  30, kSendSide);
	[self.stickerButton setImage:[TGIcons sticker] forState:UIControlStateNormal];
	self.stickerButton.tintColor = [[TGTheme shared] secondaryTextColour];
	self.stickerButton.autoresizingMask = UIViewAutoresizingFlexibleLeftMargin;
	[self.stickerButton addTarget:self action:@selector(toggleStickerPanel)
				 forControlEvents:UIControlEventTouchUpInside];
	[self.inputBar addSubview:self.stickerButton];

	// Hold to record, release to send - the gesture every client uses. It sits
	// where Send is and swaps with it depending on whether anything is typed.
	self.micButton = [UIButton buttonWithType:UIButtonTypeCustom];
	self.micButton.frame = self.sendButton.frame;
	[self.micButton setImage:[TGIcons microphone] forState:UIControlStateNormal];
	self.micButton.tintColor = [[TGTheme shared] secondaryTextColour];
	self.micButton.autoresizingMask = UIViewAutoresizingFlexibleLeftMargin;
	[self.micButton addTarget:self action:@selector(recordStart)
			 forControlEvents:UIControlEventTouchDown];
	[self.micButton addTarget:self action:@selector(recordFinish)
			 forControlEvents:UIControlEventTouchUpInside];
	[self.micButton addTarget:self action:@selector(recordCancel)
			 forControlEvents:UIControlEventTouchUpOutside | UIControlEventTouchCancel];
	[self.inputBar addSubview:self.micButton];

	[self.input addTarget:self action:@selector(inputChanged)
		 forControlEvents:UIControlEventEditingChanged];
	[self inputChanged];

	[self.view addSubview:self.inputBar];
}

/// A voice note going on playing after you have left the chat is the one thing
/// nobody expects, and the timer would outlive the screen it repaints.
- (void)viewWillDisappear:(BOOL)animated {
	[super viewWillDisappear:animated];
	// Music deliberately survives this: it goes on in the background, which is
	// the whole reason it has a player of its own.
	if (self.voicePlayer)
		[self stopPlayback];
	[self stopVideoNote];
	// A pending delete must not be lost with the screen, and a menu must not
	// outlive the messages it was opened over.
	[TGSnackbar commitNow];
	[TGPopupMenu dismiss];
}

- (void)dealloc {
	[self.playbackTimer invalidate];
	[[NSNotificationCenter defaultCenter] removeObserver:self];
}

#pragma mark - data

- (void)reloadTableDebounced {
	[NSObject cancelPreviousPerformRequestsWithTarget:self.table selector:@selector(reloadData) object:nil];
	[self.table performSelector:@selector(reloadData) withObject:nil afterDelay:0.05];
}

- (NSDictionary *)compositeAlbumMessageFromMessages:(NSArray *)albumMsgs {
	if (!albumMsgs.count) return @{};
	NSDictionary *lead = albumMsgs.firstObject;
	NSMutableDictionary *comp = [lead mutableCopy];
	comp[@"isAlbum"] = @(YES);
	comp[@"albumMessages"] = albumMsgs;
	comp[@"albumCount"] = @(albumMsgs.count);

	for (NSDictionary *sub in albumMsgs) {
		if ([sub[@"text"] length]) {
			comp[@"text"] = sub[@"text"];
			comp[@"entities"] = sub[@"entities"] ?: @[];
			break;
		}
	}
	return comp;
}

- (NSArray *)groupedMessagesFromMessages:(NSArray *)rawMessages {
	if (!rawMessages.count) return @[];
	NSMutableArray *grouped = [NSMutableArray arrayWithCapacity:rawMessages.count];
	NSMutableArray *currentAlbum = nil;
	NSString *currentAlbumId = nil;

	for (NSDictionary *m in rawMessages) {
		NSString *albumId = m[@"albumId"];
		BOOL hasAlbum = (albumId.length > 0 && ![albumId isEqualToString:@"0"]);

		if (hasAlbum) {
			if (currentAlbum && [currentAlbumId isEqualToString:albumId]) {
				[currentAlbum addObject:m];
				continue;
			} else {
				if (currentAlbum.count > 1) {
					[grouped addObject:[self compositeAlbumMessageFromMessages:currentAlbum]];
				} else if (currentAlbum.count == 1) {
					[grouped addObject:currentAlbum.firstObject];
				}
				currentAlbum = [NSMutableArray arrayWithObject:m];
				currentAlbumId = albumId;
				continue;
			}
		}

		if (currentAlbum) {
			if (currentAlbum.count > 1) {
				[grouped addObject:[self compositeAlbumMessageFromMessages:currentAlbum]];
			} else if (currentAlbum.count == 1) {
				[grouped addObject:currentAlbum.firstObject];
			}
			currentAlbum = nil;
			currentAlbumId = nil;
		}

		[grouped addObject:m];
	}

	if (currentAlbum) {
		if (currentAlbum.count > 1) {
			[grouped addObject:[self compositeAlbumMessageFromMessages:currentAlbum]];
		} else if (currentAlbum.count == 1) {
			[grouped addObject:currentAlbum.firstObject];
		}
	}

	return grouped;
}

- (void)reload {
	__weak typeof(self) weakSelf = self;
	[[TGClient shared] historyForChat:self.chatId thread:self.threadId limit:60 completion:^(NSArray *messages){
		TGChatViewController *me = weakSelf;
		if (!me)
			return;
		me.rawMessages = messages;
		me.messages = [me groupedMessagesFromMessages:messages];
		// hold the bottom until the media has settled
		me.anchorToBottom = YES;
		dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(6.0 * NSEC_PER_SEC)),
				dispatch_get_main_queue(), ^{ me.anchorToBottom = NO; });
		// kinds only - the content is the user's, the log is read remotely
		NSMutableArray *kinds = [NSMutableArray array];
		for (NSDictionary *m in messages)
			[kinds addObject:m[@"kind"] ?: @"?"];
		NSLog(@"TDLIB HISTORY: %lu msgs: %@",
				(unsigned long)messages.count, [kinds componentsJoinedByString:@", "]);
		[me.table reloadData];
		[me scrollToBottomAnimated:NO];
		[me fetchMissingImages];
		[me resolveUnknownSenders];
		[me fetchMissingQuotes];

		NSMutableArray *ids = [NSMutableArray array];
		for (NSDictionary *m in messages)
			[ids addObject:m[@"id"]];
		[[TGClient shared] markRead:ids inChat:me.chatId];
	}];
}

/// A location gets a drawn card, not a real map: MKMapSnapshotter fires no
/// completion at all on iOS 7 because Apple's tile servers stopped answering
/// clients this old. So this is a stylised plan view with a pin - honest about
/// being a placeholder, and it works with no network.
- (UIImage *)mapCardForLatitude:(double)lat longitude:(double)lon {
	CGSize size = CGSizeMake(220, 130);
	UIGraphicsBeginImageContextWithOptions(size, YES, 0);
	CGContextRef ctx = UIGraphicsGetCurrentContext();

	// paper
	CGContextSetRGBFillColor(ctx, 0.90f, 0.91f, 0.87f, 1.0f);
	CGContextFillRect(ctx, CGRectMake(0, 0, size.width, size.height));

	// a few roads, placed from the coordinates so different places differ
	CGContextSetRGBStrokeColor(ctx, 1.0f, 1.0f, 1.0f, 1.0f);
	CGContextSetLineWidth(ctx, 6);
	double seed = fabs(lat * 1000 + lon * 1000);
	for (int i = 0; i < 3; i++){
		double y = 20 + fmod(seed * (i + 3), 90);
		CGContextMoveToPoint(ctx, 0, y);
		CGContextAddLineToPoint(ctx, size.width, y - 12 + fmod(seed * (i + 1), 24));
		CGContextStrokePath(ctx);

		double x = 20 + fmod(seed * (i + 5), 180);
		CGContextMoveToPoint(ctx, x, 0);
		CGContextAddLineToPoint(ctx, x - 10 + fmod(seed * (i + 2), 20), size.height);
		CGContextStrokePath(ctx);
	}

	// greenery
	CGContextSetRGBFillColor(ctx, 0.78f, 0.86f, 0.74f, 1.0f);
	CGContextFillEllipseInRect(ctx, CGRectMake(fmod(seed, 120), fmod(seed, 60), 70, 44));

	// the pin, centred
	CGPoint p = CGPointMake(size.width / 2, size.height / 2);
	CGContextSetRGBFillColor(ctx, 0.0f, 0.0f, 0.0f, 0.25f);
	CGContextFillEllipseInRect(ctx, CGRectMake(p.x - 7, p.y + 6, 14, 5));
	CGContextSetRGBFillColor(ctx, 0.85f, 0.15f, 0.15f, 1.0f);
	CGContextFillEllipseInRect(ctx, CGRectMake(p.x - 8, p.y - 16, 16, 16));
	CGContextMoveToPoint(ctx, p.x - 5, p.y - 4);
	CGContextAddLineToPoint(ctx, p.x + 5, p.y - 4);
	CGContextAddLineToPoint(ctx, p.x, p.y + 8);
	CGContextClosePath(ctx);
	CGContextFillPath(ctx);
	CGContextSetRGBFillColor(ctx, 1, 1, 1, 1);
	CGContextFillEllipseInRect(ctx, CGRectMake(p.x - 3, p.y - 11, 6, 6));

	// coordinates, so the card still carries the real information
	NSString *coords = [NSString stringWithFormat:@"%.4f, %.4f", lat, lon];
	CGContextSetRGBFillColor(ctx, 0.25f, 0.27f, 0.24f, 1.0f);
	[coords drawAtPoint:CGPointMake(8, size.height - 18)
			   withFont:[UIFont systemFontOfSize:12]];

	UIImage *card = UIGraphicsGetImageFromCurrentImageContext();
	UIGraphicsEndImageContext();
	return card;
}

- (void)fetchMissingMaps {
	for (NSDictionary *m in self.messages){
		NSNumber *lat = m[@"lat"], *lon = m[@"lon"];
		if (![lat isKindOfClass:NSNumber.class] || ![lon isKindOfClass:NSNumber.class])
			continue;
		NSNumber *key = m[@"id"];
		if (self.maps[key])
			continue;
		self.maps[key] = [self mapCardForLatitude:lat.doubleValue
										longitude:lon.doubleValue];
	}
}

/// Group messages need a name over the bubble, and TDLib only volunteers
/// users it happens to have sent already - the rest have to be asked for.
- (void)resolveUnknownSenders {
	__weak typeof(self) weakSelf = self;
	NSMutableSet *wanted = [NSMutableSet set];
	for (NSDictionary *m in self.messages){
		int64_t sender = [m[@"senderId"] longLongValue];
		if (sender != 0 && ![[TGClient shared] nameForUserId:sender])
			[wanted addObject:@(sender)];
	}

	for (NSNumber *uid in wanted){
		[[TGClient shared] ensureUserName:uid.longLongValue completion:^{
			[weakSelf reloadTableDebounced];
		}];
	}
}

/// A reply shows what it answers. TDLib only inlines the quote sometimes, so
/// the original is fetched when it does not.
- (void)fetchMissingQuotes {
	__weak typeof(self) weakSelf = self;
	for (NSDictionary *m in self.messages){
		NSNumber *replyId = m[@"replyId"];
		if (![replyId isKindOfClass:NSNumber.class])
			continue;
		if ([m[@"replyText"] length] || self.quotes[replyId] ||
			[self.quotesRequested containsObject:replyId])
			continue;
		[self.quotesRequested addObject:replyId];

		[[TGClient shared] messageWithId:replyId.longLongValue
								  inChat:self.chatId
							  completion:^(NSDictionary *m){
			TGChatViewController *me = weakSelf;
			if (!me || !m)
				return;
			me.quotes[replyId] = m;
			[me reloadTableDebounced];
		}];
	}
}

- (void)fetchMissingImages {
	__weak typeof(self) weakSelf = self;
	CGFloat screenScale = [UIScreen mainScreen].scale;   // read here, used off-thread
	NSMutableArray *allMsgs = [NSMutableArray array];
	for (NSDictionary *m in self.messages){
		if ([m[@"isAlbum"] boolValue] && [m[@"albumMessages"] isKindOfClass:[NSArray class]]) {
			[allMsgs addObjectsFromArray:m[@"albumMessages"]];
		} else {
			[allMsgs addObject:m];
		}
	}

	// Animated stickers need the .tgs itself, not the still thumbnail.
	for (NSDictionary *m in allMsgs){
		if (![m[@"docName"] isEqualToString:@"tgs"])
			continue;
		NSNumber *docId = m[@"docId"];
		if (![docId isKindOfClass:NSNumber.class] || self.lottiePaths[docId])
			continue;
		if ([self.imagesRequested containsObject:docId])
			continue;
		[self.imagesRequested addObject:docId];

		[[TGClient shared] downloadFile:[docId integerValue] completion:^(NSString *path){
			TGChatViewController *me = weakSelf;
			if (!me || !path)
				return;
			me.lottiePaths[docId] = path;
			[me.layoutCache removeAllObjects];
			[me reloadTableDebounced];
			if (me.anchorToBottom)
				[me scrollToBottomAnimated:NO];
		}];
	}

	for (NSDictionary *m in allMsgs){
		NSNumber *fileId = m[@"photoId"];
		if (![fileId isKindOfClass:NSNumber.class])
			continue;
		if (self.images[fileId] || [self.imagesRequested containsObject:fileId])
			continue;
		[self.imagesRequested addObject:fileId];

		[[TGClient shared] downloadFile:[fileId integerValue] completion:^(NSString *path){
			if (!path) {
				[weakSelf.imagesRequested removeObject:fileId];
				return;
			}
			dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_BACKGROUND, 0), ^{
				// Stickers arrive as WebP, which UIImage does not know on iOS 7.
				UIImage *img = [UIImage imageWithContentsOfFile:path];
				if (!img && [path.pathExtension.lowercaseString isEqualToString:@"webp"])
					img = [UIImage convertFromWebP:path compressedData:nil error:nil];

				if (!img) {
					NSLog(@"image: cannot decode %@", path.lastPathComponent);
					dispatch_async(dispatch_get_main_queue(), ^{
						[weakSelf.imagesRequested removeObject:fileId];
					});
					return;
				}

				// A bubble never shows more than kImageMax across, and the file
				// off the wire can be ten times that - decoding it full size and
				// letting the main thread resample it on every frame is what made
				// a chat with pictures stutter.
				img = [TGIcons decodedImage:img
								fittingSize:CGSizeMake(kImageMax, kImageMax)
									   fill:NO scale:screenScale];

				dispatch_async(dispatch_get_main_queue(), ^{
					TGChatViewController *me = weakSelf;
					if (!me) return;
					me.images[fileId] = img;
					[me.layoutCache removeAllObjects];
					[me reloadTableDebounced];
					// Rows grow when an image arrives, pushing the newest messages
					// below the fold, so re-anchor to the bottom while first showing.
					if (me.anchorToBottom)
						[me scrollToBottomAnimated:NO];
				});
			});
		}];
	}
}

- (void)scrollToBottomAnimated:(BOOL)animated {
	if (!self.messages.count)
		return;
	NSIndexPath *last = [NSIndexPath indexPathForRow:self.messages.count - 1 inSection:0];
	[self.table scrollToRowAtIndexPath:last
					  atScrollPosition:UITableViewScrollPositionBottom animated:animated];
}

#pragma mark - sending

- (void)sendTapped {
	NSString *text = [self.input.text stringByTrimmingCharactersInSet:
			[NSCharacterSet whitespaceAndNewlineCharacterSet]];
	if (!text.length)
		return;

	if (self.editingId != 0)
		[[TGClient shared] editMessage:self.editingId inChat:self.chatId text:text];
	else
		[[TGClient shared] sendText:text toChat:self.chatId
							 thread:self.threadId replyTo:self.replyToId];

	[self clearComposeState];

	// TDLib echoes the message back as an update; refresh shortly after.
	dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(1.0 * NSEC_PER_SEC)),
			dispatch_get_main_queue(), ^{
		[self reload];
	});
}

/// Telegram puts the chat's picture top right, and it opens the profile.
- (void)buildAvatarButton {
	// 42dp in their header, which is 37 here and still clears a 44pt bar.
	CGFloat side = 37;
	UIButton *button = [UIButton buttonWithType:UIButtonTypeCustom];
	button.frame = CGRectMake(0, 0, side, side);
	button.layer.cornerRadius = side / 2;
	button.clipsToBounds = YES;
	[button addTarget:self action:@selector(openProfile)
	 forControlEvents:UIControlEventTouchUpInside];

	NSString *title = self.chatTitle ?: @"";
	BOOL isSaved = (self.chatId == [[TGClient shared] savedMessagesChatId]);
	[button setImage:(isSaved
			? [TGIcons savedMessagesAvatarOfSide:side]
			: [TGIcons avatarWithInitials:
					(title.length ? [title substringToIndex:1].uppercaseString : @"?")
									 size:side colourId:self.chatId])
			forState:UIControlStateNormal];

	self.navigationItem.rightBarButtonItem =
			[[UIBarButtonItem alloc] initWithCustomView:button];

	// Your own photo is not what Saved Messages is known by; the bookmark set
	// above stays.
	if (isSaved)
		return;

	NSNumber *fileId = [[TGClient shared] photoFileIdForChat:self.chatId];
	if (!fileId)
		return;
	CGFloat screenScale = [UIScreen mainScreen].scale;
	[[TGClient shared] downloadFile:fileId.integerValue completion:^(NSString *path){
		if (!path.length) return;
		dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_LOW, 0), ^{
			UIImage *photo = [TGIcons decodedImage:[UIImage imageWithContentsOfFile:path]
									   fittingSize:CGSizeMake(side, side)
											  fill:YES scale:screenScale];
			if (!photo) return;
			dispatch_async(dispatch_get_main_queue(), ^{
				[button setImage:photo forState:UIControlStateNormal];
			});
		});
	}];
}

- (void)openProfile {
	// A private chat id is the user id, which is what the profile needs to
	// look up a photo and a phone number; a group has no single user.
	int64_t userId = self.isGroup ? 0 : self.chatId;
	TGProfileViewController *profile = [[TGProfileViewController alloc]
			initWithChatId:self.chatId userId:userId title:self.chatTitle];
	__weak typeof(self) weakSelf = self;
	profile.onSearchTapped = ^{
		[weakSelf.navigationController popViewControllerAnimated:YES];
		[weakSelf toggleChatSearch];
	};
	[self.navigationController pushViewController:profile animated:YES];
}

/// A channel you only follow has no composer; it gets a mute switch instead,
/// which is what the bottom of a channel offers in every client.
- (void)applyPostingRights {
	__weak typeof(self) weakSelf = self;
	[[TGClient shared] canSendInChat:self.chatId completion:^(BOOL canSend, BOOL isChannel){
		TGChatViewController *me = weakSelf;
		if (!me || canSend)
			return;

		me.inputBar.hidden = YES;

		CGRect b = me.view.bounds;
		UIButton *mute = [UIButton buttonWithType:UIButtonTypeCustom];
		mute.frame = me.inputBar.frame;
		mute.backgroundColor = [[TGTheme shared] inputBarColour];
		mute.autoresizingMask = UIViewAutoresizingFlexibleWidth |
								UIViewAutoresizingFlexibleTopMargin;
		[mute setTitleColor:[[TGTheme shared] accentColour] forState:UIControlStateNormal];
		mute.titleLabel.font = [UIFont systemFontOfSize:15];
		[mute setTitle:(isChannel ? @"Mute channel" : @"Mute chat")
			  forState:UIControlStateNormal];
		[mute addTarget:me action:@selector(muteFromChat:)
	   forControlEvents:UIControlEventTouchUpInside];
		[me.view addSubview:mute];
		(void)b;
	}];
}

- (void)muteFromChat:(UIButton *)button {
	BOOL muting = [button.currentTitle hasPrefix:@"Mute"];
	[[TGClient shared] setChat:self.chatId muted:muting];
	[button setTitle:(muting ? @"Unmute" : @"Mute channel") forState:UIControlStateNormal];
}

/// YES when this message continues the album the one before it started.
- (BOOL)continuesAlbumAtRow:(NSInteger)row {
	NSString *album = self.messages[row][@"albumId"];
	if (!album.length || [album isEqualToString:@"0"] || row == 0)
		return NO;
	return [self.messages[row - 1][@"albumId"] isEqualToString:album];
}

/// YES when the next message belongs to the same album, so this one should not
/// carry the timestamp - only the last of a block does.
- (BOOL)albumContinuesAfterRow:(NSInteger)row {
	NSString *album = self.messages[row][@"albumId"];
	if (!album.length || [album isEqualToString:@"0"] ||
		row + 1 >= (NSInteger)self.messages.count)
		return NO;
	return [self.messages[row + 1][@"albumId"] isEqualToString:album];
}

/// Copy the received file into Documents first: TDLib owns its cache and can
/// delete it, and a theme has to survive the next launch.
- (void)applyThemeFromMessage:(NSDictionary *)m {
	NSNumber *docId = m[@"docId"];
	if (![docId isKindOfClass:NSNumber.class])
		return;

	NSString *name = m[@"docName"] ?: @"theme.tgios-theme";
	[self beginDownloadHUDForFile:[docId integerValue]];
	[[TGClient shared] downloadFile:[docId integerValue] completion:^(NSString *path){
		[self endDownloadHUD];
		if (!path)
			return;

		NSString *documents = [NSSearchPathForDirectoriesInDomains(
				NSDocumentDirectory, NSUserDomainMask, YES) firstObject];
		NSString *saved = [documents stringByAppendingPathComponent:name];
		[[NSFileManager defaultManager] removeItemAtPath:saved error:nil];
		[[NSFileManager defaultManager] copyItemAtPath:path toPath:saved error:nil];

		// Through the one theme list, so a file adopted from a chat clears
		// whatever built-in theme was in force rather than layering over it.
		BOOL applied = [[TGTheme shared] selectThemeId:
				[@"file:" stringByAppendingString:saved.lastPathComponent]];
		UIAlertView *alert = [[UIAlertView alloc] initWithTitle:@"Theme"
				message:(applied ? [NSString stringWithFormat:@"%@ applied.",
						[TGTheme shared].importedName ?: name]
								 : @"This file could not be read as a Telegram theme.")
			   delegate:nil cancelButtonTitle:@"OK" otherButtonTitles:nil];
		[alert show];
	}];
}

/// Scroll to a message already loaded, and flash it so the eye finds it.
/// NO when the message is not in the loaded window.
- (BOOL)scrollToMessageId:(int64_t)messageId {
	for (NSInteger row = 0; row < (NSInteger)self.messages.count; row++){
		if ([self.messages[row][@"id"] longLongValue] != messageId)
			continue;

		NSIndexPath *path = [NSIndexPath indexPathForRow:row inSection:0];
		[self.table scrollToRowAtIndexPath:path
						  atScrollPosition:UITableViewScrollPositionMiddle
								  animated:YES];
		UITableViewCell *cell = [self.table cellForRowAtIndexPath:path];
		cell.contentView.alpha = 0.3f;
		[UIView animateWithDuration:0.6 animations:^{ cell.contentView.alpha = 1.0f; }];
		return YES;
	}
	return NO;
}

/// The option that was tapped votes for itself. Which poll it belongs to comes
/// from the cell it sits in, because a button knows nothing about messages.
- (void)pollOptionTapped:(UIButton *)option {
	UIView *view = option;
	while (view && ![view isKindOfClass:TGBubbleCell.class])
		view = view.superview;
	TGBubbleCell *cell = (TGBubbleCell *)view;
	if (!cell || !cell.pollMessageId)
		return;

	NSInteger index = option.tag - 0x9100;
	[[TGClient shared] votePoll:cell.pollMessageId
						 inChat:self.chatId
						options:@[@(index)]];

	// TDLib answers with an updated message; re-read so the shares move.
	dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(1.0 * NSEC_PER_SEC)),
			dispatch_get_main_queue(), ^{ [self reload]; });
}

#pragma mark - download progress

/// A video or a document is megabytes over a 4S connection; without this the
/// tap looks like it did nothing.
- (void)beginDownloadHUDForFile:(NSInteger)fileId {
	self.downloadingFileId = fileId;

	if (!self.downloadHUD){
		self.downloadHUD = [[UILabel alloc] initWithFrame:CGRectMake(0, 0, 110, 40)];
		self.downloadHUD.center = CGPointMake(self.view.bounds.size.width / 2,
											  self.view.bounds.size.height / 2);
		self.downloadHUD.textAlignment = NSTextAlignmentCenter;
		self.downloadHUD.font = [UIFont boldSystemFontOfSize:15];
		self.downloadHUD.textColor = [[TGTheme shared] hudTextColour];
		self.downloadHUD.backgroundColor = [[TGTheme shared] hudBackgroundColour];
		self.downloadHUD.layer.cornerRadius = 8;
		self.downloadHUD.clipsToBounds = YES;
	}
	self.downloadHUD.text = @"0%";
	self.downloadHUD.hidden = NO;
	[self.view addSubview:self.downloadHUD];

	__weak typeof(self) weakSelf = self;
	[TGClient shared].onFileProgress = ^(NSInteger updatedId, float progress){
		TGChatViewController *me = weakSelf;
		if (!me || updatedId != me.downloadingFileId)
			return;
		me.downloadHUD.text = [NSString stringWithFormat:@"%d%%", (int)(progress * 100)];
	};
}

- (void)endDownloadHUD {
	self.downloadingFileId = 0;
	self.downloadHUD.hidden = YES;
	[self.downloadHUD removeFromSuperview];
}

#pragma mark - pinned message

/// A strip under the navigation bar, the way clients surface what is pinned.
- (void)loadPinnedMessage {
	__weak typeof(self) weakSelf = self;
	[[TGClient shared] pinnedMessageForChat:self.chatId completion:^(NSDictionary *m){
		NSString *text = m[@"text"];
		if (!text.length)
			return;
		[weakSelf showPinnedBanner:text];
	}];
}

- (void)showPinnedBanner:(NSString *)text {
	CGRect b = self.view.bounds;
	TGTheme *theme = [TGTheme shared];
	UIView *banner = [[UIView alloc] initWithFrame:CGRectMake(0, 0, b.size.width, 34)];
	banner.backgroundColor = [theme inputBarColour];
	banner.autoresizingMask = UIViewAutoresizingFlexibleWidth;

	UIView *stripe = [[UIView alloc] initWithFrame:CGRectMake(8, 5, 2, 24)];
	stripe.backgroundColor = [theme accentColour];
	[banner addSubview:stripe];

	UILabel *label = [[UILabel alloc] initWithFrame:CGRectMake(16, 2, b.size.width - 24, 14)];
	label.text = @"Pinned message";
	label.font = [UIFont boldSystemFontOfSize:11];
	label.textColor = [theme accentColour];
	label.backgroundColor = [UIColor clearColor];
	[banner addSubview:label];

	UILabel *body = [[UILabel alloc] initWithFrame:CGRectMake(16, 16, b.size.width - 24, 16)];
	body.text = text;
	body.font = [UIFont systemFontOfSize:13];
	body.textColor = [theme primaryTextColour];
	body.backgroundColor = [UIColor clearColor];
	body.autoresizingMask = UIViewAutoresizingFlexibleWidth;
	[banner addSubview:body];

	UIView *hair = [[UIView alloc] initWithFrame:CGRectMake(0, 33, b.size.width, 1)];
	hair.backgroundColor = [theme separatorColour];
	hair.autoresizingMask = UIViewAutoresizingFlexibleWidth;
	[banner addSubview:hair];

	[self.view addSubview:banner];
	self.pinnedBannerView = banner;
	self.pinnedBannerHair = hair;

	// Push the message list down so the banner does not cover the first row.
	UIEdgeInsets insets = self.table.contentInset;
	insets.top += 34;
	self.table.contentInset = insets;
	self.table.scrollIndicatorInsets = insets;
}


/// Cached initials until the real photo arrives; drawing it every row would
/// re-download and re-decode on every scroll.
- (UIImage *)avatarForUser:(int64_t)userId name:(NSString *)name {
	NSNumber *key = @(userId);
	UIImage *cached = self.senderAvatars[key];
	if (cached)
		return cached;

	NSString *initials = name.length ? [name substringToIndex:1] : @"?";
	UIImage *placeholder = [TGIcons avatarWithInitials:initials.uppercaseString
												  size:kAvatarSide
											  colourId:userId];
	self.senderAvatars[key] = placeholder;

	if ([self.senderAvatarsRequested containsObject:key])
		return placeholder;
	[self.senderAvatarsRequested addObject:key];

	__weak typeof(self) weakSelf = self;
	void (^fetch)(NSNumber *) = ^(NSNumber *fileId){
		if (!fileId)
			return;
		CGFloat screenScale = [UIScreen mainScreen].scale;
		[[TGClient shared] downloadFile:fileId.integerValue completion:^(NSString *path){
			if (!path.length) return;
			dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_LOW, 0), ^{
				UIImage *photo = [TGIcons decodedImage:[UIImage imageWithContentsOfFile:path]
										   fittingSize:CGSizeMake(kAvatarSide, kAvatarSide)
												  fill:YES scale:screenScale];
				if (!photo) return;
				dispatch_async(dispatch_get_main_queue(), ^{
					weakSelf.senderAvatars[key] = photo;
					// One reload per arriving avatar reloaded the whole table
					// once per participant in a busy group.
					[weakSelf reloadTableDebounced];
				});
			});
		}];
	};

	NSNumber *cachedFile = [[TGClient shared] photoFileIdForUserId:userId];
	if (cachedFile){
		fetch(cachedFile);
		return placeholder;
	}

	// TDLib only volunteers updateUser for people it has reason to send; the
	// rest of a group's members have to be asked for.
	[[TGClient shared] userInfo:userId completion:^(NSDictionary *user){
		fetch(user[@"profile_photo"][@"small"][@"id"]);
	}];
	return placeholder;
}

#pragma mark - compose banner

/// Back to composing a plain message: no reply, no edit, no banner. Also
/// missing, and reached from the recorder and from the banner's own cancel.
- (void)clearComposeState {
	self.replyToId = 0;
	self.editingId = 0;
	self.composeBanner.hidden = YES;
	[self inputChanged];
}

/// A strip above the composer saying what the next message will be: a reply,
/// an edit, or a recording in progress. Declared and used from three places
/// but never written, so holding the microphone brought the app down.
- (void)showComposeBanner:(NSString *)text {
	if (!self.composeBanner){
		CGRect b = self.view.bounds;
		self.composeBanner = [[UIView alloc] initWithFrame:
				CGRectMake(0, CGRectGetMinY(self.inputBar.frame) - 28, b.size.width, 28)];
		self.composeBanner.backgroundColor = [[TGTheme shared] inputBarColour];
		self.composeBanner.autoresizingMask = UIViewAutoresizingFlexibleWidth |
											  UIViewAutoresizingFlexibleTopMargin;

		UILabel *label = [[UILabel alloc] initWithFrame:
				CGRectMake(10, 4, b.size.width - 50, 20)];
		label.font = [UIFont systemFontOfSize:13];
		label.textColor = [[TGTheme shared] accentColour];
		label.backgroundColor = [UIColor clearColor];
		label.autoresizingMask = UIViewAutoresizingFlexibleWidth;
		[self.composeBanner addSubview:label];

		UIButton *cancel = [UIButton buttonWithType:UIButtonTypeCustom];
		cancel.frame = CGRectMake(b.size.width - 40, 0, 40, 28);
		cancel.autoresizingMask = UIViewAutoresizingFlexibleLeftMargin;
		[cancel setTitle:@"\u00d7" forState:UIControlStateNormal];
		[cancel setTitleColor:[[TGTheme shared] secondaryTextColour]
					 forState:UIControlStateNormal];
		cancel.titleLabel.font = [UIFont systemFontOfSize:22];
		[cancel addTarget:self action:@selector(clearComposeState)
		 forControlEvents:UIControlEventTouchUpInside];
		[self.composeBanner addSubview:cancel];

		[self.view addSubview:self.composeBanner];
	}

	UILabel *label = (UILabel *)[self.composeBanner.subviews firstObject];
	if ([label isKindOfClass:UILabel.class])
		label.text = text;
	self.composeBanner.hidden = NO;
}

#pragma mark - stickers

/// A strip of the stickers used lately. A full sticker-set browser is a screen
/// of its own; the recents are what a chat reaches for.
- (void)toggleStickerPanel {
	if (self.stickerPanel){
		[self.stickerPanel removeFromSuperview];
		self.stickerPanel = nil;
		return;
	}

	CGRect b = self.view.bounds;
	CGFloat height = 96;
	UIScrollView *panel = [[UIScrollView alloc] initWithFrame:
			CGRectMake(0, CGRectGetMinY(self.inputBar.frame) - height, b.size.width, height)];
	panel.backgroundColor = [[TGTheme shared] inputBarColour];
	panel.autoresizingMask = UIViewAutoresizingFlexibleWidth |
							 UIViewAutoresizingFlexibleTopMargin;
	[self.view addSubview:panel];
	self.stickerPanel = panel;

	__weak typeof(self) weakSelf = self;
	[[TGClient shared] recentStickersWithCompletion:^(NSArray *stickers){
		TGChatViewController *me = weakSelf;
		if (!me || me.stickerPanel != panel)
			return;
		[me fillStickerPanel:panel with:stickers];
	}];
}

- (void)fillStickerPanel:(UIScrollView *)panel with:(NSArray *)stickers {
	CGFloat side = 72, gap = 6, x = gap;
	for (NSDictionary *sticker in stickers){
		UIButton *button = [UIButton buttonWithType:UIButtonTypeCustom];
		button.frame = CGRectMake(x, 12, side, side);
		button.tag = [sticker[@"fileId"] integerValue];
		[button addTarget:self action:@selector(stickerTapped:)
		 forControlEvents:UIControlEventTouchUpInside];
		// Until the picture is decoded the emoji stands in, so the strip is
		// usable immediately rather than a row of blanks.
		[button setTitle:sticker[@"emoji"] forState:UIControlStateNormal];
		button.titleLabel.font = TGEmojiFontOfSize(34) ?: [UIFont systemFontOfSize:34];
		[panel addSubview:button];
		x += side + gap;

		if ([sticker[@"isAnimated"] boolValue])
			continue;
		[[TGClient shared] downloadFile:[sticker[@"fileId"] integerValue]
							 completion:^(NSString *path){
			UIImage *image = path ? [UIImage convertFromWebP:path
											  compressedData:nil error:nil] : nil;
			if (!image)
				return;
			[button setTitle:@"" forState:UIControlStateNormal];
			[button setImage:image forState:UIControlStateNormal];
			button.imageView.contentMode = UIViewContentModeScaleAspectFit;
		}];
	}
	panel.contentSize = CGSizeMake(x, panel.bounds.size.height);
}

- (void)stickerTapped:(UIButton *)button {
	[[TGClient shared] sendStickerWithFileId:button.tag
									  toChat:self.chatId
									  thread:self.threadId];
	[self toggleStickerPanel];
}


#pragma mark - attachments

static const NSInteger kAttachSheetTag  = 41;
static const NSInteger kMessageSheetTag = 42;

- (void)attachTapped {
	UIActionSheet *sheet = [[UIActionSheet alloc] initWithTitle:nil
													  delegate:self
											 cancelButtonTitle:nil
										destructiveButtonTitle:nil
											 otherButtonTitles:@"Photo or Video",
														   @"Location",
														   @"Contact", nil];
	sheet.cancelButtonIndex = [sheet addButtonWithTitle:@"Cancel"];
	sheet.tag = kAttachSheetTag;
	[sheet showInView:self.view];
}

- (void)actionSheet:(UIActionSheet *)sheet clickedButtonAtIndex:(NSInteger)index {
	if (index == sheet.cancelButtonIndex)
		return;

	if (sheet.tag == 0xDE1E) {
		NSArray *ids = self.pendingDeleteMessageIds;
		self.pendingDeleteMessageIds = nil;
		if (index == sheet.cancelButtonIndex || !ids.count)
			return;

		BOOL isSaved = (self.chatId == [[TGClient shared] savedMessagesChatId]);
		if (isSaved) {
			if (index == 0) {
				[self executeDeleteMessages:ids revoke:YES];
			}
		} else {
			if (index == 0) {
				// Delete for both / Delete for everyone
				[self executeDeleteMessages:ids revoke:YES];
			} else if (index == 1) {
				// Delete for me
				[self executeDeleteMessages:ids revoke:NO];
			}
		}
		return;
	}

	if (sheet.tag == kMessageSheetTag){
		[self runMessageAction:[sheet buttonTitleAtIndex:index]];
		return;
	}
	if (sheet.tag == 0xC047){
		NSDictionary *m = self.contactActionMessage;
		NSDictionary *contact = [m[@"contact"] isKindOfClass:NSDictionary.class] ? m[@"contact"] : nil;
		NSString *phone = contact[@"phoneNumber"] ?: @"";
		if (!phone.length) {
			NSArray *parts = [m[@"text"] componentsSeparatedByString:@"\n"];
			if (parts.count > 1) phone = parts[1];
		}
		if (index == 0) {
			NSString *clean = [[phone componentsSeparatedByCharactersInSet:[[NSCharacterSet characterSetWithCharactersInString:@"+0123456789"] invertedSet]] componentsJoinedByString:@""];
			if (clean.length)
				[[UIApplication sharedApplication] openURL:[NSURL URLWithString:[NSString stringWithFormat:@"tel:%@", clean]]];
		} else if (index == 1) {
			[self presentAddContactForMessage:m];
		} else if (index == 2) {
			[UIPasteboard generalPasteboard].string = phone ?: @"";
			[TGSnackbar showInView:self.view text:@"Phone number copied" seconds:2 onCommit:^{}];
		}
		return;
	}
	if (sheet.tag != kAttachSheetTag)
		return;
	if (index == 0)      [self pickMedia];
	else if (index == 1) [self sendCurrentLocation];
	else                 [self pickContact];
}



#pragma mark - taps

- (void)simulateTapOnRow:(NSInteger)row {
	if (row < 0 || row >= (NSInteger)self.messages.count){
		NSLog(@"tap: row %ld out of range (%lu)",
				(long)row, (unsigned long)self.messages.count);
		return;
	}
	NSLog(@"tap: row %ld, kind %@", (long)row, self.messages[row][@"kind"]);
	[self tableView:self.table
			didSelectRowAtIndexPath:[NSIndexPath indexPathForRow:row inSection:0]];
}


- (void)callCellButtonTapped:(UIButton *)btn {
	if (!self.isGroup) {
		[TGCallViewController presentForUserId:self.chatId
										  name:self.chatTitle
									  outgoing:YES];
	}
}

- (void)contactCallButtonTapped:(UIButton *)btn {
	NSInteger row = btn.tag;
	if (row >= 0 && row < (NSInteger)self.messages.count) {
		NSDictionary *m = self.messages[row];
		NSDictionary *contact = [m[@"contact"] isKindOfClass:NSDictionary.class] ? m[@"contact"] : nil;
		NSString *phone = contact[@"phoneNumber"];
		if (!phone.length) {
			NSArray *parts = [m[@"text"] componentsSeparatedByString:@"\n"];
			if (parts.count > 1) phone = parts[1];
		}
		if (phone.length) {
			NSString *clean = [[phone componentsSeparatedByCharactersInSet:[[NSCharacterSet characterSetWithCharactersInString:@"+0123456789"] invertedSet]] componentsJoinedByString:@""];
			if (clean.length)
				[[UIApplication sharedApplication] openURL:[NSURL URLWithString:[NSString stringWithFormat:@"tel:%@", clean]]];
		}
	}
}

- (void)contactAddButtonTapped:(UIButton *)btn {
	NSInteger row = btn.tag;
	if (row >= 0 && row < (NSInteger)self.messages.count) {
		[self presentAddContactForMessage:self.messages[row]];
	}
}


- (void)unknownPersonViewController:(ABUnknownPersonViewController *)unknownCardViewController didResolveToPerson:(ABRecordRef)person {
}

- (void)handleContactTapForMessage:(NSDictionary *)m {
	NSDictionary *contact = [m[@"contact"] isKindOfClass:NSDictionary.class] ? m[@"contact"] : nil;
	NSString *phone = contact[@"phoneNumber"] ?: @"";
	if (!phone.length) {
		NSArray *parts = [m[@"text"] componentsSeparatedByString:@"\n"];
		if (parts.count > 1) phone = parts[1];
	}
	NSString *name = contact[@"name"] ?: @"";
	if (!name.length) {
		NSArray *parts = [m[@"text"] componentsSeparatedByString:@"\n"];
		if (parts.count) name = parts[0];
	}

	self.contactActionMessage = m;
	UIActionSheet *sheet = [[UIActionSheet alloc]
			initWithTitle:name.length ? name : @"Contact"
				 delegate:self
		cancelButtonTitle:@"Cancel"
   destructiveButtonTitle:nil
		otherButtonTitles:
			phone.length ? [NSString stringWithFormat:@"Call %@", phone] : @"Call",
			@"Add to Contacts",
			@"Copy Phone Number",
			nil];
	sheet.tag = 0xC047;
	[sheet showInView:self.view];
}

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
	[tableView deselectRowAtIndexPath:indexPath animated:NO];
	if (indexPath.row < 0 || indexPath.row >= (NSInteger)self.messages.count)
		return;
	NSDictionary *m = self.messages[indexPath.row];
	if (self.isEditingMessages) {
		if ([m[@"service"] boolValue])
			return;
		int64_t msgId = [m[@"id"] longLongValue];
		if (msgId) {
			[self toggleMessageSelection:msgId];
		}
		return;
	}
	NSString *kind = m[@"kind"];

	// Contact card tap
	if ([kind isEqualToString:@"messageContact"]){
		[self handleContactTapForMessage:m];
		return;
	}

	// Location card tap -> open in Apple Maps
	if ([kind isEqualToString:@"messageLocation"] || [kind isEqualToString:@"messageVenue"] || [kind isEqualToString:@"messageLiveLocation"]){
		double lat = [m[@"lat"] doubleValue];
		double lon = [m[@"lon"] doubleValue];
		if (lat != 0 || lon != 0){
			NSString *title = m[@"venue"][@"title"];
			NSString *urlStr = nil;
			if (title.length){
				NSString *esc = [title stringByAddingPercentEscapesUsingEncoding:NSUTF8StringEncoding];
				urlStr = [NSString stringWithFormat:@"http://maps.apple.com/?q=%@&ll=%f,%f", esc, lat, lon];
			} else {
				urlStr = [NSString stringWithFormat:@"http://maps.apple.com/?ll=%f,%f", lat, lon];
			}
			[[UIApplication sharedApplication] openURL:[NSURL URLWithString:urlStr]];
			return;
		}
	}

	// A call log entry calls back, which is the only thing anyone wants from
	// one - and a missed call is otherwise a dead end.
	if ([kind isEqualToString:@"messageCall"] && !self.isGroup){
		[TGCallViewController presentForUserId:self.chatId
										  name:self.chatTitle
									  outgoing:YES];
		return;
	}

	// A poll is voted in by tapping an option, which is a button of its own.
	if ([kind isEqualToString:@"messagePoll"])
		return;

	// A reply is unreadable if you cannot get to what it answers.
	// The flattened message stores absent values as NSNull, which answers no
	// number selector - asking it for a long long is what brought the app
	// down on the first tap on a voice note.
	NSNumber *replyTo = [m[@"replyId"] isKindOfClass:NSNumber.class] ? m[@"replyId"] : nil;
	if (replyTo && [self scrollToMessageId:replyTo.longLongValue])
		return;

	// A theme file is the one document worth opening in place: tapping it
	// applies the theme, the way the official clients do.
	if ([kind isEqualToString:@"messageDocument"] &&
		[TGThemeFile handlesFile:(m[@"docName"] ?: @"")]){
		[self applyThemeFromMessage:m];
		return;
	}

	// A video note plays where it sits, in its own circle - handing it to the
	// full-screen player turns a two-second glance into a modal screen.
	if ([kind isEqualToString:@"messageVideoNote"]){
		if (self.playingMessageId == [m[@"id"] longLongValue] && self.videoNotePlayer){
			[self togglePlayback];
			return;
		}
		NSNumber *docId = m[@"docId"];
		if (![docId isKindOfClass:NSNumber.class])
			return;
		[self beginDownloadHUDForFile:[docId integerValue]];
		__weak typeof(self) weakSelf = self;
		[[TGClient shared] downloadFile:[docId integerValue] completion:^(NSString *path){
			dispatch_async(dispatch_get_main_queue(), ^{
				[weakSelf endDownloadHUD];
				if (path)
					[weakSelf playVideoNoteAtPath:path row:indexPath.row];
				else
					[weakSelf showPlaybackFailure];
			});
		}];
		return;
	}

	// Video and photos share one viewer: it pages between them, which is how
	// every current client shows a chat's media.
	if ([kind isEqualToString:@"messageVideo"] ||
		[kind isEqualToString:@"messagePhoto"] ||
		[m[@"isAlbum"] boolValue]){
		NSArray *albumMsgs = [m[@"isAlbum"] boolValue] ? m[@"albumMessages"] : nil;
		NSDictionary *target = albumMsgs.count ? albumMsgs.firstObject : m;
		NSArray *pool = self.rawMessages.count ? self.rawMessages : self.messages;
		NSInteger targetIdx = [pool indexOfObject:target];
		if (targetIdx == NSNotFound) {
			pool = albumMsgs ?: self.messages;
			targetIdx = [pool indexOfObject:target];
			if (targetIdx == NSNotFound) targetIdx = 0;
		}
		[TGMediaViewer presentItems:pool
							startAt:targetIdx
							 inChat:self.chatId];
		return;
	}

	// A track is not a voice note: it belongs to the run of music in this chat
	// and it keeps playing when the app goes away.
	if ([kind isEqualToString:@"messageAudio"]){
		if ([TGMusicPlayer shared].currentMessageId == [m[@"id"] longLongValue]){
			[[TGMusicPlayer shared] togglePlayPause];
			return;
		}
		if (self.voicePlayer)
			[self stopPlayback];
		[[TGMusicPlayer shared] playTracks:self.messages
								   atIndex:indexPath.row
									inChat:self.chatId];
		[self showMusicBar];
		return;
	}

	// Voice notes are Opus, which iOS 7 cannot decode - convert, then play.
	if ([kind isEqualToString:@"messageVoiceNote"]){
		[self playVoiceNoteForMessage:m atRow:indexPath.row];
		return;
	}
}



- (void)showPlaybackFailure {
	UIAlertView *alert = [[UIAlertView alloc] initWithTitle:@""
													message:@"Cannot play this audio"
												   delegate:nil
										  cancelButtonTitle:@"OK"
										  otherButtonTitles:nil];
	[alert show];
}


- (BOOL)textFieldShouldReturn:(UITextField *)textField {
	[self sendTapped];
	return NO;
}

#pragma mark - geometry

/// Size of the text inside a bubble, and of the bubble itself.
/// The quote block a reply carries, and the "forwarded from" line above it.
- (NSString *)quoteTextFor:(NSDictionary *)m {
	NSNumber *replyId = m[@"replyId"];
	if (![replyId isKindOfClass:NSNumber.class])
		return nil;
	NSString *inline_ = m[@"replyText"];
	if (inline_.length)
		return inline_;
	NSDictionary *fetched = self.quotes[replyId];
	return fetched[@"text"] ?: @"...";
}

/// Who wrote the message being answered. Only known once the original has been
/// fetched; TDLib's inline quote carries the text but not the author.
- (NSString *)quoteAuthorFor:(NSDictionary *)m {
	NSNumber *replyId = [m[@"replyId"] isKindOfClass:NSNumber.class] ? m[@"replyId"] : nil;
	if (!replyId)
		return nil;
	NSDictionary *original = self.quotes[replyId];
	if (!original)
		return nil;
	if ([original[@"outgoing"] boolValue])
		return @"You";
	return [[TGClient shared] nameForUserId:[original[@"senderId"] longLongValue]];
}

- (CGFloat)decorationHeightFor:(NSDictionary *)m {
	CGFloat h = 0;
	if ([m[@"forward"] length])
		h += 18;
	// Their reply block is two lines beside a stripe: the author, then what
	// they said.
	if ([self quoteTextFor:m])
		h += 38;
	if ([m[@"reactions"] length])
		h += 18;
	return h;
}

/// "12:29" for incoming, "12:29 ✓✓" for outgoing, "edited" in front when it
/// applies - the same line Telegram tucks into the corner of the bubble.
- (NSString *)stampFor:(NSDictionary *)m {
	static NSDateFormatter *hm = nil;
	if (!hm){ hm = [[NSDateFormatter alloc] init]; [hm setDateFormat:@"HH:mm"]; }

	NSString *stamp = [hm stringFromDate:
			[NSDate dateWithTimeIntervalSince1970:[m[@"date"] doubleValue]]];
	if ([m[@"edited"] boolValue])
		stamp = [NSString stringWithFormat:@"edited %@", stamp];
	return stamp;   // the ticks are drawn beside it, not spelled out
}

- (CGFloat)timeWidthFor:(NSDictionary *)m {
	CGFloat w = TGTextSize([self stampFor:m], [UIFont systemFontOfSize:11], 0).width + 2;
	if ([m[@"outgoing"] boolValue])
		w += 18;   // room for the ticks
	return w;
}

/// Telegram puts the stamp at the end of the last line when it fits there,
/// and only drops it to its own line when it does not. Anything else leaves a
/// gap under short messages, which is what looked wrong.
- (BOOL)stampFitsInlineFor:(NSDictionary *)m {
	NSString *text = m[@"text"] ?: @"";
	if (!text.length || [text rangeOfString:@"\n"].location != NSNotFound)
		return NO;

	CGFloat oneLine = TGTextSize(text,
			[UIFont systemFontOfSize:[TGTheme shared].messageFontSize], 0).width;
	if (oneLine > kBubbleMaxW - 2 * kPadH)
		return NO;   // it wraps, so there is no short last line to share

	return (oneLine + 6 + [self timeWidthFor:m]) <= (kBubbleMaxW - 2 * kPadH);
}

/// Their forwarded line: "Forwarded from" in grey with the name after it in
/// the accent colour. Returns the height it took, so every kind of bubble can
/// carry it by shifting its own content down - a forwarded file used to look
/// exactly like one you had been sent directly.
- (CGFloat)layoutForwardIn:(TGBubbleCell *)cell
				   message:(NSDictionary *)m
					 width:(CGFloat)width
{
	NSString *from = m[@"forward"];
	if (![from length]){
		cell.forwardLabel.hidden = YES;
		return 0;
	}

	TGTheme *theme = [TGTheme shared];
	cell.forwardLabel.hidden = NO;
	cell.forwardLabel.frame = CGRectMake(kPadH, kPadV, width - 2 * kPadH, 16);

	NSString *line = [NSString stringWithFormat:@"Forwarded from %@", from];
	if ([cell.forwardLabel respondsToSelector:@selector(setAttributedText:)]){
		NSMutableAttributedString *styled =
				[[NSMutableAttributedString alloc] initWithString:line];
		[styled addAttribute:NSForegroundColorAttributeName
					   value:[theme secondaryTextColour]
					   range:NSMakeRange(0, line.length)];
		[styled addAttribute:NSForegroundColorAttributeName
					   value:[theme accentColour]
					   range:NSMakeRange(15, from.length)];
		[styled addAttribute:NSFontAttributeName
					   value:[UIFont boldSystemFontOfSize:12]
					   range:NSMakeRange(15, from.length)];
		cell.forwardLabel.attributedText = styled;
	} else {
		cell.forwardLabel.textColor = [theme accentColour];
		cell.forwardLabel.text = line;
	}
	return 18;
}

/// Question, the "N voted" line, one row per option, and the stamp.
- (CGFloat)pollHeightFor:(NSDictionary *)m {
	NSString *question = m[@"pollQuestion"] ?: @"Poll";
	CGSize qs = TGTextSize(question, [UIFont boldSystemFontOfSize:15],
			kBubbleMaxW - 2 * kPadH);
	NSArray *options = m[@"pollOptions"];
	return kPadV + qs.height + 22 + kPollRow * options.count + 18;
}

/// A picture with no caption carries its own stamp on a plate, so the bubble
/// does not need a strip of empty space under it for one.
- (BOOL)stampSitsOnPictureFor:(NSDictionary *)m {
	if ([m[@"isAlbum"] boolValue] && [self bodySizeFor:m].height == 0)
		return YES;
	return [self imageSizeFor:m].height > 0 && [self bodySizeFor:m].height == 0 &&
		   ![m[@"kind"] isEqualToString:@"messageVideoNote"];
}

- (CGSize)bodySizeFor:(NSDictionary *)m {
	if ([m[@"kind"] isEqualToString:@"messageSticker"] || [m[@"kind"] isEqualToString:@"messageAnimatedEmoji"])
		return CGSizeZero;
	NSString *text = m[@"text"] ?: @"";
	if (!text.length)
		return CGSizeZero;
	return TGTextSizeWithEntities(text, m[@"entities"], [UIFont systemFontOfSize:[TGTheme shared].messageFontSize],
			kBubbleMaxW - 2 * kPadH);
}

- (UIImage *)imageFor:(NSDictionary *)m {
	UIImage *map = self.maps[m[@"id"]];
	if (map)
		return map;
	NSNumber *fileId = m[@"photoId"];
	return [fileId isKindOfClass:NSNumber.class] ? self.images[fileId] : nil;
}

- (CGSize)imageSizeFor:(NSDictionary *)m {
	UIImage *img = [self imageFor:m];
	CGFloat w = 0, h = 0;
	if (img) {
		w = img.size.width;
		h = img.size.height;
	} else if ([m[@"mediaWidth"] floatValue] > 0 && [m[@"mediaHeight"] floatValue] > 0) {
		w = [m[@"mediaWidth"] floatValue];
		h = [m[@"mediaHeight"] floatValue];
	} else if ([m[@"photoId"] isKindOfClass:NSNumber.class]) {
		w = kImageMax;
		h = kImageMax * 0.75f;
	}
	if (w <= 0 || h <= 0)
		return CGSizeZero;

	CGFloat scale = MIN(kImageMax / w, kImageMax / h);
	scale = MIN(scale, 1.0f);
	return CGSizeMake(floorf(w * scale), floorf(h * scale));
}

- (TGMessageLayout *)layoutForMessage:(NSDictionary *)m atRow:(NSInteger)row {
	NSNumber *msgId = m[@"id"];
	if (msgId) {
		TGMessageLayout *hit = self.layoutCache[msgId];
		if (hit) return hit;
	}

	TGMessageLayout *layout = [[TGMessageLayout alloc] init];
	CGFloat tableW = self.table.bounds.size.width;
	if (tableW <= 0) tableW = 320.0f;

	BOOL mine = [m[@"outgoing"] boolValue];
	NSString *kind = m[@"kind"];
	BOOL isSticker = [kind isEqualToString:@"messageSticker"] || [kind isEqualToString:@"messageAnimatedEmoji"];
	BOOL isVoice = [kind isEqualToString:@"messageVoiceNote"];
	BOOL isRound = [kind isEqualToString:@"messageVideoNote"];
	BOOL isService = [m[@"service"] boolValue];
	BOOL isPoll = [kind isEqualToString:@"messagePoll"];
	BOOL isCall = [kind isEqualToString:@"messageCall"];
	BOOL isDoc = [kind isEqualToString:@"messageDocument"];
	BOOL isContact = [kind isEqualToString:@"messageContact"];
	BOOL isLocation = [kind isEqualToString:@"messageLocation"] ||
					  [kind isEqualToString:@"messageVenue"] ||
					  [kind isEqualToString:@"messageLiveLocation"] ||
					  (![m[@"lat"] isKindOfClass:NSNull.class] && [m[@"lat"] doubleValue] != 0);
	BOOL isAlbum = [m[@"isAlbum"] boolValue];

	layout.isService = isService;
	layout.isSticker = isSticker;
	layout.isVoice = isVoice;
	layout.isRound = isRound;
	layout.isPoll = isPoll;
	layout.isCall = isCall;
	layout.isDoc = isDoc;
	layout.isContact = isContact;
	layout.isLocation = isLocation;
	layout.isAlbum = isAlbum;

	CGFloat forwarded = [m[@"forward"] length] ? 18.0f : 0.0f;
	layout.fwdHeight = forwarded;
	layout.stamp = [self stampFor:m];
	layout.timeWidth = TGTextSize(layout.stamp, [UIFont systemFontOfSize:11], 0).width;

	if (isService) {
		NSString *who = [[TGClient shared] nameForUserId:[m[@"senderId"] longLongValue]];
		NSString *line = who.length ? [NSString stringWithFormat:@"%@ %@", who, m[@"text"]] : (m[@"text"] ?: @"");
		UIFont *font = [UIFont systemFontOfSize:12];
		CGFloat textW = MIN(TGTextSize(line, font, 0).width, tableW - 60);
		CGFloat plateW = textW + 20;
		layout.bubbleFrame = CGRectMake((tableW - plateW) / 2, 4, plateW, 21);
		layout.bodyFrame = CGRectMake(0, 2, plateW, 17);
		layout.rowHeight = 30;
		if (msgId) self.layoutCache[msgId] = layout;
		return layout;
	}

	if (isPoll) {
		CGFloat width = kBubbleMaxW;
		CGFloat x = mine ? (tableW - width - 8) : 8;
		CGFloat height = [self pollHeightFor:m];
		layout.bubbleFrame = CGRectMake(x, 3, width, height);
		layout.rowHeight = height + 6;
		if (msgId) self.layoutCache[msgId] = layout;
		return layout;
	}

	if (isCall) {
		NSString *line = m[@"text"] ?: @"Call";
		CGFloat textW = TGTextSize(line, [UIFont boldSystemFontOfSize:14], 0).width;
		CGFloat width = MIN(kBubbleMaxW, textW + 80);
		width = MAX(190.0f, width);
		CGFloat height = 48 + forwarded;
		CGFloat x = mine ? (tableW - width - 8) : 8;
		layout.bubbleFrame = CGRectMake(x, 3, width, height);
		layout.rowHeight = 54 + forwarded;
		if (msgId) self.layoutCache[msgId] = layout;
		return layout;
	}

	if (isDoc) {
		CGFloat width = 225;
		CGFloat height = kFileTile + 2 * kPadV + forwarded;
		CGFloat x = mine ? (tableW - width - 8) : 8;
		layout.bubbleFrame = CGRectMake(x, 3, width, height);
		layout.rowHeight = kFileTile + 2 * kPadV + 6 + forwarded;
		if (msgId) self.layoutCache[msgId] = layout;
		return layout;
	}

	if (isContact) {
		CGFloat width = 230;
		CGFloat height = 56 + 36 + forwarded;
		CGFloat x = mine ? (tableW - width - 8) : 8;
		layout.bubbleFrame = CGRectMake(x, 3, width, height);
		layout.rowHeight = height + 6;
		if (msgId) self.layoutCache[msgId] = layout;
		return layout;
	}

	if (isLocation) {
		NSNumber *lat = m[@"lat"], *lon = m[@"lon"];
		if ([lat isKindOfClass:NSNumber.class] && [lon isKindOfClass:NSNumber.class] && !self.maps[m[@"id"]]) {
			self.maps[m[@"id"]] = [self mapCardForLatitude:lat.doubleValue longitude:lon.doubleValue];
		}
		CGFloat width = 224;
		CGFloat height = 130 + 44 + forwarded;
		CGFloat x = mine ? (tableW - width - 8) : 8;
		layout.bubbleFrame = CGRectMake(x, 3, width, height);
		layout.rowHeight = height + 6;
		if (msgId) self.layoutCache[msgId] = layout;
		return layout;
	}

	CGSize body = [self bodySizeFor:m];
	CGSize pic  = [self imageSizeFor:m];
	layout.bodySize = body;
	layout.picSize = pic;

	if (isRound) {
		CGFloat side = 180;
		layout.picSize = CGSizeMake(side, side);
		layout.bubbleFrame = CGRectMake(mine ? (tableW - side - 8) : 8, 3, side, side);
		layout.rowHeight = side + 10;
		layout.stamp = [self stampFor:m];
		if (msgId) self.layoutCache[msgId] = layout;
		return layout;
	}

	if ([m[@"docName"] isEqualToString:@"tgs"] && self.lottiePaths[m[@"docId"]]) {
		CGFloat side = 128;
		layout.bubbleFrame = CGRectMake(mine ? (tableW - side - 8) : 8, 3, side, side + 14);
		layout.rowHeight = 148;
		if (msgId) self.layoutCache[msgId] = layout;
		return layout;
	}

	CGFloat collageW = 220.0f;
	CGFloat collageH = 0.0f;
	NSMutableArray *itemFrames = [NSMutableArray array];

	if (isAlbum) {
		NSArray *items = m[@"albumMessages"];
		NSUInteger count = items.count;
		CGFloat gap = 2.0f;
		CGFloat halfW = (collageW - gap) / 2.0f;

		if (count <= 2) {
			collageH = 135.0f;
			[itemFrames addObject:[NSValue valueWithCGRect:CGRectMake(0, 0, halfW, collageH)]];
			[itemFrames addObject:[NSValue valueWithCGRect:CGRectMake(halfW + gap, 0, halfW, collageH)]];
		} else if (count == 3) {
			CGFloat topH = 120.0f;
			CGFloat botH = 88.0f;
			collageH = topH + gap + botH;
			[itemFrames addObject:[NSValue valueWithCGRect:CGRectMake(0, 0, collageW, topH)]];
			[itemFrames addObject:[NSValue valueWithCGRect:CGRectMake(0, topH + gap, halfW, botH)]];
			[itemFrames addObject:[NSValue valueWithCGRect:CGRectMake(halfW + gap, topH + gap, halfW, botH)]];
		} else {
			CGFloat halfH = 104.0f;
			collageH = halfH * 2.0f + gap;
			[itemFrames addObject:[NSValue valueWithCGRect:CGRectMake(0, 0, halfW, halfH)]];
			[itemFrames addObject:[NSValue valueWithCGRect:CGRectMake(halfW + gap, 0, halfW, halfH)]];
			[itemFrames addObject:[NSValue valueWithCGRect:CGRectMake(0, halfH + gap, halfW, halfH)]];
			[itemFrames addObject:[NSValue valueWithCGRect:CGRectMake(halfW + gap, halfH + gap, halfW, halfH)]];
		}
		layout.albumFrames = itemFrames;
	}

	int64_t senderId = [m[@"senderId"] longLongValue];
	NSString *senderName = (self.isGroup && !mine) ? [[TGClient shared] nameForUserId:senderId] : nil;

	BOOL inlineStamp = [self stampFitsInlineFor:m];
	CGFloat timeW = [self timeWidthFor:m];
	CGFloat contentW = MAX(body.width, pic.width);
	if (isAlbum)
		contentW = MAX(contentW, collageW);
	NSString *quoted = [self quoteTextFor:m];
	if (quoted || [m[@"forward"] length])
		contentW = MAX(contentW, 170);
	if (inlineStamp)
		contentW = MAX(contentW, body.width + 6 + timeW);
	if (isVoice)
		contentW = 190;
	if (senderName.length) {
		CGFloat senderW = TGTextSize(senderName, [UIFont boldSystemFontOfSize:12], 0).width;
		contentW = MAX(contentW, senderW);
	}

	CGFloat bubbleW = MAX(contentW + 2 * kPadH, timeW + 2 * kPadH + 8);
	bubbleW = MIN(bubbleW, kBubbleMaxW + 2 * kPadH);
	BOOL stampOnPicture = [self stampSitsOnPictureFor:m];
	CGFloat bubbleH = kPadV * 2 + (inlineStamp || stampOnPicture ? 0 : 14) +
			[self decorationHeightFor:m] +
			(isAlbum ? (collageH + (body.height ? 4 : 0)) : (pic.height ? pic.height + 4 : 0)) + body.height;
	if (isVoice)
		bubbleH = 56 + ([m[@"forward"] length] ? 18 : 0);

	CGFloat x = mine ? (tableW - bubbleW - 8) : 8;
	CGFloat top = [self continuesAlbumAtRow:row] ? 0 : 3;

	if (senderName.length) {
		x += kAvatarSide + 4;
		top = 18;
		layout.senderName = senderName;
		layout.senderFrame = CGRectMake(x + kPadH, 2, bubbleW - 2 * kPadH, 14);
		CGFloat avatarY = MAX(2.0f, top + bubbleH - kAvatarSide);
		layout.senderAvatarFrame = CGRectMake(8, avatarY, kAvatarSide, kAvatarSide);
	}

	layout.bubbleFrame = CGRectMake(x, top, bubbleW, bubbleH);
	layout.inlineStamp = inlineStamp;
	layout.stampOnPicture = stampOnPicture;
	layout.timeWidth = timeW;
	layout.stamp = [self stampFor:m];
	layout.quoteText = quoted;
	layout.quoteAuthor = [self quoteAuthorFor:m];

	layout.tailFrame = CGRectZero;

	CGFloat y = kPadV + forwarded;
	if (quoted) {
		layout.quoteBarFrame = CGRectMake(kPadH, y, 2, 34);
		layout.quoteAuthorFrame = CGRectMake(kPadH + 8, y, bubbleW - 2 * kPadH - 10, 16);
		layout.quoteFrame = CGRectMake(kPadH + 8, y + 17, bubbleW - 2 * kPadH - 10, 17);
		y += 38;
	}
	CGFloat innerW = bubbleW - 2 * kPadH;
	if (isAlbum) {
		CGFloat cW = (body.height > 0) ? innerW : collageW;
		layout.collageFrame = CGRectMake(kPadH, y, cW, collageH);
		if (!body.height) {
			CGFloat plateW = timeW + (mine ? 28 : 14);
			layout.mediaStampFrame = CGRectMake(kPadH + collageW - plateW - 6, y + collageH - 22, plateW, 16);
		}
		y += collageH + 4;
	} else if (pic.height > 0) {
		CGFloat picW = (body.height > 0) ? innerW : pic.width;
		layout.pictureFrame = CGRectMake(kPadH, y, picW, pic.height);
		if (!body.height) {
			CGFloat plateW = timeW + (mine ? 28 : 14);
			layout.mediaStampFrame = CGRectMake(kPadH + pic.width - plateW - 6, y + pic.height - 22, plateW, 16);
		}
		y += pic.height + 4;
	}
	layout.bodyFrame = CGRectMake(kPadH, y, bubbleW - 2 * kPadH, body.height);
	CGFloat stampY = inlineStamp ? (y + body.height - 14) : (bubbleH - kPadV - 13);
	CGFloat tickW = mine ? 18 : 0;
	layout.timeFrame = CGRectMake(bubbleW - timeW - kPadH, stampY, timeW - tickW, 12);

	CGFloat rowH = kPadV * 2 + [self decorationHeightFor:m] +
			(inlineStamp || stampOnPicture ? 0 : 14);
	if (self.isGroup && !mine && senderName.length)
		rowH += 15;
	if (isAlbum) rowH += collageH + (body.height > 0 ? 4 : 0);
	else if (pic.height > 0) rowH += pic.height + 4;
	if (body.height > 0) rowH += body.height;
	if (isVoice) rowH = 62 + forwarded;

	layout.rowHeight = MAX(rowH + 6, 40);

	if (msgId) self.layoutCache[msgId] = layout;
	return layout;
}

- (CGFloat)tableView:(UITableView *)tableView heightForRowAtIndexPath:(NSIndexPath *)indexPath {
	NSDictionary *m = self.messages[indexPath.row];
	return [self layoutForMessage:m atRow:indexPath.row].rowHeight;
}

/// Clients colour each participant's name; the same person keeps the same
/// colour because it is derived from their id.
static UIColor *TGSenderColour(int64_t userId) {
	static NSArray *lightPalette = nil;
	static NSArray *darkPalette = nil;
	if (!lightPalette) {
		lightPalette = @[[UIColor colorWithRed:0.85f green:0.27f blue:0.27f alpha:1],
						 [UIColor colorWithRed:0.20f green:0.55f blue:0.85f alpha:1],
						 [UIColor colorWithRed:0.25f green:0.62f blue:0.35f alpha:1],
						 [UIColor colorWithRed:0.75f green:0.45f blue:0.15f alpha:1],
						 [UIColor colorWithRed:0.55f green:0.35f blue:0.75f alpha:1],
						 [UIColor colorWithRed:0.20f green:0.60f blue:0.62f alpha:1]];
		darkPalette = @[[UIColor colorWithRed:0.95f green:0.45f blue:0.45f alpha:1],
						[UIColor colorWithRed:0.42f green:0.70f blue:0.98f alpha:1],
						[UIColor colorWithRed:0.45f green:0.80f blue:0.55f alpha:1],
						[UIColor colorWithRed:0.95f green:0.65f blue:0.35f alpha:1],
						[UIColor colorWithRed:0.75f green:0.55f blue:0.95f alpha:1],
						[UIColor colorWithRed:0.40f green:0.78f blue:0.80f alpha:1]];
	}
	NSArray *p = [TGTheme shared].isDark ? darkPalette : lightPalette;
	return p[(NSUInteger)llabs(userId) % p.count];
}

#pragma mark - pagination

- (void)scrollViewDidScroll:(UIScrollView *)scrollView {
    if (self.isLoadingMoreHistory || !self.messages.count)
        return;
    
    // Load more when scrolled near the top
    if (scrollView.contentOffset.y < 100) {
        self.isLoadingMoreHistory = YES;
        int64_t fromMessageId = [self.messages.firstObject[@"id"] longLongValue];
        
        [[TGClient shared] historyForChat:self.chatId fromMessageId:fromMessageId limit:60 completion:^(NSArray *older) {
            dispatch_async(dispatch_get_main_queue(), ^{
                if (older.count == 0) {
                    // No more history
                    return;
                }
                
                NSMutableArray *indexPaths = [NSMutableArray array];
                for (NSUInteger i = 0; i < older.count; i++) {
                    [indexPaths addObject:[NSIndexPath indexPathForRow:i inSection:0]];
                }
                
                CGFloat oldHeight = self.table.contentSize.height;
                CGFloat oldOffset = self.table.contentOffset.y;

                self.rawMessages = [older arrayByAddingObjectsFromArray:self.rawMessages ?: self.messages];
                self.messages = [self groupedMessagesFromMessages:self.rawMessages];

                [UIView setAnimationsEnabled:NO];
                [self.table reloadData];
                self.table.contentOffset = CGPointMake(0, oldOffset + (self.table.contentSize.height - oldHeight));
                [UIView setAnimationsEnabled:YES];
                [self fetchMissingImages];

                self.isLoadingMoreHistory = NO;
            });
        }];
    }
}




#pragma mark - table

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
	return self.messages.count;
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
	static NSString *reuse = @"TGBubbleCell";
	TGBubbleCell *cell = [tableView dequeueReusableCellWithIdentifier:reuse];
	if (!cell)
		cell = [[TGBubbleCell alloc] initWithStyle:UITableViewCellStyleDefault reuseIdentifier:reuse];

	NSDictionary *m = self.messages[indexPath.row];
	BOOL mine = [m[@"outgoing"] boolValue];
	NSString *kind = m[@"kind"];
	TGMessageLayout *layout = [self layoutForMessage:m atRow:indexPath.row];

	[cell resetForReuse];

	// Service messages
	if (layout.isService) {
		TGTheme *serviceTheme = [TGTheme shared];
		NSString *who = [[TGClient shared] nameForUserId:[m[@"senderId"] longLongValue]];
		NSString *line = who.length ? [NSString stringWithFormat:@"%@ %@", who, m[@"text"]] : (m[@"text"] ?: @"");

		cell.bubble.frame = layout.bubbleFrame;
		cell.bubble.backgroundColor = [serviceTheme serviceBubbleColour];
		cell.bubble.layer.borderWidth = 0;
		cell.bubble.layer.cornerRadius = 10.5f;
		cell.picture.hidden = YES;
		cell.time.text = @"";
		cell.body.hidden = NO;
		cell.body.numberOfLines = 1;
		cell.body.font = [UIFont systemFontOfSize:12];
		cell.body.textAlignment = NSTextAlignmentCenter;
		cell.body.textColor = [serviceTheme serviceTextColour];
		cell.body.text = line;
		cell.body.frame = layout.bodyFrame;
		return [self finalizeCell:cell message:m layout:layout isMine:mine];
	}

	cell.body.textAlignment = NSTextAlignmentLeft;
	cell.bubble.layer.cornerRadius = 14;

	// Polls
	if (layout.isPoll) {
		TGTheme *pollTheme = [TGTheme shared];
		NSArray *options = m[@"pollOptions"];
		NSString *question = m[@"pollQuestion"] ?: @"Poll";
		BOOL closed = [m[@"pollClosed"] boolValue];

		cell.bubble.frame = layout.bubbleFrame;
		cell.bubble.backgroundColor = mine ? [pollTheme bubbleMineColour] : [pollTheme bubbleTheirsColour];
		cell.bubble.layer.borderWidth = [pollTheme bubbleBorderWidth];
		cell.bubble.layer.borderColor = [pollTheme bubbleBorderColour].CGColor;
		cell.bubble.layer.cornerRadius = [pollTheme bubbleCornerRadius];

		cell.body.hidden = NO;
		cell.body.numberOfLines = 0;
		cell.body.font = [UIFont boldSystemFontOfSize:15];
		cell.body.textColor = [pollTheme primaryTextColour];
		cell.body.text = question;
		CGSize qs = TGTextSize(question, cell.body.font, layout.bubbleFrame.size.width - 2 * kPadH);
		cell.body.frame = CGRectMake(kPadH, kPadV, layout.bubbleFrame.size.width - 2 * kPadH, qs.height);

		cell.subtitle.hidden = NO;
		cell.subtitle.font = [UIFont systemFontOfSize:12];
		cell.subtitle.textColor = [pollTheme secondaryTextColour];
		cell.subtitle.text = closed ? @"Final results"
			: [NSString stringWithFormat:@"%@ voted",
					[m[@"pollTotal"] integerValue] == 0 ? @"Nobody" : m[@"pollTotal"]];
		cell.subtitle.frame = CGRectMake(kPadH, kPadV + qs.height + 2, layout.bubbleFrame.size.width - 2 * kPadH, 16);

		int64_t msgId = [m[@"id"] longLongValue];
		if (cell.pollMessageId != msgId) {
			for (UIView *old in [cell.bubble.subviews copy]) {
				if (old.tag >= 0x9100 && old.tag < 0x9200) [old removeFromSuperview];
			}
			cell.pollMessageId = msgId;

			CGFloat y = kPadV + qs.height + 22;
			for (NSUInteger i = 0; i < options.count; i++) {
				NSDictionary *option = options[i];
				BOOL chosen = [option[@"is_chosen"] boolValue];
				NSInteger share = [option[@"vote_percentage"] integerValue];

				UIButton *row = [UIButton buttonWithType:UIButtonTypeCustom];
				row.frame = CGRectMake(kPadH, y, layout.bubbleFrame.size.width - 2 * kPadH, kPollRow);
				row.tag = 0x9100 + (NSInteger)i;
				row.enabled = !closed;
				[row addTarget:self action:@selector(pollOptionTapped:) forControlEvents:UIControlEventTouchUpInside];
				[cell.bubble addSubview:row];

				UIView *dot = [[UIView alloc] initWithFrame:CGRectMake(0, 4, 16, 16)];
				dot.layer.cornerRadius = 8;
				dot.layer.borderWidth = 1.5f;
				dot.layer.borderColor = [pollTheme accentColour].CGColor;
				dot.backgroundColor = chosen ? [pollTheme accentColour] : [UIColor clearColor];
				[row addSubview:dot];

				UILabel *label = [[UILabel alloc] initWithFrame:CGRectMake(24, 2, row.bounds.size.width - 66, 20)];
				label.text = option[@"text"][@"text"] ?: option[@"text"] ?: @"";
				label.font = [UIFont systemFontOfSize:14];
				label.textColor = [pollTheme primaryTextColour];
				label.backgroundColor = [UIColor clearColor];
				[row addSubview:label];

				UILabel *percent = [[UILabel alloc] initWithFrame:CGRectMake(row.bounds.size.width - 40, 2, 40, 20)];
				percent.text = [NSString stringWithFormat:@"%ld%%", (long)share];
				percent.font = [UIFont systemFontOfSize:13];
				percent.textAlignment = NSTextAlignmentRight;
				percent.textColor = [pollTheme secondaryTextColour];
				percent.backgroundColor = [UIColor clearColor];
				[row addSubview:percent];

				UIView *track = [[UIView alloc] initWithFrame:CGRectMake(24, kPollRow - 6, row.bounds.size.width - 24, 2)];
				track.backgroundColor = [pollTheme separatorColour];
				[row addSubview:track];

				UIView *fill = [[UIView alloc] initWithFrame:CGRectMake(24, kPollRow - 6, (row.bounds.size.width - 24) * share / 100.0f, 2)];
				fill.backgroundColor = [pollTheme accentColour];
				[row addSubview:fill];

				y += kPollRow;
			}
		}

		cell.picture.hidden = YES;
		cell.disc.hidden = YES;
		cell.time.text = layout.stamp;
		cell.time.textColor = [pollTheme timeColour];
		CGFloat pollTimeW = layout.timeWidth;
		cell.time.frame = CGRectMake(layout.bubbleFrame.size.width - pollTimeW - kPadH, layout.bubbleFrame.size.height - 17,
									 pollTimeW - (mine ? 18 : 0), 12);
		cell.ticks.hidden = !mine;
		if (mine) {
			cell.ticks.image = [TGIcons ticksWhite:NO];
			cell.ticks.frame = CGRectMake(layout.bubbleFrame.size.width - kPadH - 15, layout.bubbleFrame.size.height - 15, 15, 9);
		}
		return [self finalizeCell:cell message:m layout:layout isMine:mine];
	}

	// Calls
	if (layout.isCall) {
		TGTheme *callTheme = [TGTheme shared];
		BOOL missed = [m[@"callState"] isEqualToString:@"missed"];
		NSString *line = m[@"text"] ?: @"Call";

		CGFloat fwd = [self layoutForwardIn:cell message:m width:layout.bubbleFrame.size.width];
		cell.bubble.frame = layout.bubbleFrame;
		cell.bubble.backgroundColor = mine ? [callTheme bubbleMineColour] : [callTheme bubbleTheirsColour];
		cell.bubble.layer.borderWidth = [callTheme bubbleBorderWidth];
		cell.bubble.layer.borderColor = [callTheme bubbleBorderColour].CGColor;
		cell.bubble.layer.cornerRadius = [callTheme bubbleCornerRadius];

		cell.disc.hidden = NO;
		cell.disc.image = [TGIcons callArrowOutgoing:mine missed:missed];
		cell.disc.frame = CGRectMake(kPadH, fwd + (layout.bubbleFrame.size.height - fwd - 16) / 2, 16, 16);

		CGFloat rightBtnW = 34.0f;
		CGFloat textW = layout.bubbleFrame.size.width - kPadH - 26 - rightBtnW - 4;

		cell.body.hidden = NO;
		cell.body.numberOfLines = 1;
		cell.body.font = [UIFont boldSystemFontOfSize:14];
		cell.body.textColor = missed ? [callTheme destructiveColour] : [callTheme primaryTextColour];
		cell.body.text = line;
		cell.body.frame = CGRectMake(kPadH + 24, fwd + 6, textW, 18);

		cell.subtitle.hidden = NO;
		cell.subtitle.font = [UIFont systemFontOfSize:12];
		cell.subtitle.textColor = [callTheme secondaryTextColour];
		cell.subtitle.text = layout.stamp;
		cell.subtitle.frame = CGRectMake(kPadH + 24, fwd + 26, textW, 14);

		cell.contactCallButton.hidden = NO;
		cell.contactCallButton.frame = CGRectMake(layout.bubbleFrame.size.width - rightBtnW - 4, fwd + (layout.bubbleFrame.size.height - fwd - 32) / 2, 32, 32);
		[cell.contactCallButton setImage:[TGIcons callArrowOutgoing:YES missed:NO] forState:UIControlStateNormal];
		[cell.contactCallButton setTitle:nil forState:UIControlStateNormal];
		cell.contactCallButton.tag = indexPath.row;
		[cell.contactCallButton removeTarget:nil action:NULL forControlEvents:UIControlEventAllEvents];
		[cell.contactCallButton addTarget:self action:@selector(callCellButtonTapped:) forControlEvents:UIControlEventTouchUpInside];

		cell.picture.hidden = YES;
		cell.time.text = @"";
		cell.ticks.hidden = YES;
		return [self finalizeCell:cell message:m layout:layout isMine:mine];
	}

	// Documents
	if (layout.isDoc) {
		NSArray *lines = [m[@"text"] componentsSeparatedByString:@"\n"];
		NSString *first = lines.count ? lines[0] : @"";
		NSString *second = lines.count > 1 ? lines[1] : @"";

		TGTheme *cardTheme = [TGTheme shared];
		CGFloat fwd = [self layoutForwardIn:cell message:m width:layout.bubbleFrame.size.width];
		cell.bubble.frame = layout.bubbleFrame;
		cell.bubble.backgroundColor = mine ? [cardTheme bubbleMineColour] : [cardTheme bubbleTheirsColour];
		cell.bubble.layer.borderWidth = [cardTheme bubbleBorderWidth];
		cell.bubble.layer.borderColor = [cardTheme bubbleBorderColour].CGColor;
		cell.bubble.layer.cornerRadius = [cardTheme bubbleCornerRadius];

		cell.icon.hidden = NO;
		CGFloat side = kFileTile;
		cell.icon.frame = CGRectMake(kPadH, fwd + kPadV + (kFileTile - side) / 2, side, side);
		cell.icon.text = @"";
		cell.icon.layer.cornerRadius = 3;
		cell.icon.backgroundColor = [cardTheme fileTileColour];

		cell.disc.hidden = NO;
		cell.disc.image = [TGIcons fileDiscOfSide:kFileDisc];
		cell.disc.frame = CGRectMake(kPadH + (kFileTile - kFileDisc) / 2,
									 fwd + kPadV + (kFileTile - kFileDisc) / 2,
									 kFileDisc, kFileDisc);
		[cell.bubble bringSubviewToFront:cell.disc];

		CGFloat textX = kPadH + side + 10;
		cell.body.hidden = NO;
		cell.body.numberOfLines = 2;
		cell.body.font = [UIFont systemFontOfSize:15];
		cell.body.textColor = [cardTheme fileNameColour];
		cell.body.text = first;
		cell.body.frame = CGRectMake(textX, fwd + kPadV + 8, layout.bubbleFrame.size.width - textX - kPadH, 38);

		cell.subtitle.hidden = NO;
		cell.subtitle.font = [UIFont systemFontOfSize:13];
		cell.subtitle.textColor = [cardTheme fileMetaColour];
		cell.subtitle.text = second;
		cell.subtitle.frame = CGRectMake(textX, fwd + kPadV + 46, layout.bubbleFrame.size.width - textX - kPadH, 17);

		cell.time.text = layout.stamp;
		cell.time.textColor = [cardTheme timeColour];
		CGFloat fileTimeW = layout.timeWidth;
		CGFloat fileTicks = mine ? 18 : 0;
		cell.time.frame = CGRectMake(layout.bubbleFrame.size.width - fileTimeW - kPadH, layout.bubbleFrame.size.height - 17,
									 fileTimeW - fileTicks, 12);
		cell.ticks.hidden = !mine;
		if (mine) {
			cell.ticks.image = [TGIcons ticksWhite:NO];
			cell.ticks.frame = CGRectMake(layout.bubbleFrame.size.width - kPadH - 15, layout.bubbleFrame.size.height - 15, 15, 9);
		}
		cell.picture.hidden = YES;
		return [self finalizeCell:cell message:m layout:layout isMine:mine];
	}

	// Contacts
	if (layout.isContact) {
		NSDictionary *contact = [m[@"contact"] isKindOfClass:NSDictionary.class] ? m[@"contact"] : nil;
		NSString *name = contact[@"name"];
		NSString *phone = contact[@"phoneNumber"];
		if (!name.length || !phone.length) {
			NSArray *lines = [m[@"text"] componentsSeparatedByString:@"\n"];
			if (!name.length && lines.count) name = lines[0];
			if (!phone.length && lines.count > 1) phone = lines[1];
		}
		if (!name.length) name = @"Contact";
		if (!phone.length) phone = @"";

		TGTheme *cardTheme = [TGTheme shared];
		CGFloat fwd = [self layoutForwardIn:cell message:m width:layout.bubbleFrame.size.width];
		cell.bubble.frame = layout.bubbleFrame;
		cell.bubble.backgroundColor = mine ? [cardTheme bubbleMineColour] : [cardTheme bubbleTheirsColour];
		cell.bubble.layer.borderWidth = [cardTheme bubbleBorderWidth];
		cell.bubble.layer.borderColor = [cardTheme bubbleBorderColour].CGColor;
		cell.bubble.layer.cornerRadius = [cardTheme bubbleCornerRadius];

		cell.icon.hidden = NO;
		CGFloat side = 42;
		cell.icon.frame = CGRectMake(kPadH, fwd + 7, side, side);
		NSString *initials = name.length ? [name substringToIndex:1] : @"?";
		NSArray *words = [name componentsSeparatedByString:@" "];
		if (words.count > 1 && [words[1] length])
			initials = [initials stringByAppendingString:[words[1] substringToIndex:1]];
		cell.icon.text = initials.uppercaseString;
		cell.icon.font = [UIFont boldSystemFontOfSize:17];
		cell.icon.layer.cornerRadius = side / 2;
		cell.icon.backgroundColor = [cardTheme mediaCircleColour];

		CGFloat textX = kPadH + side + 10;
		CGFloat textW = layout.bubbleFrame.size.width - textX - kPadH;
		cell.body.hidden = NO;
		cell.body.numberOfLines = 1;
		cell.body.font = [UIFont boldSystemFontOfSize:15];
		cell.body.textColor = [cardTheme primaryTextColour];
		cell.body.text = name;
		cell.body.frame = CGRectMake(textX, fwd + 8, textW, 18);

		cell.subtitle.hidden = NO;
		cell.subtitle.font = [UIFont systemFontOfSize:13];
		cell.subtitle.textColor = [cardTheme fileMetaColour];
		cell.subtitle.text = phone;
		cell.subtitle.frame = CGRectMake(textX, fwd + 28, textW, 16);

		CGFloat sepY = fwd + 55;
		cell.contactSeparatorH.hidden = NO;
		cell.contactSeparatorH.backgroundColor = [cardTheme separatorColour];
		cell.contactSeparatorH.frame = CGRectMake(0, sepY, layout.bubbleFrame.size.width, 0.5f);

		CGFloat btnW = layout.bubbleFrame.size.width / 2.0f;
		cell.contactSeparatorV.hidden = NO;
		cell.contactSeparatorV.backgroundColor = [cardTheme separatorColour];
		cell.contactSeparatorV.frame = CGRectMake(btnW, sepY, 0.5f, 36);

		cell.contactCallButton.hidden = NO;
		cell.contactCallButton.frame = CGRectMake(0, sepY, btnW, 36);
		[cell.contactCallButton setTitleColor:[cardTheme accentColour] forState:UIControlStateNormal];
		[cell.contactCallButton setTitleColor:[[cardTheme accentColour] colorWithAlphaComponent:0.4f] forState:UIControlStateHighlighted];
		cell.contactCallButton.tag = indexPath.row;
		[cell.contactCallButton removeTarget:nil action:NULL forControlEvents:UIControlEventAllEvents];
		[cell.contactCallButton addTarget:self action:@selector(contactCallButtonTapped:) forControlEvents:UIControlEventTouchUpInside];

		cell.contactAddButton.hidden = NO;
		cell.contactAddButton.frame = CGRectMake(btnW, sepY, btnW, 36);
		[cell.contactAddButton setTitleColor:[cardTheme accentColour] forState:UIControlStateNormal];
		[cell.contactAddButton setTitleColor:[[cardTheme accentColour] colorWithAlphaComponent:0.4f] forState:UIControlStateHighlighted];
		cell.contactAddButton.tag = indexPath.row;
		[cell.contactAddButton removeTarget:nil action:NULL forControlEvents:UIControlEventAllEvents];
		[cell.contactAddButton addTarget:self action:@selector(contactAddButtonTapped:) forControlEvents:UIControlEventTouchUpInside];

		cell.time.text = layout.stamp;
		cell.time.textColor = [cardTheme timeColour];
		CGFloat fileTimeW = layout.timeWidth;
		CGFloat fileTicks = mine ? 18 : 0;
		cell.time.frame = CGRectMake(layout.bubbleFrame.size.width - fileTimeW - kPadH, fwd + 30,
									 fileTimeW - fileTicks, 12);
		cell.ticks.hidden = !mine;
		if (mine) {
			cell.ticks.image = [TGIcons ticksWhite:NO];
			cell.ticks.frame = CGRectMake(layout.bubbleFrame.size.width - kPadH - 15, fwd + 32, 15, 9);
		}
		cell.picture.hidden = YES;
		return [self finalizeCell:cell message:m layout:layout isMine:mine];
	}

	// Locations
	if (layout.isLocation) {
		TGTheme *locTheme = [TGTheme shared];
		CGFloat fwd = [self layoutForwardIn:cell message:m width:layout.bubbleFrame.size.width];
		cell.bubble.frame = layout.bubbleFrame;
		cell.bubble.backgroundColor = mine ? [locTheme bubbleMineColour] : [locTheme bubbleTheirsColour];
		cell.bubble.layer.borderWidth = [locTheme bubbleBorderWidth];
		cell.bubble.layer.borderColor = [locTheme bubbleBorderColour].CGColor;
		cell.bubble.layer.cornerRadius = [locTheme bubbleCornerRadius];

		CGFloat mapW = layout.bubbleFrame.size.width;
		CGFloat mapH = 130.0f;

		double lat = [m[@"lat"] doubleValue];
		double lon = [m[@"lon"] doubleValue];

		cell.picture.hidden = NO;
		cell.picture.frame = CGRectMake(0, fwd, mapW, mapH);
		cell.picture.clipsToBounds = YES;
		cell.picture.image = [self imageFor:m];

		cell.disc.hidden = NO;
		cell.disc.userInteractionEnabled = NO;
		cell.disc.image = [TGIcons mapPinBadge];
		cell.disc.frame = CGRectMake((mapW - 28) / 2, fwd + (mapH - 36) / 2 - 4, 28, 36);
		[cell.bubble bringSubviewToFront:cell.disc];

		cell.icon.hidden = NO;
		cell.icon.layer.cornerRadius = 3;
		cell.icon.backgroundColor = [UIColor colorWithWhite:0.0f alpha:0.45f];
		cell.icon.textColor = [UIColor whiteColor];
		cell.icon.font = [UIFont boldSystemFontOfSize:10];
		cell.icon.text = @" Apple Maps ";
		cell.icon.frame = CGRectMake(6, fwd + mapH - 22, 68, 16);
		[cell.bubble bringSubviewToFront:cell.icon];

		cell.mediaStamp.hidden = YES;

		NSDictionary *venue = [m[@"venue"] isKindOfClass:NSDictionary.class] ? m[@"venue"] : nil;
		NSString *vTitle = venue[@"title"];
		NSString *vAddr = venue[@"address"];
		if (!vTitle.length) {
			NSArray *lines = [m[@"text"] componentsSeparatedByString:@"\n"];
			if (lines.count > 1) {
				vTitle = lines[0];
				vAddr = lines[1];
			} else if (lines.count == 1 && ![lines[0] isEqualToString:@"Location"]) {
				vTitle = lines[0];
			}
		}
		if (!vTitle.length) vTitle = @"Location";
		if (!vAddr.length)  vAddr = [NSString stringWithFormat:@"%.4f, %.4f", lat, lon];

		CGFloat locTimeW = layout.timeWidth;
		CGFloat locTicks = mine ? 18 : 0;

		cell.body.hidden = NO;
		cell.body.numberOfLines = 1;
		cell.body.font = [UIFont boldSystemFontOfSize:14];
		cell.body.textColor = [locTheme primaryTextColour];
		cell.body.text = vTitle;
		cell.body.frame = CGRectMake(kPadH, fwd + mapH + 4, mapW - 2 * kPadH, 18);

		cell.subtitle.hidden = NO;
		cell.subtitle.numberOfLines = 1;
		cell.subtitle.font = [UIFont systemFontOfSize:12];
		cell.subtitle.textColor = [locTheme fileMetaColour];
		cell.subtitle.text = vAddr;
		cell.subtitle.frame = CGRectMake(kPadH, fwd + mapH + 24, mapW - 2 * kPadH - locTimeW - locTicks - 4, 16);

		cell.time.hidden = NO;
		cell.time.text = layout.stamp;
		cell.time.textColor = [locTheme timeColour];
		cell.time.frame = CGRectMake(layout.bubbleFrame.size.width - locTimeW - locTicks - kPadH,
									 layout.bubbleFrame.size.height - 17,
									 locTimeW, 12);

		cell.ticks.hidden = !mine;
		if (mine) {
			cell.ticks.image = [TGIcons ticksWhite:NO];
			cell.ticks.frame = CGRectMake(layout.bubbleFrame.size.width - locTicks - kPadH + 2,
										  layout.bubbleFrame.size.height - 15, 15, 9);
			[cell.bubble bringSubviewToFront:cell.ticks];
		}
		return [self finalizeCell:cell message:m layout:layout isMine:mine];
	}

	// General bubble messages
	int64_t senderId = [m[@"senderId"] longLongValue];
	if (layout.senderName.length) {
		cell.senderAvatar.hidden = NO;
		cell.senderAvatar.image = [self avatarForUser:senderId name:layout.senderName];
		cell.senderAvatar.frame = layout.senderAvatarFrame;

		cell.sender.hidden = NO;
		cell.sender.text = layout.senderName;
		cell.sender.textColor = TGSenderColour(senderId);
		cell.sender.frame = layout.senderFrame;
	}

	cell.bubble.frame = layout.bubbleFrame;

	TGTheme *theme = [TGTheme shared];
	UIColor *fill = mine ? [theme bubbleMineColour] : [theme bubbleTheirsColour];
	cell.bubble.backgroundColor = layout.isSticker ? [UIColor clearColor] : fill;

	cell.tail.hidden = YES;
	cell.bubble.layer.borderWidth = (layout.isSticker || layout.isRound) ? 0.0f : [theme bubbleBorderWidth];
	cell.bubble.layer.borderColor = [theme bubbleBorderColour].CGColor;
	cell.bubble.layer.cornerRadius = [theme bubbleCornerRadius];
	cell.body.textColor = [theme primaryTextColour];

	// Video note
	if (layout.isRound) {
		CGFloat side = layout.bubbleFrame.size.width;
		cell.bubble.backgroundColor = [theme fileTileColour];
		cell.bubble.layer.borderWidth = 0;
		cell.bubble.frame = layout.bubbleFrame;
		cell.bubble.layer.cornerRadius = side / 2;
		cell.bubble.clipsToBounds = YES;
		cell.picture.hidden = NO;
		cell.picture.image = [self imageFor:m];
		cell.picture.backgroundColor = [theme fileTileColour];
		cell.picture.frame = CGRectMake(0, 0, side, side);
		cell.picture.layer.cornerRadius = side / 2;
		cell.picture.clipsToBounds = YES;
		cell.body.hidden = YES;

		cell.disc.hidden = NO;
		cell.disc.userInteractionEnabled = YES;
		CGFloat disc = 48;
		BOOL isPlaying = (self.playingMessageId == [m[@"id"] longLongValue] && self.videoNotePlayer != nil);
		cell.disc.image = [TGIcons mediaDiscOfSide:disc playing:isPlaying];
		cell.disc.frame = CGRectMake((side - disc) / 2, (side - disc) / 2, disc, disc);
		if (!cell.disc.gestureRecognizers.count) {
			[cell.disc addGestureRecognizer:[[UITapGestureRecognizer alloc]
					initWithTarget:self action:@selector(videoNoteDiscTapped:)]];
		}
		NSInteger dur = [m[@"duration"] integerValue];
		NSString *durStr = (dur > 0) ? [NSString stringWithFormat:@"%ld:%02ld", (long)(dur / 60), (long)(dur % 60)] : @"";
		NSString *stamp = (layout.stamp.length && ![layout.stamp isEqualToString:@"(null)"]) ? layout.stamp : @"";
		NSString *stampText = durStr.length ? (stamp.length ? [NSString stringWithFormat:@"%@  %@", durStr, stamp] : durStr) : stamp;

		CGFloat stampW = TGTextSize(stampText, [UIFont systemFontOfSize:11], 0).width + (mine ? 26 : 14);
		cell.mediaStamp.hidden = NO;
		cell.mediaStamp.backgroundColor = [theme mediaStampColour];
		cell.mediaStamp.text = mine ? [NSString stringWithFormat:@"  %@", stampText] : stampText;
		cell.mediaStamp.textAlignment = mine ? NSTextAlignmentLeft : NSTextAlignmentCenter;
		cell.mediaStamp.frame = CGRectMake((side - stampW) / 2, side - 24, stampW, 16);
		[cell.bubble bringSubviewToFront:cell.mediaStamp];

		cell.ticks.hidden = !mine;
		if (mine) {
			cell.ticks.image = [TGIcons ticksWhite:YES];
			cell.ticks.frame = CGRectMake(CGRectGetMaxX(cell.mediaStamp.frame) - 16,
										  CGRectGetMidY(cell.mediaStamp.frame) - 4.5f, 15, 9);
			[cell.bubble bringSubviewToFront:cell.ticks];
		}

		cell.time.hidden = YES;
		return [self finalizeCell:cell message:m layout:layout isMine:mine];
	}

	// Animated sticker
	NSString *tgsPath = [m[@"docName"] isEqualToString:@"tgs"] ? self.lottiePaths[m[@"docId"]] : nil;
	if (tgsPath) {
		CGFloat side = 128;
		cell.bubble.backgroundColor = [UIColor clearColor];
		cell.bubble.layer.borderWidth = 0;
		cell.bubble.frame = layout.bubbleFrame;
		cell.picture.hidden = YES;
		cell.body.hidden = YES;
		cell.lottie.hidden = NO;
		cell.lottie.frame = CGRectMake(0, 0, side, side);
		[cell.lottie loadTGSFile:tgsPath];
		[cell.lottie play];

		static NSDateFormatter *hmt = nil;
		if (!hmt) { hmt = [[NSDateFormatter alloc] init]; [hmt setDateFormat:@"HH:mm"]; }
		cell.time.text = [hmt stringFromDate:[NSDate dateWithTimeIntervalSince1970:[m[@"date"] doubleValue]]];
		cell.time.textColor = [theme timeColour];
		cell.time.frame = CGRectMake(side - 44, side, 44, 12);
		return [self finalizeCell:cell message:m layout:layout isMine:mine];
	}

	cell.quoteBar.hidden = YES;
	cell.quote.hidden = YES;
	cell.quoteAuthor.hidden = YES;

	[self layoutForwardIn:cell message:m width:layout.bubbleFrame.size.width];

	if (layout.quoteText) {
		cell.quoteBar.hidden = NO;
		cell.quoteBar.backgroundColor = [theme accentColour];
		cell.quoteBar.frame = layout.quoteBarFrame;

		cell.quoteAuthor.hidden = NO;
		cell.quoteAuthor.font = [UIFont boldSystemFontOfSize:13];
		cell.quoteAuthor.textColor = [theme accentColour];
		cell.quoteAuthor.text = layout.quoteAuthor ?: @"Reply";
		cell.quoteAuthor.frame = layout.quoteAuthorFrame;

		cell.quote.hidden = NO;
		cell.quote.numberOfLines = 1;
		cell.quote.font = [UIFont systemFontOfSize:13];
		cell.quote.textColor = [theme primaryTextColour];
		cell.quote.text = layout.quoteText;
		cell.quote.frame = layout.quoteFrame;
	}

	cell.mediaStamp.hidden = YES;
	if (layout.isAlbum) {
		cell.collageView.hidden = NO;
		cell.collageView.frame = layout.collageFrame;
		cell.picture.hidden = YES;
		cell.picture.image = nil;

		NSArray *albumMsgs = m[@"albumMessages"];
		NSUInteger count = albumMsgs.count;
		NSArray *frames = layout.albumFrames;

		for (NSInteger i = 0; i < 4; i++) {
			UIImageView *iv = cell.collageViews[i];
			if (i < (NSInteger)frames.count && i < (NSInteger)count) {
				iv.hidden = NO;
				iv.frame = [frames[i] CGRectValue];
				NSDictionary *itemMsg = albumMsgs[i];
				iv.image = [self imageFor:itemMsg];
			} else {
				iv.hidden = YES;
				iv.image = nil;
			}
		}

		if (count > 4 && frames.count >= 4) {
			cell.collageMoreLabel.hidden = NO;
			cell.collageMoreLabel.frame = [frames[3] CGRectValue];
			cell.collageMoreLabel.text = [NSString stringWithFormat:@"+%ld", (long)(count - 3)];
			[cell.collageView bringSubviewToFront:cell.collageMoreLabel];
		} else {
			cell.collageMoreLabel.hidden = YES;
		}

		__weak typeof(self) weakSelf = self;
		cell.onCollageItemTapped = ^(NSInteger idx) {
			TGChatViewController *strongSelf = weakSelf;
			if (!strongSelf) return;
			if (idx >= 0 && idx < (NSInteger)albumMsgs.count) {
				NSDictionary *target = albumMsgs[idx];
				NSArray *pool = strongSelf.rawMessages.count ? strongSelf.rawMessages : albumMsgs;
				NSInteger targetIdx = [pool indexOfObject:target];
				if (targetIdx == NSNotFound) {
					pool = albumMsgs;
					targetIdx = idx;
				}
				[TGMediaViewer presentItems:pool
									startAt:targetIdx
									 inChat:strongSelf.chatId];
			}
		};

		if (!layout.bodySize.height) {
			cell.mediaStamp.hidden = NO;
			cell.mediaStamp.backgroundColor = [theme mediaStampColour];
			cell.mediaStamp.text = mine ? [NSString stringWithFormat:@"  %@", layout.stamp] : layout.stamp;
			cell.mediaStamp.textAlignment = mine ? NSTextAlignmentLeft : NSTextAlignmentCenter;
			cell.mediaStamp.frame = layout.mediaStampFrame;
			[cell.bubble bringSubviewToFront:cell.mediaStamp];
		}
	} else if (layout.picSize.height > 0) {
		cell.collageView.hidden = YES;
		cell.picture.hidden = NO;
		UIImage *img = [self imageFor:m];
		cell.picture.image = img;
		cell.picture.backgroundColor = (img || layout.isSticker) ? [UIColor clearColor] : [theme fileTileColour];
		cell.picture.frame = layout.pictureFrame;
		cell.picture.layer.cornerRadius = layout.isSticker ? 0.0f : kMediaRadius;
		cell.picture.clipsToBounds = YES;

		cell.disc.hidden = ![kind isEqualToString:@"messageVideo"] && ![kind isEqualToString:@"messageAnimation"];
		if (!cell.disc.hidden) {
			CGFloat disc = 42;
			cell.disc.image = [TGIcons mediaDiscOfSide:disc playing:NO];
			cell.disc.frame = CGRectMake(kPadH + (layout.picSize.width - disc) / 2,
										 layout.pictureFrame.origin.y + (layout.picSize.height - disc) / 2, disc, disc);
		}

		if (!layout.bodySize.height) {
			cell.mediaStamp.hidden = NO;
			cell.mediaStamp.backgroundColor = [theme mediaStampColour];
			cell.mediaStamp.text = mine ? [NSString stringWithFormat:@"  %@", layout.stamp] : layout.stamp;
			cell.mediaStamp.textAlignment = mine ? NSTextAlignmentLeft : NSTextAlignmentCenter;
			cell.mediaStamp.frame = layout.mediaStampFrame;
			[cell.bubble bringSubviewToFront:cell.mediaStamp];
		}
	} else {
		cell.collageView.hidden = YES;
		cell.picture.hidden = YES;
		cell.picture.image = nil;
	}

	// Voice notes
	if (layout.isVoice) {
		TGTheme *voiceTheme = [TGTheme shared];
		CGFloat disc = 36;
		CGFloat left = kPadH + disc + 8;
		BOOL isPlaying = (self.playingMessageId == [m[@"id"] longLongValue] && self.voicePlayer && self.voicePlayer.playing);

		cell.voiceMessageId = [m[@"id"] longLongValue];
		cell.waveformData = m[@"waveform"];

		CGFloat fwd = layout.fwdHeight;

		cell.disc.hidden = NO;
		cell.disc.userInteractionEnabled = YES;
		cell.disc.image = [TGIcons mediaDiscOfSide:disc playing:isPlaying];
		cell.disc.frame = CGRectMake(kPadH, fwd + (layout.bubbleFrame.size.height - fwd - disc) / 2, disc, disc);
		if (!cell.disc.gestureRecognizers.count) {
			[cell.disc addGestureRecognizer:[[UITapGestureRecognizer alloc]
					initWithTarget:self action:@selector(voiceDiscTapped:)]];
		}

		cell.wave.hidden = NO;
		CGSize waveSize = CGSizeMake(layout.bubbleFrame.size.width - left - kPadH, 18);
		cell.wave.image = [TGIcons waveform:m[@"waveform"]
									   size:waveSize
									 played:(isPlaying ? [self playedFraction] : 0)
									 colour:[voiceTheme accentColour]];
		cell.wave.frame = CGRectMake(left, fwd + 10, waveSize.width, waveSize.height);
		cell.wave.userInteractionEnabled = YES;
		if (!cell.wave.gestureRecognizers.count) {
			[cell.wave addGestureRecognizer:[[UIPanGestureRecognizer alloc]
					initWithTarget:self action:@selector(waveformScrubbed:)]];
			[cell.wave addGestureRecognizer:[[UITapGestureRecognizer alloc]
					initWithTarget:self action:@selector(waveformScrubbed:)]];
		}

		NSInteger seconds = [m[@"duration"] integerValue];
		cell.body.hidden = NO;
		cell.body.numberOfLines = 1;
		cell.body.font = [UIFont systemFontOfSize:12];
		cell.body.textColor = [voiceTheme secondaryTextColour];
		cell.body.text = [NSString stringWithFormat:@"%ld:%02ld",
				(long)(seconds / 60), (long)(seconds % 60)];
		cell.body.frame = CGRectMake(left, layout.bubbleFrame.size.height - 20, 44, 14);

		cell.picture.hidden = YES;
		cell.time.text = layout.stamp;
		cell.time.textColor = [voiceTheme timeColour];
		CGFloat tickRoom = mine ? 18 : 0;
		cell.time.frame = CGRectMake(layout.bubbleFrame.size.width - layout.timeWidth - kPadH, layout.bubbleFrame.size.height - 20,
									 layout.timeWidth - tickRoom, 12);
		cell.ticks.hidden = !mine;
		if (mine) {
			cell.ticks.image = [TGIcons ticksWhite:NO];
			cell.ticks.frame = CGRectMake(layout.bubbleFrame.size.width - kPadH - 15, layout.bubbleFrame.size.height - 18, 15, 9);
		}
		return [self finalizeCell:cell message:m layout:layout isMine:mine];
	}

	cell.body.hidden = (layout.bodySize.height == 0 || layout.isSticker);
	cell.body.numberOfLines = 0;
	cell.body.lineBreakMode = NSLineBreakByWordWrapping;
	cell.body.font = [UIFont systemFontOfSize:[TGTheme shared].messageFontSize];
	NSArray *entities = m[@"entities"];
	if (entities.count) {
		cell.body.attributedText = TGAttributedMessageText(m[@"text"], entities, [UIFont systemFontOfSize:[TGTheme shared].messageFontSize], [theme primaryTextColour]);
	} else {
		TGSetBodyText(cell.body, m[@"text"], [theme primaryTextColour]);
	}
	cell.body.frame = layout.bodyFrame;

	cell.onLinkTapped = ^(NSString *url) {
		if (url.length) {
			NSURL *u = [NSURL URLWithString:url];
			if (!u.scheme.length) u = [NSURL URLWithString:[NSString stringWithFormat:@"http://%@", url]];
			if (u) [[UIApplication sharedApplication] openURL:u];
		}
	};

	// Reactions
	UILabel *reactions = (UILabel *)[cell.bubble viewWithTag:0x9002];
	NSString *reactionText = m[@"reactions"];
	if ([reactionText length]) {
		if (!reactions) {
			reactions = [[UILabel alloc] init];
			reactions.tag = 0x9002;
			reactions.backgroundColor = [UIColor clearColor];
			reactions.font = [UIFont systemFontOfSize:13];
			[cell.bubble addSubview:reactions];
		}
		reactions.hidden = NO;
		reactions.text = reactionText;
		reactions.textColor = [theme secondaryTextColour];
		reactions.frame = CGRectMake(kPadH, layout.bodyFrame.origin.y + layout.bodySize.height + 2, layout.bubbleFrame.size.width - 2 * kPadH, 16);
	} else {
		reactions.hidden = YES;
	}

	BOOL onPicture = !cell.mediaStamp.hidden;
	cell.time.text = (onPicture || [self albumContinuesAfterRow:indexPath.row]) ? @"" : layout.stamp;
	cell.time.textColor = [theme timeColour];
	cell.time.frame = layout.timeFrame;

	cell.ticks.hidden = !mine;
	if (mine && onPicture) {
		cell.ticks.image = [TGIcons ticksWhite:YES];
		cell.ticks.frame = CGRectMake(CGRectGetMaxX(cell.mediaStamp.frame) - 17,
									  CGRectGetMidY(cell.mediaStamp.frame) - 4.5f, 15, 9);
		[cell.bubble bringSubviewToFront:cell.ticks];
	} else if (mine) {
		cell.ticks.image = [TGIcons ticksWhite:NO];
		cell.ticks.frame = CGRectMake(layout.bubbleFrame.size.width - kPadH - 15, layout.timeFrame.origin.y + 2, 15, 9);
		[cell.bubble bringSubviewToFront:cell.ticks];
	}
	[cell.bubble bringSubviewToFront:cell.time];

	return [self finalizeCell:cell message:m layout:layout isMine:mine];
}

#pragma mark - keyboard

- (void)keyboardWillShow:(NSNotification *)note {
	CGRect kb = [[note.userInfo objectForKey:UIKeyboardFrameEndUserInfoKey] CGRectValue];
	[self shiftForKeyboardHeight:kb.size.height];
}

- (void)keyboardWillHide:(NSNotification *)note {
	[self shiftForKeyboardHeight:0];
}

- (void)shiftForKeyboardHeight:(CGFloat)height {
	CGRect b = self.view.bounds;
	[UIView animateWithDuration:0.25 animations:^{
		self.inputBar.frame = CGRectMake(0, b.size.height - kInputHeight - height,
				b.size.width, kInputHeight);
		self.table.frame = CGRectMake(0, 0, b.size.width,
				b.size.height - kInputHeight - height);
	} completion:^(BOOL done){
		[self scrollToBottomAnimated:NO];
	}];
}

@end

// vim:ft=objc
