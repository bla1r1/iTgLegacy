//
// TGStoryCameraViewController - the first two steps of posting a story, the
// way the official app starts it: a full-screen camera, then the picture on
// its own with a caption line. Both end in TGStoryComposerViewController's
// table, which is pushed on the same modal navigation controller.
//
#import <UIKit/UIKit.h>

@class TGStoryComposerViewController;

/// The steps before the table hide the status bar; iOS 7 and later read that
/// from prefersStatusBarHidden, iOS 6 has to be told. The table shows it again.
void TGStoryFlowSetStatusBarHidden(BOOL hidden);

@interface TGStoryCameraViewController : UIViewController

/// A navigation controller rooted at the camera, ready to be presented. The
/// composer is pushed on it after the editor.
+ (UINavigationController *)flowForComposer:(TGStoryComposerViewController *)composer;

- (instancetype)initWithComposer:(TGStoryComposerViewController *)composer;

@end

/// The picture (or the first frame of a video) with a caption line and Next.
@interface TGStoryEditorViewController : UIViewController

- (instancetype)initWithComposer:(TGStoryComposerViewController *)composer
						   image:(UIImage *)image;
- (instancetype)initWithComposer:(TGStoryComposerViewController *)composer
					   videoPath:(NSString *)path
						duration:(double)duration;

@end
