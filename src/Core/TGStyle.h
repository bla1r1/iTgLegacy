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
#import <UIKit/UIKit.h>

#pragma mark - type scale

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
/// 36. A sticker's emoji standing in for a thumbnail that has not arrived.
UIFont *TGFontEmojiLarge(void);

#pragma mark - computed sizes

/// For a size the screen does not choose: a glyph fitted to its box, a run of
/// message text at the size the user set. Never call these with a literal.
UIFont *TGFontAtSize(CGFloat size);
UIFont *TGFontBoldAtSize(CGFloat size);
UIFont *TGFontItalicAtSize(CGFloat size);
/// Medium weight at a computed size, with bold as the fallback where the face
/// is missing. Initials drawn into an avatar of any side.
UIFont *TGFontMediumAtSize(CGFloat size);

#pragma mark - colour that is not the theme's

/// The blue a link is drawn in inside message text. It lives here, not in the
/// palette, because the text layout is deliberately free of the theme: it is
/// compiled on its own in the tests and must not drag the theme in behind it.
UIColor *TGColourLink(void);

#pragma mark - metrics

/// One row of a list or a settings group.
static const CGFloat TGMetricRow        = 44.0f;
/// The picture on a list row - chats, contacts, search, the forward picker.
static const CGFloat TGMetricListAvatar = 40.0f;
/// Text from the side of the screen.
static const CGFloat TGMetricGutter     = 15.0f;
/// The gap around a card floating over a dimmed screen.
static const CGFloat TGMetricCardMargin = 8.0f;

// vim:ft=objc
