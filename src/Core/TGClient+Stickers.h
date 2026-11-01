//
// TGClient+Stickers.h - the client surface for the sticker shelf: installed sets, search, favourites, GIFs.
//
#import "TGClient+Base.h"

@interface TGClient (Stickers)

/// The inline bot GIF search uses. "gif" until updateAnimationSearchParameters
/// names another, which is what keeps the tab working if Telegram moves it.
@property (nonatomic, readonly) NSString *animationSearchProvider;
/// The emoji Telegram suggests for GIF search; empty until that update.
@property (nonatomic, readonly) NSArray *animationSearchEmojis;

/// Installed sets: "id" (pass back as is), "title", and "cover" - a sticker
/// in the same shape recentStickers gives.
- (void)installedStickerSetsWithCompletion:(void (^)(NSArray *sets))completion;

- (void)stickersInSet:(id)setId completion:(void (^)(NSArray *stickers))completion;

- (void)favoriteStickersWithCompletion:(void (^)(NSArray *stickers))completion;

/// Add or remove a sticker from Favourites, which is what holding one does.
- (void)setSticker:(NSInteger)fileId favourite:(BOOL)favourite;

/// Drop one sticker out of Recently Used.
- (void)removeRecentSticker:(NSInteger)fileId;

/// Uninstall a sticker set, which is what removing a pack means.
/// `archived` with `installed` NO moves it to the archived shelf instead of
/// throwing it away; YES YES puts it back among the installed.
- (void)setStickerSet:(id)setId installed:(BOOL)installed archived:(BOOL)archived;

/// A pack by the name a t.me/addstickers link carries: "id", "title",
/// "count", "shortName", "cover", and "installed" - whether this account
/// already has it. nil when Telegram does not know the name at all.
- (void)stickerSetByShortName:(NSString *)shortName
				   completion:(void (^)(NSDictionary *set))completion;

/// Installed sets whose titles match, for finding a pack the account has.
- (void)installedStickerSetsNamed:(NSString *)query
                       completion:(void (^)(NSArray *sets))completion;

/// The archived shelf, which is where a set removed by accident survives.
- (void)archivedStickerSetsWithCompletion:(void (^)(NSArray *sets))completion;

/// The sets attached to one media file - a picture or a video that carries
/// stickers. TDLib answers by file id, the same id the bubble draws.
- (void)attachedStickerSetsOfFile:(NSInteger)fileId
					   completion:(void (^)(NSArray *sets))completion;

/// The installed order after a move. `setIds` is the whole list, the
/// first id becoming the first strip slot.
- (void)reorderInstalledStickerSets:(NSArray *)setIds;

/// Put a GIF in Saved GIFs, and take one out again.
- (void)saveAnimationFileId:(NSInteger)fileId saved:(BOOL)saved;

/// GIFs: "fileId", "width", "height", "duration", optional "thumbId" (a
/// still picture) and "minithumbnail" (NSData, a tiny inline JPEG). Search
/// results also carry "queryId" and "resultId".
- (void)savedAnimationsWithCompletion:(void (^)(NSArray *animations))completion;

- (void)searchAnimations:(NSString *)query
				  inChat:(int64_t)chatId
			  completion:(void (^)(NSArray *animations))completion;

- (void)sendAnimation:(NSDictionary *)animation toChat:(int64_t)chatId thread:(int64_t)threadId;

/// Stickers for an emoji, out of the sets this account has installed.
- (void)stickersForEmoji:(NSString *)emoji
			  completion:(void (^)(NSArray *stickers))completion;

/// The same across every public set - the half that finds something new.
- (void)searchStickersForEmoji:(NSString *)emoji
					completion:(void (^)(NSArray *stickers))completion;

/// Sets by name. Entries are shaped as -installedStickerSetsWithCompletion:
/// answers: "id", "title", "cover".
- (void)searchStickerSetsNamed:(NSString *)query
					completion:(void (^)(NSArray *sets))completion;

- (void)trendingStickerSetsWithCompletion:(void (^)(NSArray *sets))completion;

#pragma mark - authoring a pack

/// Sets this account owns, all sticker types, shaped as the installed list
/// plus "stickerType" and "name". The editor and the group sticker picker
/// read from here, because only an owned set may be changed.
- (void)ownedStickerSetsWithCompletion:(void (^)(NSArray *sets))completion;

/// The status word for a name before a pack is made: "ok", "invalid" or
/// "occupied". `message` is a sentence a sheet can show verbatim.
- (void)checkStickerSetName:(NSString *)name
				 completion:(void (^)(NSString *status, NSString *message))completion;

/// What Telegram would call a pack with this title: a lower-case short name
/// with the words joined, which is the suggestion `checkStickerSetName`
/// answers with when the typed one is taken.
- (void)suggestStickerSetNameForTitle:(NSString *)title
						   completion:(void (^)(NSString *name))completion;

/// The short name behind a set id, which the id alone does not carry.
- (void)stickerSetNameForId:(int64_t)setId
				 completion:(void (^)(NSString *name))completion;

/// A public pack by its short name, with its stickers. Unlike
/// -stickerSetByShortName: this asks Telegram to search rather than fetch a
/// name the caller already knows, and it returns the pack's own name too.
- (void)searchStickerSetNamed:(NSString *)name
				  ignoreCache:(BOOL)ignoreCache
				   completion:(void (^)(NSDictionary *set))completion;

/// Make a pack owned by this account. `stickers` are newSticker dictionaries
/// (see -newStickerWithFileId:format:emojis:keywords:maskPosition:); at least
/// one is required by Telegram. `type` is "regular" or "mask".
- (void)createStickerSetNamed:(NSString *)name
						title:(NSString *)title
				  stickerType:(NSString *)type
					 stickers:(NSArray *)stickers
				   completion:(void (^)(NSDictionary *set))completion;

/// Delete a pack this account owns.
- (void)deleteStickerSetNamed:(NSString *)name
				   completion:(void (^)(BOOL ok))completion;

/// A newSticker record from the pieces the editor has. `maskPosition` may be
/// nil; `keywords` may be empty.
- (NSDictionary *)newStickerWithFileId:(NSInteger)fileId
								format:(NSString *)format
								emojis:(NSString *)emojis
							  keywords:(NSArray *)keywords
						  maskPosition:(NSDictionary *)maskPosition;

/// Add a sticker, upload a file first, and the two halves of replacing one.
- (void)addStickerToSetNamed:(NSString *)name
					 sticker:(NSDictionary *)sticker
				  completion:(void (^)(BOOL ok))completion;
- (void)removeStickerFileId:(NSInteger)fileId
				 completion:(void (^)(BOOL ok))completion;
- (void)replaceStickerInSetNamed:(NSString *)name
					  oldFileId:(NSInteger)oldFileId
					  newSticker:(NSDictionary *)sticker
					  completion:(void (^)(BOOL ok))completion;

/// Reorder, retag and re-mask a sticker that is already in a pack. Position
/// is zero based.
- (void)setStickerFileId:(NSInteger)fileId
		   positionInSet:(NSInteger)position
			  completion:(void (^)(BOOL ok))completion;
- (void)setStickerFileId:(NSInteger)fileId
				  emojis:(NSString *)emojis
			  completion:(void (^)(BOOL ok))completion;
- (void)setStickerFileId:(NSInteger)fileId
				keywords:(NSArray *)keywords
			  completion:(void (^)(BOOL ok))completion;
/// `maskPosition` is a TDLib maskPosition dictionary; nil removes it, which
/// td_api spells as a null mask_position.
- (void)setStickerFileId:(NSInteger)fileId
			maskPosition:(NSDictionary *)maskPosition
			  completion:(void (^)(BOOL ok))completion;

/// Rename a pack, or give it a new thumbnail. The thumbnail is a local image
/// file uploaded by TDLib; `format` is "webp", "tgs" or "webm".
- (void)setStickerSetNamed:(NSString *)name
					 title:(NSString *)title
				completion:(void (^)(BOOL ok))completion;
- (void)setStickerSetNamed:(NSString *)name
		 thumbnailAtPath:(NSString *)path
				  format:(NSString *)format
			  completion:(void (^)(BOOL ok))completion;

/// Upload one sticker file and answer its file id, which is what
/// addStickerToSet and createStickerSet take. A path that cannot be read
/// answers 0 without a request.
- (void)uploadStickerAtPath:(NSString *)path
					 format:(NSString *)format
				 completion:(void (^)(NSInteger fileId))completion;

#pragma mark - emoji metadata and outlines

/// The emoji a single sticker is filed under, as Telegram stores them.
- (void)stickerEmojisForFileId:(NSInteger)fileId
					completion:(void (^)(NSArray *emojis))completion;

/// Every emoji matching `query` across the installed sets, or across all
/// public sets when `chatId` is 0. `type` is "regular", "mask" or
/// "customEmoji"; `mainOnly` drops the secondary tags.
- (void)allStickerEmojisForQuery:(NSString *)query
						  chatId:(int64_t)chatId
					 stickerType:(NSString *)type
						mainOnly:(BOOL)mainOnly
					  completion:(void (^)(NSArray *emojis))completion;

/// A sticker's outline as the paths Telegram publishes. The completion gets
/// the number of closed paths and the number of points across them; a sheet
/// shows both without needing a vector renderer.
- (void)stickerOutlineForFileId:(NSInteger)fileId
					 completion:(void (^)(NSArray *paths, NSInteger pointCount))completion;

/// The same outline as one SVG path string, for clipping or for copying.
- (void)stickerOutlineSvgPathForFileId:(NSInteger)fileId
							completion:(void (^)(NSString *path))completion;

#pragma mark - custom emoji

/// Custom emoji stickers by their ids, shaped as the sticker list plus
/// "customEmojiId". A chat that shows an emoji in text carries the id.
- (void)customEmojiStickersForIds:(NSArray *)ids
					   completion:(void (^)(NSArray *stickers))completion;

/// The three default shelves Telegram ships: what a profile photo, a chat
/// photo and a background may use.
- (void)defaultProfilePhotoCustomEmojiStickersWithCompletion:
		(void (^)(NSArray *stickers))completion;
- (void)defaultChatPhotoCustomEmojiStickersWithCompletion:
		(void (^)(NSArray *stickers))completion;
- (void)defaultBackgroundCustomEmojiStickersWithCompletion:
		(void (^)(NSArray *stickers))completion;

/// Stickers Telegram suggests for greeting messages.
- (void)greetingStickersWithCompletion:(void (^)(NSArray *stickers))completion;

/// Give a custom emoji pack one of its emoji as its thumbnail.
- (void)setCustomEmojiStickerSetNamed:(NSString *)name
				   thumbnailCustomEmojiId:(int64_t)customEmojiId
						  completion:(void (^)(BOOL ok))completion;

/// Tell Telegram the trending shelf was shown, which is what stops the same
/// packs being recommended again. The ids are the ones the shelf carries.
- (void)viewTrendingStickerSets:(NSArray *)setIds;

/// Empty Recently Used. `attached` clears the half used inside messages
/// instead of the ordinary shelf.
- (void)clearRecentStickersAttached:(BOOL)attached;

@end
