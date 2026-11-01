//
// TGClient+Groups.h - the client surface for basic groups, supergroups and their invite links.
//
#import "TGClient+Base.h"

/// A chatMemberStatus dictionary as the one word a row shows:
/// "owner", "admin", "restricted", "banned", "left" or "member".
FOUNDATION_EXPORT NSString *TGMemberStatusName(NSDictionary *status);

@interface TGClient (Groups)

/// What three supergroup switches sit on right now, so a row can name the
/// flip rather than the state. NO/NO/NO/NO when the chat is not a supergroup.
- (void)supergroupFlagsForChat:(int64_t)chatId
					completion:(void (^)(BOOL signMessages, BOOL joinToSend,
										 BOOL allHistory, BOOL ok))completion;

- (void)setChatSignMessages:(int64_t)chatId
						 on:(BOOL)on
				 completion:(void (^)(BOOL ok))completion;

- (void)setChatJoinToSendMessages:(int64_t)chatId
							   on:(BOOL)on
					   completion:(void (^)(BOOL ok))completion;

/// Whether new members see the history before they joined. A supergroup or a
/// channel only, and an administrator's switch.
- (void)setSupergroupAllHistoryAvailable:(int64_t)chatId
									  on:(BOOL)on
							  completion:(void (^)(BOOL ok))completion;

/// Join or leave a channel or supergroup.
- (void)setChat:(int64_t)chatId joined:(BOOL)joined;

/// Pin or unpin a chat in the main list.
- (void)setChat:(int64_t)chatId pinned:(BOOL)pinned;

/// Mute forever, or unmute.
- (void)setChat:(int64_t)chatId muted:(BOOL)muted;

/// Messages in this chat delete themselves after `seconds`; 0 turns it off.
- (void)setChat:(int64_t)chatId autoDeleteSeconds:(NSInteger)seconds;

/// Move a chat into the archive, or back out of it.
- (void)setChat:(int64_t)chatId archived:(BOOL)archived;

/// The blue dot you put there yourself; it survives until the chat is opened.
- (void)setChat:(int64_t)chatId markedUnread:(BOOL)unread;

/// Makes a basic group - their New Group - holding `userIds`. TDLib refuses
/// an empty one, so at least one other person is required. The completion
/// gets the new chat's id, and the ids of anyone whose privacy settings
/// refused the invitation.
- (void)createGroupNamed:(NSString *)title
			   withUsers:(NSArray *)userIds
			  completion:(void (^)(int64_t chatId, NSArray *failedUserIds))completion;

/// A supergroup, or a channel with `isChannel`.
- (void)createSupergroupNamed:(NSString *)title
				  description:(NSString *)description
					isChannel:(BOOL)isChannel
				   completion:(void (^)(int64_t chatId))completion;

/// Past 200 members, or for a username or admins with rights, a basic group
/// has to become a supergroup. The chat id changes, hence the answer.
- (void)upgradeGroupToSupergroup:(int64_t)chatId
					  completion:(void (^)(int64_t newChatId))completion;

- (void)addUser:(int64_t)userId
		 toChat:(int64_t)chatId
	 completion:(void (^)(BOOL ok, NSArray *failedUserIds))completion;

/// The picker's batch, in one request. Same failed-half answer.
- (void)addUsers:(NSArray *)userIds
		  toChat:(int64_t)chatId
	  completion:(void (^)(BOOL ok, NSArray *refused))completion;

/// One member's own record; nil when there is no such member.
- (void)chatMember:(int64_t)userId
			 inChat:(int64_t)chatId
		completion:(void (^)(NSDictionary *member))completion;

/// What members may do, as a preset word: "all", "text" or "read". The
/// fifteen booleans TDLib keeps are built from it.
+ (NSDictionary *)chatPermissionsForPreset:(NSString *)preset;

- (void)setChatPermissionsFromPreset:(NSString *)preset
							   inChat:(int64_t)chatId
						  completion:(void (^)(BOOL ok))completion;

/// Handing a chat over, with the password two-factor asks for. Final.
- (void)transferOwnershipOfChat:(int64_t)chatId
						 toUser:(int64_t)userId
					   password:(NSString *)password
					 completion:(void (^)(BOOL ok))completion;

/// Members of a chat, filtered by `query`; an empty query is the whole list.
/// Entries carry "id", "name" and "status" (owner/admin/member/...).
- (void)searchMembersInChat:(int64_t)chatId
					  query:(NSString *)query
				 completion:(void (^)(NSArray *members))completion;

/// Only the administrators - a different request, and the only one that says
/// who the owner is. Entries carry "id", "name", "owner" and "editable".
- (void)administratorsOfChat:(int64_t)chatId
				  completion:(void (^)(NSArray *admins))completion;

/// "administrator", "member" or "left". Anything else is refused rather than
/// guessed at, because the wrong word here removes people.
- (void)setMember:(int64_t)userId
		   inChat:(int64_t)chatId
		   status:(NSString *)status
	   completion:(void (^)(BOOL ok))completion;

/// Not the same as removing: a banned member cannot return on a link.
- (void)banMember:(int64_t)userId
		   inChat:(int64_t)chatId
   revokeMessages:(BOOL)revokeMessages
	   completion:(void (^)(BOOL ok))completion;

- (void)setChat:(int64_t)chatId title:(NSString *)title
	 completion:(void (^)(BOOL ok))completion;

/// A supergroup or channel only; a basic group has nowhere to put one.
- (void)setChat:(int64_t)chatId description:(NSString *)description
	 completion:(void (^)(BOOL ok))completion;

- (void)setChat:(int64_t)chatId photoAtPath:(NSString *)path
	 completion:(void (^)(BOOL ok))completion;

/// Every link the chat has, flattened to "link", "name", "members",
/// "memberLimit", "primary", "revoked" and "requests".
- (void)inviteLinksForChat:(int64_t)chatId
				completion:(void (^)(NSArray *links))completion;

/// A link of its own, revocable without taking the primary one down with it.
/// A `memberLimit` of zero is no limit.
- (void)createInviteLinkForChat:(int64_t)chatId
						   name:(NSString *)name
					memberLimit:(NSInteger)memberLimit
					 completion:(void (^)(NSString *link))completion;

/// Replaces the chat's primary link; the old one stops working at once.
- (void)replacePrimaryInviteLinkForChat:(int64_t)chatId
							 completion:(void (^)(NSString *link))completion;

- (void)revokeInviteLink:(NSString *)link inChat:(int64_t)chatId
			  completion:(void (^)(BOOL ok))completion;

/// What is behind a link before joining it.
- (void)checkInviteLink:(NSString *)link
			 completion:(void (^)(NSString *title, NSInteger members,
								  BOOL alreadyMember))completion;

/// People waiting at a link that creates join requests: "id", "name", "date".
- (void)joinRequestsForChat:(int64_t)chatId
				 completion:(void (^)(NSArray *requests))completion;

- (void)processJoinRequest:(int64_t)userId inChat:(int64_t)chatId approve:(BOOL)approve;

/// The sticker pack a supergroup shows above its composer. `setId` is a pack
/// id from getOwnedStickerSets; 0 clears it. A basic group has nowhere to
/// put one, so the answer is NO rather than a request Telegram would refuse.
- (void)setSupergroupStickerSet:(int64_t)setId
						inChat:(int64_t)chatId
					completion:(void (^)(BOOL ok))completion;

/// The custom emoji pack a supergroup uses for reactions and its emoji
/// status. Same id shape and same basic-group refusal as the regular one.
- (void)setSupergroupCustomEmojiStickerSet:(int64_t)setId
									inChat:(int64_t)chatId
								completion:(void (^)(BOOL ok))completion;

@end
