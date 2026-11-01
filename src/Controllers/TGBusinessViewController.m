//
// TGBusinessViewController.m - Telegram Business settings, the profile
// fields, the automated messages, the location/hours/intro and links to
// chat.
//
// The account-level settings are real subscriber features. The profile
// checksum through setBusinessAccount* carries a business connection id and
// is declared bot-only; when a user account tries it, Telegram answers with
// its refusal and the alert shows that sentence. The row stays visible
// because hiding it would leave a Business subscriber with a page that
// silently does less than the official client.
//
#import "TGBusinessViewController.h"
#import "TGBusinessMessagesViewController.h"
#import "TGClient.h"
#import "TGTheme.h"
#import "TGStyle.h"
#import "TGAlertSheet.h"
#import "TGIcons.h"

@interface TGBusinessProfileViewController : TGBusinessBaseViewController @end
@interface TGBusinessChatLinksViewController : TGBusinessBaseViewController @end
@interface TGBusinessGreetingViewController : TGBusinessBaseViewController @end
@interface TGBusinessAwayViewController : TGBusinessBaseViewController @end
@interface TGBusinessLocationViewController : TGBusinessBaseViewController @end
@interface TGBusinessHoursViewController : TGBusinessBaseViewController @end
@interface TGBusinessIntroViewController : TGBusinessBaseViewController @end

static NSString *const TGBusinessConnectionDefaultsKey = @"TGBusinessConnectionId";

NSString *TGBusinessStoredConnectionId(void) {
	NSString *value = [[NSUserDefaults standardUserDefaults]
			stringForKey:TGBusinessConnectionDefaultsKey];
	return [value isKindOfClass:NSString.class] ? value : @"";
}

void TGBusinessStoreConnectionId(NSString *connectionId) {
	[[NSUserDefaults standardUserDefaults] setObject:(connectionId ?: @"")
											  forKey:TGBusinessConnectionDefaultsKey];
}

/// The names Telegram's Business page uses for the feature type names the
/// server returns. A feature this wave has no screen for is still listed:
/// saying Telegram included it is more honest than dropping it silently.
static NSString *TGBusinessFeatureTitle(NSString *type) {
	if ([type isEqualToString:@"businessFeatureLocation"]) return @"Location";
	if ([type isEqualToString:@"businessFeatureOpeningHours"]) return @"Opening Hours";
	if ([type isEqualToString:@"businessFeatureQuickReplies"]) return @"Quick Replies";
	if ([type isEqualToString:@"businessFeatureGreetingMessage"]) return @"Greeting Messages";
	if ([type isEqualToString:@"businessFeatureAwayMessage"]) return @"Away Messages";
	if ([type isEqualToString:@"businessFeatureAccountLinks"]) return @"Links to Chat";
	if ([type isEqualToString:@"businessFeatureStartPage"]) return @"Intro";
	if ([type isEqualToString:@"businessFeatureBots"]) return @"Chatbots";
	if ([type isEqualToString:@"businessFeatureEmojiStatus"]) return @"Emoji Status";
	if ([type isEqualToString:@"businessFeatureChatFolderTags"]) return @"Chat Folder Tags";
	if ([type isEqualToString:@"businessFeatureUpgradedStories"]) return @"Upgraded Stories";
	return type ?: @"Feature";
}

/// businessRecipients, as the switches on the greeting and away pages hold
/// it. The defaults are Telegram's "all 1-to-1 chats".
static NSDictionary *TGBusinessRecipients(BOOL existing, BOOL newChats,
										  BOOL contacts, BOOL nonContacts,
										  BOOL excludeSelected) {
	return @{
		@"existing" : @(existing),
		@"new" : @(newChats),
		@"contacts" : @(contacts),
		@"nonContacts" : @(nonContacts),
		@"excludeSelected" : @(excludeSelected),
	};
}

#pragma mark - the shared list screen

@implementation TGBusinessBaseViewController

- (instancetype)init {
	return [super initWithStyle:UITableViewStyleGrouped];
}

- (void)viewDidLoad {
	[super viewDidLoad];
	self.sections = @[];
	if ([self respondsToSelector:@selector(setEdgesForExtendedLayout:)])
		self.edgesForExtendedLayout = UIRectEdgeNone;
	[self applyTheme];
}

- (void)viewWillAppear:(BOOL)animated {
	[super viewWillAppear:animated];
	[self applyTheme];
	[self.tableView reloadData];
}

- (void)applyTheme {
	[[TGTheme shared] styleGroupedTable:self.tableView];
	[[TGTheme shared] styleNavigationBar:self.navigationController.navigationBar];
}

- (void)rebuild {
	[self.tableView reloadData];
}

- (NSDictionary *)rowAt:(NSIndexPath *)path {
	if (path.section >= (NSInteger)self.sections.count)
		return nil;
	NSArray *rows = self.sections[(NSUInteger)path.section][@"rows"];
	return path.row < (NSInteger)rows.count ? rows[(NSUInteger)path.row] : nil;
}

- (void)showResult:(BOOL)ok error:(NSString *)error title:(NSString *)title {
	NSString *text = ok ? @"Telegram accepted the request."
			: (error.length ? error : @"Telegram refused that.");
	[self showMessage:text title:title];
}

- (void)showMessage:(NSString *)message title:(NSString *)title {
	[TGAlertSheet showMessage:message title:title inView:self.view];
}

- (void)askText:(NSString *)title
		message:(NSString *)message
	placeholder:(NSString *)placeholder
		   text:(NSString *)text
		 action:(NSString *)action
	 completion:(void (^)(NSString *))completion {
	[TGAlertSheet showInput:title message:message placeholder:placeholder
					   text:text action:action inView:self.view
				 onSubmit:completion];
}

- (void)didChooseAction:(NSString *)action row:(NSDictionary *)row {}
- (void)toggleKey:(NSString *)key on:(BOOL)on sender:(UISwitch *)sender {}

#pragma mark - table

- (NSString *)tableView:(UITableView *)tableView titleForHeaderInSection:(NSInteger)section {
	NSString *text = self.sections[(NSUInteger)section][@"header"];
	return text.length ? text : nil;
}

- (NSString *)tableView:(UITableView *)tableView titleForFooterInSection:(NSInteger)section {
	NSString *text = self.sections[(NSUInteger)section][@"footer"];
	return text.length ? text : nil;
}

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView {
	return (NSInteger)self.sections.count;
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
	return (NSInteger)[self.sections[(NSUInteger)section][@"rows"] count];
}

- (CGFloat)tableView:(UITableView *)tableView heightForRowAtIndexPath:(NSIndexPath *)path {
	return TGMetricRow;
}

- (UITableViewCell *)tableView:(UITableView *)tableView
		 cellForRowAtIndexPath:(NSIndexPath *)path {
	NSDictionary *row = [self rowAt:path];
	TGTheme *theme = [TGTheme shared];
	TGBusinessRowKind kind = (TGBusinessRowKind)[row[@"kind"] integerValue];

	if (kind == TGBusinessRowSwitch){
		static NSString *reuse = @"switch";
		UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:reuse];
		if (!cell)
			cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleSubtitle
										  reuseIdentifier:reuse];
		[theme styleCell:cell];
		cell.textLabel.font = TGFontRow();
		cell.textLabel.textColor = [theme primaryTextColour];
		cell.detailTextLabel.font = TGFontCaption();
		cell.detailTextLabel.textColor = [theme secondaryTextColour];
		cell.textLabel.text = row[@"title"];
		cell.detailTextLabel.text = row[@"detail"] ?: @"";
		cell.selectionStyle = UITableViewCellSelectionStyleNone;
		UISwitch *toggle = [[UISwitch alloc] init];
		toggle.on = [row[@"on"] boolValue];
		toggle.enabled = [row[@"enabled"] boolValue];
		toggle.tag = (NSInteger)path.section * 1000 + path.row;
		[toggle addTarget:self action:@selector(switchChanged:)
		 forControlEvents:UIControlEventValueChanged];
		cell.accessoryView = toggle;
		return cell;
	}

	static NSString *reuse = @"value";
	UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:reuse];
	if (!cell)
		cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleValue1
									  reuseIdentifier:reuse];
	[theme styleCell:cell];
	cell.textLabel.font = TGFontRow();
	cell.detailTextLabel.font = TGFontBody();
	cell.detailTextLabel.textColor = [theme cellDetailColour];
	cell.textLabel.text = row[@"title"];
	cell.detailTextLabel.text = row[@"detail"] ?: @"";
	BOOL tappable = row[@"action"] != nil;
	cell.accessoryType = tappable ? UITableViewCellAccessoryDisclosureIndicator
								  : UITableViewCellAccessoryNone;
	cell.selectionStyle = tappable ? UITableViewCellSelectionStyleDefault
								   : UITableViewCellSelectionStyleNone;
	cell.textLabel.textColor = kind == TGBusinessRowDestructive
			? [theme destructiveColour] : [theme primaryTextColour];
	return cell;
}

- (void)switchChanged:(UISwitch *)sender {
	NSInteger section = sender.tag / 1000;
	NSInteger item = sender.tag % 1000;
	if (section >= (NSInteger)self.sections.count)
		return;
	NSArray *rows = self.sections[(NSUInteger)section][@"rows"];
	if (item >= (NSInteger)rows.count)
		return;
	NSDictionary *row = rows[(NSUInteger)item];
	[self toggleKey:row[@"switch"] on:sender.on sender:sender];
}

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)path {
	[tableView deselectRowAtIndexPath:path animated:YES];
	NSDictionary *row = [self rowAt:path];
	NSString *action = row[@"action"];
	if (action.length)
		[self didChooseAction:action row:row];
}

@end

#pragma mark - Settings → Telegram Business

@interface TGBusinessViewController ()
@property (nonatomic, strong) NSDictionary *info;
@property (nonatomic, strong) NSArray *features;
@property (nonatomic, copy) NSString *loadError;
@end

@implementation TGBusinessViewController

- (void)viewDidLoad {
	[super viewDidLoad];
	self.title = @"Telegram Business";
	[self load];
}

- (void)load {
	__weak typeof(self) weakSelf = self;
	[[TGClient shared] businessInfoWithCompletion:^(NSDictionary *info, NSString *error){
		TGBusinessViewController *me = weakSelf;
		if (!me)
			return;
		if (error)
			me.loadError = error;
		else
			me.info = info ?: @{};
		[me rebuildSections];
	}];
	[[TGClient shared] businessFeaturesForSource:nil
									  completion:^(NSArray *features, NSString *error){
		TGBusinessViewController *me = weakSelf;
		if (!me)
			return;
		if (error)
			me.loadError = error;
		else
			me.features = features ?: @[];
		[me rebuildSections];
	}];
}

- (NSString *)locationDetail {
	NSString *address = self.info[@"location"][@"address"];
	return address.length ? address : @"Set";
}

- (NSString *)hoursDetail {
	NSArray *intervals = self.info[@"opening_hours"][@"opening_hours"];
	if (![intervals isKindOfClass:NSArray.class] || !intervals.count)
		return @"Off";
	return [NSString stringWithFormat:@"%lu intervals", (unsigned long)intervals.count];
}

- (NSString *)introDetail {
	NSString *title = self.info[@"start_page"][@"title"];
	return title.length ? title : @"Off";
}

- (NSString *)greetingDetail {
	NSDictionary *settings = self.info[@"greeting_message_settings"];
	return [settings isKindOfClass:NSDictionary.class] ? @"On" : @"Off";
}

- (NSString *)awayDetail {
	NSDictionary *settings = self.info[@"away_message_settings"];
	if (![settings isKindOfClass:NSDictionary.class])
		return @"Off";
	NSString *schedule = settings[@"schedule"][@"@type"];
	if ([schedule isEqualToString:@"businessAwayMessageScheduleOutsideOfOpeningHours"])
		return @"Outside hours";
	if ([schedule isEqualToString:@"businessAwayMessageScheduleCustom"])
		return @"Custom schedule";
	return @"Always";
}

- (void)rebuildSections {
	NSDictionary *me = [TGClient shared].me;
	NSString *name = [[NSString stringWithFormat:@"%@ %@",
			me[@"first_name"] ?: @"", me[@"last_name"] ?: @""]
			stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceCharacterSet]];
	if (!name.length)
		name = @"Set up";

	NSMutableArray *sections = [NSMutableArray array];
	[sections addObject:TGBSection(nil,
			@"Business settings apply to this account. Telegram owns the "
			@"feature list; a row Telegram refuses opens with its own sentence "
			@"instead of disappearing.",
			@[
		TGBAction(@"Business Profile", name, @"profile"),
		TGBAction(@"Links to Chat", @"Short links that suggest a first message", @"links"),
	])];

	[sections addObject:TGBSection(@"AUTOMATED MESSAGES", nil, @[
		TGBAction(@"Greeting Messages", [self greetingDetail], @"greeting"),
		TGBAction(@"Away Messages", [self awayDetail], @"away"),
	])];

	[sections addObject:TGBSection(@"BUSINESS INFO", nil, @[
		TGBAction(@"Location", [self locationDetail], @"location"),
		TGBAction(@"Opening Hours", [self hoursDetail], @"hours"),
		TGBAction(@"Intro", [self introDetail], @"intro"),
	])];

	[sections addObject:TGBSection(@"CHATBOTS",
			@"TDLib names business profile and message calls for a business "
			@"bot's connection. A user account has no connection id; these "
			@"pages send the real request and show Telegram's refusal.",
			@[
		TGBAction(@"Business Connection",
				TGBusinessStoredConnectionId().length ? TGBusinessStoredConnectionId() : @"Not set",
				@"connection"),
		TGBAction(@"Business Messages", @"Send, edit, read and pin", @"messages"),
	])];

	NSMutableArray *featureRows = [NSMutableArray array];
	for (NSString *type in self.features)
		[featureRows addObject:TGBInfo(TGBusinessFeatureTitle(type), @"Included")];
	if (!featureRows.count)
		[featureRows addObject:TGBInfo(@"Business features",
				self.loadError.length ? self.loadError : @"Telegram did not list any")];
	[sections addObject:TGBSection(@"BUSINESS FEATURES",
			@"getBusinessFeatures answers what this account may use. A "
			@"subscription adds the rest.", featureRows)];

	self.sections = sections;
	[self rebuild];
}

- (void)didChooseAction:(NSString *)action row:(NSDictionary *)row {
	if ([action isEqualToString:@"profile"]){
		[self push:[[TGBusinessProfileViewController alloc] init]];
	} else if ([action isEqualToString:@"links"]){
		[self push:[[TGBusinessChatLinksViewController alloc] init]];
	} else if ([action isEqualToString:@"greeting"]){
		[self push:[[TGBusinessGreetingViewController alloc] init]];
	} else if ([action isEqualToString:@"away"]){
		[self push:[[TGBusinessAwayViewController alloc] init]];
	} else if ([action isEqualToString:@"location"]){
		[self push:[[TGBusinessLocationViewController alloc] init]];
	} else if ([action isEqualToString:@"hours"]){
		[self push:[[TGBusinessHoursViewController alloc] init]];
	} else if ([action isEqualToString:@"intro"]){
		[self push:[[TGBusinessIntroViewController alloc] init]];
	} else if ([action isEqualToString:@"connection"]){
		[self push:[[TGBusinessConnectionViewController alloc] init]];
	} else if ([action isEqualToString:@"messages"]){
		[self push:[[TGBusinessMessagesViewController alloc] init]];
	}
}

- (void)push:(UIViewController *)page {
	page.hidesBottomBarWhenPushed = YES;
	[self.navigationController pushViewController:page animated:YES];
}

@end

#pragma mark - business profile

@interface TGBusinessProfileViewController () <UIImagePickerControllerDelegate,
		UINavigationControllerDelegate>
@property (nonatomic, copy) NSString *firstName;
@property (nonatomic, copy) NSString *lastName;
@property (nonatomic, copy) NSString *bio;
@property (nonatomic, copy) NSString *username;
@property (nonatomic, assign) BOOL isPublic;
@property (nonatomic, assign) BOOL pickingPhoto;
@end

@implementation TGBusinessProfileViewController

- (void)viewDidLoad {
	[super viewDidLoad];
	self.title = @"Business Profile";
	NSDictionary *me = [TGClient shared].me;
	self.firstName = me[@"first_name"] ?: @"";
	self.lastName = me[@"last_name"] ?: @"";
	self.username = me[@"username"] ?: @"";
	__weak typeof(self) weakSelf = self;
	[[TGClient shared] request:@{
		@"@type" : @"getUserFullInfo",
		@"user_id" : me[@"id"] ?: @(0),
	} completion:^(NSDictionary *full){
		TGBusinessProfileViewController *page = weakSelf;
		if (!page)
			return;
		NSString *bio = full[@"bio"][@"text"];
		if ([bio isKindOfClass:NSString.class])
			page.bio = bio;
		[page rebuildSections];
	}];
	[self rebuildSections];
}

- (void)rebuildSections {
	NSString *name = [[NSString stringWithFormat:@"%@ %@",
			self.firstName ?: @"", self.lastName ?: @""]
			stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceCharacterSet]];
	self.sections = @[
		TGBSection(@"PROFILE",
				@"These fields name the business account. TDLib declares them "
				@"for a business bot's connection; Telegram's refusal is shown "
				@"as it comes.",
				@[
			TGBAction(@"Name", name.length ? name : @"Set", @"firstName"),
			TGBAction(@"Last Name", self.lastName.length ? self.lastName : @"Set", @"lastName"),
			TGBAction(@"Bio", self.bio.length ? self.bio : @"Add a bio", @"bio"),
			TGBAction(@"Username", self.username.length
					? [@"@" stringByAppendingString:self.username] : @"Set", @"username"),
			TGBAction(@"Profile Photo", @"Change or remove", @"photo"),
			TGBSwitch(@"Public Photo",
					@"Visible even when the main photo is hidden by privacy.",
					@"public", self.isPublic, YES),
		]),
		TGBSection(nil, nil, @[
			TGBDestructive(@"Remove Photo", @"removePhoto"),
		]),
	];
	[self rebuild];
}

- (void)didChooseAction:(NSString *)action row:(NSDictionary *)row {
	__weak typeof(self) weakSelf = self;
	if ([action isEqualToString:@"firstName"]){
		[self askText:@"First Name" message:nil placeholder:@"First name"
				 text:self.firstName action:@"Save"
		   completion:^(NSString *text){
			weakSelf.firstName = text;
			[weakSelf saveName];
		}];
	} else if ([action isEqualToString:@"lastName"]){
		[self askText:@"Last Name" message:nil placeholder:@"Last name"
				 text:self.lastName action:@"Save"
		   completion:^(NSString *text){
			weakSelf.lastName = text;
			[weakSelf saveName];
		}];
	} else if ([action isEqualToString:@"bio"]){
		[self askText:@"Bio" message:nil placeholder:@"A few words about the business"
				 text:self.bio action:@"Save"
		   completion:^(NSString *text){
			[[TGClient shared] setBusinessAccountBio:text
										connectionId:TGBusinessStoredConnectionId()
										  completion:^(BOOL ok, NSString *error){
				[weakSelf finishProfileChange:ok error:error title:@"Business Bio"];
			}];
		}];
	} else if ([action isEqualToString:@"username"]){
		NSString *current = self.username.length
				? [@"@" stringByAppendingString:self.username] : @"";
		[self askText:@"Username" message:@"The editable username of the business account."
			placeholder:@"username" text:current action:@"Save"
		   completion:^(NSString *text){
			NSString *username = [text stringByReplacingOccurrencesOfString:@"@" withString:@""];
			[[TGClient shared] setBusinessAccountUsername:username
											 connectionId:TGBusinessStoredConnectionId()
											   completion:^(BOOL ok, NSString *error){
				if (ok)
					weakSelf.username = username;
				[weakSelf finishProfileChange:ok error:error title:@"Business Username"];
			}];
		}];
	} else if ([action isEqualToString:@"photo"]){
		[self pickPhoto];
	} else if ([action isEqualToString:@"removePhoto"]){
		[[TGClient shared] setBusinessAccountProfilePhotoAtPath:nil
													   public:self.isPublic
												   connectionId:TGBusinessStoredConnectionId()
													 completion:^(BOOL ok, NSString *error){
			[weakSelf finishProfileChange:ok error:error title:@"Business Photo"];
		}];
	}
}

- (void)saveName {
	__weak typeof(self) weakSelf = self;
	[[TGClient shared] setBusinessAccountName:self.firstName
										 last:self.lastName
								 connectionId:TGBusinessStoredConnectionId()
								   completion:^(BOOL ok, NSString *error){
		[weakSelf finishProfileChange:ok error:error title:@"Business Name"];
	}];
}

- (void)finishProfileChange:(BOOL)ok error:(NSString *)error title:(NSString *)title {
	[self rebuildSections];
	if (!ok)
		[self showResult:NO error:error title:title];
}

- (void)toggleKey:(NSString *)key on:(BOOL)on sender:(UISwitch *)sender {
	if ([key isEqualToString:@"public"]){
		self.isPublic = on;
		[self rebuildSections];
	}
}

- (void)pickPhoto {
	if (![UIImagePickerController isSourceTypeAvailable:
			UIImagePickerControllerSourceTypePhotoLibrary]){
		[self showMessage:@"The photo library is not on this device."
					 title:@"Business Photo"];
		return;
	}
	self.pickingPhoto = YES;
	UIImagePickerController *picker = [[UIImagePickerController alloc] init];
	picker.sourceType = UIImagePickerControllerSourceTypePhotoLibrary;
	picker.delegate = self;
	[self presentViewController:picker animated:YES completion:nil];
}

- (void)imagePickerController:(UIImagePickerController *)picker
		didFinishPickingMediaWithInfo:(NSDictionary *)info {
	[picker dismissViewControllerAnimated:YES completion:nil];
	if (!self.pickingPhoto)
		return;
	self.pickingPhoto = NO;
	UIImage *image = info[UIImagePickerControllerOriginalImage];
	if (!image)
		return;
	UIImage *scaled = [TGIcons decodedImage:image
								fittingSize:CGSizeMake(TGMetricUploadPhotoSide,
													   TGMetricUploadPhotoSide)
									   fill:NO scale:TGMetricScaleFull];
	NSString *path = [NSTemporaryDirectory()
			stringByAppendingPathComponent:@"business-photo.jpg"];
	if (![UIImageJPEGRepresentation(scaled, TGCompressionQualityStandard)
			writeToFile:path atomically:YES]){
		[self showMessage:@"Could not prepare the picture." title:@"Business Photo"];
		return;
	}
	__weak typeof(self) weakSelf = self;
	[[TGClient shared] setBusinessAccountProfilePhotoAtPath:path
													 public:self.isPublic
												 connectionId:TGBusinessStoredConnectionId()
												   completion:^(BOOL ok, NSString *error){
		[weakSelf finishProfileChange:ok error:error title:@"Business Photo"];
	}];
}

- (void)imagePickerControllerDidCancel:(UIImagePickerController *)picker {
	self.pickingPhoto = NO;
	[picker dismissViewControllerAnimated:YES completion:nil];
}

@end

#pragma mark - links to chat

@interface TGBusinessChatLinksViewController ()
@property (nonatomic, strong) NSArray *links;
@property (nonatomic, copy) NSString *loadError;
@end

@implementation TGBusinessChatLinksViewController

- (void)viewDidLoad {
	[super viewDidLoad];
	self.title = @"Links to Chat";
	[self load];
}

- (void)load {
	__weak typeof(self) weakSelf = self;
	[[TGClient shared] businessChatLinksWithCompletion:^(NSArray *links, NSString *error){
		TGBusinessChatLinksViewController *page = weakSelf;
		if (!page)
			return;
		page.links = links ?: @[];
		page.loadError = error;
		[page rebuildSections];
	}];
}

- (void)rebuildSections {
	NSMutableArray *rows = [NSMutableArray array];
	for (NSDictionary *link in self.links){
		NSString *title = link[@"title"];
		if (!title.length)
			title = link[@"link"] ?: @"Link";
		NSString *text = link[@"text"][@"text"];
		if (!text.length)
			text = @"No preset message";
		NSMutableDictionary *row = [TGBAction(title, text, @"link") mutableCopy];
		row[@"link"] = link;
		[rows addObject:row];
	}
	if (!rows.count){
		[rows addObject:TGBInfo(@"No links",
				self.loadError.length ? self.loadError
						: @"Create one to suggest a first message.")];
	}
	self.sections = @[
		TGBSection(@"LINKS TO CHAT",
				@"Each link starts a chat with this account and puts the text "
				@"in the other person's input field.", rows),
		TGBSection(nil, nil, @[
			TGBAction(@"Create a Link to Chat", nil, @"create"),
		]),
	];
	[self rebuild];
}

- (void)didChooseAction:(NSString *)action row:(NSDictionary *)row {
	if ([action isEqualToString:@"create"]){
		[self createLink];
		return;
	}
	if ([action isEqualToString:@"link"]){
		[self showActionsForLink:row[@"link"]];
	}
}

- (void)createLink {
	__weak typeof(self) weakSelf = self;
	[self askText:@"Create a Link to Chat"
		  message:@"A name only you see first."
	  placeholder:@"Link name" text:nil action:@"Next"
	   completion:^(NSString *title){
		[weakSelf askText:@"Create a Link to Chat"
				  message:@"The message that will be suggested to the other person."
			  placeholder:@"Preset message" text:nil action:@"Create"
			   completion:^(NSString *text){
			[[TGClient shared] createBusinessChatLinkWithText:text title:title
					completion:^(NSDictionary *link, NSString *error){
				TGBusinessChatLinksViewController *page = weakSelf;
				if (!page)
					return;
				if (error.length)
					[page showResult:NO error:error title:@"Links to Chat"];
				[page load];
			}];
		}];
	}];
}

- (void)showActionsForLink:(NSDictionary *)link {
	__weak typeof(self) weakSelf = self;
	[TGAlertSheet showChoices:@[@"Edit", @"Info", @"Delete"]
						title:link[@"title"] ?: @"Link to Chat"
			 destructiveIndex:2
					   inView:self.view
					 onChoice:^(NSInteger index){
		TGBusinessChatLinksViewController *page = weakSelf;
		if (!page)
			return;
		if (index == 0)
			[page editLink:link];
		else if (index == 1)
			[page showInfoForLink:link];
		else
			[page deleteLink:link];
	}];
}

- (void)editLink:(NSDictionary *)link {
	__weak typeof(self) weakSelf = self;
	NSString *title = link[@"title"] ?: @"";
	NSString *text = link[@"text"][@"text"] ?: @"";
	[self askText:@"Edit Link" message:@"The name only you see."
	  placeholder:@"Link name" text:title action:@"Next"
	   completion:^(NSString *newTitle){
		[weakSelf askText:@"Edit Link" message:@"The suggested first message."
			  placeholder:@"Preset message" text:text action:@"Save"
			   completion:^(NSString *newText){
			[[TGClient shared] editBusinessChatLink:link[@"link"]
											   text:newText title:newTitle
										 completion:^(NSDictionary *edited, NSString *error){
				TGBusinessChatLinksViewController *page = weakSelf;
				if (!page)
					return;
				if (error.length)
					[page showResult:NO error:error title:@"Links to Chat"];
				[page load];
			}];
		}];
	}];
}

- (void)showInfoForLink:(NSDictionary *)link {
	__weak typeof(self) weakSelf = self;
	[[TGClient shared] businessChatLinkInfoForName:TGBusinessLinkName(link[@"link"])
										 completion:^(NSDictionary *info, NSString *error){
		TGBusinessChatLinksViewController *page = weakSelf;
		if (!page)
			return;
		if (error.length){
			[page showResult:NO error:error title:@"Link Info"];
			return;
		}
		NSString *text = info[@"text"][@"text"] ?: @"No preset message";
		[page showMessage:[NSString stringWithFormat:
				@"Chat %@\n\n%@", info[@"chat_id"] ?: @0, text]
					 title:@"Link Info"];
	}];
}

- (void)deleteLink:(NSDictionary *)link {
	__weak typeof(self) weakSelf = self;
	[TGAlertSheet showConfirm:@"Anyone using this link will not start a chat with it."
						title:@"Delete Link"
					   action:@"Delete"
				  destructive:YES
					   inView:self.view
					onConfirm:^{
		[[TGClient shared] deleteBusinessChatLink:link[@"link"]
										completion:^(BOOL ok, NSString *error){
			TGBusinessChatLinksViewController *page = weakSelf;
			if (!page)
				return;
			if (!ok)
				[page showResult:NO error:error title:@"Links to Chat"];
			[page load];
		}];
	}];
}

@end

#pragma mark - greeting messages

@interface TGBusinessGreetingViewController ()
@property (nonatomic, assign) BOOL enabled;
@property (nonatomic, assign) NSInteger shortcutId;
@property (nonatomic, assign) NSInteger inactivityDays;
@property (nonatomic, assign) BOOL existing;
@property (nonatomic, assign) BOOL newChats;
@property (nonatomic, assign) BOOL contacts;
@property (nonatomic, assign) BOOL nonContacts;
@property (nonatomic, assign) BOOL excludeSelected;
@property (nonatomic, assign) BOOL loaded;
@end

@implementation TGBusinessGreetingViewController

- (void)viewDidLoad {
	[super viewDidLoad];
	self.title = @"Greeting Messages";
	self.existing = YES;
	self.newChats = YES;
	self.contacts = YES;
	self.nonContacts = YES;
	self.inactivityDays = 7;
	[self load];
}

- (void)load {
	__weak typeof(self) weakSelf = self;
	[[TGClient shared] businessInfoWithCompletion:^(NSDictionary *info, NSString *error){
		TGBusinessGreetingViewController *page = weakSelf;
		if (!page)
			return;
		NSDictionary *settings = info[@"greeting_message_settings"];
		if ([settings isKindOfClass:NSDictionary.class]){
			page.enabled = YES;
			page.shortcutId = [settings[@"shortcut_id"] integerValue];
			page.inactivityDays = [settings[@"inactivity_days"] integerValue];
			page.existing = [settings[@"recipients"][@"select_existing_chats"] boolValue];
			page.newChats = [settings[@"recipients"][@"select_new_chats"] boolValue];
			page.contacts = [settings[@"recipients"][@"select_contacts"] boolValue];
			page.nonContacts = [settings[@"recipients"][@"select_non_contacts"] boolValue];
			page.excludeSelected = [settings[@"recipients"][@"exclude_selected"] boolValue];
		}
		page.loaded = YES;
		[page rebuildSections];
	}];
	[self rebuildSections];
}

- (void)rebuildSections {
	self.sections = @[
		TGBSection(@"GREETING MESSAGE",
				@"Sent when someone messages this account for the first time "
				@"or after the period below.",
				@[
			TGBSwitch(@"Send Greeting Message", nil, @"enabled", self.enabled, YES),
			TGBAction(@"Shortcut ID",
					[NSString stringWithFormat:@"%ld", (long)self.shortcutId],
					@"shortcut"),
			TGBAction(@"Inactivity Days",
					[NSString stringWithFormat:@"%ld", (long)self.inactivityDays],
					@"days"),
		]),
		TGBSection(@"RECIPIENTS",
				@"Telegram applies the greeting to one-to-one chats only.",
				@[
			TGBSwitch(@"Existing Chats", nil, @"existing", self.existing, self.enabled),
			TGBSwitch(@"New Chats", nil, @"new", self.newChats, self.enabled),
			TGBSwitch(@"Contacts", nil, @"contacts", self.contacts, self.enabled),
			TGBSwitch(@"Non-Contacts", nil, @"nonContacts", self.nonContacts, self.enabled),
			TGBSwitch(@"Exclude Selected", nil, @"exclude", self.excludeSelected, self.enabled),
		]),
	];
	[self rebuild];
}

- (NSDictionary *)recipients {
	return TGBusinessRecipients(self.existing, self.newChats, self.contacts,
								self.nonContacts, self.excludeSelected);
}

- (void)save {
	__weak typeof(self) weakSelf = self;
	[[TGClient shared] setBusinessGreetingMessageEnabled:self.enabled
											 shortcutId:self.shortcutId
										 inactivityDays:self.inactivityDays
											 recipients:[self recipients]
											 completion:^(BOOL ok, NSString *error){
		TGBusinessGreetingViewController *page = weakSelf;
		if (!page)
			return;
		if (!ok){
			[page showResult:NO error:error title:@"Greeting Messages"];
			[page load];
			return;
		}
		[page rebuildSections];
	}];
}

- (void)didChooseAction:(NSString *)action row:(NSDictionary *)row {
	__weak typeof(self) weakSelf = self;
	if ([action isEqualToString:@"shortcut"]){
		[self askText:@"Shortcut ID"
			  message:@"The quick reply shortcut that holds the greeting text."
		  placeholder:@"1" text:[NSString stringWithFormat:@"%ld", (long)self.shortcutId]
			   action:@"Save" completion:^(NSString *text){
			weakSelf.shortcutId = [text integerValue];
			[weakSelf save];
		}];
	} else if ([action isEqualToString:@"days"]){
		[self askText:@"Inactivity Days"
			  message:@"Days without an interaction before the greeting is sent."
		  placeholder:@"7" text:[NSString stringWithFormat:@"%ld", (long)self.inactivityDays]
			   action:@"Save" completion:^(NSString *text){
			weakSelf.inactivityDays = MAX(0, [text integerValue]);
			[weakSelf save];
		}];
	}
}

- (void)toggleKey:(NSString *)key on:(BOOL)on sender:(UISwitch *)sender {
	if ([key isEqualToString:@"enabled"]) self.enabled = on;
	else if ([key isEqualToString:@"existing"]) self.existing = on;
	else if ([key isEqualToString:@"new"]) self.newChats = on;
	else if ([key isEqualToString:@"contacts"]) self.contacts = on;
	else if ([key isEqualToString:@"nonContacts"]) self.nonContacts = on;
	else if ([key isEqualToString:@"exclude"]) self.excludeSelected = on;
	[self save];
}

@end

#pragma mark - away messages

@interface TGBusinessAwayViewController ()
@property (nonatomic, assign) BOOL enabled;
@property (nonatomic, assign) NSInteger shortcutId;
@property (nonatomic, copy) NSString *schedule;
@property (nonatomic, assign) int32_t startDate;
@property (nonatomic, assign) int32_t endDate;
@property (nonatomic, assign) BOOL offlineOnly;
@property (nonatomic, assign) BOOL existing;
@property (nonatomic, assign) BOOL newChats;
@property (nonatomic, assign) BOOL contacts;
@property (nonatomic, assign) BOOL nonContacts;
@property (nonatomic, assign) BOOL excludeSelected;
@end

@implementation TGBusinessAwayViewController

- (void)viewDidLoad {
	[super viewDidLoad];
	self.title = @"Away Messages";
	self.schedule = @"always";
	self.existing = YES;
	self.newChats = YES;
	self.contacts = YES;
	self.nonContacts = YES;
	self.startDate = (int32_t)[NSDate date].timeIntervalSince1970;
	self.endDate = self.startDate + 86400;
	[self load];
}

- (void)load {
	__weak typeof(self) weakSelf = self;
	[[TGClient shared] businessInfoWithCompletion:^(NSDictionary *info, NSString *error){
		TGBusinessAwayViewController *page = weakSelf;
		if (!page)
			return;
		NSDictionary *settings = info[@"away_message_settings"];
		if ([settings isKindOfClass:NSDictionary.class]){
			page.enabled = YES;
			page.shortcutId = [settings[@"shortcut_id"] integerValue];
			page.offlineOnly = [settings[@"offline_only"] boolValue];
			NSString *type = settings[@"schedule"][@"@type"];
			if ([type isEqualToString:@"businessAwayMessageScheduleOutsideOfOpeningHours"])
				page.schedule = @"outside";
			else if ([type isEqualToString:@"businessAwayMessageScheduleCustom"]){
				page.schedule = @"custom";
				page.startDate = [settings[@"schedule"][@"start_date"] intValue];
				page.endDate = [settings[@"schedule"][@"end_date"] intValue];
			} else
				page.schedule = @"always";
			page.existing = [settings[@"recipients"][@"select_existing_chats"] boolValue];
			page.newChats = [settings[@"recipients"][@"select_new_chats"] boolValue];
			page.contacts = [settings[@"recipients"][@"select_contacts"] boolValue];
			page.nonContacts = [settings[@"recipients"][@"select_non_contacts"] boolValue];
			page.excludeSelected = [settings[@"recipients"][@"exclude_selected"] boolValue];
		}
		[page rebuildSections];
	}];
	[self rebuildSections];
}

- (NSString *)scheduleDetail {
	if ([self.schedule isEqualToString:@"outside"]) return @"Outside of Business Hours";
	if ([self.schedule isEqualToString:@"custom"]) return @"Custom Schedule";
	return @"Always Send";
}

- (void)rebuildSections {
	NSMutableArray *rows = [NSMutableArray array];
	[rows addObject:TGBSwitch(@"Send Away Message", nil, @"enabled", self.enabled, YES)];
	[rows addObject:TGBAction(@"Shortcut ID",
			[NSString stringWithFormat:@"%ld", (long)self.shortcutId], @"shortcut")];
	[rows addObject:TGBAction(@"Schedule", [self scheduleDetail], @"schedule")];
	if ([self.schedule isEqualToString:@"custom"]){
		[rows addObject:TGBAction(@"Start Time",
				[NSString stringWithFormat:@"%d", self.startDate], @"start")];
		[rows addObject:TGBAction(@"End Time",
				[NSString stringWithFormat:@"%d", self.endDate], @"end")];
	}
	self.sections = @[
		TGBSection(@"AWAY MESSAGE",
				@"Automatically reply with a message when this account is away.",
				rows),
		TGBSection(@"SCHEDULE",
				@"Custom times are unix seconds, which is what TDLib carries.",
				@[
			TGBSwitch(@"Only if Offline",
					@"Do not send the away message if you were recently online.",
					@"offline", self.offlineOnly, self.enabled),
		]),
		TGBSection(@"RECIPIENTS", nil, @[
			TGBSwitch(@"Existing Chats", nil, @"existing", self.existing, self.enabled),
			TGBSwitch(@"New Chats", nil, @"new", self.newChats, self.enabled),
			TGBSwitch(@"Contacts", nil, @"contacts", self.contacts, self.enabled),
			TGBSwitch(@"Non-Contacts", nil, @"nonContacts", self.nonContacts, self.enabled),
			TGBSwitch(@"Exclude Selected", nil, @"exclude", self.excludeSelected, self.enabled),
		]),
	];
	[self rebuild];
}

- (NSDictionary *)recipients {
	return TGBusinessRecipients(self.existing, self.newChats, self.contacts,
								self.nonContacts, self.excludeSelected);
}

- (void)save {
	__weak typeof(self) weakSelf = self;
	[[TGClient shared] setBusinessAwayMessageEnabled:self.enabled
										 shortcutId:self.shortcutId
										   schedule:self.schedule
										  startDate:self.startDate
											endDate:self.endDate
										offlineOnly:self.offlineOnly
										 recipients:[self recipients]
										 completion:^(BOOL ok, NSString *error){
		TGBusinessAwayViewController *page = weakSelf;
		if (!page)
			return;
		if (!ok){
			[page showResult:NO error:error title:@"Away Messages"];
			[page load];
			return;
		}
		[page rebuildSections];
	}];
}

- (void)didChooseAction:(NSString *)action row:(NSDictionary *)row {
	__weak typeof(self) weakSelf = self;
	if ([action isEqualToString:@"shortcut"]){
		[self askText:@"Shortcut ID"
			  message:@"The quick reply shortcut that holds the away text."
		  placeholder:@"1" text:[NSString stringWithFormat:@"%ld", (long)self.shortcutId]
			   action:@"Save" completion:^(NSString *text){
			weakSelf.shortcutId = [text integerValue];
			[weakSelf save];
		}];
	} else if ([action isEqualToString:@"schedule"]){
		[TGAlertSheet showChoices:@[@"Always Send", @"Outside of Business Hours",
									@"Custom Schedule"]
							title:@"Away Schedule"
				 destructiveIndex:-1 inView:self.view
						 onChoice:^(NSInteger index){
			weakSelf.schedule = index == 1 ? @"outside"
					: (index == 2 ? @"custom" : @"always");
			[weakSelf save];
		}];
	} else if ([action isEqualToString:@"start"] || [action isEqualToString:@"end"]){
		BOOL start = [action isEqualToString:@"start"];
		[self askText:start ? @"Start Time" : @"End Time"
			  message:@"Unix seconds."
		  placeholder:@"1700000000"
				 text:[NSString stringWithFormat:@"%d", start ? self.startDate : self.endDate]
			   action:@"Save" completion:^(NSString *text){
			if (start) weakSelf.startDate = (int32_t)[text longLongValue];
			else       weakSelf.endDate = (int32_t)[text longLongValue];
			[weakSelf save];
		}];
	}
}

- (void)toggleKey:(NSString *)key on:(BOOL)on sender:(UISwitch *)sender {
	if ([key isEqualToString:@"enabled"]) self.enabled = on;
	else if ([key isEqualToString:@"offline"]) self.offlineOnly = on;
	else if ([key isEqualToString:@"existing"]) self.existing = on;
	else if ([key isEqualToString:@"new"]) self.newChats = on;
	else if ([key isEqualToString:@"contacts"]) self.contacts = on;
	else if ([key isEqualToString:@"nonContacts"]) self.nonContacts = on;
	else if ([key isEqualToString:@"exclude"]) self.excludeSelected = on;
	[self save];
}

@end

#pragma mark - opening hours

@interface TGBusinessHoursViewController ()
@property (nonatomic, assign) BOOL enabled;
@property (nonatomic, assign) NSInteger startHour;
@property (nonatomic, assign) NSInteger endHour;
@property (nonatomic, strong) NSMutableArray *days;
@end

@implementation TGBusinessHoursViewController

- (void)viewDidLoad {
	[super viewDidLoad];
	self.title = @"Business Hours";
	self.startHour = 9;
	self.endHour = 18;
	self.days = [NSMutableArray arrayWithArray:@[@YES, @YES, @YES, @YES, @YES, @NO, @NO]];
	[self load];
}

- (void)load {
	__weak typeof(self) weakSelf = self;
	[[TGClient shared] businessInfoWithCompletion:^(NSDictionary *info, NSString *error){
		TGBusinessHoursViewController *page = weakSelf;
		if (!page)
			return;
		NSArray *intervals = info[@"opening_hours"][@"opening_hours"];
		if ([intervals isKindOfClass:NSArray.class] && intervals.count){
			page.enabled = YES;
			[page.days replaceObjectAtIndex:0 withObject:@NO];
			[page.days replaceObjectAtIndex:1 withObject:@NO];
			[page.days replaceObjectAtIndex:2 withObject:@NO];
			[page.days replaceObjectAtIndex:3 withObject:@NO];
			[page.days replaceObjectAtIndex:4 withObject:@NO];
			[page.days replaceObjectAtIndex:5 withObject:@NO];
			[page.days replaceObjectAtIndex:6 withObject:@NO];
			BOOL first = YES;
			for (NSDictionary *interval in intervals){
				NSInteger start = [interval[@"start_minute"] integerValue];
				NSInteger end = [interval[@"end_minute"] integerValue];
				if (first){
					page.startHour = (start % 1440) / 60;
					page.endHour = (end % 1440) / 60;
					first = NO;
				}
				NSInteger day = start / 1440;
				if (day >= 0 && day < 7)
					[page.days replaceObjectAtIndex:(NSUInteger)day withObject:@YES];
			}
		}
		[page rebuildSections];
	}];
	[self rebuildSections];
}

- (void)rebuildSections {
	NSMutableArray *dayRows = [NSMutableArray array];
	for (NSInteger day = 0; day < 7; day++)
		[dayRows addObject:TGBSwitch(TGBDayName(day), nil,
				[NSString stringWithFormat:@"day%ld", (long)day],
				[self.days[(NSUInteger)day] boolValue], self.enabled)];
	self.sections = @[
		TGBSection(@"BUSINESS HOURS",
				@"Turn this on to show an opening-hours schedule to customers.",
				@[
			TGBSwitch(@"Show Business Hours", nil, @"enabled", self.enabled, YES),
			TGBInfo(@"Time Zone", [NSTimeZone localTimeZone].name ?: @"UTC"),
			TGBAction(@"Daily Hours", [NSString stringWithFormat:@"%@ to %@",
					TGBClockTime(self.startHour * 60), TGBClockTime(self.endHour * 60)],
					@"hours"),
		]),
		TGBSection(@"DAYS OPEN", @"The schedule is sent as one interval per open day.",
				dayRows),
	];
	[self rebuild];
}

- (NSDictionary *)openingHours {
	NSMutableArray *intervals = [NSMutableArray array];
	for (NSInteger day = 0; day < 7; day++){
		if (![self.days[(NSUInteger)day] boolValue])
			continue;
		NSInteger start = day * 1440 + self.startHour * 60;
		NSInteger end = day * 1440 + self.endHour * 60;
		if (end <= start)
			end = start + 60;
		[intervals addObject:@{@"@type" : @"businessOpeningHoursInterval",
							   @"start_minute" : @(start),
							   @"end_minute" : @(end)}];
	}
	return @{@"timeZone" : [NSTimeZone localTimeZone].name ?: @"UTC",
			 @"intervals" : intervals};
}

- (void)save {
	NSDictionary *object = [self openingHours];
	__weak typeof(self) weakSelf = self;
	[[TGClient shared] setBusinessOpeningHoursTimeZone:object[@"timeZone"]
											 intervals:self.enabled ? object[@"intervals"] : nil
											completion:^(BOOL ok, NSString *error){
		TGBusinessHoursViewController *page = weakSelf;
		if (!page)
			return;
		if (!ok){
			[page showResult:NO error:error title:@"Business Hours"];
			[page load];
			return;
		}
		[page rebuildSections];
	}];
}

- (void)didChooseAction:(NSString *)action row:(NSDictionary *)row {
	if (![action isEqualToString:@"hours"])
		return;
	__weak typeof(self) weakSelf = self;
	[self askText:@"Opening Time" message:@"Hour of the day, 0 to 23."
	  placeholder:@"9" text:[NSString stringWithFormat:@"%ld", (long)self.startHour]
		   action:@"Next" completion:^(NSString *text){
		NSInteger start = MAX(0, MIN(23, [text integerValue]));
		[weakSelf askText:@"Closing Time" message:@"Hour of the day, 0 to 23."
			  placeholder:@"18" text:[NSString stringWithFormat:@"%ld", (long)weakSelf.endHour]
				   action:@"Save" completion:^(NSString *close){
			weakSelf.startHour = start;
			weakSelf.endHour = MAX(0, MIN(23, [close integerValue]));
			if (weakSelf.endHour <= weakSelf.startHour)
				weakSelf.endHour = MIN(23, weakSelf.startHour + 1);
			[weakSelf save];
		}];
	}];
}

- (void)toggleKey:(NSString *)key on:(BOOL)on sender:(UISwitch *)sender {
	if ([key isEqualToString:@"enabled"]){
		self.enabled = on;
		[self save];
		return;
	}
	if ([key hasPrefix:@"day"]){
		NSInteger day = [[key substringFromIndex:3] integerValue];
		if (day >= 0 && day < 7)
			[self.days replaceObjectAtIndex:(NSUInteger)day withObject:@(on)];
		[self save];
	}
}

@end

#pragma mark - location

@interface TGBusinessLocationViewController ()
@property (nonatomic, copy) NSString *address;
@property (nonatomic, strong) NSNumber *latitude;
@property (nonatomic, strong) NSNumber *longitude;
@end

@implementation TGBusinessLocationViewController

- (void)viewDidLoad {
	[super viewDidLoad];
	self.title = @"Location";
	__weak typeof(self) weakSelf = self;
	[[TGClient shared] businessInfoWithCompletion:^(NSDictionary *info, NSString *error){
		TGBusinessLocationViewController *page = weakSelf;
		if (!page)
			return;
		page.address = [info[@"location"][@"address"] isKindOfClass:NSString.class]
				? info[@"location"][@"address"] : @"";
		id latitude = info[@"location"][@"location"][@"latitude"];
		id longitude = info[@"location"][@"location"][@"longitude"];
		page.latitude = [latitude isKindOfClass:NSNumber.class] ? latitude : nil;
		page.longitude = [longitude isKindOfClass:NSNumber.class] ? longitude : nil;
		[page rebuildSections];
	}];
	[self rebuildSections];
}

- (void)rebuildSections {
	NSString *coordinates = self.latitude && self.longitude
			? [NSString stringWithFormat:@"%.4f, %.4f",
					self.latitude.doubleValue, self.longitude.doubleValue]
			: @"Not set";
	self.sections = @[
		TGBSection(@"LOCATION",
				@"Display the location of the business on this account.",
				@[
			TGBAction(@"Address", self.address.length ? self.address : @"Enter Address",
					@"address"),
			TGBAction(@"Coordinates", coordinates, @"coordinates"),
			TGBAction(@"Save Location", nil, @"save"),
		]),
		TGBSection(nil, nil, @[
			TGBDestructive(@"Delete Location", @"delete"),
		]),
	];
	[self rebuild];
}

- (void)didChooseAction:(NSString *)action row:(NSDictionary *)row {
	__weak typeof(self) weakSelf = self;
	if ([action isEqualToString:@"address"]){
		[self askText:@"Address" message:nil placeholder:@"Enter Address"
				 text:self.address action:@"Save" completion:^(NSString *text){
			weakSelf.address = text;
			[weakSelf rebuildSections];
		}];
	} else if ([action isEqualToString:@"coordinates"]){
		[self askText:@"Latitude" message:@"Decimal degrees."
		  placeholder:@"50.4501"
				 text:self.latitude ? [NSString stringWithFormat:@"%.6f",
						 self.latitude.doubleValue] : nil
			   action:@"Next" completion:^(NSString *text){
			NSNumber *latitude = @([text doubleValue]);
			[weakSelf askText:@"Longitude" message:@"Decimal degrees."
				  placeholder:@"30.5234"
						 text:weakSelf.longitude ? [NSString stringWithFormat:@"%.6f",
								 weakSelf.longitude.doubleValue] : nil
					   action:@"Save" completion:^(NSString *lon){
				weakSelf.latitude = latitude;
				weakSelf.longitude = @([lon doubleValue]);
				[weakSelf rebuildSections];
			}];
		}];
	} else if ([action isEqualToString:@"save"]){
		if (!self.latitude || !self.longitude){
			[self showMessage:@"Set the coordinates before saving; Telegram needs a point on the map."
						 title:@"Location"];
			return;
		}
		[[TGClient shared] setBusinessLocationLatitude:self.latitude
											 longitude:self.longitude
											   address:self.address
											completion:^(BOOL ok, NSString *error){
			[weakSelf showResult:ok error:error title:@"Location"];
		}];
	} else if ([action isEqualToString:@"delete"]){
		[[TGClient shared] setBusinessLocationLatitude:nil longitude:nil address:nil
											completion:^(BOOL ok, NSString *error){
			TGBusinessLocationViewController *page = weakSelf;
			if (!ok){
				[page showResult:NO error:error title:@"Location"];
				return;
			}
			page.address = @"";
			page.latitude = nil;
			page.longitude = nil;
			[page rebuildSections];
		}];
	}
}

@end

#pragma mark - intro

@interface TGBusinessIntroViewController () <UIImagePickerControllerDelegate,
		UINavigationControllerDelegate>
@property (nonatomic, copy) NSString *introTitle;
@property (nonatomic, copy) NSString *introMessage;
@property (nonatomic, copy) NSString *stickerPath;
@property (nonatomic, assign) BOOL pickingSticker;
@end

@implementation TGBusinessIntroViewController

- (void)viewDidLoad {
	[super viewDidLoad];
	self.title = @"Intro";
	__weak typeof(self) weakSelf = self;
	[[TGClient shared] businessInfoWithCompletion:^(NSDictionary *info, NSString *error){
		TGBusinessIntroViewController *page = weakSelf;
		if (!page)
			return;
		page.introTitle = [info[@"start_page"][@"title"] isKindOfClass:NSString.class]
				? info[@"start_page"][@"title"] : @"";
		page.introMessage = [info[@"start_page"][@"message"] isKindOfClass:NSString.class]
				? info[@"start_page"][@"message"] : @"";
		[page rebuildSections];
	}];
	[self rebuildSections];
}

- (void)rebuildSections {
	self.sections = @[
		TGBSection(@"CUSTOMIZE YOUR INTRO",
				@"The message people see before they start a chat with this account.",
				@[
			TGBAction(@"Title", self.introTitle.length ? self.introTitle : @"Set",
					@"title"),
			TGBAction(@"Message", self.introMessage.length ? self.introMessage : @"Enter Message",
					@"message"),
			TGBAction(@"Sticker", self.stickerPath.length ? @"Chosen" : @"Choose Sticker",
					@"sticker"),
			TGBAction(@"Save Intro", nil, @"save"),
		]),
		TGBSection(nil, nil, @[
			TGBDestructive(@"Reset to Default", @"reset"),
		]),
	];
	[self rebuild];
}

- (void)didChooseAction:(NSString *)action row:(NSDictionary *)row {
	__weak typeof(self) weakSelf = self;
	if ([action isEqualToString:@"title"]){
		[self askText:@"Intro Title" message:nil placeholder:@"Title"
				 text:self.introTitle action:@"Save" completion:^(NSString *text){
			weakSelf.introTitle = text;
			[weakSelf rebuildSections];
		}];
	} else if ([action isEqualToString:@"message"]){
		[self askText:@"Intro Message" message:nil placeholder:@"Enter Message"
				 text:self.introMessage action:@"Save" completion:^(NSString *text){
			weakSelf.introMessage = text;
			[weakSelf rebuildSections];
		}];
	} else if ([action isEqualToString:@"sticker"]){
		[self pickSticker];
	} else if ([action isEqualToString:@"save"]){
		if (!self.introTitle.length || !self.introMessage.length){
			[self showMessage:@"An intro needs a title and a message." title:@"Intro"];
			return;
		}
		[[TGClient shared] setBusinessStartPageTitle:self.introTitle
											 message:self.introMessage
										 stickerPath:self.stickerPath
										  completion:^(BOOL ok, NSString *error){
			[weakSelf showResult:ok error:error title:@"Intro"];
		}];
	} else if ([action isEqualToString:@"reset"]){
		[[TGClient shared] setBusinessStartPageTitle:nil message:nil stickerPath:nil
										  completion:^(BOOL ok, NSString *error){
			TGBusinessIntroViewController *page = weakSelf;
			if (!ok){
				[page showResult:NO error:error title:@"Intro"];
				return;
			}
			page.introTitle = @"";
			page.introMessage = @"";
			page.stickerPath = nil;
			[page rebuildSections];
		}];
	}
}

- (void)pickSticker {
	if (![UIImagePickerController isSourceTypeAvailable:
			UIImagePickerControllerSourceTypePhotoLibrary]){
		[self showMessage:@"The photo library is not on this device." title:@"Intro"];
		return;
	}
	self.pickingSticker = YES;
	UIImagePickerController *picker = [[UIImagePickerController alloc] init];
	picker.sourceType = UIImagePickerControllerSourceTypePhotoLibrary;
	picker.delegate = self;
	[self presentViewController:picker animated:YES completion:nil];
}

- (void)imagePickerController:(UIImagePickerController *)picker
		didFinishPickingMediaWithInfo:(NSDictionary *)info {
	[picker dismissViewControllerAnimated:YES completion:nil];
	if (!self.pickingSticker)
		return;
	self.pickingSticker = NO;
	UIImage *image = info[UIImagePickerControllerOriginalImage];
	if (!image)
		return;
	NSString *path = [NSTemporaryDirectory()
			stringByAppendingPathComponent:@"business-intro.jpg"];
	if (![UIImageJPEGRepresentation(image, TGCompressionQualityStandard)
			writeToFile:path atomically:YES]){
		[self showMessage:@"Could not prepare the picture." title:@"Intro"];
		return;
	}
	self.stickerPath = path;
	[self rebuildSections];
}

- (void)imagePickerControllerDidCancel:(UIImagePickerController *)picker {
	self.pickingSticker = NO;
	[picker dismissViewControllerAnimated:YES completion:nil];
}

@end

// vim:ft=objc
