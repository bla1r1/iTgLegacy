#import "TGTheme.h"
#import "TGThemeFile.h"

NSString *const TGThemeChangedNotification = @"TGThemeChanged";

static NSString *const kStyleKey  = @"themeStyle";
static NSString *const kImportKey = @"themeImportPath";
static NSString *const kFontKey   = @"messageFontSize";

static UIColor *rgb(int r, int g, int b);   // defined with the palette below

static NSString *const kAutoNightKey     = @"themeAutoNight";
static NSString *const kAutoNightFromKey = @"themeAutoNightFrom";
static NSString *const kAutoNightToKey   = @"themeAutoNightTo";
static NSString *const kBeforeNightKey   = @"themeStyleBeforeNight";

@implementation TGTheme {
	NSDictionary *_imported;
	/// A built-in theme that is expressed as a palette rather than as branches
	/// in every accessor. Night Blue is the first; adding another is a
	/// dictionary, not twenty more `if`s.
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

/// Telegram's Night Blue, by the colours their nightBluePresentationTheme uses.
+ (NSDictionary *)nightBluePalette {
	static NSDictionary *palette = nil;
	if (!palette)
		palette = @{
			@"bar"            : rgb(0x21, 0x30, 0x40),
			@"barTitle"       : [UIColor whiteColor],
			@"accent"         : rgb(0x2E, 0xA6, 0xFF),
			@"chatBackground" : rgb(0x18, 0x22, 0x2D),
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

/// An imported file wins over a built-in palette, which wins over the style's
/// own defaults. Everything undefined falls through, so a partial theme works.
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

/// Kept for anything that has a path rather than an id. Only the file name is
/// stored: the container path changes on every reinstall, and an absolute one
/// saved across that points at a directory that is gone.
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

/// An imported colour wins over the built-in style; anything the file did not
/// define falls through, so a partial theme still works.
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

/// Dark is flat drawn on dark surfaces, so everything that asks "flat?" to
/// decide whether to draw a bevel gets the same answer for both.
- (BOOL)isFlat {
	// An imported theme brings flat colours whatever style was underneath, so
	// a bevel drawn from a stale skeuomorphic style was the one thing that
	// still looked wrong after importing one.
	if (_imported)
		return YES;
	return _style != TGThemeStyleSkeuomorphic;
}

/// The built-in dark style, which an imported theme overrides colour by colour.
- (BOOL)isDarkStyle {
	return (_style == TGThemeStyleDark || _style == TGThemeStyleNightBlue) &&
		   _imported == nil;
}

- (void)styleCell:(UITableViewCell *)cell {
	// Their settings row: 15/18 title in black, the value beside it in blue.
	cell.textLabel.font = [UIFont systemFontOfSize:15];
	cell.detailTextLabel.font = [UIFont systemFontOfSize:15];
	cell.detailTextLabel.textColor = [self cellDetailColour];

	// Every branch assigns both, because cells are reused across a theme
	// change: returning early left a dark background and a dark selection view
	// on a cell that a light theme then drew black text into.
	if (![self hasCustomPalette] && !self.isDarkStyle){
		cell.backgroundColor = [UIColor whiteColor];
		cell.textLabel.textColor = [UIColor blackColor];
		cell.selectedBackgroundView = nil;
		return;
	}
	cell.backgroundColor = [self listBackgroundColour];
	cell.textLabel.textColor = [self primaryTextColour];
	// A selection flash of white would be worse than none.
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

#pragma mark - palette

static UIColor *rgb(int r, int g, int b) {
	return [UIColor colorWithRed:r/255.0f green:g/255.0f blue:b/255.0f alpha:1.0f];
}

// Telegram's own palette, read out of their design system file. The names are
// theirs. The file is drawn for Android at 360dp; the colours carry over
// unchanged, the metrics are scaled to a 320pt screen where they appear.
#define TG_BLUE_DARK4     rgb(0x51, 0x7D, 0xA2)   // the classic header blue
#define TG_BLUE_LIGHT4    rgb(0x4C, 0xB3, 0xF5)   // send button, links
#define TG_BLUE_MEDIUM8   rgb(0x3D, 0x95, 0xD4)   // unread badge
#define TG_GREEN_LIGHT1   rgb(0xEF, 0xFE, 0xDD)   // outgoing bubble
#define TG_GREEN_BRIGHT1  rgb(0x5A, 0xCD, 0x30)   // online dot, ticks
#define TG_GRAY_LIGHT3    rgb(0xF7, 0xF7, 0xF7)   // bars, input strip
#define TG_STEEL_LIGHT1   rgb(0xED, 0xEE, 0xF0)   // chat background
#define TG_STEEL_LIGHT3   rgb(0xE1, 0xE4, 0xE9)   // separators
#define TG_TEXT_PRIMARY   rgb(0x22, 0x22, 0x22)
#define TG_TEXT_SECONDARY rgb(0x8D, 0x8E, 0x90)
#define TG_TEXT_TIME      rgb(0x95, 0x99, 0x9A)
#define TG_BLUE_SEMI8     rgb(0x51, 0xAE, 0xE7)   // the value on a settings row
#define TG_GRAY_SECTION   rgb(0x69, 0x6A, 0x6F)   // a section caption
#define TG_BLUE_DARK3     rgb(0x5A, 0x8E, 0xBD)   // behind a profile picture
#define TG_BLUE_MEDIUM2   rgb(0x5E, 0xA7, 0xDE)   // the record button
#define TG_BLUE_BLURPLE3  rgb(0x70, 0xAA, 0xEA)   // "typing..." in the chat list
#define TG_STEEL_LIGHT6   rgb(0xC5, 0xC9, 0xCC)   // a muted chat's badge
#define TG_STEEL_LIGHT13  rgb(0xA1, 0xAA, 0xB3)   // size and type under a file
#define TG_FILE_TILE      rgb(0xEB, 0xF0, 0xF4)   // the square behind a file glyph
#define TG_MEDIA_CIRCLE   rgb(0x72, 0xB5, 0xE9)   // the disc inside it
#define TG_FILE_NAME      rgb(0x4E, 0x9A, 0xD4)

// The dark half of their palette, read from the same file. Their greys are
// numbered from light to dark, so the surfaces a dark theme needs are the tail
// of gray_dark and the middle of steel-gray.
#define TG_GRAY_DARK16    rgb(0x20, 0x20, 0x20)   // bars
#define TG_GRAY_DARK15    rgb(0x21, 0x21, 0x21)   // lists
#define TG_GRAY_DARK14    rgb(0x23, 0x23, 0x23)   // chat background
#define TG_GRAY_DARK13    rgb(0x33, 0x33, 0x33)   // incoming bubble, separators
#define TG_GRAY_DARK6     rgb(0x99, 0x99, 0x99)   // secondary text
#define TG_STEEL_DARK13   rgb(0x7D, 0x84, 0x8A)   // the stamp in a dark bubble
#define TG_BLUE_DARK6     rgb(0x1B, 0x5A, 0x7D)   // outgoing bubble when dark

- (UIColor *)barColour {
	UIColor *imported = [self importedColour:@"bar"];
	if (imported) return imported;
	if (self.isDarkStyle) return TG_GRAY_DARK16;
	return self.isFlat ? TG_GRAY_LIGHT3 : TG_BLUE_DARK4;
}


- (UIColor *)barTitleColour {
	UIColor *imported = [self importedColour:@"barTitle"];
	if (imported) return imported;
	if (self.isDarkStyle) return [UIColor whiteColor];
	return self.isFlat ? TG_TEXT_PRIMARY : [UIColor whiteColor];
}


- (UIColor *)accentColour {
	UIColor *imported = [self importedColour:@"accent"];
	if (imported) return imported;
	if (self.isDarkStyle) return TG_BLUE_LIGHT4;
	return self.isFlat ? TG_BLUE_LIGHT4 : TG_BLUE_DARK4;
}


- (UIColor *)chatBackgroundColour {
	UIColor *imported = [self importedColour:@"chatBackground"];
	if (imported) return imported;
	if (self.isDarkStyle) return TG_GRAY_DARK14;
	return self.isFlat ? TG_STEEL_LIGHT1 : rgb(217, 222, 212);
}


- (UIColor *)bubbleMineColour {
	UIColor *imported = [self importedColour:@"bubbleMine"];
	if (imported) return imported;
	// Their pale green would glow on a dark surface; blue_dark6 is the darkest
	// blue they draw, and it is what the outgoing bubble becomes.
	if (self.isDarkStyle) return TG_BLUE_DARK6;
	return TG_GREEN_LIGHT1;
}


- (UIColor *)bubbleTheirsColour {
	UIColor *imported = [self importedColour:@"bubbleTheirs"];
	if (imported) return imported;
	if (self.isDarkStyle) return TG_GRAY_DARK13;
	return [UIColor whiteColor];
}


- (UIColor *)bubbleBorderColour {
	// A drawn edge is what makes a skeuomorphic bubble sit on the surface;
	// flat bubbles have none at all.
	// black_alpha12 in their palette, and it applies to both styles: their
	// bubbles carry a hairline whatever the era. On a dark surface a black
	// hairline is invisible, so it turns into a faint white one.
	if (self.isDarkStyle)
		return [UIColor colorWithWhite:1.0f alpha:0.08f];
	return [UIColor colorWithWhite:0.0f alpha:0.12f];
}

- (UIColor *)listBackgroundColour {
	UIColor *imported = [self importedColour:@"listBackground"];
	if (imported) return imported;
	if (self.isDarkStyle) return TG_GRAY_DARK15;
	return [UIColor whiteColor];
}


- (UIColor *)groupedBackgroundColour {
	UIColor *imported = [self importedColour:@"chatBackground"];
	if (imported) return imported;
	if (self.isDarkStyle) return rgb(0x0E, 0x0E, 0x0E);
	// Their settings page is the grey iOS has used behind grouped lists since
	// iOS 7, and the cards on it are white.
	return rgb(0xEF, 0xEF, 0xF4);
}

- (UIColor *)primaryTextColour {
	UIColor *imported = [self importedColour:@"primaryText"];
	if (imported) return imported;
	if (self.isDarkStyle) return [UIColor whiteColor];
	return TG_TEXT_PRIMARY;
}


- (UIColor *)secondaryTextColour {
	UIColor *imported = [self importedColour:@"secondaryText"];
	if (imported) return imported;
	if (self.isDarkStyle) return TG_GRAY_DARK6;
	return TG_TEXT_SECONDARY;
}


/// An imported theme rarely names the composer separately, so it takes the
/// bar colour - which is what the official clients do with it anyway.
- (UIColor *)timeColour {
	UIColor *imported = [self importedColour:@"secondaryText"];
	if (imported) return imported;
	return self.isDarkStyle ? TG_STEEL_DARK13 : TG_TEXT_TIME;
}

- (UIColor *)cellDetailColour {
	// Telegram puts the value of a setting in blue rather than grey, which is
	// the one thing that makes their settings read as theirs.
	UIColor *imported = [self importedColour:@"accent"];
	return imported ?: TG_BLUE_SEMI8;
}

- (UIColor *)sectionHeaderColour {
	UIColor *imported = [self importedColour:@"secondaryText"];
	return imported ?: TG_GRAY_SECTION;
}

- (UIColor *)profileHeaderColour {
	UIColor *imported = [self importedColour:@"bar"];
	return imported ?: TG_BLUE_DARK3;
}

- (UIColor *)inputBarColour {
	if ([self hasCustomPalette])
		return [self barColour];
	return self.isDarkStyle ? TG_GRAY_DARK16 : TG_GRAY_LIGHT3;
}

#pragma mark - media and file blocks

/// These four are the file block from their design system, and they are the
/// same blue in every theme: it is the block's own colour, not the accent.
- (UIColor *)fileTileColour {
	return self.isDarkStyle ? TG_GRAY_DARK13 : TG_FILE_TILE;
}

- (UIColor *)mediaCircleColour {
	return TG_MEDIA_CIRCLE;
}

- (UIColor *)fileNameColour {
	UIColor *imported = [self importedColour:@"accent"];
	return imported ?: TG_FILE_NAME;
}

- (UIColor *)fileMetaColour {
	return self.isDarkStyle ? TG_GRAY_DARK6 : TG_STEEL_LIGHT13;
}

/// The stamp over a picture has to read against whatever the picture is, so it
/// gets a plate rather than a colour.
- (UIColor *)mediaStampColour {
	return [UIColor colorWithWhite:0.0f alpha:0.35f];
}

#pragma mark - chat list

- (UIColor *)badgeColour {
	UIColor *imported = [self importedColour:@"accent"];
	return imported ?: TG_BLUE_MEDIUM8;
}

- (UIColor *)mutedBadgeColour {
	return self.isDarkStyle ? rgb(0x55, 0x55, 0x55) : TG_STEEL_LIGHT6;
}

- (UIColor *)typingColour {
	UIColor *imported = [self importedColour:@"accent"];
	return imported ?: TG_BLUE_BLURPLE3;
}

- (UIColor *)onlineColour {
	return TG_GREEN_BRIGHT1;
}

- (UIColor *)separatorColour {
	if ([self hasCustomPalette])
		return [self bubbleBorderColour];
	return self.isDarkStyle ? TG_GRAY_DARK13 : TG_STEEL_LIGHT3;
}

#pragma mark - service messages

/// A narrow plate centred on the wallpaper. Because it sits over a picture as
/// often as over a colour, it is drawn as a wash rather than a fixed grey.
- (UIColor *)serviceBubbleColour {
	return self.isDarkStyle ? [UIColor colorWithWhite:1.0f alpha:0.12f]
							: [UIColor colorWithWhite:0.0f alpha:0.30f];
}

- (UIColor *)serviceTextColour {
	return self.isDarkStyle ? [UIColor colorWithWhite:1.0f alpha:0.85f]
							: [UIColor whiteColor];
}

- (CGFloat)bubbleCornerRadius {
	// Their bubble is a 6pt tail on a softly rounded box, not a capsule.
	return self.isFlat ? 12.0f : 10.0f;
}

- (CGFloat)bubbleBorderWidth {
	// A drawn edge is what makes a skeuomorphic bubble sit on the surface. A
	// flat one is the shape and nothing else, which is what the header has
	// always said this returns.
	return self.isFlat ? 0.0f : 1.0f;
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
		bar.tintColor = self.isFlat ? [self accentColour] : [UIColor whiteColor];
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
