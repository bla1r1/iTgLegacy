//
// TGClient+Accounts.h - several accounts on one device, one TDLib client at a
// time. Each account owns a slot whose TDLib database lives in its own
// directory, so nothing one account holds is ever read from or written to
// another's. Only the active account runs, so a second account costs disk,
// not memory.
//
#import "TGClient+Base.h"

/// The TDLib database directory for `slot`, under `documents`. Slot 0 keeps
/// the pre-accounts path `Documents/tdlib`; slot N > 0 is `Documents/tdlib-N`.
/// A plain C function so the sendTdlibParameters half of TGClient.m can build
/// the path without routing through the category.
FOUNDATION_EXPORT NSString *TGAccountDatabaseDirectory(NSString *documents, NSInteger slot);

/// A per-account NSUserDefaults key: `base` for slot 0 (an update keeps the
/// name it always had) and `base-N` for slot N > 0, so one account's saved
/// value is never read as another's. Device-wide prefs (theme, ghost mode,
/// power saving, language) do not go through here.
FOUNDATION_EXPORT NSString *TGAccountDefaultsKey(NSString *base);

@interface TGClient (Accounts)

/// The slot whose TDLib database is in use. Defaults to 0, the pre-accounts
/// session.
+ (NSInteger)activeAccountSlot;

/// The known accounts in slot order. Each entry is @{@"slot", @"title",
/// @"phone"}; title and phone stay empty until that account's getMe answers.
+ (NSArray *)accountSlots;

/// Adds a new account in the next free slot (0, 1 or 2) and returns that
/// slot, or -1 when all three are taken. The new slot is not made active.
+ (NSInteger)addAccount;

/// Makes `slot` the running account: pauses (closing TDLib safely), then sets
/// the active slot, clears the per-account state and resumes, so the next
/// client asks for parameters again with the new slot's directory.
- (void)switchToAccountSlot:(NSInteger)slot;

/// Clears every in-memory value that belongs to one account - chats, users,
/// folders, unread totals, me, the auth state, pending requests, the outbox
/// and the rest - so the account that resumes starts clean.
- (void)resetStateForAccountSwitch;

/// Records the active account's title and phone in accountSlots. Called when
/// TDLib answers getMe, which is the first moment both are known.
- (void)recordActiveAccountFromMe:(NSDictionary *)me;

@end
