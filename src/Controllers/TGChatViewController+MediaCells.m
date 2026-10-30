//
// TGChatViewController+MediaCells.m
// Bubble cell rendering for photos, albums, animated stickers, video notes, and GIFs.
//
#import "TGChatViewControllerInternal.h"
#import <QuartzCore/QuartzCore.h>
#import "TGCapabilities.h"
#import "TGStyle.h"

@implementation TGChatViewController (MediaCells)

- (BOOL)configureRoundOrStickerCell:(TGBubbleCell *)cell message:(NSDictionary *)m layout:(TGMessageLayout *)layout isMine:(BOOL)mine {
	TGTheme *theme = [TGTheme shared];

	// Video note
	if (layout.isRound) {
		CGFloat side = layout.bubbleFrame.size.width;
		cell.bubble.backgroundColor = [theme fileTileColour];
		cell.bubble.layer.borderWidth = TGMetricBorderNone;
		cell.bubble.frame = layout.bubbleFrame;
		cell.bubble.layer.cornerRadius = TGHalf(side);
		cell.bubble.clipsToBounds = YES;
		cell.picture.hidden = NO;
		cell.picture.image = [self imageFor:m];
		cell.picture.backgroundColor = [theme fileTileColour];
		cell.picture.frame = CGRectMake(TGMetricZero, TGMetricZero, side, side);
		cell.picture.layer.cornerRadius = TGHalf(side);
		cell.picture.clipsToBounds = YES;
		cell.body.hidden = YES;

		cell.disc.hidden = NO;
		cell.disc.userInteractionEnabled = YES;
		CGFloat disc = kVideoDisc;
		BOOL isPlaying = (self.playingMessageId == [m[@"id"] longLongValue] && self.videoNotePlayer != nil);
		cell.disc.image = [TGIcons mediaDiscOfSide:disc playing:isPlaying];
		cell.disc.frame = CGRectMake(TGCenteredOrigin(side, disc), TGCenteredOrigin(side, disc), disc, disc);
		if (!cell.disc.gestureRecognizers.count) {
			[cell.disc addGestureRecognizer:[[UITapGestureRecognizer alloc]
					initWithTarget:self action:@selector(videoNoteDiscTapped:)]];
		}
		NSInteger dur = [m[@"duration"] integerValue];
		NSString *durStr = (dur > 0) ? [NSString stringWithFormat:@"%ld:%02ld", (long)(dur / 60), (long)(dur % 60)] : @"";
		NSString *stamp = (layout.stamp.length && ![layout.stamp isEqualToString:@"(null)"]) ? layout.stamp : @"";

		CGRect frame = layout.bubbleFrame;
		BOOL unplayedDot = !mine && [m[@"unplayed"] boolValue];
		CGFloat durW = durStr.length ? TGTextSize(durStr, TGFontMicro(), 0).width : 0.0f;
		CGFloat clockW = stamp.length ? TGTextSize(stamp, TGFontMicro(), 0).width : 0.0f;

		CGRect durFrame = CGRectZero, timeFrame = CGRectZero, ticksFrame = CGRectZero, dotFrame = CGRectZero;
		TGVideoNoteLayoutBottomBar(frame, durW, clockW, mine, unplayedDot,
								   &durFrame, &timeFrame, &ticksFrame, &dotFrame);

		[cell.contentView addSubview:cell.mediaStamp];
		cell.mediaStamp.hidden = !durStr.length;
		cell.mediaStamp.backgroundColor = [UIColor clearColor];
		cell.mediaStamp.textColor = [theme timeColour];
		cell.mediaStamp.font = TGFontMicro();
		cell.mediaStamp.text = durStr;
		cell.mediaStamp.textAlignment = NSTextAlignmentLeft;
		cell.mediaStamp.layer.cornerRadius = 0;
		cell.mediaStamp.frame = durFrame;

		[cell.contentView addSubview:cell.time];
		cell.time.hidden = !stamp.length;
		cell.time.text = stamp;
		cell.time.textColor = [theme timeColour];
		cell.time.textAlignment = NSTextAlignmentLeft;
		cell.time.frame = timeFrame;

		cell.ticks.hidden = !mine;
		if (mine) {
			[cell.contentView addSubview:cell.ticks];
			cell.ticks.image = [self ticksForMessage:m white:NO];
			cell.ticks.frame = ticksFrame;
		}

		cell.unreadDot.hidden = !unplayedDot;
		if (unplayedDot){
			[cell.contentView addSubview:cell.unreadDot];
			cell.unreadDot.frame = dotFrame;
			cell.unreadDot.layer.cornerRadius = TGHalf(TGMetricUnreadDotSide);
			cell.unreadDot.backgroundColor = [theme accentColour];
		}

		return YES;
	}

	// Animated sticker (.tgs or .webm)
	BOOL isAnimSticker = [TGCapabilities canPlayAnimatedStickers] &&
		([m[@"docName"] isEqualToString:@"tgs"] || [m[@"docName"] isEqualToString:@"webm"]);
	NSString *animPath = isAnimSticker ? self.lottiePaths[m[@"docId"]] : nil;
	if (animPath) {
		CGFloat side = kLottieSide;
		cell.bubble.backgroundColor = [UIColor clearColor];
		cell.bubble.layer.borderWidth = TGMetricBorderNone;
		cell.bubble.frame = layout.bubbleFrame;
		cell.picture.hidden = YES;
		cell.body.hidden = YES;
		cell.lottie.hidden = NO;
		cell.lottie.frame = CGRectMake(TGMetricZero, TGMetricZero, side, side);
		[cell.lottie loadStickerFile:animPath];
		[cell.lottie play];

		static NSDateFormatter *hmt = nil;
		if (!hmt) { hmt = [[NSDateFormatter alloc] init]; [hmt setDateFormat:@"HH:mm"]; }
		cell.time.text = [hmt stringFromDate:[NSDate dateWithTimeIntervalSince1970:[m[@"date"] doubleValue]]];
		cell.time.textColor = [theme timeColour];
		TGPlaceStamp(cell, layout.bubbleFrame,
				TGTextSize(cell.time.text, TGFontMicro(), 0).width, NO);
		return YES;
	}

	return NO;
}

- (void)configureMediaForCell:(TGBubbleCell *)cell message:(NSDictionary *)m layout:(TGMessageLayout *)layout isMine:(BOOL)mine {
	TGTheme *theme = [TGTheme shared];
	NSString *kind = m[@"kind"];

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
				[TGMediaViewer presentItems:albumMsgs
									startAt:idx
									 inChat:strongSelf.chatId
									isAlbum:YES];
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
		cell.picture.layer.cornerRadius = layout.isSticker ? TGMetricCornerNone : TGMetricCornerMedium;
		cell.picture.layer.borderWidth = (layout.isSticker || layout.isRound) ? 0.0f : (theme.isFlat ? 0.0f : 1.0f);
		cell.picture.clipsToBounds = YES;

		cell.disc.hidden = ![kind isEqualToString:@"messageVideo"] && ![kind isEqualToString:@"messageAnimation"];
		if (!cell.disc.hidden) {
			CGFloat disc = kGifDisc;
			cell.disc.image = [TGIcons mediaDiscOfSide:disc playing:NO];
			cell.disc.frame = CGRectMake(kPadH + TGCenteredOrigin(layout.picSize.width, disc),
										 layout.pictureFrame.origin.y + TGCenteredOrigin(layout.picSize.height, disc), disc, disc);
		}

		if ([kind isEqualToString:@"messageAnimation"] && ![TGCapabilities canAutoplayGIFs]) {
			cell.icon.hidden = NO;
			cell.icon.layer.cornerRadius = TGMetricCornerSmall;
			cell.icon.clipsToBounds = YES;
			cell.icon.backgroundColor = [[TGTheme shared] mediaOverlayColour];
			cell.icon.textColor = [UIColor whiteColor];
			cell.icon.font = TGFontPlate();
			cell.icon.text = [TGCapabilities gifAutoplayWanted] ? @" GIF · tap to play "
																: @" GIF · autoplay off ";
			CGSize fits = [cell.icon sizeThatFits:CGSizeMake(layout.picSize.width, TGMetricLineCaption)];
			cell.icon.frame = CGRectMake(kPadH + kCaptionInset,
										 layout.pictureFrame.origin.y + kCaptionInset,
										 MIN(fits.width + TGMetricPad,
												 layout.picSize.width - TGDoubled(kCaptionInset)),
										 TGMetricLineCaption);
			[cell.bubble bringSubviewToFront:cell.icon];
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
}

#pragma mark - GIFs

static const long long kGifAutoDownloadLimit = 3 * 1024 * 1024;

- (void)startGifIfWantedIn:(TGBubbleCell *)cell message:(NSDictionary *)m {
	if (![m[@"kind"] isEqualToString:@"messageAnimation"] || cell.picture.hidden ||
		![TGCapabilities canAutoplayGIFs] || self.isEditingMessages){
		[cell stopLoopingVideo];
		return;
	}
	NSNumber *docId = [m[@"docId"] isKindOfClass:NSNumber.class] ? m[@"docId"] : nil;
	if (!docId)
		return;

	NSString *path = self.gifPaths[docId];
	if (path){
		NSUInteger playing = 0;
		for (UITableViewCell *visible in self.table.visibleCells)
			if (visible != cell && [visible isKindOfClass:TGBubbleCell.class] &&
				((TGBubbleCell *)visible).isPlayingLoop)
				playing++;
		if (playing >= [TGCapabilities maxConcurrentGIFs])
			return;
		[cell playLoopingVideoAtPath:path];
		cell.disc.hidden = YES;
		return;
	}

	long long size = [m[@"docSize"] longLongValue];
	if ([self.gifsRequested containsObject:docId] || size <= 0 || size > kGifAutoDownloadLimit)
		return;
	[self.gifsRequested addObject:docId];
	__weak typeof(self) weakSelf = self;
	[[TGClient shared] downloadFile:docId.integerValue completion:^(NSString *downloaded){
		TGChatViewController *me = weakSelf;
		if (!me || !downloaded.length)
			return;
		me.gifPaths[docId] = downloaded;
		[me reloadTableDebounced];
	}];
}

@end
