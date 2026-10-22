//
// TGSnackbar - transient undo notification banner with countdown timer.
//
#import <UIKit/UIKit.h>

@interface TGSnackbar : UIView

/// Shows the plate over `host` for `seconds`, then runs `commit`. Tapping UNDO
/// dismisses it and `commit` never runs. A second call replaces the first,
/// committing it immediately - two pending deletes would be a lie about what
/// has already happened.
+ (void)showInView:(UIView *)host
              text:(NSString *)text
           seconds:(NSInteger)seconds
          onCommit:(void (^)(void))commit;

/// Run any pending action now and take the plate away. Called when the screen
/// goes away, so a delete is never silently dropped.
+ (void)commitNow;

@end
