#import "TGPlaceholderViewController.h"
#import "TGTheme.h"

@implementation TGPlaceholderViewController

- (void)viewDidLoad {
	[super viewDidLoad];
	self.title = self.featureName;
	self.view.backgroundColor = [[TGTheme shared] listBackgroundColour];
	
	UILabel *label = [[UILabel alloc] initWithFrame:self.view.bounds];
	label.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
	label.text = [NSString stringWithFormat:@"%@\nis not yet available in iTgLegacy.", self.featureName];
	label.numberOfLines = 0;
	label.textAlignment = NSTextAlignmentCenter;
	label.textColor = [[TGTheme shared] secondaryTextColour];
	label.font = [UIFont systemFontOfSize:16];
	
	[self.view addSubview:label];
}

@end
