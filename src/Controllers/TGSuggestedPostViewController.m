//
// TGSuggestedPostViewController.m
//
#import "TGSuggestedPostViewController.h"
#import "TGClient.h"
#import "TGAlertSheet.h"

@interface TGSuggestedPostViewController ()
@property (nonatomic, assign) int64_t chatId;
@property (nonatomic, assign) int64_t messageId;
@property (nonatomic, strong) NSDictionary *post;
@property (nonatomic, copy) NSString *loadError;
@end

@implementation TGSuggestedPostViewController

- (instancetype)initWithChatId:(int64_t)chatId messageId:(int64_t)messageId {
	self = [super init];
	if (!self)
		return nil;
	_chatId = chatId;
	_messageId = messageId;
	return self;
}

- (void)viewDidLoad {
	self.title = @"Suggested Post";
	[super viewDidLoad];
	[self loadPost];
}

- (void)viewWillAppear:(BOOL)animated {
	[super viewWillAppear:animated];
	[self rebuild];
}

- (void)loadPost {
	__weak typeof(self) weakSelf = self;
	[[TGClient shared] suggestedPostForMessage:self.messageId inChat:self.chatId
									completion:^(NSDictionary *post, NSString *error){
		TGSuggestedPostViewController *me = weakSelf;
		if (!me)
			return;
		me.post = post;
		me.loadError = post ? nil : (error ?: @"That message is not a suggested post.");
		[me rebuild];
	}];
}

- (void)rebuild {
	__weak typeof(self) weakSelf = self;
	NSMutableArray *detailRows = [NSMutableArray array];
	if (self.post){
		NSDateFormatter *formatter = [[NSDateFormatter alloc] init];
		formatter.dateStyle = NSDateFormatterMediumStyle;
		formatter.timeStyle = NSDateFormatterShortStyle;
		NSNumber *sendDate = self.post[@"sendDate"];
		NSString *dateText = [sendDate longLongValue] > 0
				? [formatter stringFromDate:[NSDate dateWithTimeIntervalSince1970:
						[sendDate doubleValue]]]
				: @"Not set";
		[detailRows addObject:TGTier2Row(@"Price", self.post[@"price"], nil)];
		[detailRows addObject:TGTier2Row(@"Send Date", dateText, nil)];
		[detailRows addObject:TGTier2Row(@"State", self.post[@"state"], nil)];
		[detailRows addObject:TGTier2Row(@"Can Approve",
				[self.post[@"canBeApproved"] boolValue] ? @"Yes" : @"No", nil)];
		[detailRows addObject:TGTier2Row(@"Can Decline",
				[self.post[@"canBeDeclined"] boolValue] ? @"Yes" : @"No", nil)];
	} else {
		NSMutableDictionary *row = TGTier2Row(self.loadError ?: @"Loading...", nil, nil);
		row[TGTier2RowKind] = TGTier2KindPlain;
		[detailRows addObject:row];
	}

	NSMutableArray *actions = [NSMutableArray array];
	[actions addObject:TGTier2Action(@"Approve Post", ^{ [weakSelf approve]; })];
	[actions addObject:TGTier2Action(@"Decline Post", ^{ [weakSelf decline]; })];
	[actions addObject:TGTier2Action(@"Reload", ^{ [weakSelf loadPost]; })];

	self.sections = @[
		TGTier2Section(nil,
				@"A suggested post is published only after the channel "
				@"administrator approves it. Telegram names the answer.",
				detailRows),
		TGTier2Section(nil, nil, actions),
	];
	[self reloadRows];
}

- (void)approve {
	if (![self.post[@"canBeApproved"] boolValue]){
		[self toast:@"Telegram does not let this account approve the post."];
		return;
	}
	NSInteger sendDate = [self.post[@"sendDate"] integerValue];
	if (sendDate <= 0)
		sendDate = (NSInteger)[[NSDate date] timeIntervalSince1970];
	__weak typeof(self) weakSelf = self;
	[TGAlertSheet showConfirm:@"The post is approved and queued for its send date."
						 title:@"Approve Post"
						action:@"Approve"
				   destructive:NO
						inView:self.view
					 onConfirm:^{
		[[TGClient shared] approveSuggestedPost:weakSelf.messageId
										 inChat:weakSelf.chatId
									   sendDate:sendDate
									 completion:^(BOOL ok, NSString *error){
			if (!ok){
				[weakSelf toast:error ?: @"Telegram refused that."];
				return;
			}
			[weakSelf loadPost];
		}];
	}];
}

- (void)decline {
	if (![self.post[@"canBeDeclined"] boolValue]){
		[self toast:@"Telegram does not let this account decline the post."];
		return;
	}
	__weak typeof(self) weakSelf = self;
	[TGAlertSheet showChoices:@[@"Decline without a comment", @"Write a comment"]
						title:@"Decline Post"
			 destructiveIndex:0
					   inView:self.view
					 onChoice:^(NSInteger index){
		if (index == 0){
			[weakSelf sendDecline:@""];
			return;
		}
		[TGAlertSheet showInput:@"Decline Post"
						message:@"The comment goes to the sender."
					placeholder:@"Comment"
						   text:nil
						 action:@"Decline"
						 inView:weakSelf.view
					   onSubmit:^(NSString *comment){
			[weakSelf sendDecline:comment];
		}];
	}];
}

- (void)sendDecline:(NSString *)comment {
	__weak typeof(self) weakSelf = self;
	[[TGClient shared] declineSuggestedPost:self.messageId
									 inChat:self.chatId
									comment:comment
								 completion:^(BOOL ok, NSString *error){
		if (!ok){
			[weakSelf toast:error ?: @"Telegram refused that."];
			return;
		}
		[weakSelf loadPost];
	}];
}

@end
