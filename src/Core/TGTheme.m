#import "TGTheme.h"
#import "TGThemeFile.h"
#import "TGThemeInternal.h"

#define rgb TGThemeRGB

NSString *const TGThemeChangedNotification = @"TGThemeChanged";

static NSString *const kStyleKey  = @"themeStyle";
static NSString *const kImportKey = @"themeImportPath";
static NSString *const kFontKey   = @"messageFontSize";

static NSString *const kAutoNightKey     = @"themeAutoNight";
static NSString *const kAutoNightFromKey = @"themeAutoNightFrom";
static NSString *const kAutoNightToKey   = @"themeAutoNightTo";
static NSString *const kBeforeNightKey   = @"themeStyleBeforeNight";

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
		_style = (TGThemeStyle)stored.integerValue;
	} else {
		// NSFoundationVersionNumber_iOS_6_1 is 993.00; anything above is iOS 7+
		_style = (NSFoundationVersionNumber > 993.00)
			? TGThemeStyleFlat : TGThemeStyleSkeuomorphic;
	}
	NSString *imported = [NSUserDefaults.standardUserDefaults stringForKey:kImportKey];
	if (imported.length)
		[self loadImportedTheme:[TGTheme pathInDocuments:imported]];
	[self loadBuiltinPalette];
	[self applyAutoNightIfDue];
	return self;
}

#pragma mark - the theme list

// Telegram's Night Blue presentation palette
+ (NSDictionary *)nightBluePalette {
	static NSDictionary *palette = nil;
	if (!palette)
		palette = @{
			@"bar"            : rgb(0x21, 0x30, 0x40),
			@"barTitle"       : [UIColor whiteColor],
			@"barSubtitle"    : rgb(0x7B, 0x87, 0x90),
			@"barButton"      : rgb(0x2E, 0xA6, 0xFF),
			@"accent"         : rgb(0x2E, 0xA6, 0xFF),
			@"chatBackground" : rgb(0x18, 0x22, 0x2D),
			@"cardBackground" : rgb(0x24, 0x2F, 0x3D),
			@"bubbleMine"     : rgb(0x2B, 0x52, 0x78),
			@"bubbleTheirs"   : rgb(0x18, 0x25, 0x33),
			@"listBackground" : rgb(0x17, 0x21, 0x2B),
			@"primaryText"    : [UIColor whiteColor],
			@"secondaryText"  : rgb(0x7B, 0x87, 0x90),
			@"isDark"         : @YES,
		};
	return palette;
}

- (void)loadBuiltinPalette {
	_builtinPalette = (_style == TGThemeStyleNightBlue)
			? [TGTheme nightBluePalette] : nil;
}

// Whether custom palette or imported theme is active
- (BOOL)hasCustomPalette {
	return _imported != nil || _builtinPalette != nil;
}

+ (NSArray *)availableThemes {
	NSMutableArray *themes = [@[
		@{@"id" : @"classic",   @"name" : @"Classic",    @"dark" : @NO},
		@{@"id" : @"day",       @"name" : @"Day",        @"dark" : @NO},
		@{@"id" : @"night",     @"name" : @"Night",      @"dark" : @YES},
		@{@"id" : @"nightblue", @"name" : @"Night Blue", @"dark" : @YES},
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
		case TGThemeStyleFlat:      return @"day";
		case TGThemeStyleDark:      return @"night";
		case TGThemeStyleNightBlue: return @"nightblue";
		default:                    return @"classic";
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
	if ([themeId isEqualToString:@"day"])            style = TGThemeStyleFlat;
	else if ([themeId isEqualToString:@"night"])     style = TGThemeStyleDark;
	else if ([themeId isEqualToString:@"nightblue"]) style = TGThemeStyleNightBlue;

	// A file and a style are one choice, so picking a style drops the file -
	// and both used to post their own notification, which repainted twice.
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
	return _style == TGThemeStyleDark || _style == TGThemeStyleNightBlue;
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

// Check if flat styling is active
- (BOOL)isFlat {
	if (_imported)
		return YES;
	return _style != TGThemeStyleSkeuomorphic;
}

// Built-in dark style
- (BOOL)isDarkStyle {
	return (_style == TGThemeStyleDark || _style == TGThemeStyleNightBlue) &&
		   _imported == nil;
}

- (void)styleCell:(UITableViewCell *)cell {
	cell.textLabel.font = [UIFont systemFontOfSize:15];
	cell.detailTextLabel.font = [UIFont systemFontOfSize:15];
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
}

#pragma mark - wallpaper

- (NSString *)wallpaperPath {
	NSString *documents = [NSSearchPathForDirectoriesInDomains(
			NSDocumentDirectory, NSUserDomainMask, YES) firstObject];
	return [documents stringByAppendingPathComponent:@"wallpaper.jpg"];
}

- (UIImage *)wallpaper {
	if (!_wallpaper)
		_wallpaper = [UIImage imageWithContentsOfFile:[self wallpaperPath]];
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
	} else {
		[[NSFileManager defaultManager] removeItemAtPath:path error:nil];
	}
	_wallpaper = image;
	[[NSNotificationCenter defaultCenter] postNotificationName:TGThemeChangedNotification
													   object:nil];
}



- (void)styleNavigationBar:(UINavigationBar *)bar {
	if (!bar)
		return;

	// barTintColor is iOS 7; on iOS 6 the bar colour is tintColor itself.
	// A dark bar needs light status-bar glyphs, which is what barStyle decides.
	bar.barStyle = self.isDark ? UIBarStyleBlack : UIBarStyleDefault;

	if ([bar respondsToSelector:@selector(setBarTintColor:)]){
		// A translucent bar blends with whatever is behind it, which turns a
		// dark bar pale. Anything dark gets an opaque bar.
		// Opaque, always. iOS 7 builds a bar's backdrop when translucency is
		// switched on and then keeps it: turning it on during a theme change
		// left the bar painted in the theme before last, whatever it was asked
		// to redraw afterwards. Nothing scrolls under a bar here anyway - every
		// screen sets edgesForExtendedLayout to none - so translucency was only
		// ever costing a blur nobody sees.
		bar.translucent = NO;
		bar.barTintColor = [self barColour];
		bar.tintColor = [self barButtonColour];
		// The settings bar is short, so the title has to be too or it sits with
		// its descenders against the hairline.
		bar.titleTextAttributes = @{
			NSForegroundColorAttributeName : [self barTitleColour],
			NSFontAttributeName            : [UIFont boldSystemFontOfSize:16],
		};
	} else {
		bar.tintColor = [self barColour];
		bar.titleTextAttributes = @{ UITextAttributeTextColor : [self barTitleColour] };
	}
}

@end

// vim:ft=objc
