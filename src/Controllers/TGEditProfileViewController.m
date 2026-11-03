#import "TGEditProfileViewController.h"
#import "TGSheet.h"
#import "TGClient.h"
#import "TGTheme.h"
#import "TGIcons.h"
#import <QuartzCore/QuartzCore.h>
#import "TGStyle.h"
#import "TGAlertSheet.h"
#import "TGUsernameSettingsViewController.h"

// Profile editing: avatar photo, names, bio, birthday, phone, username and the
// profile's default tab.
static const CGFloat kPhotoSide = TGMetricProfileAvatar;
/// A field in a row: the table's gutter on the left, and enough room for the
/// Done button on the right.
static const CGFloat kBioRowHeight = TGMetricRow * 2.0f;
static const CGFloat kBioCountHeight = TGMetricLineCaption;
static const CGFloat kBirthdayYearRow = TGMetricRow;

typedef void (^TGEditRequest)(void (^completion)(BOOL ok, NSString *error));

/// The three answers the privacy sheet offers, spelled as the Settings page
/// spells them.
static NSString *TGBirthdayPrivacyLabel(NSString *value) {
	if ([value isEqualToString:@"everybody"]) return @"Everybody";
	if ([value isEqualToString:@"contacts"])  return @"My Contacts";
	if ([value isEqualToString:@"nobody"])    return @"Nobody";
	return @"...";
}

@interface TGEditProfileViewController () <UITextFieldDelegate, UITextViewDelegate,
		UIImagePickerControllerDelegate, UINavigationControllerDelegate>
@property (nonatomic, strong) UITextField *firstField;
@property (nonatomic, strong) UITextField *lastField;
@property (nonatomic, strong) UITextView *bioField;
@property (nonatomic, strong) UILabel *bioCountLabel;
@property (nonatomic, assign) NSInteger bioLengthMax;
@property (nonatomic, assign) BOOL bioEdited;
@property (nonatomic, assign) BOOL firstEdited;
@property (nonatomic, assign) BOOL lastEdited;
@property (nonatomic, assign) BOOL userInfoLoaded;
@property (nonatomic, assign) BOOL waitingForProfile;
@property (nonatomic, copy) NSString *originalFirst;
@property (nonatomic, copy) NSString *originalLast;
@property (nonatomic, copy) NSString *originalBio;
@property (nonatomic, strong) UIImageView *photoView;
@property (nonatomic, assign) NSInteger birthDay;
@property (nonatomic, assign) NSInteger birthMonth;
@property (nonatomic, assign) NSInteger birthYear;
@property (nonatomic, assign) BOOL birthdayChanged;
@property (nonatomic, copy) NSString *birthdayPrivacy;
@property (nonatomic, copy) NSString *username;
@property (nonatomic, copy) NSString *phoneNumber;
@property (nonatomic, copy) NSString *mainProfileTab;
@property (nonatomic, strong) TGSheet *birthdaySheet;
@property (nonatomic, strong) UIDatePicker *birthdayPicker;
@property (nonatomic, strong) UISegmentedControl *birthdayYearSwitch;
@property (nonatomic, assign) BOOL saving;
@end

@implementation TGEditProfileViewController

- (instancetype)init {
	return [super initWithStyle:UITableViewStyleGrouped];
}

- (void)viewDidLoad {
	[super viewDidLoad];
	self.title = @"Edit Profile";
	if ([self respondsToSelector:@selector(setEdgesForExtendedLayout:)])
		self.edgesForExtendedLayout = UIRectEdgeNone;
	[self applyTheme];

	self.navigationItem.rightBarButtonItem = [[UIBarButtonItem alloc]
			initWithTitle:@"Save" style:UIBarButtonItemStyleDone
				   target:self action:@selector(save)];

	NSDictionary *me = [TGClient shared].me;
	self.firstField = [self fieldWithPlaceholder:@"First name" text:me[@"first_name"]];
	self.lastField = [self fieldWithPlaceholder:@"Last name (optional)" text:me[@"last_name"]];
	self.originalFirst = self.firstField.text ?: @"";
	self.originalLast = self.lastField.text ?: @"";
	self.originalBio = @"";
	self.username = me[@"username"] ?: @"";
	self.phoneNumber = me[@"phone"] ?: @"";

	self.bioField = [[UITextView alloc] initWithFrame:CGRectZero];
	self.bioField.font = TGFontRow();
	self.bioField.backgroundColor = [UIColor clearColor];
	self.bioField.textColor = [[TGTheme shared] primaryTextColour];
	self.bioField.delegate = self;
	self.bioField.scrollEnabled = NO;
	self.bioField.contentInset = UIEdgeInsetsZero;
	if ([self.bioField respondsToSelector:@selector(setTextContainerInset:)])
		self.bioField.textContainerInset = UIEdgeInsetsZero;

	self.bioCountLabel = [[UILabel alloc] initWithFrame:CGRectZero];
	self.bioCountLabel.font = TGFontMicro();
	self.bioCountLabel.textColor = [[TGTheme shared] secondaryTextColour];
	self.bioCountLabel.backgroundColor = [UIColor clearColor];
	self.bioCountLabel.textAlignment = NSTextAlignmentRight;
	[self updateBioCount];

	__weak typeof(self) weakSelf = self;
	[[TGClient shared] request:@{
		@"@type"   : @"getUserFullInfo",
		@"user_id" : me[@"id"] ?: @0,
	} completion:^(NSDictionary *full){
		id raw = full[@"bio"];
		NSString *bio = [raw isKindOfClass:NSDictionary.class] ? raw[@"text"] : raw;
		if (![bio isKindOfClass:NSString.class])
			bio = @"";
		weakSelf.originalBio = bio;
		if (!weakSelf.bioEdited){
			weakSelf.bioField.text = bio;
			[weakSelf updateBioCount];
		}
	}];

	// `me` is built from getMe and has no last name; the user record does.
	[self loadUserInfo];

	[[TGClient shared] myBirthdayWithCompletion:^(NSInteger day, NSInteger month,
												 NSInteger year){
		weakSelf.birthDay = day;
		weakSelf.birthMonth = month;
		weakSelf.birthYear = year;
		[weakSelf.tableView reloadData];
	}];

	[[TGClient shared] bioLengthMaxWithCompletion:^(NSInteger max){
		weakSelf.bioLengthMax = max;
		[weakSelf updateBioCount];
	}];

	[[TGClient shared] privacyRule:@"ShowBirthdate" completion:^(NSString *value){
		weakSelf.birthdayPrivacy = value;
		[weakSelf.tableView reloadData];
	}];

	[[TGClient shared] myMainProfileTabWithCompletion:^(NSString *tab){
		weakSelf.mainProfileTab = tab;
		[weakSelf.tableView reloadData];
	}];

	[[NSNotificationCenter defaultCenter] addObserverForName:TGThemeChangedNotification
			object:nil queue:[NSOperationQueue mainQueue]
		 usingBlock:^(NSNotification *note) {
		[weakSelf applyTheme];
		[weakSelf updateFieldAppearances];
		[weakSelf.tableView reloadData];
	}];
}

- (void)dealloc {
	[[NSNotificationCenter defaultCenter] removeObserver:self];
}

- (void)applyTheme {
	[[TGTheme shared] styleGroupedTable:self.tableView];
	[[TGTheme shared] styleNavigationBar:self.navigationController.navigationBar];
}

- (void)updateFieldAppearances {
	NSArray *fields = @[self.firstField, self.lastField];
	UIKeyboardAppearance kb = UIKeyboardAppearanceDefault;
	for (UITextField *f in fields) {
		if (!f) continue;
		f.textColor = [[TGTheme shared] primaryTextColour];
		f.keyboardAppearance = kb;
	}
	self.bioField.textColor = [[TGTheme shared] primaryTextColour];
	self.bioField.font = TGFontRow();
	self.bioCountLabel.textColor = [[TGTheme shared] secondaryTextColour];
	self.bioCountLabel.font = TGFontMicro();
	[self setPlaceholder:@"First name" on:self.firstField];
	[self setPlaceholder:@"Last name (optional)" on:self.lastField];
}

- (UITextField *)fieldWithPlaceholder:(NSString *)placeholder text:(NSString *)text {
	UITextField *field = [[UITextField alloc] initWithFrame:CGRectZero];
	field.text = [text isKindOfClass:NSString.class] ? text : @"";
	field.font = TGFontRow();
	field.delegate = self;
	field.returnKeyType = UIReturnKeyDone;
	field.keyboardAppearance = UIKeyboardAppearanceDefault;
	field.textColor = [[TGTheme shared] primaryTextColour];
	[self setPlaceholder:placeholder on:field];
	return field;
}

/// UITextField draws its placeholder in a fixed pale grey, which on a dark
/// theme is grey on near-black and effectively invisible - an empty Last name
/// field looked like an empty row with nothing in it at all.
- (void)setPlaceholder:(NSString *)placeholder on:(UITextField *)field {
	if (!placeholder.length)
		return;
	UIColor *colour = [[TGTheme shared] placeholderColour];
	if ([field respondsToSelector:@selector(setAttributedPlaceholder:)]){
		field.attributedPlaceholder = [[NSAttributedString alloc]
				initWithString:placeholder
					attributes:@{NSForegroundColorAttributeName : colour}];
		return;
	}
	field.placeholder = placeholder;
}

- (void)updateBioCount {
	NSUInteger count = self.bioField.text.length;
	self.bioCountLabel.text = self.bioLengthMax > 0
			? [NSString stringWithFormat:@"%lu / %ld", (unsigned long)count,
					(long)self.bioLengthMax]
			: [NSString stringWithFormat:@"%lu", (unsigned long)count];
}

#pragma mark - saving

/// The last name lives on the user record, not in getMe's summary. Read it
/// before comparing fields: otherwise saving a new first name would send an
/// empty last name and erase the real one.
- (void)loadUserInfo {
	NSDictionary *me = [TGClient shared].me;
	__weak typeof(self) weakSelf = self;
	[[TGClient shared] userInfo:[me[@"id"] longLongValue]
					 completion:^(NSDictionary *user){
		TGEditProfileViewController *controller = weakSelf;
		if (!controller)
			return;
		BOOL waiting = controller.waitingForProfile;
		controller.waitingForProfile = NO;
		if (!user){
			if (waiting)
				[TGAlertSheet showMessage:@"Your profile could not be read. "
										  @"Check the connection and try again."
									title:@"Edit Profile" inView:controller.view];
			return;
		}
		NSString *first = user[@"first_name"] ?: @"";
		NSString *last = user[@"last_name"] ?: @"";
		controller.originalFirst = first;
		controller.originalLast = last;
		if (!controller.firstEdited)
			controller.firstField.text = first;
		if (!controller.lastEdited)
			controller.lastField.text = last;
		id usernames = user[@"usernames"];
		id active = [usernames isKindOfClass:NSDictionary.class] ? usernames[@"active_usernames"] : nil;
		controller.username = ([active isKindOfClass:NSArray.class] ? [active firstObject] : nil)
				?: (user[@"username"] ?: @"");
		controller.phoneNumber = user[@"phone_number"] ?: @"";
		controller.userInfoLoaded = YES;
		[controller.tableView reloadData];
		if (waiting)
			[controller save];
	}];
}

- (void)updateSavingState:(BOOL)saving {
	self.saving = saving;
	self.navigationItem.rightBarButtonItem.enabled = !saving;
	self.navigationItem.rightBarButtonItem.title = saving ? @"Saving..." : @"Save";
}

- (void)save {
	if (self.saving || self.waitingForProfile)
		return;
	if (!self.userInfoLoaded){
		self.waitingForProfile = YES;
		[self loadUserInfo];
		return;
	}
	NSString *first = [(self.firstField.text ?: @"")
			stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
	NSString *last = [(self.lastField.text ?: @"")
			stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
	if (!first.length){
		[TGAlertSheet showMessage:@"A first name is required."
							title:@"Edit Profile" inView:self.view];
		return;
	}

	NSString *bio = self.bioField.text ?: @"";
	NSString *originalFirst = self.originalFirst ?: @"";
	NSString *originalLast = self.originalLast ?: @"";
	NSString *originalBio = self.originalBio ?: @"";

	NSMutableArray *operations = [NSMutableArray array];
	if (![first isEqualToString:originalFirst] || ![last isEqualToString:originalLast]){
		[operations addObject:^(void (^done)(BOOL, NSString *)){
			[[TGClient shared] setName:first last:last completion:done];
		}];
	}
	if (![bio isEqualToString:originalBio]){
		[operations addObject:^(void (^done)(BOOL, NSString *)){
			[[TGClient shared] setBio:bio completion:done];
		}];
	}
	if (self.birthdayChanged){
		[operations addObject:^(void (^done)(BOOL, NSString *)){
			[[TGClient shared] setBirthdayDay:self.birthDay
										month:self.birthMonth
										 year:self.birthYear
								   completion:done];
		}];
	}

	if (!operations.count){
		[self.navigationController popViewControllerAnimated:YES];
		return;
	}

	[self updateSavingState:YES];
	__weak typeof(self) weakSelf = self;
	__block NSUInteger pending = operations.count;
	__block NSString *failure = nil;
	for (TGEditRequest request in operations){
		request(^(BOOL ok, NSString *error){
			if (!ok && !failure)
				failure = error ?: @"Telegram refused that change.";
			if (--pending > 0)
				return;
			[weakSelf updateSavingState:NO];
			if (failure){
				[TGAlertSheet showMessage:failure title:@"Edit Profile"
									inView:weakSelf.view];
				return;
			}
			[weakSelf.navigationController popViewControllerAnimated:YES];
		});
	}
}

- (BOOL)textFieldShouldReturn:(UITextField *)field {
	[field resignFirstResponder];
	return NO;
}

- (BOOL)textField:(UITextField *)field
		shouldChangeCharactersInRange:(NSRange)range
		replacementString:(NSString *)string {
	if (field == self.firstField)
		self.firstEdited = YES;
	else if (field == self.lastField)
		self.lastEdited = YES;
	return YES;
}

- (void)textViewDidChange:(UITextView *)textView {
	if (textView == self.bioField){
		self.bioEdited = YES;
		[self updateBioCount];
	}
}

- (BOOL)textView:(UITextView *)textView
		shouldChangeTextInRange:(NSRange)range
		replacementText:(NSString *)text {
	if (textView != self.bioField || self.bioLengthMax <= 0)
		return YES;
	NSUInteger length = textView.text.length - range.length + text.length;
	return length <= (NSUInteger)self.bioLengthMax;
}

/// Settings has its own navigation controller, and nothing was styling
/// its bar - an imported theme stopped at the top of the screen.
- (void)viewWillAppear:(BOOL)animated {
	[super viewWillAppear:animated];
	[[TGTheme shared] styleNavigationBar:self.navigationController.navigationBar];
	[self applyTheme];
	// The fields are built once and outlive a theme change.
	for (UITextField *field in @[self.firstField, self.lastField]){
		field.textColor = [[TGTheme shared] primaryTextColour];
		[self setPlaceholder:field.attributedPlaceholder.string ?: field.placeholder
						  on:field];
	}
	self.bioField.textColor = [[TGTheme shared] primaryTextColour];
	self.bioCountLabel.textColor = [[TGTheme shared] secondaryTextColour];
	[self.tableView reloadData];
}

#pragma mark - birthday

- (NSString *)birthdayText {
	if (self.birthDay <= 0)
		return @"Add";
	static NSArray *months = nil;
	if (!months) months = @[@"", @"January", @"February", @"March", @"April",
			@"May", @"June", @"July", @"August", @"September", @"October",
			@"November", @"December"];
	NSString *month = (self.birthMonth > 0 && self.birthMonth < 13)
			? months[self.birthMonth] : @"";
	return self.birthYear > 0
			? [NSString stringWithFormat:@"%@ %ld, %ld", month,
					(long)self.birthDay, (long)self.birthYear]
			: [NSString stringWithFormat:@"%@ %ld", month, (long)self.birthDay];
}

/// A date picker in a sheet: iOS 7 has no way to put one in a row, and a
/// birthday is picked once. The card is edge to edge, as a modal sheet is,
/// with the picker's own toolbar across the top of it. The year is a switch
/// because Telegram allows a day and month with no year.
- (void)editBirthday {
	static const CGFloat kBar = TGMetricRow, kPicker = TGMetricPickerHeight;

	TGSheet *sheet = [TGSheet sheetForView:self.view.window ?: self.view];
	UIView *card = [sheet addCardOfHeight:kBar + kBirthdayYearRow + kPicker
							 edgeToEdge:YES];

	UISegmentedControl *year = [[UISegmentedControl alloc]
			initWithItems:@[@"Year", @"No Year"]];
	year.selectedSegmentIndex = (self.birthDay > 0 && self.birthYear <= 0) ? 1 : 0;
	year.frame = CGRectMake(TGMetricGutter, kBar,
			card.bounds.size.width - TGDoubled(TGMetricGutter),
			TGMetricSegmentedHeight);
	year.center = CGPointMake(year.center.x,
			kBar + TGHalf(kBirthdayYearRow));
	[card addSubview:year];

	UIDatePicker *picker = [[UIDatePicker alloc] initWithFrame:
			CGRectMake(0, kBar + kBirthdayYearRow, card.bounds.size.width, kPicker)];
	picker.datePickerMode = UIDatePickerModeDate;
	picker.maximumDate = [NSDate date];
	if (self.birthDay > 0){
		NSDateComponents *components = [[NSDateComponents alloc] init];
		components.day = self.birthDay;
		components.month = self.birthMonth;
		components.year = self.birthYear > 0 ? self.birthYear : 1990;
		NSDate *date = [[NSCalendar currentCalendar] dateFromComponents:components];
		if (date) picker.date = date;
	}
	[card addSubview:picker];

	UIToolbar *bar = [[UIToolbar alloc] initWithFrame:
			CGRectMake(0, 0, card.bounds.size.width, kBar)];
	bar.items = @[
		[[UIBarButtonItem alloc] initWithTitle:(self.birthDay > 0 ? @"Remove" : @"Cancel")
				style:UIBarButtonItemStylePlain target:self action:@selector(clearBirthday)],
		[[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemFlexibleSpace
				target:nil action:nil],
		[[UIBarButtonItem alloc] initWithTitle:@"Done"
				style:UIBarButtonItemStyleDone target:self action:@selector(commitBirthday)],
	];
	[card addSubview:bar];

	self.birthdayPicker = picker;
	self.birthdayYearSwitch = year;
	self.birthdaySheet = sheet;
	[sheet present];
}

- (void)commitBirthday {
	NSDateComponents *c = [[NSCalendar currentCalendar]
			components:(NSDayCalendarUnit | NSMonthCalendarUnit | NSYearCalendarUnit)
			  fromDate:self.birthdayPicker.date];
	self.birthDay = c.day;
	self.birthMonth = c.month;
	self.birthYear = self.birthdayYearSwitch.selectedSegmentIndex == 0 ? c.year : 0;
	self.birthdayChanged = YES;
	[self closeBirthdaySheet];
}

- (void)clearBirthday {
	self.birthDay = self.birthMonth = self.birthYear = 0;
	self.birthdayChanged = YES;
	[self closeBirthdaySheet];
}

- (void)closeBirthdaySheet {
	[self.birthdaySheet dismiss];
	self.birthdaySheet = nil;
	self.birthdayPicker = nil;
	self.birthdayYearSwitch = nil;
	[self.tableView reloadData];
}

- (void)askBirthdayPrivacy {
	__weak typeof(self) weakSelf = self;
	[TGAlertSheet showChoices:@[@"Everybody", @"My Contacts", @"Nobody"]
						title:@"Birthday Privacy"
			 destructiveIndex:-1
					   inView:self.view
					 onChoice:^(NSInteger index){
		if (index < 0 || index > 2)
			return;
		NSString *value = @[@"everybody", @"contacts", @"nobody"][(NSUInteger)index];
		weakSelf.birthdayPrivacy = value;
		[[TGClient shared] setPrivacyRule:@"ShowBirthdate" to:value];
		[weakSelf.tableView reloadData];
	}];
}

#pragma mark - photo

- (void)changePhoto {
	if (![UIImagePickerController isSourceTypeAvailable:
			UIImagePickerControllerSourceTypePhotoLibrary])
		return;
	UIImagePickerController *picker = [[UIImagePickerController alloc] init];
	picker.sourceType = UIImagePickerControllerSourceTypePhotoLibrary;
	picker.delegate = self;
	[self presentViewController:picker animated:YES completion:nil];
}

- (void)imagePickerController:(UIImagePickerController *)picker
		didFinishPickingMediaWithInfo:(NSDictionary *)info {
	[picker dismissViewControllerAnimated:YES completion:nil];
	UIImage *image = info[UIImagePickerControllerOriginalImage];
	if (!image)
		return;

	UIImage *scaled = [TGIcons decodedImage:image
								fittingSize:CGSizeMake(TGMetricUploadPhotoSide, TGMetricUploadPhotoSide) fill:NO scale:TGMetricScaleFull];
	NSString *path = [NSTemporaryDirectory()
			stringByAppendingPathComponent:@"profile-photo.jpg"];
	if (![UIImageJPEGRepresentation(scaled, TGCompressionQualityStandard) writeToFile:path atomically:YES])
		return;

	self.photoView.image = scaled;      // show it before the upload finishes
	__weak typeof(self) weakSelf = self;
	[[TGClient shared] setProfilePhotoAtPath:path completion:^(BOOL ok){
		if (ok)
			return;
		[TGAlertSheet showMessage:@"Telegram refused the picture."
							title:@"Profile Photo" inView:weakSelf.view];
	}];
}

- (void)imagePickerControllerDidCancel:(UIImagePickerController *)picker {
	[picker dismissViewControllerAnimated:YES completion:nil];
}

#pragma mark - table

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView { return 6; }

- (NSString *)tableView:(UITableView *)tableView titleForHeaderInSection:(NSInteger)section {
	if (section == 1) return @"Name";
	if (section == 2) return @"Bio";
	if (section == 3) return @"Birthday";
	if (section == 4) return @"Account";
	if (section == 5) return @"Profile";
	return nil;
}

- (NSString *)tableView:(UITableView *)tableView titleForFooterInSection:(NSInteger)section {
	if (section == 1)
		return @"Enter your name and, if you like, add a profile photo.";
	if (section == 2)
		return @"Any details such as age, occupation or city.";
	if (section == 4)
		return @"The number you signed in with, and the public name people "
			   @"can find you by.";
	if (section == 5)
		return @"The tab your profile opens on, for everyone who looks at it.";
	return nil;
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
	if (section == 0) return 1;    // the picture
	if (section == 1) return 2;    // first, last
	if (section == 2) return 1;    // bio
	if (section == 3) return 2;    // birthday, birthday privacy
	if (section == 4) return 2;    // phone, username
	return 1;                      // main profile tab
}

- (CGFloat)tableView:(UITableView *)tableView heightForRowAtIndexPath:(NSIndexPath *)path {
	if (path.section == 0)
		return TGMetricEditProfileHeaderRow;
	if (path.section == 2)
		return kBioRowHeight;
	return TGMetricRow;
}

- (UITableViewCell *)tableView:(UITableView *)tableView
		 cellForRowAtIndexPath:(NSIndexPath *)path
{
	TGTheme *theme = [TGTheme shared];

	if (path.section == 0)
		return [self photoCellFor:tableView];

	if (path.section == 2){
		UITableViewCell *cell = [[UITableViewCell alloc]
				initWithStyle:UITableViewCellStyleDefault reuseIdentifier:nil];
		[theme styleCell:cell];
		cell.selectionStyle = UITableViewCellSelectionStyleNone;
		CGFloat width = tableView.bounds.size.width;
		CGFloat contentWidth = width - TGDoubled(TGMetricGutter);
		self.bioField.frame = CGRectMake(TGMetricGutter, 0, contentWidth,
				kBioRowHeight - kBioCountHeight);
		[cell.contentView addSubview:self.bioField];
		self.bioCountLabel.frame = CGRectMake(TGMetricGutter,
				kBioRowHeight - kBioCountHeight, contentWidth, kBioCountHeight);
		[cell.contentView addSubview:self.bioCountLabel];
		return cell;
	}

	if (path.section == 5){
		UITableViewCell *cell = [[UITableViewCell alloc]
				initWithStyle:UITableViewCellStyleValue1 reuseIdentifier:nil];
		[theme styleCell:cell];
		cell.textLabel.font = TGFontRow();
		cell.detailTextLabel.font = TGFontBody();
		cell.detailTextLabel.textColor = [theme cellDetailColour];
		cell.textLabel.text = @"Main Profile Tab";
		static NSArray *names = nil;
		if (!names)
			names = @[@"posts", @"gifts", @"media", @"files",
					  @"links", @"music", @"voice", @"gifs"];
		NSString *tab = self.mainProfileTab.length ? self.mainProfileTab : @"posts";
		NSUInteger index = [names indexOfObject:tab];
		cell.detailTextLabel.text = index == NSNotFound ? tab
				: [tab stringByReplacingCharactersInRange:NSMakeRange(0, 1)
						withString:[[tab substringToIndex:1] uppercaseString]];
		cell.accessoryType = UITableViewCellAccessoryDisclosureIndicator;
		return cell;
	}

	if (path.section == 3){
		UITableViewCell *cell = [[UITableViewCell alloc]
				initWithStyle:UITableViewCellStyleValue1 reuseIdentifier:nil];
		[theme styleCell:cell];
		cell.textLabel.font = TGFontRow();
		cell.detailTextLabel.font = TGFontBody();
		cell.detailTextLabel.textColor = [theme cellDetailColour];
		if (path.row == 0){
			cell.textLabel.text = @"Birthday";
			cell.detailTextLabel.text = [self birthdayText];
			cell.accessoryType = UITableViewCellAccessoryDisclosureIndicator;
		} else {
			cell.textLabel.text = @"Birthday Privacy";
			cell.detailTextLabel.text = self.birthdayPrivacy.length
					? TGBirthdayPrivacyLabel(self.birthdayPrivacy) : @"...";
			cell.accessoryType = UITableViewCellAccessoryDisclosureIndicator;
			cell.selectionStyle = UITableViewCellSelectionStyleBlue;
		}
		return cell;
	}

	// The last card carries values rather than fields: a number cannot be
	// typed here at all, and a username needs its own screen to check itself.
	if (path.section == 4){
		UITableViewCell *cell = [[UITableViewCell alloc]
				initWithStyle:UITableViewCellStyleValue1 reuseIdentifier:nil];
		[theme styleCell:cell];
		cell.textLabel.font = TGFontRow();
		cell.detailTextLabel.font = TGFontBody();
		cell.detailTextLabel.textColor = [theme cellDetailColour];
		if (path.row == 0){
			cell.textLabel.text = @"Phone Number";
			cell.detailTextLabel.text = self.phoneNumber.length
					? [NSString stringWithFormat:@"+%@", self.phoneNumber] : @"unknown";
			// Changing a number is a whole login flow; this shows it.
			cell.selectionStyle = UITableViewCellSelectionStyleNone;
		} else {
			// Telegram puts the public name first: it is the row people
			// come here to change, and its own screen owns the switches.
			cell.textLabel.text = @"Username";
			cell.detailTextLabel.text = self.username.length
					? [NSString stringWithFormat:@"@%@", self.username] : @"none";
			cell.accessoryType = UITableViewCellAccessoryDisclosureIndicator;
			cell.selectionStyle = UITableViewCellSelectionStyleBlue;
		}
		return cell;
	}

	UITableViewCell *cell = [[UITableViewCell alloc]
			initWithStyle:UITableViewCellStyleDefault reuseIdentifier:nil];
	[theme styleCell:cell];
	cell.selectionStyle = UITableViewCellSelectionStyleNone;

	UITextField *field = path.row == 0 ? self.firstField : self.lastField;
	field.frame = CGRectMake(TGMetricGutter, 0,
			tableView.bounds.size.width - TGDoubled(TGMetricGutter), TGMetricRow);
	field.textColor = [theme primaryTextColour];
	[cell.contentView addSubview:field];
	return cell;
}

- (UITableViewCell *)photoCellFor:(UITableView *)tableView {
	TGTheme *theme = [TGTheme shared];
	CGFloat width = tableView.bounds.size.width;

	UITableViewCell *cell = [[UITableViewCell alloc]
			initWithStyle:UITableViewCellStyleDefault reuseIdentifier:nil];
	[theme styleCell:cell];
	cell.selectionStyle = UITableViewCellSelectionStyleNone;

	NSDictionary *me = [TGClient shared].me;
	NSString *name = [me[@"first_name"] length] ? me[@"first_name"] : @"?";

	self.photoView = [[UIImageView alloc] initWithFrame:
			CGRectMake(TGCenteredOrigin(width, kPhotoSide), TGMetricPad, kPhotoSide, kPhotoSide)];
	self.photoView.layer.cornerRadius = TGHalf(kPhotoSide);
	self.photoView.clipsToBounds = YES;
	self.photoView.layer.shouldRasterize = YES;
	self.photoView.layer.rasterizationScale = [UIScreen mainScreen].scale;
	self.photoView.layer.borderColor = [theme separatorColour].CGColor;
	self.photoView.layer.borderWidth = 1.0f;
	self.photoView.contentMode = UIViewContentModeScaleAspectFill;
	self.photoView.image = [TGIcons avatarWithInitials:
			[name substringToIndex:1].uppercaseString
												  size:kPhotoSide
											  colourId:[me[@"id"] longLongValue]];
	[cell.contentView addSubview:self.photoView];

	NSNumber *fileId = [[TGClient shared] photoFileIdForUserId:[me[@"id"] longLongValue]];
	if (fileId)
		[[TGClient shared] downloadFile:fileId.integerValue
							   priority:TGDownloadPriorityAvatar
							 completion:^(NSString *path){
			[TGIcons loadImageAtPath:path into:self.photoView];
		}];

	UIButton *change = [UIButton buttonWithType:UIButtonTypeCustom];
	change.frame = CGRectMake(0, kPhotoSide + TGMetricPadMedium, width, TGMetricLineTitle);
	[change setTitle:(fileId ? @"Change Photo" : @"Set Photo")
			forState:UIControlStateNormal];
	[change setTitleColor:[theme accentColour] forState:UIControlStateNormal];
	change.titleLabel.font = TGFontRow();
	[change addTarget:self action:@selector(changePhoto)
	 forControlEvents:UIControlEventTouchUpInside];
	[cell.contentView addSubview:change];

	return cell;
}

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)path {
	[tableView deselectRowAtIndexPath:path animated:YES];
	if (path.section == 3 && path.row == 0){
		[self editBirthday];
		return;
	}
	if (path.section == 3 && path.row == 1){
		[self askBirthdayPrivacy];
		return;
	}
	if (path.section == 4 && path.row == 1){
		TGUsernameSettingsViewController *usernames =
				[[TGUsernameSettingsViewController alloc] init];
		usernames.hidesBottomBarWhenPushed = YES;
		[self.navigationController pushViewController:usernames animated:YES];
		return;
	}
	if (path.section == 5)
		[self chooseMainProfileTab];
}

- (void)chooseMainProfileTab {
	NSArray *tabs = @[@"posts", @"gifts", @"media", @"files",
					  @"links", @"music", @"voice", @"gifs"];
	NSArray *titles = @[@"Posts", @"Gifts", @"Media", @"Files",
						@"Links", @"Music", @"Voice", @"GIFs"];
	NSString *current = self.mainProfileTab.length ? self.mainProfileTab : @"posts";
	__weak typeof(self) weakSelf = self;
	[TGAlertSheet showChoices:titles
						title:@"Main Profile Tab"
			 destructiveIndex:-1
					   inView:self.view
					 onChoice:^(NSInteger index){
		if (index < 0 || index >= (NSInteger)tabs.count)
			return;
		NSString *tab = tabs[(NSUInteger)index];
		[[TGClient shared] setMainProfileTab:tab completion:^(BOOL ok, NSString *error){
			if (!ok){
				[TGAlertSheet showMessage:(error ?: @"Telegram refused that.")
									title:@"Main Profile Tab" inView:weakSelf.view];
				return;
			}
			weakSelf.mainProfileTab = tab;
			[weakSelf.tableView reloadData];
		}];
	}];
}

@end

// vim:ft=objc
