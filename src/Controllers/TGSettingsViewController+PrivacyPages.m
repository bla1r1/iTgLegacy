//
// TGSettingsViewController+PrivacyPages.m
// Settings pages for notifications, privacy, security, and blocked users.
//
#import "TGSettingsViewControllerInternal.h"
#import "TGAlertSheet.h"
#import "TGCloseFriendsViewController.h"
#import "TGSessionsViewController.h"
#import "TGChatViewController.h"
#import "TGListViewController.h"
#import "TGAdminRightsViewController.h"

@implementation TGSettingsViewController (PrivacyPages)

- (NSArray *)notificationSections {
	__weak typeof(self) weakSelf = self;
	NSArray *scopes = @[@"private", @"groups", @"channels"];
	NSArray *titles = @[@"Private Chats", @"Groups", @"Channels"];

	NSMutableArray *show = [NSMutableArray array];
	NSMutableArray *preview = [NSMutableArray array];
	for (NSUInteger i = 0; i < scopes.count; i++){
		NSString *scope = scopes[i];
		[show addObject:TGSwitchRow(titles[i], ![weakSelf.muted[scope] boolValue],
				^(BOOL on){
			weakSelf.muted[scope] = @(!on);
			[[TGClient shared] setScope:scope muted:!on];
		})];
		[preview addObject:TGSwitchRow(titles[i], [weakSelf.previews[scope] boolValue],
				^(BOOL on){
			weakSelf.previews[scope] = @(on);
			[[TGClient shared] setScope:scope showPreview:on];
		})];
	}

	// Reactions are their own settings record in TDLib, not a scope. The
	// switch writes one field of it; the default and the recent list are the
	// two things the reaction bar reads before it draws.
	NSString *defaultEmoji = [TGClient shared].defaultReactionEmoji ?: @"\U0001F44D";
	NSArray *reactionRows = @[
		TGSwitchRow(@"Message Reactions", [TGClient shared].reactionNotificationsEnabled,
				^(BOOL on){
			[[TGClient shared] setReactionNotificationsEnabled:on completion:^(BOOL ok){
				if (!ok)
					[TGAlertSheet showMessage:@"Telegram refused that setting."
										 title:@"Reactions"
										inView:weakSelf.view];
				[weakSelf loadForPage];
			}];
		}),
		TGTapRow(@"Default Reaction", defaultEmoji, ^{
			NSArray *choices = [TGReactionPicker defaultReactions];
			[TGAlertSheet showChoices:choices
								title:@"Default Reaction"
							  message:@"The reaction bar leads with this one."
					   destructiveIndex:-1
							   inView:weakSelf.view
							 onChoice:^(NSInteger index){
				NSString *emoji = choices[(NSUInteger)index];
				[[TGClient shared] setDefaultReactionEmoji:emoji completion:^(BOOL ok){
					if (!ok)
						[TGAlertSheet showMessage:@"Telegram refused that default reaction."
											 title:@"Reactions"
											inView:weakSelf.view];
					[weakSelf loadForPage];
				}];
			}];
		}),
		TGRedRow(@"Clear Recently Used Reactions", ^{
			[TGAlertSheet showConfirm:@"The reaction bar forgets the ones you "
									  @"used last, on every device."
								title:@"Clear Recent Reactions"
							   action:@"Clear"
						  destructive:YES
							   inView:weakSelf.view
							onConfirm:^{
				[[TGClient shared] clearRecentReactionsWithCompletion:^(BOOL ok){
					if (ok)
						[TGAlertSheet showMessage:@"Recently used reactions cleared."
											 title:@"Reactions"
											inView:weakSelf.view];
				}];
			}];
		}),
	];

	return @[
		TGSection(@"Show notifications for", nil, show),
		TGSection(@"Message previews",
				  @"With previews off a notification says who wrote, not what "
				  @"they wrote.", preview),
		TGSection(@"Reactions",
				  @"Notification settings for reactions and poll votes live in "
				  @"the same record; only the message source moves here.",
				  reactionRows),
		TGSection(@"Per-chat exceptions", nil, @[
			TGTapRow(@"Chats With Custom Settings", nil, ^{
				[[TGClient shared] notificationExceptionsWithCompletion:^(NSArray *chats){
					NSMutableArray *rows = [NSMutableArray array];
					for (NSDictionary *chat in chats){
						[rows addObject:@{@"title" : chat[@"title"] ?: @"Chat",
										  @"detail" : @"Open",
										  @"tap" : ^{
							TGChatViewController *vc = [[TGChatViewController alloc] init];
							vc.chatId = [chat[@"id"] longLongValue];
							vc.chatTitle = chat[@"title"];
							vc.isGroup = [chat[@"isGroup"] boolValue];
							vc.hidesBottomBarWhenPushed = YES;
							[weakSelf.navigationController pushViewController:vc animated:YES];
						}}];
					}
					TGListViewController *list = [[TGListViewController alloc] init];
					list.listTitle = @"Notification Exceptions";
					list.rows = rows;
					list.emptyText = @"Every chat uses the default settings.";
					list.listFooter = @"Muted chats, chats with a custom sound, and "
									  @"chats whose previews differ from their scope.";
					list.hidesBottomBarWhenPushed = YES;
					[weakSelf.navigationController pushViewController:list animated:YES];
				}];
			}),
		]),

		TGSection(nil,
				  @"Undoes every exception you have set on an individual chat, "
				  @"on every device.",
				  @[TGRedRow(@"Reset All Notifications", ^{
			[TGAlertSheet showConfirm:@"Every per-chat notification exception will "
									  @"be forgotten."
								title:@"Reset All Notifications"
							   action:@"Reset"
						  destructive:YES
							   inView:weakSelf.view
							onConfirm:^{
				[[TGClient shared] resetAllNotificationSettings];
				[weakSelf loadForPage];
			}];
		})]),
	];
}

- (NSArray *)privacySections {
	__weak typeof(self) weakSelf = self;

	NSMutableArray *rules = [NSMutableArray array];
	NSArray *settings = [TGSettingsViewController privacySettings];
	for (NSUInteger i = 0; i < settings.count; i++){
		NSString *setting = settings[i];
		NSUInteger index = i;
		[rules addObject:TGTapRow([TGSettingsViewController privacyTitles][index],
				TGPrivacyLabel(weakSelf.privacy[setting]), ^{
			[weakSelf askPrivacyRuleAtIndex:index];
		})];
	}

	NSString *passwordDetail = !weakSelf.passwordKnown ? @"..."
			: (weakSelf.hasPassword ? @"On" : @"Off");

	NSString *deleteLabel;
	NSInteger ttl = weakSelf.autoDeleteDefault;
	if (ttl < 0)         deleteLabel = @"...";
	else if (ttl == 0)   deleteLabel = @"Off";
	else if (ttl == 86400)     deleteLabel = @"1 day";
	else if (ttl == 604800)    deleteLabel = @"1 week";
	else if (ttl == 2592000)   deleteLabel = @"1 month";
	else                 deleteLabel = [NSString stringWithFormat:@"%ld days",
									 (long)(ttl / 86400)];

	return @[
		TGSection(@"Security", nil, @[
			TGTapRow(@"Two-Step Verification", passwordDetail, ^{
				[weakSelf showTwoStepState];
			}),
			TGTapRow(@"Login Email Address", nil, ^{
				[weakSelf showLoginEmailFlow];
			}),
			TGTapRow(@"Phone Number",
					[TGClient shared].me[@"phone_number"] ?: nil, ^{
				[weakSelf showChangePhoneFlow];
			}),
			TGTapRow(@"Temporary Password", nil, ^{
				[weakSelf showTemporaryPasswordFlow];
			}),
			TGTapRow(@"Application Verification",
					[TGClient shared].pendingApplicationVerificationId ? @"Required" : @"None",
					^{
				[weakSelf showApplicationVerification];
			}),
			TGTapRow(@"Default Admin Rights", nil, ^{
				TGAdminRightsViewController *rights =
						[[TGAdminRightsViewController alloc] init];
				rights.hidesBottomBarWhenPushed = YES;
				[weakSelf.navigationController pushViewController:rights animated:YES];
			}),
			TGTapRow(@"Active Sessions", nil, ^{
				TGSessionsViewController *sessions = [[TGSessionsViewController alloc] init];
				sessions.hidesBottomBarWhenPushed = YES;
				[weakSelf.navigationController pushViewController:sessions animated:YES];
			}),
			TGTapRow(@"Blocked Users", nil, ^{
				[weakSelf openPage:TGSettingsPageBlocked];
			}),
		]),

		TGSection(@"Email",
				  @"Passport asks services to prove they own an address. This is "
				  @"the address half of that: send a code, enter it, and Telegram "
				  @"keeps the verified address on the account.", @[
			TGTapRow(@"Verify an Email Address", nil, ^{
				[weakSelf showVerifyEmailFlow];
			}),
		]),

		TGSection(@"Saved payment data", nil, @[
			TGRedRow(@"Delete Saved Payment Credentials", ^{
				[TGAlertSheet showConfirm:@"Every payment provider this account "
										  @"saved credentials with forgets them."
									title:@"Delete Saved Credentials"
								   action:@"Delete"
							  destructive:YES
								   inView:weakSelf.view
								onConfirm:^{
					[[TGClient shared] deleteSavedCredentialsWithCompletion:^(NSString *error){
						[TGAlertSheet showMessage:(error
								?: @"Saved credentials deleted on every bot.")
											title:@"Saved Payment Credentials"
										   inView:weakSelf.view];
					}];
				}];
			}),
		]),

		TGSection(nil, @"New chats carry this timer until one of the two "
				  @"of you sets an auto-delete on that chat in particular.",
				  @[
			TGTapRow(@"Delete Messages By Default", deleteLabel, ^{
				[TGAlertSheet showChoices:@[@"Off", @"1 day", @"1 week", @"1 month"]
									title:@"Delete messages in new chats after"
						 destructiveIndex:-1
								   inView:weakSelf.view
								 onChoice:^(NSInteger index){
					static const NSInteger seconds[4] = {0, 86400, 604800, 2592000};
					[[TGClient shared] setDefaultMessageAutoDeleteTime:seconds[index]];
					weakSelf.autoDeleteDefault = seconds[index];
					[weakSelf rebuild];
				}];
			}),
		]),

		TGSection(nil,
				  @"Your own t.me link works without a username, and can be "
				  @"given to someone who has no way to search for you.", @[
			TGTapRow(@"My Link", nil, ^{
				[[TGClient shared] myUserLink:^(NSString *link){
					if (!link.length){
						[weakSelf toast:@"Telegram did not answer with a link."];
						return;
					}
					[TGAlertSheet showChoices:@[@"Copy"]
										title:link
									  message:nil
							 destructiveIndex:-1
									   inView:weakSelf.view
									 onChoice:^(NSInteger index){
						[UIPasteboard generalPasteboard].string = link;
						[weakSelf toast:@"Copied."];
					}];
				}];
			}),
		]),

		TGSection(@"New chats",
				  @"Who may write first, the chat shown as your own, and the "
				  @"public or idle chats that shape those limits.", @[
			TGSwitchRow(@"Messages From Unknown Users",
					weakSelf.newChatAllowUnknown, ^(BOOL on){
				weakSelf.newChatAllowUnknown = on;
				[[TGClient shared] setNewChatPrivacyAllowUnknown:on
													  completion:^(BOOL ok){
					if (!ok)
						[weakSelf toast:@"Telegram refused that setting."];
				}];
			}),
			TGTapRow(@"Personal Chat", weakSelf.personalChatId ? @"Set" : @"None", ^{
				[weakSelf choosePersonalChat];
			}),
			TGTapRow(@"Inactive Groups", nil, ^{
				[weakSelf showInactiveGroups];
			}),
			TGTapRow(@"My Public Chats", nil, ^{
				[weakSelf showPublicChats];
			}),
		]),

		TGSection(@"Who can see", nil, rules),

		TGSection(@"Read receipts",
				  @"Turning this off stops other people seeing when you have "
				  @"read their messages. It does not stop you seeing theirs.",
				  @[ weakSelf.readDateLoaded
						? TGSwitchRow(@"Read Receipts", weakSelf.showReadDate, ^(BOOL on){
				[[TGClient shared] setReadDateShown:on completion:^(BOOL ok, NSString *error){
					if (!ok){
						[TGAlertSheet showMessage:(error ?: @"Telegram refused that.")
											title:@"Read Receipts" inView:weakSelf.view];
						[weakSelf rebuild];
						return;
					}
					weakSelf.showReadDate = on;
					[weakSelf rebuild];
				}];
			})
						: TGTapRow(@"Read Receipts", @"...", nil) ]),

		TGSection(@"Close friends",
				  @"Close friends are contacts you pick; the list is what "
				  @"stories and other close-friend features read.",
				  @[
			TGTapRow(@"Close Friends",
					weakSelf.closeFriendsLoaded
							? [NSString stringWithFormat:@"%ld",
									(long)weakSelf.closeFriendsCount] : @"...",
					^{ [weakSelf showCloseFriends]; }),
			TGTapRow(@"Close Birthdays",
					weakSelf.closeBirthdayRows.count
							? [NSString stringWithFormat:@"%lu contacts",
									(unsigned long)weakSelf.closeBirthdayRows.count]
							: @"None nearby",
					^{ [weakSelf hideCloseBirthdays]; }),
		]),

		TGSection(@"Contacts",
				  @"Frequent contacts are ranked on Telegram's side; turning "
				  @"the suggestion off deletes that ranking.", @[
			TGSwitchRow(@"Suggest Frequent Contacts", weakSelf.suggestFrequent, ^(BOOL on){
				weakSelf.suggestFrequent = on;
				[[TGClient shared] setOption:@"disable_top_chats" boolValue:!on];
			}),
			TGRedRow(@"Delete Synced Contacts", ^{
				[TGAlertSheet showConfirm:@"The phone numbers this account uploaded "
										  @"to Telegram will be removed."
									title:@"Delete Synced Contacts"
								   action:@"Delete"
							  destructive:YES
								   inView:weakSelf.view
								onConfirm:^{
					[[TGClient shared] clearImportedContacts];
				}];
			}),
		]),

		TGSection(nil,
				  @"If you do not come online at least once within this period, "
				  @"the account is deleted along with everything in it.", @[
			TGTapRow(@"Delete My Account", weakSelf.accountTtl > 0
					? [NSString stringWithFormat:@"if away for %ld months",
							(long)(weakSelf.accountTtl / 30)]
					: @"...", ^{
				[TGAlertSheet showChoices:@[@"1 month", @"3 months",
											@"6 months", @"12 months"]
									title:@"Delete my account if away for"
						 destructiveIndex:-1
								   inView:weakSelf.view
								 onChoice:^(NSInteger index){
					static const NSInteger months[4] = {1, 3, 6, 12};
					[[TGClient shared] setAccountTtlDays:months[index] * 30];
					weakSelf.accountTtl = months[index] * 30;
					[weakSelf rebuild];
				}];
			}),
			TGRedRow(@"Delete Account Now", ^{
				[weakSelf askDeleteAccountNow];
			}),
		]),
	];
}

- (NSArray *)blockedSections {
	__weak typeof(self) weakSelf = self;
	if (!self.blocked.count)
		return @[TGSection(nil, nil, @[TGRow(TGKindPlain, @"Nobody is blocked")])];

	NSMutableArray *rows = [NSMutableArray array];
	for (NSDictionary *user in self.blocked){
		int64_t userId = [user[@"id"] longLongValue];
		[rows addObject:TGSubtitleRow(user[@"name"], @"Tap to unblock", ^{
			[[TGClient shared] setUser:userId blocked:NO];
			NSMutableArray *rest = [weakSelf.blocked mutableCopy];
			[rest removeObject:user];
			weakSelf.blocked = rest;
			[weakSelf rebuild];
		})];
	}
	return @[TGSection(nil, nil, rows)];
}


- (void)choosePersonalChat {
	__weak typeof(self) weakSelf = self;
	[[TGClient shared] suitablePersonalChatsWithCompletion:^(NSArray *chats){
		TGSettingsViewController *me = weakSelf;
		if (!me)
			return;
		if (!chats.count){
			[TGAlertSheet showMessage:@"Telegram named no suitable channels."
								title:@"Personal Chat" inView:me.view];
			return;
		}
		NSMutableArray *titles = [NSMutableArray arrayWithObject:@"None"];
		for (NSDictionary *chat in chats)
			[titles addObject:chat[@"title"] ?: @"Channel"];
		[TGAlertSheet showChoices:titles title:@"Personal Chat"
				destructiveIndex:-1 inView:me.view onChoice:^(NSInteger index){
			int64_t chatId = index == 0 ? 0 : [chats[index - 1][@"id"] longLongValue];
			[[TGClient shared] setPersonalChat:chatId completion:^(BOOL ok){
				if (!ok){
					[TGAlertSheet showMessage:@"Telegram refused that chat."
										title:@"Personal Chat" inView:me.view];
					return;
				}
				me.personalChatId = chatId;
				[NSUserDefaults.standardUserDefaults setObject:@(chatId)
													   forKey:@"TGPersonalChatId"];
				[me rebuild];
			}];
		}];
	}];
}

- (void)showInactiveGroups {
	__weak typeof(self) weakSelf = self;
	[[TGClient shared] inactiveSupergroupChatsWithCompletion:^(NSArray *chats){
		TGSettingsViewController *me = weakSelf;
		if (!me)
			return;
		NSMutableArray *rows = [NSMutableArray array];
		for (NSDictionary *chat in chats){
			[rows addObject:@{@"title" : chat[@"title"] ?: @"Group",
							  @"detail" : @"Open",
							  @"tap" : ^{
				TGChatViewController *vc = [[TGChatViewController alloc] init];
				vc.chatId = [chat[@"id"] longLongValue];
				vc.chatTitle = chat[@"title"];
				vc.isGroup = YES;
				vc.hidesBottomBarWhenPushed = YES;
				[me.navigationController pushViewController:vc animated:YES];
			}}];
		}
		TGListViewController *list = [[TGListViewController alloc] init];
		list.listTitle = @"Inactive Groups";
		list.rows = rows;
		list.emptyText = @"No supergroups have gone quiet.";
		list.listFooter = @"Groups and channels you have not opened for a while, "
						  @"which can be left when the joined-chat limit is reached.";
		list.hidesBottomBarWhenPushed = YES;
		[me.navigationController pushViewController:list animated:YES];
	}];
}

- (void)showPublicChats {
	__weak typeof(self) weakSelf = self;
	[[TGClient shared] createdPublicChatsOfType:@"username" completion:^(NSArray *chats){
		TGSettingsViewController *me = weakSelf;
		if (!me)
			return;
		[[TGClient shared] checkCreatedPublicChatsLimitForType:@"username"
				completion:^(BOOL ok, NSString *reason){
			NSMutableArray *rows = [NSMutableArray arrayWithObject:@{
				@"title" : @"Check a Username",
				@"detail" : @"For a new public chat",
				@"tap" : ^{ [me checkUsernameForChat:@{@"id" : @(0)}]; },
			}];
			for (NSDictionary *chat in chats){
				[rows addObject:@{@"title" : chat[@"title"] ?: @"Channel",
								  @"detail" : @"Check a username",
								  @"tap" : ^{ [me checkUsernameForChat:chat]; }}];
			}
			TGListViewController *list = [[TGListViewController alloc] init];
			list.listTitle = @"My Public Chats";
			list.rows = rows;
			list.emptyText = @"This account owns no public chats yet.";
			list.listFooter = ok
					? @"The account can still create a public chat."
					: (reason ?: @"The public-chat limit is reached.");
			list.hidesBottomBarWhenPushed = YES;
			[me.navigationController pushViewController:list animated:YES];
		}];
	}];
}

- (void)checkUsernameForChat:(NSDictionary *)chat {
	__weak typeof(self) weakSelf = self;
	int64_t chatId = [chat[@"id"] longLongValue];
	[TGAlertSheet showInput:@"Check Username"
					message:@"Ask Telegram whether this @name is free for the chat."
				placeholder:@"username" text:nil action:@"Check"
					 inView:self.view onSubmit:^(NSString *username){
		[[TGClient shared] checkUsername:username forChat:chatId
							  completion:^(NSString *result){
			NSString *say = nil;
			if ([result isEqualToString:@"ok"])
				say = @"That username is free for this chat.";
			else if ([result isEqualToString:@"occupied"])
				say = @"Someone else has that username.";
			else if ([result isEqualToString:@"invalid"])
				say = @"Telegram does not accept that username.";
			else if ([result isEqualToString:@"purchasable"])
				say = @"That username is for sale, not free.";
			else if ([result isEqualToString:@"tooMany"])
				say = @"This account already owns too many public chats.";
			else if ([result isEqualToString:@"unavailable"])
				say = @"Public groups are unavailable to this account.";
			else
				say = @"Telegram did not answer.";
			[TGAlertSheet showMessage:say title:@"Check Username"
							   inView:weakSelf.view];
		}];
	}];
}

- (void)hideCloseBirthdays {
	__weak typeof(self) weakSelf = self;
	[[TGClient shared] hideContactCloseBirthdaysWithCompletion:^(BOOL ok, NSString *error){
		if (!ok){
			[TGAlertSheet showMessage:(error ?: @"Telegram refused that.")
								title:@"Close Birthdays" inView:weakSelf.view];
			return;
		}
		weakSelf.closeBirthdayRows = @[];
		[weakSelf rebuild];
		[TGAlertSheet showMessage:@"The close-birthday list is hidden for 24 hours."
							title:@"Close Birthdays" inView:weakSelf.view];
	}];
}

/// The close-friends list is a contact picker, because Telegram accepts only
/// contacts in setCloseFriends. The controller behind it writes the whole
/// list back and reports the count that stuck.
- (void)showCloseFriends {
	__weak typeof(self) weakSelf = self;
	TGCloseFriendsViewController *friends = [[TGCloseFriendsViewController alloc] init];
	friends.onCountChanged = ^(NSInteger count){
		weakSelf.closeFriendsCount = count;
		[weakSelf rebuild];
	};
	friends.hidesBottomBarWhenPushed = YES;
	[weakSelf.navigationController pushViewController:friends animated:YES];
}

@end
