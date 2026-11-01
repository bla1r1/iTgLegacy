#import "TGEphemeralViewController.h"
#import "TGAlertSheet.h"
#import "TGClient.h"
#import "TGTheme.h"
#import "TGStyle.h"

static const NSInteger kEphemeralSectionTarget = 0;
static const NSInteger kEphemeralSectionActions = 1;
static const NSInteger kEphemeralSectionResult = 2;

@interface TGEphemeralViewController ()
@property (nonatomic, strong) UITextView *composer;
@property (nonatomic, strong) UILabel *placeholder;
@property (nonatomic, assign) int64_t receiverUserId;
@property (nonatomic, assign) NSInteger replyId;
@property (nonatomic, assign) NSInteger lastEphemeralId;
@property (nonatomic, assign) int64_t lastMessageId;
@property (nonatomic, copy)   NSString *resultText;
@property (nonatomic, copy)   NSString *lastSentText;
@end

@implementation TGEphemeralViewController

- (id)init {
	return [super initWithStyle:UITableViewStyleGrouped];
}

- (void)viewDidLoad {
	[super viewDidLoad];
	if ([self respondsToSelector:@selector(setEdgesForExtendedLayout:)])
		self.edgesForExtendedLayout = UIRectEdgeNone;
	self.title = @"Ephemeral";
	self.receiverUserId = self.chatId > 0 ? self.chatId : 0;
	self.replyId = 0;
	self.lastEphemeralId = 0;
	self.lastMessageId = 0;
	self.resultText = @"No request sent yet.";
	self.tableView.rowHeight = TGMetricRow;
	self.tableView.separatorColor = [[TGTheme shared] separatorColour];
	self.tableView.backgroundColor = [[TGTheme shared] groupedBackgroundColour];
	[[TGTheme shared] styleNavigationBar:self.navigationController.navigationBar];
	self.navigationItem.rightBarButtonItem = [[UIBarButtonItem alloc]
			initWithTitle:@"Receiver" style:UIBarButtonItemStylePlain
				   target:self action:@selector(changeReceiver)];

	CGFloat height = TGMetricRow * 3;
	UIView *header = [[UIView alloc] initWithFrame:
			CGRectMake(0, 0, self.tableView.bounds.size.width,
					   height + TGMetricPadLarge)];
	header.backgroundColor = [UIColor clearColor];
	self.composer = [[UITextView alloc] initWithFrame:
			CGRectMake(TGMetricPadMedium, TGMetricPad,
					   header.bounds.size.width - TGDoubled(TGMetricPadMedium),
					   height)];
	self.composer.font = TGFontBody();
	self.composer.backgroundColor = [[TGTheme shared] cardBackgroundColour];
	self.composer.textColor = [[TGTheme shared] primaryTextColour];
	self.composer.autoresizingMask = UIViewAutoresizingFlexibleWidth;
	self.composer.layer.cornerRadius = TGMetricCornerControl;
	self.composer.clipsToBounds = YES;
	[header addSubview:self.composer];

	self.placeholder = [[UILabel alloc] initWithFrame:
			CGRectMake(TGMetricPadLarge, TGMetricPad,
					   self.composer.bounds.size.width - TGDoubled(TGMetricPadLarge),
					   TGMetricLineBody)];
	self.placeholder.text = @"Ephemeral message text";
	self.placeholder.font = TGFontBody();
	self.placeholder.textColor = [[TGTheme shared] placeholderColour];
	self.placeholder.backgroundColor = [UIColor clearColor];
	self.placeholder.userInteractionEnabled = NO;
	[header addSubview:self.placeholder];
	self.tableView.tableHeaderView = header;
}

- (void)viewWillAppear:(BOOL)animated {
	[super viewWillAppear:animated];
	[[TGTheme shared] styleNavigationBar:self.navigationController.navigationBar];
}

/// The text view has no placeholder support on this OS, so an empty field
/// keeps a label over it until the first character arrives.
- (void)viewDidAppear:(BOOL)animated {
	[super viewDidAppear:animated];
	[[NSNotificationCenter defaultCenter] addObserver:self
			selector:@selector(textChanged:)
				name:UITextViewTextDidChangeNotification object:self.composer];
	[self textChanged:nil];
}

- (void)viewWillDisappear:(BOOL)animated {
	[super viewWillDisappear:animated];
	[[NSNotificationCenter defaultCenter] removeObserver:self
			name:UITextViewTextDidChangeNotification object:self.composer];
}

- (void)textChanged:(NSNotification *)note {
	self.placeholder.hidden = self.composer.text.length > 0;
}

#pragma mark - table

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView {
	return 3;
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
	if (section == kEphemeralSectionTarget)
		return 2;
	if (section == kEphemeralSectionActions)
		return 6;
	return 1;
}

- (NSString *)tableView:(UITableView *)tableView titleForHeaderInSection:(NSInteger)section {
	if (section == kEphemeralSectionTarget)
		return @"Target";
	if (section == kEphemeralSectionActions)
		return @"Requests";
	return @"Result";
}

- (NSString *)tableView:(UITableView *)tableView titleForFooterInSection:(NSInteger)section {
	if (section == kEphemeralSectionTarget)
		return @"sendEphemeralMessage is for bots. A user account sees Telegram's "
			   @"refusal in the result below, which is the honest answer.";
	if (section == kEphemeralSectionActions)
		return @"Edit and delete name the ephemeral message id Telegram returned; "
			   @"the last one is kept from the send.";
	return nil;
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
	UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:@"row"];
	if (!cell)
		cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleSubtitle
									  reuseIdentifier:@"row"];
	[[TGTheme shared] styleCell:cell];
	cell.textLabel.font = TGFontBody();
	cell.textLabel.textColor = [[TGTheme shared] primaryTextColour];
	cell.detailTextLabel.font = TGFontSubhead();
	cell.detailTextLabel.textColor = [[TGTheme shared] secondaryTextColour];
	cell.selectionStyle = UITableViewCellSelectionStyleBlue;
	cell.accessoryType = UITableViewCellAccessoryNone;

	if (indexPath.section == kEphemeralSectionTarget){
		if (indexPath.row == 0){
			cell.textLabel.text = @"Receiver";
			cell.detailTextLabel.text = self.receiverUserId
					? [NSString stringWithFormat:@"%lld", self.receiverUserId]
					: @"Tap to name the bot";
		} else {
			cell.textLabel.text = @"Reply to ephemeral";
			cell.detailTextLabel.text = self.replyId
					? [NSString stringWithFormat:@"%ld", (long)self.replyId] : @"None";
		}
		return cell;
	}
	if (indexPath.section == kEphemeralSectionActions){
		NSArray *titles = @[
			@"Send Ephemeral Message",
			@"Edit Last Message",
			@"Edit Last Caption",
			@"Delete Last Message",
			@"Strip Message Ephemeral Content",
			@"Clear Composer",
		];
		cell.textLabel.text = titles[indexPath.row];
		cell.textLabel.textColor = [titles[indexPath.row] hasPrefix:@"Delete"]
				? [[TGTheme shared] destructiveColour]
				: [[TGTheme shared] accentColour];
		cell.detailTextLabel.text = nil;
		return cell;
	}
	cell.textLabel.text = self.resultText ?: @"No request sent yet.";
	cell.textLabel.font = TGFontMeta();
	cell.textLabel.textColor = [[TGTheme shared] secondaryTextColour];
	cell.textLabel.numberOfLines = 0;
	// The viewer half: what the bot's answer carried, beside the id it named.
	cell.detailTextLabel.text = self.lastSentText.length
			? [NSString stringWithFormat:@"Sent: %@", self.lastSentText] : nil;
	cell.selectionStyle = UITableViewCellSelectionStyleNone;
	return cell;
}

- (CGFloat)tableView:(UITableView *)tableView heightForRowAtIndexPath:(NSIndexPath *)indexPath {
	if (indexPath.section == kEphemeralSectionResult)
		return TGMetricPersonRow;
	return TGMetricRow;
}

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
	[tableView deselectRowAtIndexPath:indexPath animated:YES];
	if (indexPath.section == kEphemeralSectionTarget){
		if (indexPath.row == 0)
			[self changeReceiver];
		else
			[self changeReply];
		return;
	}
	if (indexPath.section != kEphemeralSectionActions)
		return;
	switch (indexPath.row){
		case 0: [self send]; break;
		case 1: [self editLast]; break;
		case 2: [self editCaption]; break;
		case 3: [self deleteLast]; break;
		case 4: [self stripContent]; break;
		case 5:
			self.composer.text = @"";
			[self textChanged:nil];
			break;
	}
}

#pragma mark - the calls

- (void)setResult:(NSString *)text {
	self.resultText = text;
	[self.tableView reloadData];
}

- (void)send {
	NSString *text = self.composer.text;
	if (!text.length){
		[self setResult:@"Type something first."];
		return;
	}
	if (!self.receiverUserId){
		[self setResult:@"Name the bot that receives the ephemeral message."];
		return;
	}
	__weak typeof(self) weakSelf = self;
	[[TGClient shared] sendEphemeralText:text
								  toChat:self.chatId
						  receiverUserId:self.receiverUserId
						 ephemeralReplyId:self.replyId
							  completion:^(NSDictionary *message, NSString *error){
		TGEphemeralViewController *me = weakSelf;
		if (!me)
			return;
		if (error.length || !message){
			[me setResult:(error ?: @"Telegram refused the ephemeral message.")];
			return;
		}
		me.lastSentText = text;
		me.lastMessageId = [message[@"id"] longLongValue];
		me.lastEphemeralId = [message[@"ephemeralMessageId"] integerValue];
		if (!me.lastEphemeralId)
			me.lastEphemeralId = (NSInteger)me.lastMessageId;
		[me setResult:[NSString stringWithFormat:
				@"Sent message %lld, ephemeral %ld.",
				me.lastMessageId, (long)me.lastEphemeralId]];
	}];
}

- (void)editLast {
	NSInteger messageId = [self askMessageId:@"Edit Last Message"];
	if (!messageId)
		return;
	__weak typeof(self) weakSelf = self;
	[TGAlertSheet showInput:@"Edit Last Message" message:nil
				placeholder:@"New text" text:self.composer.text action:@"Save"
					 inView:self.view onSubmit:^(NSString *text){
		[[TGClient shared] editEphemeralMessage:messageId text:text
									   receiver:weakSelf.receiverUserId
										 inChat:weakSelf.chatId
									 completion:^(BOOL ok, NSString *error){
			[weakSelf setResult:(ok ? @"The ephemeral message was edited."
									: (error ?: @"Telegram refused the edit."))];
		}];
	}];
}

- (void)editCaption {
	NSInteger messageId = [self askMessageId:@"Edit Last Caption"];
	if (!messageId)
		return;
	__weak typeof(self) weakSelf = self;
	[TGAlertSheet showInput:@"Edit Last Caption" message:nil
				placeholder:@"New caption" text:nil action:@"Save"
					 inView:self.view onSubmit:^(NSString *caption){
		[[TGClient shared] editEphemeralMessageCaption:messageId caption:caption
											  receiver:weakSelf.receiverUserId
												inChat:weakSelf.chatId
											completion:^(BOOL ok, NSString *error){
			[weakSelf setResult:(ok ? @"The caption was edited."
									: (error ?: @"Telegram refused the caption."))];
		}];
	}];
}

- (void)deleteLast {
	NSInteger messageId = [self askMessageId:@"Delete Last Message"];
	if (!messageId)
		return;
	__weak typeof(self) weakSelf = self;
	[TGAlertSheet showConfirm:@"Delete this ephemeral message?"
						title:@"Delete Last Message" action:@"Delete"
				  destructive:YES inView:self.view onConfirm:^{
		[[TGClient shared] deleteEphemeralMessage:messageId
										 receiver:weakSelf.receiverUserId
										   inChat:weakSelf.chatId
									   completion:^(BOOL ok, NSString *error){
			[weakSelf setResult:(ok ? @"The ephemeral message was deleted."
									: (error ?: @"Telegram refused the delete."))];
		}];
	}];
}

- (void)stripContent {
	if (!self.lastMessageId){
		__weak typeof(self) weakSelf = self;
		[TGAlertSheet showInput:@"Strip Message Ephemeral Content" message:nil
					placeholder:@"Message id" text:nil action:@"Strip"
						 inView:self.view onSubmit:^(NSString *text){
			[weakSelf stripMessageId:(int64_t)[text longLongValue]];
		}];
		return;
	}
	[self stripMessageId:self.lastMessageId];
}

- (void)stripMessageId:(int64_t)messageId {
	if (!messageId){
		[self setResult:@"Name a regular message id first."];
		return;
	}
	__weak typeof(self) weakSelf = self;
	[[TGClient shared] deleteMessageEphemeralContent:messageId inChat:self.chatId
										  completion:^(BOOL ok, NSString *error){
		[weakSelf setResult:(ok ? @"The ephemeral content was removed."
								: (error ?: @"Telegram refused the removal."))];
	}];
}

/// The id to act on: the ephemeral id from the last send, or the regular
/// message id when Telegram answered with a message that carried no
/// ephemeral id. A screen with neither says to send one rather than asking
/// for a number the user cannot know.
- (NSInteger)askMessageId:(NSString *)title {
	NSInteger value = self.lastEphemeralId ?: (NSInteger)self.lastMessageId;
	if (!value)
		[self setResult:@"Send an ephemeral message first; the id comes from its answer."];
	return value;
}

- (void)changeReceiver {
	__weak typeof(self) weakSelf = self;
	[TGAlertSheet showInput:@"Receiver" message:@"The bot's user id."
				placeholder:@"user id"
					   text:(self.receiverUserId
							   ? [NSString stringWithFormat:@"%lld", self.receiverUserId]
							   : nil)
					 action:@"Set" inView:self.view onSubmit:^(NSString *text){
		weakSelf.receiverUserId = [text longLongValue];
		[weakSelf.tableView reloadData];
	}];
}

- (void)changeReply {
	__weak typeof(self) weakSelf = self;
	[TGAlertSheet showInput:@"Reply to Ephemeral" message:@"0 for no reply."
				placeholder:@"ephemeral id"
					   text:(self.replyId ? [NSString stringWithFormat:@"%ld",
							   (long)self.replyId] : nil)
					 action:@"Set" inView:self.view onSubmit:^(NSString *text){
		weakSelf.replyId = (NSInteger)[text longLongValue];
		[weakSelf.tableView reloadData];
	}];
}

@end
