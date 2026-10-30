//
// TGChatViewController+AudioCells.m
// Bubble cell rendering for phone calls, audio tracks, and voice notes.
//
#import "TGChatViewControllerInternal.h"
#import "TGMusicPlayer.h"
#import "TGStyle.h"

@implementation TGChatViewController (AudioCells)

- (BOOL)configureAudioCell:(TGBubbleCell *)cell message:(NSDictionary *)m layout:(TGMessageLayout *)layout isMine:(BOOL)mine indexPath:(NSIndexPath *)indexPath {
	// Phone Calls
	if (layout.isCall) {
		TGTheme *callTheme = [TGTheme shared];
		BOOL missed = [m[@"callState"] isEqualToString:@"missed"];
		NSString *line = m[@"text"] ?: @"Call";

		CGFloat fwd = [self layoutForwardIn:cell message:m width:layout.bubbleFrame.size.width];
		cell.bubble.frame = layout.bubbleFrame;
		cell.bubble.backgroundColor = mine ? [callTheme bubbleMineColour] : [callTheme bubbleTheirsColour];
		cell.bubble.layer.borderWidth = TGMetricBorderNone;
		cell.bubble.layer.borderColor = [UIColor clearColor].CGColor;
		cell.bubble.layer.cornerRadius = [callTheme bubbleCornerRadius];

		cell.disc.hidden = NO;
		cell.disc.image = [TGIcons callArrowOutgoing:mine missed:missed];
		cell.disc.frame = CGRectMake(kPadH,
				fwd + TGCenteredOrigin(layout.bubbleFrame.size.height - fwd, kCallArrow),
				kCallArrow, kCallArrow);

		CGFloat rightBtnW = TGMetricCallControlSide;
		CGFloat textW = layout.bubbleFrame.size.width - kPadH - TGMetricBubbleDiscColumn
				- rightBtnW - TGMetricPadSmall;

		cell.body.hidden = NO;
		cell.body.numberOfLines = 1;
		cell.body.font = TGFontSubheadStrong();
		cell.body.textColor = missed ? [callTheme destructiveColour] : [callTheme primaryTextColour];
		cell.body.text = line;
		TGPlaceTitleDetail(cell, kPadH + TGMetricBubbleDiscColumn, fwd, textW);

		cell.subtitle.hidden = NO;
		cell.subtitle.font = TGFontMeta();
		cell.subtitle.textColor = [callTheme secondaryTextColour];
		cell.subtitle.text = layout.stamp;

		cell.contactCallButton.hidden = NO;
		cell.contactCallButton.frame =
				CGRectMake(layout.bubbleFrame.size.width - rightBtnW - TGMetricPadSmall,
						fwd + TGCenteredOrigin(layout.bubbleFrame.size.height - fwd, kCallButton),
						kCallButton, kCallButton);
		[cell.contactCallButton setImage:[TGIcons callArrowOutgoing:YES missed:NO] forState:UIControlStateNormal];
		[cell.contactCallButton setTitle:nil forState:UIControlStateNormal];
		cell.contactCallButton.tag = indexPath.row;
		[cell.contactCallButton removeTarget:nil action:NULL forControlEvents:UIControlEventAllEvents];
		[cell.contactCallButton addTarget:self action:@selector(callCellButtonTapped:) forControlEvents:UIControlEventTouchUpInside];

		cell.picture.hidden = YES;
		cell.time.text = @"";
		cell.ticks.hidden = YES;
		return YES;
	}

	// Audio Tracks
	if (layout.isTrack) {
		TGTheme *cardTheme = [TGTheme shared];
		CGFloat fwd = [self layoutForwardIn:cell message:m width:layout.bubbleFrame.size.width];
		cell.bubble.frame = layout.bubbleFrame;
		cell.bubble.backgroundColor = mine ? [cardTheme bubbleMineColour]
										   : [cardTheme bubbleTheirsColour];
		cell.bubble.layer.borderWidth = TGMetricBorderNone;
		cell.bubble.layer.borderColor = [UIColor clearColor].CGColor;
		cell.bubble.layer.cornerRadius = [cardTheme bubbleCornerRadius];

		CGFloat artY = fwd + TGCenteredOrigin(kTrackRow, kTrackArt) - TGMetricPadTiny;
		cell.artwork.hidden = NO;
		cell.artwork.frame = CGRectMake(kPadH, artY, kTrackArt, kTrackArt);
		UIImage *cover = [self artworkForTrack:m];
		cell.artwork.image = cover;
		cell.artwork.backgroundColor = cover ? [UIColor clearColor]
											 : [cardTheme fileTileColour];

		BOOL isCurrent = [TGMusicPlayer shared].currentMessageId ==
						 [m[@"id"] longLongValue];
		cell.disc.hidden = NO;
		cell.disc.image = (isCurrent && [TGMusicPlayer shared].playing)
				? [TGIcons pause] : [TGIcons play];
		cell.disc.frame = CGRectMake(kPadH + TGCenteredOrigin(kTrackArt, kTrackDisc),
									 artY + TGCenteredOrigin(kTrackArt, kTrackDisc),
									 kTrackDisc, kTrackDisc);
		[cell.bubble bringSubviewToFront:cell.disc];

		CGFloat textX = kPadH + kTrackArt + TGMetricPadSmall + TGMetricPadTiny;
		CGFloat textW = MAX(layout.bubbleFrame.size.width - textX - kPadH, TGMetricZero);

		NSString *title = [m[@"audioTitle"] length] ? m[@"audioTitle"]
				: ([m[@"docName"] length] ? m[@"docName"] : @"Audio");
		cell.body.hidden = NO;
		cell.body.numberOfLines = 1;
		cell.body.font = TGFontBodyStrong();
		cell.body.textColor = [cardTheme primaryTextColour];
		cell.body.text = title;
		TGPlaceTitleDetail(cell, textX, artY, textW);

		NSInteger seconds = [m[@"duration"] integerValue];
		NSString *length = seconds > 0
				? [NSString stringWithFormat:@"%ld:%02ld",
						(long)(seconds / 60), (long)(seconds % 60)]
				: @"";
		NSString *performer = m[@"audioPerformer"];
		NSString *second = performer.length
				? (length.length ? [NSString stringWithFormat:@"%@ - %@",
						performer, length] : performer)
				: length;
		cell.subtitle.hidden = NO;
		cell.subtitle.font = TGFontCaption();
		cell.subtitle.textColor = [cardTheme fileMetaColour];
		cell.subtitle.text = second;

		cell.time.frame = layout.timeFrame;
		return YES;
	}

	// Voice notes
	if (layout.isVoice) {
		TGTheme *voiceTheme = [TGTheme shared];
		CGFloat disc = kVoiceDisc;
		CGFloat left = kPadH + disc + TGMetricPad;
		BOOL isPlaying = (self.playingMessageId == [m[@"id"] longLongValue] && self.voicePlayer && self.voicePlayer.playing);

		cell.voiceMessageId = [m[@"id"] longLongValue];
		cell.waveformData = m[@"waveform"];

		CGFloat fwd = layout.fwdHeight;

		cell.disc.hidden = NO;
		cell.disc.userInteractionEnabled = YES;
		cell.disc.image = [TGIcons mediaDiscOfSide:disc playing:isPlaying];
		cell.disc.frame = CGRectMake(kPadH, fwd + TGCenteredOrigin(layout.bubbleFrame.size.height - fwd, disc), disc, disc);
		if (!cell.disc.gestureRecognizers.count) {
			[cell.disc addGestureRecognizer:[[UITapGestureRecognizer alloc]
					initWithTarget:self action:@selector(voiceDiscTapped:)]];
		}

		BOOL unplayed = !mine && [m[@"unplayed"] boolValue];

		cell.wave.hidden = NO;
		CGSize waveSize = CGSizeMake(layout.bubbleFrame.size.width - left - kPadH, kVoiceWaveHeight);
		cell.wave.image = [TGIcons waveform:m[@"waveform"]
									   size:waveSize
									 played:(isPlaying ? [self playedFraction]
													  : (unplayed ? 1.0f : 0))
									 colour:[voiceTheme accentColour]];
		cell.wave.frame = CGRectMake(left, fwd + kVoiceWaveTop, waveSize.width, waveSize.height);
		cell.wave.userInteractionEnabled = YES;
		if (!cell.wave.gestureRecognizers.count) {
			[cell.wave addGestureRecognizer:[[UIPanGestureRecognizer alloc]
					initWithTarget:self action:@selector(waveformScrubbed:)]];
			[cell.wave addGestureRecognizer:[[UITapGestureRecognizer alloc]
					initWithTarget:self action:@selector(waveformScrubbed:)]];
		}

		NSInteger seconds = [m[@"duration"] integerValue];
		NSString *durText = [NSString stringWithFormat:@"%ld:%02ld",
				(long)(seconds / 60), (long)(seconds % 60)];
		cell.body.hidden = NO;
		cell.body.numberOfLines = 1;
		cell.body.font = TGFontMeta();
		cell.body.textColor = [voiceTheme secondaryTextColour];
		cell.body.text = durText;
		cell.body.frame = CGRectMake(left, layout.bubbleFrame.size.height - TGMetricLineRow,
				MAX(TGTextSize(durText, TGFontMeta(), 0).width, kVoiceClockMinimum), TGMetricLineMicro);

		cell.unreadDot.hidden = !unplayed;
		if (unplayed){
			CGRect inCell = [cell.contentView convertRect:cell.body.frame fromView:cell.bubble];
			cell.unreadDot.frame = CGRectMake(
					CGRectGetMinX(inCell) + TGTextSize(cell.body.text, cell.body.font, 0).width + TGMetricPadSmall,
					CGRectGetMinY(inCell) + TGCenteredOrigin(CGRectGetHeight(inCell), TGMetricUnreadDotSide),
					TGMetricUnreadDotSide, TGMetricUnreadDotSide);
			cell.unreadDot.layer.cornerRadius = TGHalf(TGMetricUnreadDotSide);
			cell.unreadDot.backgroundColor = [voiceTheme accentColour];
		}

		cell.picture.hidden = YES;
		cell.time.text = layout.stamp;
		cell.time.textColor = mine ? [voiceTheme timeMineColour] : [voiceTheme timeColour];
		TGPlaceStamp(cell, layout.bubbleFrame, layout.timeWidth, mine);
		cell.ticks.hidden = !mine;
		if (mine) {
			cell.ticks.image = [self ticksForMessage:m white:NO];
			TGPlaceTicks(cell, layout.bubbleFrame);
		}
		return YES;
	}

	return NO;
}

@end
