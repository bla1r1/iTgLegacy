//
// TGMemberAvatarStore.m - one download per member, one decode per size.
//
// The list asks for the same handful of people every time it scrolls, so the
// two states that matter are "already decoded" and "already on its way".
// Anything else starts one download. The cache is bounded because a large
// group's member list is longer than any screen and decoded avatars are not
// free on a 256 MB device.
//
#import "TGMemberAvatarStore.h"
#import <math.h>
#import "TGClient.h"
#import "TGStyle.h"
#import "TGImageLruCache.h"

/// A square crop of a downloaded picture, drawn once on a background queue:
/// UIImage's own decode is lazy and would land on the main thread at draw
/// time, which is a dropped frame on an A4.
static UIImage *TGAvatarImageAtPath(NSString *path, CGFloat side) {
	UIImage *image = [UIImage imageWithContentsOfFile:path];
	if (!image || side <= 0)
		return nil;
	CGSize square = CGSizeMake(side, side);
	CGFloat width = image.size.width;
	CGFloat height = image.size.height;
	if (width <= 0 || height <= 0)
		return nil;
	// Fill the square rather than letterbox it: a profile picture cropped to
	// its centre is what the row wants, and a tall picture otherwise leaves
	// two empty bands inside its circle.
	CGFloat ratio = MAX(square.width / width, square.height / height);
	CGSize drawn = CGSizeMake(width * ratio, height * ratio);

	UIGraphicsBeginImageContextWithOptions(square, NO, [UIScreen mainScreen].scale);
	[image drawInRect:CGRectMake(TGCenteredOrigin(square.width, drawn.width),
								 TGCenteredOrigin(square.height, drawn.height),
								 drawn.width, drawn.height)];
	UIImage *scaled = UIGraphicsGetImageFromCurrentImageContext();
	UIGraphicsEndImageContext();
	return scaled;
}

/// TGImageLruCache turns a key into one integer. An NSString key would be
/// truncated at its first non-digit by -longLongValue, so two sizes for one
/// user would share a slot; the side is folded into the number instead.
static NSNumber *TGMemberAvatarKey(int64_t userId, CGFloat side) {
	return @(userId * 1000 + (int64_t)llround(side));
}

@interface TGMemberAvatarStore ()
@property (nonatomic, strong) TGImageLruCache *photos;
/// Key -> the completions waiting on that key's single download.
@property (nonatomic, strong) NSMutableDictionary *waiting;
@end

@implementation TGMemberAvatarStore

+ (instancetype)shared {
	static TGMemberAvatarStore *one;
	static dispatch_once_t once;
	dispatch_once(&once, ^{ one = [[TGMemberAvatarStore alloc] init]; });
	return one;
}

- (instancetype)init {
	if ((self = [super init])){
		_photos = [[TGImageLruCache alloc] initWithCapacity:120];
		_waiting = [NSMutableDictionary dictionary];
		// The cache is a convenience, never the only copy: everything in it
		// can be downloaded again.
		__weak typeof(self) weakSelf = self;
		[[NSNotificationCenter defaultCenter]
				addObserverForName:UIApplicationDidReceiveMemoryWarningNotification
							object:nil queue:[NSOperationQueue mainQueue]
						usingBlock:^(NSNotification *note) {
			[weakSelf.photos removeAllObjects];
		}];
	}
	return self;
}

- (UIImage *)cachedAvatarForUser:(int64_t)userId side:(CGFloat)side {
	if (!userId || side <= 0)
		return nil;
	return [self.photos objectForKey:TGMemberAvatarKey(userId, side)];
}

- (void)reset {
	[self.photos removeAllObjects];
	[self.waiting removeAllObjects];
}

- (void)loadAvatarForUser:(int64_t)userId
					 side:(CGFloat)side
			   completion:(void (^)(UIImage *))completion {
	if (!userId || side <= 0){
		if (completion) completion(nil);
		return;
	}
	NSNumber *key = TGMemberAvatarKey(userId, side);
	UIImage *cached = [self.photos objectForKey:key];
	if (cached){
		if (completion) completion(cached);
		return;
	}
	// A row that scrolled back into view while the picture was still
	// arriving waits behind the first request rather than asking for it
	// again.
	NSMutableArray *queue = self.waiting[key];
	if (queue){
		if (completion) [queue addObject:[completion copy]];
		return;
	}
	queue = [NSMutableArray array];
	if (completion) [queue addObject:[completion copy]];
	self.waiting[key] = queue;

	__weak typeof(self) weakSelf = self;
	[[TGClient shared] profilePhotoFileIdForUser:userId
									  completion:^(NSNumber *fileId){
		TGMemberAvatarStore *me = weakSelf;
		if (!me)
			return;
		if (!fileId){
			[me finishKey:key image:nil];
			return;
		}
		[[TGClient shared] downloadFile:fileId.integerValue
							   priority:TGDownloadPriorityAvatar
							 completion:^(NSString *path){
			TGMemberAvatarStore *again = weakSelf;
			if (!again)
				return;
			if (!path.length){
				[again finishKey:key image:nil];
				return;
			}
			dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_BACKGROUND, 0), ^{
				UIImage *image = TGAvatarImageAtPath(path, side);
				dispatch_async(dispatch_get_main_queue(), ^{
					TGMemberAvatarStore *last = weakSelf;
					if (last)
						[last finishKey:key image:image];
				});
			});
		}];
	}];
}

/// One place where a key's waiters are answered, so a failure and a picture
/// take the same path out.
- (void)finishKey:(NSNumber *)key image:(UIImage *)image {
	if (image)
		[self.photos setObject:image forKey:key];
	NSArray *waiters = self.waiting[key];
	[self.waiting removeObjectForKey:key];
	for (void (^completion)(UIImage *) in waiters)
		completion(image);
}

@end
