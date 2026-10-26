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
#import "TGSheet.h"
#import "TGTheme.h"
#import "TGStyle.h"

@interface TGScheduledViewController ()
@property (nonatomic, strong) NSArray *messages;
@property (nonatomic, strong) UIDatePicker *picker;
@property (nonatomic, strong) TGSheet *pickerSheet;
@property (nonatomic, assign) int64_t pickerMessageId;
@end

@implementation TGScheduledViewController

- (void)viewDidLoad {
	[super viewDidLoad];

	if ([self respondsToSelector:@selector(setEdgesForExtendedLayout:)])
		self.edgesForExtendedLayout = UIRectEdgeNone;

	self.title = @"Scheduled Messages";
	self.messages = @[];
	self.tableView.rowHeight = 52;
	[self applyTheme];
	[self reload];

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

- (void)viewWillAppear:(BOOL)animated {
	[super viewWillAppear:animated];
	[self applyTheme];
	[self reload];
}

- (void)reload {
	__weak typeof(self) weakSelf = self;
	[[TGClient shared] scheduledMessagesInChat:self.chatId completion:^(NSArray *messages){
		TGScheduledViewController *me = weakSelf;
		if (!me)
			return;
		me.messages = messages ?: @[];
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

/// Seconds into "in 2 h 15 m" - the only phrasing that means something
/// while the numbers move, and the server's stamp is what answers with it.
static NSString *TGTimeUntil(NSTimeInterval sendDate) {
	if (sendDate <= 0)
		return @"";
	NSInteger gap = (NSInteger)(sendDate - [[NSDate date] timeIntervalSince1970]);
	if (gap < 0)
		gap = 0;
	if (gap < 60)
		return @"in less than a minute";
	NSInteger minutes = gap / 60;
	if (minutes < 60)
		return [NSString stringWithFormat:@"in %ld min", (long)minutes];
	NSInteger hours = minutes / 60;
	minutes -= hours * 60;
	if (hours < 24)
		return minutes > 0
				? [NSString stringWithFormat:@"in %ld h %ld min", (long)hours, (long)minutes]
				: [NSString stringWithFormat:@"in %ld h", (long)hours];
	NSInteger days = hours / 24;
	hours -= days * 24;
	return hours > 0
			? [NSString stringWithFormat:@"in %ld d %ld h", (long)days, (long)hours]
			: [NSString stringWithFormat:@"in %ld d", (long)days];
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
	return self.messages.count;
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
	cell.textLabel.text = m[@"text"] ?: @"...";
	cell.textLabel.font = TGFontRowStrong();
	cell.textLabel.textColor = [theme primaryTextColour];
	cell.textLabel.backgroundColor = [theme listBackgroundColour];

	// The clock it is waiting for, not the date it was written.
	cell.detailTextLabel.text = TGTimeUntil([m[@"date"] doubleValue]);
	cell.detailTextLabel.textColor = [theme secondaryTextColour];
	cell.detailTextLabel.backgroundColor = [theme listBackgroundColour];

	cell.accessoryType = UITableViewCellAccessoryDisclosureIndicator;
	if (theme.isDark) {
		UIView *selected = [[UIView alloc] init];
		selected.backgroundColor = [theme bubbleTheirsColour];
		cell.selectedBackgroundView = selected;
	} else {
		cell.selectedBackgroundView = nil;
	}
	return cell;
}

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
	[tableView deselectRowAtIndexPath:indexPath animated:YES];

	NSDictionary *m = self.messages[indexPath.row];
	int64_t messageId = [m[@"id"] longLongValue];
	NSString *what = m[@"text"] ?: @"";
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

/// The date a waiting message moves to. The picker's own bar closes it; a
/// refusal is heard rather than assumed, which is why this is a request.
- (void)pickDateFor:(int64_t)messageId {
	static const CGFloat kBar = 44.0f, kPicker = 216.0f;

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
