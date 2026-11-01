//
// TGGameScoresViewController.m
//
// Telegram keeps a game's score table behind the bot that serves it. A user
// session can send the two reads and the two writes, and the server decides;
// this screen shows its answer, including the refusal. Nothing here invents
// a score or a leaderboard.
//
#import "TGGameScoresViewController.h"
#import "TGClient.h"
#import "TGAlertSheet.h"

@interface TGGameScoresViewController ()
@property (nonatomic, copy) NSString *inlineMessageId;
@property (nonatomic, copy) NSString *scoreText;
@property (nonatomic, assign) int64_t userId;
@property (nonatomic, assign) BOOL editMessage;
@property (nonatomic, assign) BOOL force;
@property (nonatomic, strong) NSArray *answerLines;
@end

@implementation TGGameScoresViewController

- (instancetype)init {
	if ((self = [super init])){
		_scoreText = @"0";
		_editMessage = YES;
		_force = NO;
		_answerLines = @[@"Load a game message's high scores or set one score."];
	}
	return self;
}

- (void)viewDidLoad {
	[super viewDidLoad];
	self.title = @"Game Scores";
	[self rebuildSections];
}

- (void)rebuildSections {
	NSMutableArray *ids = [NSMutableArray array];
	[ids addObject:TGBAction(@"Chat ID", self.chatId
			? [NSString stringWithFormat:@"%lld", self.chatId] : @"Set", @"chatId")];
	[ids addObject:TGBAction(@"Message ID", self.messageId
			? [NSString stringWithFormat:@"%lld", self.messageId] : @"Set",
			@"messageId")];
	[ids addObject:TGBAction(@"User ID", self.userId
			? [NSString stringWithFormat:@"%lld", self.userId] : @"Set", @"userId")];
	[ids addObject:TGBAction(@"Inline Message ID",
			self.inlineMessageId.length ? self.inlineMessageId : @"Set",
			@"inline")];
	[ids addObject:TGBAction(@"Score", self.scoreText, @"score")];
	[ids addObject:TGBAction(@"Edit Message",
			self.editMessage ? @"On - tap to turn off" : @"Off - tap to turn on",
			@"edit")];
	[ids addObject:TGBAction(@"Force",
			self.force ? @"On - tap to turn off" : @"Off - tap to turn on",
			@"force")];

	NSMutableArray *reads = [NSMutableArray array];
	[reads addObject:TGBAction(@"Get Game High Scores", nil, @"read")];
	[reads addObject:TGBAction(@"Get Inline High Scores", nil, @"readInline")];

	NSMutableArray *writes = [NSMutableArray array];
	[writes addObject:TGBAction(@"Set Game Score", nil, @"write")];
	[writes addObject:TGBAction(@"Set Inline Score", nil, @"writeInline")];

	NSMutableArray *answers = [NSMutableArray array];
	for (NSString *line in self.answerLines)
		[answers addObject:TGBInfo(line, nil)];

	self.sections = @[
		TGBSection(@"GAME", @"A game message carries chat and message ids; an "
				@"inline game is played outside a chat and carries only the "
				@"inline_message_id the bot returned.", ids),
		TGBSection(@"READ", @"Reading a table is served by the game's bot, so a "
				@"user session often gets Telegram's refusal.", reads),
		TGBSection(@"WRITE", @"The score is the bot's to write. The refusal is "
				@"shown; no local table is changed.", writes),
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

- (void)showScores:(NSArray *)scores title:(NSString *)title {
	if (!scores.count){
		[self showAnswer:@"Telegram returned an empty score table." title:title];
		return;
	}
	NSMutableArray *lines = [NSMutableArray array];
	for (NSDictionary *score in scores){
		[lines addObject:[NSString stringWithFormat:@"#%@  user %@  %@",
				score[@"position"] ?: @0, score[@"userId"] ?: @0,
				score[@"score"] ?: @0]];
	}
	[self showAnswer:[lines componentsJoinedByString:@"\n"] title:title];
}

- (void)didChooseAction:(NSString *)action row:(NSDictionary *)row {
	__weak typeof(self) weakSelf = self;
	if ([action isEqualToString:@"chatId"] || [action isEqualToString:@"messageId"] ||
			[action isEqualToString:@"userId"] || [action isEqualToString:@"inline"] ||
			[action isEqualToString:@"score"]){
		NSString *current = @"";
		NSString *title = action;
		if ([action isEqualToString:@"chatId"]){ current = [NSString stringWithFormat:@"%lld", self.chatId]; title = @"Chat ID"; }
		if ([action isEqualToString:@"messageId"]){ current = [NSString stringWithFormat:@"%lld", self.messageId]; title = @"Message ID"; }
		if ([action isEqualToString:@"userId"]){ current = [NSString stringWithFormat:@"%lld", self.userId]; title = @"User ID"; }
		if ([action isEqualToString:@"inline"]){ current = self.inlineMessageId; title = @"Inline Message ID"; }
		if ([action isEqualToString:@"score"]){ current = self.scoreText; title = @"Score"; }
		[self askText:title message:nil placeholder:current text:current
			   action:@"Save" completion:^(NSString *text){
			if ([action isEqualToString:@"chatId"]) weakSelf.chatId = text.longLongValue;
			if ([action isEqualToString:@"messageId"]) weakSelf.messageId = text.longLongValue;
			if ([action isEqualToString:@"userId"]) weakSelf.userId = text.longLongValue;
			if ([action isEqualToString:@"inline"]) weakSelf.inlineMessageId = text;
			if ([action isEqualToString:@"score"]) weakSelf.scoreText = text;
			[weakSelf rebuildSections];
		}];
		return;
	}
	if ([action isEqualToString:@"edit"]){
		self.editMessage = !self.editMessage;
		[self rebuildSections];
		return;
	}
	if ([action isEqualToString:@"force"]){
		self.force = !self.force;
		[self rebuildSections];
		return;
	}

	int32_t score = self.scoreText.intValue;
	if ([action isEqualToString:@"read"]){
		[[TGClient shared] gameHighScoresForChat:self.chatId
										 message:self.messageId
											user:self.userId
									  completion:^(NSArray *scores, NSString *error){
			if (error){
				[weakSelf finish:NO error:error title:@"Game High Scores"];
				return;
			}
			[weakSelf showScores:scores title:@"Game High Scores"];
		}];
	} else if ([action isEqualToString:@"readInline"]){
		[[TGClient shared] inlineGameHighScores:self.inlineMessageId
										   user:self.userId
									 completion:^(NSArray *scores, NSString *error){
			if (error){
				[weakSelf finish:NO error:error title:@"Inline High Scores"];
				return;
			}
			[weakSelf showScores:scores title:@"Inline High Scores"];
		}];
	} else if ([action isEqualToString:@"write"]){
		[[TGClient shared] setGameScoreForChat:self.chatId
									   message:self.messageId
										  user:self.userId
										 score:score
										 force:self.force
								   editMessage:self.editMessage
									completion:^(NSDictionary *message, NSString *error){
			if (error){
				[weakSelf finish:NO error:error title:@"Set Game Score"];
				return;
			}
			[weakSelf showAnswer:[NSString stringWithFormat:@"Message #%@: %@",
					message[@"id"] ?: @0, message[@"text"] ?: @""]
						   title:@"Set Game Score"];
		}];
	} else if ([action isEqualToString:@"writeInline"]){
		[[TGClient shared] setInlineGameScore:self.inlineMessageId
										 user:self.userId
										score:score
										force:self.force
								  editMessage:self.editMessage
								   completion:^(BOOL ok, NSString *error){
			[weakSelf finish:ok error:error title:@"Set Inline Score"];
		}];
	}
}

@end

// vim:ft=objc
