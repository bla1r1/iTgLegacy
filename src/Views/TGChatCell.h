#import <UIKit/UIKit.h>
#import "TGStyle.h"

// Their iOS chat list: a 60pt picture and up to two lines of preview, so a
// row is read without opening it.
static const CGFloat kRowHeight = TGMetricChatRow;
static const CGFloat kAvatar    = TGMetricChatAvatar;

@interface TGChatCell : UITableViewCell

@property (nonatomic, strong) UIImageView *avatar;
@property (nonatomic, strong) UILabel *titleLabel;
@property (nonatomic, strong) UILabel *previewLabel;
@property (nonatomic, strong) UILabel *dateLabel;
@property (nonatomic, strong) UILabel *badge;
@property (nonatomic, strong) UIView *onlineDot;
@property (nonatomic, strong) UIImageView *tick;   // your own last message
@property (nonatomic, strong) UIImageView *pin;   // pinned to the top
@property (nonatomic, strong) UIImageView *muteIcon;   // beside the title of a muted chat
@property (nonatomic, strong) UIView *separator;   // starts under the text, not the picture
@property (nonatomic, strong) UILabel *editCheck;    // the blue tick in chat-list Edit

/// The preview, with whoever wrote it ("Ivan:", "You:") in the title colour
/// ahead of the text, the way their list sets the speaker apart.
- (void)setPreview:(NSString *)text author:(NSString *)author;

- (void)applyTheme;

/// The table's own row actions start at iOS 8. Before that the list swipes a
/// row itself: three buttons are built the first time the row is pulled open
/// and dropped again when it closes, so ordinary scrolling never pays for them.
- (void)revealSwipeActionsWithTitles:(NSArray *)titles
                             colours:(NSArray *)colours
                              target:(id)target
                              action:(SEL)action;
- (void)setSwipeActionsOffset:(CGFloat)offset;
- (void)openSwipeActionsAnimated:(BOOL)animated;
- (void)closeSwipeActionsAnimated:(BOOL)animated;
@property (nonatomic, readonly) BOOL swipeActionsOpen;
@property (nonatomic, readonly) CGFloat swipeActionsWidth;

@end
