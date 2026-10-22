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

NSAttributedString *TGAttributedMessageText(NSString *text, NSArray *entities, UIFont *baseFont, UIColor *textColor) {
	if (!text.length)
		return nil;
	if (!baseFont)
		baseFont = [UIFont systemFontOfSize:15];
	if (!textColor)
		textColor = [UIColor blackColor];

	// 1. Emoji font substitution on base text
	NSMutableAttributedString *str = nil;
	NSAttributedString *emojiStr = TGEmojiAttributedText(text, baseFont);
	if (emojiStr) {
		str = [emojiStr mutableCopy];
	} else {
		str = [[NSMutableAttributedString alloc] initWithString:text attributes:@{
			NSFontAttributeName : baseFont,
			NSForegroundColorAttributeName : textColor
		}];
	}
	[str addAttribute:NSForegroundColorAttributeName value:textColor range:NSMakeRange(0, str.length)];

	if (!entities.count)
		return str;

	CGFloat size = baseFont.pointSize;
	UIColor *linkColour = [UIColor colorWithRed:0.18f green:0.54f blue:0.92f alpha:1.0f];

	for (NSDictionary *ent in entities) {
		if (![ent isKindOfClass:[NSDictionary class]])
			continue;
		NSInteger offset = [ent[@"offset"] integerValue];
		NSInteger length = [ent[@"length"] integerValue];
		if (offset < 0 || length <= 0 || (offset + length) > (NSInteger)str.length)
			continue;

		NSRange range = NSMakeRange(offset, length);
		NSString *type = ent[@"type"][@"@type"] ?: ent[@"@type"];

		if ([type isEqualToString:@"textEntityTypeBold"] || [type isEqualToString:@"messageEntityBold"]) {
			[str addAttribute:NSFontAttributeName value:[UIFont boldSystemFontOfSize:size] range:range];
		} else if ([type isEqualToString:@"textEntityTypeItalic"] || [type isEqualToString:@"messageEntityItalic"]) {
			[str addAttribute:NSFontAttributeName value:[UIFont italicSystemFontOfSize:size] range:range];
		} else if ([type isEqualToString:@"textEntityTypeUnderline"] || [type isEqualToString:@"messageEntityUnderline"]) {
			[str addAttribute:NSUnderlineStyleAttributeName value:@(NSUnderlineStyleSingle) range:range];
		} else if ([type isEqualToString:@"textEntityTypeStrikethrough"] || [type isEqualToString:@"messageEntityStrikethrough"]) {
			[str addAttribute:NSStrikethroughStyleAttributeName value:@(NSUnderlineStyleSingle) range:range];
		} else if ([type isEqualToString:@"textEntityTypeCode"] || [type isEqualToString:@"messageEntityCode"] ||
				   [type isEqualToString:@"textEntityTypePre"]  || [type isEqualToString:@"messageEntityPre"] ||
				   [type isEqualToString:@"textEntityTypePreCode"]) {
			UIFont *mono = [UIFont fontWithName:@"Courier" size:MAX(11.0f, size - 1.0f)] ?:
						   [UIFont fontWithName:@"CourierNewPSMT" size:MAX(11.0f, size - 1.0f)];
			if (mono)
				[str addAttribute:NSFontAttributeName value:mono range:range];
			[str addAttribute:NSBackgroundColorAttributeName value:[UIColor colorWithWhite:0.5f alpha:0.15f] range:range];
		} else if ([type isEqualToString:@"textEntityTypeTextUrl"] || [type isEqualToString:@"messageEntityTextUrl"]) {
			NSString *urlStr = ent[@"type"][@"url"] ?: ent[@"url"];
			if (urlStr.length) {
				[str addAttribute:NSForegroundColorAttributeName value:linkColour range:range];
				[str addAttribute:NSUnderlineStyleAttributeName value:@(NSUnderlineStyleSingle) range:range];
				[str addAttribute:@"TGLinkURL" value:urlStr range:range];
			}
		} else if ([type isEqualToString:@"textEntityTypeUrl"] || [type isEqualToString:@"messageEntityUrl"]) {
			NSString *urlStr = [text substringWithRange:range];
			[str addAttribute:NSForegroundColorAttributeName value:linkColour range:range];
			[str addAttribute:NSUnderlineStyleAttributeName value:@(NSUnderlineStyleSingle) range:range];
			[str addAttribute:@"TGLinkURL" value:urlStr range:range];
		} else if ([type isEqualToString:@"textEntityTypeEmailAddress"] || [type isEqualToString:@"textEntityTypePhoneNumber"]) {
			NSString *link = [text substringWithRange:range];
			[str addAttribute:NSForegroundColorAttributeName value:linkColour range:range];
			[str addAttribute:@"TGLinkURL" value:link range:range];
		} else if ([type isEqualToString:@"textEntityTypeMention"] || [type isEqualToString:@"textEntityTypeHashtag"] ||
				   [type isEqualToString:@"textEntityTypeBotCommand"]) {
			[str addAttribute:NSForegroundColorAttributeName value:linkColour range:range];
		} else if ([type isEqualToString:@"textEntityTypeSpoiler"] || [type isEqualToString:@"messageEntitySpoiler"]) {
			[str addAttribute:NSBackgroundColorAttributeName value:[UIColor colorWithWhite:0.5f alpha:0.25f] range:range];
		}
	}

	return str;
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

CGSize TGTextSizeWithEntities(NSString *text, NSArray *entities, UIFont *font, CGFloat width) {
	if (!text.length)
		return CGSizeZero;

	static NSMutableDictionary *cache = nil;
	if (!cache)
		cache = [NSMutableDictionary dictionary];

	NSString *key = [NSString stringWithFormat:@"%.0f|%.0f|%lu|%@", width, font.pointSize, (unsigned long)entities.count, text];
	NSValue *hit = cache[key];
	if (hit)
		return [hit CGSizeValue];

	CGSize size = CGSizeZero;
	NSAttributedString *rich = TGAttributedMessageText(text, entities, font, [UIColor blackColor]);

	if (width > 0) {
		if (rich) {
			CGRect rect = [rich boundingRectWithSize:CGSizeMake(width, 10000)
											 options:NSStringDrawingUsesLineFragmentOrigin | NSStringDrawingUsesFontLeading
											 context:nil];
			size = CGSizeMake(ceilf(rect.size.width) + 2.0f, ceilf(rect.size.height) + 1.0f);
		} else {
			size = [text sizeWithFont:font
					constrainedToSize:CGSizeMake(width, 10000)
						lineBreakMode:NSLineBreakByWordWrapping];
			size = CGSizeMake(ceilf(size.width) + 2.0f, ceilf(size.height) + 1.0f);
		}
	} else {
		if (rich) {
			size = [rich size];
			size = CGSizeMake(ceilf(size.width) + 2.0f, ceilf(size.height) + 1.0f);
		} else {
			size = [text sizeWithFont:font];
			size = CGSizeMake(ceilf(size.width) + 2.0f, ceilf(size.height) + 1.0f);
		}
	}

	if (cache.count > 1000)
		[cache removeAllObjects];
	cache[key] = [NSValue valueWithCGSize:size];
	return size;
}

CGSize TGTextSize(NSString *text, UIFont *font, CGFloat width) {
	return TGTextSizeWithEntities(text, nil, font, width);
}

@implementation TGMessageLayout
@end
