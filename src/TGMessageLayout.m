//
// TGMessageLayout.m - Geometry, sizing and layout cache for chat bubbles.
//
#import "TGMessageLayout.h"

UIFont *TGEmojiFontOfSize(CGFloat size) {
	static BOOL logged = NO;
	UIFont *font = [UIFont fontWithName:@"OpenMojiColor" size:size];
	if (!font) font = [UIFont fontWithName:@"OpenMoji Color" size:size];
	if (!font) font = [UIFont fontWithName:@"OpenMoji" size:size];
	if (!logged){
		logged = YES;
		NSLog(@"emoji font: %@", font ? font.fontName
				: @"NOT REGISTERED - check UIAppFonts in Info.plist");
	}
	return font;
}

BOOL TGIsEmojiScalar(UTF32Char c) {
	return (c >= 0x1F000 && c <= 0x1FAFF) ||   // pictographs, faces, flags
		   (c >= 0x2600  && c <= 0x27BF)  ||   // misc symbols and dingbats
		   (c >= 0x2B00  && c <= 0x2BFF);      // arrows and stars
}

NSAttributedString *TGEmojiAttributedText(NSString *text, UIFont *base) {
	if (!text.length)
		return nil;

	static NSMutableDictionary *cache = nil;
	if (!cache)
		cache = [NSMutableDictionary dictionary];
	NSString *key = [NSString stringWithFormat:@"%.0f|%@", base.pointSize, text];
	id hit = cache[key];
	if (hit)
		return (hit == [NSNull null]) ? nil : hit;

	UIFont *emojiFont = TGEmojiFontOfSize(base.pointSize);
	__block NSMutableAttributedString *styled = nil;
	if (emojiFont){
		[text enumerateSubstringsInRange:NSMakeRange(0, text.length)
								 options:NSStringEnumerationByComposedCharacterSequences
							  usingBlock:^(NSString *piece, NSRange range,
										   NSRange enclosing, BOOL *stop){
			UTF32Char first = [piece characterAtIndex:0];
			if (piece.length >= 2 && CFStringIsSurrogateHighCharacter(first))
				first = (UTF32Char)CFStringGetLongCharacterForSurrogatePair(
						first, [piece characterAtIndex:1]);
			if (!TGIsEmojiScalar(first))
				return;
			if (!styled)
				styled = [[NSMutableAttributedString alloc] initWithString:text
						attributes:@{NSFontAttributeName : base}];
			[styled addAttribute:NSFontAttributeName value:emojiFont range:range];
		}];
	}

	if (cache.count > 300)
		[cache removeAllObjects];
	cache[key] = styled ?: (id)[NSNull null];
	return styled;
}

void TGSetBodyText(UILabel *label, NSString *text, UIColor *colour) {
	NSAttributedString *rich = TGEmojiAttributedText(text, label.font);
	if (!rich){
		label.textColor = colour;
		label.text = text;
		return;
	}
	NSMutableAttributedString *coloured = [rich mutableCopy];
	[coloured addAttribute:NSForegroundColorAttributeName value:colour
					 range:NSMakeRange(0, coloured.length)];
	label.attributedText = coloured;
}

CGSize TGTextSize(NSString *text, UIFont *font, CGFloat width) {
	if (!text.length)
		return CGSizeZero;

	static NSMutableDictionary *cache = nil;
	if (!cache)
		cache = [NSMutableDictionary dictionary];

	NSString *key = [NSString stringWithFormat:@"%.0f|%.0f|%@", width, font.pointSize, text];
	NSValue *hit = cache[key];
	if (hit)
		return [hit CGSizeValue];

	CGSize size = CGSizeZero;
	NSAttributedString *rich = TGEmojiAttributedText(text, font);

	if (width > 0) {
		if (rich) {
			CGRect rect = [rich boundingRectWithSize:CGSizeMake(width, 10000)
											 options:NSStringDrawingUsesLineFragmentOrigin | NSStringDrawingUsesFontLeading
											 context:nil];
			size = CGSizeMake(ceilf(rect.size.width), ceilf(rect.size.height));
		} else if ([text respondsToSelector:@selector(boundingRectWithSize:options:attributes:context:)]) {
			CGRect rect = [text boundingRectWithSize:CGSizeMake(width, 10000)
											 options:NSStringDrawingUsesLineFragmentOrigin | NSStringDrawingUsesFontLeading
										  attributes:@{ NSFontAttributeName : font }
											 context:nil];
			size = CGSizeMake(ceilf(rect.size.width), ceilf(rect.size.height));
		} else {
			size = [text sizeWithFont:font
					constrainedToSize:CGSizeMake(width, 10000)
						lineBreakMode:NSLineBreakByWordWrapping];
			size = CGSizeMake(ceilf(size.width), ceilf(size.height));
		}
	} else {
		if (rich) {
			size = [rich size];
			size = CGSizeMake(ceilf(size.width), ceilf(size.height));
		} else if ([text respondsToSelector:@selector(sizeWithAttributes:)]) {
			size = [text sizeWithAttributes:@{ NSFontAttributeName : font }];
			size = CGSizeMake(ceilf(size.width), ceilf(size.height));
		} else {
			size = [text sizeWithFont:font];
			size = CGSizeMake(ceilf(size.width), ceilf(size.height));
		}
	}

	if (cache.count > 1000)
		[cache removeAllObjects];
	cache[key] = [NSValue valueWithCGSize:size];
	return size;
}

@implementation TGMessageLayout
@end
