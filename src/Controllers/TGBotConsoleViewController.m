//
// TGBotConsoleViewController.m - the half of the bot API a user account can
// call: editing bots it owns, choosing an attachment-menu bot, starting a bot,
// reading recent inline bots, and answering an OAuth link.
//
// Bot sessions answer inline queries and callbacks; those calls live in the
// bot-session half of Tier 3 and are not here. Every row below names a
// request whose `can_be_edited` guard the *user* satisfies.
//
#import "TGBotConsoleViewController.h"
#import "TGClient.h"
#import "TGAlertSheet.h"
#import "TGStyle.h"

@interface TGBotConsoleViewController ()
@property (nonatomic, copy) NSString *language;
@property (nonatomic, copy) NSString *username;
@property (nonatomic, copy) NSString *oauthURL;
@property (nonatomic, copy) NSString *oauthCode;
@property (nonatomic, strong) NSArray *answerLines;
@end

@implementation TGBotConsoleViewController

- (instancetype)init {
	if ((self = [super init])){
		_language = @"en";
		_answerLines = @[@"A bot id is needed for every row below."];
	}
	return self;
}

- (void)viewDidLoad {
	[super viewDidLoad];
	self.title = @"Bot Console";
	[self rebuildSections];
}

- (void)rebuildSections {
	NSMutableArray *identity = [NSMutableArray array];
	[identity addObject:TGBAction(@"Bot User ID", self.botUserId
			? [NSString stringWithFormat:@"%lld", self.botUserId] : @"Set", @"botId")];
	[identity addObject:TGBAction(@"Load Owned Bots", nil, @"owned")];
	[identity addObject:TGBAction(@"Language", self.language.length ? self.language : @"en",
			@"language")];
	[identity addObject:TGBAction(@"Read Name", nil, @"readName")];
	[identity addObject:TGBAction(@"Set Name", nil, @"setName")];
	[identity addObject:TGBAction(@"Read Description", nil, @"readDescription")];
	[identity addObject:TGBAction(@"Set Description", nil, @"setDescription")];
	[identity addObject:TGBAction(@"Read Short Description", nil, @"readShort")];
	[identity addObject:TGBAction(@"Set Short Description", nil, @"setShort")];
	[identity addObject:TGBAction(@"Remove Profile Photo", nil, @"removePhoto")];

	NSMutableArray *usernames = [NSMutableArray array];
	[usernames addObject:TGBAction(@"Check Bot Username", nil, @"checkUsername")];
	[usernames addObject:TGBAction(@"Add Secondary Username", nil, @"addSecondary")];
	[usernames addObject:TGBAction(@"Delete Secondary Username", nil, @"deleteSecondary")];
	[usernames addObject:TGBAction(@"Activate Username", nil, @"activateUsername")];
	[usernames addObject:TGBAction(@"Deactivate Username", nil, @"deactivateUsername")];
	[usernames addObject:TGBAction(@"Reorder Active Usernames", nil, @"reorderUsernames")];

	NSMutableArray *media = [NSMutableArray array];
	[media addObject:TGBAction(@"Load Media Previews", nil, @"loadPreviews")];
	[media addObject:TGBAction(@"Preview Info", nil, @"previewInfo")];
	[media addObject:TGBAction(@"Add Preview From File", nil, @"addPreview")];
	[media addObject:TGBAction(@"Edit Preview", nil, @"editPreview")];
	[media addObject:TGBAction(@"Delete Previews", nil, @"deletePreviews")];
	[media addObject:TGBAction(@"Reorder Previews", nil, @"reorderPreviews")];

	NSMutableArray *otherBots = [NSMutableArray array];
	[otherBots addObject:TGBAction(@"Similar Bot Count (local)", nil, @"similarCount")];
	[otherBots addObject:TGBAction(@"Similar Bots", nil, @"similarBots")];
	[otherBots addObject:TGBAction(@"Open Similar Bot", nil, @"openSimilar")];
	[otherBots addObject:TGBAction(@"Let This Bot Manage My Emoji Status",
			nil, @"emojiStatus")];

	NSMutableArray *userSide = [NSMutableArray array];
	[userSide addObject:TGBAction(@"Recent Inline Bots", nil, @"recentInline")];
	[userSide addObject:TGBAction(@"Attachment Menu Bot", nil, @"attachment")];
	[userSide addObject:TGBAction(@"Add To Attachment Menu", nil, @"attachAdd")];
	[userSide addObject:TGBAction(@"Remove From Attachment Menu", nil, @"attachRemove")];
	[userSide addObject:TGBAction(@"Can This Bot Message Me?", nil, @"canSend")];
	[userSide addObject:TGBAction(@"Allow This Bot To Message Me", nil, @"allowSend")];
	[userSide addObject:TGBAction(@"Start Bot In Chat", nil, @"startBot")];
	[userSide addObject:TGBAction(@"Add Inline Result To Saved Reply", nil, @"inlineResult")];

	NSMutableArray *browser = [NSMutableArray array];
	[browser addObject:TGBAction(@"Open Links Externally", nil, @"browserDefault")];
	[browser addObject:TGBAction(@"Add Browser Exception", nil, @"browserAdd")];
	[browser addObject:TGBAction(@"Remove Browser Exception", nil, @"browserRemove")];
	[browser addObject:TGBAction(@"Remove All Browser Exceptions", nil, @"browserRemoveAll")];
	[browser addObject:TGBAction(@"Grossing Web App Bots", nil, @"grossing")];
	[browser addObject:TGBAction(@"Search Web App", nil, @"searchApp")];
	[browser addObject:TGBAction(@"Web App Placeholder", nil, @"placeholder")];
	[browser addObject:TGBAction(@"Web App URL", nil, @"webAppUrl")];
	[browser addObject:TGBAction(@"Main Web App URL", nil, @"mainWebApp")];
	[browser addObject:TGBAction(@"Web App Link URL", nil, @"webAppLink")];
	[browser addObject:TGBAction(@"Share A Chat With A Bot", nil, @"shareChat")];
	[browser addObject:TGBAction(@"Share Users With A Bot", nil, @"shareUsers")];

	NSMutableArray *verification = [NSMutableArray array];
	[verification addObject:TGBAction(@"Verify A User Or Chat", nil, @"verify")];
	[verification addObject:TGBAction(@"Remove Verification", nil, @"unverify")];
	[verification addObject:TGBAction(@"Create Bot", nil, @"createBot")];

	NSMutableArray *oauth = [NSMutableArray array];
	[oauth addObject:TGBAction(@"OAuth Link",
			self.oauthURL.length ? self.oauthURL : @"Set", @"oauthURL")];
	[oauth addObject:TGBAction(@"Match Code",
			self.oauthCode.length ? self.oauthCode : @"Set", @"oauthCode")];
	[oauth addObject:TGBAction(@"Read OAuth Link", nil, @"oauthInfo")];
	[oauth addObject:TGBAction(@"Check Match Code", nil, @"oauthCheck")];
	[oauth addObject:TGBAction(@"Accept OAuth Request", nil, @"oauthAccept")];
	[oauth addObject:TGBAction(@"Decline OAuth Request", nil, @"oauthDecline")];

	NSMutableArray *business = [NSMutableArray array];
	[business addObject:TGBAction(@"Read Connected Business Bot", nil, @"businessRead")];
	[business addObject:TGBAction(@"Connect Business Bot", nil, @"businessSet")];
	[business addObject:TGBAction(@"Confirm Business Bot", nil, @"businessConfirm")];
	[business addObject:TGBAction(@"Delete Business Bot", nil, @"businessDelete")];
	[business addObject:TGBAction(@"Remove Bot From Chat", nil, @"businessRemoveChat")];
	[business addObject:TGBAction(@"Pause Bot In Chat", nil, @"businessPause")];

	NSMutableArray *answers = [NSMutableArray array];
	for (NSString *line in self.answerLines)
		[answers addObject:TGBInfo(line, nil)];

	self.sections = @[
		TGBSection(@"BOT RECORD", @"These calls work when this account owns the "
				@"bot, which is what TDLib's can_be_edited guard checks.",
				identity),
		TGBSection(@"USERNAMES", @"The editable name cannot be turned off while it "
				@"is the only active one; the server says so.", usernames),
		TGBSection(@"MEDIA PREVIEWS", @"Previews are files TDLib already knows; "
				@"the file id comes from a sticker, photo or story upload.",
				media),
		TGBSection(@"OTHER BOTS", @"Discovery around a bot: similar bots and the "
				@"emoji-status permission it may ask for.", otherBots),
		TGBSection(@"USER-SIDE BOT CALLS", @"What a person does with a bot: add "
				@"it to the menu, start it, or take an inline result into a saved "
				@"reply.", userSide),
		TGBSection(@"BROWSER AND WEB APPS", @"How links open and the Web App "
				@"records Telegram keeps. This client has no in-app Web App host, "
				@"so the URL getters copy a link instead of opening one, and the "
				@"two keyboard-button answers are here for a bot that asks.",
				browser),
		TGBSection(@"VERIFICATION AND CREATION", @"An owned bot can verify a user "
				@"or chat; createBot needs a manager bot this account owns.",
				verification),
		TGBSection(@"OAUTH", @"The link is opened in the system browser after "
				@"accept; this client hosts no in-app browser.", oauth),
		TGBSection(@"BUSINESS BOT", @"A Business subscriber connects one bot for "
				@"replies and profile edits.", business),
		TGBSection(@"ANSWER", nil, answers),
	];
	[self rebuild];
}

- (void)finish:(BOOL)ok error:(NSString *)error title:(NSString *)title {
	self.answerLines = @[ok ? @"Telegram accepted the request."
						   : (error.length ? error : @"Telegram refused that.")];
	[self rebuildSections];
	if (!ok)
		[self showMessage:self.answerLines.firstObject title:title];
}

- (void)showText:(NSString *)text title:(NSString *)title {
	self.answerLines = @[text ?: @""];
	[self rebuildSections];
	[self showMessage:text ?: @"" title:title];
}

- (void)askBotId:(NSString *)title action:(void (^)(int64_t botId))action {
	__weak typeof(self) weakSelf = self;
	[self askText:title message:@"Bot user id" placeholder:@"123"
			 text:(self.botUserId
			 ? [NSString stringWithFormat:@"%lld", self.botUserId] : nil)
		   action:@"Next" completion:^(NSString *text){
		int64_t botId = text.longLongValue;
		weakSelf.botUserId = botId;
		[weakSelf rebuildSections];
		action(botId);
	}];
}

- (void)didChooseAction:(NSString *)action row:(NSDictionary *)row {
	__weak typeof(self) weakSelf = self;
	if ([action isEqualToString:@"botId"]){
		[self askBotId:@"Bot User ID" action:^(int64_t botId){}];
	} else if ([action isEqualToString:@"language"]){
		[self askText:@"Language" message:@"Two-letter code, empty for all"
		  placeholder:@"en" text:self.language action:@"Save" completion:^(NSString *text){
			weakSelf.language = text;
			[weakSelf rebuildSections];
		}];
	} else if ([action isEqualToString:@"owned"]){
		[[TGClient shared] ownedBotsWithCompletion:^(NSArray *bots, NSString *error){
			if (error){
				[weakSelf finish:NO error:error title:@"Owned Bots"];
				return;
			}
			NSMutableArray *lines = [NSMutableArray array];
			for (NSDictionary *bot in bots)
				[lines addObject:[NSString stringWithFormat:@"%@  #%@",
						bot[@"name"], bot[@"id"]]];
			[weakSelf showText:(lines.count ? [lines componentsJoinedByString:@"\n"]
					: @"This account owns no bots.") title:@"Owned Bots"];
		}];
	} else if ([action isEqualToString:@"readName"]){
		[self askBotId:@"Read Bot Name" action:^(int64_t botId){
			[[TGClient shared] botNameForBot:botId language:weakSelf.language
								  completion:^(NSString *name, NSString *error){
				[weakSelf finish:error == nil error:error title:@"Bot Name"];
				if (!error) [weakSelf showText:name title:@"Bot Name"];
			}];
		}];
	} else if ([action isEqualToString:@"setName"]){
		[self askBotId:@"Set Bot Name" action:^(int64_t botId){
			[weakSelf askText:@"Set Bot Name" message:nil placeholder:@"My Bot"
						 text:nil action:@"Save" completion:^(NSString *text){
				[[TGClient shared] setBotName:text forBot:botId
									 language:weakSelf.language
								   completion:^(BOOL ok, NSString *error){
					[weakSelf finish:ok error:error title:@"Bot Name"];
				}];
			}];
		}];
	} else if ([action isEqualToString:@"readDescription"]){
		[self askBotId:@"Read Description" action:^(int64_t botId){
			[[TGClient shared] botDescriptionForBot:botId language:weakSelf.language
										 completion:^(NSString *text, NSString *error){
				[weakSelf finish:error == nil error:error title:@"Bot Description"];
				if (!error) [weakSelf showText:text title:@"Bot Description"];
			}];
		}];
	} else if ([action isEqualToString:@"setDescription"]){
		[self askBotId:@"Set Description" action:^(int64_t botId){
			[weakSelf askText:@"Set Description" message:@"Shown in an empty chat"
						 placeholder:@"What the bot does" text:nil
					   action:@"Save" completion:^(NSString *text){
				[[TGClient shared] setBotDescription:text forBot:botId
										   language:weakSelf.language
										 completion:^(BOOL ok, NSString *error){
					[weakSelf finish:ok error:error title:@"Bot Description"];
				}];
			}];
		}];
	} else if ([action isEqualToString:@"readShort"]){
		[self askBotId:@"Read Short Description" action:^(int64_t botId){
			[[TGClient shared] botShortDescriptionForBot:botId
												language:weakSelf.language
											  completion:^(NSString *text, NSString *error){
				[weakSelf finish:error == nil error:error title:@"Short Description"];
				if (!error) [weakSelf showText:text title:@"Short Description"];
			}];
		}];
	} else if ([action isEqualToString:@"setShort"]){
		[self askBotId:@"Set Short Description" action:^(int64_t botId){
			[weakSelf askText:@"Set Short Description" message:@"Shown on the profile"
						 placeholder:@"A one-line summary" text:nil action:@"Save"
				   completion:^(NSString *text){
				[[TGClient shared] setBotShortDescription:text forBot:botId
												language:weakSelf.language
											  completion:^(BOOL ok, NSString *error){
					[weakSelf finish:ok error:error title:@"Short Description"];
				}];
			}];
		}];
	} else if ([action isEqualToString:@"removePhoto"]){
		[self askBotId:@"Remove Bot Photo" action:^(int64_t botId){
			[[TGClient shared] removeBotProfilePhoto:botId
										  completion:^(BOOL ok, NSString *error){
				[weakSelf finish:ok error:error title:@"Bot Photo"];
			}];
		}];
	} else if ([action isEqualToString:@"checkUsername"]){
		[self askText:@"Check Bot Username" message:nil placeholder:@"mybot"
				 text:self.username action:@"Next" completion:^(NSString *text){
			weakSelf.username = text;
			[TGAlertSheet showChoices:@[@"As a new bot name", @"As a secondary name"]
								title:@"Check Bot Username" destructiveIndex:-1
							   inView:weakSelf.view onChoice:^(NSInteger index){
				[[TGClient shared] checkBotUsername:text isSecondary:(index == 1)
										 completion:^(NSString *result, NSString *error){
					[weakSelf finish:error == nil error:error title:@"Bot Username"];
					if (!error) [weakSelf showText:result title:@"Bot Username"];
				}];
			}];
		}];
	} else if ([action isEqualToString:@"addSecondary"]){
		[self askBotId:@"Add Secondary Username" action:^(int64_t botId){
			[weakSelf askText:@"Add Secondary Username" message:nil placeholder:@"mybot2"
						 text:nil action:@"Add" completion:^(NSString *text){
				[[TGClient shared] addBotSecondaryUsername:text forBot:botId
												completion:^(BOOL ok, NSString *error){
					[weakSelf finish:ok error:error title:@"Bot Username"];
				}];
			}];
		}];
	} else if ([action isEqualToString:@"deleteSecondary"]){
		[self askBotId:@"Delete Secondary Username" action:^(int64_t botId){
			[[TGClient shared] deleteBotSecondaryUsernameForBot:botId
													 completion:^(BOOL ok, NSString *error){
				[weakSelf finish:ok error:error title:@"Bot Username"];
			}];
		}];
	} else if ([action isEqualToString:@"activateUsername"] ||
			   [action isEqualToString:@"deactivateUsername"]){
		BOOL active = [action isEqualToString:@"activateUsername"];
		[self askBotId:(active ? @"Activate Username" : @"Deactivate Username")
			   action:^(int64_t botId){
			[weakSelf askText:@"Bot Username" message:nil placeholder:@"mybot"
						 text:nil action:@"Send" completion:^(NSString *text){
				[[TGClient shared] setBotUsername:text active:active forBot:botId
									   completion:^(BOOL ok, NSString *error){
					[weakSelf finish:ok error:error title:@"Bot Username"];
				}];
			}];
		}];
	} else if ([action isEqualToString:@"reorderUsernames"]){
		[self askBotId:@"Reorder Usernames" action:^(int64_t botId){
			[weakSelf askText:@"Reorder Usernames" message:@"Comma separated, in order"
						 placeholder:@"one,two" text:nil action:@"Send"
				   completion:^(NSString *text){
				NSMutableArray *names = [NSMutableArray array];
				for (NSString *part in [text componentsSeparatedByString:@","]){
					NSString *name = [part stringByTrimmingCharactersInSet:
							[NSCharacterSet whitespaceAndNewlineCharacterSet]];
					if (name.length) [names addObject:name];
				}
				[[TGClient shared] reorderBotActiveUsernames:names forBot:botId
												  completion:^(BOOL ok, NSString *error){
					[weakSelf finish:ok error:error title:@"Bot Usernames"];
				}];
			}];
		}];
	} else if ([action isEqualToString:@"loadPreviews"]){
		[self askBotId:@"Media Previews" action:^(int64_t botId){
			[[TGClient shared] botMediaPreviewsForBot:botId
										   completion:^(NSArray *previews, NSString *error){
				if (error){
					[weakSelf finish:NO error:error title:@"Media Previews"];
					return;
				}
				NSMutableArray *lines = [NSMutableArray array];
				for (NSDictionary *preview in previews)
					[lines addObject:[NSString stringWithFormat:@"%@  file %@",
							preview[@"contentType"], preview[@"fileId"]]];
				[weakSelf showText:(lines.count ? [lines componentsJoinedByString:@"\n"]
						: @"This bot has no media previews.")
						   title:@"Media Previews"];
			}];
		}];
	} else if ([action isEqualToString:@"previewInfo"]){
		[self askBotId:@"Preview Info" action:^(int64_t botId){
			[[TGClient shared] botMediaPreviewInfoForBot:botId
												language:weakSelf.language
											  completion:^(NSDictionary *info, NSString *error){
				if (error){
					[weakSelf finish:NO error:error title:@"Preview Info"];
					return;
				}
				NSString *line = [NSString stringWithFormat:@"%lu preview(s); languages: %@",
						(unsigned long)[info[@"previews"] count],
						[info[@"languages"] componentsJoinedByString:@", "]];
				[weakSelf showText:line title:@"Preview Info"];
			}];
		}];
	} else if ([action isEqualToString:@"addPreview"]){
		[self askBotId:@"Add Preview" action:^(int64_t botId){
			[weakSelf askText:@"Preview File ID" message:@"A file TDLib already knows"
						 placeholder:@"123" text:nil action:@"Add"
				   completion:^(NSString *file){
				[[TGClient shared] addBotMediaPreviewForBot:botId
												   language:weakSelf.language
													 fileId:file.intValue
													  video:NO
												 completion:^(NSDictionary *preview,
															  NSString *error){
					[weakSelf finish:error == nil error:error title:@"Add Preview"];
				}];
			}];
		}];
	} else if ([action isEqualToString:@"editPreview"]){
		[self askBotId:@"Edit Preview" action:^(int64_t botId){
			[weakSelf askText:@"Old File ID" message:nil placeholder:@"123" text:nil
					   action:@"Next" completion:^(NSString *oldFile){
				[weakSelf askText:@"New File ID" message:nil placeholder:@"456" text:nil
						   action:@"Replace" completion:^(NSString *newFile){
					[[TGClient shared] editBotMediaPreviewForBot:botId
														language:weakSelf.language
														  fileId:oldFile.intValue
													   newFileId:newFile.intValue
														   video:NO
													  completion:^(NSDictionary *preview,
																   NSString *error){
						[weakSelf finish:error == nil error:error title:@"Edit Preview"];
					}];
				}];
			}];
		}];
	} else if ([action isEqualToString:@"deletePreviews"]){
		[self askBotId:@"Delete Previews" action:^(int64_t botId){
			[weakSelf askText:@"File IDs" message:@"Comma separated" placeholder:@"123,456" text:nil action:@"Delete" completion:^(NSString *text){
				NSMutableArray *ids = [NSMutableArray array];
				for (NSString *part in [text componentsSeparatedByString:@","]){
					NSInteger value = part.intValue;
					if (value > 0) [ids addObject:@(value)];
				}
				[[TGClient shared] deleteBotMediaPreviewsForBot:botId
													   language:weakSelf.language
														fileIds:ids
													 completion:^(BOOL ok, NSString *error){
					[weakSelf finish:ok error:error title:@"Delete Previews"];
				}];
			}];
		}];
	} else if ([action isEqualToString:@"reorderPreviews"]){
		[self askBotId:@"Reorder Previews" action:^(int64_t botId){
			[weakSelf askText:@"File IDs" message:@"Comma separated, in order" placeholder:@"456,123" text:nil action:@"Reorder" completion:^(NSString *text){
				NSMutableArray *ids = [NSMutableArray array];
				for (NSString *part in [text componentsSeparatedByString:@","]){
					NSInteger value = part.intValue;
					if (value > 0) [ids addObject:@(value)];
				}
				[[TGClient shared] reorderBotMediaPreviewsForBot:botId
														language:weakSelf.language
														 fileIds:ids
													  completion:^(BOOL ok, NSString *error){
					[weakSelf finish:ok error:error title:@"Reorder Previews"];
				}];
			}];
		}];
	} else if ([action isEqualToString:@"similarCount"]){
		[self askBotId:@"Similar Bots" action:^(int64_t botId){
			[[TGClient shared] similarBotCountForBot:botId local:YES
										  completion:^(int32_t count, NSString *error){
				[weakSelf finish:error == nil error:error title:@"Similar Bots"];
				if (!error) [weakSelf showText:[NSString stringWithFormat:
						@"About %d similar bot(s).", (int)count] title:@"Similar Bots"];
			}];
		}];
	} else if ([action isEqualToString:@"similarBots"]){
		[self askBotId:@"Similar Bots" action:^(int64_t botId){
			[[TGClient shared] similarBotsForBot:botId
									  completion:^(NSArray *bots, NSString *error){
				if (error){
					[weakSelf finish:NO error:error title:@"Similar Bots"];
					return;
				}
				NSMutableArray *lines = [NSMutableArray array];
				for (NSDictionary *bot in bots)
					[lines addObject:[NSString stringWithFormat:@"%@  #%@",
							bot[@"name"], bot[@"id"]]];
				[weakSelf showText:(lines.count ? [lines componentsJoinedByString:@"\n"]
						: @"Telegram named no similar bots.") title:@"Similar Bots"];
			}];
		}];
	} else if ([action isEqualToString:@"openSimilar"]){
		[self askBotId:@"Open Similar Bot" action:^(int64_t botId){
			[weakSelf askText:@"Opened Bot ID" message:nil placeholder:@"456" text:nil
					   action:@"Open" completion:^(NSString *text){
				[[TGClient shared] openSimilarBot:text.longLongValue fromBot:botId
									   completion:^(BOOL ok, NSString *error){
					[weakSelf finish:ok error:error title:@"Similar Bots"];
				}];
			}];
		}];
	} else if ([action isEqualToString:@"emojiStatus"]){
		[self askBotId:@"Emoji Status Permission" action:^(int64_t botId){
			[TGAlertSheet showChoices:@[@"Allow", @"Do Not Allow"]
								title:@"Let This Bot Manage My Emoji Status"
					   destructiveIndex:-1 inView:weakSelf.view
							 onChoice:^(NSInteger index){
				[[TGClient shared] setBotCanManageEmojiStatus:(index == 0) forBot:botId
												   completion:^(BOOL ok, NSString *error){
					[weakSelf finish:ok error:error title:@"Emoji Status Permission"];
				}];
			}];
		}];
	} else if ([action isEqualToString:@"recentInline"]){
		[[TGClient shared] recentInlineBotsWithCompletion:^(NSArray *bots, NSString *error){
			if (error){
				[weakSelf finish:NO error:error title:@"Inline Bots"];
				return;
			}
			NSMutableArray *lines = [NSMutableArray array];
			for (NSDictionary *bot in bots)
				[lines addObject:[NSString stringWithFormat:@"@%@  %@",
						bot[@"username"], bot[@"name"]]];
			[weakSelf showText:(lines.count ? [lines componentsJoinedByString:@"\n"]
					: @"This account has not used an inline bot yet.")
					   title:@"Inline Bots"];
		}];
	} else if ([action isEqualToString:@"attachment"]){
		[self askBotId:@"Attachment Menu Bot" action:^(int64_t botId){
			[[TGClient shared] attachmentMenuBot:botId
									  completion:^(NSDictionary *bot, NSString *error){
				if (error){
					[weakSelf finish:NO error:error title:@"Attachment Menu"];
					return;
				}
				NSString *line = [NSString stringWithFormat:
						@"%@\nAdded: %@\nRequests write access: %@\nSelf chat: %@\n"
						 @"User chats: %@\nGroup chats: %@\nChannel chats: %@",
						bot[@"name"], [bot[@"isAdded"] boolValue] ? @"yes" : @"no",
						[bot[@"requestWriteAccess"] boolValue] ? @"yes" : @"no",
						[bot[@"supportsSelfChat"] boolValue] ? @"yes" : @"no",
						[bot[@"supportsUserChats"] boolValue] ? @"yes" : @"no",
						[bot[@"supportsGroupChats"] boolValue] ? @"yes" : @"no",
						[bot[@"supportsChannelChats"] boolValue] ? @"yes" : @"no"];
				[weakSelf showText:line title:@"Attachment Menu"];
			}];
		}];
	} else if ([action isEqualToString:@"attachAdd"] || [action isEqualToString:@"attachRemove"]){
		BOOL add = [action isEqualToString:@"attachAdd"];
		[self askBotId:(add ? @"Add To Attachment Menu" : @"Remove From Attachment Menu")
			   action:^(int64_t botId){
			[TGAlertSheet showChoices:@[@"Without write access", @"With write access"]
								title:@"Attachment Menu" destructiveIndex:-1
							   inView:weakSelf.view onChoice:^(NSInteger index){
				[[TGClient shared] setBotOnAttachmentMenu:botId added:add
										 allowWriteAccess:(index == 1)
											   completion:^(BOOL ok, NSString *error){
					[weakSelf finish:ok error:error title:@"Attachment Menu"];
				}];
			}];
		}];
	} else if ([action isEqualToString:@"canSend"]){
		[self askBotId:@"Bot Messaging" action:^(int64_t botId){
			[[TGClient shared] canBotSendMessages:botId
									   completion:^(BOOL can, NSString *error){
				[weakSelf finish:error == nil error:error title:@"Bot Messaging"];
				if (!error) [weakSelf showText:(can ? @"This bot may message you."
						: @"Telegram refused; the allow row can grant it.")
										   title:@"Bot Messaging"];
			}];
		}];
	} else if ([action isEqualToString:@"allowSend"]){
		[self askBotId:@"Allow Bot" action:^(int64_t botId){
			[[TGClient shared] allowBotToSendMessages:botId
										   completion:^(BOOL ok, NSString *error){
				[weakSelf finish:ok error:error title:@"Bot Messaging"];
			}];
		}];
	} else if ([action isEqualToString:@"startBot"]){
		[self askBotId:@"Start Bot" action:^(int64_t botId){
			[weakSelf askText:@"Chat ID" message:@"Where to start it" placeholder:@"123"
				 text:nil action:@"Next" completion:^(NSString *chat){
				[weakSelf askText:@"Start Parameter" message:@"Empty for none" placeholder:@"deep-link"
					 text:nil action:@"Start" completion:^(NSString *parameter){
					[[TGClient shared] startBot:botId inChat:chat.longLongValue
									  parameter:parameter
									 completion:^(NSDictionary *message, NSString *error){
						[weakSelf finish:error == nil error:error title:@"Start Bot"];
						if (!error) [weakSelf showText:[NSString stringWithFormat:
								@"Message #%@ sent.", message[@"id"]] title:@"Start Bot"];
					}];
				}];
			}];
		}];
	} else if ([action isEqualToString:@"inlineResult"]){
		[self askText:@"Saved Reply" message:@"Shortcut name" placeholder:@"greeting"
			 text:nil action:@"Next" completion:^(NSString *shortcut){
			[weakSelf askText:@"Inline Query ID" message:nil placeholder:@"0" text:nil
					   action:@"Next" completion:^(NSString *query){
				[weakSelf askText:@"Result ID" message:nil placeholder:@"result-1" text:nil
						   action:@"Add" completion:^(NSString *result){
					[[TGClient shared] addInlineResultToQuickReply:shortcut
														 replyToId:0
														   queryId:query.longLongValue
														  resultId:result
														hideViaBot:NO
														completion:^(NSDictionary *message,
																	 NSString *error){
						[weakSelf finish:error == nil error:error title:@"Saved Reply"];
						if (!error) [weakSelf showText:[NSString stringWithFormat:
								@"Added message #%@.", message[@"id"]]
											   title:@"Saved Reply"];
					}];
				}];
			}];
		}];
	} else if ([action isEqualToString:@"browserDefault"]){
		[TGAlertSheet showChoices:@[@"In the system browser", @"In an in-app browser"]
							title:@"Open Links" destructiveIndex:-1 inView:self.view
						 onChoice:^(NSInteger index){
			[[TGClient shared] setWebBrowserSettingsOpenExternal:(index == 0)
											  displayCloseButton:NO
													 completion:^(BOOL ok, NSString *error){
				[weakSelf finish:ok error:error title:@"Open Links"];
			}];
		}];
	} else if ([action isEqualToString:@"browserAdd"]){
		[self askText:@"Browser Exception" message:@"URL" placeholder:@"https://example.com"
			 text:nil action:@"Next"
		   completion:^(NSString *url){
			[TGAlertSheet showChoices:@[@"Open externally", @"Open in-app"]
								title:@"Browser Exception" destructiveIndex:-1
							   inView:weakSelf.view onChoice:^(NSInteger index){
				[[TGClient shared] addWebBrowserException:url openExternal:(index == 0)
											   completion:^(BOOL ok, NSString *error){
					[weakSelf finish:ok error:error title:@"Browser Exception"];
				}];
			}];
		}];
	} else if ([action isEqualToString:@"browserRemove"]){
		[self askText:@"Remove Browser Exception" message:@"URL" placeholder:@"https://example.com"
			 text:nil action:@"Remove"
		   completion:^(NSString *url){
			[[TGClient shared] removeWebBrowserException:url
											  completion:^(BOOL ok, NSString *error){
				[weakSelf finish:ok error:error title:@"Browser Exception"];
			}];
		}];
	} else if ([action isEqualToString:@"browserRemoveAll"]){
		[[TGClient shared] removeAllWebBrowserExceptionsWithCompletion:
				^(BOOL ok, NSString *error){
			[weakSelf finish:ok error:error title:@"Browser Exceptions"];
		}];
	} else if ([action isEqualToString:@"grossing"]){
		[[TGClient shared] grossingWebAppBotsOffset:@"" limit:20
										 completion:^(NSArray *bots, NSString *error){
			if (error){
				[weakSelf finish:NO error:error title:@"Web App Bots"];
				return;
			}
			NSMutableArray *lines = [NSMutableArray array];
			for (NSDictionary *bot in bots)
				[lines addObject:[NSString stringWithFormat:@"%@  #%@",
						bot[@"name"], bot[@"id"]]];
			[weakSelf showText:(lines.count ? [lines componentsJoinedByString:@"\n"]
					: @"Telegram returned no Web App bots.") title:@"Web App Bots"];
		}];
	} else if ([action isEqualToString:@"searchApp"]){
		[self askBotId:@"Search Web App" action:^(int64_t botId){
			[weakSelf askText:@"Web App Short Name" message:nil placeholder:@"app"
				 text:nil action:@"Search" completion:^(NSString *name){
				[[TGClient shared] searchWebAppForBot:botId shortName:name
										   completion:^(NSDictionary *app, NSString *error){
					if (error){
						[weakSelf finish:NO error:error title:@"Web App"];
						return;
					}
					[weakSelf showText:[NSString stringWithFormat:@"%@\n%@\n%@",
							app[@"title"], app[@"shortName"], app[@"description"]]
							   title:@"Web App"];
				}];
			}];
		}];
	} else if ([action isEqualToString:@"placeholder"]){
		[self askBotId:@"Web App Placeholder" action:^(int64_t botId){
			[[TGClient shared] webAppPlaceholderForBot:botId
											completion:^(NSString *outline, NSString *error){
				[weakSelf finish:error == nil error:error title:@"Placeholder"];
				if (!error) [weakSelf showText:outline title:@"Placeholder"];
			}];
		}];
	} else if ([action isEqualToString:@"webAppUrl"]){
		[self askBotId:@"Web App URL" action:^(int64_t botId){
			[weakSelf askText:@"Web App URL" message:@"Empty for the menu"
					 placeholder:@"https://" text:nil action:@"Read"
				   completion:^(NSString *url){
				[[TGClient shared] webAppURLForBot:botId url:url mode:@"compact"
										completion:^(NSString *link, NSString *error){
					[weakSelf finish:error == nil error:error title:@"Web App URL"];
					if (link.length){
						[UIPasteboard generalPasteboard].string = link;
						[weakSelf showText:link title:@"Web App URL"];
					}
				}];
			}];
		}];
	} else if ([action isEqualToString:@"mainWebApp"]){
		[self askBotId:@"Main Web App" action:^(int64_t botId){
			[weakSelf askText:@"Chat ID" message:@"0 for none" placeholder:@"0"
				 text:nil action:@"Next" completion:^(NSString *chat){
				[weakSelf askText:@"Start Parameter" message:@"Empty for none" placeholder:@"start"
					 text:nil action:@"Read" completion:^(NSString *start){
					[[TGClient shared] mainWebAppForBot:botId chatId:chat.longLongValue
										startParameter:start mode:@"compact"
										  completion:^(NSString *link, NSString *error){
						[weakSelf finish:error == nil error:error title:@"Main Web App"];
						if (link.length){
							[UIPasteboard generalPasteboard].string = link;
							[weakSelf showText:link title:@"Main Web App"];
						}
					}];
				}];
			}];
		}];
	} else if ([action isEqualToString:@"webAppLink"]){
		[self askBotId:@"Web App Link" action:^(int64_t botId){
			[weakSelf askText:@"Short Name" message:nil placeholder:@"app" text:nil
					   action:@"Next" completion:^(NSString *shortName){
				[weakSelf askText:@"Start Parameter" message:@"Empty for none" placeholder:@"start"
					 text:nil action:@"Read" completion:^(NSString *start){
					[[TGClient shared] webAppLinkURLForBot:botId chatId:0
												shortName:shortName
										   startParameter:start allowWrite:NO
													 mode:@"compact"
											   completion:^(NSString *link, NSString *error){
						[weakSelf finish:error == nil error:error title:@"Web App Link"];
						if (link.length){
							[UIPasteboard generalPasteboard].string = link;
							[weakSelf showText:link title:@"Web App Link"];
						}
					}];
				}];
			}];
		}];
	} else if ([action isEqualToString:@"shareChat"]){
		[self askBotId:@"Share Chat With Bot" action:^(int64_t botId){
			[weakSelf askText:@"Source Chat ID" message:@"The message with the button"
					 placeholder:@"123" text:nil action:@"Next"
				   completion:^(NSString *sourceChat){
				[weakSelf askText:@"Source Message ID" message:nil placeholder:@"456"
					 text:nil action:@"Next" completion:^(NSString *sourceMessage){
					[weakSelf askText:@"Button ID" message:nil placeholder:@"0" text:nil
							   action:@"Next" completion:^(NSString *button){
						[weakSelf askText:@"Shared Chat ID" message:nil placeholder:@"789"
							 text:nil action:@"Share" completion:^(NSString *shared){
							[[TGClient shared] shareChatWithBot:botId
													 sourceChat:sourceChat.longLongValue
												  sourceMessage:sourceMessage.longLongValue
													   buttonId:button.intValue
													  sharedChat:shared.longLongValue
														checkOnly:NO
													   completion:^(BOOL ok, NSString *error){
								[weakSelf finish:ok error:error title:@"Share Chat"];
							}];
						}];
					}];
				}];
			}];
		}];
	} else if ([action isEqualToString:@"shareUsers"]){
		[self askBotId:@"Share Users With Bot" action:^(int64_t botId){
			[weakSelf askText:@"Source Chat ID" message:nil placeholder:@"123" text:nil
					   action:@"Next" completion:^(NSString *sourceChat){
				[weakSelf askText:@"Source Message ID" message:nil placeholder:@"456"
					 text:nil action:@"Next" completion:^(NSString *sourceMessage){
					[weakSelf askText:@"Button ID" message:nil placeholder:@"0" text:nil
							   action:@"Next" completion:^(NSString *button){
						[weakSelf askText:@"User IDs" message:@"Comma separated" placeholder:@"1001,1002"
							 text:nil action:@"Share"
							   completion:^(NSString *users){
							NSMutableArray *ids = [NSMutableArray array];
							for (NSString *part in [users componentsSeparatedByString:@","]){
								NSInteger value = part.intValue;
								if (value > 0) [ids addObject:@(value)];
							}
							[[TGClient shared] shareUsersWithBot:botId
													  sourceChat:sourceChat.longLongValue
												   sourceMessage:sourceMessage.longLongValue
														buttonId:button.intValue
														 userIds:ids
													   checkOnly:NO
													  completion:^(BOOL ok, NSString *error){
								[weakSelf finish:ok error:error title:@"Share Users"];
							}];
						}];
					}];
				}];
			}];
		}];
	} else if ([action isEqualToString:@"verify"] || [action isEqualToString:@"unverify"]){
		BOOL remove = [action isEqualToString:@"unverify"];
		[self askBotId:(remove ? @"Remove Verification" : @"Verify Account")
			   action:^(int64_t botId){
			[TGAlertSheet showChoices:@[@"A user", @"A chat"]
								title:@"Verification" destructiveIndex:-1
							   inView:weakSelf.view onChoice:^(NSInteger index){
				NSString *kind = index == 1 ? @"chat" : @"user";
				[weakSelf askText:@"Account ID" message:nil placeholder:@"123" text:nil
						   action:@"Next" completion:^(NSString *account){
					if (remove){
						[[TGClient shared] removeBotVerification:botId
												   verifiedKind:kind
													   verifiedId:account.longLongValue
													 completion:^(BOOL ok, NSString *error){
							[weakSelf finish:ok error:error title:@"Verification"];
						}];
						return;
					}
					[weakSelf askText:@"Reason" message:@"Empty for Telegram's wording"
								 placeholder:@"Verified organisation" text:nil
							   action:@"Verify" completion:^(NSString *reason){
						[[TGClient shared] setBotVerification:botId
												 verifiedKind:kind
													 verifiedId:account.longLongValue
													description:reason
													 completion:^(BOOL ok, NSString *error){
							[weakSelf finish:ok error:error title:@"Verification"];
						}];
					}];
				}];
			}];
		}];
	} else if ([action isEqualToString:@"createBot"]){
		[TGAlertSheet showChoices:@[@"A bot this account owns", @"Ask for a manager id"]
							title:@"Create Bot" destructiveIndex:-1 inView:self.view
						 onChoice:^(NSInteger index){
			[weakSelf askText:@"Manager Bot ID" message:@"The bot that will manage it"
						 placeholder:@"123" text:nil action:@"Next"
				   completion:^(NSString *manager){
				[weakSelf askText:@"Bot Name" message:nil placeholder:@"My Bot" text:nil
						   action:@"Next" completion:^(NSString *name){
					[weakSelf askText:@"Bot Username" message:@"Must end in bot"
								 placeholder:@"mybot" text:nil action:@"Create"
						   completion:^(NSString *username){
						[[TGClient shared] createBotNamed:name username:username
												 manager:manager.longLongValue
											  completion:^(NSDictionary *bot,
														   NSString *error){
							[weakSelf finish:error == nil error:error title:@"Create Bot"];
							if (!error) [weakSelf showText:[NSString stringWithFormat:
									@"%@  #%@", bot[@"name"], bot[@"id"]]
												   title:@"Create Bot"];
						}];
					}];
				}];
			}];
		}];
	} else if ([action isEqualToString:@"oauthURL"] || [action isEqualToString:@"oauthCode"]){
		BOOL url = [action isEqualToString:@"oauthURL"];
		[self askText:(url ? @"OAuth Link" : @"Match Code") message:nil
		  placeholder:(url ? @"https://t.me/..." : @"AB12")
				 text:(url ? self.oauthURL : self.oauthCode) action:@"Save"
		   completion:^(NSString *text){
			if (url) weakSelf.oauthURL = text; else weakSelf.oauthCode = text;
			[weakSelf rebuildSections];
		}];
	} else if ([action isEqualToString:@"oauthInfo"]){
		[[TGClient shared] oauthLinkInfo:self.oauthURL origin:@""
							  completion:^(NSDictionary *info, NSString *error){
			if (error){
				[weakSelf finish:NO error:error title:@"OAuth"];
				return;
			}
			NSString *line = [NSString stringWithFormat:@"Bot: %@ (@%@)\nMatches: %@",
					info[@"botName"], info[@"botUsername"],
					[info[@"matches"] componentsJoinedByString:@", "]];
			[weakSelf showText:line title:@"OAuth"];
		}];
	} else if ([action isEqualToString:@"oauthCheck"]){
		[[TGClient shared] checkOauthMatchCode:self.oauthCode forURL:self.oauthURL
									completion:^(BOOL ok, NSString *error){
			[weakSelf finish:ok error:error title:@"OAuth"];
		}];
	} else if ([action isEqualToString:@"oauthAccept"]){
		[TGAlertSheet showChoices:@[@"No extra access",
									@"Let the bot message me",
									@"Let it message me and read my phone number"]
							title:@"Accept OAuth" destructiveIndex:-1 inView:self.view
						 onChoice:^(NSInteger index){
			[[TGClient shared] acceptOauthRequest:weakSelf.oauthURL
										matchCode:weakSelf.oauthCode
								   allowWriteAccess:(index >= 1)
							allowPhoneNumberAccess:(index >= 2)
									   completion:^(NSString *link, NSString *error){
				[weakSelf finish:error == nil error:error title:@"OAuth"];
				if (link.length){
					[UIPasteboard generalPasteboard].string = link;
					[weakSelf showText:[NSString stringWithFormat:
							@"Open this link to finish:\n%@", link] title:@"OAuth"];
				}
			}];
		}];
	} else if ([action isEqualToString:@"oauthDecline"]){
		[[TGClient shared] declineOauthRequest:self.oauthURL
									completion:^(BOOL ok, NSString *error){
			[weakSelf finish:ok error:error title:@"OAuth"];
		}];
	} else if ([action isEqualToString:@"businessRead"]){
		[[TGClient shared] businessConnectedBotWithCompletion:^(NSDictionary *bot,
																 NSString *error){
			if (error){
				[weakSelf finish:NO error:error title:@"Business Bot"];
				return;
			}
			NSString *line = [NSString stringWithFormat:@"Bot #%@\nConnected %@\n%@\n%@",
					bot[@"botUserId"], bot[@"connectionDate"],
					bot[@"deviceModel"], bot[@"location"]];
			[weakSelf showText:line title:@"Business Bot"];
		}];
	} else if ([action isEqualToString:@"businessSet"]){
		[self askBotId:@"Connect Business Bot" action:^(int64_t botId){
			[[TGClient shared] setBusinessConnectedBot:botId
											recipients:@{@"existing" : @YES,
														 @"new" : @YES,
														 @"contacts" : @YES,
														 @"nonContacts" : @NO}
											completion:^(BOOL ok, NSString *error){
				[weakSelf finish:ok error:error title:@"Business Bot"];
			}];
		}];
	} else if ([action isEqualToString:@"businessConfirm"]){
		[self askBotId:@"Confirm Business Bot" action:^(int64_t botId){
			[[TGClient shared] confirmBusinessConnectedBot:botId
												completion:^(BOOL ok, NSString *error){
				[weakSelf finish:ok error:error title:@"Business Bot"];
			}];
		}];
	} else if ([action isEqualToString:@"businessDelete"]){
		[self askBotId:@"Delete Business Bot" action:^(int64_t botId){
			[[TGClient shared] deleteBusinessConnectedBot:botId
											   completion:^(BOOL ok, NSString *error){
				[weakSelf finish:ok error:error title:@"Business Bot"];
			}];
		}];
	} else if ([action isEqualToString:@"businessRemoveChat"] ||
			   [action isEqualToString:@"businessPause"]){
		BOOL pause = [action isEqualToString:@"businessPause"];
		[self askText:@"Chat ID" message:nil placeholder:@"123" text:nil
			   action:(pause ? @"Pause" : @"Remove") completion:^(NSString *chat){
			int64_t chatId = chat.longLongValue;
			if (pause){
				[[TGClient shared] pauseBusinessConnectedBotInChat:chatId paused:YES
														completion:^(BOOL ok, NSString *error){
					[weakSelf finish:ok error:error title:@"Business Bot"];
				}];
			} else {
				[[TGClient shared] removeBusinessConnectedBotFromChat:chatId
														   completion:^(BOOL ok, NSString *error){
					[weakSelf finish:ok error:error title:@"Business Bot"];
				}];
			}
		}];
	}
}

@end

// vim:ft=objc
