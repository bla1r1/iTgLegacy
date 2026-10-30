//
// TGStickerPack.mm - see TGStickerPack.h.
//
#import "TGStickerPack.h"
#import "TGClientInternal.h"

#include <vector>
#include <cstring>

namespace {

/// 48 bytes, no pointers, no retain traffic. The emoji is the UTF-8 the
/// sticker carries; Telegram's are one or two codepoints, so 32 bytes is
/// room to spare and anything longer is simply cut (it is a label, not a
/// key).
struct TGStickerItem {
	int32_t fileId;
	int32_t thumbId;
	int16_t width;
	int16_t height;
	uint8_t isAnimated;
	char    emoji[32];
};

}  // namespace

@interface TGStickerPack () {
	std::vector<TGStickerItem> _items;
}
@end

@implementation TGStickerPack

+ (instancetype)packWithTDLibStickers:(NSArray *)stickers {
	TGStickerPack *pack = [[TGStickerPack alloc] init];
	if (![stickers isKindOfClass:NSArray.class])
		return pack;

	pack->_items.reserve(stickers.count);
	for (NSDictionary *sticker in stickers){
		if (![sticker isKindOfClass:NSDictionary.class])
			continue;
		// One shared reading of TDLib's shape, so the flat path and the
		// single-sticker path cannot drift apart.
		NSDictionary *info = TGStickerInfo(sticker);
		if (!info)
			continue;

		TGStickerItem item;
		std::memset(&item, 0, sizeof(item));
		item.fileId     = (int32_t)[info[@"fileId"] intValue];
		item.thumbId    = (int32_t)[info[@"thumbId"] intValue];
		item.width      = (int16_t)[info[@"width"] intValue];
		item.height     = (int16_t)[info[@"height"] intValue];
		item.isAnimated = [info[@"isAnimated"] boolValue] ? 1 : 0;

		NSString *emoji = info[@"emoji"];
		const char *utf8 = emoji.UTF8String;
		if (utf8){
			std::strncpy(item.emoji, utf8, sizeof(item.emoji) - 1);
			item.emoji[sizeof(item.emoji) - 1] = '\0';
		}
		pack->_items.push_back(item);
	}
	return pack;
}

#pragma mark - NSArray

- (NSUInteger)count {
	return _items.size();
}

- (id)objectAtIndex:(NSUInteger)index {
	if (index >= _items.size())
		[NSException raise:NSRangeException
					format:@"index %lu beyond sticker pack of %lu",
						   (unsigned long)index, (unsigned long)_items.size()];
	const TGStickerItem &item = _items[index];
	return @{
		@"fileId"     : @(item.fileId),
		@"emoji"      : [NSString stringWithUTF8String:item.emoji] ?: @"",
		@"isAnimated" : @(item.isAnimated != 0),
		@"thumbId"    : @(item.thumbId),
		@"width"      : @(item.width),
		@"height"     : @(item.height),
	};
}

- (NSUInteger)byteSize {
	return _items.size() * sizeof(TGStickerItem);
}

@end
