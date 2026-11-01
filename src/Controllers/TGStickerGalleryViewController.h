//
// TGStickerGalleryViewController - a preview grid of stickers Telegram sent back.
//
// The sticker editor, the custom emoji shelves and the greeting shelf all
// read a flat sticker list from different requests. One screen draws any of
// them: a grid of the sticker images, with the emoji name and the file actions
// one tap away.
//
#import <UIKit/UIKit.h>

@interface TGStickerGalleryViewController : UIViewController

/// Each sticker is a dictionary with "fileId", "emoji", and optionally
/// "setId" and "customEmojiId".
@property (nonatomic, copy) NSArray *stickers;
/// What to say when the list is empty.
@property (nonatomic, copy) NSString *emptyText;

@end
