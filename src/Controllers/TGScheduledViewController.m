//
// TGScheduledViewController - the queue behind a scheduled send. One section
// of rows, each answering with the menu a waiting message has: send it now,
// send it when they are next online, move it, or take it away.
//
// Nothing here asks for a reason: the only thing this screen does is that
// one list, so the words in the rows are the messages themselves.
#import "TGScheduledViewController.h"
#import "TGAlertSheet.h"
#import "TGClient.h"
#import "TGEmptyView.h"
#import "TGIcons.h"
#import "TGSheet.h"
#import "TGTheme.h"
#import "TGUIFormat.h"
#import "TGStyle.h"

@interface TGScheduledViewController ()
@property (nonatomic, strong) NSArray *messages;
@property (nonatomic, strong) UIDatePicker *picker;
@property (nonatomic, strong) TGSheet *pickerSheet;
@property (nonatomic, assign) int64_t pickerMessageId;
@property (nonatomic, strong) TGEmptyView *emptyView;
@end

@implementation TGScheduledViewController

- (void)viewDidLoad {
	[super viewDidLoad];

	if ([self respondsToSelector:@selector(setEdgesForExtendedLayout:)])
		self.edgesForExtendedLayout = UIRectEdgeNone;

	self.title = @"Scheduled Messages";
	self.messages = @[];
	self.tableView.rowHeight = TGMetricPersonRow;
	[self applyTheme];

	UIRefreshControl *refresh = [[UIRefreshControl alloc] init];
	[refresh addTarget:self action:@selector(refreshPulled)
	  forControlEvents:UIControlEventValueChanged];
	self.refreshControl = refresh;

	[self reload];

	__weak typeof(self) weakSelf = self;
	[[NSNotificationCenter defaultCenter] addObserverForName:TGThemeChangedNotification
			object:nil queue:[NSOperationQueue mainQueue]
		 usingBlock:^(NSNotification *note) {
		[weakSelf applyTheme];
		weakSelf.emptyView = nil;
		weakSelf.tableView.backgroundView = nil;
		[weakSelf updateEmptyView];
		[weakSelf.tableView reloadData];
	}];
}

- (void)dealloc {
	[[NSNotificationCenter defaultCenter] removeObserver:self];
}

- (void)viewWillAppear:(BOOL)animated {
	[super viewWillAppear:animated];
	[self applyTheme];
	[self reload];
}

- (void)refreshPulled {
	[self reload];
}

- (void)reload {
	__weak typeof(self) weakSelf = self;
	[[TGClient shared] scheduledMessagesInChat:self.chatId completion:^(NSArray *messages){
		TGScheduledViewController *me = weakSelf;
		if (!me)
			return;
		me.messages = messages ?: @[];
		[me.refreshControl endRefreshing];
		[me updateEmptyView];
		[me.tableView reloadData];
		NSLog(@"TDLIB SCHEDULED: %lu", (unsigned long)messages.count);
	}];
}

- (void)applyTheme {
	TGTheme *theme = [TGTheme shared];
	self.tableView.backgroundColor = [theme listBackgroundColour];
	self.tableView.separatorColor = [theme separatorColour];
	[theme styleNavigationBar:self.navigationController.navigationBar];
}

- (void)updateEmptyView {
	if (self.messages.count) {
		self.tableView.backgroundView = nil;
		self.emptyView = nil;
		return;
	}
	if (!self.emptyView) {
		self.emptyView = [TGEmptyView emptyViewWithFrame:self.tableView.bounds
				image:[TGIcons emptySearchIllustration]
				title:@"No scheduled messages"
				subtitle:@"Messages you schedule to send later appear here."
				buttonTitle:nil
				target:nil
				action:nil];
	}
	self.tableView.backgroundView = self.emptyView;
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
	return self.messages.count;
}

- (NSString *)tableView:(UITableView *)tableView titleForFooterInSection:(NSInteger)section {
	if (!self.messages.count)
		return nil;
	return @"Tap a message to send it now, move it, or delete it.";
}

- (void)tableView:(UITableView *)tableView willDisplayFooterView:(UIView *)view forSection:(NSInteger)section {
	if ([view isKindOfClass:[UITableViewHeaderFooterView class]]) {
		UITableViewHeaderFooterView *footer = (UITableViewHeaderFooterView *)view;
		footer.textLabel.font = TGFontCaption();
		footer.textLabel.textColor = [[TGTheme shared] sectionHeaderColour];
		footer.contentView.backgroundColor = [[TGTheme shared] listBackgroundColour];
	}
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
	static NSString *reuse = @"TGScheduledCell";
	UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:reuse];
	if (!cell)
		cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleSubtitle
									  reuseIdentifier:reuse];

	TGTheme *theme = [TGTheme shared];
	cell.backgroundColor = [theme listBackgroundColour];
	cell.contentView.backgroundColor = [theme listBackgroundColour];

	NSDictionary *m = self.messages[indexPath.row];
	NSString *text = m[@"text"];
	cell.textLabel.text = text.length ? text : @"Message";
	cell.textLabel.font = TGFontRowStrong();
	cell.textLabel.textColor = [theme primaryTextColour];
	cell.textLabel.backgroundColor = [theme listBackgroundColour];

	// Telegram names the day and the clock first, then how long that is.
	// "in 2 h 15 min" alone never says when it lands.
	NSTimeInterval stamp = [m[@"date"] doubleValue];
	NSTimeInterval now = [[NSDate date] timeIntervalSince1970];
	NSString *when = TGUIFormatScheduledWhen(stamp, now);
	NSString *until = TGUIFormatScheduledRelative(stamp, now);
	cell.detailTextLabel.text = when.length
			? (until.length ? [NSString stringWithFormat:@"%@  ·  %@", when, until] : when)
			: until;
	cell.detailTextLabel.textColor = [theme secondaryTextColour];
	cell.detailTextLabel.backgroundColor = [theme listBackgroundColour];

	cell.accessoryType = UITableViewCellAccessoryDisclosureIndicator;
	return cell;
}

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
	[tableView deselectRowAtIndexPath:indexPath animated:YES];
	if (indexPath.row >= (NSInteger)self.messages.count)
		return;

	NSDictionary *m = self.messages[indexPath.row];
	int64_t messageId = [m[@"id"] longLongValue];
	NSString *what = m[@"text"] ?: @"Message";
	__weak typeof(self) weakSelf = self;

	NSString *whenOnline = @"Send When Online";
	NSMutableArray *choices = [NSMutableArray arrayWithObjects:
			@"Send Now", whenOnline, @"Pick a Date...", @"Delete", nil];
	[TGAlertSheet showChoices:choices
						title:what.length > 60 ? [what substringToIndex:60] : what
			 destructiveIndex:3
					   inView:self.navigationController.view ?: self.view
					 onChoice:^(NSInteger index){
		void (^done)(BOOL) = ^(BOOL ok){
			NSString *say = ok ? @"Done." : @"Telegram refused that.";
			[TGAlertSheet showMessage:say title:nil inView:weakSelf.view];
			[weakSelf reload];
		};
		if (index == 0)
			[[TGClient shared] setSchedulingState:nil forMessage:messageId
										   inChat:weakSelf.chatId completion:done];
		else if (index == 1)
			[[TGClient shared] setSchedulingState:[TGClient scheduledWhenOnline]
									   forMessage:messageId
										   inChat:weakSelf.chatId completion:done];
		else if (index == 2)
			[weakSelf pickDateFor:messageId];
		else {
			[TGAlertSheet showConfirm:@"The message is taken out of the queue "
									  @"and does not go to the chat."
								title:@"Delete"
							   action:@"Delete"
						  destructive:YES
							   inView:weakSelf.navigationController.view ?: weakSelf.view
						   onConfirm:^{
				[[TGClient shared] deleteMessages:@[@(messageId)] inChat:weakSelf.chatId];
				[weakSelf reload];
			}];
		}
	}];
}

/// Swipe-to-delete is the same removal the hold menu offers, so the queue can
/// be emptied without opening a sheet for every row.
- (BOOL)tableView:(UITableView *)tableView canEditRowAtIndexPath:(NSIndexPath *)indexPath {
	return self.messages.count > 0;
}

- (void)tableView:(UITableView *)tableView
		commitEditingStyle:(UITableViewCellEditingStyle)editingStyle
		 forRowAtIndexPath:(NSIndexPath *)indexPath {
	if (editingStyle != UITableViewCellEditingStyleDelete)
		return;
	if (indexPath.row >= (NSInteger)self.messages.count)
		return;
	int64_t messageId = [self.messages[(NSUInteger)indexPath.row][@"id"] longLongValue];
	__weak typeof(self) weakSelf = self;
	[TGAlertSheet showConfirm:@"The message is taken out of the queue and "
							  @"does not go to the chat."
						title:@"Delete"
					   action:@"Delete"
				  destructive:YES
					   inView:self.navigationController.view ?: self.view
				   onConfirm:^{
		[[TGClient shared] deleteMessages:@[@(messageId)] inChat:weakSelf.chatId];
		[weakSelf reload];
	}];
}

/// The date a waiting message moves to. The picker's own bar closes it; a
/// refusal is heard rather than assumed, which is why this is a request.
- (void)pickDateFor:(int64_t)messageId {
	static const CGFloat kBar = TGMetricRow, kPicker = TGMetricPickerHeight;

	TGSheet *sheet = [TGSheet sheetForView:self.view.window ?: self.view];
	UIView *card = [sheet addCardOfHeight:kBar + kPicker edgeToEdge:YES];

	UIDatePicker *picker = [[UIDatePicker alloc] initWithFrame:
			CGRectMake(0, kBar, card.bounds.size.width, kPicker)];
	picker.datePickerMode = UIDatePickerModeDateAndTime;
	picker.minimumDate = [NSDate dateWithTimeIntervalSinceNow:60];
	picker.minuteInterval = 15;
	picker.date = [NSDate dateWithTimeIntervalSinceNow:60 * 60];
	[card addSubview:picker];

	UIToolbar *bar = [[UIToolbar alloc] initWithFrame:
			CGRectMake(0, 0, card.bounds.size.width, kBar)];
	bar.items = @[
		[[UIBarButtonItem alloc] initWithTitle:@"Cancel" style:UIBarButtonItemStylePlain
				target:self action:@selector(sheetDismissed)],
		[[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemFlexibleSpace
				target:nil action:nil],
		[[UIBarButtonItem alloc] initWithTitle:@"Schedule" style:UIBarButtonItemStyleDone
				target:self action:@selector(sheetCommitted)],
	];
	[card addSubview:bar];

	self.picker = picker;
	self.pickerSheet = sheet;
	self.pickerMessageId = messageId;
	[sheet present];
}

- (void)sheetDismissed {
	[self.pickerSheet dismiss];
	self.pickerSheet = nil;
}

- (void)sheetCommitted {
	NSTimeInterval date = [self.picker.date timeIntervalSince1970];
	[self.pickerSheet dismiss];
	self.pickerSheet = nil;

	__weak typeof(self) weakSelf = self;
	[[TGClient shared] setSchedulingState:[TGClient scheduledAtDate:date]
							   forMessage:self.pickerMessageId
								   inChat:self.chatId
							   completion:^(BOOL ok){
		NSString *say = ok ? @"Scheduled." : @"Telegram refused that move.";
		[TGAlertSheet showMessage:say title:nil inView:weakSelf.view];
		[weakSelf reload];
	}];
}

@end

// vim:ft=objc
