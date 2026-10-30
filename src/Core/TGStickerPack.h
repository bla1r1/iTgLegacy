//
// TGStickerPack.h - a sticker list held as one flat buffer.
//
// A pack of a hundred stickers used to be a hundred NSDictionaries, each
// boxing six values - two file ids, a flag, two dimensions and an emoji -
// into separate heap objects: around 500 bytes and seven allocations per
// sticker, 50 KB and 700 allocations for one pack, and the panel holds
// several at once. On a 256 MB phone that is both the memory and the
// fragmentation.
//
// This holds the same stickers as a contiguous std::vector of a 48-byte POD
// and is itself an NSArray, so every caller - `for (NSDictionary *s in pack)`,
// `pack.count`, `pack.firstObject`, `pack[i]` - is unchanged. A dictionary is
// built only for an entry somebody actually reads, which in a grid means the
// cells on screen.
//
#import <Foundation/Foundation.h>

@interface TGStickerPack : NSArray

/// Flattens TDLib `sticker` objects. Anything without a file is skipped.
+ (instancetype)packWithTDLibStickers:(NSArray *)stickers;

/// Bytes the flat buffer occupies - what the saving is measured in.
@property (nonatomic, readonly) NSUInteger byteSize;

@end
