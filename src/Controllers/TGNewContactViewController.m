//
// TGNewContactViewController - the three fields a new contact is made of:
// a name for you to read and a number for Telegram to match on. The import
// makes the user when Telegram has never met the number, and the contact is
// what adds them.
//
#import <UIKit/UIKit.h>
#import "TGNewContactViewController.h"

#import "TGClient.h"
#import "TGTheme.h"
#import <QuartzCore/QuartzCore.h>
#import "TGStyle.h"
#import "TGAlertSheet.h"

/// A field in a row: the table's gutter on the left, and room for the Done
/// button on the right.
static const CGFloat kFieldWidth = 290.0f;

@interface TGNewContactViewController () <UITextFieldDelegate>
@property (nonatomic, strong) UITextField *firstField;
@property (nonatomic, strong) UITextField *lastField;
@property (nonatomic, strong) UITextField *phoneField;
@end

@implementation TGNewContactViewController

- (instancetype)init {
	return [super initWithStyle:UITableViewStyleGrouped];
}

- (void)viewDidLoad {
	[super viewDidLoad];
	self.title = @"New Contact";
	if ([self respondsToSelector:@selector(setEdgesForExtendedLayout:)])
		self.edgesForExtendedLayout = UIRectEdgeNone;
	[self applyTheme];

	self.navigationItem.rightBarButtonItem = [[UIBarButtonItem alloc]
			initWithTitle:@"Done" style:UIBarButtonItemStyleDone
				   target:self action:@selector(save)];

	self.firstField = [self fieldWithPlaceholder:@"First name" text:self.first];
	self.lastField  = [self fieldWithPlaceholder:@"Last name"  text:self.last];
	self.phoneField = [self fieldWithPlaceholder:@"Phone"      text:self.phone];
	self.phoneField.keyboardType = UIKeyboardTypePhonePad;
	if (self.firstField.text.length)
		[self.phoneField becomeFirstResponder];
	else
		[self.firstField becomeFirstResponder];

	__weak typeof(self) weakSelf = self;
	[[NSNotificationCenter defaultCenter] addObserverForName:TGThemeChangedNotification
			object:nil queue:[NSOperationQueue mainQueue]
		 usingBlock:^(NSNotification *note) {
		[weakSelf applyTheme];
		[weakSelf.tableView reloadData];
	}];
}

- (void)dealloc {
	[[NSNotificationCenter defaultCenter] removeObserver:self];
}

- (void)applyTheme {
	self.tableView.backgroundColor = [[TGTheme shared] groupedBackgroundColour];
	self.tableView.separatorColor = [[TGTheme shared] separatorColour];
	[[TGTheme shared] styleNavigationBar:self.navigationController.navigationBar];
	for (UITextField *field in @[self.firstField, self.lastField, self.phoneField]){
		if (!field) continue;
		field.textColor = [[TGTheme shared] primaryTextColour];
		field.keyboardAppearance = [TGTheme shared].isDark
				? UIKeyboardAppearanceDark : UIKeyboardAppearanceDefault;
	}
}

- (UITextField *)fieldWithPlaceholder:(NSString *)placeholder text:(NSString *)text {
	UITextField *field = [[UITextField alloc] initWithFrame:CGRectMake(TGMetricGutter, 0,
			kFieldWidth, TGMetricRow)];
	field.text = [text isKindOfClass:NSString.class] ? text : @"";
	field.font = TGFontRow();
	field.delegate = self;
	field.returnKeyType = UIReturnKeyDone;
	field.keyboardAppearance = [TGTheme shared].isDark
			? UIKeyboardAppearanceDark : UIKeyboardAppearanceDefault;
	field.textColor = [[TGTheme shared] primaryTextColour];
	field.attributedPlaceholder = [[NSAttributedString alloc]
			initWithString:placeholder
				attributes:@{NSForegroundColorAttributeName:
							 [[TGTheme shared] secondaryTextColour]}];
	return field;
}

- (BOOL)textFieldShouldReturn:(UITextField *)field {
	if (field == self.firstField)
		[self.lastField becomeFirstResponder];
	else if (field == self.lastField)
		[self.phoneField becomeFirstResponder];
	else
		[field resignFirstResponder];
	return YES;
}

#pragma mark - the table

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
	return 3;
}

- (UITableViewCell *)tableView:(UITableView *)tableView
		 cellForRowAtIndexPath:(NSIndexPath *)indexPath {
	UITableViewCell *cell = [[UITableViewCell alloc]
			initWithStyle:UITableViewCellStyleDefault
			reuseIdentifier:@"TGNewContact"];
	cell.backgroundColor = [UIColor clearColor];
	cell.selectionStyle = UITableViewCellSelectionStyleNone;
	UITextField *field = indexPath.row == 0 ? self.firstField
			: indexPath.row == 1 ? self.lastField : self.phoneField;
	[field removeFromSuperview];
	[cell.contentView addSubview:field];
	return cell;
}

- (void)tableView:(UITableView *)tableView
	   willDisplayHeaderView:(UIView *)view
				 forSection:(NSInteger)section {
	[[TGTheme shared] styleSectionHeader:view];
}

#pragma mark - saving

/// The import makes the user when Telegram has never met the number; the
/// contact is what adds them, and it answers on the phone number either way.
- (void)save {
	NSString *first = [self.firstField.text stringByTrimmingCharactersInSet:
			[NSCharacterSet whitespaceAndNewlineCharacterSet]];
	NSString *last  = [self.lastField.text stringByTrimmingCharactersInSet:
			[NSCharacterSet whitespaceAndNewlineCharacterSet]];
	NSString *phone = [[self.phoneField.text stringByReplacingOccurrencesOfString:@" "
																		   withString:@""]
			stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];

	if (!first.length || !phone.length){
		[TGAlertSheet showMessage:@"A name for you to read and a number for "
								  @"Telegram to match on - both are wanted."
							title:@"New Contact" inView:self.view];
		return;
	}

	__weak typeof(self) weakSelf = self;
	[[TGClient shared] importContactNamed:first lastName:last phone:phone
							   completion:^(int64_t userId){
		[[TGClient shared] addContactWithUserId:userId
									  firstName:first
									   lastName:last
										  phone:phone
									 completion:^(BOOL ok){
			TGNewContactViewController *me = weakSelf;
			if (!me)
				return;
			NSString *phrase = ok
					? [NSString stringWithFormat:@"%@ saved.", first]
					: @"Telegram refused that contact.";
			[TGAlertSheet showMessage:phrase
								title:@"New Contact" inView:me.view];
			if (ok)
				[me.navigationController popViewControllerAnimated:YES];
		}];
	}];
}

@end

// vim:ft=objc
