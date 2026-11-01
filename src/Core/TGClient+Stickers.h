//
// TGClient+Stickers.h - the client surface for the sticker shelf: installed sets, search, favourites, GIFs.
//
#import "TGClient+Base.h"

@interface TGClient (Stickers)

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

/// The sets that used to be attached in a chat - what their client shows
/// when you send media there.
- (void)attachedStickerSetsInChat:(int64_t)chatId
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

@end
