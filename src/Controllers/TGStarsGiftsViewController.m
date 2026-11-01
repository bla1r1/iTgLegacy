//
// TGStarsGiftsViewController.m - what a user account can read about Premium,
// Stars and gifts without a payment provider.
//
// The store purchase, the card form, the TON wallet and the giveaway launch
// are not here: they need a stack this build does not carry, and pretending
// to charge a card would be worse than refusing. These rows only ask, and
// every answer is Telegram's.
//
#import "TGStarsGiftsViewController.h"
#import "TGClient.h"
#import "TGAlertSheet.h"
#import "TGStyle.h"

@interface TGStarsGiftsViewController ()
@property (nonatomic, copy) NSString *ownerKind;
@property (nonatomic, assign) int64_t ownerId;
@property (nonatomic, assign) int64_t giftId;
@property (nonatomic, strong) NSArray *answerLines;
@end

@implementation TGStarsGiftsViewController

- (instancetype)init {
	if ((self = [super init])){
		_ownerKind = @"user";
		_answerLines = @[@"Nothing read yet."];
	}
	return self;
}

- (void)viewDidLoad {
	[super viewDidLoad];
	self.title = @"Premium, Stars and Gifts";
	[self rebuildSections];
}

- (void)rebuildSections {
	NSMutableArray *premium = [NSMutableArray array];
	[premium addObject:TGBAction(@"Load Premium Features", nil, @"features")];
	[premium addObject:TGBAction(@"View A Premium Feature", nil, @"viewFeature")];
	[premium addObject:TGBAction(@"Load A Premium Limit", nil, @"limit")];
	[premium addObject:TGBAction(@"Premium Stickers", nil, @"premiumStickers")];
	[premium addObject:TGBAction(@"Premium Sticker Examples", nil, @"premiumExamples")];
	[premium addObject:TGBAction(@"Premium Info Sticker", nil, @"premiumInfo")];
	[premium addObject:TGBAction(@"Check Gift Code", nil, @"checkCode")];
	[premium addObject:TGBAction(@"Apply Gift Code", nil, @"applyCode")];

	NSMutableArray *stars = [NSMutableArray array];
	[stars addObject:TGBAction(@"Owner",
			[NSString stringWithFormat:@"%@ %lld", self.ownerKind, self.ownerId], @"owner")];
	[stars addObject:TGBAction(@"Star Transactions", nil, @"transactions")];
	[stars addObject:TGBAction(@"Star Subscriptions", nil, @"subscriptions")];
	[stars addObject:TGBAction(@"Cancel A Subscription", nil, @"cancelSubscription")];
	[stars addObject:TGBAction(@"Reuse A Subscription", nil, @"reuseSubscription")];

	NSMutableArray *boosts = [NSMutableArray array];
	[boosts addObject:TGBAction(@"Available Boost Slots", nil, @"boostSlots")];
	[boosts addObject:TGBAction(@"Boost Status For Owner", nil, @"boostStatus")];
	[boosts addObject:TGBAction(@"Boost Features For Channels", nil, @"boostFeatures")];
	[boosts addObject:TGBAction(@"Boost Level Features", nil, @"boostLevelFeatures")];
	[boosts addObject:TGBAction(@"Boost Link", nil, @"boostLink")];
	[boosts addObject:TGBAction(@"Read A Boost Link", nil, @"boostLinkInfo")];
	[boosts addObject:TGBAction(@"Boosts On A Chat", nil, @"boostList")];
	[boosts addObject:TGBAction(@"Boost The Owner Chat", nil, @"boostSend")];

	NSMutableArray *revenue = [NSMutableArray array];
	[revenue addObject:TGBAction(@"Chat Revenue Statistics", nil, @"chatRevenue")];
	[revenue addObject:TGBAction(@"Chat Revenue Transactions", nil, @"chatRevenueList")];
	[revenue addObject:TGBAction(@"Star Revenue Statistics", nil, @"starRevenue")];
	[revenue addObject:TGBAction(@"Gram Revenue Statistics", nil, @"gramRevenue")];
	[revenue addObject:TGBAction(@"Paid Message Revenue", nil, @"paidRevenue")];
	[revenue addObject:TGBAction(@"Direct Messages Topic Revenue", nil, @"topicRevenue")];

	NSMutableArray *paid = [NSMutableArray array];
	[paid addObject:TGBAction(@"Allow Unpaid Messages From A User", nil, @"allowUnpaid")];
	[paid addObject:TGBAction(@"Apply An Unpaid Token", nil, @"unpaidToken")];
	[paid addObject:TGBAction(@"Paid Reaction Senders", nil, @"reactionSenders")];
	[paid addObject:TGBAction(@"Chat Paid Message Price", nil, @"chatPaidPrice")];
	[paid addObject:TGBAction(@"Call Paid Message Price", nil, @"callPaidPrice")];
	[paid addObject:TGBAction(@"Topic Unpaid Messages", nil, @"topicUnpaid")];
	[paid addObject:TGBAction(@"Payment Receipt", nil, @"receipt")];
	[paid addObject:TGBAction(@"Star Ads Account URL", nil, @"adAccount")];
	[paid addObject:TGBAction(@"Unrestrict Boost Count", nil, @"unrestrict")];

	NSMutableArray *discovery = [NSMutableArray array];
	[discovery addObject:TGBAction(@"Giveaway Info", nil, @"giveaway")];
	[discovery addObject:TGBAction(@"Collectible Info", nil, @"collectible")];
	[discovery addObject:TGBAction(@"Premium Subscribe Button", nil, @"subscribe")];

	NSMutableArray *gifts = [NSMutableArray array];
	[gifts addObject:TGBAction(@"Gift ID", self.giftId
			? [NSString stringWithFormat:@"%lld", self.giftId] : @"Set", @"giftId")];
	[gifts addObject:TGBAction(@"Available Gifts", nil, @"available")];
	[gifts addObject:TGBAction(@"Can This Gift Be Sent?", nil, @"canSend")];
	[gifts addObject:TGBAction(@"Read A Received Gift", nil, @"received")];
	[gifts addObject:TGBAction(@"Read An Upgraded Gift", nil, @"upgraded")];
	[gifts addObject:TGBAction(@"Upgraded Gift Value", nil, @"value")];
	[gifts addObject:TGBAction(@"Upgraded Gift Variants", nil, @"variants")];
	[gifts addObject:TGBAction(@"Upgrade Preview", nil, @"upgradePreview")];
	[gifts addObject:TGBAction(@"Gift Collections", nil, @"collections")];
	[gifts addObject:TGBAction(@"Gifts For Crafting", nil, @"crafting")];
	[gifts addObject:TGBAction(@"Gifts For Resale", nil, @"resale")];
	[gifts addObject:TGBAction(@"Gift Emoji Statuses", nil, @"emojiStatuses")];
	[gifts addObject:TGBAction(@"Gift Chat Themes", nil, @"themes")];
	[gifts addObject:TGBAction(@"Gift Auction State", nil, @"auctionState")];
	[gifts addObject:TGBAction(@"Acquired Auction Gifts", nil, @"auctionGifts")];
	[gifts addObject:TGBAction(@"Open Gift Auction", nil, @"auctionOpen")];
	[gifts addObject:TGBAction(@"Close Gift Auction", nil, @"auctionClose")];
	[gifts addObject:TGBAction(@"Promotional Animation", nil, @"promo")];

	NSMutableArray *answers = [NSMutableArray array];
	for (NSString *line in self.answerLines)
		[answers addObject:TGBInfo(line, nil)];

	self.sections = @[
		TGBSection(@"PREMIUM", @"Feature and limit records, the sticker set "
				@"Telegram uses on the Premium page, and gift-code redemption. "
				@"A purchase itself needs the App Store flow this build has not.",
				premium),
		TGBSection(@"STARS", @"The Star wallet's transactions and subscriptions. "
				@"Cancelling or reusing one is a normal user action; buying Stars "
				@"is not offered here.", stars),
		TGBSection(@"BOOSTS", @"A Premium account's boost allowance and the "
				@"records around one chat. Spending a slot is not a payment: the "
				@"slot is already owned.", boosts),
		TGBSection(@"REVENUE", @"What an owned channel or this account earned. "
				@"Withdrawing it needs a wallet this build does not carry, so the "
				@"rows stop at the figure.", revenue),
		TGBSection(@"PAID MESSAGES", @"The free half of paid messages: the "
				@"privacy rule that lets one person write without paying, the "
				@"admin price settings, and a receipt read.", paid),
		TGBSection(@"DISCOVERY", @"Giveaways, collectible usernames and the "
				@"Premium subscribe signal.", discovery),
		TGBSection(@"GIFTS", @"The gift catalogue and the records behind one gift. "
				@"Sending, upgrading, transferring and withdrawing need a funded "
				@"Stars or TON balance and are absent on purpose.", gifts),
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

- (void)askGift:(NSString *)title action:(void (^)(int64_t giftId))action {
	__weak typeof(self) weakSelf = self;
	[self askText:title message:@"Regular gift id" placeholder:@"123"
			 text:(self.giftId ? [NSString stringWithFormat:@"%lld", self.giftId] : nil)
		   action:@"Next" completion:^(NSString *text){
		int64_t giftId = text.longLongValue;
		weakSelf.giftId = giftId;
		[weakSelf rebuildSections];
		action(giftId);
	}];
}

- (void)didChooseAction:(NSString *)action row:(NSDictionary *)row {
	__weak typeof(self) weakSelf = self;
	if ([action isEqualToString:@"features"]){
		[[TGClient shared] premiumFeaturesFromSource:@""
										  completion:^(NSDictionary *features, NSString *error){
			if (error){
				[weakSelf finish:NO error:error title:@"Premium"];
				return;
			}
			NSMutableArray *lines = [NSMutableArray array];
			for (NSString *feature in features[@"features"])
				[lines addObject:feature];
			for (NSDictionary *limit in features[@"limits"])
				[lines addObject:[NSString stringWithFormat:@"%@  %@ / %@",
						limit[@"type"], limit[@"defaultValue"], limit[@"premiumValue"]]];
			[weakSelf showText:(lines.count ? [lines componentsJoinedByString:@"\n"]
					: @"Telegram returned no Premium features.")
					   title:@"Premium"];
		}];
	} else if ([action isEqualToString:@"viewFeature"]){
		[self askText:@"Premium Feature" message:@"Example: disabledAds"
				 placeholder:@"disabledAds" text:nil action:@"Open"
		   completion:^(NSString *text){
			[[TGClient shared] viewPremiumFeature:text
									   completion:^(BOOL ok, NSString *error){
				[weakSelf finish:ok error:error title:@"Premium Feature"];
			}];
		}];
	} else if ([action isEqualToString:@"limit"]){
		[self askText:@"Premium Limit" message:@"Example: pinnedChatCount"
				 placeholder:@"pinnedChatCount" text:nil action:@"Read"
		   completion:^(NSString *text){
			[[TGClient shared] premiumLimitOfType:text
									   completion:^(NSDictionary *limit, NSString *error){
				if (error){
					[weakSelf finish:NO error:error title:@"Premium Limit"];
					return;
				}
				[weakSelf showText:[NSString stringWithFormat:@"%@\nFree: %@\nPremium: %@",
						limit[@"type"], limit[@"defaultValue"], limit[@"premiumValue"]]
							   title:@"Premium Limit"];
			}];
		}];
	} else if ([action isEqualToString:@"premiumStickers"]){
		[[TGClient shared] premiumStickersWithLimit:50
										 completion:^(NSArray *stickers, NSString *error){
			if (error){
				[weakSelf finish:NO error:error title:@"Premium Stickers"];
				return;
			}
			NSMutableArray *lines = [NSMutableArray array];
			for (NSDictionary *sticker in stickers)
				[lines addObject:[NSString stringWithFormat:@"%@  file %@",
						sticker[@"emoji"], sticker[@"fileId"]]];
			[weakSelf showText:(lines.count ? [lines componentsJoinedByString:@"\n"]
					: @"Telegram returned no Premium stickers.")
					   title:@"Premium Stickers"];
		}];
	} else if ([action isEqualToString:@"premiumExamples"]){
		[[TGClient shared] premiumStickerExamplesWithCompletion:^(NSArray *stickers,
																  NSString *error){
			[weakSelf finish:error == nil error:error title:@"Premium Examples"];
			if (!error)
				[weakSelf showText:[NSString stringWithFormat:@"%lu example(s).",
						(unsigned long)stickers.count] title:@"Premium Examples"];
		}];
	} else if ([action isEqualToString:@"premiumInfo"]){
		[self askText:@"Premium Months" message:nil placeholder:@"12" text:@"12"
			   action:@"Read" completion:^(NSString *text){
			[[TGClient shared] premiumInfoStickerForMonths:text.intValue
												completion:^(NSDictionary *sticker,
															 NSString *error){
				[weakSelf finish:error == nil error:error title:@"Premium Sticker"];
				if (!error) [weakSelf showText:[NSString stringWithFormat:
						@"Sticker %@ in set %@", sticker[@"id"], sticker[@"setId"]]
									   title:@"Premium Sticker"];
			}];
		}];
	} else if ([action isEqualToString:@"checkCode"]){
		[self askText:@"Premium Gift Code" message:nil placeholder:@"ABCD-1234"
				 text:nil action:@"Check" completion:^(NSString *text){
			[[TGClient shared] checkPremiumGiftCode:text
										 completion:^(NSDictionary *info, NSString *error){
				if (error){
					[weakSelf finish:NO error:error title:@"Gift Code"];
					return;
				}
				[weakSelf showText:[NSString stringWithFormat:
						@"%@ month(s), %@ day(s)\nFrom giveaway: %@\nUsed by: %@",
						info[@"monthCount"], info[@"dayCount"],
						[info[@"isFromGiveaway"] boolValue] ? @"yes" : @"no",
						info[@"userId"]] title:@"Gift Code"];
			}];
		}];
	} else if ([action isEqualToString:@"applyCode"]){
		[self askText:@"Apply Premium Gift Code" message:nil placeholder:@"ABCD-1234"
				 text:nil action:@"Apply" completion:^(NSString *text){
			[[TGClient shared] applyPremiumGiftCode:text
										 completion:^(BOOL ok, NSString *error){
				[weakSelf finish:ok error:error title:@"Gift Code"];
			}];
		}];
	} else if ([action isEqualToString:@"owner"]){
		[TGAlertSheet showChoices:@[@"My account", @"A chat"]
							title:@"Star Owner" destructiveIndex:-1 inView:self.view
						 onChoice:^(NSInteger index){
			NSString *kind = index == 0 ? @"user" : @"chat";
			[weakSelf askText:@"Owner ID" message:nil placeholder:@"123" text:nil
					   action:@"Save" completion:^(NSString *text){
				weakSelf.ownerKind = kind;
				weakSelf.ownerId = text.longLongValue;
				[weakSelf rebuildSections];
			}];
		}];
	} else if ([action isEqualToString:@"transactions"]){
		[TGAlertSheet showChoices:@[@"Incoming", @"Outgoing", @"Both"]
							title:@"Star Transactions" destructiveIndex:-1
						   inView:self.view onChoice:^(NSInteger index){
			NSString *direction = index == 0 ? @"incoming"
					: index == 1 ? @"outgoing" : @"";
			int64_t ownerId = weakSelf.ownerId;
			if (!ownerId && [weakSelf.ownerKind isEqualToString:@"user"])
				ownerId = [[TGClient shared].me[@"id"] longLongValue];
			[[TGClient shared] starTransactionsForOwner:weakSelf.ownerKind
												ownerId:ownerId
											  direction:direction
												 offset:@""
												  limit:20
											 completion:^(NSDictionary *page, NSString *error){
				if (error){
					[weakSelf finish:NO error:error title:@"Star Transactions"];
					return;
				}
				NSMutableArray *lines = [NSMutableArray array];
				for (NSDictionary *transaction in page[@"transactions"])
					[lines addObject:[NSString stringWithFormat:@"%@  %@  %@ stars",
							transaction[@"date"], transaction[@"type"],
							transaction[@"starCount"]]];
				[weakSelf showText:(lines.count ? [lines componentsJoinedByString:@"\n"]
						: @"No Star transactions.") title:@"Star Transactions"];
			}];
		}];
	} else if ([action isEqualToString:@"subscriptions"]){
		[[TGClient shared] starSubscriptionsOnlyExpiring:NO offset:@""
											  completion:^(NSDictionary *page,
														   NSString *error){
			if (error){
				[weakSelf finish:NO error:error title:@"Star Subscriptions"];
				return;
			}
			NSMutableArray *lines = [NSMutableArray array];
			for (NSDictionary *subscription in page[@"subscriptions"])
				[lines addObject:[NSString stringWithFormat:@"%@  chat %@  %@ stars  %@",
						subscription[@"id"], subscription[@"chatId"],
						subscription[@"starCount"],
						[subscription[@"isExpiring"] boolValue] ? @"expiring" : @"active"]];
			[weakSelf showText:(lines.count ? [lines componentsJoinedByString:@"\n"]
					: @"No Star subscriptions.") title:@"Star Subscriptions"];
		}];
	} else if ([action isEqualToString:@"cancelSubscription"] ||
			   [action isEqualToString:@"reuseSubscription"]){
		BOOL reuse = [action isEqualToString:@"reuseSubscription"];
		[self askText:(reuse ? @"Reuse Subscription" : @"Cancel Subscription")
				 message:@"Subscription id" placeholder:@"sub-1" text:nil
				 action:@"Send" completion:^(NSString *text){
			if (reuse){
				[[TGClient shared] reuseStarSubscription:text
											  completion:^(BOOL ok, NSString *error){
					[weakSelf finish:ok error:error title:@"Star Subscription"];
				}];
			} else {
				[[TGClient shared] setStarSubscription:text canceled:YES
											completion:^(BOOL ok, NSString *error){
					[weakSelf finish:ok error:error title:@"Star Subscription"];
				}];
			}
		}];
	} else if ([action isEqualToString:@"boostSlots"]){
		[[TGClient shared] availableChatBoostSlotsWithCompletion:^(NSArray *slots, NSString *error){
			if (error){
				[weakSelf finish:NO error:error title:@"Boost Slots"];
				return;
			}
			NSMutableArray *lines = [NSMutableArray array];
			for (NSDictionary *slot in slots)
				[lines addObject:[NSString stringWithFormat:@"Slot %@  chat %@  until %@",
						slot[@"slotId"], slot[@"currentlyBoostedChatId"],
						slot[@"cooldownUntilDate"]]];
			[weakSelf showText:(lines.count ? [lines componentsJoinedByString:@"\n"]
					: @"No boost slots are available.") title:@"Boost Slots"];
		}];
	} else if ([action isEqualToString:@"boostStatus"]){
		[self askText:@"Boost Status" message:@"Chat ID" placeholder:@"123" text:nil
			   action:@"Read" completion:^(NSString *chat){
			[[TGClient shared] chatBoostStatusForChat:chat.longLongValue
										   completion:^(NSDictionary *status, NSString *error){
				if (error){
					[weakSelf finish:NO error:error title:@"Boost Status"];
					return;
				}
				[weakSelf showText:[NSString stringWithFormat:
						@"Level %@\nBoosts: %@ (this level %@, next %@)\n%@",
						status[@"level"], status[@"boostCount"],
						status[@"currentLevelBoostCount"], status[@"nextLevelBoostCount"],
						status[@"boostUrl"]] title:@"Boost Status"];
			}];
		}];
	} else if ([action isEqualToString:@"boostFeatures"]){
		[[TGClient shared] chatBoostFeaturesForChannel:YES
											completion:^(NSDictionary *features, NSString *error){
			if (error){
				[weakSelf finish:NO error:error title:@"Boost Features"];
				return;
			}
			[weakSelf showText:[NSString stringWithFormat:
					@"%@ levels\nEmoji status from %@\nSpeech from %@\nNo ads from %@",
					features[@"levels"], features[@"minEmojiStatusBoostLevel"],
					features[@"minSpeechRecognitionBoostLevel"],
					features[@"minSponsoredMessageDisableBoostLevel"]]
						   title:@"Boost Features"];
		}];
	} else if ([action isEqualToString:@"boostLevelFeatures"]){
		[self askText:@"Boost Level" message:@"0 to 100" placeholder:@"1" text:@"1"
			   action:@"Read" completion:^(NSString *text){
			[[TGClient shared] chatBoostLevelFeaturesForChannel:YES level:text.intValue
													 completion:^(NSDictionary *features,
																  NSString *error){
				if (error){
					[weakSelf finish:NO error:error title:@"Boost Level"];
					return;
				}
				[weakSelf showText:[NSString stringWithFormat:
						@"Level %@\nStory per day: %@\nSpeech: %@\nNo ads: %@",
						features[@"level"], features[@"storyPerDay"],
						[features[@"canRecognizeSpeech"] boolValue] ? @"yes" : @"no",
						[features[@"canDisableSponsoredMessages"] boolValue] ? @"yes" : @"no"]
							   title:@"Boost Level"];
			}];
		}];
	} else if ([action isEqualToString:@"boostLink"]){
		[self askText:@"Boost Link" message:@"Chat ID" placeholder:@"123" text:nil
			   action:@"Read" completion:^(NSString *chat){
			[[TGClient shared] chatBoostLinkForChat:chat.longLongValue
										 completion:^(NSString *link, NSString *error){
				[weakSelf finish:error == nil error:error title:@"Boost Link"];
				if (link.length){
					[UIPasteboard generalPasteboard].string = link;
					[weakSelf showText:link title:@"Boost Link"];
				}
			}];
		}];
	} else if ([action isEqualToString:@"boostLinkInfo"]){
		[self askText:@"Boost Link Info" message:@"https://t.me/boost/..." placeholder:@"https://t.me/boost/x"
			 text:nil action:@"Read"
		   completion:^(NSString *text){
			[[TGClient shared] chatBoostLinkInfo:text
									  completion:^(NSDictionary *info, NSString *error){
				if (error){
					[weakSelf finish:NO error:error title:@"Boost Link"];
					return;
				}
				[weakSelf showText:[NSString stringWithFormat:@"Chat %@\nPublic: %@",
						info[@"chatId"], [info[@"isPublic"] boolValue] ? @"yes" : @"no"]
							   title:@"Boost Link"];
			}];
		}];
	} else if ([action isEqualToString:@"boostList"]){
		[self askText:@"Chat Boosts" message:@"Chat ID" placeholder:@"123" text:nil
			   action:@"Read" completion:^(NSString *chat){
			[[TGClient shared] chatBoostsForChat:chat.longLongValue offset:@"" limit:20
									  completion:^(NSDictionary *page, NSString *error){
				if (error){
					[weakSelf finish:NO error:error title:@"Chat Boosts"];
					return;
				}
				NSMutableArray *lines = [NSMutableArray array];
				for (NSDictionary *boost in page[@"boosts"])
					[lines addObject:[NSString stringWithFormat:@"%@  %@x  %@",
							boost[@"id"], boost[@"count"], boost[@"source"]]];
				[weakSelf showText:(lines.count ? [lines componentsJoinedByString:@"\n"]
						: @"This chat has no boosts.") title:@"Chat Boosts"];
			}];
		}];
	} else if ([action isEqualToString:@"boostSend"]){
		[self askText:@"Boost A Chat" message:@"Chat ID" placeholder:@"123" text:nil
			   action:@"Next" completion:^(NSString *chat){
			[weakSelf askText:@"Boost A Chat" message:@"Slot ids, comma separated"
						 placeholder:@"0" text:nil action:@"Boost"
				   completion:^(NSString *slots){
				NSMutableArray *ids = [NSMutableArray array];
				for (NSString *part in [slots componentsSeparatedByString:@","]){
					NSInteger value = part.intValue;
					if (value >= 0) [ids addObject:@(value)];
				}
				[[TGClient shared] boostChat:chat.longLongValue slotIds:ids
								   completion:^(NSArray *remaining, NSString *error){
					[weakSelf finish:error == nil error:error title:@"Boost"];
					if (!error) [weakSelf showText:[NSString stringWithFormat:
							@"%lu slot(s) remain.", (unsigned long)remaining.count]
											 title:@"Boost"];
				}];
			}];
		}];
	} else if ([action isEqualToString:@"chatRevenue"]){
		[self askText:@"Chat Revenue" message:@"Chat ID" placeholder:@"123" text:nil
			   action:@"Read" completion:^(NSString *chat){
			[[TGClient shared] chatRevenueStatisticsForChat:chat.longLongValue dark:NO
												 completion:^(NSDictionary *statistics,
															  NSString *error){
				if (error){
					[weakSelf finish:NO error:error title:@"Chat Revenue"];
					return;
				}
				[weakSelf showText:[NSString stringWithFormat:
						@"Total %@\nBalance %@\nAvailable %@\nWithdrawal: %@\nGraph: %@",
						statistics[@"totalAmount"], statistics[@"balanceAmount"],
						statistics[@"availableAmount"],
						[statistics[@"withdrawalEnabled"] boolValue] ? @"yes" : @"no",
						statistics[@"graph"]] title:@"Chat Revenue"];
			}];
		}];
	} else if ([action isEqualToString:@"chatRevenueList"]){
		[self askText:@"Revenue Transactions" message:@"Chat ID" placeholder:@"123"
			 text:nil action:@"Read" completion:^(NSString *chat){
			[[TGClient shared] chatRevenueTransactionsForChat:chat.longLongValue
														 offset:@"" limit:20
													 completion:^(NSDictionary *page,
																  NSString *error){
				if (error){
					[weakSelf finish:NO error:error title:@"Revenue Transactions"];
					return;
				}
				NSMutableArray *lines = [NSMutableArray array];
				for (NSDictionary *transaction in page[@"transactions"])
					[lines addObject:[NSString stringWithFormat:@"%@ %@",
							transaction[@"amount"], transaction[@"currency"]]];
				[weakSelf showText:(lines.count ? [lines componentsJoinedByString:@"\n"]
						: @"No revenue transactions.") title:@"Revenue Transactions"];
			}];
		}];
	} else if ([action isEqualToString:@"starRevenue"]){
		int64_t ownerId = self.ownerId;
		if (!ownerId) ownerId = [[TGClient shared].me[@"id"] longLongValue];
		[[TGClient shared] starRevenueStatisticsForOwner:self.ownerKind ownerId:ownerId
													dark:NO
											  completion:^(NSDictionary *statistics,
														   NSString *error){
			if (error){
				[weakSelf finish:NO error:error title:@"Star Revenue"];
				return;
			}
			[weakSelf showText:[NSString stringWithFormat:
					@"Total %@\nAvailable %@\nNext withdrawal in %@ s\nGraph: %@",
					statistics[@"total"], statistics[@"available"],
					statistics[@"nextWithdrawalIn"], statistics[@"graph"]]
						   title:@"Star Revenue"];
		}];
	} else if ([action isEqualToString:@"gramRevenue"]){
		[[TGClient shared] gramRevenueStatisticsWithDark:NO
											  completion:^(NSDictionary *statistics,
														   NSString *error){
			if (error){
				[weakSelf finish:NO error:error title:@"Gram Revenue"];
				return;
			}
			[weakSelf showText:[NSString stringWithFormat:
					@"Total %@\nBalance %@\nAvailable %@\nGraph: %@",
					statistics[@"total"], statistics[@"balance"],
					statistics[@"available"], statistics[@"graph"]]
						   title:@"Gram Revenue"];
		}];
	} else if ([action isEqualToString:@"paidRevenue"]){
		[self askText:@"Paid Message Revenue" message:@"User ID" placeholder:@"123"
			 text:nil action:@"Read" completion:^(NSString *text){
			[[TGClient shared] paidMessageRevenueForUser:text.longLongValue
											  completion:^(int64_t stars, NSString *error){
				[weakSelf finish:error == nil error:error title:@"Paid Revenue"];
				if (!error) [weakSelf showText:[NSString stringWithFormat:
						@"%lld Star(s).", (long long)stars] title:@"Paid Revenue"];
			}];
		}];
	} else if ([action isEqualToString:@"topicRevenue"]){
		[self askText:@"Topic Revenue" message:@"Chat ID" placeholder:@"123" text:nil
			   action:@"Next" completion:^(NSString *chat){
			[weakSelf askText:@"Topic Revenue" message:@"Topic ID" placeholder:@"1"
				 text:nil action:@"Read" completion:^(NSString *topic){
				[[TGClient shared] directMessagesChatTopicRevenueForChat:chat.longLongValue
																   topic:topic.longLongValue
															  completion:^(int64_t stars,
																		   NSString *error){
					[weakSelf finish:error == nil error:error title:@"Topic Revenue"];
					if (!error) [weakSelf showText:[NSString stringWithFormat:
							@"%lld Star(s).", (long long)stars] title:@"Topic Revenue"];
				}];
			}];
		}];
	} else if ([action isEqualToString:@"allowUnpaid"]){
		[self askText:@"Allow Unpaid Messages" message:@"User ID" placeholder:@"123"
				 text:nil action:@"Next" completion:^(NSString *user){
			[TGAlertSheet showChoices:@[@"Keep their payments", @"Refund their payments"]
								title:@"Allow Unpaid Messages" destructiveIndex:-1
							   inView:weakSelf.view onChoice:^(NSInteger index){
				[[TGClient shared] allowUnpaidMessagesFromUser:user.longLongValue
													   refund:(index == 1)
												   completion:^(BOOL ok, NSString *error){
					[weakSelf finish:ok error:error title:@"Unpaid Messages"];
				}];
			}];
		}];
	} else if ([action isEqualToString:@"unpaidToken"]){
		[self askText:@"Apply Unpaid Token" message:@"User ID" placeholder:@"123"
				 text:nil action:@"Next" completion:^(NSString *user){
			[weakSelf askText:@"Apply Unpaid Token" message:@"From the link"
					 placeholder:@"token" text:nil action:@"Apply"
				   completion:^(NSString *token){
				[[TGClient shared] applyUnpaidMessagesToken:token
												   forUser:user.longLongValue
												completion:^(BOOL ok, NSString *error){
					[weakSelf finish:ok error:error title:@"Unpaid Token"];
				}];
			}];
		}];
	} else if ([action isEqualToString:@"reactionSenders"]){
		[self askText:@"Paid Reaction Senders" message:@"Chat ID" placeholder:@"123"
				 text:nil action:@"Read" completion:^(NSString *chat){
			[[TGClient shared] paidReactionSendersForChat:chat.longLongValue
												completion:^(NSArray *senders, NSString *error){
				if (error){
					[weakSelf finish:NO error:error title:@"Paid Reactions"];
					return;
				}
				NSMutableArray *lines = [NSMutableArray array];
				for (NSDictionary *sender in senders)
					[lines addObject:[NSString stringWithFormat:@"%@  %@",
							sender[@"kind"], sender[@"id"]]];
				[weakSelf showText:(lines.count ? [lines componentsJoinedByString:@"\n"]
						: @"No sender may carry a paid reaction.") title:@"Paid Reactions"];
			}];
		}];
	} else if ([action isEqualToString:@"chatPaidPrice"]){
		[self askText:@"Chat Paid Message Price" message:@"Chat ID" placeholder:@"123"
				 text:nil action:@"Next" completion:^(NSString *chat){
			[weakSelf askText:@"Chat Paid Message Price" message:@"Stars per message"
					 placeholder:@"0" text:nil action:@"Save"
				   completion:^(NSString *price){
				[[TGClient shared] setChatPaidMessageStarCount:chat.longLongValue
														 count:price.intValue
													completion:^(BOOL ok, NSString *error){
					[weakSelf finish:ok error:error title:@"Paid Messages"];
				}];
			}];
		}];
	} else if ([action isEqualToString:@"callPaidPrice"]){
		[self askText:@"Call Paid Message Price" message:@"Group call ID"
			 placeholder:@"123" text:nil action:@"Next"
		   completion:^(NSString *call){
			[weakSelf askText:@"Call Paid Message Price" message:@"Stars per message"
					 placeholder:@"0" text:nil action:@"Save"
				   completion:^(NSString *price){
				[[TGClient shared] setGroupCallPaidMessageStarCount:call.intValue
															 count:price.intValue
														completion:^(BOOL ok, NSString *error){
					[weakSelf finish:ok error:error title:@"Paid Messages"];
				}];
			}];
		}];
	} else if ([action isEqualToString:@"topicUnpaid"]){
		[self askText:@"Topic Unpaid Messages" message:@"Chat ID" placeholder:@"123"
				 text:nil action:@"Next" completion:^(NSString *chat){
			[weakSelf askText:@"Topic Unpaid Messages" message:@"Topic ID"
					 placeholder:@"1" text:nil action:@"Next"
				   completion:^(NSString *topic){
				[TGAlertSheet showChoices:@[@"Allow unpaid messages",
											@"Disallow and refund"]
									title:@"Topic Unpaid Messages" destructiveIndex:-1
								   inView:weakSelf.view onChoice:^(NSInteger index){
					[[TGClient shared] setDirectMessagesTopicUnpaid:chat.longLongValue
															 topic:topic.longLongValue
														   allowed:(index == 0)
															refund:(index == 1)
														completion:^(BOOL ok, NSString *error){
						[weakSelf finish:ok error:error title:@"Topic Unpaid Messages"];
					}];
				}];
			}];
		}];
	} else if ([action isEqualToString:@"receipt"]){
		[self askText:@"Payment Receipt" message:@"Chat ID" placeholder:@"123"
				 text:nil action:@"Next" completion:^(NSString *chat){
			[weakSelf askText:@"Payment Receipt" message:@"Message ID" placeholder:@"456"
					 text:nil action:@"Read" completion:^(NSString *message){
				[[TGClient shared] paymentReceiptForChat:chat.longLongValue
												 message:message.longLongValue
											  completion:^(NSDictionary *receipt,
														   NSString *error){
					if (error){
						[weakSelf finish:NO error:error title:@"Receipt"];
						return;
					}
					[weakSelf showText:[NSString stringWithFormat:
							@"%@\n%@\n%@\n%@ Star(s)",
							receipt[@"title"], receipt[@"description"],
							receipt[@"kind"], receipt[@"starCount"]] title:@"Receipt"];
				}];
			}];
		}];
	} else if ([action isEqualToString:@"adAccount"]){
		int64_t ownerId = self.ownerId;
		if (!ownerId) ownerId = [[TGClient shared].me[@"id"] longLongValue];
		[[TGClient shared] starAdAccountURLForOwner:self.ownerKind ownerId:ownerId
										 completion:^(NSString *link, NSString *error){
			[weakSelf finish:error == nil error:error title:@"Ads Account"];
			if (link.length){
				[UIPasteboard generalPasteboard].string = link;
				[weakSelf showText:link title:@"Ads Account"];
			}
		}];
	} else if ([action isEqualToString:@"unrestrict"]){
		[self askText:@"Unrestrict Boost Count" message:@"Supergroup ID"
			 placeholder:@"123" text:nil action:@"Next"
		   completion:^(NSString *group){
			[weakSelf askText:@"Unrestrict Boost Count" message:@"0 to 8"
					 placeholder:@"1" text:nil action:@"Save"
				   completion:^(NSString *count){
				[[TGClient shared] setSupergroupUnrestrictBoostCount:count.intValue
														 supergroupId:group.longLongValue
														  completion:^(BOOL ok, NSString *error){
					[weakSelf finish:ok error:error title:@"Boost Settings"];
				}];
			}];
		}];
	} else if ([action isEqualToString:@"giveaway"]){
		[self askText:@"Giveaway" message:@"Chat ID" placeholder:@"123" text:nil
			   action:@"Next" completion:^(NSString *chat){
			[weakSelf askText:@"Giveaway" message:@"Message ID" placeholder:@"456"
				 text:nil action:@"Read" completion:^(NSString *message){
				[[TGClient shared] giveawayInfoForChat:chat.longLongValue
											   message:message.longLongValue
											completion:^(NSDictionary *info, NSString *error){
					if (error){
						[weakSelf finish:NO error:error title:@"Giveaway"];
						return;
					}
					[weakSelf showText:[NSString stringWithFormat:
							@"%@\nWinner: %@\nWinners: %@\nWon: %@ stars\nCode: %@",
							info[@"kind"], [info[@"isWinner"] boolValue] ? @"yes" : @"no",
							info[@"winnerCount"], info[@"wonStarCount"],
							info[@"giftCode"]] title:@"Giveaway"];
				}];
			}];
		}];
	} else if ([action isEqualToString:@"collectible"]){
		[TGAlertSheet showChoices:@[@"A username", @"A phone number"]
							title:@"Collectible" destructiveIndex:-1 inView:self.view
						 onChoice:^(NSInteger index){
			NSString *kind = index == 0 ? @"username" : @"phoneNumber";
			[weakSelf askText:@"Collectible" message:@"The value" placeholder:(index == 0 ? @"name" : @"+380...")
				 text:nil action:@"Read"
				   completion:^(NSString *value){
				[[TGClient shared] collectibleItemInfoForKind:kind value:value
												   completion:^(NSDictionary *info,
																NSString *error){
					if (error){
						[weakSelf finish:NO error:error title:@"Collectible"];
						return;
					}
					[weakSelf showText:[NSString stringWithFormat:
							@"%@ %@\nBought %@\n%@",
							info[@"amount"], info[@"currency"],
							info[@"purchaseDate"], info[@"url"]]
								   title:@"Collectible"];
				}];
			}];
		}];
	} else if ([action isEqualToString:@"subscribe"]){
		[[TGClient shared] clickPremiumSubscriptionButtonWithCompletion:
				^(BOOL ok, NSString *error){
			[weakSelf finish:ok error:error title:@"Premium"];
		}];
	} else if ([action isEqualToString:@"giftId"]){
		[self askGift:@"Gift ID" action:^(int64_t giftId){}];
	} else if ([action isEqualToString:@"available"]){
		[[TGClient shared] availableGiftsWithCompletion:^(NSArray *gifts, NSString *error){
			if (error){
				[weakSelf finish:NO error:error title:@"Gifts"];
				return;
			}
			NSMutableArray *lines = [NSMutableArray array];
			for (NSDictionary *gift in gifts)
				[lines addObject:[NSString stringWithFormat:@"%@  #%@  %@ stars",
						gift[@"title"], gift[@"id"], gift[@"starCount"]]];
			[weakSelf showText:(lines.count ? [lines componentsJoinedByString:@"\n"]
					: @"Telegram returned no gifts.") title:@"Gifts"];
		}];
	} else if ([action isEqualToString:@"canSend"]){
		[self askGift:@"Can Send Gift" action:^(int64_t giftId){
			[[TGClient shared] canSendGift:giftId
								completion:^(NSDictionary *result, NSString *error){
				if (error){
					[weakSelf finish:NO error:error title:@"Gift"];
					return;
				}
				NSString *line = [NSString stringWithFormat:@"%@\n%@",
						result[@"type"], result[@"reason"]];
				[weakSelf showText:line title:@"Can Send Gift"];
			}];
		}];
	} else if ([action isEqualToString:@"received"]){
		[self askText:@"Received Gift" message:@"received_gift_id" placeholder:@"gift-1"
			 text:nil action:@"Read" completion:^(NSString *text){
			[[TGClient shared] receivedGift:text
								 completion:^(NSDictionary *gift, NSString *error){
				if (error){
					[weakSelf finish:NO error:error title:@"Gift"];
					return;
				}
				[weakSelf showText:[NSString stringWithFormat:
						@"%@ %@\nSaved: %@\nPinned: %@\nCan upgrade: %@\nCan transfer: %@",
						gift[@"emoji"], gift[@"starCount"],
						[gift[@"isSaved"] boolValue] ? @"yes" : @"no",
						[gift[@"isPinned"] boolValue] ? @"yes" : @"no",
						[gift[@"canBeUpgraded"] boolValue] ? @"yes" : @"no",
						[gift[@"canBeTransferred"] boolValue] ? @"yes" : @"no"]
										   title:@"Received Gift"];
			}];
		}];
	} else if ([action isEqualToString:@"upgraded"] || [action isEqualToString:@"value"]){
		BOOL value = [action isEqualToString:@"value"];
		[self askText:(value ? @"Upgraded Gift Value" : @"Upgraded Gift")
				 message:@"Unique name" placeholder:@"gift-1" text:nil
				 action:@"Read" completion:^(NSString *text){
			if (value){
				[[TGClient shared] upgradedGiftValueInfoNamed:text
												   completion:^(NSDictionary *info,
																NSString *error){
					if (error){
						[weakSelf finish:NO error:error title:@"Gift Value"];
						return;
					}
					[weakSelf showText:[NSString stringWithFormat:
							@"%@ %@\nAverage: %@\nMinimum: %@\n%@",
							info[@"value"], info[@"currency"],
							info[@"isValueAverage"], info[@"minimumPrice"],
							info[@"fragmentUrl"]] title:@"Gift Value"];
				}];
			} else {
				[[TGClient shared] upgradedGiftNamed:text
										  completion:^(NSDictionary *gift, NSString *error){
					if (error){
						[weakSelf finish:NO error:error title:@"Gift"];
						return;
					}
					[weakSelf showText:[NSString stringWithFormat:
							@"%@\n#%@\n%@ %@\nValue: %@ %@",
							gift[@"title"], gift[@"number"], gift[@"model"],
							gift[@"symbol"], gift[@"valueAmount"],
							gift[@"valueCurrency"]] title:@"Upgraded Gift"];
				}];
			}
		}];
	} else if ([action isEqualToString:@"variants"] || [action isEqualToString:@"upgradePreview"]){
		BOOL preview = [action isEqualToString:@"upgradePreview"];
		[self askGift:(preview ? @"Upgrade Preview" : @"Gift Variants")
			   action:^(int64_t giftId){
			if (preview){
				[[TGClient shared] giftUpgradePreviewForGift:giftId
												 completion:^(NSDictionary *data,
															  NSString *error){
					[weakSelf finish:error == nil error:error title:@"Upgrade Preview"];
					if (!error) [weakSelf showText:[NSString stringWithFormat:
							@"%@ models, %@ symbols, %@ backdrops, %@ prices",
							@([data[@"models"] count]), @([data[@"symbols"] count]),
							@([data[@"backdrops"] count]), @([data[@"prices"] count])]
										   title:@"Upgrade Preview"];
				}];
			} else {
				[[TGClient shared] upgradedGiftVariantsForGift:giftId
												   completion:^(NSDictionary *data,
																NSString *error){
					[weakSelf finish:error == nil error:error title:@"Gift Variants"];
					if (!error) [weakSelf showText:[NSString stringWithFormat:
							@"%@ models, %@ symbols, %@ backdrops",
							@([data[@"models"] count]), @([data[@"symbols"] count]),
							@([data[@"backdrops"] count])] title:@"Gift Variants"];
				}];
			}
		}];
	} else if ([action isEqualToString:@"collections"]){
		int64_t ownerId = self.ownerId;
		if (!ownerId && [self.ownerKind isEqualToString:@"user"])
			ownerId = [[TGClient shared].me[@"id"] longLongValue];
		[[TGClient shared] giftCollectionsForOwner:self.ownerKind ownerId:ownerId
									   completion:^(NSArray *collections, NSString *error){
			if (error){
				[weakSelf finish:NO error:error title:@"Gift Collections"];
				return;
			}
			NSMutableArray *lines = [NSMutableArray array];
			for (NSDictionary *collection in collections)
				[lines addObject:[NSString stringWithFormat:@"%@  %@ gifts",
						collection[@"name"], collection[@"giftCount"]]];
			[weakSelf showText:(lines.count ? [lines componentsJoinedByString:@"\n"]
					: @"No gift collections.") title:@"Gift Collections"];
		}];
	} else if ([action isEqualToString:@"crafting"]){
		[self askGift:@"Gifts For Crafting" action:^(int64_t giftId){
			[[TGClient shared] giftsForCraftingFromGift:giftId offset:@"" limit:20
											 completion:^(NSArray *gifts, NSString *error){
				[weakSelf finish:error == nil error:error title:@"Crafting"];
				if (!error) [weakSelf showText:[NSString stringWithFormat:
						@"%lu gift(s) can be crafted.", (unsigned long)gifts.count]
									   title:@"Crafting"];
			}];
		}];
	} else if ([action isEqualToString:@"resale"]){
		[self askGift:@"Gifts For Resale" action:^(int64_t giftId){
			[[TGClient shared] searchGiftsForResaleFromGift:giftId
													 order:@"giftForResaleOrderPrice"
													offset:@""
													 limit:20
												completion:^(NSArray *gifts, NSString *error){
				if (error){
					[weakSelf finish:NO error:error title:@"Resale"];
					return;
				}
				NSMutableArray *lines = [NSMutableArray array];
				for (NSDictionary *gift in gifts)
					[lines addObject:[NSString stringWithFormat:@"%@  #%@",
							gift[@"title"] ?: gift[@"name"], gift[@"number"]]];
				[weakSelf showText:(lines.count ? [lines componentsJoinedByString:@"\n"]
						: @"No resale gifts.") title:@"Resale"];
			}];
		}];
	} else if ([action isEqualToString:@"emojiStatuses"]){
		[[TGClient shared] upgradedGiftEmojiStatusesWithCompletion:^(NSArray *statuses,
																	 NSString *error){
			if (error){
				[weakSelf finish:NO error:error title:@"Gift Statuses"];
				return;
			}
			NSMutableArray *lines = [NSMutableArray array];
			for (NSDictionary *status in statuses)
				[lines addObject:status[@"giftTitle"] ?: status[@"type"]];
			[weakSelf showText:(lines.count ? [lines componentsJoinedByString:@"\n"]
					: @"No gift emoji statuses.") title:@"Gift Statuses"];
		}];
	} else if ([action isEqualToString:@"themes"]){
		[[TGClient shared] giftChatThemesWithOffset:@"" limit:20
										 completion:^(NSArray *themes, NSString *error){
			if (error){
				[weakSelf finish:NO error:error title:@"Gift Themes"];
				return;
			}
			NSMutableArray *lines = [NSMutableArray array];
			for (NSDictionary *theme in themes)
				[lines addObject:theme[@"giftTitle"] ?: theme[@"giftName"]];
			[weakSelf showText:(lines.count ? [lines componentsJoinedByString:@"\n"]
					: @"No gift chat themes.") title:@"Gift Themes"];
		}];
	} else if ([action isEqualToString:@"auctionState"]){
		[self askText:@"Gift Auction" message:@"Auction id" placeholder:@"auction-1"
				 text:nil action:@"Read" completion:^(NSString *auction){
			[[TGClient shared] giftAuctionStateForAuction:auction
											   completion:^(NSDictionary *state,
															NSString *error){
				if (error){
					[weakSelf finish:NO error:error title:@"Gift Auction"];
					return;
				}
				[weakSelf showText:[NSString stringWithFormat:
						@"%@\nGift: %@\nStart %@  end %@\nMin bid %@\nRound %@ of %@",
						state[@"state"], state[@"giftTitle"], state[@"startDate"],
						state[@"endDate"], state[@"minBid"], state[@"currentRoundNumber"],
						state[@"totalRoundCount"]] title:@"Gift Auction"];
			}];
		}];
	} else if ([action isEqualToString:@"auctionGifts"]){
		[self askGift:@"Acquired Auction Gifts" action:^(int64_t giftId){
			[[TGClient shared] giftAuctionAcquiredGiftsForGift:giftId
													completion:^(NSArray *gifts, NSString *error){
				if (error){
					[weakSelf finish:NO error:error title:@"Auction Gifts"];
					return;
				}
				NSMutableArray *lines = [NSMutableArray array];
				for (NSDictionary *gift in gifts)
					[lines addObject:[NSString stringWithFormat:
							@"#%@  %@ stars  round %@", gift[@"uniqueGiftNumber"],
							gift[@"starCount"], gift[@"roundNumber"]]];
				[weakSelf showText:(lines.count ? [lines componentsJoinedByString:@"\n"]
						: @"No acquired auction gifts.") title:@"Auction Gifts"];
			}];
		}];
	} else if ([action isEqualToString:@"auctionOpen"] ||
			   [action isEqualToString:@"auctionClose"]){
		BOOL open = [action isEqualToString:@"auctionOpen"];
		[self askGift:(open ? @"Open Gift Auction" : @"Close Gift Auction")
			   action:^(int64_t giftId){
			if (open){
				[[TGClient shared] openGiftAuctionForGift:giftId
											   completion:^(BOOL ok, NSString *error){
					[weakSelf finish:ok error:error title:@"Gift Auction"];
				}];
			} else {
				[[TGClient shared] closeGiftAuctionForGift:giftId
												completion:^(BOOL ok, NSString *error){
					[weakSelf finish:ok error:error title:@"Gift Auction"];
				}];
			}
		}];
	} else if ([action isEqualToString:@"promo"]){
		[[TGClient shared] upgradedGiftsPromotionalAnimationWithCompletion:
				^(NSDictionary *animation, NSString *error){
			[weakSelf finish:error == nil error:error title:@"Promotional Animation"];
			if (!error) [weakSelf showText:[NSString stringWithFormat:
					@"%@  file %@", animation[@"@type"], animation[@"file"][@"id"]]
								   title:@"Promotional Animation"];
		}];
	}
}

@end

// vim:ft=objc
