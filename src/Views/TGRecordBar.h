//
// TGRecordBar.h
// The strip a recording shows in the composer's place. The voice note and the
// round video are one gesture with two outputs, so they share this rather than
// each drawing their own and drifting apart.
//
#import <UIKit/UIKit.h>

@interface TGRecordBar : UIView

@property (nonatomic, strong, readonly) UIButton *cancelButton;
@property (nonatomic, strong, readonly) UIButton *sendButton;
@property (nonatomic, strong, readonly) UIButton *pauseButton;

/// The clock, and the dot that blinks while it runs and dims while paused.
- (void)showSeconds:(NSTimeInterval)seconds paused:(BOOL)paused;

/// A round control over the recording, in the pause disc's look.
+ (UIButton *)discOfSide:(CGFloat)side;
/// The "1" that makes the note one-time.
+ (UIButton *)onceButton;
+ (void)setOnce:(BOOL)on onButton:(UIButton *)button;

@end
