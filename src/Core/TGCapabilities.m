#import "TGCapabilities.h"
#import <UIKit/UIKit.h>
#import <CoreText/CoreText.h>

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
+ (BOOL)gifAutoplayWanted { return TGWanted(@"TGWantGifAutoplay"); }
+ (void)setGifAutoplayWanted:(BOOL)wanted {
	TGSetWanted(@"TGWantGifAutoplay", wanted);
}

+ (BOOL)canPlayAnimatedStickers {
	// TGLottieView does play these on an A5 - not at full speed, but it plays.
	// Single-core chips (A4) choke on parallel vector rendering.
	if ([NSProcessInfo processInfo].processorCount < 2)
		return NO;
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
	// Video calls require 64-bit hardware (A7+), hardware VideoToolbox
	// available cleanly on iOS 9+, and at least 2GB of RAM to prevent jetsam.
	return [self is64Bit] && [self systemVersion] >= 9.0 && [TGDevice tier] >= TGDeviceTierFull;
}

+ (BOOL)canAutoplayGIFs {
	return [TGDevice tier] >= TGDeviceTierLegacy && [self gifAutoplayWanted];
}

+ (NSUInteger)maxConcurrentGIFs {
	switch ([TGDevice tier]){
		case TGDeviceTierVintage: return 0;
		case TGDeviceTierLegacy:  return 2;
		case TGDeviceTierModern:  return 3;
		case TGDeviceTierFull:    return 4;
	}
	return 2;
}

+ (BOOL)canSwipeRowActions {
	return NSClassFromString(@"UITableViewRowAction") != nil;
}

+ (BOOL)canShowRecentPhotos {
	return [TGDevice tier] >= TGDeviceTierLegacy;
}

/// iOS 7's typesetter segfaults outright when it meets a character the emoji
/// font has no glyph for - 🏳️ (U+1F3F3) is one - so ask the font directly
/// before handing anything to CTLine. Selectors and joiners carry no glyph of
/// their own, and a surrogate pair answers on its lead unit.
static BOOL TGEmojiFontHasGlyphs(CTFontRef font, NSString *s) {
	NSUInteger len = s.length;
	if (!len || len > 64)
		return NO;
	unichar buf[64];
	[s getCharacters:buf range:NSMakeRange(0, len)];
	for (NSUInteger i = 0; i < len; i++){
		unichar c = buf[i];
		if (c == 0xFE0E || c == 0xFE0F || c == 0x200D)
			continue;
		unichar pair[2] = { c, 0 };
		CFIndex n = 1;
		if (c >= 0xD800 && c <= 0xDBFF && i + 1 < len){
			pair[1] = buf[++i];
			n = 2;
		}
		CGGlyph glyphs[2] = { 0, 0 };
		CTFontGetGlyphsForCharacters(font, pair, glyphs, n);
		if (glyphs[0] == 0)
			return NO;
	}
	return YES;
}

+ (BOOL)canDrawEmoji:(NSString *)emoji {
	if (!emoji.length)
		return NO;
	static NSMutableDictionary *answers = nil;
	static CTFontRef font = NULL;
	if (!answers){
		answers = [NSMutableDictionary dictionary];
		font = CTFontCreateWithName(CFSTR("AppleColorEmoji"), 20, NULL);
	}
	NSNumber *known = answers[emoji];
	if (known)
		return known.boolValue;

	// Asking for each character's glyph is not enough: a flag is two letters
	// the font has on their own, and an unknown flag or joined sequence still
	// "draws" - as two boxes or a family taken apart. Shaping the whole thing
	// and wanting one glyph from the emoji font itself is what the screen
	// will actually show.
	BOOL ok = NO;
	if (font && TGEmojiFontHasGlyphs(font, emoji)){
		NSAttributedString *text = [[NSAttributedString alloc] initWithString:emoji
				attributes:@{(__bridge NSString *)kCTFontAttributeName : (__bridge id)font}];
		CTLineRef line = CTLineCreateWithAttributedString((__bridge CFAttributedStringRef)text);
		if (line){
			CFArrayRef runs = CTLineGetGlyphRuns(line);
			if (CFArrayGetCount(runs) == 1){
				CTRunRef run = (CTRunRef)CFArrayGetValueAtIndex(runs, 0);
				CTFontRef used = (CTFontRef)CFDictionaryGetValue(CTRunGetAttributes(run), kCTFontAttributeName);
				NSString *name = used ? (__bridge_transfer NSString *)CTFontCopyPostScriptName(used) : nil;
				CGGlyph glyph = 0;
				if (CTRunGetGlyphCount(run) == 1)
					CTRunGetGlyphs(run, CFRangeMake(0, 1), &glyph);
				ok = glyph != 0 && [name isEqualToString:@"AppleColorEmoji"];
			}
			CFRelease(line);
		}
	}
	answers[emoji] = @(ok);
	return ok;
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
		@[@"GIF autoplay",            @([self canAutoplayGIFs]),       @"Legacy - an A5 or later"],
		@[@"Recent photos in attach", @([self canShowRecentPhotos]),   @"Legacy - 512MB or more"],
		@[@"Swipe actions in chats",  @([self canSwipeRowActions]),    @"iOS 8 or later"],
		@[@"Custom emoji",            @([self canAnimateInline]),      @"Modern - a 64-bit chip"],
		@[@"Mini apps",               @([self canRunWebApps]),         @"iOS 9 or later"],
		@[@"Multiple accounts",       @([self canHoldMultipleAccounts]), @"Full - 2GB or more"],
		@[@"Video calls",             @([self canEncodeVideoCall]),    @"Full - 64-bit, iOS 9+, 2GB+"],
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
