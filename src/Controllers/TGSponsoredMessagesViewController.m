//
// TGSponsoredMessagesViewController.m - one page for every advertisement
// TDLib hands a user client: channel posts, search results, video overlays
// and the owner switches that turn them off.
//
// The requests are real and the server's answer is the row's text. A channel
// account with no ads is told so rather than shown an empty table, and a
// report that Telegram wants a reason for opens its own option list.
//
#import "TGSponsoredMessagesViewController.h"
#import "TGClient.h"
#import "TGAlertSheet.h"
#import "TGTheme.h"
#import "TGStyle.h"

@interface TGSponsoredMessagesViewController ()
@property (nonatomic, assign) BOOL myAdsEnabled;
@property (nonatomic, assign) BOOL channelAdsEnabled;
@property (nonatomic, copy) NSString *searchQuery;
@property (nonatomic, strong) NSArray *answerLines;
@end

@implementation TGSponsoredMessagesViewController

- (instancetype)init {
	if ((self = [super init])){
		_myAdsEnabled = YES;
		_channelAdsEnabled = YES;
		_answerLines = @[@"Load a chat's advertisements or search for one."];
	}
	return self;
}

- (void)viewDidLoad {
	[super viewDidLoad];
	self.title = @"Sponsored Messages";
	[self rebuildSections];
}

- (void)rebuildSections {
	NSMutableArray *answers = [NSMutableArray array];
	for (NSString *line in self.answerLines)
		[answers addObject:TGBInfo(line, nil)];

	NSMutableArray *chatRows = [NSMutableArray array];
	[chatRows addObject:TGBAction(@"Chat ID", self.chatId
			? [NSString stringWithFormat:@"%lld", self.chatId] : @"Set", @"chatId")];
	[chatRows addObject:TGBAction(@"Load Sponsored Messages", nil, @"load")];

	NSMutableArray *switchRows = [NSMutableArray array];
	[switchRows addObject:TGBAction(@"My Sponsored Messages",
			self.myAdsEnabled ? @"On - tap to turn off" : @"Off - tap to turn on",
			@"toggleMine")];
	[switchRows addObject:TGBAction(@"Channel Ads Enabled",
			self.channelAdsEnabled ? @"On - tap to turn off" : @"Off - tap to turn on",
			@"toggleChannel")];
	[switchRows addObject:TGBAction(@"Set Supergroup ID", nil, @"supergroupId")];

	NSMutableArray *searchRows = [NSMutableArray array];
	[searchRows addObject:TGBAction(@"Search Query",
			self.searchQuery.length ? self.searchQuery : @"Set", @"query")];
	[searchRows addObject:TGBAction(@"Search Sponsored Chats", nil, @"search")];

	NSMutableArray *videoRows = [NSMutableArray array];
	[videoRows addObject:TGBAction(@"Video Message ID", self.messageId
			? [NSString stringWithFormat:@"%lld", self.messageId] : @"Set",
			@"videoMessageId")];
	[videoRows addObject:TGBAction(@"Load Video Advertisements", nil, @"loadVideo")];

	NSMutableArray *speechRows = [NSMutableArray array];
	[speechRows addObject:TGBAction(@"Transcribe This Voice Note", nil, @"transcribe")];
	[speechRows addObject:TGBAction(@"Transcription Was Good", nil, @"speechGood")];
	[speechRows addObject:TGBAction(@"Transcription Was Bad", nil, @"speechBad")];

	self.sections = @[
		TGBSection(@"CHANNEL ADS",
				@"Sponsored messages are the posts Telegram inserts between a "
				@"channel's own messages. A bot chat can carry them too.",
				chatRows),
		TGBSection(@"SWITCHES",
				@"The account switch only means something for Premium; Telegram "
				@"ignores it otherwise. The channel switch needs the supergroup "
				@"id and owner rights, and the server says so when it refuses.",
				switchRows),
		TGBSection(@"SEARCH ADS",
				@"Sponsored chats sit above or below search results. Every row "
				@"keeps the id Telegram uses for its view, click and report calls.",
				searchRows),
		TGBSection(@"VIDEO ADS",
				@"A video message can carry advertisements that play around it. "
				@"The chat id above is reused here.",
				videoRows),
		TGBSection(@"SPEECH",
				@"Transcription runs on Telegram's side: recognizeSpeech asks for "
				@"it and the text arrives with the message. The vote is optional.",
				speechRows),
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

- (void)showAds:(NSArray *)ads title:(NSString *)title {
	if (!ads.count){
		[self showMessage:@"Telegram has no advertisements for this place right now."
					title:title];
		return;
	}
	NSMutableArray *titles = [NSMutableArray array];
	for (NSDictionary *ad in ads){
		NSString *line = ad[@"title"] ?: ad[@"text"] ?: ad[@"sponsorInfo"] ?: @"";
		if (!line.length)
			line = [NSString stringWithFormat:@"Advertisement %@", ad[@"uniqueId"] ?: ad[@"messageId"] ?: @""];
		[titles addObject:line];
	}
	__weak typeof(self) weakSelf = self;
	[TGAlertSheet showChoices:titles title:title destructiveIndex:-1 inView:self.view
					 onChoice:^(NSInteger index){
		[weakSelf actOnAd:ads[(NSUInteger)index] title:title];
	}];
}

- (void)actOnAd:(NSDictionary *)ad title:(NSString *)title {
	__weak typeof(self) weakSelf = self;
	NSString *kind = ad[@"kind"];
	BOOL chatAd = [kind isEqualToString:@"chat"];
	BOOL videoAd = [kind isEqualToString:@"video"];
	NSString *report = chatAd ? @"Report Sponsored Message" : @"Report Advertisement";
	[TGAlertSheet showChoices:@[@"Open / Click", @"View", report]
						title:title destructiveIndex:-1 inView:self.view
					 onChoice:^(NSInteger index){
		if (index == 0){
			if (chatAd){
				[[TGClient shared] clickSponsoredMessage:[ad[@"messageId"] longLongValue]
												  inChat:weakSelf.chatId
											   mediaClick:NO
											 fromFullscreen:NO
											   completion:^(BOOL ok, NSString *error){
					[weakSelf finish:ok error:error title:title];
				}];
			} else if (videoAd){
				[[TGClient shared] clickVideoAdvertisement:[ad[@"uniqueId"] longLongValue]
											   completion:^(BOOL ok, NSString *error){
					[weakSelf finish:ok error:error title:title];
				}];
			} else {
				[[TGClient shared] openSponsoredChat:[ad[@"uniqueId"] longLongValue]
										  completion:^(BOOL ok, NSString *error){
					[weakSelf finish:ok error:error title:title];
				}];
			}
		} else if (index == 1){
			if (chatAd){
				[self showMessage:@"A channel advertisement has no separate view call; "
								  @"opening it is the click." title:title];
			} else if (videoAd){
				[[TGClient shared] viewVideoAdvertisement:[ad[@"uniqueId"] longLongValue]
											  completion:^(BOOL ok, NSString *error){
					[weakSelf finish:ok error:error title:title];
				}];
			} else {
				[[TGClient shared] viewSponsoredChat:[ad[@"uniqueId"] longLongValue]
										  completion:^(BOOL ok, NSString *error){
					[weakSelf finish:ok error:error title:title];
				}];
			}
		} else {
			[self reportAd:ad title:title];
		}
	}];
}

- (void)reportAd:(NSDictionary *)ad title:(NSString *)title {
	__weak typeof(self) weakSelf = self;
	void (^done)(NSDictionary *, NSString *) = ^(NSDictionary *result, NSString *error){
		if (error){
			[weakSelf finish:NO error:error title:title];
			return;
		}
		NSArray *options = result[@"options"];
		if ([options isKindOfClass:NSArray.class] && options.count){
			NSMutableArray *titles = [NSMutableArray array];
			for (NSDictionary *option in options)
				[titles addObject:option[@"text"] ?: @"Reason"];
			[TGAlertSheet showChoices:titles title:title destructiveIndex:-1
							   inView:weakSelf.view onChoice:^(NSInteger index){
				NSDictionary *option = options[(NSUInteger)index];
				[weakSelf sendReport:ad option:option[@"id"] title:title];
			}];
			return;
		}
		[weakSelf finish:YES error:nil title:title];
		[weakSelf showMessage:[NSString stringWithFormat:@"Telegram answered: %@",
				result[@"type"] ?: @"received"] title:title];
	};
	if ([ad[@"kind"] isEqualToString:@"chat"]){
		[[TGClient shared] reportSponsoredMessage:[ad[@"messageId"] longLongValue]
										   inChat:weakSelf.chatId option:@""
									   completion:done];
	} else if ([ad[@"kind"] isEqualToString:@"video"]){
		[[TGClient shared] reportVideoAdvertisement:[ad[@"uniqueId"] longLongValue]
											option:@""
										completion:done];
	} else {
		[[TGClient shared] reportSponsoredChat:[ad[@"uniqueId"] longLongValue]
										option:@""
									completion:done];
	}
}

- (void)sendReport:(NSDictionary *)ad option:(NSString *)optionId title:(NSString *)title {
	__weak typeof(self) weakSelf = self;
	void (^done)(NSDictionary *, NSString *) = ^(NSDictionary *result, NSString *error){
		[weakSelf finish:error == nil error:error title:title];
	};
	if ([ad[@"kind"] isEqualToString:@"chat"]){
		[[TGClient shared] reportSponsoredMessage:[ad[@"messageId"] longLongValue]
										   inChat:weakSelf.chatId option:optionId
									   completion:done];
	} else if ([ad[@"kind"] isEqualToString:@"video"]){
		[[TGClient shared] reportVideoAdvertisement:[ad[@"uniqueId"] longLongValue]
											option:optionId completion:done];
	} else {
		[[TGClient shared] reportSponsoredChat:[ad[@"uniqueId"] longLongValue]
										option:optionId completion:done];
	}
}

- (void)didChooseAction:(NSString *)action row:(NSDictionary *)row {
	__weak typeof(self) weakSelf = self;
	if ([action isEqualToString:@"chatId"]){
		[self askText:@"Chat ID" message:@"The channel or bot chat."
		  placeholder:@"-100..." text:(self.chatId
				  ? [NSString stringWithFormat:@"%lld", self.chatId] : nil)
			   action:@"Save" completion:^(NSString *text){
			weakSelf.chatId = text.longLongValue;
			[weakSelf rebuildSections];
		}];
	} else if ([action isEqualToString:@"load"]){
		[[TGClient shared] sponsoredMessagesForChat:self.chatId
										 completion:^(NSArray *messages, NSString *error){
			if (error){
				[weakSelf finish:NO error:error title:@"Sponsored Messages"];
				return;
			}
			weakSelf.answerLines = messages.count
					? @[[NSString stringWithFormat:@"%lu advertisement(s) for this chat.",
						 (unsigned long)messages.count]]
					: @[@"Telegram has no advertisements for this chat."];
			[weakSelf rebuildSections];
			[weakSelf showAds:messages title:@"Sponsored Messages"];
		}];
	} else if ([action isEqualToString:@"toggleMine"]){
		weakSelf.myAdsEnabled = !weakSelf.myAdsEnabled;
		[[TGClient shared] setSponsoredMessagesEnabled:weakSelf.myAdsEnabled
											completion:^(BOOL ok, NSString *error){
			[weakSelf finish:ok error:error title:@"Sponsored Messages"];
		}];
	} else if ([action isEqualToString:@"toggleChannel"]){
		[weakSelf askText:@"Channel Ads" message:@"Supergroup id (not chat id)"
			  placeholder:@"123" text:nil action:@"Next" completion:^(NSString *text){
			int64_t supergroupId = text.longLongValue;
			weakSelf.channelAdsEnabled = !weakSelf.channelAdsEnabled;
			[[TGClient shared] setChannelSponsoredMessagesEnabled:weakSelf.channelAdsEnabled
													 supergroupId:supergroupId
													  completion:^(BOOL ok, NSString *error){
				[weakSelf finish:ok error:error title:@"Channel Ads"];
			}];
		}];
	} else if ([action isEqualToString:@"supergroupId"]){
		[self askText:@"Supergroup ID" message:@"The number getSupergroup returns."
		  placeholder:@"123" text:nil action:@"Save" completion:^(NSString *text){
			[weakSelf finish:YES error:nil title:@"Supergroup ID"];
		}];
	} else if ([action isEqualToString:@"query"]){
		[self askText:@"Search Query" message:nil placeholder:@"news" text:self.searchQuery
			   action:@"Save" completion:^(NSString *text){
			weakSelf.searchQuery = text;
			[weakSelf rebuildSections];
		}];
	} else if ([action isEqualToString:@"search"]){
		[[TGClient shared] searchSponsoredChats:self.searchQuery
									 completion:^(NSArray *chats, NSString *error){
			if (error){
				[weakSelf finish:NO error:error title:@"Search Ads"];
				return;
			}
			weakSelf.answerLines = @[[NSString stringWithFormat:@"%lu sponsored chat(s).",
					(unsigned long)chats.count]];
			[weakSelf rebuildSections];
			[weakSelf showAds:chats title:@"Search Ads"];
		}];
	} else if ([action isEqualToString:@"videoMessageId"]){
		[self askText:@"Video Message ID" message:nil placeholder:@"123"
				 text:(self.messageId
				  ? [NSString stringWithFormat:@"%lld", self.messageId] : nil)
			   action:@"Save" completion:^(NSString *text){
			weakSelf.messageId = text.longLongValue;
			[weakSelf rebuildSections];
		}];
	} else if ([action isEqualToString:@"loadVideo"]){
		[[TGClient shared] videoAdvertisementsForChat:self.chatId
											  message:self.messageId
										   completion:^(NSArray *ads, NSString *error){
			if (error){
				[weakSelf finish:NO error:error title:@"Video Ads"];
				return;
			}
			weakSelf.answerLines = @[[NSString stringWithFormat:@"%lu video advertisement(s).",
					(unsigned long)ads.count]];
			[weakSelf rebuildSections];
			[weakSelf showAds:ads title:@"Video Ads"];
		}];
	} else if ([action isEqualToString:@"transcribe"]){
		[[TGClient shared] recognizeSpeechInChat:self.chatId message:self.messageId
									  completion:^(BOOL ok, NSString *error){
			[weakSelf finish:ok error:error title:@"Transcribe"];
			if (ok)
				[weakSelf showMessage:@"Telegram is transcribing. The text arrives "
									  @"with the message and the bubble redraws."
								 title:@"Transcribe"];
		}];
	} else if ([action isEqualToString:@"speechGood"] || [action isEqualToString:@"speechBad"]){
		BOOL good = [action isEqualToString:@"speechGood"];
		[[TGClient shared] rateSpeechInChat:self.chatId message:self.messageId
									 isGood:good completion:^(BOOL ok, NSString *error){
			[weakSelf finish:ok error:error title:@"Transcription Vote"];
		}];
	}
}

@end

// vim:ft=objc
