//
// TGAntiSpamViewController.m - the deleted messages TDLib marks as reportable.
//
// reportSupergroupAntiSpamFalsePositive takes a message id "from
// chatEventMessageDeleted with can_report_anti_spam_false_positive == true".
// The group event log is the only place those ids are named, so the screen
// reads it instead of asking an administrator to type a number.
//
#import "TGAntiSpamViewController.h"
#import "TGClient.h"
#import "TGAlertSheet.h"
#import "TGStyle.h"

@interface TGAntiSpamViewController ()
@property (nonatomic, strong) NSArray *rows;
@property (nonatomic, copy) NSString *loadError;
@end

@implementation TGAntiSpamViewController

- (void)viewDidLoad {
	[super viewDidLoad];
	self.title = @"Anti-Spam";
	[self load];
}

- (void)load {
	__weak typeof(self) weakSelf = self;
	[[TGClient shared] antiSpamFalsePositiveCandidatesForChat:self.chatId
												   completion:^(NSArray *rows, NSString *error){
		TGAntiSpamViewController *page = weakSelf;
		if (!page)
			return;
		page.rows = rows ?: @[];
		page.loadError = error;
		[page rebuildSections];
	}];
	[self rebuildSections];
}

- (void)rebuildSections {
	NSMutableArray *rows = [NSMutableArray array];
	for (NSDictionary *candidate in self.rows){
		NSDate *date = [NSDate dateWithTimeIntervalSince1970:
				[candidate[@"date"] doubleValue]];
		NSDateFormatter *formatter = [[NSDateFormatter alloc] init];
		formatter.dateStyle = NSDateFormatterShortStyle;
		formatter.timeStyle = NSDateFormatterShortStyle;
		NSString *when = [formatter stringFromDate:date];
		NSString *detail = [NSString stringWithFormat:@"%@  %@",
				candidate[@"text"] ?: @"Deleted message", when];
		NSMutableDictionary *row = [TGBAction(
				[NSString stringWithFormat:@"Message %@", candidate[@"messageId"] ?: @0],
				detail, @"report") mutableCopy];
		row[@"candidate"] = candidate;
		[rows addObject:row];
	}
	if (!rows.count){
		[rows addObject:TGBInfo(@"No reportable deletions",
				self.loadError.length ? self.loadError
						: @"Telegram did not return a deleted message marked "
						  @"as a false positive.")];
	}

	self.sections = @[
		TGBSection(@"AGGRESSIVE ANTI-SPAM",
				@"Messages Telegram deleted on suspicion appear here only when "
				@"the event log says they may be reported. A report asks "
				@"Telegram to restore the message.", rows),
	];
	[self rebuild];
}

- (void)didChooseAction:(NSString *)action row:(NSDictionary *)row {
	if (![action isEqualToString:@"report"])
		return;
	NSDictionary *candidate = row[@"candidate"];
	int64_t messageId = [candidate[@"messageId"] longLongValue];
	__weak typeof(self) weakSelf = self;
	[TGAlertSheet showConfirm:@"Report this deletion as a false positive? Telegram "
			@"will review the message."
						title:@"Report False Positive"
					   action:@"Report"
				  destructive:NO
					   inView:self.view
					onConfirm:^{
		[[TGClient shared] reportAntiSpamFalsePositiveInChat:weakSelf.chatId
												  messageId:messageId
												 completion:^(BOOL ok, NSString *error){
			TGAntiSpamViewController *page = weakSelf;
			if (!page)
				return;
			if (!ok){
				[page showResult:NO error:error title:@"Anti-Spam"];
				return;
			}
			NSMutableArray *left = [NSMutableArray array];
			for (NSDictionary *other in page.rows)
				if ([other[@"messageId"] longLongValue] != messageId)
					[left addObject:other];
			page.rows = left;
			[page rebuildSections];
			[page showResult:YES error:nil title:@"Anti-Spam"];
		}];
	}];
}

@end

// vim:ft=objc
