//
// TGTermsViewController.m - the terms popup updateTermsOfService asks for.
//
// The text can run to pages, so it is a scroll view and not an alert: an
// alert would cut it at a few lines and the acceptance would be for a
// document nobody could read. One button, because accepting is the only way
// past it.
#import "TGTermsViewController.h"
#import "TGTheme.h"
#import "TGStyle.h"

@interface TGTermsViewController ()
@property (nonatomic, strong) UITextView *body;
@end

@implementation TGTermsViewController

- (void)viewDidLoad {
	[super viewDidLoad];

	self.title = @"Terms of Service";

	UITextView *body = [[UITextView alloc] initWithFrame:self.view.bounds];
	body.autoresizingMask = UIViewAutoresizingFlexibleWidth |
							UIViewAutoresizingFlexibleHeight;
	body.editable = NO;
	body.font = TGFontBody();
	body.text = self.termsText ?: @"";
	body.textContainerInset = UIEdgeInsetsMake(TGMetricPad, TGMetricPad,
											   TGMetricPad, TGMetricPad);
	self.body = body;
	[self.view addSubview:body];

	self.navigationItem.rightBarButtonItem = [[UIBarButtonItem alloc]
			initWithTitle:@"Accept"
					style:UIBarButtonItemStyleDone
				   target:self
				   action:@selector(acceptTapped)];
	[self applyTheme];
}

- (void)applyTheme {
	TGTheme *theme = [TGTheme shared];
	self.view.backgroundColor = [theme listBackgroundColour];
	self.body.backgroundColor = [theme listBackgroundColour];
	self.body.textColor = [theme primaryTextColour];
	[theme styleNavigationBar:self.navigationController.navigationBar];
}

- (void)acceptTapped {
	if (self.onAccept)
		self.onAccept();
	if (self.navigationController.presentingViewController)
		[self.navigationController dismissViewControllerAnimated:YES completion:nil];
	else
		[self.navigationController popViewControllerAnimated:YES];
}

@end

// vim:ft=objc
