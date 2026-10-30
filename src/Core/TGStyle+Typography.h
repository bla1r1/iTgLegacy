//
// TGStyle+Typography.h
// Type scale, line heights and glyph font roles.
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

/// 16, medium weight. The chat list's own title face.
UIFont *TGFontListTitle(void);

#pragma mark - glyphs and emoji

UIFont *TGFontGlyph(void);
UIFont *TGFontGlyphSmall(void);
UIFont *TGFontPlate(void);
UIFont *TGFontSwitchTag(void);
UIFont *TGFontEmoji(void);
UIFont *TGFontEmojiSmall(void);
UIFont *TGFontEmojiMeta(void);
UIFont *TGFontEmojiLarge(void);

#pragma mark - computed sizes

UIFont *TGFontAtSize(CGFloat size);
UIFont *TGFontBoldAtSize(CGFloat size);
UIFont *TGFontItalicAtSize(CGFloat size);
UIFont *TGFontCodeAtSize(CGFloat size);
UIFont *TGFontMediumAtSize(CGFloat size);

#pragma mark - the line scale

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

#ifdef __cplusplus
}
#endif
