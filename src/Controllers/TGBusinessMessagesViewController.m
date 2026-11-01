//
// TGBusinessMessagesViewController.m - the business-bot connection and the
// message calls TDLib exposes for it.
//
// These calls are declared "for bots only" in td_api.tl. A user account
// cannot obtain a connection id from TDLib, so this page is where a bot
// session's id is pasted when one is at hand; every request is still the
// real one and every refusal is printed in the Answer section.
//
#import "TGBusinessMessagesViewController.h"
#import "TGClient.h"
#import "TGTheme.h"
#import "TGStyle.h"
#import "TGAlertSheet.h"

#pragma mark - the connection

@interface TGBusinessConnectionViewController ()
@property (nonatomic, copy) NSString *connectionId;
@property (nonatomic, strong) NSDictionary *connection;
@property (nonatomic, copy) NSString *answer;
@end

@implementation TGBusinessConnectionViewController

- (void)viewDidLoad {
	[super viewDidLoad];
	self.title = @"Business Connection";
	self.connectionId = TGBusinessStoredConnectionId();
	if (self.connectionId.length)
		[self readConnection];
	[self rebuildSections];
}

- (void)readConnection {
	__weak typeof(self) weakSelf = self;
	[[TGClient shared] businessConnectionWithId:self.connectionId
									 completion:^(NSDictionary *connection, NSString *error){
		TGBusinessConnectionViewController *page = weakSelf;
		if (!page)
			return;
		page.connection = connection;
		page.answer = error.length ? error
				: [NSString stringWithFormat:@"Connection %@",
						connection[@"id"] ?: @""];
		[page rebuildSections];
	}];
}

- (void)rebuildSections {
	NSMutableArray *rows = [NSMutableArray array];
	[rows addObject:TGBAction(@"Connection ID",
			self.connectionId.length ? self.connectionId : @"Not set", @"connectionId")];
	[rows addObject:TGBAction(@"Read Connection", nil, @"read")];
	[rows addObject:TGBAction(@"Business Messages", @"Send and edit as the business",
			@"messages")];
	if (self.connection){
		[rows addObject:TGBInfo(@"User", [NSString stringWithFormat:@"%@",
				self.connection[@"user_id"] ?: @0])];
		[rows addObject:TGBInfo(@"Enabled",
				[self.connection[@"is_enabled"] boolValue] ? @"Yes" : @"No")];
	}
	if (self.answer.length)
		[rows addObject:TGBInfo(@"Last Answer", self.answer)];

	self.sections = @[
		TGBSection(@"CONNECTION",
				@"A business connection id belongs to a bot that manages the "
				@"business account. A user account has none; getBusinessConnection "
				@"answers with Telegram's refusal.", rows),
	];
	[self rebuild];
}

- (void)didChooseAction:(NSString *)action row:(NSDictionary *)row {
	__weak typeof(self) weakSelf = self;
	if ([action isEqualToString:@"connectionId"]){
		[self askText:@"Connection ID"
			  message:@"The id from a business bot's updateBusinessConnection."
		  placeholder:@"connection id" text:self.connectionId action:@"Save"
		   completion:^(NSString *text){
			weakSelf.connectionId = text;
			TGBusinessStoreConnectionId(text);
			[weakSelf readConnection];
			[weakSelf rebuildSections];
		}];
	} else if ([action isEqualToString:@"read"]){
		[self readConnection];
	} else if ([action isEqualToString:@"messages"]){
		TGBusinessMessagesViewController *messages =
				[[TGBusinessMessagesViewController alloc] init];
		messages.hidesBottomBarWhenPushed = YES;
		[self.navigationController pushViewController:messages animated:YES];
	}
}

@end

#pragma mark - business messages

@interface TGBusinessMessagesViewController ()
@property (nonatomic, copy) NSString *connectionId;
@property (nonatomic, assign) int64_t chatId;
@property (nonatomic, assign) int64_t messageId;
@property (nonatomic, copy) NSString *text;
@property (nonatomic, copy) NSString *mediaPath;
@property (nonatomic, copy) NSString *albumPaths;
@property (nonatomic, assign) BOOL isVideo;
@property (nonatomic, assign) BOOL disableNotification;
@property (nonatomic, assign) BOOL protectContent;
@property (nonatomic, strong) NSArray *answerLines;
@end

@implementation TGBusinessMessagesViewController

- (void)viewDidLoad {
	[super viewDidLoad];
	self.title = @"Business Messages";
	self.connectionId = TGBusinessStoredConnectionId();
	self.answerLines = @[@"No request yet."];
	[self rebuildSections];
}

- (void)rebuildSections {
	NSMutableArray *answers = [NSMutableArray array];
	for (NSString *line in self.answerLines)
		[answers addObject:TGBInfo(line, nil)];

	self.sections = @[
		TGBSection(@"CONNECTION",
				@"Every call below carries this id. Empty is still sent, so "
				@"Telegram's own refusal is what appears in Answer.",
				@[
			TGBInfo(@"Connection ID",
					self.connectionId.length ? self.connectionId : @"Not set"),
			TGBAction(@"Change Connection ID", nil, @"connection"),
		]),
		TGBSection(@"TARGET", nil, @[
			TGBAction(@"Chat ID", [NSString stringWithFormat:@"%lld",
					(long long)self.chatId], @"chat"),
			TGBAction(@"Message ID", [NSString stringWithFormat:@"%lld",
					(long long)self.messageId], @"message"),
			TGBAction(@"Message Text", self.text.length ? self.text : @"Set", @"text"),
		]),
		TGBSection(@"SEND", @"The first message is a text. An album takes two to ten local photos.",
				@[
			TGBSwitch(@"Disable Notification", nil, @"silent",
					self.disableNotification, YES),
			TGBSwitch(@"Protect Content", nil, @"protect", self.protectContent, YES),
			TGBAction(@"Send Message", nil, @"send"),
			TGBAction(@"Album Paths", self.albumPaths.length
					? self.albumPaths : @"Comma-separated local paths", @"albumPaths"),
			TGBAction(@"Send Album", nil, @"sendAlbum"),
		]),
		TGBSection(@"EDIT", nil, @[
			TGBAction(@"Edit Text", nil, @"editText"),
			TGBAction(@"Edit Caption", nil, @"editCaption"),
			TGBAction(@"Media Path", self.mediaPath.length ? self.mediaPath : @"Set",
					@"mediaPath"),
			TGBSwitch(@"Media Is Video", nil, @"video", self.isVideo, YES),
			TGBAction(@"Edit Media", nil, @"editMedia"),
			TGBAction(@"Edit Checklist", nil, @"editChecklist"),
			TGBAction(@"Edit Live Location", nil, @"liveLocation"),
			TGBAction(@"Clear Reply Markup", nil, @"clearMarkup"),
			TGBAction(@"Stop Poll", nil, @"stopPoll"),
		]),
		TGBSection(@"MESSAGE", nil, @[
			TGBAction(@"Read Message", nil, @"read"),
			TGBAction(@"Pin Message", nil, @"pin"),
			TGBAction(@"Unpin Message", nil, @"unpin"),
			TGBAction(@"Delete Messages", @"Uses Message ID", @"delete"),
		]),
		TGBSection(@"ANSWER", @"Telegram's reply to the last request.",
				answers),
	];
	[self rebuild];
}

- (void)finishOK:(BOOL)ok error:(NSString *)error title:(NSString *)title {
	if (ok)
		self.answerLines = @[@"Telegram accepted the request."];
	else
		self.answerLines = @[error.length ? error : @"Telegram refused that."];
	[self rebuildSections];
	if (!ok)
		[self showResult:NO error:error title:title];
}

- (void)finishMessage:(NSDictionary *)message error:(NSString *)error
				title:(NSString *)title {
	if (error.length || !message){
		[self finishOK:NO error:error title:title];
		return;
	}
	NSNumber *messageId = message[@"message"][@"id"] ?: message[@"id"];
	self.answerLines = @[[NSString stringWithFormat:@"Message %@ answered.",
			messageId ?: @"?"]];
	if (messageId)
		self.messageId = [messageId longLongValue];
	[self rebuildSections];
}

- (NSArray *)albumPathList {
	NSMutableArray *paths = [NSMutableArray array];
	for (NSString *part in [self.albumPaths componentsSeparatedByString:@","]){
		NSString *path = [part stringByTrimmingCharactersInSet:
				[NSCharacterSet whitespaceAndNewlineCharacterSet]];
		if (path.length)
			[paths addObject:path];
	}
	return paths;
}

- (void)didChooseAction:(NSString *)action row:(NSDictionary *)row {
	__weak typeof(self) weakSelf = self;
	if ([action isEqualToString:@"connection"]){
		[self askText:@"Connection ID" message:nil placeholder:@"connection id"
				 text:self.connectionId action:@"Save" completion:^(NSString *text){
			weakSelf.connectionId = text;
			TGBusinessStoreConnectionId(text);
			[weakSelf rebuildSections];
		}];
	} else if ([action isEqualToString:@"chat"]){
		[self askText:@"Chat ID" message:nil placeholder:@"123456789"
				 text:[NSString stringWithFormat:@"%lld", (long long)self.chatId]
			   action:@"Save" completion:^(NSString *text){
			weakSelf.chatId = [text longLongValue];
			[weakSelf rebuildSections];
		}];
	} else if ([action isEqualToString:@"message"]){
		[self askText:@"Message ID" message:nil placeholder:@"123"
				 text:[NSString stringWithFormat:@"%lld", (long long)self.messageId]
			   action:@"Save" completion:^(NSString *text){
			weakSelf.messageId = [text longLongValue];
			[weakSelf rebuildSections];
		}];
	} else if ([action isEqualToString:@"text"]){
		[self askText:@"Message Text" message:nil placeholder:@"Text"
				 text:self.text action:@"Save" completion:^(NSString *text){
			weakSelf.text = text;
			[weakSelf rebuildSections];
		}];
	} else if ([action isEqualToString:@"albumPaths"]){
		[self askText:@"Album Paths"
			  message:@"Two to ten local photo paths, separated by commas."
		  placeholder:@"/tmp/a.jpg, /tmp/b.jpg" text:self.albumPaths action:@"Save"
		   completion:^(NSString *text){
			weakSelf.albumPaths = text;
			[weakSelf rebuildSections];
		}];
	} else if ([action isEqualToString:@"mediaPath"]){
		[self askText:@"Media Path" message:nil placeholder:@"/tmp/photo.jpg"
				 text:self.mediaPath action:@"Save" completion:^(NSString *text){
			weakSelf.mediaPath = text;
			[weakSelf rebuildSections];
		}];
	} else if ([action isEqualToString:@"send"]){
		[[TGClient shared] sendBusinessMessageWithConnectionId:self.connectionId
													   chatId:self.chatId
														 text:self.text
										  disableNotification:self.disableNotification
											 protectContent:self.protectContent
												  completion:^(NSDictionary *message, NSString *error){
			[weakSelf finishMessage:message error:error title:@"Send Business Message"];
		}];
	} else if ([action isEqualToString:@"sendAlbum"]){
		[[TGClient shared] sendBusinessMessageAlbumWithConnectionId:self.connectionId
														   chatId:self.chatId
															paths:[self albumPathList]
														  caption:self.text
											  disableNotification:self.disableNotification
												 protectContent:self.protectContent
													  completion:^(NSArray *messages, NSString *error){
			if (error.length || !messages.count){
				[weakSelf finishOK:NO error:error title:@"Send Business Album"];
				return;
			}
			weakSelf.answerLines = @[[NSString stringWithFormat:@"%lu messages answered.",
					(unsigned long)messages.count]];
			[weakSelf rebuildSections];
		}];
	} else if ([action isEqualToString:@"editText"]){
		[[TGClient shared] editBusinessMessageTextWithConnectionId:self.connectionId
														   chatId:self.chatId
														messageId:self.messageId
															 text:self.text
													   completion:^(NSDictionary *message, NSString *error){
			[weakSelf finishMessage:message error:error title:@"Edit Business Text"];
		}];
	} else if ([action isEqualToString:@"editCaption"]){
		[[TGClient shared] editBusinessMessageCaptionWithConnectionId:self.connectionId
															  chatId:self.chatId
														   messageId:self.messageId
															 caption:self.text
														  completion:^(NSDictionary *message, NSString *error){
			[weakSelf finishMessage:message error:error title:@"Edit Business Caption"];
		}];
	} else if ([action isEqualToString:@"editMedia"]){
		if (!self.mediaPath.length){
			[self showMessage:@"Set the media path first." title:@"Edit Business Media"];
			return;
		}
		[[TGClient shared] editBusinessMessageMediaWithConnectionId:self.connectionId
															chatId:self.chatId
														 messageId:self.messageId
															  path:self.mediaPath
														   isVideo:self.isVideo
														   caption:self.text
														completion:^(NSDictionary *message, NSString *error){
			[weakSelf finishMessage:message error:error title:@"Edit Business Media"];
		}];
	} else if ([action isEqualToString:@"editChecklist"]){
		[self askText:@"Checklist Title" message:nil placeholder:@"Checklist"
				 text:nil action:@"Next" completion:^(NSString *title){
			[weakSelf askText:@"Checklist Tasks"
					  message:@"Task texts, separated by commas."
				  placeholder:@"First, Second, Third" text:nil action:@"Save"
				   completion:^(NSString *tasks){
				NSArray *parts = [tasks componentsSeparatedByString:@","];
				[[TGClient shared] editBusinessMessageChecklistWithConnectionId:weakSelf.connectionId
																	  chatId:weakSelf.chatId
																   messageId:weakSelf.messageId
																	   title:title
																	   tasks:parts
																	completion:^(NSDictionary *message, NSString *error){
					[weakSelf finishMessage:message error:error title:@"Business Checklist"];
				}];
			}];
		}];
	} else if ([action isEqualToString:@"liveLocation"]){
		[self askText:@"Latitude" message:nil placeholder:@"50.4501" text:nil
			   action:@"Next" completion:^(NSString *lat){
			double latitude = [lat doubleValue];
			[weakSelf askText:@"Longitude" message:nil placeholder:@"30.5234" text:nil
				   action:@"Next" completion:^(NSString *lon){
				double longitude = [lon doubleValue];
				[weakSelf askText:@"Live Period" message:@"Seconds; 0 stops sharing."
					  placeholder:@"900" text:@"900" action:@"Save"
					   completion:^(NSString *seconds){
					[[TGClient shared] editBusinessMessageLiveLocationWithConnectionId:weakSelf.connectionId
																			  chatId:weakSelf.chatId
																		   messageId:weakSelf.messageId
																			latitude:latitude
																		   longitude:longitude
																		  livePeriod:[seconds integerValue]
																		  completion:^(NSDictionary *message, NSString *error){
						[weakSelf finishMessage:message error:error title:@"Business Live Location"];
					}];
				}];
			}];
		}];
	} else if ([action isEqualToString:@"clearMarkup"]){
		[[TGClient shared] editBusinessMessageReplyMarkupWithConnectionId:self.connectionId
																 chatId:self.chatId
															  messageId:self.messageId
															 completion:^(NSDictionary *message, NSString *error){
			[weakSelf finishMessage:message error:error title:@"Business Reply Markup"];
		}];
	} else if ([action isEqualToString:@"stopPoll"]){
		[[TGClient shared] stopBusinessPollWithConnectionId:self.connectionId
													chatId:self.chatId
												 messageId:self.messageId
												completion:^(NSDictionary *message, NSString *error){
			[weakSelf finishMessage:message error:error title:@"Stop Business Poll"];
		}];
	} else if ([action isEqualToString:@"read"]){
		[[TGClient shared] readBusinessMessageWithConnectionId:self.connectionId
													   chatId:self.chatId
													messageId:self.messageId
												   completion:^(BOOL ok, NSString *error){
			[weakSelf finishOK:ok error:error title:@"Read Business Message"];
		}];
	} else if ([action isEqualToString:@"pin"] || [action isEqualToString:@"unpin"]){
		BOOL pinned = [action isEqualToString:@"pin"];
		[[TGClient shared] setBusinessMessagePinnedWithConnectionId:self.connectionId
															 chatId:self.chatId
														  messageId:self.messageId
															 pinned:pinned
														 completion:^(BOOL ok, NSString *error){
			[weakSelf finishOK:ok error:error title:pinned ? @"Pin Business Message" : @"Unpin Business Message"];
		}];
	} else if ([action isEqualToString:@"delete"]){
		[self askText:@"Delete Messages"
			  message:@"Message ids separated by commas. Empty uses the Message ID above."
		  placeholder:@"123, 124"
				 text:nil action:@"Delete" completion:^(NSString *text){
			NSMutableArray *ids = [NSMutableArray array];
			for (NSString *part in [text componentsSeparatedByString:@","]){
				NSString *trimmed = [part stringByTrimmingCharactersInSet:
						[NSCharacterSet whitespaceAndNewlineCharacterSet]];
				if (trimmed.length)
					[ids addObject:@([trimmed longLongValue])];
			}
			if (!ids.count && weakSelf.messageId)
				[ids addObject:@(weakSelf.messageId)];
			[[TGClient shared] deleteBusinessMessagesWithConnectionId:weakSelf.connectionId
														   messageIds:ids
														   completion:^(BOOL ok, NSString *error){
				[weakSelf finishOK:ok error:error title:@"Delete Business Messages"];
			}];
		}];
	}
}

- (void)toggleKey:(NSString *)key on:(BOOL)on sender:(UISwitch *)sender {
	if ([key isEqualToString:@"silent"]) self.disableNotification = on;
	else if ([key isEqualToString:@"protect"]) self.protectContent = on;
	else if ([key isEqualToString:@"video"]) self.isVideo = on;
	[self rebuildSections];
}

@end

// vim:ft=objc
