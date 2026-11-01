//
// TGStickerGalleryViewController - a list of stickers Telegram sent back.
//
// The sticker editor, the custom emoji shelves and the greeting shelf all
// read a flat sticker list from different requests. One screen draws any of
// them: emoji, file id, the set it belongs to and, for a custom emoji pack,
// the custom emoji id that is the only way to name it.
//
#import <UIKit/UIKit.h>

@interface TGStickerGalleryViewController : UITableViewController

/// Each sticker is a dictionary with "fileId", "emoji", and optionally
/// "setId" and "customEmojiId".
@property (nonatomic, copy) NSArray *stickers;
/// What to say when the list is empty.
@property (nonatomic, copy) NSString *emptyText;

@end
