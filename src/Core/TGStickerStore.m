//
// TGStickerStore - forwards the sticker shelf's questions to the client.
// One method per line the client already answers; the point is the boundary
// the panel sees, not a new implementation.
//
#import "TGStickerStore.h"
#import "TGClient.h"

@implementation TGStickerStore

+ (TGStickerStore *)shared {
	static TGStickerStore *one;
	static dispatch_once_t once;
	dispatch_once(&once, ^{ one = [[TGStickerStore alloc] init]; });
	return one;
}

#pragma mark - reads

- (void)installedStickerSetsWithCompletion:(void (^)(NSArray *sets))completion {
	[[TGClient shared] installedStickerSetsWithCompletion:completion];
}

- (void)stickersInSet:(id)setId completion:(void (^)(NSArray *stickers))completion {
	[[TGClient shared] stickersInSet:setId completion:completion];
}

- (void)favoriteStickersWithCompletion:(void (^)(NSArray *stickers))completion {
	[[TGClient shared] favoriteStickersWithCompletion:completion];
}

- (void)recentStickersWithCompletion:(void (^)(NSArray *stickers))completion {
	[[TGClient shared] recentStickersWithCompletion:completion];
}

- (void)stickersForEmoji:(NSString *)emoji
			  completion:(void (^)(NSArray *stickers))completion {
	[[TGClient shared] stickersForEmoji:emoji completion:completion];
}

- (void)searchStickersForEmoji:(NSString *)emoji
					completion:(void (^)(NSArray *stickers))completion {
	[[TGClient shared] searchStickersForEmoji:emoji completion:completion];
}

- (void)searchStickerSetsNamed:(NSString *)query
					completion:(void (^)(NSArray *sets))completion {
	[[TGClient shared] searchStickerSetsNamed:query completion:completion];
}

- (void)installedStickerSetsNamed:(NSString *)query
					   completion:(void (^)(NSArray *sets))completion {
	[[TGClient shared] installedStickerSetsNamed:query completion:completion];
}

- (void)trendingStickerSetsWithCompletion:(void (^)(NSArray *sets))completion {
	[[TGClient shared] trendingStickerSetsWithCompletion:completion];
}

- (void)archivedStickerSetsWithCompletion:(void (^)(NSArray *sets))completion {
	[[TGClient shared] archivedStickerSetsWithCompletion:completion];
}

- (void)attachedStickerSetsOfFile:(NSInteger)fileId
					   completion:(void (^)(NSArray *sets))completion {
	[[TGClient shared] attachedStickerSetsOfFile:fileId completion:completion];
}

- (void)savedAnimationsWithCompletion:(void (^)(NSArray *animations))completion {
	[[TGClient shared] savedAnimationsWithCompletion:completion];
}

- (void)searchAnimations:(NSString *)query
				  inChat:(int64_t)chatId
			  completion:(void (^)(NSArray *animations))completion {
	[[TGClient shared] searchAnimations:query inChat:chatId completion:completion];
}

- (NSArray *)animationSearchEmojis {
	return [[TGClient shared] animationSearchEmojis];
}

#pragma mark - commands

- (void)reorderInstalledStickerSets:(NSArray *)setIds {
	[[TGClient shared] reorderInstalledStickerSets:setIds];
}

- (void)setSticker:(NSInteger)fileId favourite:(BOOL)favourite {
	[[TGClient shared] setSticker:fileId favourite:favourite];
}

- (void)removeRecentSticker:(NSInteger)fileId {
	[[TGClient shared] removeRecentSticker:fileId];
}

- (void)setStickerSet:(id)setId installed:(BOOL)installed archived:(BOOL)archived {
	[[TGClient shared] setStickerSet:setId installed:installed archived:archived];
}

- (void)saveAnimationFileId:(NSInteger)fileId saved:(BOOL)saved {
	[[TGClient shared] saveAnimationFileId:fileId saved:saved];
}

#pragma mark - files

- (void)downloadFile:(NSInteger)fileId completion:(void (^)(NSString *path))completion {
	[[TGClient shared] downloadFile:fileId completion:completion];
}

- (void)downloadFile:(NSInteger)fileId priority:(NSInteger)priority
          completion:(void (^)(NSString *path))completion {
	[[TGClient shared] downloadFile:fileId priority:priority completion:completion];
}

@end
