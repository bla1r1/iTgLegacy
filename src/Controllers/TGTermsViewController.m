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
@property (nonatomic, strong) UILabel *intro;
@end

@implementation TGTermsViewController

- (void)viewDidLoad {
	[super viewDidLoad];

	self.title = @"Terms of Service";

	// Telegram puts one sentence above the document so the buttons have a
	// reason. The body keeps its own scroll, because the text can run to
	// pages and the acceptance is only meaningful if it can be read.
	CGFloat width = self.view.bounds.size.width;
	UILabel *intro = [[UILabel alloc] initWithFrame:
			CGRectMake(TGMetricPad, TGMetricPad,
					width - TGDoubled(TGMetricPad), TGDoubled(TGMetricLineTitle))];
	intro.text = @"Please read and accept Telegram's Terms of Service to continue.";
	intro.font = TGFontCaption();
	intro.numberOfLines = 2;
	intro.textAlignment = NSTextAlignmentCenter;
	intro.backgroundColor = [UIColor clearColor];
	intro.autoresizingMask = UIViewAutoresizingFlexibleWidth;
	[self.view addSubview:intro];

	CGFloat top = CGRectGetMaxY(intro.frame) + TGMetricPadSmall;
	UITextView *body = [[UITextView alloc] initWithFrame:
			CGRectMake(0, top, width, self.view.bounds.size.height - top)];
	body.autoresizingMask = UIViewAutoresizingFlexibleWidth |
							UIViewAutoresizingFlexibleHeight;
	body.editable = NO;
	body.font = TGFontBody();
	body.text = self.termsText ?: @"";
	body.textContainerInset = UIEdgeInsetsMake(TGMetricPad, TGMetricPad,
											   TGMetricPad, TGMetricPad);
	self.body = body;
	self.intro = intro;
	[self.view addSubview:body];

	self.navigationItem.rightBarButtonItem = [[UIBarButtonItem alloc]
			initWithTitle:@"Accept"
					style:UIBarButtonItemStyleDone
				   target:self
				   action:@selector(acceptTapped)];
	[self applyTheme];
	[[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(applyTheme) name:TGThemeChangedNotification object:nil];
}

- (void)dealloc {
	[[NSNotificationCenter defaultCenter] removeObserver:self];
}

- (void)applyTheme {
	TGTheme *theme = [TGTheme shared];
	self.view.backgroundColor = [theme listBackgroundColour];
	self.intro.textColor = [theme secondaryTextColour];
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
