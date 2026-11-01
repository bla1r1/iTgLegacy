//
// TGClient+Usernames.h - the account's usernames, a supergroup's username
// and the switches on the group profile that change what the group is.
//
// The two halves share a shape TDLib names usernames: active, disabled and
// one editable name. An account and a supergroup take the same three requests
// with different ids, so the screens that draw them are cousins too.
//
#import "TGClient+Base.h"

@interface TGClient (Usernames)

#pragma mark - the account

/// The signed-in account's usernames object from getMe: "active_usernames",
/// "disabled_usernames" and "editable_username". Nil when Telegram refuses.
- (void)accountUsernamesWithCompletion:(void (^)(NSDictionary *usernames))completion;

/// Turns one of the account's names on or off. The editable name cannot be
/// switched off, and Telegram says so in `error`.
- (void)toggleUsernameIsActive:(NSString *)username
					  isActive:(BOOL)isActive
					completion:(void (^)(BOOL ok, NSString *error))completion;

/// The order of the active names as they are shown on the profile. Every
/// currently active name has to be in `usernames`.
- (void)reorderActiveUsernames:(NSArray *)usernames
					completion:(void (^)(BOOL ok, NSString *error))completion;

#pragma mark - a supergroup or channel

/// One read of everything the group settings screen draws: the username
/// object, the mode switches from getSupergroup and the two facts that only
/// live in full info (hidden members and the main profile tab). Nil when the
/// chat is not a supergroup or Telegram refuses.
- (void)supergroupSettingsForChat:(int64_t)chatId
						completion:(void (^)(NSDictionary *settings))completion;

/// The editable username of a supergroup or channel. An empty string removes
/// it; the active names Telegram keeps are left alone.
- (void)setSupergroupUsername:(NSString *)username
					   inChat:(int64_t)chatId
				   completion:(void (^)(BOOL ok, NSString *error))completion;

- (void)toggleSupergroupUsernameIsActive:(NSString *)username
								  inChat:(int64_t)chatId
								isActive:(BOOL)isActive
							  completion:(void (^)(BOOL ok, NSString *error))completion;

- (void)reorderSupergroupActiveUsernames:(NSArray *)usernames
								  inChat:(int64_t)chatId
							  completion:(void (^)(BOOL ok, NSString *error))completion;

/// Switches off every active name but the editable one.
- (void)disableAllSupergroupUsernamesInChat:(int64_t)chatId
								 completion:(void (^)(BOOL ok, NSString *error))completion;

/// Forum mode. Turning it off also clears the tabs, which TDLib ignores while
/// is_forum is false. Discussion groups cannot be converted and answer an error.
- (void)setSupergroupForumInChat:(int64_t)chatId
							  on:(BOOL)on
					  completion:(void (^)(BOOL ok, NSString *error))completion;

/// New members need an administrator's approval. `apply_to_invite_links` is
/// sent as YES so the switch means the same thing for existing links.
/// `guardBotUserId` is the bot already guarding the group, or 0; sending 0
/// would quietly remove one that was there.
- (void)setSupergroupJoinByRequestInChat:(int64_t)chatId
									 on:(BOOL)on
						   guardBotUserId:(int64_t)guardBotUserId
							 completion:(void (^)(BOOL ok, NSString *error))completion;

/// Non-administrators stop being able to list members. Only a group whose
/// full info says can_hide_members accepts it.
- (void)setSupergroupHiddenMembersInChat:(int64_t)chatId
									 on:(BOOL)on
							 completion:(void (^)(BOOL ok, NSString *error))completion;

/// Converts the group to a broadcast group: members read, administrators post.
/// TDLib has no inverse, so the row asks before sending it.
- (void)convertSupergroupToBroadcastInChat:(int64_t)chatId
								completion:(void (^)(BOOL ok, NSString *error))completion;

/// The channel's automatic translation switch. A boost level can be required,
/// and Telegram's refusal carries that reason in `error`.
- (void)setSupergroupAutomaticTranslationInChat:(int64_t)chatId
											 on:(BOOL)on
									 completion:(void (^)(BOOL ok, NSString *error))completion;

/// The first tab a channel profile opens on. `tab` is "posts", "media",
/// "files", "links", "music", "voice" or "gifs".
- (void)setSupergroupMainProfileTab:(NSString *)tab
							 inChat:(int64_t)chatId
						 completion:(void (^)(BOOL ok, NSString *error))completion;

#pragma mark - default administrator rights

/// One of the presets the default-rights page offers: "readonly", "standard",
/// "posting" or "full". The whole chatAdministratorRights object is built,
/// because TDLib has no default for its booleans.
+ (NSDictionary *)administratorRightsForPreset:(NSString *)preset;

/// Telegram keeps one default set for groups and one for channels, and applies
/// it when this bot is added as an administrator. Both are bot-only requests;
/// a user account gets the server's refusal, which the screen shows.
- (void)setDefaultGroupAdministratorRightsPreset:(NSString *)preset
									  completion:(void (^)(BOOL ok, NSString *error))completion;

- (void)setDefaultChannelAdministratorRightsPreset:(NSString *)preset
										completion:(void (^)(BOOL ok, NSString *error))completion;

@end
