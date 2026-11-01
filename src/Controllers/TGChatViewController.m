#import "TGPerf.h"
#import "TGChatViewController.h"
#import "TGClient.h"
#import "TGTheme.h"
#import "TGIcons.h"
#import "TGForwardPicker.h"
#import "TGVoiceRecorder.h"
#import "TGProfileViewController.h"
#import "TGThemeFile.h"
#import "TGCapabilities.h"
#import "TGDevice.h"
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
#import "TGDevShowcase.h"
#import "TGCallViewController.h"
#import "TGPopupMenu.h"
#import "TGSnackbar.h"
#import "TGMediaViewer.h"
#import "TGMusicPlayer.h"
#import "TGDevShowcase.h"

#import "TGMessageLayout.h"
#import "TGBubbleCell.h"

#import "TGChatViewControllerInternal.h"
#import "TGMessageStreamStore.h"
#import "TGStyle.h"
#import "TGAlertSheet.h"

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
	double vcStart = TGPerfNow();
	[self buildTitleView];
	TGPerfReport("chat vc", "title", vcStart, 50.0);
	self.streamStore = [[TGMessageStreamStore alloc] init];
	self.messages = @[];
	self.layoutCache = [[TGMessageLayoutCache alloc] initWithCapacity:500];
	self.gifPaths = [NSMutableDictionary dictionary];
	self.gifsRequested = [NSMutableSet set];
	self.senderAvatars = [[TGImageLruCache alloc] initWithCapacity:50];
	self.senderAvatarsRequested = [NSMutableSet set];
	// About 1.1 MB a photo (a 400 px decode plus its rounded copy): forty of
	// them were 45 MB, past where jetsam kills the app on a 256 MB phone. Rows
	// fetch an evicted photo again, so a small window is enough.
	TGDeviceTier tier = [TGDevice tier];
	self.images = [[TGImageLruCache alloc] initWithCapacity:
			tier == TGDeviceTierVintage ? 12 : tier == TGDeviceTierLegacy ? 24 : 40];
	self.imagesRequested = [NSMutableSet set];
	[[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(memoryWarning:)
			name:UIApplicationDidReceiveMemoryWarningNotification object:nil];
	self.lottiePaths = [NSMutableDictionary dictionary];
	self.maps = [[TGImageLruCache alloc] initWithCapacity:20];
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
	if ([TGCapabilities canShowWallpaper]) {
		// The pattern takes about a frame to render on the A4, and the chat
		// open paid for it inside the push: the tint shows at once, the
		// texture lands when the background thread finishes.
		__weak UIImageView *weakWallpaper = self.wallpaperView;
		self.wallpaperView.backgroundColor = [[TGTheme shared] chatBackgroundColour];
		dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_LOW, 0), ^{
			UIImage *image = [[TGTheme shared] wallpaper];
			dispatch_async(dispatch_get_main_queue(), ^{
				weakWallpaper.image = image;
			});
		});
	}
	[self.view addSubview:self.wallpaperView];

	// Hold a message for the things a chat needs and a tap cannot carry.
	[self.table addGestureRecognizer:[[UILongPressGestureRecognizer alloc]
			initWithTarget:self action:@selector(messageHeld:)]];

	UITapGestureRecognizer *tableTap = [[UITapGestureRecognizer alloc]
			initWithTarget:self action:@selector(tableTapped:)];
	tableTap.cancelsTouchesInView = NO;
	[self.table addGestureRecognizer:tableTap];

	[self.view addSubview:self.table];

	[self buildInputBar:b];
	TGPerfReport("chat vc", "input bar", vcStart, 100.0);
	[self buildChrome];
	[self refreshReplyKeyboard];
	[[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(replyMarkupChanged:)
			name:TGChatReplyMarkupChangedNotification object:nil];
	// Server-side composer facts: a bot's draft was stopped, or a scheduled
	// video went live. Both arrive as updates, not as a re-open.
	[[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(draftStopped:)
			name:TGChatDraftStoppedNotification object:nil];
	[[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(videoPublished:)
			name:TGChatVideoPublishedNotification object:nil];
	TGPerfReport("chat vc", "chrome", vcStart, 50.0);
	[self installSwipeToReply];
	TGPerfReport("chat vc", "swipe + load", vcStart, 100.0);

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
			// Reading further up: leave the place alone and count it on the
			// jump button instead. Your own message always brings you down.
			BOOL follow = [me isNearBottom] || [message[@"outgoing"] boolValue];
			[me.streamStore appendNewerMessages:@[message]];
			me.rawMessages = [me.streamStore messages];
			me.messages = [me groupedMessagesFromMessages:me.rawMessages];
			[me.table reloadData];
			if (follow) {
				me.atChatEnd = YES;
				[me scrollToBottomAnimated:YES];
			} else {
				[me noteArrivedWhileAway];
			}
			[me fetchMissingImages];
			[[TGClient shared] markRead:@[message[@"id"]] inChat:chatId];
			return;
		}
		if (deletedId > 0 && [me.streamStore removeMessageId:deletedId]){
			me.rawMessages = [me.streamStore messages];
			me.messages = [me groupedMessagesFromMessages:me.rawMessages];
			[me.table reloadData];
			return;
		}
		// edited or unknown deletion - re-read
		[me reload];
	};

	[[NSNotificationCenter defaultCenter] addObserver:self
			selector:@selector(musicChanged)
				name:TGMusicPlayerChangedNotification object:nil];
	// One tick turns into two when they read it.
	[[NSNotificationCenter defaultCenter] addObserver:self
			selector:@selector(readOutboxChanged:)
				name:TGChatReadOutboxChangedNotification object:nil];

	if (![TGDevShowcase isDevChatId:self.chatId]) {
		// Captured before opening marks everything read.
		self.readInboxAtOpen = [[TGClient shared] lastReadInboxForChat:self.chatId];
		[[TGClient shared] openChat:self.chatId];
		// Opening clears unread; the @ and the reaction badges are counted apart
		// from it and stay until they are read in their own right.
		[[TGClient shared] readAllMentionsAndReactionsInChat:self.chatId];
		// So are the votes: the badge on a fresh poll answer is the chat's to
		// see, and the chat has now seen it.
		[[TGClient shared] readAllChatPollVotes:self.chatId];

		// Whatever was typed here last and not sent - here or on another device.
		NSString *draft = [[TGClient shared] draftForChat:self.chatId];
		if (draft.length && !self.input.text.length){
			self.input.text = draft;
			[self inputChanged];
		}
	}

	[self reload];
	TGPerfReportMemory("chat opened");
	if ([TGDevShowcase isDevChatId:self.chatId]) {
		return;
	}
}

- (void)viewDidLayoutSubviews {
	[super viewDidLayoutSubviews];
	// The table started framed under the input bar, and autoresizing holds
	// only the width against a rotation - left alone the height would spread
	// the rows under the composer. The bar's own top edge is the honest
	// bottom: keyboard up or down, the table ends where the composer begins.
	if (!self.inputBar || CGRectIsEmpty(self.inputBar.frame))
		return;
	CGFloat width = self.view.bounds.size.width;
	CGFloat height = CGRectGetMinY(self.inputBar.frame);
	if (CGRectEqualToRect(self.table.frame, CGRectMake(0, 0, width, height)))
		return;
	BOOL widthChanged = self.table.frame.size.width != width;
	self.table.frame = CGRectMake(0, 0, width, height);
	if (widthChanged) {
		// Every bubble measured itself against the old width.
		[self.layoutCache removeAllObjects];
		[self.table reloadData];
	}
}

/// A two-line header: the chat name with member count or status beneath it,
/// which is what tells you where you are in a group.
- (void)buildTitleView {
	UIView *header = [[UIView alloc] initWithFrame:CGRectMake(0, 0, kTitleWidth, kTitleRow)];

	UILabel *name = [[UILabel alloc] initWithFrame:CGRectMake(0, TGMetricBorderWidth,
			kTitleWidth, TGMetricLineRow)];
	name.text = self.chatTitle ?: @"Chat";
	name.font = TGFontHeader();
	name.textColor = [[TGTheme shared] barTitleColour];
	name.backgroundColor = [UIColor clearColor];
	name.textAlignment = NSTextAlignmentCenter;
	name.shadowColor = [[TGTheme shared] navBarTextShadowColour];
	name.shadowOffset = TGMetricShadowOffsetNav;
	[header addSubview:name];
	self.titleNameLabel = name;

	UILabel *subtitle = [[UILabel alloc] initWithFrame:CGRectMake(0,
			TGMetricBorderWidth + TGMetricLineRow, kTitleWidth, TGMetricLineMicro)];
	subtitle.font = TGFontMeta();
	subtitle.textColor = [[TGTheme shared] barSubtitleColour];
	subtitle.backgroundColor = [UIColor clearColor];
	subtitle.textAlignment = NSTextAlignmentCenter;
	[header addSubview:subtitle];
	self.titleSubtitleLabel = subtitle;

	header.userInteractionEnabled = YES;
	[header addGestureRecognizer:[[UITapGestureRecognizer alloc]
			initWithTarget:self action:@selector(openProfile)]];
	// The tap opens the profile; the hold offers what a secret chat needs
	// that no menu row reaches: ending it.
	UILongPressGestureRecognizer *headerHold = [[UILongPressGestureRecognizer alloc]
			initWithTarget:self action:@selector(headerHeld:)];
	headerHold.minimumPressDuration = 0.6;
	[header addGestureRecognizer:headerHold];
	self.navigationItem.titleView = header;
	[self buildAvatarButton];

	// "typing..." takes the subtitle over while it lasts, then hands it back.
	__weak typeof(self) weakSelf = self;
	self.restingSubtitle = @"";

	// The subtitle belongs to the network whenever TDLib is not ready (B4):
	// a chat opened offline used to freeze at its captured "last seen"
	// instead of breathing "Waiting for network".
	NSNotificationCenter *nc = [NSNotificationCenter defaultCenter];
	[nc addObserver:self selector:@selector(titleSubtitleOwnerChanged:)
			name:TGConnectionStateChangedNotification object:nil];
	[nc addObserver:self selector:@selector(titleSubtitleOwnerChanged:)
			name:TGUserStatusChangedNotification object:nil];
	[TGClient shared].onChatAction = ^(int64_t chatId, NSString *action){
		if (chatId != weakSelf.chatId)
			return;
		[weakSelf showChatAction:action resting:weakSelf.restingSubtitle];
	};

	// An imported theme can arrive while a chat is open - repaint rather than
	// wait for the screen to be pushed again.
	[[NSNotificationCenter defaultCenter] addObserver:self
			selector:@selector(themeChanged:)
				name:TGThemeChangedNotification object:nil];

	// A secret chat's state is its header, and it can change while you
	// watch: the key exchange answers, or the other side closes the chat.
	[[TGClient shared] secretChatIdForChat:self.chatId completion:^(NSInteger secretId){
		if (!secretId)
			return;
		weakSelf.secretChatId = secretId;
		[weakSelf refreshSecretState];
	}];
	[TGClient shared].onSecretChat = ^(NSInteger secretChatId, NSString *state){
		if (secretChatId != weakSelf.secretChatId)
			return;
		[weakSelf refreshSecretState];
	};

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
			weakSelf.restingSubtitle = status;
			[weakSelf titleSubtitleOwnerChanged:nil];
		}];
		return;
	}

	[[TGClient shared] memberCountForChat:self.chatId completion:^(NSInteger count){
		if (count > 0){
			weakSelf.restingSubtitle = [NSString stringWithFormat:@"%ld members", (long)count];
			[weakSelf titleSubtitleOwnerChanged:nil];
		}
	}];
}

- (void)themeChanged:(NSNotification *)note {
	[TGIcons flush];
	TGTheme *theme = [TGTheme shared];
	[self.layoutCache removeAllObjects];
	self.view.backgroundColor = [theme chatBackgroundColour];
	self.table.backgroundColor = [UIColor clearColor];
	self.inputBar.backgroundColor = [theme inputBarColour];
	self.input.backgroundColor = [theme listBackgroundColour];
	self.input.textColor = [theme primaryTextColour];
	self.input.layer.borderColor = [theme separatorColour].CGColor;
	self.input.keyboardAppearance = UIKeyboardAppearanceLight;
	self.sendButton.backgroundColor = [theme accentColour];
	self.wallpaperView.image = [theme wallpaper];
	self.titleNameLabel.textColor = [theme barTitleColour];
	self.titleSubtitleLabel.textColor = [theme barSubtitleColour];
	if (self.pinnedBannerView) {
		self.pinnedBannerView.backgroundColor = [theme inputBarColour];
		self.pinnedBannerHair.backgroundColor = [theme separatorColour];
	}
	if (self.recordPanel) {
		self.recordPanel.backgroundColor = [theme inputBarColour];
	}
	[self.stickerPanel applyTheme];
	[self applyChromeTheme:theme];
	if (self.editToolbar) {
		self.editToolbar.backgroundColor = [theme inputBarColour];
		[self.editDeleteButton setTitleColor:[theme destructiveColour] forState:UIControlStateNormal];
		[self.editForwardButton setTitleColor:[theme accentColour] forState:UIControlStateNormal];
	}
	[theme styleNavigationBar:self.navigationController.navigationBar];
	[self.table reloadData];
}

/// A voice note going on playing after you have left the chat is the one thing
/// nobody expects, and the timer would outlive the screen it repaints.
- (void)viewWillDisappear:(BOOL)animated {
	[super viewWillDisappear:animated];
	if (self.voicePlayer)
		[self stopPlayback];
	[self stopVideoNote];
	// The GPS is the chat's, not the app's: a trace watched from this screen
	// stops being watched when the screen is gone.
	[self.locationManager stopUpdatingLocation];
	[TGSnackbar commitNow];
	// Dismissing the menu restores the held message through its onDismiss;
	// this covers the one window where the lift exists but its menu has not
	// been added yet.
	[TGPopupMenu dismiss];
	[self endHoldPresentation];

	[NSObject cancelPreviousPerformRequestsWithTarget:self.table];
	[NSObject cancelPreviousPerformRequestsWithTarget:self];

	if ([self isMovingFromParentViewController]) {
		// An unsent message is a draft, not something to throw away. Saved
		// before closeChat so the chat list redraws with it in place.
		//
		// Only when it actually differs from the draft already there. It used
		// to be sent on the way out of every chat, which meant a clear-draft
		// request for every chat anybody ever opened - and in a channel this
		// account does not administer Telegram refuses it, so the device log
		// filled with "Need administrator rights in the channel chat" for
		// drafts nobody had typed.
		NSString *typed = self.input.text ?: @"";
		NSString *stored = [[TGClient shared] draftForChat:self.chatId] ?: @"";
		if (self.editingId == 0 && ![typed isEqualToString:stored])
			[[TGClient shared] setDraft:typed
								 inChat:self.chatId
								 thread:self.threadId
								replyTo:self.replyToId];
		if (![TGDevShowcase isDevChatId:self.chatId]) {
			[[TGClient shared] cancelTypingInChat:self.chatId thread:self.threadId];
			[[TGClient shared] closeChat:self.chatId];
		}
		[TGClient shared].onMessage = nil;
		[TGClient shared].onChatAction = nil;
		[TGClient shared].onSecretChat = nil;
		[self stopChrome];
		[TGClient shared].onFileProgress = nil;
		[self.images removeAllObjects];
		[self.imagesRequested removeAllObjects];
		[self.senderAvatars removeAllObjects];
		[self.senderAvatarsRequested removeAllObjects];
		[self.maps removeAllObjects];
		[self.mapsRequested removeAllObjects];
		[self.quotes removeAllObjects];
		[self.quotesRequested removeAllObjects];
		[self.layoutCache removeAllObjects];
	}
}

/// Keeps only the photos on screen. Nothing used to answer a memory warning,
/// so the next step after one was jetsam; an evicted photo comes back when its
/// row is drawn again (fetchImageForMessage:).
- (void)memoryWarning:(NSNotification *)note {
	NSMutableArray *keepIds = [NSMutableArray array];
	NSMutableArray *keepImages = [NSMutableArray array];
	for (NSIndexPath *path in self.table.indexPathsForVisibleRows) {
		if (path.row >= (NSInteger)self.messages.count)
			continue;
		NSDictionary *m = self.messages[path.row];
		NSArray *parts = [m[@"albumMessages"] isKindOfClass:NSArray.class] ? m[@"albumMessages"] : @[m];
		for (NSDictionary *part in parts) {
			NSNumber *fileId = part[@"photoId"];
			UIImage *img = [fileId isKindOfClass:NSNumber.class] ? self.images[fileId] : nil;
			if (img) {
				[keepIds addObject:fileId];
				[keepImages addObject:img];
			}
		}
	}
	[self.images removeAllObjects];
	for (NSUInteger i = 0; i < keepIds.count; i++)
		self.images[keepIds[i]] = keepImages[i];
	[self.senderAvatars removeAllObjects];
	[self.senderAvatarsRequested removeAllObjects];
	NSLog(@"memory warning: chat kept %lu photos", (unsigned long)keepIds.count);
}

- (void)dealloc {
	[NSObject cancelPreviousPerformRequestsWithTarget:self.table];
	[NSObject cancelPreviousPerformRequestsWithTarget:self];
	[self.playbackTimer invalidate];
	self.playbackTimer = nil;
	[self.recordTimer invalidate];
	self.recordTimer = nil;
	[[NSNotificationCenter defaultCenter] removeObserver:self];
}

#pragma mark - data

- (void)readOutboxChanged:(NSNotification *)note {
	if ([note.userInfo[@"chatId"] longLongValue] == self.chatId)
		[self reloadTableDebounced];
}

/// updateStopMessageDraft names the chat, topic and draft. The composer only
/// clears when it still holds the text the client had cached: a stop must not
/// wipe words typed after it. The table reloads either way, because the
/// message being streamed may have changed too.
- (void)draftStopped:(NSNotification *)note {
	NSDictionary *info = note.userInfo;
	if ([info[@"chat_id"] longLongValue] != self.chatId)
		return;
	int64_t topicId = [info[@"forum_topic_id"] longLongValue];
	if (topicId && topicId != self.threadId)
		return;
	NSString *draft = info[@"draft_text"];
	if ([draft isKindOfClass:NSString.class] && draft.length &&
			[self.input.text isEqualToString:draft]){
		self.input.text = @"";
		[self inputChanged];
	}
	[self reloadTableDebounced];
	[TGSnackbar showInView:self.view text:@"Draft stopped" seconds:2 onCommit:nil];
}

/// updateVideoPublished says which message gained the video. The history is
/// re-read rather than patched, because the message's kind and its file both
/// changed; the chat list is nudged by the client on the same update.
- (void)videoPublished:(NSNotification *)note {
	if ([note.userInfo[@"chat_id"] longLongValue] != self.chatId)
		return;
	[self reload];
	[TGSnackbar showInView:self.view text:@"Video published" seconds:2 onCommit:nil];
}

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

	return [self messagesWithSeparators:grouped];
}

- (void)reload {
	if ([TGDevShowcase isDevChatId:self.chatId]) {
		double fixtureStart = TGPerfNow();
		NSArray *messages = [TGDevShowcase messagesForChatId:self.chatId];
		TGPerfReport("chat dev", "fixtures", fixtureStart, 50.0);
		[self noteFirstUnreadIn:messages];
		[self.streamStore resetWithMessages:messages];
		self.rawMessages = [self.streamStore messages];
		self.messages = [self groupedMessagesFromMessages:self.rawMessages];
		double buildStart = TGPerfNow();
		TGPerfReport("chat dev", "grouping", buildStart, 50.0);
		self.atChatEnd = YES;
		self.anchorToBottom = NO;

		NSString *tgsPath = [TGDevShowcase devStickerPath];
		NSString *webmPath = [TGDevShowcase devWebMPath];
		if (tgsPath) self.lottiePaths[@(-101)] = tgsPath;
		if (webmPath) self.lottiePaths[@(-102)] = webmPath;

		// iOS 6 asks this delegate for the height of every row during
		// reloadData, so the layout of the whole chat runs synchronously
		// here - the "outed" tap on this tier. The chip names it exact.
		double tableStart = TGPerfNow();
		[self.table reloadData];
		TGPerfReport("chat table", "layouts during reload", tableStart, 150.0);
		return;
	}

	__weak typeof(self) weakSelf = self;
	double chatStart = TGPerfNow();
	[[TGClient shared] historyForChat:self.chatId thread:self.threadId limit:60 completion:^(NSArray *messages){
		TGChatViewController *me = weakSelf;
		if (!me)
			return;
		TGPerfReport("chat load", "history wait", chatStart, 300.0);
		BOOL firstLoad = !me.unreadChecked;
		[me noteFirstUnreadIn:messages];
		[me.streamStore resetWithMessages:messages];
		me.rawMessages = [me.streamStore messages];
		me.messages = [me groupedMessagesFromMessages:me.rawMessages];
		me.atChatEnd = YES;
		NSInteger unreadRow = firstLoad ? [me unreadSeparatorRow] : NSNotFound;
		// hold the bottom until the media has settled - unless the chat opens
		// at what you have not read yet
		me.anchorToBottom = unreadRow == NSNotFound;
		if (me.anchorToBottom)
			dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(6.0 * NSEC_PER_SEC)),
					dispatch_get_main_queue(), ^{ me.anchorToBottom = NO; });
		// kinds only - the content is the user's, the log is read remotely
		NSMutableArray *kinds = [NSMutableArray array];
		for (NSDictionary *m in messages)
			[kinds addObject:m[@"kind"] ?: @"?"];
		NSLog(@"TDLIB HISTORY: %lu msgs: %@",
				(unsigned long)messages.count, [kinds componentsJoinedByString:@", "]);
		// The layout of thirty visible rows is what a first paint on the A4
		// really pays for; the network wait is logged on its own.
		double tableStart = TGPerfNow();
		[me.table reloadData];
		TGPerfReport("chat table", "reloadData", tableStart, 100.0);
		if (me.initialMessageId){
			// Opened by a link to one message: the unread separator and the
			// bottom both lose to the message the tap was about.
			int64_t target = me.initialMessageId;
			me.initialMessageId = 0;
			[me showMessageId:target gone:@"That message is not in this chat"];
			[me fetchMissingImages];
			[me resolveUnknownSenders];
			return;
		}
		if (unreadRow != NSNotFound)
			[me.table scrollToRowAtIndexPath:[NSIndexPath indexPathForRow:unreadRow inSection:0]
							atScrollPosition:UITableViewScrollPositionTop animated:NO];
		else
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

- (void)scrollToBottomAnimated:(BOOL)animated {
	if (!self.messages.count)
		return;
	NSIndexPath *last = [NSIndexPath indexPathForRow:self.messages.count - 1 inSection:0];
	[self.table scrollToRowAtIndexPath:last
					  atScrollPosition:UITableViewScrollPositionBottom animated:animated];
}

/// Telegram puts the chat's picture top right, and it opens the profile.
- (void)buildAvatarButton {
	// 42dp in their header, which is 37 here and still clears a 44pt bar.
	CGFloat side = 37;
	UIButton *button = [UIButton buttonWithType:UIButtonTypeCustom];
	button.frame = CGRectMake(0, 0, side, side);
	// No clip: the nav bar is recomposited on every frame of a scroll, and a
	// rounded clip there is an offscreen pass each time. The images below are
	// round already.
	[button addTarget:self action:@selector(openProfile)
	 forControlEvents:UIControlEventTouchUpInside];

	NSString *title = self.chatTitle ?: @"";
	BOOL isSaved = (self.chatId == [[TGClient shared] savedMessagesChatId]);
	[button setImage:(isSaved
			? [TGIcons savedMessagesAvatarOfSide:side]
			: [TGIcons avatarWithInitials:[TGIcons initialsForTitle:title]
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
			photo = [TGIcons roundedImage:photo size:CGSizeMake(side, side) radius:TGHalf(side)
								  corners:UIRectCornerAllCorners];
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
	profile.onJumpToDateTapped = ^{
		[weakSelf.navigationController popViewControllerAnimated:YES];
		[weakSelf showJumpToDateSheet];
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
		mute.titleLabel.font = TGFontBody();
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

/// The pinned message, which may be far above whatever the chat has loaded.
- (void)pinnedBannerTapped {
	if (self.pinnedMessageId)
		[self showMessageId:self.pinnedMessageId gone:@"The pinned message is gone"];
}

/// Scrolls to a message; when it is outside the loaded window the history is
/// fetched around it, replacing what was on screen the way following a reply
/// upwards does, and the scroll is tried again. `gone` is said if even that
/// does not find it.
- (void)showMessageId:(int64_t)messageId gone:(NSString *)gone {
	if ([self scrollToMessageId:messageId])
		return;
	__weak typeof(self) weakSelf = self;
	[[TGClient shared] historyForChat:self.chatId
						 fromMessageId:messageId
								 limit:(NSInteger)TGMetricHistoryPageAroundPinned
							completion:^(NSArray *messages){
		TGChatViewController *me = weakSelf;
		if (!me || !messages.count)
			return;
		[me.streamStore resetWithMessages:messages];
		me.rawMessages = [me.streamStore messages];
		me.messages = [me groupedMessagesFromMessages:me.rawMessages];
		me.atChatEnd = NO;
		me.atChatStart = NO;
		[me.table reloadData];
		if (![me scrollToMessageId:messageId])
			[TGSnackbar showInView:me.view text:gone seconds:2 onCommit:nil];
	}];
}

/// Holding the strip offers the one thing a tap cannot: taking every pinned
/// message down at once.
- (void)pinnedBannerHeld:(UILongPressGestureRecognizer *)hold {
	if (hold.state != UIGestureRecognizerStateBegan)
		return;
	int64_t chatId = self.chatId, threadId = self.threadId;
	__weak typeof(self) weakSelf = self;
	[TGAlertSheet showConfirm:@"Every pinned message in this chat is unpinned."
						title:@"Unpin All Messages"
					   action:@"Unpin All"
				  destructive:YES
					   inView:self.view
					onConfirm:^{
		[[TGClient shared] unpinAllMessagesInChat:chatId thread:threadId];
		weakSelf.pinnedMessageId = 0;
		[weakSelf hidePinnedBanner];
	}];
}

/// A day to go to: the last message sent on or before the end of it.
- (void)showJumpToDateSheet {
	TGSheet *sheet = [TGSheet sheetForView:self.view.window ?: self.view];
	UIView *card = [sheet addCardOfHeight:TGMetricRow * 2 + TGMetricPickerHeight edgeToEdge:YES];
	UIDatePicker *picker = [[UIDatePicker alloc] initWithFrame:
			CGRectMake(0, TGMetricRow, card.bounds.size.width, TGMetricPickerHeight)];
	picker.datePickerMode = UIDatePickerModeDate;
	picker.maximumDate = [NSDate date];
	[card addSubview:picker];
	UIToolbar *bar = [[UIToolbar alloc] initWithFrame:CGRectMake(0, 0, card.bounds.size.width, TGMetricRow)];
	bar.items = @[
		[[UIBarButtonItem alloc] initWithTitle:@"Cancel" style:UIBarButtonItemStylePlain
				target:sheet action:@selector(dismiss)],
		[[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemFlexibleSpace
				target:nil action:nil],
		[[UIBarButtonItem alloc] initWithTitle:@"Go" style:UIBarButtonItemStyleDone
				target:self action:@selector(jumpToDateCommit:)],
	];
	UILabel *countLabel = [[UILabel alloc] initWithFrame:CGRectMake(
			TGMetricPad, TGMetricRow + TGMetricPickerHeight - TGMetricPad,
			card.bounds.size.width - TGMetricPad - TGMetricPad, TGMetricRow)];
	countLabel.font = TGFontCaption();
	countLabel.textColor = [[TGTheme shared] secondaryTextColour];
	countLabel.text = @"counting...";
	[card addSubview:countLabel];
	self.pickCountLabel = countLabel;
	self.pickPicker = picker;
	self.pickSheet = sheet;
	[sheet present];

	// The one number the sheet never knew: how big this chat carries. A
	// folder applies its own answer, so the chat itself is asked.
	NSString *line = self.chatTitle ?: @"This chat";
	__weak typeof(self) weakSelf = self;
	[[TGClient shared] messageCountInChat:self.chatId thread:self.threadId
			completion:^(NSInteger count){
		NSString *say = count > 0
				? [NSString stringWithFormat:@"%@: %ld messages total",
								   line, (long)count]
				: [NSString stringWithFormat:@"%@: no server answer", line];
		TGChatViewController *me = weakSelf ? weakSelf : nil;
		if (!me || !me.pickCountLabel)
			return;
		me.pickCountLabel.text = say;
	}];
}

- (void)jumpToDateCommit:(UIBarButtonItem *)sender {
	NSDate *day = self.pickPicker.date;
	[self.pickSheet dismiss];
	self.pickSheet = nil;
	self.pickPicker = nil;
	// End of the chosen day in local time: "the 3rd" includes its evening.
	NSCalendar *calendar = [NSCalendar currentCalendar];
	NSDateComponents *c = [calendar components:NSYearCalendarUnit | NSMonthCalendarUnit | NSDayCalendarUnit
									  fromDate:day];
	c.hour = 23; c.minute = 59; c.second = 59;
	NSTimeInterval end = [[calendar dateFromComponents:c] timeIntervalSince1970];
	__weak typeof(self) weakSelf = self;
	// One stop instead of two: the calendar answers both the message to
	// land on and how many the chat has carried all along.
	[[TGClient shared] calendarJumpForChat:self.chatId
									endDate:(NSInteger)end
								completion:^(int64_t messageId, NSInteger total){
		TGChatViewController *me = weakSelf;
		if (!me)
			return;
		if (messageId){
			[me showMessageId:messageId gone:@"That message is gone"];
			return;
		}
		// The calendar query is a search and can answer nothing while the
		// day still holds a message; getChatMessageByDate is the direct
		// lookup for exactly that day.
		[[TGClient shared] messageAtDate:end inChat:me.chatId
							  completion:^(NSDictionary *found){
			int64_t foundId = [found[@"id"] longLongValue];
			if (!foundId){
				[TGSnackbar showInView:me.view
								  text:@"Nothing that old in this chat"
							   seconds:2 onCommit:nil];
				return;
			}
			[me showMessageId:foundId gone:@"That message is gone"];
		}];
	}];
}

/// A channel post's comments: a thread in the discussion group, opened as a
/// chat of its own the way forum topics are.
- (void)openCommentsForMessage:(NSDictionary *)m {
	__weak typeof(self) weakSelf = self;
	[[TGClient shared] commentThreadForChat:self.chatId messageId:[m[@"id"] longLongValue]
								 completion:^(int64_t discussionChatId, int64_t threadId, NSString *error){
		TGChatViewController *me = weakSelf;
		if (!me)
			return;
		if (error) {
			[TGAlertSheet showMessage:error title:@"Comments" inView:me.view];
			return;
		}
		TGChatViewController *thread = [[TGChatViewController alloc] init];
		thread.chatId = discussionChatId;
		thread.threadId = threadId;
		thread.chatTitle = @"Comments";
		thread.isGroup = YES;
		thread.hidesBottomBarWhenPushed = YES;
		[me.navigationController pushViewController:thread animated:YES];
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
		cell.contentView.alpha = TGAlphaHighlight;
		[UIView animateWithDuration:TGAnimationDurationHighlight animations:^{ cell.contentView.alpha = TGAlphaOpaque; }];
		return YES;
	}
	return NO;
}

/// Following a reply. The loaded window first; then a fetched window around
/// what it answers, replacing what was on screen the way the pinned banner
/// does; then the chat that actually holds it, because a reply can point
/// across chats - and that one opens rather than scrolls.
- (void)jumpToReplyById:(int64_t)replyId {
	if (!replyId)
		return;
	if ([self scrollToMessageId:replyId])
		return;

	__weak typeof(self) weakSelf = self;
	[[TGClient shared] historyForChat:self.chatId
						fromMessageId:replyId
								limit:(NSInteger)TGMetricHistoryPageAroundPinned
						   completion:^(NSArray *messages){
		TGChatViewController *me = weakSelf;
		if (!me)
			return;
		if (messages.count){
			[me.streamStore resetWithMessages:messages];
			me.rawMessages = [me.streamStore messages];
			me.messages = [me groupedMessagesFromMessages:me.rawMessages];
			me.atChatEnd = NO;
			me.atChatStart = NO;
			[me.table reloadData];
			if ([me scrollToMessageId:replyId])
				return;
		}
		// Not in this chat's history: ask TDLib what the reply names.
		[[TGClient shared] repliedMessageTo:replyId inChat:me.chatId
								 completion:^(NSDictionary *reply){
			TGChatViewController *inner = weakSelf;
			if (!inner)
				return;
			int64_t otherChat = reply ? [reply[@"chatId"] longLongValue] : 0;
			if (otherChat && otherChat != inner.chatId){
				NSString *title = [[TGClient shared] titleForChat:otherChat] ?: @"Chat";
				TGChatViewController *other = [[TGChatViewController alloc] init];
				other.chatId = otherChat;
				other.chatTitle = title;
				other.hidesBottomBarWhenPushed = YES;
				[inner.navigationController pushViewController:other animated:YES];
				return;
			}
			[TGSnackbar showInView:inner.view
							  text:@"The replied message is gone"
						   seconds:2 onCommit:nil];
		}];
	}];
}

/// The option that was tapped opens its own card: what TDLib says the answer
/// still allows, then the vote. Voting is still one tap later, because the
/// vote is irreversible and the card is the honest place to say what the
/// answer can be used for. Which poll it belongs to comes from the cell it
/// sits in, because a button knows nothing about messages.
- (void)pollOptionTapped:(UIButton *)option {
	UIView *view = option;
	while (view && ![view isKindOfClass:TGBubbleCell.class])
		view = view.superview;
	TGBubbleCell *cell = (TGBubbleCell *)view;
	if (!cell || !cell.pollMessageId)
		return;

	NSInteger index = option.tag - 0x9100;
	NSDictionary *message = nil;
	for (NSDictionary *candidate in self.messages){
		if ([candidate[@"id"] longLongValue] == cell.pollMessageId){
			message = candidate;
			break;
		}
	}
	NSArray *options = message[@"pollOptions"];
	NSDictionary *pollOption = (index >= 0 && index < (NSInteger)options.count)
			? options[(NSUInteger)index] : nil;
	NSString *optionId = pollOption[@"id"];
	id optionText = pollOption[@"text"];
	NSString *label = [optionText isKindOfClass:NSDictionary.class]
			? (optionText[@"text"] ?: @"")
			: ([optionText isKindOfClass:NSString.class] ? optionText : @"This answer");
	BOOL closed = [message[@"pollClosed"] boolValue];

	__weak typeof(self) weakSelf = self;
	[[TGClient shared] pollOptionProperties:(optionId ?: @"")
								 ofMessage:cell.pollMessageId
									inChat:self.chatId
								completion:^(NSDictionary *properties, NSString *error){
		TGChatViewController *me = weakSelf;
		if (!me)
			return;

		NSString *body;
		if (properties){
			body = [NSString stringWithFormat:
					@"Can be deleted: %@\nCan be replied to: %@\n"
					@"Can be replied to in another chat: %@\nCan get a link: %@",
					[properties[@"canBeDeleted"] boolValue] ? @"yes" : @"no",
					[properties[@"canBeReplied"] boolValue] ? @"yes" : @"no",
					[properties[@"canBeRepliedInAnotherChat"] boolValue] ? @"yes" : @"no",
					[properties[@"canGetLink"] boolValue] ? @"yes" : @"no"];
		} else {
			body = error ?: @"Telegram did not answer with the answer's properties.";
		}

		void (^vote)(void) = ^{
			[[TGClient shared] votePoll:cell.pollMessageId
								 inChat:me.chatId
								options:@[@(index)]];
			// TDLib answers with an updated message; re-read so the shares move.
			dispatch_after(dispatch_time(DISPATCH_TIME_NOW,
					(int64_t)(1.0 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
				[me reload];
			});
		};

		if (closed){
			[TGAlertSheet showMessage:body title:label inView:me.view];
			return;
		}
		[TGAlertSheet showChoices:@[@"Vote for this answer"]
							title:label
						  message:body
				 destructiveIndex:-1
						   inView:me.view
						 onChoice:^(NSInteger choice){ vote(); }];
	}];
}

#pragma mark - pinned message

/// A strip under the navigation bar, the way clients surface what is pinned.
- (void)loadPinnedMessage {
	__weak typeof(self) weakSelf = self;
	[[TGClient shared] pinnedMessageForChat:self.chatId completion:^(NSDictionary *m){
		TGChatViewController *me = weakSelf;
		me.pinnedMessageId = [m[@"id"] longLongValue];
		NSString *text = m[@"text"];
		if (!text.length){
			[me hidePinnedBanner];
			return;
		}
		[me showPinnedBanner:text];
	}];
}

/// Takes the strip away and gives the list back the room it had. Reached
/// when the pinned message is unpinned from the message menu.
- (void)hidePinnedBanner {
	if (!self.pinnedBannerView)
		return;
	[self.pinnedBannerView removeFromSuperview];
	self.pinnedBannerView = nil;
	self.pinnedBannerHair = nil;

	UIEdgeInsets insets = self.table.contentInset;
	insets.top = MAX(0, insets.top - 34);
	self.table.contentInset = insets;
	self.table.scrollIndicatorInsets = insets;
}

- (void)showPinnedBanner:(NSString *)text {
	// One strip at a time: pinning a second message replaces the first.
	[self hidePinnedBanner];
	CGRect b = self.view.bounds;
	TGTheme *theme = [TGTheme shared];
	UIView *banner = [[UIView alloc] initWithFrame:CGRectMake(0, 0, b.size.width,
			kPinnedBanner)];
	banner.backgroundColor = [theme inputBarColour];
	banner.autoresizingMask = UIViewAutoresizingFlexibleWidth;

	UIView *stripe = [[UIView alloc] initWithFrame:CGRectMake(TGMetricPad,
			TGMetricPadSmall, kQuoteBarWidth, kPinnedBanner - TGMetricPadMedium)];
	stripe.backgroundColor = [theme accentColour];
	[banner addSubview:stripe];

	UILabel *label = [[UILabel alloc] initWithFrame:CGRectMake(TGMetricPadLarge, TGMetricPadTiny,
			b.size.width - TGMetricPinnedBannerTextPadRight, TGMetricLineMicro)];
	label.text = @"Pinned message";
	label.font = TGFontMicroStrong();
	label.textColor = [theme accentColour];
	label.backgroundColor = [UIColor clearColor];
	[banner addSubview:label];

	UILabel *body = [[UILabel alloc] initWithFrame:CGRectMake(TGMetricPadLarge, TGMetricPadTiny + TGMetricLineMicro,
			b.size.width - TGMetricPinnedBannerTextPadRight, TGMetricLineCaption)];
	body.text = text;
	body.font = TGFontCaption();
	body.textColor = [theme primaryTextColour];
	body.backgroundColor = [UIColor clearColor];
	body.autoresizingMask = UIViewAutoresizingFlexibleWidth;
	[banner addSubview:body];

	UIView *hair = [[UIView alloc] initWithFrame:CGRectMake(0,
			kPinnedBanner - TGMetricBorderWidth, b.size.width, TGMetricBorderWidth)];
	hair.backgroundColor = [theme separatorColour];
	hair.autoresizingMask = UIViewAutoresizingFlexibleWidth;
	[banner addSubview:hair];

	[self.view addSubview:banner];
	// Tapping the strip goes to what is pinned, which is the whole reason a
	// client shows it. It had no tap handler at all.
	banner.userInteractionEnabled = YES;
	[banner addGestureRecognizer:[[UITapGestureRecognizer alloc]
			initWithTarget:self action:@selector(pinnedBannerTapped)]];
	[banner addGestureRecognizer:[[UILongPressGestureRecognizer alloc]
			initWithTarget:self action:@selector(pinnedBannerHeld:)]];

	self.pinnedBannerView = banner;
	self.pinnedBannerHair = hair;

	// Push the message list down so the banner does not cover the first row.
	UIEdgeInsets insets = self.table.contentInset;
	insets.top += 34;
	self.table.contentInset = insets;
	self.table.scrollIndicatorInsets = insets;
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

	__weak typeof(self) weakSelf = self;
	NSString *dialable = [[phone componentsSeparatedByCharactersInSet:
			[[NSCharacterSet characterSetWithCharactersInString:@"+0123456789"]
					invertedSet]] componentsJoinedByString:@""];
	[TGAlertSheet showChoices:@[phone.length ? [NSString stringWithFormat:@"Call %@", phone]
											 : @"Call",
								@"Add to Contacts",
								@"Copy Phone Number"]
						title:name.length ? name : @"Contact"
			 destructiveIndex:-1
					   inView:self.view
					 onChoice:^(NSInteger index){
		TGChatViewController *me = weakSelf;
		if (index == 0){
			if (dialable.length)
				[[UIApplication sharedApplication] openURL:[NSURL URLWithString:
						[NSString stringWithFormat:@"tel:%@", dialable]]];
		} else if (index == 1){
			[me presentAddContactForMessage:m];
		} else {
			[UIPasteboard generalPasteboard].string = phone ?: @"";
			[TGSnackbar showInView:me.view text:@"Phone number copied"
						   seconds:2 onCommit:^{}];
		}
	}];
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
			NSString *title = [m[@"venue"] isKindOfClass:[NSDictionary class]] ? m[@"venue"][@"title"] : nil;
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
	if (replyTo){
		[self jumpToReplyById:replyTo.longLongValue];
		return;
	}

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
		[kind isEqualToString:@"messageAnimation"] ||
		[kind isEqualToString:@"messagePhoto"] ||
		[m[@"isAlbum"] boolValue]){
		NSArray *albumMsgs = [m[@"isAlbum"] boolValue] ? m[@"albumMessages"] : nil;
		if (albumMsgs.count) {
			[TGMediaViewer presentItems:albumMsgs
								startAt:0
								 inChat:self.chatId
								isAlbum:YES];
			return;
		}
		NSArray *pool = self.rawMessages.count ? self.rawMessages : self.messages;
		NSInteger targetIdx = [pool indexOfObject:m];
		if (targetIdx == NSNotFound) targetIdx = 0;
		[TGMediaViewer presentItems:pool
							startAt:targetIdx
							 inChat:self.chatId
							isAlbum:NO];
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
	[TGAlertSheet showMessage:@"Cannot play this audio" title:nil inView:self.view];
}

#pragma mark - pagination & scroll

- (void)tableTapped:(UITapGestureRecognizer *)gesture {
	[self hideStickerPanel];
	[self.input resignFirstResponder];
}

- (void)scrollViewWillBeginDragging:(UIScrollView *)scrollView {
	if (scrollView == self.table) {
		[self hideStickerPanel];
		[self.input resignFirstResponder];
	}
}

- (void)scrollViewDidScroll:(UIScrollView *)scrollView {
    if (scrollView == self.table)
        [self chromeDidScroll];
    if (scrollView != self.table || !self.messages.count)
        return;
    
    // 1. Load older messages when scrolled near the top
    if (scrollView.contentOffset.y < (CGFloat)TGMetricHistoryTopGate && !self.isLoadingMoreHistory && !self.atChatStart) {
        self.isLoadingMoreHistory = YES;
        int64_t fromMessageId = self.streamStore.oldestMessageId;
        if (!fromMessageId) {
            NSArray *pool = self.rawMessages.count ? self.rawMessages : self.messages;
            fromMessageId = [pool.firstObject[@"id"] longLongValue];
        }
        
        __weak typeof(self) weakScroll = self;
        [[TGClient shared] historyForChat:self.chatId fromMessageId:fromMessageId limit:60 completion:^(NSArray *older) {
            dispatch_async(dispatch_get_main_queue(), ^{
                TGChatViewController *me = weakScroll;
                if (!me) return;
                me.isLoadingMoreHistory = NO;
                // Without this the next scroll event asks again, and a chat
                // that has nothing older - a local one above all - answers
                // an empty list a hundred times a second.
                if (older.count == 0) {
                    me.atChatStart = YES;
                    return;
                }

                CGFloat oldHeight = me.table.contentSize.height;
                CGFloat oldOffset = me.table.contentOffset.y;

                NSUInteger added = [me.streamStore prependOlderMessages:older];
                if (!added) {
                    me.atChatStart = YES;
                    return;
                }

                me.rawMessages = [me.streamStore messages];
                me.messages = [me groupedMessagesFromMessages:me.rawMessages];

                [UIView setAnimationsEnabled:NO];
                [me.table reloadData];
                me.table.contentOffset = CGPointMake(0, oldOffset + (me.table.contentSize.height - oldHeight));
                [UIView setAnimationsEnabled:YES];
                [me fetchMissingImages];
            });
        }];
    }

    // 2. Load newer messages when scrolled near the bottom
    CGFloat distanceFromBottom = scrollView.contentSize.height - (scrollView.contentOffset.y + scrollView.bounds.size.height);
    if (distanceFromBottom < (CGFloat)TGMetricHistoryTopGate && !self.isLoadingNewerHistory && !self.atChatEnd) {
        self.isLoadingNewerHistory = YES;
        int64_t fromMessageId = self.streamStore.newestMessageId;
        if (!fromMessageId) {
            NSArray *pool = self.rawMessages.count ? self.rawMessages : self.messages;
            fromMessageId = [pool.lastObject[@"id"] longLongValue];
        }

        __weak typeof(self) weakScroll = self;
        [[TGClient shared] newerHistoryForChat:self.chatId fromMessageId:fromMessageId limit:60 completion:^(NSArray *newer) {
            dispatch_async(dispatch_get_main_queue(), ^{
                TGChatViewController *me = weakScroll;
                if (!me) return;
                me.isLoadingNewerHistory = NO;
                if (newer.count == 0) {
                    me.atChatEnd = YES;
                    return;
                }

                NSUInteger added = [me.streamStore appendNewerMessages:newer];
                if (!added) {
                    me.atChatEnd = YES;
                    return;
                }

                me.rawMessages = [me.streamStore messages];
                me.messages = [me groupedMessagesFromMessages:me.rawMessages];

                [UIView setAnimationsEnabled:NO];
                [me.table reloadData];
                [UIView setAnimationsEnabled:YES];
                [me fetchMissingImages];

                if (newer.count < 60) {
                    me.atChatEnd = YES;
                }
            });
        }];
    }
}

@end
