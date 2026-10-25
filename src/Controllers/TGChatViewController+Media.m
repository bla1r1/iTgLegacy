#import "TGChatViewControllerInternal.h"
#import "TGThemeFile.h"
#import "UIImage+WebP.h"
#import "TGCapabilities.h"

@implementation TGChatViewController (Media)

/// Renders an offline stylized map card with pin for location messages.
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
	// Only fetch when the device and user settings allow animated stickers.
	if ([TGCapabilities canPlayAnimatedStickers]){
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

@end
