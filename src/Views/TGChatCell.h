#import <UIKit/UIKit.h>

// Their iOS chat list: a 60pt picture and up to two lines of preview, so a
// row is read without opening it.
static const CGFloat kRowHeight = 76.0f;
static const CGFloat kAvatar    = 60.0f;

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

/// The preview, with whoever wrote it ("Ivan:", "You:") in the title colour
/// ahead of the text, the way their list sets the speaker apart.
- (void)setPreview:(NSString *)text author:(NSString *)author;

- (void)applyTheme;

@end
