#import "TGTheme.h"
#import "TGThemeFile.h"
#import "TGIcons.h"
#import "TGThemeInternal.h"
#import "TGStyle.h"

#define rgb TGThemeRGB

NSString *const TGThemeChangedNotification = @"TGThemeChanged";

static NSString *const kStyleKey  = @"themeStyle";
static NSString *const kImportKey = @"themeImportPath";
static NSString *const kFontKey   = @"messageFontSize";

static NSString *const kWallpaperTypeKey = @"themeWallpaperType";

@implementation TGTheme {
	NSDictionary *_imported;
	UIImage *_wallpaper;
}

+ (instancetype)shared {
	static TGTheme *s = nil;
	static dispatch_once_t once;
	dispatch_once(&once, ^{ s = [[TGTheme alloc] init]; });
	return s;
}

+ (BOOL)drawsSkeuomorphicChrome {
	static BOOL draws;
	static dispatch_once_t once;
	dispatch_once(&once, ^{
		draws = NSFoundationVersionNumber <= NSFoundationVersionNumber_iOS_6_1;
	});
	return draws;
}

- (id)init {
	self = [super init];
	if (!self)
		return nil;

	// Night is gone; a stored Night, or a dark theme file, comes back light.
	[NSUserDefaults.standardUserDefaults removeObjectForKey:kStyleKey];
	NSString *imported = [NSUserDefaults.standardUserDefaults stringForKey:kImportKey];
	if (imported.length)
		[self loadImportedTheme:[TGTheme pathInDocuments:imported]];
	return self;
}

#pragma mark - the theme list

+ (NSArray *)availableThemes {
	NSMutableArray *themes = [@[
		@{@"id" : @"classic", @"name" : @"Classic", @"dark" : @NO},
	] mutableCopy];

	for (NSString *path in [self availableThemeFiles]){
		NSString *name = [path.lastPathComponent stringByDeletingPathExtension];
		[themes addObject:@{
			@"id"   : [@"file:" stringByAppendingString:path.lastPathComponent],
			@"name" : name,
			@"dark" : @NO,          // only known once the file has been read
			@"path" : path,
		}];
	}
	return themes;
}

- (NSString *)currentThemeId {
	NSString *imported = [NSUserDefaults.standardUserDefaults stringForKey:kImportKey];
	if (_imported && imported.length)
		return [@"file:" stringByAppendingString:imported];
	return @"classic";
}

- (BOOL)selectThemeId:(NSString *)themeId {
	if (![themeId isKindOfClass:NSString.class] || !themeId.length)
		return NO;

	if ([themeId hasPrefix:@"file:"]){
		NSString *name = [themeId substringFromIndex:5];
		if (![self loadImportedTheme:[TGTheme pathInDocuments:name]])
			return NO;
		[NSUserDefaults.standardUserDefaults setObject:name forKey:kImportKey];
		[NSUserDefaults.standardUserDefaults synchronize];
		[self themeChanged];
		return YES;
	}

	// Anything else is Classic: clear the imported file.
	_imported = nil;
	_importedName = nil;
	[NSUserDefaults.standardUserDefaults removeObjectForKey:kImportKey];
	[NSUserDefaults.standardUserDefaults synchronize];
	[self themeChanged];
	return YES;
}

- (void)themeChanged {
	[[NSNotificationCenter defaultCenter] postNotificationName:TGThemeChangedNotification
													   object:nil];
}

- (CGFloat)messageFontSize {
	CGFloat stored = [NSUserDefaults.standardUserDefaults floatForKey:kFontKey];
	return stored > 0 ? stored : 15.0f;
}

- (void)setMessageFontSize:(CGFloat)size {
	[NSUserDefaults.standardUserDefaults setFloat:size forKey:kFontKey];
	[NSUserDefaults.standardUserDefaults synchronize];
	[[NSNotificationCenter defaultCenter] postNotificationName:TGThemeChangedNotification
													   object:nil];
}

#pragma mark - imported themes

// Store file name only to survive container path changes across reinstall
- (BOOL)importThemeAtPath:(NSString *)path {
	return [self selectThemeId:
			[@"file:" stringByAppendingString:path.lastPathComponent]];
}

+ (NSString *)pathInDocuments:(NSString *)name {
	NSString *documents = [NSSearchPathForDirectoriesInDomains(
			NSDocumentDirectory, NSUserDomainMask, YES) firstObject];
	return [documents stringByAppendingPathComponent:name.lastPathComponent];
}

- (BOOL)loadImportedTheme:(NSString *)path {
	NSString *name = nil;
	NSDictionary *palette = [TGThemeFile chatPaletteFromFile:path name:&name];
	if (!palette)
		return NO;
	_imported = palette;
	_importedName = name;
	return YES;
}

- (void)clearImportedTheme {
	[self selectThemeId:@"classic"];
}

+ (NSArray *)availableThemeFiles {
	NSString *documents = [NSSearchPathForDirectoriesInDomains(
			NSDocumentDirectory, NSUserDomainMask, YES) firstObject];
	NSMutableArray *found = [NSMutableArray array];
	for (NSString *entry in [[NSFileManager defaultManager]
			contentsOfDirectoryAtPath:documents error:nil]){
		NSString *path = [documents stringByAppendingPathComponent:entry];
		if ([TGThemeFile handlesFile:path])
			[found addObject:path];
	}
	return found;
}

- (UIColor *)importedColour:(NSString *)key {
	return _imported[key];
}

+ (UITableViewCell *)systemCellOfStyle:(UITableViewCellStyle)style {
	static UITableViewCell *cells[4];
	if (style < 0 || style > 3)
		style = UITableViewCellStyleDefault;
	if (!cells[style])
		cells[style] = [[UITableViewCell alloc] initWithStyle:style reuseIdentifier:nil];
	return cells[style];
}

- (void)styleCell:(UITableViewCell *)cell {
	// UIKit's own cell: its fonts and colours, and labels it can highlight -
	// opaque white ones showed as boxes on the blue selection.
	UITableViewCell *system = [TGTheme systemCellOfStyle:UITableViewCellStyleValue1];
	cell.textLabel.font = system.textLabel.font;
	cell.textLabel.textColor = system.textLabel.textColor;
	cell.detailTextLabel.font = system.detailTextLabel.font;
	cell.detailTextLabel.textColor = system.detailTextLabel.textColor;
	cell.textLabel.backgroundColor = [UIColor clearColor];
	cell.detailTextLabel.backgroundColor = [UIColor clearColor];
	cell.textLabel.opaque = NO;
	cell.detailTextLabel.opaque = NO;
	cell.selectedBackgroundView = nil;
}

/// A search bar as the OS draws one: grey on iOS 6, light on 7, nothing of
/// ours painted on it. A dark or imported theme gets the black style and
/// its own colours.
- (void)styleSearchBar:(UISearchBar *)bar {
	if ([bar respondsToSelector:@selector(setBackgroundImage:)])
		[bar setBackgroundImage:nil];
	bar.barStyle = UIBarStyleDefault;
	bar.tintColor = nil;
	if ([bar respondsToSelector:@selector(setBarTintColor:)])
		bar.barTintColor = nil;
}

/// A grouped table as UIKit draws it on the OS it runs on - iOS 6's
/// pinstripes and rounded cards, iOS 7's grey sheet - with only the colours
/// changed on a dark or imported theme.
- (void)styleGroupedTable:(UITableView *)table {
	// The system's own background view draws iOS 6's pinstripes; a pattern
	// colour on a view of ours came out black.
	table.separatorStyle = UITableViewCellSeparatorStyleSingleLine;
}

- (void)styleTabBar:(UITabBar *)bar {
	if (!bar)
		return;

	// iOS 6's own tab bar: black glass and the blue glow on the selected
	// item, the look every app on the phone around this one has.
	if ([TGTheme drawsSkeuomorphicChrome]) {
		// The system tab bar tinted the slate blue of the system nav bar, so
		// the top and bottom of the screen are one colour.
		bar.tintColor = [self systemBarBlueColour];
		if ([bar respondsToSelector:@selector(setBackgroundImage:)])
			bar.backgroundImage = nil;
		if ([bar respondsToSelector:@selector(setSelectionIndicatorImage:)])
			bar.selectionIndicatorImage = nil;
		// On the blue bar the system's grey glyphs went dark; they are drawn
		// white instead - full for the selected tab, faded for the rest.
		for (UITabBarItem *item in bar.items) {
			UIImage *mask = item.image;
			if (!mask || ![item respondsToSelector:@selector(setFinishedSelectedImage:withFinishedUnselectedImage:)])
				continue;
			UIColor *off = [UIColor colorWithWhite:1.0f alpha:TGAlphaSecondary];
			[item setFinishedSelectedImage:[TGIcons image:mask filledWith:[UIColor whiteColor]]
			   withFinishedUnselectedImage:[TGIcons image:mask filledWith:off]];
			[item setTitleTextAttributes:@{UITextAttributeTextColor : off}
								forState:UIControlStateNormal];
			[item setTitleTextAttributes:@{UITextAttributeTextColor : [UIColor whiteColor]}
								forState:UIControlStateSelected];
		}
		return;
	}

	if ([bar respondsToSelector:@selector(setBarTintColor:)]){
		bar.translucent = NO;      // see -styleNavigationBar:
		bar.barTintColor = [self barColour];
		bar.tintColor = [self accentColour];
	} else {
		bar.tintColor = [self barColour];
	}

	// Their own bar from 7 on as well: no painted plate, no glow indicator.
	if ([bar respondsToSelector:@selector(setBackgroundImage:)])
		bar.backgroundImage = nil;
	if ([bar respondsToSelector:@selector(setSelectionIndicatorImage:)])
		bar.selectionIndicatorImage = nil;
}

#pragma mark - wallpaper

- (NSString *)wallpaperPath {
	NSString *documents = [NSSearchPathForDirectoriesInDomains(
			NSDocumentDirectory, NSUserDomainMask, YES) firstObject];
	return [documents stringByAppendingPathComponent:@"wallpaper.jpg"];
}

- (TGWallpaperType)wallpaperType {
	NSNumber *stored = [NSUserDefaults.standardUserDefaults objectForKey:kWallpaperTypeKey];
	if (stored) {
		return (TGWallpaperType)stored.integerValue;
	}
	if ([[NSFileManager defaultManager] fileExistsAtPath:[self wallpaperPath]]) {
		return TGWallpaperTypeCustom;
	}
	return TGWallpaperTypeNone;
}

- (void)setWallpaperType:(TGWallpaperType)type {
	_wallpaper = nil;
	[NSUserDefaults.standardUserDefaults setInteger:type forKey:kWallpaperTypeKey];
	[NSUserDefaults.standardUserDefaults synchronize];
	if (type != TGWallpaperTypeCustom) {
		[[NSFileManager defaultManager] removeItemAtPath:[self wallpaperPath] error:nil];
	}
	[[NSNotificationCenter defaultCenter] postNotificationName:TGThemeChangedNotification object:nil];
}

- (NSString *)wallpaperTitleForType:(TGWallpaperType)type {
	switch (type) {
		case TGWallpaperTypeNone: return @"None (Solid)";
		case TGWallpaperTypePaperGrain: return @"Paper Grain";
		case TGWallpaperTypePinstripes: return @"Pinstripes";
		case TGWallpaperTypeLinen: return @"Classic Linen";
		case TGWallpaperTypeParchment: return @"Parchment";
		case TGWallpaperTypeFelt: return @"Game Center Felt";
		case TGWallpaperTypeCustom: return @"Photo Library";
	}
	return @"None";
}

- (UIImage *)wallpaper {
	if (_wallpaper)
		return _wallpaper;
	TGWallpaperType type = [self wallpaperType];
	if (type == TGWallpaperTypeNone)
		return nil;
	if (type == TGWallpaperTypeCustom) {
		_wallpaper = [UIImage imageWithContentsOfFile:[self wallpaperPath]];
		return _wallpaper;
	}
	_wallpaper = [TGTheme textureImageForType:type];
	return _wallpaper;
}

- (void)setWallpaperImage:(UIImage *)image {
	NSString *path = [self wallpaperPath];
	if (image){
		// Scaled down first: a full camera frame behind every chat is megabytes
		// of memory on a device that has 512.
		CGFloat maxSide = 640;
		CGFloat scale = MIN(1.0f, maxSide / MAX(image.size.width, image.size.height));
		if (scale < 1.0f){
			CGSize size = CGSizeMake(image.size.width * scale, image.size.height * scale);
			UIGraphicsBeginImageContextWithOptions(size, YES, 1);
			[image drawInRect:CGRectMake(0, 0, size.width, size.height)];
			image = UIGraphicsGetImageFromCurrentImageContext();
			UIGraphicsEndImageContext();
		}
		[UIImageJPEGRepresentation(image, 0.8f) writeToFile:path atomically:YES];
		_wallpaper = image;
		[NSUserDefaults.standardUserDefaults setInteger:TGWallpaperTypeCustom forKey:kWallpaperTypeKey];
	} else {
		[[NSFileManager defaultManager] removeItemAtPath:path error:nil];
		_wallpaper = nil;
		[NSUserDefaults.standardUserDefaults setInteger:TGWallpaperTypeNone forKey:kWallpaperTypeKey];
	}
	[NSUserDefaults.standardUserDefaults synchronize];
	[[NSNotificationCenter defaultCenter] postNotificationName:TGThemeChangedNotification
													   object:nil];
}



- (void)styleNavigationBar:(UINavigationBar *)bar {
	if (!bar)
		return;

	bar.barStyle = UIBarStyleDefault;

	// iOS 6 draws its own bar: tinted, it is the real gloss, edge and shadow,
	// and its Back and Done buttons match it because they come from the same
	// place. The procedural imitation below was close, never the same.
	if ([TGTheme drawsSkeuomorphicChrome]) {
		if ([bar respondsToSelector:@selector(setBackgroundImage:forBarMetrics:)])
			[bar setBackgroundImage:nil forBarMetrics:UIBarMetricsDefault];
		if ([bar respondsToSelector:@selector(setShadowImage:)])
			[bar setShadowImage:nil];
		// No tint at all: iOS 6's own slate-blue bar and white title. A pale
		// theme tint made it read as not quite iOS.
		bar.tintColor = nil;
		bar.titleTextAttributes = nil;
		return;
	}

	// iOS 7 and later: their flat bar, its hairline and their title font. The
	// iOS 6 gloss painted over it here looked foreign on every later system.
	if ([bar respondsToSelector:@selector(setBackgroundImage:forBarMetrics:)])
		[bar setBackgroundImage:nil forBarMetrics:UIBarMetricsDefault];
	if ([bar respondsToSelector:@selector(setShadowImage:)])
		[bar setShadowImage:nil];
	bar.translucent = NO;
	bar.barTintColor = [self barColour];
	bar.tintColor = [self barButtonColour];
	bar.titleTextAttributes = @{ NSForegroundColorAttributeName : [self barTitleColour] };
}

@end

// vim:ft=objc
