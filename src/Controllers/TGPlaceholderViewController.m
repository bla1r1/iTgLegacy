#import "TGPlaceholderViewController.h"
#import "TGEmptyView.h"
#import "TGIcons.h"
#import "TGTheme.h"
#import "TGStyle.h"

@interface TGPlaceholderViewController ()
@property (nonatomic, strong) TGEmptyView *emptyView;
@end

@implementation TGPlaceholderViewController

- (void)viewDidLoad {
	[super viewDidLoad];
	self.title = self.featureName.length ? self.featureName : @"Not Available";
	self.view.backgroundColor = [[TGTheme shared] listBackgroundColour];

	__weak typeof(self) weakSelf = self;
	[[NSNotificationCenter defaultCenter] addObserverForName:TGThemeChangedNotification
			object:nil queue:[NSOperationQueue mainQueue]
		 usingBlock:^(NSNotification *note) {
		TGPlaceholderViewController *me = weakSelf;
		if (!me)
			return;
		me.view.backgroundColor = [[TGTheme shared] listBackgroundColour];
		[me buildEmptyView];
	}];

	[self buildEmptyView];
}

- (void)dealloc {
	[[NSNotificationCenter defaultCenter] removeObserver:self];
}

- (void)viewDidLayoutSubviews {
	[super viewDidLayoutSubviews];
	self.emptyView.frame = self.view.bounds;
}

/// A feature that is not here is a state, not an error: the same icon and
/// sentence shape every other empty screen uses, instead of a paragraph in
/// the middle of a blank view.
- (void)buildEmptyView {
	[self.emptyView removeFromSuperview];
	NSString *name = self.featureName.length ? self.featureName : @"This feature";
	self.emptyView = [TGEmptyView emptyViewWithFrame:self.view.bounds
			image:[TGIcons emptySearchIllustration]
			title:name
			subtitle:@"This feature is not available on this device yet. "
					 @"Settings > This Device explains what the hardware can do."
			buttonTitle:nil
			target:nil
			action:nil];
	[self.view addSubview:self.emptyView];
}

@end
