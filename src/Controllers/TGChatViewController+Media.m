#import "TGChatViewControllerInternal.h"
#import "TGThemeFile.h"
#import "UIImage+WebP.h"
#import "TGCapabilities.h"
#import "TGStyle.h"
#import "TGAlertSheet.h"
#import "TGDevShowcase.h"

@implementation TGChatViewController (Media)

/// Renders an offline stylized map card with pin for location messages.
- (UIImage *)mapCardForLatitude:(double)lat longitude:(double)lon {
	CGSize size = CGSizeMake(TGMetricMapCardWidth, TGMetricMapCardHeight);
	UIGraphicsBeginImageContextWithOptions(size, YES, 0);
	CGContextRef ctx = UIGraphicsGetCurrentContext();
	TGTheme *theme = [TGTheme shared];

	// paper
	CGContextSetFillColorWithColor(ctx, [theme mapPaperColour].CGColor);
	CGContextFillRect(ctx, CGRectMake(0, 0, size.width, size.height));

	// a few roads, placed from the coordinates so different places differ
	CGContextSetStrokeColorWithColor(ctx, [theme mapRoadColour].CGColor);
	CGContextSetLineWidth(ctx, TGMetricCornerMedium);
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
	CGContextSetFillColorWithColor(ctx, [theme mapGreeneryColour].CGColor);
	CGContextFillEllipseInRect(ctx, CGRectMake(fmod(seed, 120), fmod(seed, 60), 70, 44));

	// the pin, centred
	CGPoint p = CGPointMake(TGHalf(size.width), TGHalf(size.height));
	CGContextSetFillColorWithColor(ctx, [theme mapPinShadowColour].CGColor);
	CGContextFillEllipseInRect(ctx, CGRectMake(p.x - 7, p.y + 6, 14, 5));
	CGContextSetFillColorWithColor(ctx, [theme mapPinColour].CGColor);
	CGContextFillEllipseInRect(ctx, CGRectMake(p.x - 8, p.y - 16, 16, 16));
	CGContextMoveToPoint(ctx, p.x - 5, p.y - 4);
	CGContextAddLineToPoint(ctx, p.x + 5, p.y - 4);
	CGContextAddLineToPoint(ctx, p.x, p.y + 8);
	CGContextClosePath(ctx);
	CGContextFillPath(ctx);
	CGContextSetFillColorWithColor(ctx, [theme mapRoadColour].CGColor);
	CGContextFillEllipseInRect(ctx, CGRectMake(p.x - 3, p.y - 11, 6, 6));

	UIImage *card = UIGraphicsGetImageFromCurrentImageContext();
	UIGraphicsEndImageContext();
	return card;
}

/// The drawn card goes up first so the bubble has something at once, and
/// Telegram's own picture of the place replaces it when it arrives. The card
/// is not a placeholder to be ashamed of - on a device with no connection it
/// is the whole answer - but it shows roads that are not there, and the real
/// thumbnail shows where the pin actually is.
/// A track's album cover, downloaded once and kept with the other pictures.
/// TDLib sends the cover's file id with the message and nothing here drew it
/// until the track bubble existed.
- (UIImage *)artworkForTrack:(NSDictionary *)m {
	NSNumber *coverId = m[@"albumCoverId"];
	if ([TGDevShowcase isDevChatId:self.chatId] || (coverId && coverId.longLongValue < 0)) {
		return [TGDevShowcase trackArtwork];
	}
	if (![coverId isKindOfClass:NSNumber.class] || coverId.integerValue <= 0)
		return nil;

	UIImage *cached = self.images[coverId];
	if (cached)
		return cached;
	if ([self.imagesRequested containsObject:coverId])
		return nil;
	[self.imagesRequested addObject:coverId];

	__weak typeof(self) weakSelf = self;
	[[TGClient shared] downloadFile:coverId.integerValue completion:^(NSString *path){
		TGChatViewController *me = weakSelf;
		UIImage *cover = path.length ? [UIImage imageWithContentsOfFile:path] : nil;
		if (!me || !cover)
			return;
		me.images[coverId] = cover;
		[me reloadTableDebounced];
	}];
	return nil;
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

		// One request per message, ever: mapsRequested outlives the drawn
		// card, so a chat scrolled past and back does not ask again.
		if ([self.mapsRequested containsObject:key])
			continue;
		[self.mapsRequested addObject:key];

		__weak typeof(self) weakSelf = self;
		[[TGClient shared] mapThumbnailForLatitude:lat.doubleValue
										 longitude:lon.doubleValue
											 width:220
											height:130
											inChat:self.chatId
										completion:^(NSString *path){
			TGChatViewController *me = weakSelf;
			UIImage *real = path.length ? [UIImage imageWithContentsOfFile:path] : nil;
			if (!me || !real)
				return;          // the card stays, which is the right answer
			me.maps[key] = real;
			[me reloadTableDebounced];
		}];
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
	NSMutableArray *wanted = [NSMutableArray array];
	for (NSDictionary *m in self.messages){
		NSNumber *replyId = m[@"replyId"];
		if (![replyId isKindOfClass:NSNumber.class])
			continue;
		if ([m[@"replyText"] length] || self.quotes[replyId] ||
			[self.quotesRequested containsObject:replyId])
			continue;
		[self.quotesRequested addObject:replyId];
		[wanted addObject:replyId];
	}
	if (!wanted.count)
		return;

	__weak typeof(self) weakSelf = self;
	// One getMessages for the whole window. A chat with a dozen replies in
	// view used to send a dozen separate getMessage requests for the same
	// screen, which is most of what a slow connection noticed.
	[[TGClient shared] messagesInChat:self.chatId messageIds:wanted
						   completion:^(NSArray *messages){
		TGChatViewController *me = weakSelf;
		if (!me)
			return;
		BOOL any = NO;
		for (NSUInteger i = 0; i < wanted.count && i < messages.count; i++){
			id found = messages[i];
			if (![found isKindOfClass:NSDictionary.class])
				continue;
			NSNumber *replyId = wanted[i];
			me.quotes[replyId] = found;
			any = YES;
			for (NSDictionary *msg in me.messages){
				if ([msg[@"replyId"] isEqual:replyId]){
					NSNumber *msgId = msg[@"id"];
					if (msgId) [me.layoutCache removeObjectForKey:msgId];
				}
			}
		}
		if (any)
			[me reloadTableDebounced];
	}];
}

- (void)fetchMissingImages {
	__weak typeof(self) weakSelf = self;
	NSMutableArray *allMsgs = [NSMutableArray array];
	for (NSDictionary *m in self.messages){
		if ([m[@"isAlbum"] boolValue] && [m[@"albumMessages"] isKindOfClass:[NSArray class]]) {
			[allMsgs addObjectsFromArray:m[@"albumMessages"]];
		} else {
			[allMsgs addObject:m];
		}
	}

	// Animated stickers (.tgs or .webm) need the animation file, not just the still thumbnail.
	// Only fetch when the device and user settings allow animated stickers.
	if ([TGCapabilities canPlayAnimatedStickers]){
		for (NSDictionary *m in allMsgs){
			if (![m[@"docName"] isEqualToString:@"tgs"] && ![m[@"docName"] isEqualToString:@"webm"])
				continue;
			NSNumber *docId = m[@"docId"];
			if (![docId isKindOfClass:NSNumber.class] || docId.longLongValue < 0 || self.lottiePaths[docId])
				continue;
			if ([self.imagesRequested containsObject:docId])
				continue;
			[self.imagesRequested addObject:docId];

			[[TGClient shared] downloadFile:[docId integerValue] priority:TGDownloadPriorityOnScreen completion:^(NSString *path){
				TGChatViewController *me = weakSelf;
				if (!me)
					return;
				if (!path) {
					[me.imagesRequested removeObject:docId];
					return;
				}
				me.lottiePaths[docId] = path;
				for (NSDictionary *msg in me.messages) {
					if ([msg[@"docId"] isEqual:docId]) {
						NSNumber *msgId = msg[@"id"];
						if (msgId) [me.layoutCache removeObjectForKey:msgId];
					}
				}
				[me reloadTableDebounced];
				if (me.anchorToBottom)
					[me scrollToBottomAnimated:NO];
			}];
		}
	}

	for (NSDictionary *m in allMsgs)
		[self fetchImageForMessage:m];
}


/// Loads one message's photo into `images` unless it is there or on its way.
/// Rows call it too, for a photo the LRU let go of while it was off screen.
- (void)fetchImageForMessage:(NSDictionary *)m {
	NSNumber *fileId = m[@"photoId"];
	if (![fileId isKindOfClass:NSNumber.class] || fileId.longLongValue < 0)
		return;
	if (self.images[fileId] || [self.imagesRequested containsObject:fileId])
		return;
	__weak typeof(self) weakSelf = self;
	CGFloat screenScale = [UIScreen mainScreen].scale;   // read here, used off-thread
	[self.imagesRequested addObject:fileId];

	[[TGClient shared] downloadFile:[fileId integerValue] completion:^(NSString *path){
		if (!path) {
			[weakSelf.imagesRequested removeObject:fileId];
			return;
		}
		dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_BACKGROUND, 0), ^{
			// Stickers arrive as WebP, which UIImage does not know on iOS 7.
			UIImage *img = [UIImage imageWithContentsOfFile:path];
			if (!img)
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
				// Done, so not "requested" any more: the cache is an LRU, and an
				// id left here kept an evicted photo from ever loading again.
				[me.imagesRequested removeObject:fileId];
				// Only the rows showing this photo change height. Dropping every
				// layout cost a full re-measure of the chat (~300 ms on an A4),
				// which a photo coming back mid-scroll cannot afford.
				for (NSDictionary *row in me.messages) {
					BOOL shows = [row[@"photoId"] isEqual:fileId];
					NSArray *parts = row[@"albumMessages"];
					if ([parts isKindOfClass:NSArray.class])
						for (NSDictionary *part in parts)
							shows = shows || [part[@"photoId"] isEqual:fileId];
					if (shows && row[@"id"])
						[me.layoutCache removeObjectForKey:row[@"id"]];
				}
				[me reloadTableDebounced];
				// Rows grow when an image arrives, pushing the newest messages
				// below the fold, so re-anchor to the bottom while first showing.
				if (me.anchorToBottom)
					[me scrollToBottomAnimated:NO];
			});
		});
	}];
}

/// Cached initials until the real photo arrives; drawing it every row would
/// re-download and re-decode on every scroll.
- (UIImage *)avatarForUser:(int64_t)userId name:(NSString *)name {
	NSNumber *key = @(userId);
	UIImage *cached = self.senderAvatars[key];
	if (cached)
		return cached;

	if ([TGDevShowcase isDevChatId:self.chatId] || userId == 20002 || userId == 10001) {
		UIImage *devAvatar = [TGDevShowcase avatarForUserId:userId];
		if (devAvatar) {
			self.senderAvatars[key] = devAvatar;
			return devAvatar;
		}
	}

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
				// Same pooled-gated decode as every other avatar path: a busy
				// group's flood used to ride this block pool-free (B15).
				dispatch_semaphore_wait(TGIconsDecodeGate(), DISPATCH_TIME_FOREVER);
				__block UIImage *photo = nil;
				@autoreleasepool {
					photo = [TGIcons decodedImage:[UIImage imageWithContentsOfFile:path]
										  fittingSize:CGSizeMake(kAvatarSide, kAvatarSide)
												 fill:YES scale:screenScale];
				}
				dispatch_semaphore_signal(TGIconsDecodeGate());
				if (!photo) return;
				dispatch_async(dispatch_get_main_queue(), ^{
					weakSelf.senderAvatars[key] = photo;
					// One reload per arriving avatar loaded the whole table once
					// per participant in a busy group.
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

#pragma mark - download progress

/// A video or a document is megabytes over a 4S connection; without this the
/// tap looks like it did nothing. The system progress bar sits in the centre
/// of the screen; the plate keeps it visible over the wallpaper.
- (void)beginDownloadHUDForFile:(NSInteger)fileId {
	self.downloadingFileId = fileId;

	if (!self.downloadHUD){
		UIView *plate = [[UIView alloc] initWithFrame:CGRectMake(0, 0, kHUDWidth, kHUDHeight)];
		plate.backgroundColor = [[TGTheme shared] hudBackgroundColour];
		plate.layer.cornerRadius = TGMetricCornerControl;
		plate.clipsToBounds = YES;

		UILabel *percent = [[UILabel alloc] initWithFrame:
				CGRectMake(0, TGMetricPadSmall, kHUDWidth, TGMetricLineCaption)];
		percent.textAlignment = NSTextAlignmentCenter;
		percent.font = TGFontCaption();
		percent.textColor = [[TGTheme shared] hudTextColour];
		percent.backgroundColor = [UIColor clearColor];
		percent.tag = kHUDPercentTag;
		[plate addSubview:percent];

		UIProgressView *bar = [[UIProgressView alloc]
				initWithProgressViewStyle:UIProgressViewStyleDefault];
		bar.frame = CGRectMake(TGMetricPadLarge,
				TGMetricPadSmall + TGMetricLineCaption + TGMetricPadSmall,
				kHUDWidth - TGDoubled(TGMetricPadLarge), TGMetricLineMicro);
		bar.progressTintColor = [[TGTheme shared] accentColour];
		bar.tag = kHUDBarTag;
		[plate addSubview:bar];

		// The plate is the Cancel button too: a download that began with a
		// tap should stop with one, and the plate already sits where the
		// finger is. Nothing else on the screen is that tap's to take.
		UITapGestureRecognizer *cancel = [[UITapGestureRecognizer alloc]
				initWithTarget:self action:@selector(cancelDownloadHUDTapped)];
		[plate addGestureRecognizer:cancel];

		self.downloadHUD = plate;
		self.downloadHUD.center = CGPointMake(TGHalf(self.view.bounds.size.width),
											  TGHalf(self.view.bounds.size.height));
		self.downloadHUD.hidden = YES;
		[self.view addSubview:plate];
	}
	self.downloadHUD.hidden = NO;

	__weak typeof(self) weakSelf = self;
	[TGClient shared].onFileProgress = ^(NSInteger updatedId, float progress){
		TGChatViewController *me = weakSelf;
		if (!me || updatedId != me.downloadingFileId)
			return;
		UIProgressView *bar = (UIProgressView *)[me.downloadHUD viewWithTag:kHUDBarTag];
		bar.progress = progress;
		UILabel *percent = (UILabel *)[me.downloadHUD viewWithTag:kHUDPercentTag];
		percent.text = [NSString stringWithFormat:@"%d%%", (int)(progress * 100)];
	};
}

- (void)endDownloadHUD {
	self.downloadingFileId = 0;
	self.downloadHUD.hidden = YES;
	[self.downloadHUD removeFromSuperview];
	self.downloadHUD = nil;
}

/// Tapping the progress plate stops the download where it is. TDLib is told
/// so it stops fetching, and the waiters are released so nothing keeps the
/// file's record alive; the completion then simply never fires, which is
/// what cancel means for the screen that asked.
- (void)cancelDownloadHUDTapped {
	NSInteger fileId = self.downloadingFileId;
	if (!fileId)
		return;
	[self endDownloadHUD];
	[[TGClient shared] cancelDownloadOfFile:fileId onlyIfPending:NO];
	[TGSnackbar showInView:self.view text:@"Download cancelled" seconds:2 onCommit:nil];
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
		[TGAlertSheet showMessage:(applied
						? [NSString stringWithFormat:@"%@ applied.",
								[TGTheme shared].importedName ?: name]
						: @"This file could not be read as a Telegram theme.")
							title:@"Theme" inView:self.view];
	}];
}

@end
