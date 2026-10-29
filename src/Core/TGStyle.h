//
// TGStyle - the one place a size comes from.
//
// Colour has lived in TGTheme+Palette since the beginning; type and metrics
// did not, so every screen picked its own and the app drifted apart - a
// contacts row at 15, the same row in settings at 16, section captions at 11
// and 12 and 13 depending on who wrote the screen. These are the roles, with
// one size each. A screen asks for the role, not the number.
//
// Sizes a screen cannot choose - a glyph fitted to its box, a bold run inside
// message text at the user's own text size - go through TGFontAtSize and its
// two siblings. Those take a computed value, never a literal: scripts/lint_tokens.sh
// fails the build on a literal anywhere, here included.
//
// ── on two names holding the same number ────────────────────────────────────
//
// There are 245 names here over about a hundred values, so most numbers are
// spelled more
// than once, and the obvious reading - that the extras are duplicates - is
// the wrong one. TGMetricButtonHeight, TGMetricInputBarHeight and
// TGMetricPlayerBarHeight are all 48 and all have to stay: raising the music
// player's strip must not silently move every button in the app. A name
// answers to a drawing, not to a number, and two drawings that happen to
// agree today are still two drawings.
//
// So a name is merged only when the two are the same thing and cannot come
// apart - the ticks on a bubble and the ticks on a stamp over a picture are
// one glyph, drawn once, and had no business having two pairs of names; a map
// card's height and the height it is displayed at cannot differ without the
// image being stretched. Both of those are gone.
//
// Where a name does belong to a scale - any gap, inset or margin; the box
// given to one line of text - it does not repeat the number, it derives from
// the step, so TGMetricAlertPad still says what it is for while sitting on
// the 16pt step and cannot drift off it in silence. Three scales carry most
// of this: spacing, the line boxes, and the corner radii.
//
// What does not go here at all is a dimension only one screen has any use
// for. A call bubble's width allowance and a map pin's 28 by 36 live beside
// the code that draws them - in TGChatViewControllerInternal.h and the rest -
// because a name in this file that one file reads is how the layer came to
// hold more names than values in the first place.
//
#import <UIKit/UIKit.h>

#ifdef __cplusplus
extern "C" {
#endif

#pragma mark - type scale

/// 11, point size for micro captions / minimum monospace code.
static const CGFloat TGFontSizeMicro           = 11.0f;

/// 28, regular. A name on a screen that is only that name: the call screen.
UIFont *TGFontHero(void);
/// 22, bold. The name at the top of a profile, a total in storage.
UIFont *TGFontTitle(void);
/// 17, bold. A navigation header's name, a prominent button's label.
UIFont *TGFontHeader(void);
/// 17, regular. Something being typed into: a login field.
UIFont *TGFontInput(void);
/// 16, regular. A row's label, in a list and in settings alike.
UIFont *TGFontRow(void);
/// 16, bold. The same row when it carries a title, and action buttons.
UIFont *TGFontRowStrong(void);
/// 15, regular. Body text outside a bubble: previews, sheet rows, hints.
UIFont *TGFontBody(void);
/// 15, bold. A result's title, a HUD, a counter.
UIFont *TGFontBodyStrong(void);
/// 14, regular. The second line of a row, the date on a chat list row.
UIFont *TGFontSubhead(void);
/// 14, bold. An inline button: Undo, a tab.
UIFont *TGFontSubheadStrong(void);
/// 13, regular. The value on the right of a settings row, a quote, reactions.
UIFont *TGFontCaption(void);
/// 13, bold. A quote's author, the floating date, a badge.
UIFont *TGFontCaptionStrong(void);
/// 12, regular. A sender line, a forward line, a footer under a section.
UIFont *TGFontMeta(void);
/// 12, bold. A sender's name inside a bubble, the jump badge.
UIFont *TGFontMetaStrong(void);
/// 11, regular. A timestamp.
UIFont *TGFontMicro(void);
/// 11, bold. A short all-caps label.
UIFont *TGFontMicroStrong(void);

/// 16, medium weight. The chat list's own title face, which is not the system
/// bold - their list reads lighter than a bold row would.
UIFont *TGFontListTitle(void);

#pragma mark - glyphs and emoji

// Text that is really an icon. Its size belongs to the box it sits in, not to
// the type scale, so it is named for the box.

/// 22. A dismiss cross, or a round button's glyph where no drawn icon exists.
UIFont *TGFontGlyph(void);
/// 18. The transport arrows in the player bar, which is half a row tall.
UIFont *TGFontGlyphSmall(void);
/// 10, bold. A label on a plate laid over media: "Apple Maps" on a map.
UIFont *TGFontPlate(void);
/// 28. An emoji on a key of the picker.
UIFont *TGFontEmoji(void);
/// 20. An emoji on the picker's category strip, which is smaller than a key.
UIFont *TGFontEmojiSmall(void);
/// 12. An emoji at caption/meta size.
UIFont *TGFontEmojiMeta(void);
/// 36. A sticker's emoji standing in for a thumbnail that has not arrived.
UIFont *TGFontEmojiLarge(void);

#pragma mark - computed sizes

/// For a size the screen does not choose: a glyph fitted to its box, a run of
/// message text at the size the user set. Never call these with a literal.
UIFont *TGFontAtSize(CGFloat size);
UIFont *TGFontBoldAtSize(CGFloat size);
UIFont *TGFontItalicAtSize(CGFloat size);
/// Monospaced code font at a computed size.
UIFont *TGFontCodeAtSize(CGFloat size);
/// Medium weight at a computed size, with bold as the fallback where the face
/// is missing. Initials drawn into an avatar of any side.
UIFont *TGFontMediumAtSize(CGFloat size);

#pragma mark - colour that is not the theme's

/// The blue a link is drawn in inside message text. It lives here, not in the
/// palette, because the text layout is deliberately free of the theme: it is
/// compiled on its own in the tests and must not drag the theme in behind it.
UIColor *TGColourLink(void);
UIColor *TGColourCodeBackground(void);
UIColor *TGColourCodeBlockBackground(void);

/// The decorative colours an icon tile is drawn in - decoration, not
/// semantics, so they are named by the hue and not the row: rows are
/// re-ordered by product, hues do not drift by a point again.
UIColor *TGIconTileViolet(void);
UIColor *TGIconTilePurple(void);
UIColor *TGIconTileOrchid(void);
UIColor *TGIconTileSky(void);
UIColor *TGIconTileAzure(void);
UIColor *TGIconTileCyan(void);
UIColor *TGIconTileGreen(void);
UIColor *TGIconTileAmber(void);
UIColor *TGIconTileGold(void);
UIColor *TGIconTileCoral(void);
UIColor *TGIconTileRed(void);
UIColor *TGIconTileGrey(void);
UIColor *TGIconTileSlate(void);

#pragma mark - the spacing scale

// Six steps and no seventh. Before this the app spaced things at 2, 4, 5, 6,
// 7, 8, 10, 12, 14, 15, 16, 20 and 24, which is not a scale, it is whatever
// each screen's author felt like: an alert padded at 14 beside a card padded
// at 16, a pill inset 5 beside a bar inset 4. The eye cannot read a 1pt
// difference as meaning anything, so those differences were only noise, and
// noise that each new screen copied from whichever neighbour it grew from.
//
// Every gap, inset, margin and pad in the app is one of these. A role that
// wants its own name says so by deriving from a step - see TGMetricCardMargin
// and the rest below - so the name can explain itself while the value stays
// on the scale. Two values stand outside it on purpose, and each says why:
// TGMetricGutter, which is UIKit's own, and TGMetricTextPadV, which is a
// measuring allowance rather than a gap.

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
/// Not a step on the scale: a 1pt rounding allowance when measuring text,
/// which is a lie told to CoreText, not a gap anybody sees.
static const CGFloat TGMetricTextPadV          = 1.0f;
#pragma mark - the line scale

// The box a screen gives one line of text. These went the same way as the
// spacing did: a one-line label was 12, 13, 14, 15, 16, 17, 18, 19, 20, 21,
// 26 or 34 points tall depending on the screen, and nothing tied any of them
// to the font inside. A box 1pt short of its font clips the descender on a
// "g"; a box 4pt over it opens a gap the layout above has to absorb.
//
// So there is one line box per role in the type scale, and the name says
// which role it is for: TGFontCaption text gets TGMetricLineCaption. Ask for
// the pair, not the numbers. A label that holds two or more lines is measured
// instead - TGTextSize - and these do not apply to it.

/// One line of TGFontMicro (11).
static const CGFloat TGMetricLineMicro   = 14.0f;
/// One line of TGFontCaption (13).
static const CGFloat TGMetricLineCaption = 16.0f;
/// One line of TGFontSubhead (14).
static const CGFloat TGMetricLineSubhead = 17.0f;
/// One line of TGFontBody (15).
static const CGFloat TGMetricLineBody    = 18.0f;
/// One line of TGFontRow (16).
static const CGFloat TGMetricLineRow     = 20.0f;
/// One line of TGFontHeader (17).
static const CGFloat TGMetricLineHeader  = 21.0f;
/// One line of TGFontTitle (22).
static const CGFloat TGMetricLineTitle   = 26.0f;
/// One line of TGFontHero (28).
static const CGFloat TGMetricLineHero    = 34.0f;

#pragma mark - metrics

/// Returns half of a dimension without manual / 2 division.
static inline __attribute__((always_inline)) CGFloat TGHalf(CGFloat val) {
	return val * 0.5f;
}

/// Returns double of a dimension without manual * 2 multiplication.
static inline __attribute__((always_inline)) CGFloat TGDoubled(CGFloat val) {
	return val * 2.0f;
}

/// Computes the origin to center an item within a container without manual / 2 division.
static inline __attribute__((always_inline)) CGFloat TGCenteredOrigin(CGFloat containerSize, CGFloat itemSize) {
	return (containerSize - itemSize) * 0.5f;
}

/// One row of a list or a settings group.
static const CGFloat TGMetricRow        = 44.0f;
/// A row showing somebody: their picture, their name, and a line under it.
/// Contacts, the forward picker, topics, search and the scheduled list each
/// picked their own - 52, 56 and 60 - for the same row.
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
/// Text from the side of the screen. Not a step on the spacing scale: 15 is
/// UIKit's own separator inset on a 320pt screen, so what the app lays out
/// itself lines up with the text in a stock table cell beside it. Move it to
/// 16 and every custom header stands 1pt out of line with the system's.
static const CGFloat TGMetricGutter     = 15.0f;
/// The gap around a card floating over a dimmed screen. Its own name because
/// a card's outer gap and a component's inner padding answer to different
/// drawings, even while both sit on the 8pt step.
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
/// The call screen reads as a cursor from the top - the emoji that confirm
/// the key, the picture, the name, what the call is doing - and then one row
/// of buttons measured up from the bottom, End among them.
static const CGFloat TGMetricCallEmojiTop        = 26.0f;
static const CGFloat TGMetricCallEmojiHeight     = 30.0f;
static const CGFloat TGMetricCallNameHeight      = TGMetricLineHero;
static const CGFloat TGMetricCallStatusHeight    = TGMetricLineBody;
static const CGFloat TGMetricCallTogglesBottom   = 150.0f;
/// Call button label vertical gap from button origin (65 pt).
static const CGFloat TGMetricCallLabelGap        = 65.0f;
/// Call button caption label width (80 pt).
static const CGFloat TGMetricCallLabelWidth      = 80.0f;
/// Call button caption label height (15 pt).
static const CGFloat TGMetricCallLabelHeight     = 15.0f;

#pragma mark - menu and sheet metrics

/// Width of a floating contextual popup menu.
static const CGFloat TGMetricMenuWidth      = 188.0f;
/// Height of a single item in a popup menu.
static const CGFloat TGMetricMenuRow        = 44.0f;
/// Height of a choice or action button in an alert sheet.
static const CGFloat TGMetricActionRow      = 50.0f;
/// Height of a prominent action button.
static const CGFloat TGMetricButtonHeight   = 48.0f;
/// Height of a chat list row.
static const CGFloat TGMetricChatRow        = 76.0f;

#pragma mark - message bubble metrics

/// Horizontal inner padding for message bubbles.
static const CGFloat TGMetricBubblePadH         = TGMetricPadMedium;
/// Vertical inner padding for message bubbles.
static const CGFloat TGMetricBubblePadV         = TGMetricPad;
/// Sender avatar side in group chats.
static const CGFloat TGMetricGroupAvatarSide    = 28.0f;
/// Maximum side of an inline image or photo.
static const CGFloat TGMetricImageMax           = 200.0f;
/// Single option height in a poll bubble.
static const CGFloat TGMetricPollRow            = 30.0f;
/// Compose banner text right margin (leaving room for cancel button) (66 pt).
static const CGFloat TGMetricComposeBannerTextMarginRight = 66.0f;
/// Pinned message banner text right padding (24 pt).
/// Not a step on the spacing scale: it is the room a banner's text leaves on
/// the right for the cross that dismisses it, so it tracks that button's
/// width and not any gap.
static const CGFloat TGMetricPinnedBannerTextPadRight = 24.0f;

#pragma mark - input and picker metrics

/// Standard iOS wheel date/time picker height.
static const CGFloat TGMetricPickerHeight       = 216.0f;
/// Floating jump-to-bottom round button side.
static const CGFloat TGMetricJumpSide           = 40.0f;
/// Horizontal pull distance to trigger inline reply.
static const CGFloat TGMetricReplyPull          = 56.0f;
/// Folder category bar height above chat list.
static const CGFloat TGMetricFolderTabRow       = 40.0f;
/// Profile action tile height (Call, Mute, Search, More).
static const CGFloat TGMetricActionTile         = 52.0f;
/// Large profile photo avatar side.
static const CGFloat TGMetricProfileAvatar      = 80.0f;

#pragma mark - viewer and panel metrics

/// Top bar height in full-screen media viewer.
static const CGFloat TGMetricViewerTopBar       = 54.0f;
/// Bottom bar height in full-screen media viewer.
static const CGFloat TGMetricViewerBottomBar    = 62.0f;
/// Media viewer header counter/date label horizontal inset (70 pt).
static const CGFloat TGMetricViewerTitleSide       = 70.0f;
/// Media viewer bottom bar caption right margin (88 pt).
static const CGFloat TGMetricViewerCaptionMarginRight = 88.0f;
/// Media viewer scrubber right margin for time label (104 pt).
static const CGFloat TGMetricViewerScrubberMarginRight = 104.0f;
/// Total height of the emoji/sticker/GIF keyboard replacement panel (matches iOS system keyboard height).
static const CGFloat TGMetricEmojiPanelHeight   = 216.0f;
/// Emoji / sticker panel top strip height.
static const CGFloat TGMetricEmojiStripHeight   = 38.0f;
/// Emoji / sticker / GIF tab selector height.
static const CGFloat TGMetricEmojiTabsHeight    = 36.0f;
/// Grid cell size for an individual emoji item.
static const CGFloat TGMetricEmojiCell          = 40.0f;
/// Section header height in emoji panel.
static const CGFloat TGMetricEmojiHeader        = 22.0f;
/// Profile media strip category header height.
static const CGFloat TGMetricMediaStripHeader   = 38.0f;

#pragma mark - strokes and borders

/// Primary line-art icon stroke weight (1.8 pt).
static const CGFloat TGMetricStrokeIcon         = 1.8f;
/// Standard iOS hairline separator (0.5 pt on Retina).
static const CGFloat TGMetricHairline           = 0.5f;
/// 0 pt border stroke (flat mode).
static const CGFloat TGMetricBorderNone         = 0.0f;
/// Standard 1 pt border stroke.
static const CGFloat TGMetricBorderWidth        = 1.0f;
/// Standard medium border stroke.
static const CGFloat TGMetricBorderMedium       = 1.5f;
/// Standard thick 2 pt border stroke.
static const CGFloat TGMetricBorderThick        = 2.0f;

#pragma mark - motion and animation

/// Fast transition (150ms): dates, badges, immediate feedback.
static const NSTimeInterval TGAnimationDurationFast   = 0.15;
/// Standard transition (200ms): sheets, popups, viewer chrome.
static const NSTimeInterval TGAnimationDurationNormal = 0.20;
/// Medium transition (250ms): keyboard slide, composer expansion.
static const NSTimeInterval TGAnimationDurationMedium = 0.25;
/// Slow transition (300ms): toasts, screen cross-fades.
static const NSTimeInterval TGAnimationDurationSlow   = 0.30;
/// Long highlight pulse (600ms): jump-to-message highlight dissipation.
static const NSTimeInterval TGAnimationDurationHighlight = 0.60;

#pragma mark - elevation and shadows

/// Floating menu shadow blur radius (10 pt).
static const CGFloat TGMetricShadowMenuRadius   = 10.0f;
/// Floating menu shadow opacity (28%).
static const CGFloat TGMetricShadowMenuOpacity  = 0.28f;
/// Floating button shadow blur radius (2 pt).
static const CGFloat TGMetricShadowButtonRadius = 2.0f;
/// Floating button shadow opacity (18%).
static const CGFloat TGMetricShadowButtonOpacity= 0.18f;
/// Skeuomorphic etched light text shadow offset (0, 1).
static const CGSize TGMetricShadowOffsetEtched  = {0.0f, 1.0f};
/// Skeuomorphic recessed navigation bar title shadow offset (0, -1).
static const CGSize TGMetricShadowOffsetNav     = {0.0f, -1.0f};
/// Floating card / popup menu downward shadow offset (0, 4).
static const CGSize TGMetricShadowOffsetMenu    = {0.0f, 4.0f};

#pragma mark - opacity and alpha tokens

/// Fully opaque (1.0).
static const CGFloat TGAlphaOpaque            = 1.0f;
/// Inactive folder pill / panel tab (0.85).
static const CGFloat TGAlphaPillInactive      = 0.85f;
/// Secondary button / hint icon (0.75).
static const CGFloat TGAlphaSecondary         = 0.75f;
/// Dimmed control / call end button (0.50).
static const CGFloat TGAlphaDimmed            = 0.50f;
/// Disabled button / action item (0.40).
static const CGFloat TGAlphaDisabled          = 0.40f;
/// Message highlight flash start (0.30).
static const CGFloat TGAlphaHighlight         = 0.30f;
/// Pulse ring / track trace opacity (0.25).
static const CGFloat TGAlphaRingTrack         = 0.25f;
/// Minimum threshold alpha to consider non-empty (0.01).
static const CGFloat TGAlphaEpsilon           = 0.01f;
/// Fully transparent (0.0).
static const CGFloat TGAlphaTransparent       = 0.0f;

#pragma mark - transform scales

/// Dragged folder pill active scale (1.08).
static const CGFloat TGTransformScalePillActive   = 1.08f;
/// Active call end button press scale (0.86).
static const CGFloat TGTransformScaleButtonActive = 0.86f;
/// Popup menu appearance initial scale (0.85).
static const CGFloat TGTransformScaleMenuInitial  = 0.85f;
/// The ring a held call control wears: wider than the button it surrounds.
static const CGFloat TGTransformScaleRingHeld     = 1.22f;
/// Audio mic button small scale (0.30).
static const CGFloat TGTransformScaleSmall        = 0.30f;

#pragma mark - table section metrics

/// Grouped table section header standard height.
static const CGFloat TGMetricSectionHeaderHeight = 32.0f;
/// Grouped table empty header separator gap.
static const CGFloat TGMetricSectionHeaderEmpty  = 20.0f;
/// Grouped table footer text vertical padding.
static const CGFloat TGMetricSectionFooterGap    = TGMetricPadLarge;
/// Grouped table root page footer trailing height.
static const CGFloat TGMetricSectionFooterRoot   = 38.0f;

/// Toast HUD bottom margin above screen bottom (70 pt).
static const CGFloat TGMetricToastBottomOffset = 70.0f;
/// Story viewer caption bottom offset (76 pt).
static const CGFloat TGMetricStoryCaptionBottomOffset = 76.0f;
/// Story viewer caption box height (60 pt).
static const CGFloat TGMetricStoryCaptionHeight       = 60.0f;

#pragma mark - popup, sheet, and alert tokens

/// Glyphs inside popup menu rows.
static const CGFloat TGMetricMenuGlyph          = 22.0f;
/// Left inset inside popup menu rows.
static const CGFloat TGMetricMenuInset          = TGMetricPadLarge;
/// Alert sheet inner padding.
static const CGFloat TGMetricAlertPad           = TGMetricPadLarge;
/// Spacing between title and message in alert sheets.
static const CGFloat TGMetricAlertTextGap       = TGMetricPad;
/// Spacing above text input field in alert sheets.
static const CGFloat TGMetricAlertFieldTop      = TGMetricPad;
/// Height of recent photo strip in attach sheet.
static const CGFloat TGMetricAttachStrip        = 100.0f;
/// Side of photo thumbnail in attach sheet.
static const CGFloat TGMetricAttachThumb        = 86.0f;
/// Close round button side in full-screen viewers.
static const CGFloat TGMetricCloseSide          = 30.0f;
/// Compact avatar side inside gift viewer.
static const CGFloat TGMetricGiftAvatar         = 22.0f;
/// Star badge side inside gift viewer.
static const CGFloat TGMetricGiftStar           = 15.0f;
/// Inset of countdown plate in snackbar.
static const CGFloat TGMetricSnackbarInset      = TGMetricPad;
/// Countdown ring diameter in snackbar.
static const CGFloat TGMetricSnackbarRing       = 22.0f;
/// Full-screen image preview hold-to-save hint bottom offset (34 pt).
static const CGFloat TGMetricImageHintBottomOffset = 34.0f;

#pragma mark - media and collage layout

/// Standard screen width reference for legacy 3.5" and 4" devices (320 pt).
static const CGFloat TGMetricScreenWidth        = 320.0f;
/// Compact navigation bar height on 3.5" displays.
static const CGFloat TGMetricCompactBarHeight   = 32.0f;
/// Maximum width of an inline photo collage block.
static const CGFloat TGMetricCollageWidth       = 220.0f;
/// Gap between photos in an inline collage.
static const CGFloat TGMetricCollageGap         = TGMetricPadTiny;
/// Height of 2-photo collage layout.
static const CGFloat TGMetricCollageHeightDual  = 135.0f;
/// Top photo height in 3-photo collage layout.
static const CGFloat TGMetricCollageTopHeight   = 120.0f;
/// Bottom photo height in 3-photo collage layout.
static const CGFloat TGMetricCollageBottomHeight= 88.0f;
/// Height of each row in 4-photo collage layout.
static const CGFloat TGMetricCollageQuadHeight  = 104.0f;
/// Height of forwarded header line inside quotes.
static const CGFloat TGMetricQuoteForwardLine   = TGMetricLineBody;
/// Height of sender name header line inside bubbles.
static const CGFloat TGMetricSenderLineHeight   = TGMetricLineCaption;
/// Checkmark selection horizontal shift in edit mode.
static const CGFloat TGMetricSelectionShift     = 34.0f;
/// Login QR code dimension.
static const CGFloat TGMetricLoginQRSize        = 180.0f;

/// The sign-in screens are a vertical stack, and they were a pile of
/// absolute offsets: 14, 56, 108, 154, 190, 210 with gaps of 8, 8, 4, 6 and
/// 4 between them. One step between things, one larger step before a new
/// group, and the positions come out of adding them up.
static const CGFloat TGMetricStackTop   = TGMetricPadLarge;
static const CGFloat TGMetricStackStep  = TGMetricPad;
static const CGFloat TGMetricStackGroup = 20.0f;
/// The three sizes the sign-in stack needs that are not the shared scale:
/// two lines of instructions, the country prefix beside the number, and the
/// height of a plain text link or a segmented control.
static const CGFloat TGMetricLoginSubtitleHeight = TGMetricLineSubhead + TGMetricLineSubhead;
static const CGFloat TGMetricLoginPrefixWidth    = 56.0f;
static const CGFloat TGMetricLoginLinkHeight     = 30.0f;
/// Where the QR code sits, which is below a one-line instruction rather than
/// the two the other steps carry.
static const CGFloat TGMetricStackQRTop          = 64.0f;
/// The longest side a photo is scaled to before it is sent. Telegram's own
/// limit, so a picture that leaves this app is the size their clients expect.
static const CGFloat TGMetricUploadPhotoSide     = 640.0f;
/// An unbounded height to measure wrapped text against.
static const CGFloat TGMetricTextMeasureHeight   = 10000.0f;
/// Selected photo checkmark badge side in attach sheet.
static const CGFloat TGMetricAttachTick         = 18.0f;
/// The delivery ticks in the corner of your own bubble. The frame was
/// written out at four places, with 15x9 each time and three different rules
/// for the y - height-15, height-18 and a hand-counted offset - so the ticks
/// sat at three heights depending on what kind of message carried them.
static const CGFloat TGMetricTicksWidth         = 15.0f;
static const CGFloat TGMetricTicksHeight        = 9.0f;
/// How far the ticks' baseline sits above the bottom of the bubble.
/// The dot that marks a voice note unheard or a round note unwatched, and the
/// air around the clock that sits outside a round note.
static const CGFloat TGMetricUnreadDotSide      = 7.0f;

/// The two lines inside a bubble that names something - a file, a contact, a
/// track, a place. The title line and the line under it were written out at
/// 18/14, 19/16 and 18/16 in different branches, which is why a document and
/// a track did not line up with each other.
static const CGFloat TGMetricBubbleTitleHeight  = 19.0f;
static const CGFloat TGMetricBubbleDetailHeight = TGMetricLineCaption;
/// The gap from the top of such a bubble to its title, and from the title to
/// the line under it.
static const CGFloat TGMetricBubbleTitleTop     = TGMetricPadTiny;
static const CGFloat TGMetricBubbleDetailTop    = 23.0f;
/// The column a call bubble's text starts in, past its disc.
static const CGFloat TGMetricBubbleDiscColumn   = 24.0f;
/// The stamp in the corner of a bubble. Three branches placed it at
/// height-17 and one at a counted offset, and each worked out the room the
/// ticks take beside it with its own "mine ? 18 : 0".
static const CGFloat TGMetricStampHeight        = 12.0f;
/// Not a step on the spacing scale: a position, measured up from the bottom
/// of a bubble to the baseline the stamp sits on.
static const CGFloat TGMetricStampBottomInset   = 17.0f;
static const CGFloat TGMetricStampTicksRoom     = 18.0f;
/// Radio dot indicator side in polls.
static const CGFloat TGMetricPollDotSide        = 16.0f;
/// Contact action button or right call button width.
static const CGFloat TGMetricCallControlSide    = 34.0f;
/// The glyph inside a round call button.
static const CGFloat TGMetricCallGlyphSide      = 28.0f;

/// Small round things, named by their side rather than by their roundness:
/// the radius is half of whichever of these the view is, which cannot drift
/// from it the way a separate TGMetricCorner* name could.
static const CGFloat TGMetricPlayerThumbSide    = 8.0f;
static const CGFloat TGMetricRecordDotSide      = 9.0f;
static const CGFloat TGMetricRecordHaloSide     = 60.0f;
/// Capsules: the height is what rounds them.
static const CGFloat TGMetricJumpBadgeHeight    = TGMetricLineBody;
static const CGFloat TGMetricChatBadgeHeight    = TGMetricLineRow;
/// Where the unread count sits on a chat list row.
static const CGFloat TGMetricChatBadgeTop       = 42.0f;
/// How far the folder pill is inset into its strip, top and bottom. Its
/// height and its radius are both worked out from this, so they cannot
/// disagree - which is how the pill stopped being a pill once.
static const CGFloat TGMetricFolderPillInset    = TGMetricPadSmall;
/// How much history to fetch around a pinned message when going to it.
static const CGFloat TGMetricHistoryPageAroundPinned = 40.0f;
/// How close to the top a scroll must come before older history is asked for.
static const CGFloat TGMetricHistoryTopGate          = 100.0f;
static const CGFloat TGMetricFloatingDateHeight = 22.0f;
// The map card's own height is TGMetricMapCardHeight, and the bubble shows it
// at that height. They were two names, and two names for the height a drawn
// image is displayed at is how an image comes to be drawn at one size and
// stretched to another.
/// Width of the audio record lock pill capsule.
static const CGFloat TGMetricVoicePillWidth     = 32.0f;
/// Height of the audio record lock pill capsule.
static const CGFloat TGMetricVoicePillHeight    = 62.0f;

#pragma mark - storage chart metrics

/// Diameter of circular storage usage chart.
static const CGFloat TGMetricStorageRingSide     = 150.0f;
/// Ring stroke thickness of storage usage chart.
static const CGFloat TGMetricStorageRingWidth    = 26.0f;

#pragma mark - audio and video recording metrics

/// Round video note player circle side (178 pt).
static const CGFloat TGMetricRoundVideoSide     = 178.0f;
/// Deadzone drag threshold before triggering voice cancel (25 pt).
static const CGFloat TGMetricVoiceDragDeadzone  = 25.0f;
/// Upward drag distance to lock voice recording (35 pt).
static const CGFloat TGMetricVoiceLockDistance  = 35.0f;
/// Leftward drag distance to cancel voice recording (45 pt).
static const CGFloat TGMetricVoiceSlideCancelDistance = 45.0f;
/// Maximum visual slide shift during voice cancel (40 pt).
static const CGFloat TGMetricVoiceSlideMaxShift = 40.0f;
/// Maximum visual slide shift during voice lock (12 pt).
static const CGFloat TGMetricVoiceLockMaxShift  = 12.0f;
/// How far back the ticks sit from the right edge of a stamp plate drawn on
/// a picture. The ticks themselves are TGMetricTicksWidth by
/// TGMetricTicksHeight here as everywhere: it is one glyph, so it had no
/// business having a second pair of names.
static const CGFloat TGMetricMediaStampCheckPhotoInset = 17.0f;
/// Jump button right margin from edge (8 pt).
static const CGFloat TGMetricJumpMarginRight       = TGMetricPad;
/// Jump button bottom margin above composer (10 pt).
static const CGFloat TGMetricJumpMarginBottom      = TGMetricPadMedium;
/// Badge overlap top offset (-9 pt).
static const CGFloat TGMetricBadgeOffsetTop        = -9.0f;
/// Floating date plate top offset (8 pt).
static const CGFloat TGMetricFloatingDateTopOffset = TGMetricPad;
/// Context menu action horizontal offset (60 pt).
static const CGFloat TGMetricMenuActionOffset      = 60.0f;
/// Chat list context menu X coordinate (120 pt).
static const CGFloat TGMetricChatListMenuX         = 120.0f;
/// Chat cell title to date gap (6 pt).
static const CGFloat TGMetricChatCellDateGap       = TGMetricPadSmall;
/// Zero height gap for hidden table section header (0.001 pt).
static const CGFloat TGMetricSectionHeaderHidden = 0.001f;
/// Base point size for chat message font slider.
static const CGFloat TGFontMessageBaseSize      = 13.0f;
/// Font step for message size slider.
static const CGFloat TGFontMessageStep          = 2.0f;
/// Standard 1x playback speed.
static const CGFloat TGPlaybackSpeedNormal      = 1.0f;
/// 1.5x fast playback speed.
static const CGFloat TGPlaybackSpeedFast        = 1.5f;
/// 2x double playback speed.
static const CGFloat TGPlaybackSpeedDouble      = 2.0f;
/// Minimum pinch zoom scale.
static const CGFloat TGMetricZoomMin            = 1.0f;
/// Maximum pinch zoom scale.
static const CGFloat TGMetricZoomMax            = 4.0f;
/// Viewfinder square dimension ratio in QR scanner screen.
static const CGFloat TGMetricQRViewfinderRatio  = 0.66f;
/// Landscape media aspect ratio (0.75).
static const CGFloat TGMetricMediaRatioLandscape = 0.75f;

#pragma mark - gesture damping and rubberband tokens

/// Rubberband damping resistance when pulling beyond threshold (0.25).
static const CGFloat TGDampingRubberband          = 0.25f;
/// Voice lock upward tracking friction multiplier (0.40).
static const CGFloat TGDampingVoiceLock           = 0.40f;
/// Voice slide-to-cancel tracking multiplier (0.70).
static const CGFloat TGDampingVoiceCancel         = 0.70f;
/// Minimum scale of inline reply icon during pull (0.60).
static const CGFloat TGTransformScaleReplyMin     = 0.60f;
/// Growth range scale of inline reply icon during pull (0.40).
static const CGFloat TGTransformScaleReplyRange   = 0.40f;
/// Minimum alpha of voice slide cancel hint (0.10).
static const CGFloat TGAlphaVoiceCancelMin        = 0.10f;
/// Recording pulse breathing scale amplitude (0.08).
static const CGFloat TGAnimationPulseAmplitude    = 0.08f;
/// Media sticker / gift emoji inner inset ratio (0.08).
static const CGFloat TGMetricEmojiArtworkInsetRatio = 0.08f;
/// Media sticker / gift emoji size ratio (0.84).
static const CGFloat TGMetricEmojiArtworkSizeRatio  = 0.84f;
/// Emoji artwork text font size inset factor (3.5).
static const CGFloat TGMetricEmojiArtworkFontInsetRatio = 3.5f;
/// GIF picker cell height to width aspect ratio (0.80).
static const CGFloat TGMetricGIFCellAspect          = 0.80f;
/// Gift card art size ratio relative to inner width (0.55).
static const CGFloat TGMetricGiftArtRatio         = 0.55f;
/// Maximum gift card art side (150 pt).
static const CGFloat TGMetricGiftArtMaxSide       = 150.0f;
/// Video note drag cancel threshold velocity (900 pt/s).
static const CGFloat TGMetricViewerDismissVelocity = 900.0f;
/// Video note drag dismiss threshold distance (110 pt).
static const CGFloat TGMetricViewerDismissDistance = 110.0f;
/// Video note drag max fade divisor (420 pt).
static const CGFloat TGMetricViewerFadeDistance    = 420.0f;
/// Video note drag max fade ratio (0.66).
static const CGFloat TGMetricViewerMaxFadeRatio    = 0.66f;
/// Horizontal vs vertical velocity ratio to accept reply swipe (1.50).
static const CGFloat TGDampingReplySwipeSlope      = 1.50f;

#pragma mark - general numeric and scale tokens

/// Zero coordinate or offset.
static const CGFloat TGMetricZero                  = 0.0f;
/// Unit scale / 100% factor.
static const CGFloat TGMetricScaleFull             = 1.0f;
/// Small float comparison epsilon (0.10).
static const CGFloat TGMetricEpsilon               = 0.10f;
/// 100 percent multiplier / divisor.
static const CGFloat TGPercentFull                 = 100.0f;
/// High quality JPEG compression (85%).
static const CGFloat TGCompressionQualityHigh      = 0.85f;
/// Standard JPEG compression (90%).
static const CGFloat TGCompressionQualityStandard  = 0.90f;
/// Run gap spacing when starting a bubble sequence (4 pt).
static const CGFloat TGMetricBubbleRunGapStart     = TGMetricPadSmall;
/// Run gap spacing between bubbles inside a run (1 pt).
static const CGFloat TGMetricBubbleRunGapInner     = 1.0f;
/// The gap a bubble leaves above and below itself inside its own row, so a
/// row is its bubble plus twice this. The run gaps above are measured from
/// here, which is why they and this are one value and not three: a bubble
/// moved off this inset stops being gapped at all (see adjustmentForRow:).
static const CGFloat TGMetricBubbleRowInset        = 3.0f;
/// Voice lock finger margin from top bar (20 pt).
static const CGFloat TGMetricVoiceLockMargin       = 20.0f;
/// Playback rate threshold to switch to fast 1.5x (1.25).
static const CGFloat TGPlaybackSpeedThresholdFast  = 1.25f;
/// Playback rate threshold to switch to double 2x (1.75).
static const CGFloat TGPlaybackSpeedThresholdDouble = 1.75f;
/// Stopped audio rate (0.0).
static const CGFloat TGPlaybackSpeedStopped        = 0.0f;
/// Double tap zoom target scale (2.5x).
static const CGFloat TGMetricZoomDoubleTap         = 2.5f;
/// Message font size preview slider base cap (14 pt).
static const CGFloat TGFontMessageBaseCap          = 14.0f;
/// Font slider swipe sensitivity delta threshold (14 pt).
static const CGFloat TGMetricFontSizeDeltaThreshold = 14.0f;

// vim:ft=objc

/// Restored: these are used from headers (TGMessageLayout.h aliases them
/// as the chat's own k-names, TGIconsInternal.h for the stroke), and a scan
/// that only counted .m files called them dead.
static const CGFloat TGMetricBubbleMaxW         = 246.0f;
static const CGFloat TGMetricBubbleTailHeight   = 13.0f;
static const CGFloat TGMetricBubbleTailWidth    = 6.0f;
static const CGFloat TGMetricChatAvatar     = 60.0f;
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
/// A track's bubble is as fixed in width as a voice note's: the cover, the
/// gap, and room for a title that gets truncated rather than growing it.
static const CGFloat TGMetricTrackContent       = 200.0f;

#pragma mark - iOS 6 Reimagined player and chrome metrics

/// Fullscreen modal player album art square side.
static const CGFloat TGMetricPlayerModalArtSide    = 190.0f;
/// Fullscreen modal player main play/pause button side.
static const CGFloat TGMetricPlayerModalButtonMain = 58.0f;
/// Fullscreen modal player secondary transport button side.
static const CGFloat TGMetricPlayerModalButtonSide = 44.0f;
/// Fullscreen modal player volume / scrubber touch height.
static const CGFloat TGMetricPlayerModalSliderH   = 28.0f;
/// Empty state vector illustration side.
static const CGFloat TGMetricEmptyIconSide         = 64.0f;
/// Pinned connection status banner height.
static const CGFloat TGMetricConnectionBannerH     = 28.0f;
/// Tactile segmented control height.
static const CGFloat TGMetricSegmentedHeight       = 30.0f;

#pragma mark - iOS 6 Reimagined UI Component metrics

/// Small tactile button height (28 pt).
static const CGFloat TGMetricButtonSmallH          = 28.0f;
/// Medium tactile button height (36 pt).
static const CGFloat TGMetricButtonMediumH         = 36.0f;
/// Large tactile action button height (44 pt).
static const CGFloat TGMetricButtonLargeH          = 44.0f;
/// iOS 6 tactile toggle switch width (51 pt).
static const CGFloat TGMetricSwitchW               = 51.0f;
/// iOS 6 tactile toggle switch height (31 pt).
static const CGFloat TGMetricSwitchH               = 31.0f;
/// iOS 6 tactile toggle knob diameter (27 pt).
static const CGFloat TGMetricSwitchThumbD          = 27.0f;
/// Tactile slider touch height (28 pt).
static const CGFloat TGMetricSliderH               = 28.0f;
/// Tactile slider thumb diameter (22 pt).
static const CGFloat TGMetricSliderThumbD          = 22.0f;
/// Tactile slider recessed track height (6 pt).
static const CGFloat TGMetricSliderTrackH          = 6.0f;
/// Tactile input field height (36 pt).
static const CGFloat TGMetricTextFieldH            = 36.0f;
/// Tactile pill badge height (18 pt).
static const CGFloat TGMetricBadgeH                = 18.0f;
/// iOS standard tab bar height (49 pt).
static const CGFloat TGMetricTabBarH               = 49.0f;

#ifdef __cplusplus
}
#endif
