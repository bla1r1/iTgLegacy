#import "TGCapabilities.h"
#import <UIKit/UIKit.h>

@implementation TGCapability
@end

@implementation TGCapabilities

+ (double)systemVersion {
	static double version = 0;
	if (version == 0)
		version = [[UIDevice currentDevice].systemVersion doubleValue];
	return version;
}

+ (BOOL)is64Bit {
	return sizeof(void *) == 8;
}

+ (NSUInteger)memoryMB {
	return (NSUInteger)([NSProcessInfo processInfo].physicalMemory / (1024 * 1024));
}

+ (BOOL)canRunWebApps {
	return [self systemVersion] >= 9.0;
}

/// A Power Saving switch, defaulting to on when the user has never touched it.
static BOOL TGWanted(NSString *key) {
	NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
	return [defaults objectForKey:key] ? [defaults boolForKey:key] : YES;
}

static void TGSetWanted(NSString *key, BOOL wanted) {
	[[NSUserDefaults standardUserDefaults] setBool:wanted forKey:key];
	[[NSUserDefaults standardUserDefaults] synchronize];
}

+ (BOOL)animatedStickersWanted { return TGWanted(@"TGWantAnimatedStickers"); }
+ (void)setAnimatedStickersWanted:(BOOL)wanted {
	TGSetWanted(@"TGWantAnimatedStickers", wanted);
}
+ (BOOL)wallpaperWanted { return TGWanted(@"TGWantWallpaper"); }
+ (void)setWallpaperWanted:(BOOL)wanted {
	TGSetWanted(@"TGWantWallpaper", wanted);
}

+ (BOOL)canPlayAnimatedStickers {
	// TGLottieView does play these on an A5 - not at full speed, but it plays.
	// Custom emoji are the ones that need a newer chip, because they animate
	// inside every message rather than one at a time.
	return [TGDevice tier] >= TGDeviceTierLegacy && [self animatedStickersWanted];
}

+ (BOOL)canShowWallpaper {
	return [TGDevice tier] >= TGDeviceTierLegacy && [self wallpaperWanted];
}

+ (BOOL)canAnimateInline {
	return [TGDevice tier] >= TGDeviceTierModern;
}

+ (BOOL)canHoldMultipleAccounts {
	return [TGDevice tier] >= TGDeviceTierFull;
}

+ (BOOL)canEncodeVideoCall {
	return [TGDevice tier] >= TGDeviceTierFull;
}

/// Everything the app gates, each with what it is waiting for. The order is
/// the order a Device screen shows them in.
+ (NSArray *)all {
	NSArray *rows = @[
		@[@"Messages, media, groups", @YES,  @"every device"],
		@[@"WebP stickers",           @YES,  @"every device"],
		@[@"Voice notes",             @YES,  @"every device"],
		@[@"Chat wallpaper",          @([self canShowWallpaper]),      @"Legacy - 512MB or more"],
		@[@"Animated stickers",       @([self canPlayAnimatedStickers]), @"Legacy - 512MB or more"],
		@[@"Custom emoji",            @([self canAnimateInline]),      @"Modern - a 64-bit chip"],
		@[@"Mini apps",               @([self canRunWebApps]),         @"iOS 9 or later"],
		@[@"Multiple accounts",       @([self canHoldMultipleAccounts]), @"Full - 2GB or more"],
		@[@"Video calls",             @([self canEncodeVideoCall]),    @"Full - an A9 or later"],
	];

	NSMutableArray *out = [NSMutableArray array];
	for (NSArray *row in rows){
		TGCapability *capability = [[TGCapability alloc] init];
		capability.name = row[0];
		capability.available = [row[1] boolValue];
		capability.requirement = row[2];
		[out addObject:capability];
	}
	return out;
}

@end

// vim:ft=objc
