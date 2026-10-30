//
// TGStyle+Metrics.h
// Component dimensions, padding scales, corner radii and layout metrics.
//
#import <UIKit/UIKit.h>
#import "TGStyle+Decorations.h"
#import "TGStyle+Typography.h"

#ifdef __cplusplus
extern "C" {
#endif

#pragma mark - the spacing scale

/// 2. A hairline gap: a title over its text, cells in a collage.
static const CGFloat TGMetricPadTiny           = 2.0f;
/// 4. Inside something small: a pill, a badge, a stamp.
static const CGFloat TGMetricPadSmall          = 4.0f;
/// 8. The default. Reach for this one first.
static const CGFloat TGMetricPad               = 8.0f;
/// 10. A list row's own inset, which sits in from the screen's gutter.
static const CGFloat TGMetricPadMedium         = 10.0f;
/// 16. A card's inner inset, a wide margin.
static const CGFloat TGMetricPadLarge          = 16.0f;
/// 20. The roomiest step: a screen that is mostly empty, a login form.
static const CGFloat TGMetricPadWide           = 20.0f;

/// Extra padding horizontally when measuring text bounds (2 pt).
static const CGFloat TGMetricTextPadH          = TGMetricPadTiny;
/// Measuring allowance for CoreText rounding.
static const CGFloat TGMetricTextPadV          = 1.0f;

#pragma mark - metrics

/// One row of a list or a settings group.
static const CGFloat TGMetricRow        = 44.0f;
/// A row showing somebody: their picture, their name, and a line under it.
static const CGFloat TGMetricPersonRow  = 56.0f;
/// Settings profile row height.
static const CGFloat TGMetricSettingsProfileRow = 168.0f;
/// Settings theme preview row height.
static const CGFloat TGMetricSettingsPreviewRow = 108.0f;
/// Profile avatar photos row height.
static const CGFloat TGMetricProfilePhotoRow    = 180.0f;
/// Profile avatar photo square side in photos viewer.
static const CGFloat TGMetricProfilePhotoSide   = 100.0f;
/// Edit profile avatar header row height.
static const CGFloat TGMetricEditProfileHeaderRow = 126.0f;
/// Search lens icon side in search bars.
static const CGFloat TGMetricSearchIconSize     = 15.0f;
/// Button height for small toolbar buttons (e.g. selection edit toolbar).
static const CGFloat TGMetricButtonHeightSmall  = 36.0f;
/// Selection edit toolbar action button width (140 pt).
static const CGFloat TGMetricEditToolbarButtonWidth = 140.0f;
/// Offline map card width.
static const CGFloat TGMetricMapCardWidth       = 220.0f;
/// Offline map card height.
static const CGFloat TGMetricMapCardHeight      = 130.0f;
/// The picture on a list row - chats, contacts, search, the forward picker.
static const CGFloat TGMetricListAvatar = 40.0f;
/// Text from the side of the screen (UIKit's own separator inset).
static const CGFloat TGMetricGutter     = 15.0f;
/// The gap around a card floating over a dimmed screen.
static const CGFloat TGMetricCardMargin = TGMetricPad;

#pragma mark - corner radii

/// 0. Sharp corner.
static const CGFloat TGMetricCornerNone          = 0.0f;
/// 3. Fine corners on artwork, thumbnails, tiny status markers.
static const CGFloat TGMetricCornerSmall         = 3.0f;
/// 6. Medium corners on toast notifications, thumbnails, input plates.
static const CGFloat TGMetricCornerMedium        = 6.0f;
/// 8. Standard interactive controls: text inputs, action buttons, HUDs, dialog boxes.
static const CGFloat TGMetricCornerControl       = 8.0f;
/// 12. Floating sheets, alert cards, dialogs, popup menus (iOS 6 + Modern Telegram).
static const CGFloat TGMetricCornerCard          = 12.0f;
/// 16. Soft rounded message bubble in modern flat mode.
static const CGFloat TGMetricCornerBubbleFlat    = 16.0f;
/// 10. Softly rounded message bubble in iOS 6 skeuomorphic mode.
static const CGFloat TGMetricCornerBubbleSkeuo   = 10.0f;
/// 5. Joined message bubble corner where runs meet.
static const CGFloat TGMetricCornerBubbleJoined  = 5.0f;

#pragma mark - circular and pill corner tokens

/// Call screen avatar square side (120 pt).
static const CGFloat TGMetricCallAvatarSide      = 120.0f;
/// Round call action button square side (60 pt).
static const CGFloat TGMetricCallButtonSide      = 60.0f;
static const CGFloat TGMetricCallEmojiTop        = 26.0f;
static const CGFloat TGMetricCallEmojiHeight     = 30.0f;
static const CGFloat TGMetricCallNameHeight      = TGMetricLineHero;
static const CGFloat TGMetricCallStatusHeight    = TGMetricLineBody;
static const CGFloat TGMetricCallTogglesBottom   = 150.0f;
static const CGFloat TGMetricCallLabelGap        = 65.0f;
static const CGFloat TGMetricCallLabelWidth      = 80.0f;
static const CGFloat TGMetricCallLabelHeight     = 15.0f;

#pragma mark - menu and sheet metrics

static const CGFloat TGMetricMenuWidth      = 188.0f;
static const CGFloat TGMetricMenuRow        = 44.0f;
static const CGFloat TGMetricActionRow      = 50.0f;
static const CGFloat TGMetricButtonHeight   = 48.0f;
static const CGFloat TGMetricChatRow        = 76.0f;

#pragma mark - message bubble metrics

static const CGFloat TGMetricBubblePadH         = TGMetricPadMedium;
static const CGFloat TGMetricBubblePadV         = TGMetricPad;
static const CGFloat TGMetricGroupAvatarSide    = 28.0f;
static const CGFloat TGMetricImageMax           = 200.0f;
static const CGFloat TGMetricPollRow            = 30.0f;
static const CGFloat TGMetricComposeBannerTextMarginRight = 66.0f;
static const CGFloat TGMetricPinnedBannerTextPadRight = 24.0f;

#pragma mark - input and picker metrics

static const CGFloat TGMetricPickerHeight       = 216.0f;
static const CGFloat TGMetricJumpSide           = 40.0f;
static const CGFloat TGMetricReplyPull          = 56.0f;
static const CGFloat TGMetricFolderTabRow       = 40.0f;
static const CGFloat TGMetricActionTile         = 52.0f;
static const CGFloat TGMetricProfileAvatar      = 80.0f;

#pragma mark - viewer and panel metrics

static const CGFloat TGMetricViewerTopBar       = 54.0f;
static const CGFloat TGMetricViewerBottomBar    = 62.0f;
static const CGFloat TGMetricViewerTitleSide       = 70.0f;
static const CGFloat TGMetricViewerCaptionMarginRight = 88.0f;
static const CGFloat TGMetricViewerScrubberMarginRight = 104.0f;
static const CGFloat TGMetricEmojiPanelHeight   = 216.0f;
static const CGFloat TGMetricEmojiStripHeight   = 38.0f;
static const CGFloat TGMetricEmojiTabsHeight    = 36.0f;
static const CGFloat TGMetricEmojiCell          = 40.0f;
static const CGFloat TGMetricEmojiHeader        = 22.0f;
static const CGFloat TGMetricMediaStripHeader   = 38.0f;

#pragma mark - table section metrics

static const CGFloat TGMetricSectionHeaderHeight = 32.0f;
static const CGFloat TGMetricSectionHeaderEmpty  = 20.0f;
static const CGFloat TGMetricSectionFooterGap    = TGMetricPadLarge;
static const CGFloat TGMetricSectionFooterRoot   = 38.0f;

static const CGFloat TGMetricToastBottomOffset = 70.0f;
static const CGFloat TGMetricStoryCaptionBottomOffset = 76.0f;
static const CGFloat TGMetricStoryCaptionHeight       = 60.0f;

#pragma mark - popup, sheet, and alert tokens

static const CGFloat TGMetricMenuGlyph          = 22.0f;
static const CGFloat TGMetricMenuInset          = TGMetricPadLarge;
static const CGFloat TGMetricAlertPad           = TGMetricPadLarge;
static const CGFloat TGMetricAlertTextGap       = TGMetricPad;
static const CGFloat TGMetricAlertFieldTop      = TGMetricPad;
static const CGFloat TGMetricAttachStrip        = 100.0f;
static const CGFloat TGMetricAttachThumb        = 86.0f;
static const CGFloat TGMetricCloseSide          = 30.0f;
static const CGFloat TGMetricGiftAvatar         = 22.0f;
static const CGFloat TGMetricGiftStar           = 15.0f;
static const CGFloat TGMetricSnackbarInset      = TGMetricPad;
static const CGFloat TGMetricSnackbarRing       = 22.0f;
static const CGFloat TGMetricImageHintBottomOffset = 34.0f;

#pragma mark - media and collage layout

static const CGFloat TGMetricScreenWidth        = 320.0f;
static const CGFloat TGMetricCompactBarHeight   = 32.0f;
static const CGFloat TGMetricCollageWidth       = 220.0f;
static const CGFloat TGMetricCollageGap         = TGMetricPadTiny;
static const CGFloat TGMetricCollageHeightDual  = 135.0f;
static const CGFloat TGMetricCollageTopHeight   = 120.0f;
static const CGFloat TGMetricCollageBottomHeight= 88.0f;
static const CGFloat TGMetricCollageQuadHeight  = 104.0f;
static const CGFloat TGMetricQuoteForwardLine   = TGMetricLineBody;
static const CGFloat TGMetricSenderLineHeight   = TGMetricLineCaption;
static const CGFloat TGMetricSelectionShift     = 34.0f;
static const CGFloat TGMetricLoginQRSize        = 180.0f;

static const CGFloat TGMetricStackTop   = TGMetricPadLarge;
static const CGFloat TGMetricStackStep  = TGMetricPad;
static const CGFloat TGMetricStackGroup = 20.0f;
static const CGFloat TGMetricLoginSubtitleHeight = TGMetricLineSubhead + TGMetricLineSubhead;
static const CGFloat TGMetricLoginPrefixWidth    = 56.0f;
static const CGFloat TGMetricLoginLinkHeight     = 30.0f;
static const CGFloat TGMetricStackQRTop          = 64.0f;
static const CGFloat TGMetricUploadPhotoSide     = 640.0f;
static const CGFloat TGMetricTextMeasureHeight   = 10000.0f;
static const CGFloat TGMetricAttachTick         = 18.0f;
static const CGFloat TGMetricTicksWidth         = 15.0f;
static const CGFloat TGMetricTicksHeight        = 9.0f;
static const CGFloat TGMetricUnreadDotSide      = 7.0f;

static const CGFloat TGMetricBubbleTitleHeight  = 19.0f;
static const CGFloat TGMetricBubbleDetailHeight = TGMetricLineCaption;
static const CGFloat TGMetricBubbleTitleTop     = TGMetricPadTiny;
static const CGFloat TGMetricBubbleDetailTop    = 23.0f;
static const CGFloat TGMetricBubbleDiscColumn   = 24.0f;
static const CGFloat TGMetricStampHeight        = 12.0f;
static const CGFloat TGMetricStampBottomInset   = 17.0f;
static const CGFloat TGMetricStampTicksRoom     = 18.0f;
static const CGFloat TGMetricPollDotSide        = 16.0f;
static const CGFloat TGMetricCallControlSide    = 34.0f;
static const CGFloat TGMetricCallGlyphSide      = 28.0f;

static const CGFloat TGMetricPlayerThumbSide    = 8.0f;
static const CGFloat TGMetricRecordDotSide      = 9.0f;
static const CGFloat TGMetricRecordHaloSide     = 60.0f;
static const CGFloat TGMetricJumpBadgeHeight    = TGMetricLineBody;
static const CGFloat TGMetricChatBadgeHeight    = TGMetricLineRow;
static const CGFloat TGMetricChatBadgeTop       = 42.0f;
static const CGFloat TGMetricFolderPillInset    = TGMetricPadSmall;
static const CGFloat TGMetricHistoryPageAroundPinned = 40.0f;
static const CGFloat TGMetricHistoryTopGate          = 100.0f;
static const CGFloat TGMetricFloatingDateHeight = 22.0f;
static const CGFloat TGMetricVoicePillWidth     = 32.0f;
static const CGFloat TGMetricVoicePillHeight    = 62.0f;

#pragma mark - storage chart metrics

static const CGFloat TGMetricStorageRingSide     = 150.0f;
static const CGFloat TGMetricStorageRingWidth    = 26.0f;

#pragma mark - audio and video recording metrics

static const CGFloat TGMetricRoundVideoSide     = 178.0f;
static const CGFloat TGMetricVoiceDragDeadzone  = 25.0f;
static const CGFloat TGMetricVoiceLockDistance  = 35.0f;
static const CGFloat TGMetricVoiceSlideCancelDistance = 45.0f;
static const CGFloat TGMetricVoiceSlideMaxShift = 40.0f;
static const CGFloat TGMetricVoiceLockMaxShift  = 12.0f;
static const CGFloat TGMetricMediaStampCheckPhotoInset = 17.0f;
static const CGFloat TGMetricJumpMarginRight       = TGMetricPad;
static const CGFloat TGMetricJumpMarginBottom      = TGMetricPadMedium;
static const CGFloat TGMetricBadgeOffsetTop        = -9.0f;
static const CGFloat TGMetricFloatingDateTopOffset = TGMetricPad;
static const CGFloat TGMetricMenuActionOffset      = 60.0f;
static const CGFloat TGMetricChatListMenuX         = 120.0f;
static const CGFloat TGMetricChatCellDateGap       = TGMetricPadSmall;
static const CGFloat TGMetricSectionHeaderHidden = 0.001f;
static const CGFloat TGFontMessageBaseSize      = 13.0f;
static const CGFloat TGFontMessageStep          = 2.0f;
static const CGFloat TGPlaybackSpeedNormal      = 1.0f;
static const CGFloat TGPlaybackSpeedFast        = 1.5f;
static const CGFloat TGPlaybackSpeedDouble      = 2.0f;
static const CGFloat TGMetricZoomMin            = 1.0f;
static const CGFloat TGMetricZoomMax            = 4.0f;
static const CGFloat TGMetricQRViewfinderRatio  = 0.66f;
static const CGFloat TGMetricMediaRatioLandscape = 0.75f;

static const CGFloat TGMetricEmojiArtworkInsetRatio = 0.08f;
static const CGFloat TGMetricEmojiArtworkSizeRatio  = 0.84f;
static const CGFloat TGMetricEmojiArtworkFontInsetRatio = 3.5f;
static const CGFloat TGMetricGIFCellAspect          = 0.80f;
static const CGFloat TGMetricGiftArtRatio         = 0.55f;
static const CGFloat TGMetricGiftArtMaxSide       = 150.0f;
static const CGFloat TGMetricViewerDismissVelocity = 900.0f;
static const CGFloat TGMetricViewerDismissDistance = 110.0f;
static const CGFloat TGMetricViewerFadeDistance    = 420.0f;
static const CGFloat TGMetricViewerMaxFadeRatio    = 0.66f;
static const CGFloat TGDampingReplySwipeSlope      = 1.50f;

#pragma mark - general numeric and scale tokens

static const CGFloat TGMetricZero                  = 0.0f;
static const CGFloat TGMetricScaleFull             = 1.0f;
static const CGFloat TGMetricEpsilon               = 0.10f;
static const CGFloat TGPercentFull                 = 100.0f;
static const CGFloat TGCompressionQualityHigh      = 0.85f;
static const CGFloat TGCompressionQualityStandard  = 0.90f;
static const CGFloat TGMetricBubbleRunGapStart     = TGMetricPadSmall;
static const CGFloat TGMetricBubbleRunGapInner     = 1.0f;
static const CGFloat TGMetricBubbleRowInset        = 3.0f;
static const CGFloat TGMetricVoiceLockMargin       = 20.0f;
static const CGFloat TGPlaybackSpeedThresholdFast  = 1.25f;
static const CGFloat TGPlaybackSpeedThresholdDouble = 1.75f;
static const CGFloat TGPlaybackSpeedStopped        = 0.0f;
static const CGFloat TGMetricZoomDoubleTap         = 2.5f;
static const CGFloat TGFontMessageBaseCap          = 14.0f;
static const CGFloat TGMetricFontSizeDeltaThreshold = 14.0f;

static const CGFloat TGMetricBubbleMaxW         = 246.0f;
static const CGFloat TGMetricBubbleTailHeight   = 13.0f;
static const CGFloat TGMetricBubbleTailWidth    = 6.0f;
static const CGFloat TGMetricChatAvatar         = 60.0f;
static const CGFloat TGMetricFileDisc           = 37.0f;
static const CGFloat TGMetricFileTile           = 71.0f;
static const CGFloat TGMetricInputBarHeight     = 48.0f;
static const CGFloat TGMetricPlayerArt          = 36.0f;
static const CGFloat TGMetricPlayerBarHeight    = 48.0f;
static const CGFloat TGMetricSendSide           = 36.0f;
static const CGFloat TGMetricStrokeFine         = 1.4f;
static const CGFloat TGMetricTrackArt           = 44.0f;
static const CGFloat TGMetricTrackDisc          = 28.0f;
static const CGFloat TGMetricTrackRow           = 60.0f;
static const CGFloat TGMetricTrackContent       = 200.0f;

#pragma mark - iOS 6 Reimagined player and chrome metrics

static const CGFloat TGMetricPlayerModalArtSide    = 190.0f;
static const CGFloat TGMetricPlayerModalButtonMain = 58.0f;
static const CGFloat TGMetricPlayerModalButtonSide = 44.0f;
static const CGFloat TGMetricPlayerModalSliderH   = 28.0f;
static const CGFloat TGMetricEmptyIconSide         = 64.0f;
static const CGFloat TGMetricConnectionBannerH     = 28.0f;
static const CGFloat TGMetricSegmentedHeight       = 30.0f;

#pragma mark - iOS 6 Reimagined UI Component metrics

static const CGFloat TGMetricButtonSmallH          = 28.0f;
static const CGFloat TGMetricButtonMediumH         = 36.0f;
static const CGFloat TGMetricButtonLargeH          = 44.0f;
static const CGFloat TGMetricSwitchW               = 51.0f;
static const CGFloat TGMetricSwitchH               = 31.0f;
static const CGFloat TGMetricSwitchThumbD          = 27.0f;
static const CGFloat TGMetricSliderH               = 28.0f;
static const CGFloat TGMetricSliderThumbD          = 22.0f;
static const CGFloat TGMetricSliderTrackH          = 6.0f;
static const CGFloat TGMetricTextFieldH            = 36.0f;
static const CGFloat TGMetricBadgeH                = 18.0f;
static const CGFloat TGMetricTabBarH               = 49.0f;

#ifdef __cplusplus
}
#endif
