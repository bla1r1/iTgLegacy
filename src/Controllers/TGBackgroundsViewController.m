//
// TGBackgroundsViewController.m - the background catalogue.
//
// Telegram keeps two lists (light and dark) of the backgrounds an account has
// installed, and one default behind the chat. The screen draws the list it is
// looking at, searches the public catalogue by name, and sends every change
// back through TDLib. A found background is drawn with its own thumbnail or,
// when Telegram stores it as a colour, a swatch of that colour.
//
#import "TGBackgroundsViewController.h"
#import "TGClient.h"
#import "TGAlertSheet.h"
#import "TGStyle.h"
#import "TGTheme.h"
#import <QuartzCore/QuartzCore.h>

static NSMutableDictionary *TGBRow(NSString *kind, NSString *title) {
	return [@{@"kind" : kind, @"title" : title ?: @""} mutableCopy];
}

static NSDictionary *TGBCellRow(NSString *title, NSString *detail, NSString *action) {
	NSMutableDictionary *row = TGBRow(@"action", title);
	if (detail) row[@"detail"] = detail;
	if (action) row[@"action"] = action;
	return row;
}

static NSDictionary *TGBSection(NSString *header, NSString *footer, NSArray *rows) {
	NSMutableDictionary *section = [NSMutableDictionary dictionary];
	if (header) section[@"header"] = header;
	if (footer) section[@"footer"] = footer;
	section[@"rows"] = rows ?: @[];
	return section;
}

/// TDLib's RGB integer as a colour. This is server data - the colour Telegram
/// itself draws the background with - not a design token, which is why it is
/// built here rather than added to the theme palette.
static UIColor *TGBackgroundColour(NSInteger rgb) {
	CGFloat red   = (CGFloat)((rgb >> 16) & 0xFF) / 255.0f;
	CGFloat green = (CGFloat)((rgb >> 8) & 0xFF) / 255.0f;
	CGFloat blue  = (CGFloat)(rgb & 0xFF) / 255.0f;
	return [UIColor colorWithRed:red green:green blue:blue alpha:1.0f];
}

/// A square cell picture: the downloaded thumbnail when there is one, the
/// background's colour otherwise. Backgrounds are pictures or fills; a row
/// with neither would be a blank line in a list about how things look.
static UIImage *TGBackgroundPreview(UIImage *source, NSInteger fillColour) {
	CGFloat side = TGMetricListAvatar;
	CGSize box = CGSizeMake(side, side);
	UIGraphicsBeginImageContextWithOptions(box, YES, 0);
	UIColor *fallback = fillColour >= 0
			? TGBackgroundColour(fillColour)
			: [[TGTheme shared] groupedBackgroundColour];
	[fallback setFill];
	UIRectFill(CGRectMake(0, 0, side, side));
	if (source && source.size.width > 0 && source.size.height > 0){
		// Aspect fill: a wallpaper thumbnail is usually wider than a row
		// picture, and squashing it would show the wrong shape.
		CGFloat scale = MAX(side / source.size.width, side / source.size.height);
		CGSize drawn = CGSizeMake(source.size.width * scale,
				source.size.height * scale);
		[source drawInRect:CGRectMake(TGCenteredOrigin(side, drawn.width),
				TGCenteredOrigin(side, drawn.height),
				drawn.width, drawn.height)];
	}
	UIImage *image = UIGraphicsGetImageFromCurrentImageContext();
	UIGraphicsEndImageContext();
	return image;
}

@interface TGBackgroundsViewController ()
@property (nonatomic, strong) NSArray *sections;
@property (nonatomic, strong) NSArray *installed;
@property (nonatomic, strong) NSDictionary *found;
@property (nonatomic, copy) NSString *loadError;
@property (nonatomic, copy) NSString *searchError;
@property (nonatomic, copy) NSString *status;
@property (nonatomic, assign) BOOL darkTheme;
@property (nonatomic, strong) NSMutableDictionary *previews;   // background id -> UIImage
@property (nonatomic, strong) NSMutableSet *requested;         // background id
@end

@implementation TGBackgroundsViewController

- (instancetype)init {
	return [super initWithStyle:UITableViewStyleGrouped];
}

- (void)viewDidLoad {
	[super viewDidLoad];
	self.title = @"Chat Backgrounds";
	if ([self respondsToSelector:@selector(setEdgesForExtendedLayout:)])
		self.edgesForExtendedLayout = UIRectEdgeNone;
	self.installed = @[];
	self.previews = [NSMutableDictionary dictionary];
	self.requested = [NSMutableSet set];
	[self applyTheme];
	[self loadInstalled];

	__weak typeof(self) weakSelf = self;
	[[NSNotificationCenter defaultCenter] addObserverForName:TGThemeChangedNotification
			object:nil queue:[NSOperationQueue mainQueue]
		 usingBlock:^(NSNotification *note){
		[weakSelf applyTheme];
		[weakSelf.tableView reloadData];
	}];
}

- (void)dealloc {
	[[NSNotificationCenter defaultCenter] removeObserver:self];
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

#pragma mark - loading

- (void)loadInstalled {
	__weak typeof(self) weakSelf = self;
	[[TGClient shared] installedBackgroundsForDarkTheme:self.darkTheme
			completion:^(NSArray *backgrounds, NSString *error){
		weakSelf.installed = backgrounds ?: @[];
		weakSelf.loadError = error;
		[weakSelf rebuild];
	}];
}

- (void)rebuild {
	self.sections = [self buildSections];
	[self.tableView reloadData];
}

#pragma mark - sections

- (NSArray *)buildSections {
	NSMutableArray *sections = [NSMutableArray array];

	NSMutableDictionary *themeRow = TGBRow(@"switch", @"Dark Theme Backgrounds");
	themeRow[@"on"] = @(self.darkTheme);
	[sections addObject:TGBSection(@"THEME",
			@"Telegram keeps a separate installed list and default for the dark "
			@"theme. This switch chooses which one this page edits.",
			@[themeRow])];

	NSMutableArray *installedRows = [NSMutableArray array];
	if (self.loadError.length)
		[installedRows addObject:TGBRow(@"plain", self.loadError)];
	else if (!self.installed.count)
		[installedRows addObject:TGBRow(@"plain", @"No backgrounds installed.")];
	else {
		for (NSDictionary *background in self.installed){
			NSMutableDictionary *row = TGBRow(@"background", background[@"title"] ?: background[@"name"]);
			row[@"background"] = background;
			row[@"installed"] = @YES;
			[installedRows addObject:row];
		}
	}
	[sections addObject:TGBSection(@"INSTALLED",
			@"Tap a background to make it the default, read its address, or "
			@"remove it from this list.", installedRows)];

	NSMutableArray *searchRows = [NSMutableArray array];
	[searchRows addObject:TGBCellRow(@"Search Telegram's Backgrounds",
			@"By name", @"search")];
	if (self.searchError.length)
		[searchRows addObject:TGBRow(@"plain", self.searchError)];
	if (self.found){
		NSMutableDictionary *row = TGBRow(@"background", self.found[@"title"] ?: self.found[@"name"]);
		row[@"background"] = self.found;
		row[@"installed"] = @NO;
		[searchRows addObject:row];
	}
	[sections addObject:TGBSection(@"CATALOGUE",
			@"Searches Telegram's public background catalogue. A result can be "
			@"installed or its persistent address copied.", searchRows)];

	NSMutableArray *defaultRows = [NSMutableArray array];
	[defaultRows addObject:TGBCellRow(@"Delete Default Background", nil,
			@"deleteDefault")];
	[defaultRows addObject:TGBCellRow(@"Reset Installed Backgrounds", nil,
			@"reset")];
	[sections addObject:TGBSection(@"DEFAULT",
			@"Deleting the default puts chats back on Telegram's own background. "
			@"Reset restores the installed list without touching the default.",
			defaultRows)];

	if (self.status.length)
		[sections addObject:TGBSection(@"LAST ANSWER", nil,
				@[TGBRow(@"plain", self.status)])];

	return sections;
}

#pragma mark - table

- (NSDictionary *)rowAt:(NSIndexPath *)indexPath {
	if (indexPath.section >= (NSInteger)self.sections.count)
		return nil;
	NSArray *rows = self.sections[(NSUInteger)indexPath.section][@"rows"];
	return indexPath.row < (NSInteger)rows.count ? rows[(NSUInteger)indexPath.row] : nil;
}

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView {
	return (NSInteger)self.sections.count;
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
	return (NSInteger)[self.sections[(NSUInteger)section][@"rows"] count];
}

- (NSString *)tableView:(UITableView *)tableView titleForHeaderInSection:(NSInteger)section {
	NSString *text = self.sections[(NSUInteger)section][@"header"];
	return text.length ? text : nil;
}

- (NSString *)tableView:(UITableView *)tableView titleForFooterInSection:(NSInteger)section {
	NSString *text = self.sections[(NSUInteger)section][@"footer"];
	return text.length ? text : nil;
}

- (CGFloat)tableView:(UITableView *)tableView heightForRowAtIndexPath:(NSIndexPath *)indexPath {
	NSDictionary *row = [self rowAt:indexPath];
	if ([row[@"kind"] isEqualToString:@"background"])
		return TGMetricPersonRow;
	return TGMetricRow;
}

- (UITableViewCell *)tableView:(UITableView *)tableView
		 cellForRowAtIndexPath:(NSIndexPath *)indexPath {
	NSDictionary *row = [self rowAt:indexPath];
	TGTheme *theme = [TGTheme shared];
	NSString *kind = row[@"kind"];

	if ([kind isEqualToString:@"switch"]){
		UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:@"switch"];
		if (!cell){
			cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleDefault
										  reuseIdentifier:@"switch"];
			[theme styleCell:cell];
			cell.selectionStyle = UITableViewCellSelectionStyleNone;
		}
		cell.textLabel.text = row[@"title"];
		cell.textLabel.font = TGFontRow();
		cell.textLabel.textColor = [theme primaryTextColour];
		cell.backgroundColor = [theme cardBackgroundColour];
		UISwitch *toggle = [[UISwitch alloc] init];
		toggle.on = [row[@"on"] boolValue];
		[toggle addTarget:self action:@selector(darkThemeToggled:)
		 forControlEvents:UIControlEventValueChanged];
		cell.accessoryView = toggle;
		return cell;
	}

	if ([kind isEqualToString:@"background"]){
		UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:@"background"];
		if (!cell){
			cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleSubtitle
										  reuseIdentifier:@"background"];
			[theme styleCell:cell];
		}
		NSDictionary *background = row[@"background"];
		cell.textLabel.text = row[@"title"];
		cell.textLabel.font = TGFontRow();
		cell.textLabel.textColor = [theme primaryTextColour];

		NSMutableArray *parts = [NSMutableArray array];
		if ([background[@"isDefault"] boolValue])
			[parts addObject:@"Default"];
		NSString *type = [background[@"typeName"] capitalizedString];
		if (type.length)
			[parts addObject:type];
		cell.detailTextLabel.text = [parts componentsJoinedByString:@" · "];
		cell.detailTextLabel.font = TGFontCaption();
		cell.detailTextLabel.textColor = [theme secondaryTextColour];
		cell.imageView.image = [self previewForBackground:background];
		cell.imageView.contentMode = UIViewContentModeScaleAspectFill;
		cell.imageView.clipsToBounds = YES;
		cell.imageView.layer.cornerRadius = TGMetricCornerSmall;
		cell.backgroundColor = [theme cardBackgroundColour];
		cell.accessoryType = UITableViewCellAccessoryDisclosureIndicator;
		cell.selectionStyle = UITableViewCellSelectionStyleBlue;
		return cell;
	}

	UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:@"action"];
	if (!cell){
		cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleSubtitle
									  reuseIdentifier:@"action"];
		[theme styleCell:cell];
	}
	cell.textLabel.text = row[@"title"];
	cell.detailTextLabel.text = row[@"detail"];
	cell.backgroundColor = [theme listBackgroundColour];
	cell.imageView.image = nil;
	cell.accessoryView = nil;
	cell.accessoryType = UITableViewCellAccessoryNone;

	if ([kind isEqualToString:@"plain"]){
		cell.textLabel.font = TGFontBody();
		cell.textLabel.textColor = [theme secondaryTextColour];
		cell.detailTextLabel.text = nil;
		cell.selectionStyle = UITableViewCellSelectionStyleNone;
		return cell;
	}

	BOOL destructive = [row[@"action"] isEqualToString:@"deleteDefault"] ||
					   [row[@"action"] isEqualToString:@"reset"];
	cell.textLabel.font = TGFontRow();
	cell.textLabel.textColor = destructive ? [theme destructiveColour]
										   : [theme accentColour];
	cell.detailTextLabel.font = TGFontCaption();
	cell.detailTextLabel.textColor = [theme secondaryTextColour];
	cell.selectionStyle = UITableViewCellSelectionStyleBlue;
	return cell;
}

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
	[tableView deselectRowAtIndexPath:indexPath animated:YES];
	NSDictionary *row = [self rowAt:indexPath];
	if ([row[@"kind"] isEqualToString:@"background"])
		[self showActionsForBackground:row[@"background"]
							 installed:[row[@"installed"] boolValue]];
	else if ([row[@"kind"] isEqualToString:@"action"])
		[self runAction:row[@"action"]];
}

#pragma mark - previews

- (UIImage *)previewForBackground:(NSDictionary *)background {
	NSNumber *backgroundId = background[@"id"];
	UIImage *cached = self.previews[backgroundId];
	if (cached)
		return cached;

	NSNumber *fileId = background[@"fileId"];
	if (fileId.longLongValue > 0 && ![self.requested containsObject:backgroundId]){
		[self.requested addObject:backgroundId];
		__weak typeof(self) weakSelf = self;
		[[TGClient shared] downloadFile:fileId.integerValue
							   priority:TGDownloadPriorityOnScreen
							 completion:^(NSString *path){
			if (!path.length)
				return;
			UIImage *image = [UIImage imageWithContentsOfFile:path];
			if (!image)
				return;
			weakSelf.previews[backgroundId] = image;
			[weakSelf.tableView reloadData];
		}];
	}
	return TGBackgroundPreview(nil, [background[@"fillColour"] integerValue]);
}

#pragma mark - the switch

- (void)darkThemeToggled:(UISwitch *)toggle {
	self.darkTheme = toggle.on;
	self.found = nil;
	self.searchError = nil;
	[self loadInstalled];
}

#pragma mark - actions

- (void)runAction:(NSString *)action {
	__weak typeof(self) weakSelf = self;
	if ([action isEqualToString:@"search"]){
		[TGAlertSheet showInput:@"Search Backgrounds"
						message:@"Telegram's catalogue is searched by name."
					placeholder:@"cat"
						   text:nil action:@"Search" inView:self.view
					   onSubmit:^(NSString *name){
			[weakSelf searchNamed:name];
		}];
		return;
	}
	if ([action isEqualToString:@"reset"]){
		[TGAlertSheet showConfirm:@"Every installed background except Telegram's "
								  @"defaults is dropped from the list."
							title:@"Reset Installed Backgrounds"
						   action:@"Reset" destructive:YES inView:self.view
						onConfirm:^{
			[[TGClient shared] resetInstalledBackgroundsWithCompletion:
					^(BOOL ok, NSString *error){
				if (!ok){
					[weakSelf showError:error title:@"Reset Backgrounds"];
					return;
				}
				weakSelf.status = @"Installed backgrounds reset to Telegram's defaults.";
				[weakSelf loadInstalled];
			}];
		}];
		return;
	}
	if ([action isEqualToString:@"deleteDefault"]){
		[TGAlertSheet showConfirm:@"Chats go back to Telegram's own background for "
								  @"this theme. Installed backgrounds stay."
							title:@"Delete Default Background"
						   action:@"Delete" destructive:YES inView:self.view
						onConfirm:^{
			[[TGClient shared] deleteDefaultBackgroundForDarkTheme:weakSelf.darkTheme
					completion:^(BOOL ok, NSString *error){
				if (!ok){
					[weakSelf showError:error title:@"Default Background"];
					return;
				}
				weakSelf.status = @"The default background was deleted.";
				[weakSelf loadInstalled];
			}];
		}];
	}
}

- (void)searchNamed:(NSString *)name {
	__weak typeof(self) weakSelf = self;
	[[TGClient shared] searchBackgroundNamed:name
			completion:^(NSDictionary *background, NSString *error){
		weakSelf.found = background;
		weakSelf.searchError = error;
		if (error){
			[TGAlertSheet showMessage:error title:@"Search Backgrounds"
							   inView:weakSelf.view];
		} else if (background){
			weakSelf.status = [NSString stringWithFormat:@"Found \"%@\".",
					background[@"title"] ?: background[@"name"]];
		}
		[weakSelf rebuild];
	}];
}

- (void)showActionsForBackground:(NSDictionary *)background installed:(BOOL)installed {
	__weak typeof(self) weakSelf = self;
	NSArray *titles = installed
			? @[@"Set as Default", @"Show Remote URL", @"Remove from Installed"]
			: @[@"Install as Default", @"Show Remote URL"];
	[TGAlertSheet showChoices:titles
						title:(background[@"title"] ?: background[@"name"] ?: @"Background")
					  message:[self detailForBackground:background]
			 destructiveIndex:(installed ? 2 : -1)
					   inView:self.view
					 onChoice:^(NSInteger index){
		if (index == 0)
			[weakSelf installBackground:background];
		else if (index == 1)
			[weakSelf showUrlForBackground:background];
		else if (installed && index == 2)
			[weakSelf removeBackground:background];
	}];
}

- (NSString *)detailForBackground:(NSDictionary *)background {
	NSMutableArray *parts = [NSMutableArray array];
	[parts addObject:[background[@"typeName"] capitalizedString] ?: @"Background"];
	if ([background[@"isDark"] boolValue])
		[parts addObject:@"Dark theme"];
	if ([background[@"fileId"] longLongValue] > 0)
		[parts addObject:[NSString stringWithFormat:@"file %@", background[@"fileId"]]];
	return [parts componentsJoinedByString:@" · "];
}

- (void)installBackground:(NSDictionary *)background {
	__weak typeof(self) weakSelf = self;
	[[TGClient shared] setDefaultBackground:background
							   forDarkTheme:self.darkTheme
								 completion:^(NSDictionary *installed, NSString *error){
		if (!installed){
			[weakSelf showError:(error ?: @"Telegram refused that background.")
						  title:@"Set Background"];
			return;
		}
		weakSelf.status = [NSString stringWithFormat:@"\"%@\" is now the default.",
				installed[@"title"] ?: background[@"title"] ?: background[@"name"]];
		[weakSelf loadInstalled];
	}];
}

- (void)showUrlForBackground:(NSDictionary *)background {
	__weak typeof(self) weakSelf = self;
	[[TGClient shared] backgroundUrlForBackground:background
			completion:^(NSString *url, NSString *error){
		if (!url.length){
			[weakSelf showError:(error ?: @"Telegram did not answer with an address.")
						  title:@"Background Address"];
			return;
		}
		[TGAlertSheet showChoices:@[@"Copy Address", @"Open Address"]
							title:@"Background Address"
						  message:url
				 destructiveIndex:-1
						   inView:weakSelf.view
						 onChoice:^(NSInteger index){
			if (index == 0)
				[UIPasteboard generalPasteboard].string = url;
			else
				[[UIApplication sharedApplication]
						openURL:[NSURL URLWithString:url]];
		}];
	}];
}

- (void)removeBackground:(NSDictionary *)background {
	__weak typeof(self) weakSelf = self;
	[TGAlertSheet showConfirm:@"It leaves the installed list. Telegram's catalogue "
							  @"still has it, so a search can bring it back."
						title:@"Remove Background"
					   action:@"Remove" destructive:YES inView:self.view
					onConfirm:^{
		[[TGClient shared] removeInstalledBackground:[background[@"id"] longLongValue]
				completion:^(BOOL ok, NSString *error){
			if (!ok){
				[weakSelf showError:error title:@"Remove Background"];
				return;
			}
			weakSelf.status = [NSString stringWithFormat:@"\"%@\" was removed.",
					background[@"title"] ?: background[@"name"]];
			[weakSelf loadInstalled];
		}];
	}];
}

- (void)showError:(NSString *)message title:(NSString *)title {
	if (!message.length)
		message = @"Telegram refused that.";
	self.status = message;
	[TGAlertSheet showMessage:message title:title inView:self.view];
	[self rebuild];
}

@end
