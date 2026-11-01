//
// TGSupportInfoViewController.m
//
// getSupportName and the two UserSupportInfo calls are plumbing for Telegram
// support staff. A normal account often gets a refusal; the page prints the
// sentence instead of pretending the note was saved.
//
#import "TGSupportInfoViewController.h"
#import "TGClient.h"

@interface TGSupportInfoViewController ()
@property (nonatomic, assign) int64_t userId;
@property (nonatomic, copy) NSString *message;
@property (nonatomic, strong) NSArray *answerLines;
@end

@implementation TGSupportInfoViewController

- (instancetype)init {
	if ((self = [super init])){
		_answerLines = @[@"Load the support name or one user's support note."];
	}
	return self;
}

- (void)viewDidLoad {
	[super viewDidLoad];
	self.title = @"Support Info";
	[self rebuildSections];
}

- (void)rebuildSections {
	NSMutableArray *identity = [NSMutableArray array];
	[identity addObject:TGBAction(@"User ID", self.userId
			? [NSString stringWithFormat:@"%lld", self.userId] : @"Set", @"userId")];
	[identity addObject:TGBAction(@"Note", self.message.length ? self.message : @"Set",
			@"message")];

	NSMutableArray *reads = [NSMutableArray array];
	[reads addObject:TGBAction(@"Support Name", nil, @"name")];
	[reads addObject:TGBAction(@"User Support Info", nil, @"read")];

	NSMutableArray *write = [NSMutableArray array];
	[write addObject:TGBAction(@"Set User Support Info", nil, @"write")];

	NSMutableArray *answers = [NSMutableArray array];
	for (NSString *line in self.answerLines)
		[answers addObject:TGBInfo(line, nil)];

	self.sections = @[
		TGBSection(@"SUPPORT", @"The name is Telegram's own label for the "
				@"support account. The note is per user and may be refused for "
				@"an account without support rights.", identity),
		TGBSection(@"READ", nil, reads),
		TGBSection(@"WRITE", nil, write),
		TGBSection(@"ANSWER", nil, answers),
	];
	[self rebuild];
}

- (void)showAnswer:(NSString *)text title:(NSString *)title {
	self.answerLines = @[text.length ? text : @"Telegram answered with an empty value."];
	[self rebuildSections];
	[self showMessage:self.answerLines.firstObject title:title];
}

- (void)finish:(BOOL)ok error:(NSString *)error title:(NSString *)title {
	self.answerLines = @[ok ? @"Telegram accepted the request."
			: (error.length ? error : @"Telegram refused that.")];
	[self rebuildSections];
	if (!ok)
		[self showMessage:self.answerLines.firstObject title:title];
}

- (void)didChooseAction:(NSString *)action row:(NSDictionary *)row {
	__weak typeof(self) weakSelf = self;
	if ([action isEqualToString:@"userId"] || [action isEqualToString:@"message"]){
		NSString *current = [action isEqualToString:@"userId"]
				? [NSString stringWithFormat:@"%lld", self.userId] : self.message;
		[self askText:([action isEqualToString:@"userId"] ? @"User ID" : @"Note")
			  message:nil placeholder:current text:current action:@"Save"
		   completion:^(NSString *text){
			if ([action isEqualToString:@"userId"]) weakSelf.userId = text.longLongValue;
			else weakSelf.message = text;
			[weakSelf rebuildSections];
		}];
		return;
	}
	if ([action isEqualToString:@"name"]){
		[[TGClient shared] supportNameWithCompletion:^(NSString *name, NSString *error){
			if (error){
				[weakSelf finish:NO error:error title:@"Support Name"];
				return;
			}
			[weakSelf showAnswer:name title:@"Support Name"];
		}];
	} else if ([action isEqualToString:@"read"]){
		[[TGClient shared] supportInfoForUser:self.userId
								  completion:^(NSDictionary *info, NSString *error){
			if (error){
				[weakSelf finish:NO error:error title:@"User Support Info"];
				return;
			}
			NSString *body = [NSString stringWithFormat:@"%@\n- %@",
					info[@"message"] ?: @"", info[@"author"] ?: @"support"];
			[weakSelf showAnswer:body title:@"User Support Info"];
		}];
	} else if ([action isEqualToString:@"write"]){
		[[TGClient shared] setSupportInfo:self.message forUser:self.userId
							   completion:^(NSDictionary *info, NSString *error){
			if (error){
				[weakSelf finish:NO error:error title:@"Set Support Info"];
				return;
			}
			NSString *body = [NSString stringWithFormat:@"Saved: %@",
					info[@"message"] ?: self.message];
			[weakSelf showAnswer:body title:@"Set Support Info"];
		}];
	}
}

@end

// vim:ft=objc
