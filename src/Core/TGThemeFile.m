#import "TGThemeFile.h"

//
// Theme file import. Every format here has one job: turn a third-party theme
// into an NSDictionary keyed by the importable roles listed in
// TGThemeInternal.h. Whatever a format does not provide is silently absent,
// and the built-in palettes keep answering - so extending a map is safe and
// incremental.
//
// Supported today:
//   .tgios-theme       JSON, official Telegram for iOS theme exports
//   .attheme           key=value, Telegram for Android
//   .tdesktop-palette  key: value; variable reference, Telegram for Desktop
//   .tdesktop-theme    the same palette text without an attached wallpaper zip
//
// To support a new format: add its extension to -handlesFile and write a
// paletteFrom__ function below. See docs/theme_system.md.
//
@implementation TGThemeFile

+ (BOOL)handlesFile:(NSString *)path {
	NSString *ext = path.pathExtension.lowercaseString;
	return [ext isEqualToString:@"tgios-theme"] || [ext isEqualToString:@"attheme"] ||
		   [ext isEqualToString:@"tdesktop-palette"] || [ext isEqualToString:@"tdesktop-theme"] ||
		   [ext isEqualToString:@"theme"];
}

+ (NSDictionary *)paletteFromFile:(NSString *)path name:(NSString **)name {
	NSData *data = [NSData dataWithContentsOfFile:path];
	if (!data.length)
		return nil;

	if (name)
		*name = [path.lastPathComponent stringByDeletingPathExtension];

	NSString *ext = path.pathExtension.lowercaseString;
	if ([ext isEqualToString:@"attheme"])
		return [self paletteFromAndroidTheme:data];
	if ([ext isEqualToString:@"tdesktop-palette"] || [ext isEqualToString:@"tdesktop-theme"])
		return [self paletteFromDesktopTheme:data name:name];

	// A wallpaper-carrying export is a zip, which this does not unpack.
	const unsigned char *bytes = data.bytes;
	if (data.length > 4 && bytes[0] == 'P' && bytes[1] == 'K'){
		NSLog(@"TGThemeFile: %@ is a zipped theme, not supported",
				path.lastPathComponent);
		return nil;
	}
	return [self paletteFromIOSTheme:data name:name];}

#pragma mark - Telegram for iOS (.tgios-theme)

/// "ffffff", "#ffffff", "ffffffcc" with alpha, or a gradient "aabbcc-ddeeff",
/// of which the first stop is taken - nothing here paints gradients.
static UIColor *TGColourFromHex(id value) {
	if (![value isKindOfClass:NSString.class])
		return nil;

	NSString *hex = [(NSString *)value stringByReplacingOccurrencesOfString:@"#" withString:@""];
	NSRange dash = [hex rangeOfString:@"-"];
	if (dash.location != NSNotFound)
		hex = [hex substringToIndex:dash.location];
	if (hex.length != 6 && hex.length != 8)
		return nil;

	unsigned int rgb = 0;
	if (![[NSScanner scannerWithString:[hex substringToIndex:6]] scanHexInt:&rgb])
		return nil;

	CGFloat alpha = 1.0f;
	if (hex.length == 8){
		unsigned int a = 255;
		[[NSScanner scannerWithString:[hex substringFromIndex:6]] scanHexInt:&a];
		alpha = a / 255.0f;
	}
	return [UIColor colorWithRed:((rgb >> 16) & 0xFF) / 255.0f
						   green:((rgb >> 8) & 0xFF) / 255.0f
							blue:(rgb & 0xFF) / 255.0f
						   alpha:alpha];
}

/// Follow a dotted key path, tolerating a missing branch.
static id TGDig(NSDictionary *root, NSString *path) {
	id node = root;
	for (NSString *key in [path componentsSeparatedByString:@"."]){
		if (![node isKindOfClass:NSDictionary.class])
			return nil;
		node = node[key];
	}
	return node;
}

+ (NSDictionary *)paletteFromIOSTheme:(NSData *)data name:(NSString **)name {
	NSError *err = nil;
	id json = [NSJSONSerialization JSONObjectWithData:data options:0 error:&err];
	if (![json isKindOfClass:NSDictionary.class]){
		NSLog(@"TGThemeFile: not JSON (%@)", err.localizedDescription);
		return nil;
	}
	NSDictionary *root = json;
	if (name && [root[@"name"] isKindOfClass:NSString.class])
		*name = root[@"name"];

	// The bubble sits under a wallpaper in the official client; without
	// wallpapers here, withoutWp is the closer match, with withWp as fallback.
	NSMutableDictionary *palette = [NSMutableDictionary dictionary];
	struct { NSString *key; NSString *paths; } map[] = {
		{@"bar",           @"root.navBar.background"},
		{@"barTitle",      @"root.navBar.primaryText"},
		{@"barSubtitle",   @"root.navBar.secondaryText"},
		{@"accent",        @"root.navBar.accentText|list.accent|chatList.unreadBadgeActiveBg"},
		{@"destructive",   @"list.destructiveText"},
		{@"chatBackground",@"chat.message.freeform.withoutWp.bg|list.plainBg"},
		{@"bubbleMine",    @"chat.message.outgoing.bubble.withoutWp.bg|chat.message.outgoing.bubble.withWp.bg"},
		{@"bubbleTheirs",  @"chat.message.incoming.bubble.withoutWp.bg|chat.message.incoming.bubble.withWp.bg"},
		{@"listBackground",@"chatList.bg|list.plainBg"},
		{@"primaryText",   @"chatList.title|list.primaryText"},
		{@"secondaryText", @"chatList.messageText|list.secondaryText"},
		{@"badge",         @"chatList.unreadBadgeActiveBg"},
		{@"badgeText",     @"chatList.unreadBadgeActiveText"},
		{@"mutedBadge",    @"chatList.unreadBadgeMutedBg"},
	};

	for (unsigned i = 0; i < sizeof(map) / sizeof(map[0]); i++){
		for (NSString *path in [map[i].paths componentsSeparatedByString:@"|"]){
			UIColor *colour = TGColourFromHex(TGDig(root, path));
			if (colour){
				palette[map[i].key] = colour;
				break;
			}
		}
	}

	palette[@"isDark"] = @([root[@"dark"] boolValue]);
	return palette.count > 2 ? palette : nil;
}

#pragma mark - Telegram for Android (.attheme)

/// Android writes signed decimal ARGB, so -14606047 is a colour.
static UIColor *TGColourFromSignedARGB(NSString *value) {
	long long v = [value longLongValue];
	uint32_t argb = (uint32_t)v;
	CGFloat alpha = ((argb >> 24) & 0xFF) / 255.0f;
	return [UIColor colorWithRed:((argb >> 16) & 0xFF) / 255.0f
						   green:((argb >> 8) & 0xFF) / 255.0f
							blue:(argb & 0xFF) / 255.0f
						   alpha:(alpha == 0 ? 1.0f : alpha)];
}

/// Perceived luminance of a parsed colour, for the theme's own dark guess.
static CGFloat TGLuminanceOf(UIColor *colour) {
	// getRed: is BOOL on iOS and void on newer macOS hosts, so success is
	// detected by the out-params themselves: untouched negatives mean the
	// colour is not component-based and the guess stays neutral.
	CGFloat r = -1, g = -1, b = -1, a = -1;
	[colour getRed:&r green:&g blue:&b alpha:&a];
	if (r < 0) return 0.5f;
	// Rec. 601, the cheap one; the point is only "does this theme read dark".
	return 0.299f * r + 0.587f * g + 0.114f * b;
}

+ (NSDictionary *)paletteFromAndroidTheme:(NSData *)data {
	NSString *text = [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding];
	if (!text.length)
		return nil;

	NSMutableDictionary *raw = [NSMutableDictionary dictionary];
	for (NSString *line in [text componentsSeparatedByString:@"\n"]){
		NSRange eq = [line rangeOfString:@"="];
		if (eq.location == NSNotFound)
			continue;
		NSString *key = [[line substringToIndex:eq.location]
				stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceCharacterSet]];
		NSString *value = [line substringFromIndex:eq.location + 1];
		if (key.length && value.length)
			raw[key] = value;
	}
	if (!raw.count)
		return nil;

	NSMutableDictionary *palette = [NSMutableDictionary dictionary];
	struct { NSString *key; NSString *names; } map[] = {
		{@"bar",           @"actionBarDefault"},
		{@"barTitle",      @"actionBarDefaultTitle"},
		{@"barSubtitle",   @"actionBarDefaultSubtitle"},
		{@"barButton",     @"actionBarDefaultIcon"},
		{@"accent",        @"windowBackgroundWhiteBlueText|actionBarDefaultSubtitle"},
		{@"destructive",   @"windowBackgroundWhiteRedText"},
		{@"chatBackground",@"chat_wallpaper|windowBackgroundWhite"},
		{@"bubbleMine",    @"chat_outBubble"},
		{@"bubbleTheirs",  @"chat_inBubble"},
		{@"listBackground",@"windowBackgroundWhite"},
		{@"primaryText",   @"windowBackgroundWhiteBlackText"},
		{@"secondaryText", @"windowBackgroundWhiteGrayText"},
		{@"badge",         @"chats_unreadCounter"},
		{@"badgeText",     @"chats_unreadCounterText"},
		{@"mutedBadge",    @"chats_unreadCounterMuted"},
		{@"ticks",         @"chat_outSentCheck|chat_outSentCheckRead"},
		{@"service",       @"chat_serviceBackground"},
		{@"serviceText",   @"chat_serviceText"},
		{@"groupedBackground", @"windowBackgroundGray"},
		{@"separator",     @"divider|windowBackgroundWhiteSeparator"},
	};

	for (unsigned i = 0; i < sizeof(map) / sizeof(map[0]); i++){
		for (NSString *candidate in [map[i].names componentsSeparatedByString:@"|"]){
			NSString *value = raw[candidate];
			if (value){
				palette[map[i].key] = TGColourFromSignedARGB(value);
				break;
			}
		}
	}

	// Android themes carry no explicit dark flag; guess it from the paper
	// behind the lists. Without a guess a dark .attheme would keep the built
	// in light answers for every role its map missed.
	UIColor *paper = [palette objectForKey:@"listBackground"]
			?: [palette objectForKey:@"bar"];
	palette[@"isDark"] = @(paper && TGLuminanceOf(paper) < 0.5f);
	return palette.count ? palette : nil;
}

#pragma mark - Telegram for Desktop (.tdesktop-palette)

/// Desktop values are "#rrggbb", "#rrggbbaa" (alpha last), or a reference to
/// another palette name ("color: windowBg;", which itself may chain deeper).
static UIColor *TGColourFromDesktopHex(NSString *raw) {
	NSString *hex = [(NSString *)raw stringByReplacingOccurrencesOfString:@"#"
													withString:@""];
	if (hex.length != 6 && hex.length != 8)
		return nil;
	if (hex.length == 8){
		// alpha is the trailing pair, tdesktop's "rrggbbaa" order
		NSString *rgbHex = [hex substringToIndex:6];
		unsigned int a = 255;
		[[NSScanner scannerWithString:[hex substringFromIndex:6]] scanHexInt:&a];
		unsigned int rgb = 0;
		if (![[NSScanner scannerWithString:rgbHex] scanHexInt:&rgb])
			return nil;
		return [UIColor colorWithRed:((rgb >> 16) & 0xFF) / 255.0f
							   green:((rgb >> 8) & 0xFF) / 255.0f
								blue:(rgb & 0xFF) / 255.0f
							   alpha:a / 255.0f];
	}
	unsigned int rgb = 0;
	if (![[NSScanner scannerWithString:hex] scanHexInt:&rgb])
		return nil;
	return [UIColor colorWithRed:((rgb >> 16) & 0xFF) / 255.0f
						   green:((rgb >> 8) & 0xFF) / 255.0f
							blue:(rgb & 0xFF) / 255.0f
						   alpha:1.0f];
}

+ (NSDictionary *)paletteFromDesktopTheme:(NSData *)data name:(NSString **)name {
	NSString *text = [[NSString alloc] initWithData:data
										   encoding:NSUTF8StringEncoding];
	if (!text.length){
		// a packaged .tdesktop-theme carries its wallpaper in a zip
		NSLog(@"TGThemeFile: desktop theme is not plain palette text");
		return nil;
	}

	// Key: value; pairs. Comments are stripped line-wise first, so a
	// trailing comment can never swallow the next chunk after the ';', and
	// values may name other palette entries; they resolve by lookup.
	NSMutableString *code = [NSMutableString string];
	for (NSString *line in [text componentsSeparatedByString:@"\n"]){
		[code appendString:[[line componentsSeparatedByString:@"//"] firstObject]];
		[code appendString:@"\n"];
	}
	NSString *normalised = [code stringByReplacingOccurrencesOfString:@"\n"
														   withString:@" "];
	NSMutableDictionary *entries = [NSMutableDictionary dictionary];
	for (NSString *chunk in [normalised componentsSeparatedByString:@";"]){
		NSString *trimmed = [chunk stringByTrimmingCharactersInSet:
				[NSCharacterSet whitespaceCharacterSet]];
		NSRange colon = [trimmed rangeOfString:@":"];
		if (colon.location == NSNotFound || colon.location == 0)
			continue;
		NSString *key = [trimmed substringToIndex:colon.location];
		NSString *value = [trimmed substringFromIndex:colon.location + 1];
		NSString *first = [value stringByTrimmingCharactersInSet:
				[NSCharacterSet whitespaceCharacterSet]];
		if (!key.length || !first.length || [key containsString:@"//"])
			continue;
		// a newline inside the key collapses to a space after normalisation
		NSString *plainKey = [[key componentsSeparatedByString:@" "] lastObject];
		entries[plainKey] = first;
	}
	if (!entries.count)
		return nil;

	NSMutableDictionary *palette = [NSMutableDictionary dictionary];
	struct { NSString *key; NSString *names; } map[] = {
		{@"bar",           @"topBarBg|titleBg"},
		{@"barTitle",      @"topBarFg|titleFg"},
		{@"accent",        @"windowBgActive"},
		{@"chatBackground",@"chatBg|windowBg"},
		{@"bubbleMine",    @"msgOutBg"},
		{@"bubbleTheirs",  @"msgInBg"},
		{@"listBackground",@"dialogsBg|windowBg"},
		{@"primaryText",   @"windowFg"},
		{@"secondaryText", @"windowSubTextFg"},
		{@"badge",         @"dialogsUnreadBg|sideBarBadgeBg"},
		{@"badgeText",     @"dialogsUnreadFg|sideBarBadgeFg"},
		{@"mutedBadge",    @"dialogsUnreadBgMuted|sideBarBadgeBgMuted"},
		{@"service",       @"msgServiceBg"},
		{@"serviceText",   @"msgServiceFg"},
		{@"groupedBackground", @"windowBgOver"},
	};

	// Resolve values first so a variable chain ("x: y; y: #112233;") gets its
	// colour no matter the order it was written in.
	NSMutableDictionary *colours = [NSMutableDictionary dictionary];
	for (NSString *key in entries){
		NSString *value = entries[key];
		for (unsigned hop = 0; hop < 8; hop++){
			if ([value hasPrefix:@"#"]){
				colours[key] = TGColourFromDesktopHex(value);
				break;
			}
			NSString *next = entries[value];
			if (!next.length)
				break;
			value = next;
		}
	}
	for (unsigned i = 0; i < sizeof(map) / sizeof(map[0]); i++){
		for (NSString *candidate in [map[i].names componentsSeparatedByString:@"|"]){
			UIColor *colour = colours[candidate];
			if (colour){
				palette[map[i].key] = colour;
				break;
			}
		}
	}

	UIColor *paper = [palette objectForKey:@"listBackground"];
	palette[@"isDark"] = @(paper && TGLuminanceOf(paper) < 0.5f);
	return palette.count > 2 ? palette : nil;
}

@end

// vim:ft=objc
