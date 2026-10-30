// TGThemeFileTests.m — the theme import parsers, pinned.
//
// TGThemeFile is Foundation-only, so each real format (.tgios-theme JSON,
// Android .attheme, Desktop .tdesktop-palette) is fed through its parser
// here: role mapping, variable chains, dark detection. Compiled into
// TGClientTests.
#import "TGTestRunner.h"
#import "TGThemeFile.h"

// Writes text into the inherited temp dir and returns the path.
static NSString *TGThemeWriteTemp(NSString *name, NSString *text) {
	NSString *path = [NSTemporaryDirectory()
			stringByAppendingPathComponent:name];
	[text writeToFile:path atomically:YES encoding:NSUTF8StringEncoding error:nil];
	return path;
}

// A .attheme value is signed decimal ARGB with an opaque alpha byte.
static int32_t TGAtThemeARGB(int r, int g, int b) {
	return (int32_t)(0xFF000000u | ((uint32_t)r << 16) | ((uint32_t)g << 8) | b);
}

static BOOL TGColourMatches(UIColor *colour, int r, int g, int b) {
	// getRed: is BOOL on iOS, void on newer macOS hosts - the sentinel
	// out-params carry the success bit instead.
	CGFloat cr = -1, cg = -1, cb = -1, ca = -1;
	[colour getRed:&cr green:&cg blue:&cb alpha:&ca];
	return cr >= 0 && lroundf(cr * 255) == r && lroundf(cg * 255) == g
			&& lroundf(cb * 255) == b;
}

static void TGAssertColour(NSString *key, NSDictionary *palette,
						   int r, int g, int b) {
	UIColor *colour = [palette objectForKey:key];
	XCTAssertNotNil(colour, "theme must carry the %@ role", key);
	if (colour)
		XCTAssertTrue(TGColourMatches(colour, r, g, b),
				"%@ must be #%02x%02x%02x, got %@", key, r, g, b, colour);
}

@interface TGThemeFileTests : XCTestCase
@end
@implementation TGThemeFileTests

- (void)testHandlesFileKnowsTheRootFamilies {
	XCTAssertTrue([TGThemeFile handlesFile:@"a.tgios-theme"]);
	XCTAssertTrue([TGThemeFile handlesFile:@"a.attheme"]);
	XCTAssertTrue([TGThemeFile handlesFile:@"a.tdesktop-palette"]);
	XCTAssertTrue([TGThemeFile handlesFile:@"a.tdesktop-theme"]);
	XCTAssertFalse([TGThemeFile handlesFile:@"a.json"]);
}

- (void)testIOSThemeMapsNavBubblesAndBadges {
	NSString *json = @"{\n"
		"  \"name\": \"Reference\",\n"
		"  \"dark\": true,\n"
		"  \"root\": {\"navBar\": {\"background\": \"#517DA2\",\n"
		"      \"primaryText\": \"FFFFFF\", \"secondaryText\": \"F2F2F2\"}},\n"
		"  \"chatList\": {\"title\": \"E9EEEEF4\", \"messageText\": \"D8E1E7\",\n"
		"      \"unreadBadgeActiveBg\": \"FF6262\",\n"
		"      \"unreadBadgeActiveText\": \"FFFFFF\",\n"
		"      \"unreadBadgeMutedBg\": \"8E6E6E\"},\n"
		"  \"chat\": {\"message\": {\n"
		"      \"outgoing\": {\"bubble\": {\"withoutWp\": {\"bg\": \"96E176\"}}},\n"
		"      \"incoming\": {\"bubble\": {\"withoutWp\": {\"bg\": \"FFFFFF\"}}}}}}";
	NSString *path = TGThemeWriteTemp(@"reference.tgios-theme", json);

	NSString *name = nil;
	NSDictionary *palette = [TGThemeFile paletteFromFile:path name:&name];
	XCTAssertNotNil(palette);
	XCTAssertEqualObjects(name, @"Reference");
	XCTAssertTrue([palette[@"isDark"] boolValue], "%@", palette);
	TGAssertColour(@"bar", palette, 0x51, 0x7D, 0xA2);
	TGAssertColour(@"barTitle", palette, 0xFF, 0xFF, 0xFF);
	TGAssertColour(@"barSubtitle", palette, 0xF2, 0xF2, 0xF2);
	// withWp is the last resort; withoutWp must win first.
	TGAssertColour(@"bubbleMine", palette, 0x96, 0xE1, 0x76);
	TGAssertColour(@"bubbleTheirs", palette, 0xFF, 0xFF, 0xFF);
	TGAssertColour(@"primaryText", palette, 0xE9, 0xEE, 0xEE);
	TGAssertColour(@"badge", palette, 0xFF, 0x62, 0x62);
	TGAssertColour(@"badgeText", palette, 0xFF, 0xFF, 0xFF);
	TGAssertColour(@"mutedBadge", palette, 0x8E, 0x6E, 0x6E);

	NSString *ignored = nil;
	NSString *brokenPath = TGThemeWriteTemp(@"broken.tgios-theme", @"{\"no\": [");
	XCTAssertNil([TGThemeFile paletteFromFile:brokenPath name:&ignored]);
}

- (void)testAndroidThemeMapsRolesAndGuessesDark {
	NSString *light = [NSString stringWithFormat:
		@"actionBarDefault=%d\n"
		"actionBarDefaultTitle=%d\n"
		"windowBackgroundWhite=%d\n"
		"windowBackgroundWhiteBlackText=%d\n"
		"windowBackgroundWhiteRedText=%d\n"
		"chat_wallpaper=%d\n"
		"chat_inBubble=%d\n"
		"chat_outBubble=%d\n"
		"chats_unreadCounter=%d\n"
		"chats_unreadCounterText=%d\n"
		"chat_outSentCheck=%d\n",
		TGAtThemeARGB(0x51, 0x7D, 0xA2),
		TGAtThemeARGB(0xFF, 0xFF, 0xFF),
		TGAtThemeARGB(0xFF, 0xFF, 0xFF),
		TGAtThemeARGB(0x22, 0x22, 0x22),
		TGAtThemeARGB(0xE5, 0x39, 0x35),
		TGAtThemeARGB(0xD9, 0xDE, 0xD4),
		TGAtThemeARGB(0xFF, 0xFF, 0xFF),
		TGAtThemeARGB(0x2B, 0x5D, 0x7F),
		TGAtThemeARGB(0x3D, 0x95, 0xD4),
		TGAtThemeARGB(0xFF, 0xFF, 0xFF),
		TGAtThemeARGB(0xE5, 0x39, 0x35)];
	NSString *path = TGThemeWriteTemp(@"light.attheme", light);
	NSString *name = nil;
	NSDictionary *palette = [TGThemeFile paletteFromFile:path name:&name];
	XCTAssertNotNil(palette);
	XCTAssertEqualObjects(name, @"light");
	XCTAssertFalse([palette[@"isDark"] boolValue], "%@", palette);
	TGAssertColour(@"bar", palette, 0x51, 0x7D, 0xA2);
	TGAssertColour(@"bubbleMine", palette, 0x2B, 0x5D, 0x7F);
	TGAssertColour(@"bubbleTheirs", palette, 0xFF, 0xFF, 0xFF);
	TGAssertColour(@"badge", palette, 0x3D, 0x95, 0xD4);
	TGAssertColour(@"badgeText", palette, 0xFF, 0xFF, 0xFF);
	TGAssertColour(@"ticks", palette, 0xE5, 0x39, 0x35);
	TGAssertColour(@"destructive", palette, 0xE5, 0x39, 0x35);

	// A dark paper must be detected, so unmap roles don't fall to light.
	NSString *dark = [NSString stringWithFormat:
		@"windowBackgroundWhite=%d\n",
		TGAtThemeARGB(0x26, 0x2E, 0x26)];
	NSString *darkPath = TGThemeWriteTemp(@"dark.attheme", dark);
	NSString *darkName = nil;
	NSDictionary *darkPalette = [TGThemeFile paletteFromFile:darkPath name:&darkName];
	XCTAssertNotNil(darkPalette);
	XCTAssertEqualObjects(darkName, @"dark");
	XCTAssertTrue([darkPalette[@"isDark"] boolValue], "%@", darkPalette);
}

- (void)testDesktopPaletteMapsRolesVariablesAndComments {
	NSString *text = @"// Variable theme, comments everywhere\n"
		"windowBg: #17212b;      // background\n"
		"windowFg: #ffffff;\n"
		"windowSubTextFg: #708499;\n"
		"topBarBg:\n"
		"  #17212b;              // value continues on the next line\n"
		"topBarFg: #ffffff;\n"
		"chatBg: #0e1621;\n"
		"msgInBg: #182533;\n"
		"msgOutBg: #2b5278;\n"
		"dialogsBg: #17212b;\n"
		"windowBgActive: #5288c1;\n"
		"dialogsUnreadBg: windowBgActive;   // resolves a variable chain\n"
		"msgServiceBg: #22303cc0;  // eight digits: alpha is the last pair\n"
		"msgServiceFg: #ffffff;\n"
		"windowBgOver: #17212b;";
	NSString *path = TGThemeWriteTemp(@"night.tdesktop-palette", text);
	NSString *name = nil;
	NSDictionary *palette = [TGThemeFile paletteFromFile:path name:&name];
	XCTAssertNotNil(palette, "%@", palette);
	XCTAssertEqualObjects(name, @"night");
	XCTAssertTrue([palette[@"isDark"] boolValue], "%@", palette);
	TGAssertColour(@"bar", palette, 0x17, 0x21, 0x2b);
	TGAssertColour(@"barTitle", palette, 0xFF, 0xFF, 0xFF);
	TGAssertColour(@"chatBackground", palette, 0x0e, 0x16, 0x21);
	TGAssertColour(@"bubbleMine", palette, 0x2b, 0x52, 0x78);
	TGAssertColour(@"bubbleTheirs", palette, 0x18, 0x25, 0x33);
	TGAssertColour(@"secondaryText", palette, 0x70, 0x84, 0x99);
	// The reference must reach both its role and the badge that falls back
	// to the same key name in the desktop palette.
	TGAssertColour(@"accent", palette, 0x52, 0x88, 0xc1);
	TGAssertColour(@"badge", palette, 0x52, 0x88, 0xc1);
	// The alpha byte trails the colour in tdesktop's spelling.
	TGAssertColour(@"service", palette, 0x22, 0x30, 0x3c);
	UIColor *service = [palette objectForKey:@"service"];
	CGFloat sa = -1, sr = -1, sg = -1, sb = -1;
	[service getRed:&sr green:&sg blue:&sb alpha:&sa];
	XCTAssertGreaterThan(sa, 0.7f, "the alpha byte must survive, got %.2f", sa);
	XCTAssertLessThan(sa, 0.9f, "too opaque: the alpha byte was lost");
	TGAssertColour(@"service", palette, 0x22, 0x30, 0x3c);
}
@end
