//
// TGMessageToolsViewController.m
//
#import "TGMessageToolsViewController.h"
#import "TGClient.h"
#import "TGAlertSheet.h"
#import "TGChecklistViewController.h"
#import "TGSuggestedPostViewController.h"
#import "TGAiComposeViewController.h"

@implementation TGMessageToolsViewController

- (void)viewDidLoad {
	self.title = @"Message Tools";
	[super viewDidLoad];
	[self rebuild];
}

- (void)viewWillAppear:(BOOL)animated {
	[super viewWillAppear:animated];
	[self rebuild];
}

- (void)rebuild {
	__weak typeof(self) weakSelf = self;
	NSMutableArray *aiRows = [NSMutableArray array];
	[aiRows addObject:TGTier2Action(@"Summarize Message", ^{ [weakSelf summarize]; })];
	[aiRows addObject:TGTier2Action(@"Fix Text with AI", ^{ [weakSelf fixText]; })];
	[aiRows addObject:TGTier2Action(@"Translate Rich Message", ^{
		[weakSelf translateRichMessage];
	})];
	[aiRows addObject:TGTier2Action(@"Get Full Rich Message", ^{
		[weakSelf fullRichMessage];
	})];

	NSMutableArray *messageRows = [NSMutableArray array];
	if (self.isChecklist){
		[messageRows addObject:TGTier2Row(@"Checklist", @"Open the task editor", ^{
			TGChecklistViewController *screen = [[TGChecklistViewController alloc]
					initWithChatId:weakSelf.chatId
						 messageId:weakSelf.messageId
							 title:@"Checklist"];
			screen.hidesBottomBarWhenPushed = YES;
			[weakSelf.navigationController pushViewController:screen animated:YES];
		})];
	}
	if (self.hasSuggestedPost){
		[messageRows addObject:TGTier2Row(@"Suggested Post", @"Approve or decline", ^{
			TGSuggestedPostViewController *screen =
					[[TGSuggestedPostViewController alloc]
							initWithChatId:weakSelf.chatId
								 messageId:weakSelf.messageId];
			screen.hidesBottomBarWhenPushed = YES;
			[weakSelf.navigationController pushViewController:screen animated:YES];
		})];
	}
	[messageRows addObject:TGTier2Row(@"Fact Check",
			self.factCheck.length ? self.factCheck : @"None", ^{
		[weakSelf editFactCheck];
	})];
	if (self.factCheck.length){
		[messageRows addObject:TGTier2Action(@"Clear Fact Check", ^{
			[weakSelf clearFactCheck];
		})];
	}

	NSMutableArray *richRows = [NSMutableArray array];
	[richRows addObject:TGTier2Action(@"Send as Rich Draft", ^{ [weakSelf sendDraft]; })];
	[richRows addObject:TGTier2Row(@"AI Compose", nil, ^{
		TGAiComposeViewController *screen = [[TGAiComposeViewController alloc] init];
		screen.chatId = weakSelf.chatId;
		screen.chatTitle = weakSelf.chatTitle;
		screen.hidesBottomBarWhenPushed = YES;
		[weakSelf.navigationController pushViewController:screen animated:YES];
	})];

	self.sections = @[
		TGTier2Section(@"AI", nil, aiRows),
		TGTier2Section(@"This Message", nil, messageRows),
		TGTier2Section(@"Rich Messages", nil, richRows),
	];
	[self reloadRows];
}

#pragma mark - requests

- (void)summarize {
	__weak typeof(self) weakSelf = self;
	[[TGClient shared] summarizeMessage:self.messageId
								 inChat:self.chatId
							translateTo:@""
								   tone:@""
							 completion:^(NSString *text, NSString *error){
		if (!text.length){
			[weakSelf toast:error ?: @"Telegram refused that."];
			return;
		}
		[weakSelf show:text title:@"Summary"];
	}];
}

- (void)fixText {
	if (!self.messageText.length){
		[self toast:@"This message has no text to fix."];
		return;
	}
	__weak typeof(self) weakSelf = self;
	[[TGClient shared] fixTextWithAi:self.messageText
						  completion:^(NSString *text, NSString *diff, NSString *error){
		if (!text.length){
			[weakSelf toast:error ?: @"Telegram refused that."];
			return;
		}
		[weakSelf show:text title:@"Fixed Text"];
	}];
}

- (void)translateRichMessage {
	__weak typeof(self) weakSelf = self;
	NSString *code = [[NSLocale currentLocale] objectForKey:NSLocaleLanguageCode];
	[[TGClient shared] translateMessageRichMessage:self.messageId
											inChat:self.chatId
											toCode:code.length ? code : @"en"
											  tone:@""
										completion:^(NSString *text, NSString *error){
		if (!text.length){
			[weakSelf toast:error ?: @"Telegram refused that."];
			return;
		}
		[weakSelf show:text title:@"Translation"];
	}];
}

- (void)fullRichMessage {
	__weak typeof(self) weakSelf = self;
	[[TGClient shared] getFullRichMessage:self.messageId
								   inChat:self.chatId
							   completion:^(NSString *text, NSDictionary *message,
											NSString *error){
		if (!text.length){
			[weakSelf toast:error ?: @"Telegram refused that."];
			return;
		}
		[weakSelf show:text title:@"Full Rich Message"];
	}];
}

- (void)sendDraft {
	if (!self.messageText.length){
		[self toast:@"This message has no text to draft."];
		return;
	}
	__weak typeof(self) weakSelf = self;
	[[TGClient shared] sendRichMessageDraft:self.messageText
									 toChat:self.chatId
									topicId:0
									draftId:(int64_t)arc4random()
									canStop:NO
								 keepOnStop:YES
								 completion:^(BOOL ok, NSString *error){
		if (!ok){
			[weakSelf toast:error ?: @"Telegram refused that draft."];
			return;
		}
		[weakSelf toast:@"Draft sent"];
	}];
}

- (void)editFactCheck {
	__weak typeof(self) weakSelf = self;
	[TGAlertSheet showInput:@"Fact Check"
					message:@"Shown under the post. Empty removes it."
				placeholder:@"Fact check"
					   text:self.factCheck
					 action:@"Save"
					 inView:self.view
				   onSubmit:^(NSString *text){
		[[TGClient shared] setMessageFactCheck:weakSelf.messageId
										inChat:weakSelf.chatId
										  text:text
									completion:^(BOOL ok, NSString *error){
			if (!ok){
				[weakSelf toast:error ?: @"Telegram refused that."];
				return;
			}
			weakSelf.factCheck = text;
			[weakSelf rebuild];
		}];
	}];
}

- (void)clearFactCheck {
	__weak typeof(self) weakSelf = self;
	[[TGClient shared] setMessageFactCheck:self.messageId
									inChat:self.chatId
									  text:nil
								completion:^(BOOL ok, NSString *error){
		if (!ok){
			[weakSelf toast:error ?: @"Telegram refused that."];
			return;
		}
		weakSelf.factCheck = @"";
		[weakSelf rebuild];
	}];
}

- (void)show:(NSString *)text title:(NSString *)title {
	TGTier2ResultViewController *screen = [[TGTier2ResultViewController alloc]
			initWithTitle:title body:text];
	screen.hidesBottomBarWhenPushed = YES;
	[self.navigationController pushViewController:screen animated:YES];
}

@end
