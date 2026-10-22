#import "TGThemeFile.h"

@implementation TGThemeFile

+ (BOOL)handlesFile:(NSString *)path {
	NSString *ext = path.pathExtension.lowercaseString;
	return [ext isEqualToString:@"tgios-theme"] || [ext isEqualToString:@"attheme"] ||
		   [ext isEqualToString:@"theme"];
}

+ (NSDictionary *)paletteFromFile:(NSString *)path name:(NSString **)name {
	NSData *data = [NSData dataWithContentsOfFile:path];
	if (!data.length)
		return nil;

	if (name)
		*name = [path.lastPathComponent stringByDeletingPathExtension];

	// A wallpaper-carrying export is a zip, which this does not unpack.
	const unsigned char *bytes = data.bytes;
	if (data.length > 4 && bytes[0] == 'P' && bytes[1] == 'K'){
		NSLog(@"TGThemeFile: %@ is a zipped theme, not supported",
				path.lastPathComponent);
		return nil;
	}

	if ([path.pathExtension.lowercaseString isEqualToString:@"attheme"])
		return [self paletteFromAndroidTheme:data];
	return [self paletteFromIOSTheme:data name:name];
}

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
		{@"accent",        @"root.navBar.accentText|list.accent|chatList.unreadBadgeActiveBg"},
		{@"chatBackground",@"chat.message.freeform.withoutWp.bg|list.plainBg"},
		{@"bubbleMine",    @"chat.message.outgoing.bubble.withoutWp.bg|chat.message.outgoing.bubble.withWp.bg"},
		{@"bubbleTheirs",  @"chat.message.incoming.bubble.withoutWp.bg|chat.message.incoming.bubble.withWp.bg"},
		{@"listBackground",@"chatList.bg|list.plainBg"},
		{@"primaryText",   @"chatList.title|list.primaryText"},
		{@"secondaryText", @"chatList.messageText|list.secondaryText"},
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
		{@"accent",        @"windowBackgroundWhiteBlueText|actionBarDefaultSubtitle"},
		{@"chatBackground",@"chat_wallpaper|windowBackgroundWhite"},
		{@"bubbleMine",    @"chat_outBubble"},
		{@"bubbleTheirs",  @"chat_inBubble"},
		{@"listBackground",@"windowBackgroundWhite"},
		{@"primaryText",   @"windowBackgroundWhiteBlackText"},
		{@"secondaryText", @"windowBackgroundWhiteGrayText"},
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
	return palette.count ? palette : nil;
}

@end

// vim:ft=objc
