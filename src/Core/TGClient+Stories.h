//
// TGClient+Stories.h - stories on the wire: the feed, the viewer's requests,
// posting and editing, albums, interactions, discovery, notifications and the
// live story calls.
//
// TDLib splits a story across storyInfo (what a feed row needs), story (the
// full record) and storyInteraction (who did what). The screens deal in one
// flat dictionary per story and per row, because a 4S cannot afford to walk a
// TDLib tree three times per cell.
//
#import "TGClient+Base.h"

@interface TGClient (Stories)

#pragma mark - the feed

/// Loads more active stories for "main" or "archive". TDLib streams the result
/// as updates; the caller follows up with -activeStoryRowsForList: so the row
/// it draws comes from the same source as its refresh.
- (void)loadActiveStoriesForList:(NSString *)list
					  completion:(void (^)(BOOL ok, NSString *error))completion;

/// One chat's active stories: "chatId", "title", "photoFileId", "isOwn",
/// "unread" (max_read_story_id is behind the newest story), "isLive",
/// "maxReadStoryId", "order", "canBeArchived", "list" and "stories" - the
/// storyInfo records TDLib sends. Nil when the chat has none.
- (void)activeStoryRowForChat:(int64_t)chatId
				   completion:(void (^)(NSDictionary *row))completion;

/// The rows the chat list's stories strip draws. Sends loadActiveStories for
/// the list, then reads each chat already in the client's list. Empty is a
/// real answer: no active stories, not a failed request.
- (void)activeStoryRowsForList:(NSString *)list
					completion:(void (^)(NSArray *rows))completion;

/// Moves a chat's stories between the main strip and the archive strip.
- (void)setActiveStoriesList:(NSString *)list
					 forChat:(int64_t)chatId
				  completion:(void (^)(BOOL ok, NSString *error))completion;

/// The stories pinned to a chat's profile page, in order. Every id must
/// already be posted to the chat page.
- (void)setPinnedStoryIds:(NSArray *)storyIds
				   inChat:(int64_t)chatId
			   completion:(void (^)(BOOL ok, NSString *error))completion;

/// All stories a chat has ever posted; requires can_edit_stories in a group
/// or channel. Only the ids Telegram returns are new: the archive screen
/// converts them with -story:fromChat:completion:.
- (void)archivedStoryIdsForChat:(int64_t)chatId
					 fromStoryId:(int32_t)fromStoryId
						  limit:(NSInteger)limit
					 completion:(void (^)(NSArray *storyIds, NSString *error))completion;

/// A story by id, flattened. The viewer asks for this rather than re-reading
/// the whole chat every time the user swipes.
- (void)story:(int32_t)storyId
	  fromChat:(int64_t)chatId
  completion:(void (^)(NSDictionary *story))completion;

#pragma mark - viewing

/// Tells TDLib the story is open, so views count and read state moves.
- (void)openStory:(int32_t)storyId
		  fromChat:(int64_t)chatId
	   completion:(void (^)(BOOL ok, NSString *error))completion;

/// Tells TDLib the viewer closed. Sent when leaving a story, whatever moved
/// the user away from it.
- (void)closeStory:(int32_t)storyId
		  fromChat:(int64_t)chatId
	   completion:(void (^)(BOOL ok, NSString *error))completion;

/// Reactions Telegram offers for stories: "emojis" (top first), "recent",
/// "popular", "allowCustom" and "unavailable" (Telegram's reason, or nil).
- (void)storyAvailableReactionsWithCompletion:
		(void (^)(NSDictionary *reactions))completion;

/// Sets a reaction on a story. `emoji` nil removes the current one; custom
/// emoji reactions are sent as "custom:<id>" so the picker has one string
/// to carry. Unsupported for live stories.
- (void)setStoryReaction:(NSString *)emoji
				  onStory:(int32_t)storyId
				 fromChat:(int64_t)chatId
			  completion:(void (^)(BOOL ok, NSString *error))completion;

#pragma mark - posting and editing

/// Telegram's answer for "may this chat post a story now?". The dictionary
/// carries "ok", "reason", "storyCount", "retryAfter" and "storyId" (the
/// live story that has to be deleted first, when that is the reason).
- (void)canPostStoryInChat:(int64_t)chatId
				completion:(void (^)(NSDictionary *answer))completion;

/// Chats this account may post stories on behalf of: "id", "title",
/// "photoFileId" and "isChannel".
- (void)chatsToPostStoriesWithCompletion:(void (^)(NSArray *chats))completion;

/// Posts a photo or video story. `path` is a local JPEG/MP4; the controller
/// has already sized it to Telegram's 1080x1920 / 720x1280 contract.
/// `caption` may be empty. `privacy` is "everyone", "contacts",
/// "closeFriends" or "selected"; `userIds` is used by the last.
- (void)postStoryToChat:(int64_t)chatId
				   path:(NSString *)path
				isVideo:(BOOL)isVideo
			   duration:(double)duration
				caption:(NSString *)caption
				privacy:(NSString *)privacy
				 userIds:(NSArray *)userIds
		   activePeriod:(NSInteger)seconds
		postedToChatPage:(BOOL)postedToChatPage
		  protectContent:(BOOL)protectContent
				albumIds:(NSArray *)albumIds
			 completion:(void (^)(NSDictionary *story, NSString *error))completion;

/// Edits a story's media and/or caption. A nil `path` keeps the current
/// media; a nil `caption` keeps the current caption.
- (void)editStory:(int32_t)storyId
		  fromChat:(int64_t)chatId
			  path:(NSString *)path
		 isVideo:(BOOL)isVideo
		duration:(double)duration
		 caption:(NSString *)caption
	  completion:(void (^)(BOOL ok, NSString *error))completion;

/// The poster frame used for a video story, in seconds from the start.
- (void)editStoryCover:(int32_t)storyId
			  fromChat:(int64_t)chatId
	  coverTimestamp:(double)timestamp
		  completion:(void (^)(BOOL ok, NSString *error))completion;

- (void)deleteStory:(int32_t)storyId
		   fromChat:(int64_t)chatId
		 completion:(void (^)(BOOL ok, NSString *error))completion;

/// Keeps the story on the profile after it expires, or takes it off.
- (void)toggleStory:(int32_t)storyId
			 fromChat:(int64_t)chatId
	  postedToChatPage:(BOOL)posted
		  completion:(void (^)(BOOL ok, NSString *error))completion;

/// Own-account stories only; Telegram refuses it for a chat's story.
- (void)setStoryPrivacySettings:(int32_t)storyId
						privacy:(NSString *)privacy
						userIds:(NSArray *)userIds
					 completion:(void (^)(BOOL ok, NSString *error))completion;

/// The two business-only variants. A user account gets Telegram's refusal,
/// which is the answer the menu shows.
- (void)deleteBusinessStory:(int32_t)storyId
				   fromChat:(int64_t)chatId
				 completion:(void (^)(BOOL ok, NSString *error))completion;

- (void)editBusinessStory:(int32_t)storyId
				 fromChat:(int64_t)chatId
					 path:(NSString *)path
				  isVideo:(BOOL)isVideo
				 duration:(double)duration
				  caption:(NSString *)caption
			   completion:(void (^)(BOOL ok, NSString *error))completion;

#pragma mark - albums

/// "id", "name", "photoFileId" and "videoFileId" per album.
- (void)storyAlbumsForChat:(int64_t)chatId
				completion:(void (^)(NSArray *albums))completion;

/// Telegram returns only the album record (id, name, icons) - the stories it
/// now holds are read with -storiesInAlbum:... after this answers.
- (void)createStoryAlbumNamed:(NSString *)name
					   inChat:(int64_t)chatId
					 storyIds:(NSArray *)storyIds
				   completion:(void (^)(NSDictionary *album, NSString *error))completion;

- (void)deleteStoryAlbum:(int32_t)albumId
				  inChat:(int64_t)chatId
			  completion:(void (^)(BOOL ok, NSString *error))completion;

- (void)setStoryAlbumName:(NSString *)name
					albumId:(int32_t)albumId
					 inChat:(int64_t)chatId
				 completion:(void (^)(NSDictionary *album, NSString *error))completion;

- (void)reorderStoryAlbums:(NSArray *)albumIds
					inChat:(int64_t)chatId
				completion:(void (^)(BOOL ok, NSString *error))completion;

/// Flattened stories in an album, in the album's order.
- (void)storiesInAlbum:(int32_t)albumId
				inChat:(int64_t)chatId
				offset:(NSInteger)offset
				 limit:(NSInteger)limit
			completion:(void (^)(NSArray *stories, NSString *error))completion;

- (void)addStories:(NSArray *)storyIds
		 toAlbum:(int32_t)albumId
			inChat:(int64_t)chatId
		completion:(void (^)(NSDictionary *album, NSString *error))completion;

- (void)removeStories:(NSArray *)storyIds
		 fromAlbum:(int32_t)albumId
			 inChat:(int64_t)chatId
		 completion:(void (^)(NSDictionary *album, NSString *error))completion;

/// Moves the named stories to the front of the album in the order given.
- (void)reorderStories:(NSArray *)storyIds
			 inAlbum:(int32_t)albumId
				inChat:(int64_t)chatId
			completion:(void (^)(NSDictionary *album, NSString *error))completion;

#pragma mark - interactions and statistics

/// Interactions with an own-account story. `offset` is "" for the first page;
/// the answer carries "nextOffset".
- (void)storyInteractionsForStory:(int32_t)storyId
							query:(NSString *)query
					 onlyContacts:(BOOL)onlyContacts
					preferForwards:(BOOL)preferForwards
				preferWithReaction:(BOOL)preferWithReaction
							 offset:(NSString *)offset
							  limit:(NSInteger)limit
						 completion:(void (^)(NSDictionary *page, NSString *error))completion;

/// Interactions with a story posted by a chat; requires an administrator
/// right in that chat.
- (void)chatStoryInteractionsForStory:(int32_t)storyId
							  fromChat:(int64_t)chatId
							reactionEmoji:(NSString *)emoji
						   preferForwards:(BOOL)preferForwards
								   offset:(NSString *)offset
									limit:(NSInteger)limit
							   completion:(void (^)(NSDictionary *page, NSString *error))completion;

/// Public messages and reposts of a story: "totalCount", "nextOffset" and
/// "forwards" rows carrying "kind", "title", "text" and a story when the
/// forward is itself a story.
- (void)storyPublicForwards:(int32_t)storyId
					fromChat:(int64_t)chatId
					  offset:(NSString *)offset
					   limit:(NSInteger)limit
				  completion:(void (^)(NSDictionary *page, NSString *error))completion;

/// Interaction and reaction graphs, each flattened to "lines" the list draws
/// as bars. A statisticalGraphAsync token is shown rather than followed: this
/// screen has nowhere to keep a graph that arrives after it closed.
- (void)storyStatistics:(int32_t)storyId
			   fromChat:(int64_t)chatId
				 isDark:(BOOL)isDark
			 completion:(void (^)(NSDictionary *statistics, NSString *error))completion;

/// The report is two steps: the first call with an empty option asks Telegram
/// which options exist; the chosen option and optional text are sent second.
- (void)reportStory:(int32_t)storyId
		   fromChat:(int64_t)chatId
		   optionId:(NSString *)optionId
			   text:(NSString *)text
		 completion:(void (^)(NSDictionary *result, NSString *error))completion;

#pragma mark - notifications

/// Chats with story notification settings that differ from the scope default:
/// "id", "title", "photoFileId", "muteStories" and "muteFor".
- (void)storyNotificationExceptionsWithCompletion:(void (^)(NSArray *chats))completion;

#pragma mark - public discovery

/// FoundStories flattened to "totalCount", "nextOffset" and "stories".
- (void)searchPublicStoriesByTag:(NSString *)tag
						  offset:(NSString *)offset
						   limit:(NSInteger)limit
					  completion:(void (^)(NSDictionary *page, NSString *error))completion;

/// `address` uses the four strings TDLib names: "countryCode", "state",
/// "city" and "street". At least one has to be present.
- (void)searchPublicStoriesByLocation:(NSDictionary *)address
							   offset:(NSString *)offset
								limit:(NSInteger)limit
						   completion:(void (^)(NSDictionary *page, NSString *error))completion;

- (void)searchPublicStoriesByVenue:(NSString *)venueProvider
						   venueId:(NSString *)venueId
							offset:(NSString *)offset
							 limit:(NSInteger)limit
						completion:(void (^)(NSDictionary *page, NSString *error))completion;

#pragma mark - stealth

/// Hides this account's views for the past and next stealth window. Premium
/// only; the server's refusal is the answer the menu shows.
- (void)activateStoryStealthModeWithCompletion:
		(void (^)(BOOL ok, NSString *error))completion;

#pragma mark - live stories

/// Starts a live story. `rtmp` asks Telegram for an RTMP stream; without a
/// camera encoder this client still shows the server's stream key and the
/// live state. The answer carries "ok", "story" and, on failure, "error".
- (void)startLiveStoryInChat:(int64_t)chatId
					 privacy:(NSString *)privacy
					  userIds:(NSArray *)userIds
			   protectContent:(BOOL)protectContent
					   rtmp:(BOOL)rtmp
			 enableMessages:(BOOL)enableMessages
			  paidMessageStars:(NSInteger)paidMessageStars
				  completion:(void (^)(NSDictionary *answer))completion;

/// Joins the call behind a live story and returns Telegram's join payload.
/// This client has no camera to put into it; the payload and the server's
/// refusal are shown as they arrive.
- (void)joinLiveStoryCall:(int32_t)groupCallId
			   completion:(void (^)(NSString *payload, NSString *error))completion;

/// Who is streaming: "kind", "id", "name", "isCurrentUser", "isSpeaking",
/// "isMuted" and "bio".
- (void)liveStoryStreamerForCall:(int32_t)groupCallId
					  completion:(void (^)(NSDictionary *streamer, NSString *error))completion;

/// The chat's RTMP address: "url" and "streamKey".
- (void)liveStoryRtmpUrlForChat:(int64_t)chatId
					 completion:(void (^)(NSDictionary *url, NSString *error))completion;

/// Asks Telegram for a new stream key, invalidating the old one.
- (void)replaceLiveStoryRtmpUrlForChat:(int64_t)chatId
							completion:(void (^)(NSDictionary *url, NSString *error))completion;

/// Senders messages may be posted in the live story as, with "needsPremium".
- (void)liveStoryAvailableMessageSendersForCall:(int32_t)groupCallId
									 completion:(void (^)(NSArray *senders, NSString *error))completion;

/// `sender` is a dictionary with "kind" ("user" or "chat") and "id".
- (void)setLiveStoryMessageSender:(NSDictionary *)sender
						  forCall:(int32_t)groupCallId
					   completion:(void (^)(BOOL ok, NSString *error))completion;

/// "totalStarCount" and "donors": "kind", "id", "name", "stars", "isTop",
/// "isMe" and "isAnonymous".
- (void)liveStoryTopDonorsForCall:(int32_t)groupCallId
					   completion:(void (^)(NSDictionary *donors, NSString *error))completion;

/// Paid reactions are batched: add one, then commit when the undo window
/// ends, or remove every pending one when the user changes their mind.
- (void)addPendingLiveStoryReactionInCall:(int32_t)groupCallId
								   stars:(NSInteger)stars
							  completion:(void (^)(BOOL ok, NSString *error))completion;

- (void)commitPendingLiveStoryReactionsInCall:(int32_t)groupCallId
								   completion:(void (^)(BOOL ok, NSString *error))completion;

- (void)removePendingLiveStoryReactionsInCall:(int32_t)groupCallId
								   completion:(void (^)(BOOL ok, NSString *error))completion;

@end
