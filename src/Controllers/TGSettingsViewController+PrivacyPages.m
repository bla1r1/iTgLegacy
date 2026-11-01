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
#import "TGActiveNotificationsViewController.h"

/// A unix time from a status record, or the honest "not scheduled" for 0.
static NSString *TGStatusDateText(id raw) {
	long long seconds = [raw longLongValue];
	if (seconds <= 0)
		return @"not scheduled";
	NSDate *date = [NSDate dateWithTimeIntervalSince1970:(NSTimeInterval)seconds];
	return [NSDateFormatter localizedStringFromDate:date
										 dateStyle:NSDateFormatterMediumStyle
										 timeStyle:NSDateFormatterShortStyle];
}

static NSString *TGFreezeDetail(NSDictionary *state) {
	if (![state isKindOfClass:NSDictionary.class])
		return @"Unknown";
	return [state[@"is_frozen"] boolValue] ? @"Frozen" : @"Not frozen";
}

/// Subscription flags are not exclusive: a canceled subscription can also
/// carry a failed payment. The row names the one that changes what to do.
static NSString *TGSubscriptionDetail(NSDictionary *record) {
	if (![record isKindOfClass:NSDictionary.class])
		return @"None";
	if ([record[@"is_payment_failed"] boolValue])
		return @"Payment failed";
	if ([record[@"is_canceled"] boolValue])
		return @"Canceled";
	if ([record[@"is_restored"] boolValue])
		return @"Restored";
	return @"Active";
}

static NSString *TGAgeVerificationDetail(NSDictionary *parameters) {
	if (![parameters isKindOfClass:NSDictionary.class])
		return @"Not set";
	NSInteger minAge = [parameters[@"min_age"] integerValue];
	if (minAge <= 0)
		return @"No minimum";
	return [NSString stringWithFormat:@"Age %ld+", (long)minAge];
}

@implementation TGSettingsViewController (PrivacyPages)

static NSString *TGNotificationWhen(NSNumber *stamp) {
	if (![stamp isKindOfClass:NSNumber.class] || ![stamp longLongValue])
		return @"";
	return [NSDateFormatter localizedStringFromDate:
			[NSDate dateWithTimeIntervalSince1970:[stamp doubleValue]]
			dateStyle:NSDateFormatterShortStyle
			timeStyle:NSDateFormatterShortStyle];
}

static NSString *TGSoundName(NSDictionary *sound) {
	NSString *title = sound[@"title"];
	if (title.length)
		return title;
	return [NSString stringWithFormat:@"Sound %@", sound[@"id"] ?: @(0)];
}

static NSString *TGNotificationGroupLabel(NSString *type) {
	if ([type isEqualToString:@"notificationGroupTypeMessages"]) return @"messages";
	if ([type isEqualToString:@"notificationGroupTypeMentions"]) return @"mentions";
	if ([type isEqualToString:@"notificationGroupTypeSecretChat"]) return @"secret chats";
	if ([type isEqualToString:@"notificationGroupTypeCalls"]) return @"calls";
	return type.length ? type : @"notifications";
}

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

	NSUInteger activeGroups = [TGClient shared].activeNotificationGroups.count;
	NSUInteger activeRows = 0;
	for (NSDictionary *group in [TGClient shared].activeNotificationGroups)
		activeRows += [group[@"notifications"] count];
	NSString *activeDetail;
	if ([TGClient shared].havePendingNotifications)
		activeDetail = @"Updating...";
	else if (activeRows)
		activeDetail = [NSString stringWithFormat:@"%lu in %lu groups",
				(unsigned long)activeRows, (unsigned long)activeGroups];
	else
		activeDetail = @"None";

	return @[
		TGSection(@"Show notifications for", nil, show),
		TGSection(@"Message previews",
				  @"With previews off a notification says who wrote, not what "
				  @"they wrote.", preview),
		TGSection(@"Active",
				  @"TDLib keeps the notifications it showed while this app was "
				  @"closed. They can be read and removed here without leaving "
				  @"the chat.", @[
			TGTapRow(@"Active Notifications", activeDetail, ^{
				TGActiveNotificationsViewController *active =
						[[TGActiveNotificationsViewController alloc] init];
				active.hidesBottomBarWhenPushed = YES;
				[weakSelf.navigationController pushViewController:active animated:YES];
			}),
		]),
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

		TGSection(@"Sounds and Local Notifications",
				  @"Custom sounds are stored on the account. The active list is "
				  @"TDLib's own copy; iOS still draws the banners.",
				  @[
			TGTapRow(@"Custom Sounds",
					weakSelf.savedSoundsLoaded
							? [NSString stringWithFormat:@"%lu",
								(unsigned long)weakSelf.savedSounds.count]
							: nil,
					^{ [weakSelf openPage:TGSettingsPageNotificationSounds]; }),
			TGTapRow(@"Active Notifications",
					[TGClient shared].activeNotificationGroups.count
							? [NSString stringWithFormat:@"%lu",
								(unsigned long)[TGClient shared].activeNotificationGroups.count]
							: @"None",
					^{ [weakSelf openPage:TGSettingsPageActiveNotifications]; }),
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

- (NSArray *)soundSections {
	__weak typeof(self) weakSelf = self;
	NSMutableArray *rows = [NSMutableArray array];
	for (NSDictionary *sound in self.savedSounds){
		NSString *when = TGNotificationWhen(sound[@"date"]);
		NSString *detail = [NSString stringWithFormat:@"%ld s%@%@",
				(long)[sound[@"duration"] integerValue],
				when.length ? @" · " : @"", when];
		[rows addObject:TGTapRow(TGSoundName(sound), detail, ^{
			[weakSelf showSavedSound:sound];
		})];
	}
	if (!rows.count){
		NSString *empty = self.savedSoundsLoaded
				? @"No custom sounds yet. Telegram plays the default one."
				: @"Reading Telegram's sound list...";
		[rows addObject:TGRow(TGKindPlain, empty)];
	}

	NSArray *addRows = @[
		TGActionRow(@"Add Bundled Sample", ^{ [weakSelf addSoundFromBundle]; }),
		TGActionRow(@"Add MP3 from Documents", ^{ [weakSelf addSoundFromDocuments]; }),
	];

	return @[
		TGSection(@"Saved Sounds",
				  @"A sound here is usable as the notification sound of a chat "
				  @"or a scope. Tap one for what Telegram answered.",
				  rows),
		TGSection(@"Add a Sound",
				  @"Telegram stores notification sounds as MP3. iTunes file "
				  @"sharing puts files into this app's Documents folder.",
				  addRows),
	];
}

- (void)addSoundFromBundle {
	NSString *path = [[NSBundle mainBundle] pathForResource:@"notification-sample"
													 ofType:@"mp3"];
	if (!path.length){
		[TGAlertSheet showMessage:@"This build has no bundled sample sound."
							 title:@"Custom Sounds" inView:self.view];
		return;
	}
	[self addSavedSoundAtPath:path];
}

/// The only picker this OS gives a sandboxed app is its own Documents folder,
/// which iTunes file sharing exposes. MP3 only, because that is the format
/// addSavedNotificationSound accepts.
- (void)addSoundFromDocuments {
	NSString *documents = [NSSearchPathForDirectoriesInDomains(
			NSDocumentDirectory, NSUserDomainMask, YES) firstObject];
	NSArray *entries = [[NSFileManager defaultManager]
			contentsOfDirectoryAtPath:documents error:nil];
	NSMutableArray *names = [NSMutableArray array];
	for (NSString *entry in entries){
		if (![[entry pathExtension].lowercaseString isEqualToString:@"mp3"])
			continue;
		[names addObject:entry];
	}
	if (!names.count){
		[TGAlertSheet showMessage:@"No MP3 in Documents. Drop one there over "
								  @"iTunes file sharing, then try again."
							 title:@"Custom Sounds" inView:self.view];
		return;
	}
	__weak typeof(self) weakSelf = self;
	if (names.count == 1){
		[self addSavedSoundAtPath:[documents stringByAppendingPathComponent:names[0]]];
		return;
	}
	[TGAlertSheet showChoices:names
						title:@"Add a Sound"
			 destructiveIndex:-1
					   inView:self.view
					 onChoice:^(NSInteger index){
		if (index < 0 || index >= (NSInteger)names.count)
			return;
		[weakSelf addSavedSoundAtPath:
				[documents stringByAppendingPathComponent:names[(NSUInteger)index]]];
	}];
}

- (void)addSavedSoundAtPath:(NSString *)path {
	__weak typeof(self) weakSelf = self;
	[[TGClient shared] addSavedNotificationSoundAtPath:path
											completion:^(NSDictionary *sound,
														 NSString *error){
		if (error || !sound){
			[TGAlertSheet showMessage:(error ?: @"Telegram did not save that sound.")
								 title:@"Custom Sounds" inView:weakSelf.view];
			return;
		}
		[TGAlertSheet showMessage:[NSString stringWithFormat:
				@"Added \"%@\". It is at the top of the list.", TGSoundName(sound)]
							 title:@"Custom Sounds" inView:weakSelf.view];
		[weakSelf loadForPage];
	}];
}

- (void)showSavedSound:(NSDictionary *)sound {
	__weak typeof(self) weakSelf = self;
	NSString *name = TGSoundName(sound);
	[TGAlertSheet showChoices:@[@"Sound Details", @"Remove Sound"]
						title:name
			 destructiveIndex:1
					   inView:self.view
					 onChoice:^(NSInteger index){
		if (index == 1){
			[weakSelf removeSavedSound:sound];
			return;
		}
		[[TGClient shared] savedNotificationSound:[sound[@"id"] longLongValue]
									   completion:^(NSDictionary *fresh){
			if (!fresh){
				[TGAlertSheet showMessage:@"Telegram no longer has that sound."
									 title:@"Sound Details" inView:weakSelf.view];
				[weakSelf loadForPage];
				return;
			}
			NSString *when = TGNotificationWhen(fresh[@"date"]);
			NSMutableString *detail = [NSMutableString stringWithFormat:
					@"%@\n%ld seconds\n%@\nStored file %@, %@",
					TGSoundName(fresh),
					(long)[fresh[@"duration"] integerValue],
					when.length ? when : @"No date",
					fresh[@"fileId"] ?: @(0),
					TGBytes([fresh[@"size"] longLongValue])];
			if ([fresh[@"data"] length])
				[detail appendFormat:@"\n%@", fresh[@"data"]];
			[TGAlertSheet showMessage:detail title:@"Sound Details"
									inView:weakSelf.view];
		}];
	}];
}

- (void)removeSavedSound:(NSDictionary *)sound {
	__weak typeof(self) weakSelf = self;
	NSString *name = TGSoundName(sound);
	[TGAlertSheet showConfirm:@"Telegram forgets this sound for every device. "
							  @"Chats that choose it fall back to the default."
						title:name
					   action:@"Remove"
				 destructive:YES
					   inView:self.view
					onConfirm:^{
		[[TGClient shared] removeSavedNotificationSound:[sound[@"id"] longLongValue]
										   completion:^(BOOL ok, NSString *error){
			if (!ok){
				[TGAlertSheet showMessage:(error ?: @"Telegram refused that.")
									 title:@"Custom Sounds" inView:weakSelf.view];
				return;
			}
			[TGAlertSheet showMessage:@"Sound removed."
								 title:@"Custom Sounds" inView:weakSelf.view];
			[weakSelf loadForPage];
		}];
	}];
}

- (NSArray *)activeNotificationSections {
	NSArray *groups = [TGClient shared].activeNotificationGroups;
	if (!groups.count){
		return @[TGSection(nil,
				@"TDLib has no local notifications right now. iOS draws the "
				@"banners through APNs; this page shows the copy TDLib keeps "
				@"while the app is running.",
				@[TGRow(TGKindPlain, @"No active notifications")])];
	}

	__weak typeof(self) weakSelf = self;
	NSMutableArray *sections = [NSMutableArray array];
	for (NSDictionary *group in groups){
		NSMutableArray *rows = [NSMutableArray array];
		for (NSDictionary *notification in group[@"notifications"]){
			NSString *when = TGNotificationWhen(notification[@"date"]);
			NSString *silent = [notification[@"isSilent"] boolValue]
					? @" · Silent" : @"";
			NSString *detail = [NSString stringWithFormat:@"%@%@",
					when.length ? when : @"No date", silent];
			[rows addObject:TGTapRow(notification[@"text"] ?: @"Notification",
					detail, ^{
				[weakSelf removeNotificationRow:notification inGroup:group];
			})];
		}
		if (!rows.count)
			[rows addObject:TGRow(TGKindPlain, @"No notifications in this group")];
		[rows addObject:TGRedRow(@"Remove This Group", ^{
			[weakSelf removeNotificationGroup:group];
		})];

		NSString *chat = group[@"chatTitle"];
		NSString *header = chat.length ? chat
				: [NSString stringWithFormat:@"Group %@", group[@"id"] ?: @(0)];
		NSString *footer = [NSString stringWithFormat:@"%ld active · %@",
				(long)[group[@"totalCount"] integerValue],
				TGNotificationGroupLabel(group[@"type"])];
		[sections addObject:TGSection(header, footer, rows)];
	}
	return sections;
}

- (void)removeNotificationRow:(NSDictionary *)notification
					  inGroup:(NSDictionary *)group {
	__weak typeof(self) weakSelf = self;
	[TGAlertSheet showConfirm:@"TDLib stops counting this notification."
						title:notification[@"text"] ?: @"Notification"
					   action:@"Remove"
				 destructive:YES
					   inView:self.view
					onConfirm:^{
		[[TGClient shared] removeNotification:[notification[@"id"] intValue]
									  inGroup:[group[@"id"] intValue]
								   completion:^(BOOL ok, NSString *error){
			if (!ok){
				[TGAlertSheet showMessage:(error ?: @"Telegram refused that.")
									 title:@"Active Notifications"
									inView:weakSelf.view];
				return;
			}
			[weakSelf rebuild];
		}];
	}];
}

- (void)removeNotificationGroup:(NSDictionary *)group {
	int32_t maxId = 0;
	for (NSDictionary *notification in group[@"notifications"])
		maxId = MAX(maxId, [notification[@"id"] intValue]);
	__weak typeof(self) weakSelf = self;
	[TGAlertSheet showConfirm:@"Every notification in this group is removed "
							  @"from TDLib's local list."
						title:group[@"chatTitle"] ?: @"Notification Group"
					   action:@"Remove"
				 destructive:YES
					   inView:self.view
					onConfirm:^{
		[[TGClient shared] removeNotificationGroup:[group[@"id"] intValue]
								maxNotificationId:maxId
									   completion:^(BOOL ok, NSString *error){
			if (!ok){
				[TGAlertSheet showMessage:(error ?: @"Telegram refused that.")
									 title:@"Active Notifications"
									inView:weakSelf.view];
				return;
			}
			[weakSelf rebuild];
		}];
	}];
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

		TGSection(@"Account Status",
				  @"Telegram's own record for this account: a freeze, the "
				  @"subscription it holds, the age gate its country sets, and "
				  @"any reCAPTCHA it asks for before a request goes through. "
				  @"These are pushed by the server, not fetched here.",
				  @[
			TGTapRow(@"Freeze State",
					TGFreezeDetail([TGClient shared].freezeState), ^{
				[weakSelf showFreezeState];
			}),
			TGTapRow(@"Subscription",
					TGSubscriptionDetail([[TGClient shared]
							subscriptionForUserId:
									[[TGClient shared].me[@"id"] longLongValue]]), ^{
				[weakSelf showSubscriptionState];
			}),
			TGTapRow(@"Age Verification",
					TGAgeVerificationDetail([TGClient shared].ageVerificationParameters),
					^{
				[weakSelf showAgeVerificationState];
			}),
			TGTapRow(@"reCAPTCHA Verification",
					[TGClient shared].recaptchaVerificationRequest ? @"Requested" : @"None",
					^{
				[weakSelf showRecaptchaVerification];
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
			TGTapRow(@"Orders and Payment Data", nil, ^{
				[weakSelf openPage:TGSettingsPagePaymentData];
			}),
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


/// The freeze record is four fields and a date each. The row says whether it
/// is on; the sheet says until when and where the appeal goes, and offers the
/// link the update named rather than only printing it.
- (void)showFreezeState {
	NSDictionary *state = [TGClient shared].freezeState;
	if (![state isKindOfClass:NSDictionary.class]){
		[TGAlertSheet showMessage:@"Telegram has not sent a freeze record for this account."
							title:@"Freeze State" inView:self.view];
		return;
	}
	NSString *appeal = state[@"appeal_link"];
	NSString *details = [NSString stringWithFormat:
			@"%@\nFreezing date: %@\nDeletion date: %@\nAppeal link: %@",
			TGFreezeDetail(state),
			TGStatusDateText(state[@"freezing_date"]),
			TGStatusDateText(state[@"deletion_date"]),
			appeal.length ? appeal : @"none"];
	__weak typeof(self) weakSelf = self;
	if (!appeal.length){
		[TGAlertSheet showMessage:details title:@"Freeze State" inView:self.view];
		return;
	}
	[TGAlertSheet showChoices:@[@"Open Appeal Link"]
						title:@"Freeze State"
					  message:details
			 destructiveIndex:-1
					   inView:self.view
					 onChoice:^(NSInteger index){
		[weakSelf openURL:appeal];
	}];
}

- (void)showSubscriptionState {
	NSDictionary *record = [[TGClient shared] subscriptionForUserId:
			[[TGClient shared].me[@"id"] longLongValue]];
	if (![record isKindOfClass:NSDictionary.class]){
		[TGAlertSheet showMessage:@"Telegram has not sent a subscription record for this account."
							title:@"Subscription" inView:self.view];
		return;
	}
	NSString *payload = record[@"payload"];
	NSString *details = [NSString stringWithFormat:
			@"%@\nCanceled: %@\nRestored: %@\nPayment failed: %@\nPayload: %@",
			TGSubscriptionDetail(record),
			[record[@"is_canceled"] boolValue] ? @"yes" : @"no",
			[record[@"is_restored"] boolValue] ? @"yes" : @"no",
			[record[@"is_payment_failed"] boolValue] ? @"yes" : @"no",
			payload.length ? payload : @"none"];
	[TGAlertSheet showMessage:details title:@"Subscription" inView:self.view];
}

/// The age gate names the country and the bot that answers it. Opening the
/// bot is the action the protocol names; there is no td_api call that solves
/// it on the app's behalf.
- (void)showAgeVerificationState {
	NSDictionary *parameters = [TGClient shared].ageVerificationParameters;
	if (![parameters isKindOfClass:NSDictionary.class]){
		[TGAlertSheet showMessage:@"Telegram has not sent age verification parameters."
							title:@"Age Verification" inView:self.view];
		return;
	}
	NSString *bot = parameters[@"verification_bot_username"];
	NSString *country = parameters[@"country"];
	NSString *details = [NSString stringWithFormat:
			@"%@\nVerification bot: %@\nCountry: %@",
			TGAgeVerificationDetail(parameters),
			bot.length ? [@"@" stringByAppendingString:bot] : @"none",
			country.length ? country : @"not named"];
	__weak typeof(self) weakSelf = self;
	if (!bot.length){
		[TGAlertSheet showMessage:details title:@"Age Verification" inView:self.view];
		return;
	}
	[TGAlertSheet showChoices:@[[NSString stringWithFormat:@"Open @%@", bot]]
						title:@"Age Verification"
					  message:details
			 destructiveIndex:-1
					   inView:self.view
					 onChoice:^(NSInteger index){
		[weakSelf openURL:[NSString stringWithFormat:@"https://t.me/%@", bot]];
	}];
}

/// A reCAPTCHA cannot be drawn by this client: there is no web view in the
/// app and no td_api call that answers one. The sheet shows the exact request
/// (action, site key, verification id) and can copy the key for an official
/// client, instead of pretending the request was handled.
- (void)showRecaptchaVerification {
	NSDictionary *request = [TGClient shared].recaptchaVerificationRequest;
	if (![request isKindOfClass:NSDictionary.class]){
		[TGAlertSheet showMessage:@"Telegram is not asking for a reCAPTCHA."
							title:@"reCAPTCHA Verification" inView:self.view];
		return;
	}
	NSString *action = request[@"action"];
	NSString *key = request[@"recaptcha_key_id"];
	NSString *details = [NSString stringWithFormat:
			@"Verification id: %lld\nAction: %@\nreCAPTCHA key: %@\n\n"
			@"This client has no web view to solve it. Finish the check in an "
			@"official client; the key above is what the server named.",
			(long long)[request[@"verification_id"] longLongValue],
			action.length ? action : @"not named",
			key.length ? key : @"not named"];
	__weak typeof(self) weakSelf = self;
	if (!key.length){
		[TGAlertSheet showMessage:details title:@"reCAPTCHA Verification" inView:self.view];
		return;
	}
	[TGAlertSheet showChoices:@[@"Copy reCAPTCHA Key"]
						title:@"reCAPTCHA Verification"
					  message:details
			 destructiveIndex:-1
					   inView:self.view
					 onChoice:^(NSInteger index){
		[UIPasteboard generalPasteboard].string = key;
		[weakSelf toast:@"reCAPTCHA key copied."];
	}];
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
