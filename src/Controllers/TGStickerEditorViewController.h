//
// TGStickerEditorViewController - one pack, and every part of it that can be
// changed: its title, its thumbnail, the stickers in it and their order,
// tags and mask. The same screen makes a new pack, because a pack that can
// be edited is one that can be created.
//
#import <UIKit/UIKit.h>

@interface TGStickerEditorViewController : UITableViewController

/// The pack being edited. `setName` is the short name TDLib changes a pack
/// by; `setId` is what reads its stickers. `stickerType` is "regular",
/// "mask" or "customEmoji".
@property (nonatomic, copy) NSString *setName;
@property (nonatomic, copy) NSString *setTitle;
@property (nonatomic, assign) int64_t setId;
@property (nonatomic, copy) NSString *stickerType;

/// YES for the empty screen that asks for a title and a name and creates
/// the pack, NO for one that was opened from My Packs.
@property (nonatomic, assign) BOOL creating;

@end
