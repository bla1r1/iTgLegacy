//
// TGChatGeometry.h - the chat screen's own dimensions.
//
// These belong to no other screen: a call bubble's width allowance means
// nothing to the settings list. They live here instead of in TGStyle
// because a name in TGStyle that only one file reads is how the token
// layer came to hold more names than values. What they are built from is
// TGStyle's, so a change to the spacing or the line scale reaches them.
//
#ifndef TGCHATGEOMETRY_H
#define TGCHATGEOMETRY_H

#import "TGChatViewController.h"
#import "TGBubbleCell.h"
#import "TGStyle.h"

static const CGFloat kInputHeight = TGMetricInputBarHeight;
/// The reply / edit strip above the composer: two lines, the way their client
/// shows who is being answered and what they said.
static const CGFloat kComposeBannerHeight = TGMetricRow;

// ── the chat's own geometry ──────────────────────────────────────────────────
// This screen's own dimensions, which no other screen has any use for: a call
// bubble's width allowance means nothing to the settings list. They live here
// instead of in TGStyle because a name in TGStyle that only one file reads is
// how the token layer came to hold more names than values. What they are built
// from is TGStyle's, so a change to the spacing or the line scale reaches them.

/// The gap between the last word of a message and the stamp on its line.
static const CGFloat kStampGap        = TGMetricPad;
/// A quote block: the author's line, then what they said, then a gap.
static const CGFloat kQuoteLine       = TGMetricLineSubhead;
static const CGFloat kQuoteBlock      = TGMetricLineSubhead + TGMetricLineSubhead + TGMetricPadSmall;
/// The stripe down the left of a quote block, and the text's indent past it.
static const CGFloat kQuoteBarWidth   = TGMetricPadTiny;
static const CGFloat kQuoteTextInset  = TGMetricPad;
/// A service plate - a day, or an event like "pinned a message" - sits on a
/// row of its own: a gap, one line of header type, the same gap again.
static const CGFloat kServiceGap      = TGMetricPad;
static const CGFloat kServiceEventGap = TGMetricPadSmall;
static const CGFloat kServicePlate    = TGMetricLineHeader;
static const CGFloat kServiceRow      = TGMetricPad + TGMetricLineHeader + TGMetricPad;
static const CGFloat kServiceEventRow = TGMetricPadSmall + TGMetricLineHeader + TGMetricPadSmall;
/// Text from the end of a service plate, and the margin the plate keeps from
/// the sides of the table so a long day never runs edge to edge.
static const CGFloat kServicePlatePad    = TGMetricPadMedium;
static const CGFloat kServicePlateMargin = TGMetricPadWide + TGMetricPadMedium;
/// The unread marker, which is a band across the table rather than a plate.
static const CGFloat kUnreadBar       = TGMetricLineBody + TGMetricPadSmall;
/// A call bubble: a glyph beside two lines, at a height that does not vary.
static const CGFloat kCallBubble      = TGMetricButtonHeight;
/// What a call bubble keeps beside its text for the glyph and the button, and
/// the least width it will shrink to so a short "Missed call" is still a card.
static const CGFloat kCallBubbleRoom  = 80.0f;
static const CGFloat kCallBubbleMin   = 190.0f;
/// A document bubble, wide enough for a file name beside its tile.
static const CGFloat kDocBubble       = 225.0f;
/// A contact bubble: a disc, a name and a number, with a call button under.
static const CGFloat kContactBubble   = 230.0f;
static const CGFloat kContactBubbleH  = TGMetricPersonRow + TGMetricButtonHeightSmall;
/// A location bubble: the map card, with a caption strip beneath it.
static const CGFloat kLocationBubble  = 224.0f;
static const CGFloat kLocationBubbleH = TGMetricMapCardHeight + TGMetricRow;
/// A round video message, and an animated sticker. Both square; the round
/// note reads its side from the token so the bubble and the full-screen
/// player cannot drift apart by two points again.
static const CGFloat kRoundSide       = TGMetricRoundVideoSide;
static const CGFloat kLottieSide      = 128.0f;
/// The narrowest a text bubble will be, so one word is still a bubble.
static const CGFloat kBubbleMinW      = 170.0f;
/// A bubble that carries a picture is this wide whatever the picture is.
static const CGFloat kPicBubbleW      = 190.0f;
/// The shortest a bubble row gets, so a one-word message still reads as a
/// row and not as a line of text in a list.
static const CGFloat kBubbleRowMin    = TGMetricRow - TGMetricPadSmall;
/// A poll row: the dot's column, then the option, then its share on the right,
/// over a track that runs the row's width.
static const CGFloat kPollTextColumn  = TGMetricPadLarge + TGMetricPad;
static const CGFloat kPollShareWidth  = 40.0f;
static const CGFloat kPollTrackDrop   = TGMetricPadSmall;
static const CGFloat kPollTrackHeight = TGMetricPadTiny;
/// The "N voted" line under a poll's question.
static const CGFloat kPollVotedLine   = TGMetricPadTiny + TGMetricLineRow;
/// A call bubble's arrow, and the button on its right.
static const CGFloat kCallArrow       = 16.0f;
static const CGFloat kCallButton      = 32.0f;
/// A contact bubble: the initials disc, and where its two buttons begin.
static const CGFloat kContactDisc     = 42.0f;
static const CGFloat kContactDiscTop  = TGMetricPad;
static const CGFloat kContactButtons  = TGMetricPersonRow;
/// A file or contact bubble's text column, which clears the tile beside it.
static const CGFloat kTileTextGap     = TGMetricPadMedium;
/// A file bubble's name, which may wrap to two lines, and its meta line.
static const CGFloat kFileNameBlock   = TGMetricLineBody + TGMetricLineBody;
static const CGFloat kFileMetaTop     = TGMetricPad + TGMetricLineBody + TGMetricLineBody
		+ TGMetricPadTiny;
/// A location bubble: the pin over the map, and the attribution strip.
static const CGFloat kMapPinWidth     = 28.0f;
static const CGFloat kMapPinHeight    = 36.0f;
static const CGFloat kMapPinLift      = TGMetricPadSmall;
static const CGFloat kMapCreditWidth  = 68.0f;
/// A voice note: the play disc, the waveform, and the duration under it.
static const CGFloat kVoiceDisc       = 36.0f;
static const CGFloat kVoiceWaveHeight = TGMetricLineBody;
static const CGFloat kVoiceWaveTop    = TGMetricPadMedium;
static const CGFloat kVoiceClockMinimum = 44.0f;
/// The play disc over a video, and the one over an animation.
static const CGFloat kVideoDisc       = 48.0f;
static const CGFloat kGifDisc         = 42.0f;
/// A caption plate on a picture: how far in it sits, and the room it keeps.
static const CGFloat kCaptionInset    = TGMetricPadSmall;
/// How far a stamp on a picture sits in from its corner.
static const CGFloat kMediaStampInset = TGMetricPadSmall;

// ── the record bar and the player bar ───────────────────────────────────────
// The two strips that take the composer's place: one while a voice note is
// being recorded, one while a track is playing.

/// The red dot, the running clock beside it, and the "slide to cancel" line.
static const CGFloat kRecordDotX      = TGMetricPadLarge;
static const CGFloat kRecordClockX    = 32.0f;
static const CGFloat kRecordClockW    = 62.0f;
static const CGFloat kRecordSlideX    = 100.0f;
static const CGFloat kRecordSlideRoom = 180.0f;
/// The Cancel button that replaces all of it once recording is locked.
static const CGFloat kRecordCancelW   = 100.0f;
static const CGFloat kRecordCancelH   = 32.0f;
/// The lock pill above the mic: a padlock over an arrow.
static const CGFloat kRecordLockGlyph = 18.0f;
static const CGFloat kRecordLockArrow = 16.0f;
static const CGFloat kRecordLockArrowY = 36.0f;
static const CGFloat kRecordLockRest  = TGMetricPadMedium;
static const CGFloat kRecordLockLift  = TGMetricPadLarge;
/// The player bar: artwork, a play button, two lines of text, a clock, and
/// the transport buttons that only a music track gets.
static const CGFloat kPlayerArtX      = TGMetricPad;
static const CGFloat kPlayerArtLift   = 1.0f;
static const CGFloat kPlayerButton    = 28.0f;
static const CGFloat kPlayerButtonGap = TGMetricPadSmall;
static const CGFloat kPlayerArtGap    = 6.0f;
static const CGFloat kPlayerCloseW    = TGMetricCloseSide;
static const CGFloat kPlayerRightEdge = 38.0f;
static const CGFloat kPlayerClockW    = 72.0f;
static const CGFloat kPlayerClockDrop = TGMetricPad;
static const CGFloat kPlayerSpeedW    = 40.0f;
static const CGFloat kPlayerTextMin   = 40.0f;
static const CGFloat kPlayerProgressH = TGMetricPadTiny;
/// The bar's two lines are packed into the height of the button beside them,
/// so they are tighter than the line scale and say so here rather than
/// borrowing a name from it.
static const CGFloat kPlayerTitleLine  = 15.0f;
static const CGFloat kPlayerDetailLine = 13.0f;
/// The composer: the attach button, the field between them, the send button
/// and the sticker button tucked in beside it.
static const CGFloat kAttachWidth     = 34.0f;
static const CGFloat kComposerInset   = TGMetricPadSmall;
static const CGFloat kSendInset       = 6.0f;
static const CGFloat kStickerInset    = TGMetricSendSide + 6.0f;
static const CGFloat kStickerWidth    = 30.0f;
static const CGFloat kFieldLeft       = 40.0f;
static const CGFloat kFieldRoom       = 120.0f;
static const CGFloat kFieldInsetV     = TGMetricPad;
static const CGFloat kFieldLeftPad    = TGMetricPadMedium;
/// The reply / edit banner above the composer: a stripe, then two lines.
static const CGFloat kBannerStripeX   = TGMetricPadMedium + TGMetricPadTiny;
static const CGFloat kBannerStripeTop = TGMetricPad;
static const CGFloat kBannerTextX     = 22.0f;
static const CGFloat kBannerTitleTop  = TGMetricPadSmall;
/// The little plate that says a file is being fetched.
static const CGFloat kHUDWidth        = 110.0f;
static const CGFloat kHUDHeight       = TGMetricListAvatar;
// The percent label and the progress bar ride inside downloadHUD; cells use
// this tag range too.
static const NSInteger kHUDPercentTag = 0x9102;
static const NSInteger kHUDBarTag     = 0x9103;
/// The title view in the navigation bar: the chat's name over who is there.
static const CGFloat kTitleWidth      = 200.0f;
static const CGFloat kTitleRow        = TGMetricListAvatar;
/// The pinned-message strip under the navigation bar.
static const CGFloat kPinnedBanner    = 34.0f;
/// The cross that dismisses the banner.
static const CGFloat kBannerCloseGlyph = 16.0f;

// The three placers a cell configure uses; pure functions over the cell's
// own parts.

static inline void TGPlaceStamp(TGBubbleCell *cell, CGRect bubbleFrame,
								CGFloat timeWidth, BOOL mine) {
	cell.time.frame = CGRectMake(
			bubbleFrame.size.width - timeWidth - kPadH,
			bubbleFrame.size.height - TGMetricStampBottomInset,
			timeWidth - (mine ? TGMetricStampTicksRoom : 0),
			TGMetricStampHeight);
}

static inline void TGPlaceTicks(TGBubbleCell *cell, CGRect bubbleFrame) {
	CGFloat stampTop = cell.time.frame.origin.y > 0 ? cell.time.frame.origin.y : (bubbleFrame.size.height - TGMetricStampBottomInset);
	cell.ticks.frame = CGRectMake(
			bubbleFrame.size.width - kPadH - TGMetricTicksWidth,
			stampTop + TGCenteredOrigin(TGMetricStampHeight, TGMetricTicksHeight),
			TGMetricTicksWidth, TGMetricTicksHeight);
}

static inline void TGPlaceTitleDetail(TGBubbleCell *cell, CGFloat x, CGFloat top,
									  CGFloat width) {
	cell.body.frame = CGRectMake(x, top + TGMetricBubbleTitleTop, width,
								 TGMetricBubbleTitleHeight);
	cell.subtitle.frame = CGRectMake(x, top + TGMetricBubbleDetailTop, width,
									 TGMetricBubbleDetailHeight);
}

UIColor *TGSenderColour(int64_t userId);


#endif // TGCHATGEOMETRY_H
