#import "TGTheme.h"
#import "TGThemeFile.h"
#import "TGThemeInternal.h"
#import "TGStyle.h"

#define rgb TGThemeRGB

NSString *const TGThemeChangedNotification = @"TGThemeChanged";

static NSString *const kStyleKey  = @"themeStyle";
static NSString *const kImportKey = @"themeImportPath";
static NSString *const kFontKey   = @"messageFontSize";

static NSString *const kAutoNightKey     = @"themeAutoNight";
static NSString *const kAutoNightFromKey = @"themeAutoNightFrom";
static NSString *const kAutoNightToKey   = @"themeAutoNightTo";
static NSString *const kBeforeNightKey   = @"themeStyleBeforeNight";
static NSString *const kWallpaperTypeKey = @"themeWallpaperType";

@implementation TGTheme {
	NSDictionary *_imported;
	// Built-in theme palette (e.g. Night Blue)
	NSDictionary *_builtinPalette;
	UIImage *_wallpaper;
}

+ (instancetype)shared {
	static TGTheme *s = nil;
	static dispatch_once_t once;
	dispatch_once(&once, ^{ s = [[TGTheme alloc] init]; });
	return s;
}

- (id)init {
	self = [super init];
	if (!self)
		return nil;

	NSNumber *stored = [NSUserDefaults.standardUserDefaults objectForKey:kStyleKey];
	if (stored){
		NSInteger val = stored.integerValue;
		_style = (val == TGThemeStyleDark || val == 2 || val == 3) ? TGThemeStyleDark : TGThemeStyleSkeuomorphic;
	} else {
		_style = TGThemeStyleSkeuomorphic;
	}
	NSString *imported = [NSUserDefaults.standardUserDefaults stringForKey:kImportKey];
	if (imported.length)
		[self loadImportedTheme:[TGTheme pathInDocuments:imported]];
	[self loadBuiltinPalette];
	[self applyAutoNightIfDue];
	return self;
}

#pragma mark - the theme list

- (void)loadBuiltinPalette {
	_builtinPalette = nil;
}

// Whether custom palette or imported theme is active
- (BOOL)hasCustomPalette {
	return _imported != nil || _builtinPalette != nil;
}

+ (NSArray *)availableThemes {
	NSMutableArray *themes = [@[
		@{@"id" : @"classic", @"name" : @"Classic", @"dark" : @NO},
		@{@"id" : @"night",   @"name" : @"Night",   @"dark" : @YES},
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

static NSString *TGIdForStyle(TGThemeStyle style) {
	switch (style){
		case TGThemeStyleDark: return @"night";
		default:               return @"classic";
	}
}

- (NSString *)currentThemeId {
	NSString *imported = [NSUserDefaults.standardUserDefaults stringForKey:kImportKey];
	if (_imported && imported.length)
		return [@"file:" stringByAppendingString:imported];
	return TGIdForStyle(_style);
}

- (BOOL)selectThemeId:(NSString *)themeId {
	if (![themeId isKindOfClass:NSString.class] || !themeId.length)
		return NO;

	if ([themeId hasPrefix:@"file:"]){
		NSString *name = [themeId substringFromIndex:5];
		if (![self loadImportedTheme:[TGTheme pathInDocuments:name]])
			return NO;
		_builtinPalette = nil;
		[NSUserDefaults.standardUserDefaults setObject:name forKey:kImportKey];
		[NSUserDefaults.standardUserDefaults synchronize];
		[self themeChanged];
		return YES;
	}

	TGThemeStyle style = TGThemeStyleSkeuomorphic;
	if ([themeId isEqualToString:@"night"] || [themeId isEqualToString:@"nightblue"])
		style = TGThemeStyleDark;

	// Switching style clears any active imported theme file.
	_imported = nil;
	_importedName = nil;
	[NSUserDefaults.standardUserDefaults removeObjectForKey:kImportKey];
	_style = style;
	[NSUserDefaults.standardUserDefaults setInteger:style forKey:kStyleKey];
	[NSUserDefaults.standardUserDefaults synchronize];
	[self loadBuiltinPalette];
	[self themeChanged];
	return YES;
}

- (void)themeChanged {
	[[NSNotificationCenter defaultCenter] postNotificationName:TGThemeChangedNotification
													   object:nil];
}

#pragma mark - auto-night

- (TGAutoNightMode)autoNight {
	return (TGAutoNightMode)[NSUserDefaults.standardUserDefaults integerForKey:kAutoNightKey];
}

- (void)setAutoNight:(TGAutoNightMode)mode {
	[NSUserDefaults.standardUserDefaults setInteger:mode forKey:kAutoNightKey];
	[NSUserDefaults.standardUserDefaults synchronize];
	[self applyAutoNightIfDue];
}

- (NSInteger)autoNightFromHour {
	NSNumber *stored = [NSUserDefaults.standardUserDefaults objectForKey:kAutoNightFromKey];
	return stored ? stored.integerValue : 22;
}

- (void)setAutoNightFromHour:(NSInteger)hour {
	[NSUserDefaults.standardUserDefaults setInteger:hour forKey:kAutoNightFromKey];
	[NSUserDefaults.standardUserDefaults synchronize];
	[self applyAutoNightIfDue];
}

- (NSInteger)autoNightToHour {
	NSNumber *stored = [NSUserDefaults.standardUserDefaults objectForKey:kAutoNightToKey];
	return stored ? stored.integerValue : 7;
}

- (void)setAutoNightToHour:(NSInteger)hour {
	[NSUserDefaults.standardUserDefaults setInteger:hour forKey:kAutoNightToKey];
	[NSUserDefaults.standardUserDefaults synchronize];
	[self applyAutoNightIfDue];
}

- (void)applyAutoNightIfDue {
	if (self.autoNight != TGAutoNightScheduled)
		return;

	NSInteger hour = [[[NSCalendar currentCalendar]
			components:NSHourCalendarUnit fromDate:[NSDate date]] hour];
	NSInteger from = self.autoNightFromHour, to = self.autoNightToHour;
	// The window normally crosses midnight, which is why this is an OR.
	BOOL night = (from <= to) ? (hour >= from && hour < to)
							  : (hour >= from || hour < to);

	NSUserDefaults *defaults = NSUserDefaults.standardUserDefaults;
	if (night){
		if (self.isDark)
			return;
		// Remember what to go back to, so morning does not land on whichever
		// light theme happens to be first in the list.
		[defaults setObject:[self currentThemeId] forKey:kBeforeNightKey];
		[defaults synchronize];
		[self selectThemeId:@"night"];
		return;
	}

	if (!self.isDark)
		return;
	NSString *before = [defaults stringForKey:kBeforeNightKey];
	if (!before.length)
		return;              // the user chose a dark theme themselves
	[defaults removeObjectForKey:kBeforeNightKey];
	[defaults synchronize];
	[self selectThemeId:before];
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
	NSDictionary *palette = [TGThemeFile paletteFromFile:path name:&name];
	if (!palette)
		return NO;
	_imported = palette;
	_importedName = name;
	return YES;
}

- (void)clearImportedTheme {
	[self selectThemeId:TGIdForStyle(_style)];
}

- (BOOL)isDark {
	if (_imported)
		return [_imported[@"isDark"] boolValue];
	return _style == TGThemeStyleDark;
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

// Imported color override with fallback
- (UIColor *)importedColour:(NSString *)key {
	return _imported[key] ?: _builtinPalette[key];
}

- (void)setStyle:(TGThemeStyle)style {
	if (_style == style)
		return;
	_style = style;
	[NSUserDefaults.standardUserDefaults setInteger:style forKey:kStyleKey];
	[NSUserDefaults.standardUserDefaults synchronize];
	[self loadBuiltinPalette];
	[self themeChanged];
}

// Check if flat styling is active (flat style deleted, pure skeuomorphic)
- (BOOL)isFlat {
	return NO;
}

// Built-in dark style
- (BOOL)isDarkStyle {
	return _style == TGThemeStyleDark && _imported == nil;
}

- (void)styleCell:(UITableViewCell *)cell {
	cell.textLabel.font = TGFontRow();
	cell.detailTextLabel.font = TGFontBody();
	cell.detailTextLabel.textColor = [self cellDetailColour];

	UIColor *bg = [self cardBackgroundColour];
	cell.backgroundColor = bg;
	cell.textLabel.backgroundColor = bg;
	cell.textLabel.opaque = YES;
	cell.detailTextLabel.backgroundColor = bg;
	cell.detailTextLabel.opaque = YES;

	cell.textLabel.textColor = [self primaryTextColour];
	if (![self hasCustomPalette] && !self.isDarkStyle) {
		cell.selectedBackgroundView = nil;
		return;
	}
	UIView *selected = [[UIView alloc] init];
	selected.backgroundColor = [self bubbleTheirsColour];
	cell.selectedBackgroundView = selected;
}

- (void)styleSectionHeader:(UIView *)headerView {
	if (![headerView isKindOfClass:UITableViewHeaderFooterView.class])
		return;
	UITableViewHeaderFooterView *header = (UITableViewHeaderFooterView *)headerView;
	header.textLabel.textColor = [self sectionHeaderColour];
	header.textLabel.font = TGFontCaption();
}

- (void)styleTabBar:(UITabBar *)bar {
	if (!bar)
		return;

	if ([bar respondsToSelector:@selector(setBarTintColor:)]){
		bar.translucent = NO;      // see -styleNavigationBar:
		bar.barTintColor = [self barColour];
		bar.tintColor = [self accentColour];
	} else {
		bar.tintColor = [self barColour];
	}

	UIColor *tabColor = self.isDarkStyle ? TGThemeRGB(0x22, 0x26, 0x2E) : TGThemeRGB(0x45, 0x56, 0x68);
	UIImage *tabBg = [TGTheme skeuomorphicBarImageWithColor:tabColor height:TGMetricTabBarH];
	if ([bar respondsToSelector:@selector(setBackgroundImage:)]) {
		bar.backgroundImage = tabBg;
	}
	if ([bar respondsToSelector:@selector(setSelectionIndicatorImage:)]) {
		bar.selectionIndicatorImage = [TGTheme skeuomorphicTabSelectionIndicator];
	}
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

	// barTintColor is iOS 7; on iOS 6 the bar colour is tintColor itself.
	// A dark bar needs light status-bar glyphs, which is what barStyle decides.
	bar.barStyle = self.isDark ? UIBarStyleBlack : UIBarStyleDefault;

	CGFloat barHeight = bar.bounds.size.height > 0 ? bar.bounds.size.height : TGMetricRow;
	UIImage *bgImageAttached = [TGTheme skeuomorphicBarImageWithColor:[self barColour] height:TGMetricPadWide + TGMetricRow];
	UIImage *bgImageStandard = [TGTheme skeuomorphicBarImageWithColor:[self barColour] height:barHeight];
	if ([bar respondsToSelector:@selector(setBackgroundImage:forBarPosition:barMetrics:)]) {
		[bar setBackgroundImage:bgImageAttached forBarPosition:UIBarPositionTopAttached barMetrics:UIBarMetricsDefault];
		[bar setBackgroundImage:bgImageStandard forBarPosition:UIBarPositionAny barMetrics:UIBarMetricsDefault];
	} else if ([bar respondsToSelector:@selector(setBackgroundImage:forBarMetrics:)]) {
		[bar setBackgroundImage:bgImageStandard forBarMetrics:UIBarMetricsDefault];
	}
	if ([bar respondsToSelector:@selector(setShadowImage:)]) {
		[bar setShadowImage:[[UIImage alloc] init]];
	}
	if ([bar respondsToSelector:@selector(setBarTintColor:)]) {
		bar.translucent = NO;
		bar.barTintColor = [self barColour];
		bar.tintColor = [self barButtonColour];
		NSShadow *shadow = [[NSShadow alloc] init];
		shadow.shadowColor = [self navBarTextShadowColour];
		shadow.shadowOffset = CGSizeMake(0, -1.0f);
		bar.titleTextAttributes = @{
			NSForegroundColorAttributeName : [self barTitleColour],
			NSFontAttributeName            : TGFontRowStrong(),
			NSShadowAttributeName          : shadow,
		};
	} else {
		bar.tintColor = [self barColour];
		bar.titleTextAttributes = @{ UITextAttributeTextColor : [self barTitleColour] };
	}
}

@end

// vim:ft=objc
