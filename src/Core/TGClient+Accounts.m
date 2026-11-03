//
// TGClient+Accounts.m
//
#import "TGClient+Accounts.h"
#import "TGClientInternal.h"
#import "TGOptions.h"

NSString *const TGAccountDidSwitchNotification = @"TGAccountDidSwitchNotification";

/// The defaults key the slot list is stored under.
static NSString *const TGAccountSlotsKey = @"TGAccountSlots";
/// The defaults key the active slot is stored under. Absent reads as 0, which
/// is the pre-accounts session an existing install already has.
static NSString *const TGActiveAccountSlotKey = @"TGActiveAccountSlot";
/// Telegram's own ceiling: three accounts, slots 0, 1 and 2.
static const NSInteger TGAccountSlotMax = 3;

/// The private setter TGClient+Auth owns; resetting an account clears the
/// push identity the old account registered.
@interface TGClient (AuthPrivate)
- (void)setPushReceiverId:(int64_t)receiverId;
@end

static void TGStoreAccountSlots(NSArray *slots) {
	[[NSUserDefaults standardUserDefaults] setObject:slots forKey:TGAccountSlotsKey];
	[[NSUserDefaults standardUserDefaults] synchronize];
}

NSString *TGAccountDatabaseDirectory(NSString *documents, NSInteger slot) {
	if (slot <= 0)
		return [documents stringByAppendingPathComponent:@"tdlib"];
	return [documents stringByAppendingPathComponent:
			[NSString stringWithFormat:@"tdlib-%ld", (long)slot]];
}

NSString *TGAccountDefaultsKey(NSString *base) {
	NSInteger slot = [TGClient activeAccountSlot];
	if (slot <= 0)
		return base;
	return [base stringByAppendingFormat:@"-%ld", (long)slot];
}

@implementation TGClient (Accounts)

+ (NSInteger)activeAccountSlot {
	NSInteger slot = [[NSUserDefaults standardUserDefaults]
			integerForKey:TGActiveAccountSlotKey];
	if (slot < 0 || slot >= TGAccountSlotMax)
		return 0;
	return slot;
}

+ (NSArray *)accountSlots {
	NSArray *raw = [[NSUserDefaults standardUserDefaults]
			arrayForKey:TGAccountSlotsKey];
	if (![raw isKindOfClass:NSArray.class])
		return @[];
	NSMutableArray *out = [NSMutableArray arrayWithCapacity:raw.count];
	for (id entry in raw){
		if (![entry isKindOfClass:NSDictionary.class])
			continue;
		NSNumber *slot = entry[@"slot"];
		if (![slot isKindOfClass:NSNumber.class])
			continue;
		NSString *title = [entry[@"title"] isKindOfClass:NSString.class]
				? entry[@"title"] : @"";
		NSString *phone = [entry[@"phone"] isKindOfClass:NSString.class]
				? entry[@"phone"] : @"";
		[out addObject:@{@"slot" : slot, @"title" : title, @"phone" : phone}];
	}
	return out;
}

+ (NSInteger)addAccount {
	NSArray *existing = [self accountSlots];
	NSInteger active = [self activeAccountSlot];

	// The active slot is the running account, whether or not the stored list
	// has named it yet: an install that signed out of slot 0 keeps an empty
	// list, and the next free slot must never be the one TDLib already uses.
	BOOL used[3] = { NO, NO, NO };
	if (active >= 0 && active < TGAccountSlotMax)
		used[active] = YES;
	BOOL activeListed = NO;
	for (NSDictionary *entry in existing){
		NSInteger s = [entry[@"slot"] integerValue];
		if (s >= 0 && s < TGAccountSlotMax){
			used[s] = YES;
			if (s == active)
				activeListed = YES;
		}
	}
	NSInteger next = 0;
	while (next < TGAccountSlotMax && used[next])
		next++;
	if (next >= TGAccountSlotMax)
		return -1;

	NSMutableArray *slots = [existing mutableCopy];
	// The active slot is being signed into but the list does not name it yet;
	// store it too, so the account that signs in there survives the switch
	// away from it.
	if (!activeListed)
		[slots addObject:@{@"slot" : @(active), @"title" : @"", @"phone" : @""}];
	[slots addObject:@{@"slot" : @(next), @"title" : @"", @"phone" : @""}];
	TGStoreAccountSlots(slots);
	return next;
}

- (void)recordActiveAccountFromMe:(NSDictionary *)me {
	if (![me isKindOfClass:NSDictionary.class])
		return;
	NSInteger slot = [TGClient activeAccountSlot];
	NSString *firstName = [me[@"first_name"] isKindOfClass:NSString.class]
			? me[@"first_name"] : @"";
	NSString *username = [me[@"username"] isKindOfClass:NSString.class]
			? me[@"username"] : @"";
	NSString *phone = [me[@"phone"] isKindOfClass:NSString.class]
			? me[@"phone"] : @"";
	// The name the switcher shows, falling back to what the record carries
	// while Telegram has not sent a name yet.
	NSString *title = firstName.length ? firstName
			: (username.length ? username : phone);

	NSArray *existing = [TGClient accountSlots];
	NSMutableArray *slots = [NSMutableArray arrayWithCapacity:existing.count + 1];
	BOOL found = NO;
	for (NSDictionary *entry in existing){
		NSMutableDictionary *row = [entry mutableCopy];
		if ([row[@"slot"] integerValue] == slot){
			row[@"title"] = title ?: @"";
			row[@"phone"] = phone ?: @"";
			found = YES;
		}
		[slots addObject:row];
	}
	if (!found)
		[slots addObject:@{@"slot" : @(slot), @"title" : title ?: @"",
						   @"phone" : phone ?: @""}];
	TGStoreAccountSlots(slots);
}

- (void)switchToAccountSlot:(NSInteger)slot {
	if (slot < 0 || slot >= TGAccountSlotMax)
		return;
	if (slot == [TGClient activeAccountSlot])
		return;
	// A switch while TDLib is still closing must not move the active slot:
	// pauseForBackground runs its completion at once when pausing is already
	// YES, and the slot would move while the old database is still closing.
	if (self.pausing)
		return;

	// pauseForBackground closes TDLib safely and its completion runs on the
	// main queue once the client is gone - the only window where the active
	// slot may move, because a running client has already opened a database.
	[self pauseForBackground:^{
		[[NSUserDefaults standardUserDefaults] setInteger:slot
												  forKey:TGActiveAccountSlotKey];
		[[NSUserDefaults standardUserDefaults] synchronize];
		[self resetStateForAccountSwitch];
		[[NSNotificationCenter defaultCenter]
				postNotificationName:TGAccountDidSwitchNotification object:self];
		[self resumeFromBackground];
	}];
}

- (void)resetStateForAccountSwitch {
	// Identity and the half-finished sign-in steps.
	self.me = nil;
	self.authState = TGAuthStateUnknown;
	self.pendingPhoneNumber = nil;
	self.codeInfo = nil;
	self.loginPasswordInfo = nil;
	self.emailCodeInfo = nil;
	self.qrCodeLink = nil;
	self.registrationTermsText = nil;
	[self noteApplicationVerificationWithId:0 nonce:@""];
	[self setPushReceiverId:0];

	// Chat and user caches.
	[self.chatsById removeAllObjects];
	[self.usersById removeAllObjects];
	[self.rawUsersById removeAllObjects];
	[self.userPhotosById removeAllObjects];
	[self.forumSupergroups removeAllObjects];
	[self.savedTopicsById removeAllObjects];
	self.archivedChats = @[];
	self.folders = @[];
	self.chats = @[];
	self.chatListComplete = NO;
	self.loadChatsAttempts = 0;
	self.chatsAtLastLoad = 0;
	self.chatsNeedRebuild = NO;
	self.batchingUpdates = NO;

	// Account facts the settings and profile pages read from the client.
	self.accentColorIds = @[];
	self.profileAccentColorIds = @[];
	self.accentColors = @[];
	self.profileAccentColors = @[];
	self.contactCloseBirthdays = @[];
	self.freezeStateValue = nil;
	self.ageVerificationParametersValue = nil;
	self.recaptchaVerificationRequestValue = nil;
	[self.userSubscriptionsById removeAllObjects];
	self.reactionMessageEffectIds = @[];
	self.stickerMessageEffectIds = @[];
	self.defaultBackgroundValue = nil;
	self.emojiChatThemesValue = @[];
	self.stoppedMessageDraftValue = nil;
	self.publishedVideoValue = nil;
	for (NSNumber *pending in [self.noteSendWaiters allKeys])
		[self noteSendFinished:pending.longLongValue sent:NO];
	self.storyMainListChatCount = 0;
	self.storyArchiveListChatCount = 0;
	self.storyStealthModeValue = nil;
	self.ownedStarCountValue = 0;
	[self.chatRevenueAmountByChat removeAllObjects];
	[self.starRevenueStatusByOwner removeAllObjects];
	self.reactionDefaultEmoji = nil;
	self.reactionNotificationSettingsValue = nil;
	self.gifSearchProvider = nil;
	self.gifSearchEmojis = @[];
	self.archiveSettings = nil;

	// Tier 2, notifications and the misc caches.
	self.textCompositionStylesValue = @[];
	[self.directMessagesTopicsByChat removeAllObjects];
	self.stakeDiceStateValue = nil;
	self.activeNotificationGroupRows = @[];
	self.activeNotificationGroupsValue = @[];
	self.haveDelayedNotifications = NO;
	self.haveUnreceivedNotifications = NO;
	[self.autosaveSettingsByScope removeAllObjects];
	self.languagePackStringsByPack = nil;
	[self.communitiesById removeAllObjects];
	[self.communityOrder removeAllObjects];
	[self.communityFullInfoById removeAllObjects];
	[self.quickReplyShortcutsById removeAllObjects];
	[self.quickReplyShortcutOrder removeAllObjects];
	[self.quickReplyMessagesByShortcut removeAllObjects];
	self.suggestedActionsValue = @[];
	[self.checklistCache removeAllObjects];

	// Connection, requests and the outbox.
	self.connectionState = TGConnectionStateUnknown;
	[self.pendingRequests removeAllObjects];
	self.requestSeq = 0;
	[self.outboxLock lock];
	[self.outbox removeAllObjects];
	[self.outboxLock unlock];
	[self.updateCoalescer reset];
	[self removeAllFileWaiters];

	// Server options (updateOption) are account-scoped too; the next account
	// re-fetches them and a stale value would otherwise be read as its own.
	TGOptionReset();

	// The stores and players that hold this account's ids are the app's to
	// reset, on TGAccountDidSwitchNotification.
	[self resetGroupCallState];
	[self removeAllPendingGenerations];
}

@end
