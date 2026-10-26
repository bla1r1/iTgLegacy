#import "TGStyle.h"

// The scale, and the only place in the app allowed to name a point size.
#define TGSizeHero     28.0f
#define TGSizeTitle    22.0f
#define TGSizeHeader   17.0f
#define TGSizeRow      16.0f
#define TGSizeBody     15.0f
#define TGSizeSubhead  14.0f
#define TGSizeCaption  13.0f
#define TGSizeMeta     12.0f
#define TGSizeMicro    11.0f
#define TGSizeGlyph    22.0f
#define TGSizeGlyphSm  18.0f
#define TGSizePlate    10.0f
#define TGSizeEmoji    28.0f
#define TGSizeEmojiSm  20.0f
#define TGSizeEmojiLg  36.0f

UIFont *TGFontHero(void)          { return [UIFont systemFontOfSize:TGSizeHero]; }
UIFont *TGFontTitle(void)         { return [UIFont boldSystemFontOfSize:TGSizeTitle]; }
UIFont *TGFontHeader(void)        { return [UIFont boldSystemFontOfSize:TGSizeHeader]; }
UIFont *TGFontInput(void)         { return [UIFont systemFontOfSize:TGSizeHeader]; }
UIFont *TGFontRow(void)           { return [UIFont systemFontOfSize:TGSizeRow]; }
UIFont *TGFontRowStrong(void)     { return [UIFont boldSystemFontOfSize:TGSizeRow]; }
UIFont *TGFontBody(void)          { return [UIFont systemFontOfSize:TGSizeBody]; }
UIFont *TGFontBodyStrong(void)    { return [UIFont boldSystemFontOfSize:TGSizeBody]; }
UIFont *TGFontSubhead(void)       { return [UIFont systemFontOfSize:TGSizeSubhead]; }
UIFont *TGFontSubheadStrong(void) { return [UIFont boldSystemFontOfSize:TGSizeSubhead]; }
UIFont *TGFontCaption(void)       { return [UIFont systemFontOfSize:TGSizeCaption]; }
UIFont *TGFontCaptionStrong(void) { return [UIFont boldSystemFontOfSize:TGSizeCaption]; }
UIFont *TGFontMeta(void)          { return [UIFont systemFontOfSize:TGSizeMeta]; }
UIFont *TGFontMetaStrong(void)    { return [UIFont boldSystemFontOfSize:TGSizeMeta]; }
UIFont *TGFontMicro(void)         { return [UIFont systemFontOfSize:TGSizeMicro]; }
UIFont *TGFontMicroStrong(void)   { return [UIFont boldSystemFontOfSize:TGSizeMicro]; }

UIFont *TGFontListTitle(void)     { return TGFontMediumAtSize(TGSizeRow); }

UIFont *TGFontGlyph(void)         { return [UIFont systemFontOfSize:TGSizeGlyph]; }
UIFont *TGFontGlyphSmall(void)    { return [UIFont systemFontOfSize:TGSizeGlyphSm]; }
UIFont *TGFontPlate(void)         { return [UIFont boldSystemFontOfSize:TGSizePlate]; }
UIFont *TGFontEmoji(void)         { return [UIFont systemFontOfSize:TGSizeEmoji]; }
UIFont *TGFontEmojiSmall(void)    { return [UIFont systemFontOfSize:TGSizeEmojiSm]; }
UIFont *TGFontEmojiMeta(void)     {
	return [UIFont fontWithName:@"OpenMojiColor" size:TGSizeMeta]
		?: [UIFont fontWithName:@"OpenMoji" size:TGSizeMeta]
		?: [UIFont systemFontOfSize:TGSizeMeta];
}
UIFont *TGFontEmojiLarge(void)    { return [UIFont systemFontOfSize:TGSizeEmojiLg]; }

UIColor *TGColourLink(void) {
	return [UIColor colorWithRed:0.18f green:0.54f blue:0.92f alpha:1.0f];
}

UIColor *TGColourCodeBackground(void) {
	return [UIColor colorWithWhite:0.5f alpha:0.15f];
}

UIColor *TGColourCodeBlockBackground(void) {
	return [UIColor colorWithWhite:0.5f alpha:0.25f];
}

UIFont *TGFontAtSize(CGFloat size)       { return [UIFont systemFontOfSize:size]; }
UIFont *TGFontBoldAtSize(CGFloat size)   { return [UIFont boldSystemFontOfSize:size]; }
UIFont *TGFontItalicAtSize(CGFloat size) { return [UIFont italicSystemFontOfSize:size]; }

UIFont *TGFontCodeAtSize(CGFloat size) {
	return [UIFont fontWithName:@"Courier" size:size]
		?: [UIFont fontWithName:@"CourierNewPSMT" size:size]
		?: [UIFont systemFontOfSize:size];
}

UIFont *TGFontMediumAtSize(CGFloat size) {
	// Medium is not a system weight on this OS; ask for the face by name and
	// fall back to bold where it is missing.
	return [UIFont fontWithName:@"HelveticaNeue-Medium" size:size]
		   ?: [UIFont boldSystemFontOfSize:size];
}

// vim:ft=objc
