#import "TGSettingsViewControllerInternal.h"
#import "TGAlertSheet.h"
#import "TGForwardPicker.h"
#import "TGStyle.h"
#import "TGGalleryViewController.h"
#import "AppDelegate.h"
#import "TGChatViewController.h"
#import "TGDevShowcase.h"
#import "TGStickerPacksViewController.h"

@implementation TGSettingsViewController (Pages)

#pragma mark - pages

- (NSArray *)buildSections {
	switch (self.page){
		case TGSettingsPageAppearance:    return [self appearanceSections];
		case TGSettingsPageData:          return [self dataSections];
		case TGSettingsPageNotifications: return [self notificationSections];
		case TGSettingsPagePrivacy:       return [self privacySections];
		case TGSettingsPageLanguage:      return [self languageSections];
		case TGSettingsPageBlocked:       return [self blockedSections];
		case TGSettingsPagePowerSaving:   return [self powerSavingSections];
		case TGSettingsPageRecentCalls:   return [self recentCallSections];
		case TGSettingsPageFolders:       return [self folderSections];
		case TGSettingsPageProxy:         return [self proxySections];
		case TGSettingsPageDownloads:     return [self downloadSections];
		case TGSettingsPageWallpaper:     return [self wallpaperSections];
		case TGSettingsPageDebug:         return [self debugSections];
		default:                          return [self rootSections];
	}
}

- (NSArray *)rootSections {
	__weak typeof(self) weakSelf = self;
	NSDictionary *me = [TGClient shared].me;
	BOOL hasPhoto = [[TGClient shared] photoFileIdForUserId:
			[me[@"id"] longLongValue]] != nil;

	return @[
		// Profile header card
		TGSection(nil, nil, @[
			TGRow(TGKindProfile, @""),
		]),

		// Account actions card
		TGSection(nil, nil, @[
			// Rows like every other in Settings: a glyph on a tile, dark text,
			// a chevron. Two bare blue lines above an icon row read as a
			// different list that had lost its margin.
			([TGClient shared].authState != TGAuthStateReady) ? TGIconRow(@"Log in to Telegram", @"privacy", TGIconTileAzure(), ^{
				[[AppDelegate sharedDelegate] showLoginUI];
			}) : TGIconRow(@"Add Account", @"select", TGIconTileAzure(), ^{ [weakSelf explainAddAccount]; }),
			TGIconRow(hasPhoto ? @"Change Profile Photo" : @"Set Profile Photo", @"react", TGIconTileCoral(), ^{
				[weakSelf pickProfilePhoto];
			}),
			TGIconRow(@"Edit Profile", @"chat", TGIconTileViolet(), ^{
				UIViewController *edit = [[TGEditProfileViewController alloc] init];
				edit.hidesBottomBarWhenPushed = YES;
				[weakSelf.navigationController pushViewController:edit animated:YES];
			}),
		]),

		TGSection(nil, nil, @[
			TGIconRow(@"Saved Messages", @"folder", TGIconTileSky(), ^{
				[weakSelf openSavedMessages];
			}),
			TGIconRow(@"Stickers", @"star", TGIconTileViolet(), ^{
				TGStickerPacksViewController *packs =
						[[TGStickerPacksViewController alloc] init];
				packs.hidesBottomBarWhenPushed = YES;
				[weakSelf.navigationController pushViewController:packs animated:YES];
			}),
			TGIconRow(@"Recent Calls", @"call", TGIconTileGreen(), ^{
				[weakSelf openPage:TGSettingsPageRecentCalls];
			}),
			TGIconRow(@"Devices", @"devices", TGIconTileAmber(), ^{
				TGSessionsViewController *sessions = [[TGSessionsViewController alloc] init];
				sessions.hidesBottomBarWhenPushed = YES;
				[weakSelf.navigationController pushViewController:sessions animated:YES];
			}),
			TGIconRow(@"Chat Folders", @"folder", TGIconTileCyan(), ^{
				[weakSelf openPage:TGSettingsPageFolders];
			}),
			TGIconRow(@"Proxy", @"data", TGIconTileGrey(), ^{
				[weakSelf openPage:TGSettingsPageProxy];
			}),
		]),

		TGSection(nil, nil, @[
			TGIconRow(@"Notifications and Sounds", @"notifications", TGIconTileRed(), ^{
				[weakSelf openPage:TGSettingsPageNotifications];
			}),
			TGIconRow(@"Privacy and Security", @"privacy", TGIconTileGrey(), ^{
				[weakSelf openPage:TGSettingsPagePrivacy];
			}),
			TGIconRow(@"Data and Storage", @"data", TGIconTileGreen(), ^{
				[weakSelf openPage:TGSettingsPageData];
			}),
			TGIconRow(@"Appearance", @"chat", TGIconTileSky(), ^{
				[weakSelf openPage:TGSettingsPageAppearance];
			}),
			TGIconRow(@"Power Saving", @"battery", TGIconTileAmber(), ^{
				[weakSelf openPage:TGSettingsPagePowerSaving];
			}),
			TGIconRow(@"Language", @"language", TGIconTileViolet(), ^{
				[weakSelf openPage:TGSettingsPageLanguage];
			}),
			TGIconRow(@"Device", @"devices", TGIconTileSlate(), ^{
				TGDeviceViewController *device = [[TGDeviceViewController alloc] init];
				device.hidesBottomBarWhenPushed = YES;
				[weakSelf.navigationController pushViewController:device animated:YES];
			}),
		]),

		TGSection(nil, nil, @[
			TGIconRow(@"Telegram Premium", @"star", TGIconTilePurple(), ^{
				[weakSelf showPremiumState];
			}),
			TGIconRow(@"Telegram Business", @"briefcase", TGIconTileAzure(), ^{
				[weakSelf pushPlaceholder:@"Telegram Business"];
			}),
			TGIconRow(@"Send a Gift", @"gift", TGIconTileCoral(), ^{
				[weakSelf pushPlaceholder:@"Send a Gift"];
			}),
		]),

		TGSection(nil, nil, @[
			TGIconRow(@"Ask a Question", @"chat", TGIconTileAmber(), ^{
				[weakSelf openSupport];
			}),
			TGIconRow(@"Telegram FAQ", @"faq", TGIconTileCyan(), ^{
				[weakSelf openURL:@"https://telegram.org/faq"];
			}),
			TGIconRow(@"Privacy Policy", @"policy", TGIconTileGold(), ^{
				[weakSelf openURL:@"https://telegram.org/privacy"];
			}),
		]),

		TGSection(nil, nil, @[
			TGRedRow(@"Log out", ^{
				[TGAlertSheet showConfirm:@"Are you sure you want to log out?"
									title:@"Log out"
								   action:@"Log out"
							  destructive:YES
								   inView:weakSelf.view
								onConfirm:^{ [[TGClient shared] logOut]; }];
			}),
		]),
	];
}

- (NSArray *)languageSections {
	__weak typeof(self) weakSelf = self;
	NSMutableArray *rows = [NSMutableArray array];
	for (NSDictionary *language in self.languages){
		NSString *packId = language[@"id"];
		[rows addObject:TGCheckRow(language[@"name"], nil,
				[packId isEqualToString:self.currentLanguage], ^{
			[[TGClient shared] setLanguage:packId];
			weakSelf.currentLanguage = packId;
			[weakSelf rebuild];
		})];
	}
	if (!rows.count)
		[rows addObject:TGRow(TGKindPlain, @"Loading...")];

	return @[TGSection(nil,
			@"This app's own text is English throughout. The language is what "
			@"Telegram itself writes in, and it follows the account onto your "
			@"other devices.", rows)];
}

- (NSArray *)recentCallSections {
	__weak typeof(self) weakSelf = self;
	if (!self.calls.count)
		return @[TGSection(nil, nil, @[TGRow(TGKindPlain, @"No recent calls")])];

	static NSDateFormatter *when = nil;
	if (!when){
		when = [[NSDateFormatter alloc] init];
		when.dateStyle = NSDateFormatterShortStyle;
		when.timeStyle = NSDateFormatterShortStyle;
	}

	NSMutableArray *rows = [NSMutableArray array];
	for (NSDictionary *call in self.calls){
		BOOL missed = [call[@"missed"] boolValue];
		BOOL outgoing = [call[@"outgoing"] boolValue];
		NSInteger duration = [call[@"duration"] integerValue];
		NSString *detail = [NSString stringWithFormat:@"%@ %@%@",
				(outgoing ? @"Outgoing" : @"Incoming"),
				[when stringFromDate:[NSDate dateWithTimeIntervalSince1970:
						[call[@"date"] doubleValue]]],
				(!missed && duration > 0)
						? [NSString stringWithFormat:@" - %ld:%02ld",
								(long)(duration / 60), (long)(duration % 60)]
						: @""];

		NSMutableDictionary *row = [TGSubtitleRow(call[@"name"], detail, ^{
			[weakSelf pushPlaceholder:@"Call back"];
		}) mutableCopy];
		if (missed)
			row[TGRowKind] = TGKindDestructive;
		[rows addObject:row];
	}
	return @[TGSection(nil, nil, rows)];
}

/// Their Debug Menu, with what is actually inspectable on this build. Reached
/// by ten taps on the version, and linked from nowhere - the same bargain
/// their client makes.
- (NSArray *)debugSections {
	__weak typeof(self) weakSelf = self;
	NSDictionary *info = [NSBundle mainBundle].infoDictionary;

	// Whether the bundled emoji font actually registered - the one thing that
	// cannot be told apart from "no emoji in this message" by looking.
	UIFont *emoji = TGFontEmojiMeta();

	NSMutableArray *facts = [NSMutableArray array];
	[facts addObject:TGTapRow(@"App Version", [NSString stringWithFormat:@"%@ (%@)",
			info[@"CFBundleShortVersionString"] ?: @"?",
			info[@"CFBundleVersion"] ?: @"?"], nil)];
	[facts addObject:TGTapRow(@"TDLib", self.tdlibVersion ?: @"...", nil)];
	[facts addObject:TGTapRow(@"System", [UIDevice currentDevice].systemVersion, nil)];
	[facts addObject:TGTapRow(@"Device", [TGDevice modelName] ?: @"?", nil)];
	[facts addObject:TGTapRow(@"Machine", [TGDevice machine] ?: @"?", nil)];
	[facts addObject:TGTapRow(@"Tier", [TGDevice tierName] ?: @"?", nil)];
	[facts addObject:TGTapRow(@"Chip", [TGDevice chip] ?: @"unknown", nil)];
	[facts addObject:TGTapRow(@"Memory", [NSString stringWithFormat:@"%lu MB",
			(unsigned long)[TGCapabilities memoryMB]], nil)];
	[facts addObject:TGTapRow(@"Architecture",
			[TGCapabilities is64Bit] ? @"arm64" : @"armv7", nil)];
	[facts addObject:TGTapRow(@"Emoji Font",
			emoji ? emoji.fontName : @"NOT REGISTERED", nil)];
	[facts addObject:TGTapRow(@"Theme", [[TGTheme shared] currentThemeId], nil)];

	return @[
		TGSection(@"Dev & Showcase",
				  @"Interactive showcase for all 30 TDLib message types, vector Lottie (.tgs), and VP9 video (.webm) stickers.", @[
			TGTapRow(@"Open Message Types Showcase Chat", nil, ^{
				TGChatViewController *chat = [[TGChatViewController alloc] init];
				chat.chatId = kDevChatId;
				chat.chatTitle = @"Dev Showcase";
				chat.isGroup = YES;
				chat.hidesBottomBarWhenPushed = YES;
				[weakSelf.navigationController pushViewController:chat animated:YES];
			}),
		]),

		TGSection(@"Build", nil, facts),

		TGSection(@"Capabilities",
				  @"What this device is allowed to do, and what it is waiting "
				  @"for when it is not.", @[
			TGTapRow(@"Device Capabilities", nil, ^{
				TGDeviceViewController *device = [[TGDeviceViewController alloc] init];
				device.hidesBottomBarWhenPushed = YES;
				[weakSelf.navigationController pushViewController:device animated:YES];
			}),
		]),

		TGSection(@"Dev Harness",
				  @"Preview rich media, interactive polls, audio tracks, and custom stickers.", @[
			TGTapRow(@"Open Dev Showcase Chat", @"30 message types", ^{
				TGChatViewController *vc = [[TGChatViewController alloc] init];
				vc.chatId = kDevChatId;
				vc.chatTitle = @"Dev Showcase";
				vc.isGroup = YES;
				vc.hidesBottomBarWhenPushed = YES;
				[weakSelf.navigationController pushViewController:vc animated:YES];
			}),
		]),

		// The calls TDLib reserves for bot accounts. A user account still
		// sends them; the server's refusal is the honest answer, and the row
		// exists so the request and its result have a real surface.
		TGSection(@"Bot Tools",
				  @"Requests a bot account owns. A user account will usually get "
				  @"Telegram's refusal back, shown as the answer.", @[
			TGTapRow(@"Callback Query Message", nil, ^{
				[TGAlertSheet showInput:@"Callback Query Message"
								message:@"Chat id" placeholder:@"-100..."
									 text:nil action:@"Next" inView:weakSelf.view
							   onSubmit:^(NSString *chat){
					int64_t chatId = [chat longLongValue];
					[TGAlertSheet showInput:@"Callback Query Message"
									message:@"Message id" placeholder:@"123"
										 text:nil action:@"Next" inView:weakSelf.view
								   onSubmit:^(NSString *message){
						int64_t messageId = [message longLongValue];
						[TGAlertSheet showInput:@"Callback Query Message"
										message:@"Callback query id"
									placeholder:@"0"
										 text:nil action:@"Fetch"
									   inView:weakSelf.view
								   onSubmit:^(NSString *query){
							[[TGClient shared] callbackQueryMessage:messageId
															 inChat:chatId
													callbackQueryId:[query longLongValue]
														 completion:^(NSDictionary *found){
								[TGAlertSheet showMessage:(found[@"text"] ?: @"Telegram refused or has no such callback.")
													title:@"Callback Query Message"
												   inView:weakSelf.view];
							}];
						}];
					}];
				}];
			}),
			TGTapRow(@"Personal Chat History", nil, ^{
				[TGAlertSheet showInput:@"Personal Chat History"
								message:@"User id" placeholder:@"123"
									 text:nil action:@"Fetch" inView:weakSelf.view
							   onSubmit:^(NSString *user){
					[[TGClient shared] personalChatHistoryForUser:[user longLongValue]
														   limit:20
													  completion:^(NSArray *messages){
						NSMutableString *body = [NSMutableString string];
						for (NSDictionary *message in messages)
							[body appendFormat:@"%@\n",
									message[@"text"] ?: @"(no text)"];
						if (!body.length)
							body = [@"Telegram refused or the chat is empty."
									mutableCopy];
						[TGAlertSheet showMessage:body
											title:@"Personal Chat History"
										   inView:weakSelf.view];
					}];
				}];
			}),
			TGTapRow(@"Set Reactions", nil, ^{
				[TGAlertSheet showInput:@"Set Reactions"
								message:@"Chat id" placeholder:@"-100..."
									 text:nil action:@"Next" inView:weakSelf.view
							   onSubmit:^(NSString *chat){
					int64_t chatId = [chat longLongValue];
					[TGAlertSheet showInput:@"Set Reactions"
									message:@"Message id" placeholder:@"123"
										 text:nil action:@"Next" inView:weakSelf.view
								   onSubmit:^(NSString *message){
						int64_t messageId = [message longLongValue];
						[TGAlertSheet showInput:@"Set Reactions"
										message:@"Emoji (empty clears)"
									placeholder:@"👍"
										 text:nil action:@"Set"
									   inView:weakSelf.view
								   onSubmit:^(NSString *emoji){
							[[TGClient shared] setReactions:(emoji.length ? @[emoji] : @[])
												  onMessage:messageId
													 inChat:chatId
												 completion:^(BOOL ok){
								[TGAlertSheet showMessage:(ok ? @"Reactions set."
															: @"Telegram refused that.")
													title:@"Set Reactions"
												   inView:weakSelf.view];
							}];
						}];
					}];
				}];
			}),
			TGTapRow(@"Send Text Draft", nil, ^{
				[TGAlertSheet showInput:@"Send Text Draft"
								message:@"Chat id" placeholder:@"-100..."
									 text:nil action:@"Next" inView:weakSelf.view
							   onSubmit:^(NSString *chat){
					int64_t chatId = [chat longLongValue];
					[TGAlertSheet showInput:@"Send Text Draft"
									message:@"Draft text" placeholder:@"Thinking..."
										 text:nil action:@"Send" inView:weakSelf.view
								   onSubmit:^(NSString *text){
						int64_t draftId = (int64_t)([[NSDate date]
								timeIntervalSince1970] * 1000);
						[[TGClient shared] sendTextDraft:text
												 toChat:chatId
												  topic:0
												draftId:draftId
												 canStop:YES
													keep:NO
											 completion:^(BOOL ok){
							NSString *body = ok
									? [NSString stringWithFormat:
											@"Draft sent. Its id is %lld.",
											(long long)draftId]
									: @"Telegram refused that.";
							[TGAlertSheet showMessage:body
												title:@"Send Text Draft"
											   inView:weakSelf.view];
						}];
					}];
				}];
			}),
			TGTapRow(@"Stop Text Draft", nil, ^{
				[TGAlertSheet showInput:@"Stop Text Draft"
								message:@"Chat id" placeholder:@"-100..."
									 text:nil action:@"Next" inView:weakSelf.view
							   onSubmit:^(NSString *chat){
					int64_t chatId = [chat longLongValue];
					[TGAlertSheet showInput:@"Stop Text Draft"
									message:@"Draft id" placeholder:@"0"
										 text:nil action:@"Stop" inView:weakSelf.view
								   onSubmit:^(NSString *draft){
						[[TGClient shared] stopTextDraft:[draft longLongValue]
												  inChat:chatId
												   topic:0
											  completion:^(BOOL ok){
							[TGAlertSheet showMessage:(ok ? @"Draft stopped."
														: @"Telegram refused that.")
												title:@"Stop Text Draft"
											   inView:weakSelf.view];
						}];
					}];
				}];
			}),
			TGTapRow(@"Prepared Inline Message", nil, ^{
				[TGAlertSheet showInput:@"Prepared Inline Message"
								message:@"Bot user id" placeholder:@"123"
									 text:nil action:@"Next" inView:weakSelf.view
							   onSubmit:^(NSString *bot){
					int64_t botId = [bot longLongValue];
					[TGAlertSheet showInput:@"Prepared Inline Message"
									message:@"Prepared message id"
								placeholder:@"prepared"
									 text:nil action:@"Fetch"
								   inView:weakSelf.view
							   onSubmit:^(NSString *prepared){
						[[TGClient shared] preparedInlineMessageFromBot:botId
													  preparedMessageId:prepared
														   completion:^(NSDictionary *found){
							NSString *body = found
									? [NSString stringWithFormat:@"Id: %@\nResult: %@",
											found[@"id"] ?: @"",
											found[@"result"] ?: @{}]
									: @"Telegram refused or has no such message.";
							[TGAlertSheet showMessage:body
												title:@"Prepared Inline Message"
											   inView:weakSelf.view];
						}];
					}];
				}];
			}),
			TGTapRow(@"Save Inline Message", nil, ^{
				[TGAlertSheet showInput:@"Save Inline Message"
								message:@"User id to prepare it for" placeholder:@"123"
									 text:nil action:@"Next" inView:weakSelf.view
							   onSubmit:^(NSString *user){
					int64_t userId = [user longLongValue];
					[TGAlertSheet showInput:@"Save Inline Message"
									message:@"Message text"
								placeholder:@"Hello"
									 text:nil action:@"Save"
								   inView:weakSelf.view
							   onSubmit:^(NSString *text){
						[[TGClient shared] savePreparedInlineMessageForUser:userId
																	 text:text
																	title:text
															   completion:^(NSString *preparedId){
							[TGAlertSheet showMessage:(preparedId.length
									? [NSString stringWithFormat:@"Saved as %@", preparedId]
									: @"Telegram refused that.")
												title:@"Save Inline Message"
											   inView:weakSelf.view];
						}];
					}];
				}];
			}),
			TGTapRow(@"Edit Inline Message", nil, ^{
				[TGAlertSheet showInput:@"Edit Inline Message"
								message:@"Inline message id"
							placeholder:@"AAH..."
									 text:nil action:@"Next"
								   inView:weakSelf.view
							   onSubmit:^(NSString *inlineId){
					[TGAlertSheet showChoices:@[@"Text", @"Caption",
												@"Remove Buttons", @"Photo",
												@"Live Location"]
										title:@"Edit Inline Message"
							  destructiveIndex:-1
									   inView:weakSelf.view
									 onChoice:^(NSInteger index){
						if (index == 0){
							[TGAlertSheet showInput:@"Edit Inline Message"
											message:@"New text" placeholder:@"Hello"
												 text:nil action:@"Save"
											   inView:weakSelf.view
										   onSubmit:^(NSString *text){
								[[TGClient shared] editInlineMessageText:inlineId
																	text:text
															  completion:^(BOOL ok){
									[TGAlertSheet showMessage:(ok ? @"Edited."
																: @"Telegram refused that.")
														title:@"Edit Inline Message"
													   inView:weakSelf.view];
								}];
							}];
						} else if (index == 1){
							[TGAlertSheet showInput:@"Edit Inline Message"
											message:@"New caption" placeholder:@"Caption"
												 text:nil action:@"Save"
											   inView:weakSelf.view
										   onSubmit:^(NSString *caption){
								[[TGClient shared] editInlineMessageCaption:inlineId
																   caption:caption
																completion:^(BOOL ok){
									[TGAlertSheet showMessage:(ok ? @"Caption saved."
																: @"Telegram refused that.")
														title:@"Edit Inline Message"
													   inView:weakSelf.view];
								}];
							}];
						} else if (index == 2){
							[[TGClient shared] clearInlineMessageReplyMarkup:inlineId
																 completion:^(BOOL ok){
								[TGAlertSheet showMessage:(ok ? @"Buttons removed."
															: @"Telegram refused that.")
													title:@"Edit Inline Message"
												   inView:weakSelf.view];
							}];
						} else if (index == 3){
							[TGAlertSheet showInput:@"Edit Inline Message"
											message:@"Photo id" placeholder:@"123"
												 text:nil action:@"Next"
											   inView:weakSelf.view
										   onSubmit:^(NSString *photo){
								int64_t photoId = [photo longLongValue];
								[TGAlertSheet showInput:@"Edit Inline Message"
												message:@"Caption" placeholder:@"Photo"
													 text:nil action:@"Save"
												   inView:weakSelf.view
											   onSubmit:^(NSString *caption){
									[[TGClient shared] editInlineMessagePhoto:inlineId
																	photoId:photoId
																	caption:caption
																 completion:^(BOOL ok){
										[TGAlertSheet showMessage:(ok ? @"Photo saved."
																	: @"Telegram refused that.")
															title:@"Edit Inline Message"
														   inView:weakSelf.view];
									}];
								}];
							}];
						} else {
							[TGAlertSheet showInput:@"Edit Inline Message"
											message:@"Latitude" placeholder:@"0.0"
												 text:nil action:@"Next"
											   inView:weakSelf.view
										   onSubmit:^(NSString *lat){
								double latitude = [lat doubleValue];
								[TGAlertSheet showInput:@"Edit Inline Message"
												message:@"Longitude" placeholder:@"0.0"
													 text:nil action:@"Save"
												   inView:weakSelf.view
											   onSubmit:^(NSString *lon){
									[[TGClient shared] editInlineMessageLiveLocation:inlineId
																			latitude:latitude
																		   longitude:[lon doubleValue]
																		  completion:^(BOOL ok){
										[TGAlertSheet showMessage:(ok ? @"Location moved."
																	: @"Telegram refused that.")
															title:@"Edit Inline Message"
														   inView:weakSelf.view];
									}];
								}];
							}];
						}
					}];
				}];
			}),
		]),

		TGSection(@"Chat Resolvers",
				  @"A chat id is what every screen carries. These turn the "
				  @"internal basic-group, supergroup or secret-chat id back "
				  @"into one, which is the compatibility path TDLib keeps for "
				  @"an account that only ever saw the inner id.", @[
			TGTapRow(@"Open Basic Group by ID", nil, ^{
				[TGAlertSheet showInput:@"Basic Group ID" message:nil
							placeholder:@"Group id" text:nil action:@"Open"
								 inView:weakSelf.view onSubmit:^(NSString *text){
					[[TGClient shared] chatForBasicGroup:text.longLongValue
											completion:^(int64_t chatId){
						[weakSelf openResolvedChat:chatId title:@"Basic Group"];
					}];
				}];
			}),
			TGTapRow(@"Open Supergroup by ID", nil, ^{
				[TGAlertSheet showInput:@"Supergroup ID" message:nil
							placeholder:@"Supergroup id" text:nil action:@"Open"
								 inView:weakSelf.view onSubmit:^(NSString *text){
					[[TGClient shared] chatForSupergroup:text.longLongValue
											completion:^(int64_t chatId){
						[weakSelf openResolvedChat:chatId title:@"Supergroup"];
					}];
				}];
			}),
			TGTapRow(@"Open Secret Chat by ID", nil, ^{
				[TGAlertSheet showInput:@"Secret Chat ID" message:nil
							placeholder:@"Secret chat id" text:nil action:@"Open"
								 inView:weakSelf.view onSubmit:^(NSString *text){
					[[TGClient shared] chatForSecretChat:(int32_t)text.intValue
											completion:^(int64_t chatId){
						[weakSelf openResolvedChat:chatId title:@"Secret Chat"];
					}];
				}];
			}),
		]),

		TGSection(@"Logging",
				  @"Verbose puts TDLib's own chatter into the system log, which "
				  @"is where a connection problem shows up. It is noisy and it "
				  @"costs speed, so it does not survive a restart.", @[
			TGTapRow(@"TDLib Log Verbosity: Errors", nil, ^{
				[[TGClient shared] send:@{@"@type" : @"setLogVerbosityLevel",
										  @"new_verbosity_level" : @(1)}];
				[weakSelf toast:@"Verbosity set to 1"];
			}),
			TGTapRow(@"TDLib Log Verbosity: Verbose", nil, ^{
				[[TGClient shared] send:@{@"@type" : @"setLogVerbosityLevel",
										  @"new_verbosity_level" : @(5)}];
				[weakSelf toast:@"Verbosity set to 5"];
			}),
		]),

		TGSection(@"Storage",
				  @"Documents is shared over iTunes file sharing, so anything "
				  @"written there can be pulled off the device.", @[
			TGTapRow(@"Clear Temporary Files", nil, ^{
				[weakSelf clearTemporaryFiles];
			}),
			TGTapRow(@"Storage Usage", nil, ^{
				TGStorageViewController *storage = [[TGStorageViewController alloc] init];
				storage.hidesBottomBarWhenPushed = YES;
				[weakSelf.navigationController pushViewController:storage animated:YES];
			}),
		]),

		TGSection(nil,
				  @"Resets this app's own preferences - theme, text size, power "
				  @"saving, auto-download. The session and the messages stay.", @[
			TGRedRow(@"Reset Local Preferences", ^{
				[TGAlertSheet showConfirm:@"Theme, text size and every switch in "
										  @"Settings go back to their defaults."
									title:@"Reset Local Preferences"
								   action:@"Reset"
							  destructive:YES
								   inView:weakSelf.view
								onConfirm:^{
					NSString *domain = [NSBundle mainBundle].bundleIdentifier;
					[NSUserDefaults.standardUserDefaults
							removePersistentDomainForName:domain];
					[NSUserDefaults.standardUserDefaults synchronize];
					[weakSelf repaint];
					[weakSelf toast:@"Preferences reset."];
				}];
			}),
		]),
	];
}

- (void)openResolvedChat:(int64_t)chatId title:(NSString *)title {
	if (!chatId){
		[TGAlertSheet showMessage:@"TDLib did not resolve that id to a chat."
							title:title inView:self.view];
		return;
	}
	TGChatViewController *chat = [[TGChatViewController alloc] init];
	chat.chatId = chatId;
	chat.chatTitle = title;
	chat.isGroup = YES;
	chat.hidesBottomBarWhenPushed = YES;
	[self.navigationController pushViewController:chat animated:YES];
}

- (void)toast:(NSString *)text {
	[TGAlertSheet showMessage:text title:nil inView:self.view];
}

@end
