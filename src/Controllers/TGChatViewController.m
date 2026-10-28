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
	[self buildTitleView];
	self.streamStore = [[TGMessageStreamStore alloc] init];
	self.messages = @[];
	self.layoutCache = [NSMutableDictionary dictionary];
	self.gifPaths = [NSMutableDictionary dictionary];
	self.gifsRequested = [NSMutableSet set];
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

	UITapGestureRecognizer *tableTap = [[UITapGestureRecognizer alloc]
			initWithTarget:self action:@selector(tableTapped:)];
	tableTap.cancelsTouchesInView = NO;
	[self.table addGestureRecognizer:tableTap];

	[self.view addSubview:self.table];

	[self buildInputBar:b];
	[self buildChrome];
	[self installSwipeToReply];

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

	[self reload];
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
	if (![TGTheme shared].isFlat){
		name.shadowColor = [[TGTheme shared] navBarTextShadowColour];
		name.shadowOffset = TGMetricShadowOffsetNav;
	}
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
	self.input.keyboardAppearance = theme.isDark ? UIKeyboardAppearanceDark : UIKeyboardAppearanceLight;
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
	[TGPopupMenu dismiss];

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
		[[TGClient shared] cancelTypingInChat:self.chatId thread:self.threadId];
		[[TGClient shared] closeChat:self.chatId];
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
	__weak typeof(self) weakSelf = self;
	[[TGClient shared] historyForChat:self.chatId thread:self.threadId limit:60 completion:^(NSArray *messages){
		TGChatViewController *me = weakSelf;
		if (!me)
			return;
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
		[me.table reloadData];
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
	button.layer.cornerRadius = TGHalf(side);
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
/// Scrolling there is the first try; when it is outside the window the
/// history is fetched around it and the scroll is tried again.
- (void)pinnedBannerTapped {
	int64_t pinned = self.pinnedMessageId;
	if (!pinned)
		return;
	if ([self scrollToMessageId:pinned])
		return;

	__weak typeof(self) weakSelf = self;
	[[TGClient shared] historyForChat:self.chatId
						 fromMessageId:pinned
								 limit:(NSInteger)TGMetricHistoryPageAroundPinned
							completion:^(NSArray *messages){
		TGChatViewController *me = weakSelf;
		if (!me || !messages.count)
			return;
		// The fetched window replaces what was on screen, the way following a
		// reply upwards does.
		[me.streamStore resetWithMessages:messages];
		me.rawMessages = [me.streamStore messages];
		me.messages = [me groupedMessagesFromMessages:me.rawMessages];
		me.atChatEnd = NO;
		[me.table reloadData];
		if (![me scrollToMessageId:pinned])
			[TGSnackbar showInView:me.view text:@"The pinned message is gone"
						   seconds:2 onCommit:nil];
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
    if (scrollView.contentOffset.y < (CGFloat)TGMetricHistoryTopGate && !self.isLoadingMoreHistory) {
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
                if (older.count == 0) return;
                
                CGFloat oldHeight = me.table.contentSize.height;
                CGFloat oldOffset = me.table.contentOffset.y;

                NSUInteger added = [me.streamStore prependOlderMessages:older];
                if (!added) return;

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
