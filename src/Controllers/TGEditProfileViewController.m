#import "TGEditProfileViewController.h"
#import "TGClient.h"
#import "TGTheme.h"
#import "TGIcons.h"
#import <QuartzCore/QuartzCore.h>
#import "TGStyle.h"
#import "TGAlertSheet.h"

// Profile editing: avatar photo, names, bio, birthday, and username.
static const CGFloat kPhotoSide = TGMetricProfileAvatar;

@interface TGEditProfileViewController () <UITextFieldDelegate,
		UIImagePickerControllerDelegate, UINavigationControllerDelegate>
@property (nonatomic, strong) UITextField *firstField;
@property (nonatomic, strong) UITextField *lastField;
@property (nonatomic, strong) UITextField *usernameField;
@property (nonatomic, strong) UITextField *bioField;
@property (nonatomic, strong) UIImageView *photoView;
@property (nonatomic, assign) NSInteger birthDay;
@property (nonatomic, assign) NSInteger birthMonth;
@property (nonatomic, assign) NSInteger birthYear;
@property (nonatomic, assign) BOOL birthdayChanged;
@property (nonatomic, strong) TGSheet *birthdaySheet;
@property (nonatomic, strong) UIDatePicker *birthdayPicker;
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
	self.firstField    = [self fieldWithPlaceholder:@"First name" text:me[@"first_name"]];
	self.lastField     = [self fieldWithPlaceholder:@"Last name"  text:me[@"last_name"]];
	self.usernameField = [self fieldWithPlaceholder:@"username"   text:me[@"username"]];
	self.usernameField.autocapitalizationType = UITextAutocapitalizationTypeNone;
	self.usernameField.autocorrectionType = UITextAutocorrectionTypeNo;
	self.bioField      = [self fieldWithPlaceholder:@"A few words about you" text:nil];

	__weak typeof(self) weakSelf = self;
	[[TGClient shared] request:@{
		@"@type"   : @"getUserFullInfo",
		@"user_id" : me[@"id"] ?: @0,
	} completion:^(NSDictionary *full){
		weakSelf.bioField.text = full[@"bio"][@"text"] ?: full[@"bio"] ?: @"";
	}];

	[[TGClient shared] myBirthdayWithCompletion:^(NSInteger day, NSInteger month,
												 NSInteger year){
		weakSelf.birthDay = day;
		weakSelf.birthMonth = month;
		weakSelf.birthYear = year;
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
	self.tableView.backgroundColor = [[TGTheme shared] groupedBackgroundColour];
	self.tableView.separatorColor = [[TGTheme shared] separatorColour];
	[[TGTheme shared] styleNavigationBar:self.navigationController.navigationBar];
}

- (void)updateFieldAppearances {
	NSArray *fields = @[self.firstField, self.lastField, self.usernameField, self.bioField];
	UIKeyboardAppearance kb = [TGTheme shared].isDark ? UIKeyboardAppearanceDark : UIKeyboardAppearanceDefault;
	for (UITextField *f in fields) {
		if (!f) continue;
		f.textColor = [[TGTheme shared] primaryTextColour];
		f.keyboardAppearance = kb;
	}
	[self setPlaceholder:@"First name" on:self.firstField];
	[self setPlaceholder:@"Last name" on:self.lastField];
	[self setPlaceholder:@"username" on:self.usernameField];
	[self setPlaceholder:@"A few words about you" on:self.bioField];
}

- (UITextField *)fieldWithPlaceholder:(NSString *)placeholder text:(NSString *)text {
	UITextField *field = [[UITextField alloc] initWithFrame:CGRectMake(15, 0, 290, 44)];
	field.text = [text isKindOfClass:NSString.class] ? text : @"";
	field.font = TGFontRow();
	field.delegate = self;
	field.returnKeyType = UIReturnKeyDone;
	field.keyboardAppearance = [TGTheme shared].isDark ? UIKeyboardAppearanceDark : UIKeyboardAppearanceDefault;
	field.textColor = [[TGTheme shared] primaryTextColour];
	[self setPlaceholder:placeholder on:field];
	return field;
}

- (void)tableView:(UITableView *)tableView willDisplayHeaderView:(UIView *)view
	   forSection:(NSInteger)section {
	[[TGTheme shared] styleSectionHeader:view];
}

- (void)tableView:(UITableView *)tableView willDisplayFooterView:(UIView *)view forSection:(NSInteger)section {
	if ([view isKindOfClass:[UITableViewHeaderFooterView class]]) {
		UITableViewHeaderFooterView *footer = (UITableViewHeaderFooterView *)view;
		footer.textLabel.textColor = [[TGTheme shared] sectionHeaderColour];
	}
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

#pragma mark - saving

- (void)save {
	[[TGClient shared] setName:self.firstField.text last:self.lastField.text];
	[[TGClient shared] setBio:self.bioField.text];

	if (self.birthdayChanged)
		[[TGClient shared] setBirthdayDay:self.birthDay
									month:self.birthMonth
									 year:self.birthYear];

	NSString *username = [self.usernameField.text
			stringByReplacingOccurrencesOfString:@"@" withString:@""];
	NSDictionary *me = [TGClient shared].me;
	if (![username isEqualToString:me[@"username"] ?: @""]){
		// A username can be taken, which is the one failure worth reporting.
		[[TGClient shared] setUsername:username completion:^(BOOL ok){
			if (!ok){
				[TGAlertSheet showMessage:@"That username is not available."
									title:@"Username"
								   inView:[UIApplication sharedApplication].keyWindow];
			}
		}];
	}
	[self.navigationController popViewControllerAnimated:YES];
}

- (BOOL)textFieldShouldReturn:(UITextField *)field {
	[field resignFirstResponder];
	return NO;
}

/// Settings has its own navigation controller, and nothing was styling
/// its bar - an imported theme stopped at the top of the screen.
- (void)viewWillAppear:(BOOL)animated {
	[super viewWillAppear:animated];
	[[TGTheme shared] styleNavigationBar:self.navigationController.navigationBar];
	[self applyTheme];
	// The fields are built once and outlive a theme change.
	for (UITextField *field in @[self.firstField, self.lastField,
								 self.usernameField, self.bioField]){
		field.textColor = [[TGTheme shared] primaryTextColour];
		[self setPlaceholder:field.attributedPlaceholder.string ?: field.placeholder
						  on:field];
	}
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
/// with the picker's own toolbar across the top of it.
- (void)editBirthday {
	static const CGFloat kBar = TGMetricRow, kPicker = TGMetricPickerHeight;

	TGSheet *sheet = [TGSheet sheetForView:self.view.window ?: self.view];
	UIView *card = [sheet addCardOfHeight:kBar + kPicker edgeToEdge:YES];

	UIDatePicker *picker = [[UIDatePicker alloc] initWithFrame:
			CGRectMake(0, kBar, card.bounds.size.width, kPicker)];
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
	self.birthdaySheet = sheet;
	[sheet present];
}

- (void)commitBirthday {
	NSDateComponents *c = [[NSCalendar currentCalendar]
			components:(NSDayCalendarUnit | NSMonthCalendarUnit | NSYearCalendarUnit)
			  fromDate:self.birthdayPicker.date];
	self.birthDay = c.day;
	self.birthMonth = c.month;
	self.birthYear = c.year;
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
	[self.tableView reloadData];
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
								fittingSize:CGSizeMake(640, 640) fill:NO scale:TGMetricScaleFull];
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

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView { return 4; }

- (NSString *)tableView:(UITableView *)tableView titleForHeaderInSection:(NSInteger)section {
	if (section == 1) return @"Name";
	if (section == 2) return @"Bio";
	return nil;
}

- (NSString *)tableView:(UITableView *)tableView titleForFooterInSection:(NSInteger)section {
	if (section == 1)
		return @"Enter your name and, if you like, add a profile photo.";
	if (section == 2)
		return @"Any details such as age, occupation or city. Only contacts "
			   @"can see this.";
	if (section == 3)
		return @"Only contacts can see your birthday.";
	return nil;
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
	if (section == 0) return 1;    // the picture
	if (section == 1) return 2;    // first, last
	if (section == 2) return 1;    // bio
	return 3;                      // birthday, number, username
}

- (CGFloat)tableView:(UITableView *)tableView heightForRowAtIndexPath:(NSIndexPath *)path {
	return path.section == 0 ? TGMetricEditProfileHeaderRow : TGMetricRow;
}

- (UITableViewCell *)tableView:(UITableView *)tableView
		 cellForRowAtIndexPath:(NSIndexPath *)path
{
	TGTheme *theme = [TGTheme shared];

	if (path.section == 0)
		return [self photoCellFor:tableView];

	// The last card carries values rather than fields: a number cannot be
	// typed here at all, and a username needs its own screen to check itself.
	if (path.section == 3){
		UITableViewCell *cell = [[UITableViewCell alloc]
				initWithStyle:UITableViewCellStyleValue1 reuseIdentifier:nil];
		[theme styleCell:cell];
		cell.textLabel.font = TGFontRow();
		cell.detailTextLabel.font = TGFontBody();
		cell.detailTextLabel.textColor = [theme cellDetailColour];

		NSDictionary *me = [TGClient shared].me;
		if (path.row == 0){
			cell.textLabel.text = @"Birthday";
			cell.detailTextLabel.text = [self birthdayText];
			cell.accessoryType = UITableViewCellAccessoryDisclosureIndicator;
		} else if (path.row == 1){
			cell.textLabel.text = @"Phone Number";
			cell.detailTextLabel.text = [me[@"phone"] length]
					? [NSString stringWithFormat:@"+%@", me[@"phone"]] : @"unknown";
			// Changing a number is a whole login flow; this shows it.
			cell.selectionStyle = UITableViewCellSelectionStyleNone;
		} else {
			cell.textLabel.text = @"Username";
			cell.detailTextLabel.text = [me[@"username"] length]
					? [NSString stringWithFormat:@"@%@", me[@"username"]] : @"none";
			cell.selectionStyle = UITableViewCellSelectionStyleNone;
		}
		return cell;
	}

	UITableViewCell *cell = [[UITableViewCell alloc]
			initWithStyle:UITableViewCellStyleDefault reuseIdentifier:nil];
	[theme styleCell:cell];
	cell.selectionStyle = UITableViewCellSelectionStyleNone;

	UITextField *field = nil;
	if (path.section == 1) field = path.row == 0 ? self.firstField : self.lastField;
	else                   field = self.bioField;

	field.frame = CGRectMake(TGMetricGutter, 0, tableView.bounds.size.width - TGDoubled(TGMetricGutter), TGMetricRow);
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
			CGRectMake(TGCenteredOrigin(width, kPhotoSide), 8, kPhotoSide, kPhotoSide)];
	self.photoView.layer.cornerRadius = TGHalf(kPhotoSide);
	self.photoView.clipsToBounds = YES;
	self.photoView.layer.shouldRasterize = YES;
	self.photoView.layer.rasterizationScale = [UIScreen mainScreen].scale;
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
	change.frame = CGRectMake(0, kPhotoSide + 12, width, 26);
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
	if (path.section == 3 && path.row == 0)
		[self editBirthday];
}

@end

// vim:ft=objc
