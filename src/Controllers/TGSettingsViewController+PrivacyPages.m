//
// TGSettingsViewController+PrivacyPages.m
// Settings pages for notifications, privacy, security, and blocked users.
//
#import "TGSettingsViewControllerInternal.h"
#import "TGAlertSheet.h"
#import "TGSessionsViewController.h"

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

	return @[
		TGSection(@"Show notifications for", nil, show),
		TGSection(@"Message previews",
				  @"With previews off a notification says who wrote, not what "
				  @"they wrote.", preview),
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

	return @[
		TGSection(@"Security", nil, @[
			TGTapRow(@"Two-Step Verification", passwordDetail, ^{
				[weakSelf showTwoStepState];
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

		TGSection(@"Who can see", nil, rules),

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

@end
