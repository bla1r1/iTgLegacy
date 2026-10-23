//
// TGEmojiPanel - the panel that takes the keyboard's place: emoji by
// category, stickers by set, GIFs saved and searched. Tabs along the bottom
// the way Telegram lays it out.
//
#import <UIKit/UIKit.h>

@class TGEmojiPanel;

@protocol TGEmojiPanelDelegate <NSObject>
- (void)emojiPanel:(TGEmojiPanel *)panel didPickEmoji:(NSString *)emoji;
- (void)emojiPanelDidBackspace:(TGEmojiPanel *)panel;
/// A sticker in the shape TGClient's sticker calls give ("fileId", ...).
- (void)emojiPanel:(TGEmojiPanel *)panel didPickSticker:(NSDictionary *)sticker;
/// A GIF in the shape TGClient's animation calls give.
- (void)emojiPanel:(TGEmojiPanel *)panel didPickAnimation:(NSDictionary *)animation;
@end

typedef NS_ENUM(NSInteger, TGEmojiPanelTab) {
	TGEmojiPanelTabEmoji = 0,
	TGEmojiPanelTabStickers,
	TGEmojiPanelTabGIFs
};

@interface TGEmojiPanel : UIView

@property (nonatomic, weak) id<TGEmojiPanelDelegate> delegate;
/// The chat a GIF search runs in; the @gif bot answers per chat.
@property (nonatomic, assign) int64_t chatId;
@property (nonatomic, readonly) TGEmojiPanelTab tab;

/// The height of the keyboard it stands in for.
+ (CGFloat)preferredHeight;

- (void)selectTab:(TGEmojiPanelTab)tab;
- (void)applyTheme;

@end
