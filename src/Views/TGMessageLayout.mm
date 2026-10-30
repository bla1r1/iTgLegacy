//
// TGMessageLayout.mm - Geometry, sizing and C++ LRU layout cache for chat bubbles.
//
#import "TGMessageLayout.h"
#import "TGStyle.h"
#import "TGLruCache.hpp"

#ifndef typeof
#define typeof __typeof__
#endif

@interface TGMessageLayoutCache () {
	TGLruCache<int64_t, TGMessageLayout *> _lru;
}
@end

@implementation TGMessageLayoutCache

- (instancetype)init {
	return [self initWithCapacity:500];
}

- (instancetype)initWithCapacity:(NSUInteger)capacity {
	if ((self = [super init])) {
		_lru.set_capacity(capacity ? capacity : 500);
	}
	return self;
}

- (TGMessageLayout *)layoutForMessageId:(int64_t)msgId {
	TGMessageLayout *hit = nil;
	if (_lru.get(msgId, hit)) {
		return hit;
	}
	return nil;
}

- (void)setLayout:(TGMessageLayout *)layout forMessageId:(int64_t)msgId {
	if (layout) {
		_lru.put(msgId, layout);
	} else {
		_lru.remove(msgId);
	}
}

- (void)removeLayoutForMessageId:(int64_t)msgId {
	_lru.remove(msgId);
}

- (void)clear {
	_lru.clear();
}

- (NSUInteger)count {
	return _lru.size();
}

- (TGMessageLayout *)objectForKeyedSubscript:(id)key {
	if ([key respondsToSelector:@selector(longLongValue)]) {
		return [self layoutForMessageId:[key longLongValue]];
	}
	return nil;
}

- (void)setObject:(TGMessageLayout *)obj forKeyedSubscript:(id)key {
	if ([key respondsToSelector:@selector(longLongValue)]) {
		[self setLayout:obj forMessageId:[key longLongValue]];
	}
}

- (void)removeAllObjects {
	_lru.clear();
}

- (void)removeObjectForKey:(id)key {
	if ([key respondsToSelector:@selector(longLongValue)]) {
		_lru.remove([key longLongValue]);
	}
}

@end

// ─── Key hashing ──────────────────────────────────────────────────────────────

static inline uint64_t TGFNV1a64(NSString *str) {
	if (!str.length) return 0;
	uint64_t hash = 14695981039346656037ULL;
	NSUInteger len = str.length;
	const UniChar *direct = CFStringGetCharactersPtr((__bridge CFStringRef)str);
	UniChar buf[128];
	NSUInteger offset = 0;
	while (offset < len) {
		const UniChar *p;
		NSUInteger count;
		if (direct) {
			p = direct + offset;
			count = len - offset;
		} else {
			count = MIN((NSUInteger)128, len - offset);
			[str getCharacters:buf range:NSMakeRange(offset, count)];
			p = buf;
		}
		for (NSUInteger i = 0; i < count; i++) {
			hash ^= (uint64_t)(p[i]);
			hash *= 1099511628211ULL;
		}
		offset += count;
	}
	return hash;
}

struct EmojiKey {
	uint64_t textHash;
	uint32_t fontSizeInt;

	bool operator==(const EmojiKey &o) const {
		return textHash == o.textHash && fontSizeInt == o.fontSizeInt;
	}
};

namespace std {
	template <>
	struct hash<EmojiKey> {
		size_t operator()(const EmojiKey &k) const {
			return (size_t)(k.textHash ^ ((uint64_t)k.fontSizeInt << 32));
		}
	};
}

struct TextSizeKey {
	uint64_t textHash;
	uint16_t widthInt;
	uint16_t fontSizeInt;
	uint16_t entitiesCount;

	bool operator==(const TextSizeKey &o) const {
		return textHash == o.textHash &&
			   widthInt == o.widthInt &&
			   fontSizeInt == o.fontSizeInt &&
			   entitiesCount == o.entitiesCount;
	}
};

namespace std {
	template <>
	struct hash<TextSizeKey> {
		size_t operator()(const TextSizeKey &k) const {
			return (size_t)(k.textHash ^ ((uint64_t)k.widthInt << 48) ^ ((uint64_t)k.fontSizeInt << 32) ^ k.entitiesCount);
		}
	};
}

static TGLruCache<EmojiKey, id> sEmojiCache(500);
static TGLruCache<TextSizeKey, CGSize> sTextSizeCache(1000);

// ─── Font & Emoji helpers ─────────────────────────────────────────────────────

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

static inline BOOL TGTextContainsEmoji(NSString *text) {
	NSUInteger len = text.length;
	if (len == 0) return NO;

	const UniChar *direct = CFStringGetCharactersPtr((__bridge CFStringRef)text);
	UniChar stackBuf[256];
	if (!direct) {
		for (NSUInteger offset = 0; offset < len; offset += 256) {
			NSUInteger chunk = MIN((NSUInteger)256, len - offset);
			[text getCharacters:stackBuf range:NSMakeRange(offset, chunk)];
			for (NSUInteger i = 0; i < chunk; i++) {
				UniChar c = stackBuf[i];
				if (c >= 0xD800 && c <= 0xDBFF && (i + 1 < chunk)) {
					UniChar low = stackBuf[i + 1];
					if (low >= 0xDC00 && low <= 0xDFFF) {
						UTF32Char cp = (((c - 0xD800) << 10) | (low - 0xDC00)) + 0x10000;
						if (TGIsEmojiScalar(cp)) return YES;
						i++;
						continue;
					}
				}
				if (TGIsEmojiScalar(c)) return YES;
			}
		}
		return NO;
	}

	for (NSUInteger i = 0; i < len; i++) {
		UniChar c = direct[i];
		if (c >= 0xD800 && c <= 0xDBFF && (i + 1 < len)) {
			UniChar low = direct[i + 1];
			if (low >= 0xDC00 && low <= 0xDFFF) {
				UTF32Char cp = (((c - 0xD800) << 10) | (low - 0xDC00)) + 0x10000;
				if (TGIsEmojiScalar(cp)) return YES;
				i++;
				continue;
			}
		}
		if (TGIsEmojiScalar(c)) return YES;
	}
	return NO;
}

NSAttributedString *TGEmojiAttributedText(NSString *text, UIFont *base) {
	if (!text.length)
		return nil;

	EmojiKey key = { TGFNV1a64(text), (uint32_t)(base.pointSize * 10.0f) };
	id hit = nil;
	if (sEmojiCache.get(key, hit)) {
		return (hit == [NSNull null]) ? nil : (NSAttributedString *)hit;
	}

	if (!TGTextContainsEmoji(text)) {
		sEmojiCache.put(key, [NSNull null]);
		return nil;
	}

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

	sEmojiCache.put(key, styled ?: (id)[NSNull null]);
	return styled;
}

NSAttributedString *TGAttributedMessageText(NSString *text, NSArray *entities, UIFont *baseFont, UIColor *textColor) {
	if (!text.length)
		return nil;
	if (!baseFont)
		baseFont = TGFontBody();
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
	UIColor *linkColour = TGColourLink();

	for (NSDictionary *ent in entities) {
		if (![ent isKindOfClass:[NSDictionary class]])
			continue;
		NSInteger offset = [ent[@"offset"] integerValue];
		NSInteger length = [ent[@"length"] integerValue];
		if (offset < 0 || length <= 0 || (offset + length) > (NSInteger)str.length)
			continue;

		NSRange range = NSMakeRange(offset, length);
		id typeObj = ent[@"type"];
		NSString *type = nil;
		if ([typeObj isKindOfClass:[NSDictionary class]]) {
			type = typeObj[@"@type"];
		} else if ([typeObj isKindOfClass:[NSString class]]) {
			type = (NSString *)typeObj;
		}
		if (!type && [ent[@"@type"] isKindOfClass:[NSString class]]) {
			type = ent[@"@type"];
		}

		if ([type isEqualToString:@"textEntityTypeBold"] || [type isEqualToString:@"messageEntityBold"] || [type isEqualToString:@"bold"]) {
			[str addAttribute:NSFontAttributeName value:TGFontBoldAtSize(size) range:range];
		} else if ([type isEqualToString:@"textEntityTypeItalic"] || [type isEqualToString:@"messageEntityItalic"] || [type isEqualToString:@"italic"]) {
			[str addAttribute:NSFontAttributeName value:TGFontItalicAtSize(size) range:range];
		} else if ([type isEqualToString:@"textEntityTypeUnderline"] || [type isEqualToString:@"messageEntityUnderline"] || [type isEqualToString:@"underline"]) {
			[str addAttribute:NSUnderlineStyleAttributeName value:@(NSUnderlineStyleSingle) range:range];
		} else if ([type isEqualToString:@"textEntityTypeStrikethrough"] || [type isEqualToString:@"messageEntityStrikethrough"] || [type isEqualToString:@"strikethrough"]) {
			[str addAttribute:NSStrikethroughStyleAttributeName value:@(NSUnderlineStyleSingle) range:range];
		} else if ([type isEqualToString:@"textEntityTypeCode"] || [type isEqualToString:@"messageEntityCode"] ||
				   [type isEqualToString:@"textEntityTypePre"]  || [type isEqualToString:@"messageEntityPre"] ||
				   [type isEqualToString:@"textEntityTypePreCode"] || [type isEqualToString:@"code"]) {
			UIFont *mono = TGFontCodeAtSize(MAX(TGFontSizeMicro, size - TGMetricTextPadV));
			if (mono)
				[str addAttribute:NSFontAttributeName value:mono range:range];
			[str addAttribute:NSBackgroundColorAttributeName value:TGColourCodeBackground() range:range];
		} else if ([type isEqualToString:@"textEntityTypeTextUrl"] || [type isEqualToString:@"messageEntityTextUrl"] || [type isEqualToString:@"url"] || [type isEqualToString:@"textEntityTypeUrl"]) {
			NSString *urlStr = nil;
			if ([typeObj isKindOfClass:[NSDictionary class]]) {
				urlStr = typeObj[@"url"];
			}
			if (!urlStr.length) {
				urlStr = ent[@"url"];
			}
			if (urlStr.length) {
				[str addAttribute:NSForegroundColorAttributeName value:linkColour range:range];
				[str addAttribute:NSUnderlineStyleAttributeName value:@(NSUnderlineStyleSingle) range:range];
				[str addAttribute:@"TGLinkURL" value:urlStr range:range];
			}
		} else if ([type isEqualToString:@"textEntityTypeUrl"] || [type isEqualToString:@"messageEntityUrl"] || [type isEqualToString:@"url"]) {
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
			[str addAttribute:NSBackgroundColorAttributeName value:TGColourCodeBlockBackground() range:range];
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

	TextSizeKey key = {
		TGFNV1a64(text),
		(uint16_t)(width > 0 ? (uint16_t)width : 0),
		(uint16_t)(font ? (uint16_t)(font.pointSize * 10.0f) : 0),
		(uint16_t)entities.count
	};

	CGSize cachedSize;
	if (sTextSizeCache.get(key, cachedSize)) {
		return cachedSize;
	}

	CGSize size = CGSizeZero;
	NSAttributedString *rich = TGAttributedMessageText(text, entities, font, [UIColor blackColor]);

	if (width > 0) {
		if (rich) {
			CGRect rect = [rich boundingRectWithSize:CGSizeMake(width, TGMetricTextMeasureHeight)
											 options:NSStringDrawingUsesLineFragmentOrigin | NSStringDrawingUsesFontLeading
											 context:nil];
			size = CGSizeMake(ceilf(rect.size.width) + TGMetricTextPadH, ceilf(rect.size.height) + TGMetricTextPadV);
		} else {
			size = [text sizeWithFont:font
					constrainedToSize:CGSizeMake(width, TGMetricTextMeasureHeight)
						lineBreakMode:NSLineBreakByWordWrapping];
			size = CGSizeMake(ceilf(size.width) + TGMetricTextPadH, ceilf(size.height) + TGMetricTextPadV);
		}
	} else {
		if (rich) {
			size = [rich size];
			size = CGSizeMake(ceilf(size.width) + TGMetricTextPadH, ceilf(size.height) + TGMetricTextPadV);
		} else {
			size = [text sizeWithFont:font];
			size = CGSizeMake(ceilf(size.width) + TGMetricTextPadH, ceilf(size.height) + TGMetricTextPadV);
		}
	}

	sTextSizeCache.put(key, size);
	return size;
}

CGSize TGTextSize(NSString *text, UIFont *font, CGFloat width) {
	return TGTextSizeWithEntities(text, nil, font, width);
}

NSString *TGDescribeMessageContent(NSDictionary *m) {
	if (!m || ![m isKindOfClass:NSDictionary.class]) return @"...";
	NSString *text = m[@"text"];
	if (text.length) return text;

	NSString *kind = m[@"kind"] ?: @"";
	if ([kind isEqualToString:@"messageVideoNote"])
		return @"Video message";
	if ([kind isEqualToString:@"messageVoiceNote"])
		return @"Voice message";
	if ([kind isEqualToString:@"messageSticker"] || [kind isEqualToString:@"messageAnimatedEmoji"]) {
		NSString *emoji = m[@"extra"] ?: m[@"emoji"];
		return emoji.length ? [NSString stringWithFormat:@"Sticker %@", emoji] : @"Sticker";
	}
	if ([kind isEqualToString:@"messagePhoto"])
		return @"Photo";
	if ([kind isEqualToString:@"messageVideo"])
		return @"Video";
	if ([kind isEqualToString:@"messageAnimation"])
		return @"GIF";
	if ([kind isEqualToString:@"messageDocument"]) {
		NSString *docName = m[@"docName"];
		return docName.length ? docName : @"Document";
	}
	if ([kind isEqualToString:@"messageAudio"]) {
		NSString *title = m[@"audioTitle"];
		return title.length ? title : @"Audio";
	}
	if ([kind isEqualToString:@"messageLocation"] || [kind isEqualToString:@"messageLiveLocation"])
		return @"Location";
	if ([kind isEqualToString:@"messageContact"])
		return @"Contact";
	if ([kind isEqualToString:@"messagePoll"])
		return @"Poll";
	if ([kind isEqualToString:@"messageCall"])
		return @"Call";
	if ([kind isEqualToString:@"messageDice"])
		return @"Dice";
	if ([kind isEqualToString:@"messageGame"])
		return @"Game";
	if ([kind isEqualToString:@"messageStory"])
		return @"Story";

	if ([kind hasPrefix:@"message"]) {
		NSString *shortKind = [kind substringFromIndex:7];
		if (shortKind.length) {
			NSMutableString *spaced = [NSMutableString stringWithString:[shortKind substringToIndex:1]];
			for (NSUInteger i = 1; i < shortKind.length; i++) {
				unichar c = [shortKind characterAtIndex:i];
				if (c >= 'A' && c <= 'Z')
					[spaced appendFormat:@" %c", (char)(c - 'A' + 'a')];
				else
					[spaced appendFormat:@"%C", c];
			}
			return spaced;
		}
	}
	return @"...";
}

void TGVideoNoteLayoutBottomBar(CGRect bubbleFrame,
								CGFloat durWidth,
								CGFloat clockWidth,
								bool mine,
								bool unplayed,
								CGRect *outDurFrame,
								CGRect *outTimeFrame,
								CGRect *outTicksFrame,
								CGRect *outDotFrame) {
	CGFloat clockY = CGRectGetMaxY(bubbleFrame) + TGMetricPadSmall;

	// Duration on the left side under the circle
	if (outDurFrame) {
		*outDurFrame = CGRectMake(CGRectGetMinX(bubbleFrame) + TGMetricPadSmall,
								  clockY,
								  durWidth,
								  TGMetricStampHeight);
	}

	// Time group on the right side under the circle: clock + ticks + unplayed dot
	CGFloat ticksW = mine ? (TGMetricPadSmall + TGMetricTicksWidth) : 0.0f;
	CGFloat dotW = unplayed ? (TGMetricPadSmall + TGMetricUnreadDotSide) : 0.0f;
	CGFloat groupW = clockWidth + ticksW + dotW;
	CGFloat groupX = CGRectGetMaxX(bubbleFrame) - groupW - TGMetricPadSmall;

	if (outTimeFrame) {
		*outTimeFrame = CGRectMake(groupX, clockY, clockWidth, TGMetricStampHeight);
	}
	if (outTicksFrame) {
		*outTicksFrame = CGRectMake(groupX + clockWidth + TGMetricPadSmall,
									clockY + TGCenteredOrigin(TGMetricStampHeight, TGMetricTicksHeight),
									TGMetricTicksWidth,
									TGMetricTicksHeight);
	}
	if (outDotFrame) {
		*outDotFrame = CGRectMake(groupX + clockWidth + ticksW + TGMetricPadSmall,
								  clockY + TGCenteredOrigin(TGMetricStampHeight, TGMetricUnreadDotSide),
								  TGMetricUnreadDotSide,
								  TGMetricUnreadDotSide);
	}
}

@implementation TGMessageLayout
@end
