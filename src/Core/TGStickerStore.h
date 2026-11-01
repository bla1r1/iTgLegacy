//
// TGStickerStore - the sticker shelf's front door.
//
// Everything the emoji panel asks for: installed sets, stickers by set,
// emoji and search, favourites, recent, saved GIFs - and the commands that
// change them. The panel talks to this narrow surface, not to the whole
// client header: what a sticker view may ask for is one file, here it is,
// named.
//
#import <Foundation/Foundation.h>
#import "TGDownloadPriority.h"

@interface TGStickerStore : NSObject

+ (TGStickerStore *)shared;

/// Posted when the lists the shelf shows changed from somewhere else - a set
/// installed, a GIF saved, a sticker favourited, here or on another client.
/// The name is the client's; the shelf asks again rather than patching.
extern NSString *const TGStickerListsChangedNotification;

#pragma mark - reads

/// Installed sets, shaped as "id", "title", "cover", "count".
- (void)installedStickerSetsWithCompletion:(void (^)(NSArray *sets))completion;
/// Stickers of one set; `setId` is the set's NSNumber id.
- (void)stickersInSet:(id)setId completion:(void (^)(NSArray *stickers))completion;
- (void)favoriteStickersWithCompletion:(void (^)(NSArray *stickers))completion;
- (void)recentStickersWithCompletion:(void (^)(NSArray *stickers))completion;
/// Stickers for an emoji, out of the installed sets.
- (void)stickersForEmoji:(NSString *)emoji
			  completion:(void (^)(NSArray *stickers))completion;
/// The same across every public set.
- (void)searchStickersForEmoji:(NSString *)emoji
					completion:(void (^)(NSArray *stickers))completion;
/// Sets by name, shaped as -installedStickerSetsWithCompletion: answers.
- (void)searchStickerSetsNamed:(NSString *)query
					completion:(void (^)(NSArray *sets))completion;
/// The same search over the sets this account already has, which is how a
/// pack that is installed is told apart from one that is not.
- (void)installedStickerSetsNamed:(NSString *)query
					   completion:(void (^)(NSArray *sets))completion;
/// What is popular now; the other half of finding a new set.
- (void)trendingStickerSetsWithCompletion:(void (^)(NSArray *sets))completion;
/// The shelf a removed pack lands on, from which it can be put back.
- (void)archivedStickerSetsWithCompletion:(void (^)(NSArray *sets))completion;
/// The packs a piece of media carries, by the media file's id - what a photo
/// with stickers on it can offer.
- (void)attachedStickerSetsOfFile:(NSInteger)fileId
					   completion:(void (^)(NSArray *sets))completion;
/// Saved GIFs, shaped as "fileId", "width", "height", "duration", "thumbId".
- (void)savedAnimationsWithCompletion:(void (^)(NSArray *animations))completion;
/// GIF search; the @gif bot answers per chat.
- (void)searchAnimations:(NSString *)query
				  inChat:(int64_t)chatId
			  completion:(void (^)(NSArray *animations))completion;

/// Emoji Telegram suggests for GIF search, from the search-parameters update.
/// Empty until it arrives.
- (NSArray *)animationSearchEmojis;

/// The tags a single sticker carries, and every tag matching one of them.
/// The panel's hold card shows both so a sticker's filing is visible.
- (void)stickerEmojisForFileId:(NSInteger)fileId
					completion:(void (^)(NSArray *emojis))completion;
- (void)allStickerEmojisForQuery:(NSString *)query
					  completion:(void (^)(NSArray *emojis))completion;

/// A sticker's outline and its SVG path. The card shows the shape count and
/// offers the path for copying; no vector renderer is needed for either.
- (void)stickerOutlineForFileId:(NSInteger)fileId
					 completion:(void (^)(NSArray *paths, NSInteger pointCount))completion;
- (void)stickerOutlineSvgPathForFileId:(NSInteger)fileId
							completion:(void (^)(NSString *path))completion;

/// Mark the trending shelf as seen. Called when the panel or the packs screen
/// actually shows it, so the same packs are not recommended forever.
- (void)viewTrendingStickerSets:(NSArray *)setIds;

/// Empty Recently Used.
- (void)clearRecentStickers;

#pragma mark - commands

/// The new strip order, as the */reorder* calls take it.
- (void)reorderInstalledStickerSets:(NSArray *)setIds;
- (void)setSticker:(NSInteger)fileId favourite:(BOOL)favourite;
- (void)removeRecentSticker:(NSInteger)fileId;
- (void)setStickerSet:(id)setId installed:(BOOL)installed archived:(BOOL)archived;
- (void)saveAnimationFileId:(NSInteger)fileId saved:(BOOL)saved;

#pragma mark - files

- (void)downloadFile:(NSInteger)fileId completion:(void (^)(NSString *path))completion;
- (void)downloadFile:(NSInteger)fileId priority:(NSInteger)priority
          completion:(void (^)(NSString *path))completion;

@end
