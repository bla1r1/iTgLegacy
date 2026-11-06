//
// TGCustomEmojiStore.m - one getCustomEmojiStickers per burst of ids, the
// still thumbnail of each, decoded off the main thread at the size asked for.
//
#import "TGCustomEmojiStore.h"
#import "TGClient.h"
#import "TGImageLruCache.h"
#import "TGIcons.h"
#import "UIImage+WebP.h"

NSString *const TGCustomEmojiLoadedNotification = @"TGCustomEmojiLoadedNotification";

/// About 300 KB at 20 pt @2x: the pictures on one chat screen and its list.
static const NSUInteger kCachedPictures = 192;
/// getCustomEmojiStickers takes up to 200 ids.
static const NSUInteger kBatchLimit = 200;

@interface TGCustomEmojiStore ()
@property (nonatomic, strong) TGImageLruCache *pictures;     // "id:side" -> image
@property (nonatomic, strong) NSMutableDictionary *paths;    // id -> file on disk
@property (nonatomic, strong) NSMutableDictionary *wanted;   // id -> set of sides
@property (nonatomic, strong) NSMutableSet *queued;          // ids waiting for the batch
@property (nonatomic, strong) NSMutableSet *failed;          // ids TDLib gave no picture for
@end

@implementation TGCustomEmojiStore

+ (instancetype)shared {
	static TGCustomEmojiStore *store = nil;
	static dispatch_once_t once;
	dispatch_once(&once, ^{ store = [[TGCustomEmojiStore alloc] init]; });
	return store;
}

- (instancetype)init {
	if ((self = [super init]))
		[self reset];
	return self;
}

- (void)reset {
	self.pictures = [[TGImageLruCache alloc] initWithCapacity:kCachedPictures];
	self.paths = [NSMutableDictionary dictionary];
	self.wanted = [NSMutableDictionary dictionary];
	self.queued = [NSMutableSet set];
	self.failed = [NSMutableSet set];
}

static NSString *TGPictureKey(int64_t emojiId, CGFloat side) {
	return [NSString stringWithFormat:@"%lld:%.0f", emojiId, side];
}

- (UIImage *)imageForId:(int64_t)emojiId side:(CGFloat)side {
	if (emojiId == 0 || side <= 0)
		return nil;
	UIImage *picture = self.pictures[TGPictureKey(emojiId, side)];
	if (picture)
		return picture;
	NSNumber *key = @(emojiId);
	if ([self.failed containsObject:key])
		return nil;

	NSMutableSet *sides = self.wanted[key];
	BOOL asked = sides != nil;
	if (!sides)
		self.wanted[key] = sides = [NSMutableSet set];
	if ([sides containsObject:@(side)])
		return nil;
	[sides addObject:@(side)];

	// The file is already here for another size: only the decode is new.
	NSString *path = self.paths[key];
	if (path){
		[self decodePath:path forId:emojiId side:side];
		return nil;
	}
	if (asked)
		return nil;
	[self.queued addObject:key];
	if (self.queued.count == 1)
		[self performSelector:@selector(sendBatch) withObject:nil afterDelay:0.05];
	return nil;
}

- (void)sendBatch {
	NSArray *ids = [[self.queued allObjects] subarrayWithRange:
			NSMakeRange(0, MIN(self.queued.count, kBatchLimit))];
	[self.queued minusSet:[NSSet setWithArray:ids]];
	if (self.queued.count)
		[self performSelector:@selector(sendBatch) withObject:nil afterDelay:0.05];

#if TG_DEV
	NSLog(@"custom emoji: asking for %lu", (unsigned long)ids.count);
#endif
	__weak typeof(self) weakSelf = self;
	[[TGClient shared] customEmojiStickersForIds:ids completion:^(NSArray *stickers){
		dispatch_async(dispatch_get_main_queue(), ^{
			[weakSelf receiveStickers:stickers forIds:ids];
		});
	}];
}

- (void)receiveStickers:(NSArray *)stickers forIds:(NSArray *)ids {
	NSMutableSet *missing = [NSMutableSet setWithArray:ids];
	for (NSDictionary *sticker in stickers){
		NSNumber *key = @([sticker[@"customEmojiId"] longLongValue]);
		NSNumber *thumb = sticker[@"thumbId"];
		if (![thumb isKindOfClass:NSNumber.class] || !thumb.integerValue)
			continue;
		[missing removeObject:key];
		__weak typeof(self) weakSelf = self;
		[[TGClient shared] downloadFile:thumb.integerValue
							   priority:TGDownloadPriorityAvatar
							 completion:^(NSString *path){
			dispatch_async(dispatch_get_main_queue(), ^{
				[weakSelf receivePath:path forId:key.longLongValue];
			});
		}];
	}
	// An animated emoji with no still thumbnail, or an id TDLib does not
	// know: the plain emoji in the text stays, and nobody asks again.
	[self.failed unionSet:missing];
#if TG_DEV
	NSLog(@"custom emoji: %lu stickers, %lu without a still picture",
			(unsigned long)stickers.count, (unsigned long)missing.count);
#endif
}

- (void)receivePath:(NSString *)path forId:(int64_t)emojiId {
	NSNumber *key = @(emojiId);
	if (!path.length){
		[self.failed addObject:key];
		return;
	}
	self.paths[key] = path;
	for (NSNumber *side in [self.wanted[key] copy])
		[self decodePath:path forId:emojiId side:side.floatValue];
}

- (void)decodePath:(NSString *)path forId:(int64_t)emojiId side:(CGFloat)side {
	CGFloat scale = [UIScreen mainScreen].scale;
	__weak typeof(self) weakSelf = self;
	dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
		UIImage *raw = [UIImage imageWithContentsOfFile:path]
				?: [UIImage convertFromWebP:path compressedData:nil error:nil];
		UIImage *picture = raw ? [TGIcons decodedImage:raw fittingSize:CGSizeMake(side, side)
												   fill:NO scale:scale] : nil;
		dispatch_async(dispatch_get_main_queue(), ^{
			TGCustomEmojiStore *me = weakSelf;
			if (!me || !picture)
				return;
			me.pictures[TGPictureKey(emojiId, side)] = picture;
			[me.wanted[@(emojiId)] removeObject:@(side)];
			[[NSNotificationCenter defaultCenter]
					postNotificationName:TGCustomEmojiLoadedNotification object:me
								userInfo:@{@"id" : @(emojiId)}];
		});
	});
}

@end
