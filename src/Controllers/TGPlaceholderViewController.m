#import "TGPlaceholderViewController.h"
#import "TGTheme.h"
#import "TGStyle.h"

@implementation TGPlaceholderViewController

- (void)viewDidLoad {
	[super viewDidLoad];
	self.title = self.featureName;
	self.view.backgroundColor = [[TGTheme shared] listBackgroundColour];
	
	UILabel *label = [[UILabel alloc] initWithFrame:self.view.bounds];
	label.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
	label.text = [NSString stringWithFormat:@"%@\nis not yet available in LegacyTG.", self.featureName];
	label.numberOfLines = 0;
	label.textAlignment = NSTextAlignmentCenter;
	label.textColor = [[TGTheme shared] secondaryTextColour];
	label.font = TGFontRow();
	
	[self.view addSubview:label];
}

@end
