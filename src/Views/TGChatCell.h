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
@property (nonatomic, strong) UILabel *mentionBadge;
@property (nonatomic, strong) UIView *onlineDot;
@property (nonatomic, strong) UIImageView *tick;   // your own last message
@property (nonatomic, strong) UIImageView *pin;   // pinned to the top
@property (nonatomic, strong) UIImageView *muteIcon;   // beside the title of a muted chat
@property (nonatomic, strong) UIView *separator;   // starts under the text, not the picture
@property (nonatomic, strong) UILabel *editCheck;    // the blue tick in chat-list Edit

/// The preview, with whoever wrote it ("Ivan:", "You:") in the title colour
/// ahead of the text, the way their list sets the speaker apart.
- (void)setPreview:(NSString *)text author:(NSString *)author;
- (void)setDraftPreview:(NSString *)draftText;

- (void)applyTheme;

/// The table's own row actions start at iOS 8. Before that the list swipes a
/// row itself: three trailing buttons (Pin, Mute, Delete) on a left swipe,
/// and one leading button (Read/Unread) on a right swipe.
- (void)revealSwipeActionsWithTrailingTitles:(NSArray *)trailingTitles
                             trailingColours:(NSArray *)trailingColours
                               leadingTitles:(NSArray *)leadingTitles
                              leadingColours:(NSArray *)leadingColours
                                      target:(id)target
                                      action:(SEL)action;
- (void)revealSwipeActionsWithTitles:(NSArray *)titles
                             colours:(NSArray *)colours
                              target:(id)target
                              action:(SEL)action;
- (void)setSwipeActionsOffset:(CGFloat)offset;
- (void)openTrailingSwipeActionsAnimated:(BOOL)animated;
- (void)openLeadingSwipeActionsAnimated:(BOOL)animated;
- (void)openSwipeActionsAnimated:(BOOL)animated;
- (void)closeSwipeActionsAnimated:(BOOL)animated;
@property (nonatomic, readonly) BOOL swipeActionsOpen;
@property (nonatomic, readonly) CGFloat swipeActionsWidth;
@property (nonatomic, readonly) CGFloat trailingActionsWidth;
@property (nonatomic, readonly) CGFloat leadingActionsWidth;

@end
