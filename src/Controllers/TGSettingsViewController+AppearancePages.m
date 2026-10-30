//
// TGSettingsViewController+AppearancePages.m
// Settings pages for theme styling, chat appearance, and skeuomorphic wallpapers.
//
#import "TGSettingsViewControllerInternal.h"
#import "TGAlertSheet.h"
#import "TGGalleryViewController.h"
#import "TGStyle.h"

@implementation TGSettingsViewController (AppearancePages)

- (NSArray *)appearanceSections {
	__weak typeof(self) weakSelf = self;
	TGTheme *theme = [TGTheme shared];

	NSString *current = [theme currentThemeId];
	NSMutableArray *themes = [NSMutableArray array];
	for (NSDictionary *entry in [TGTheme availableThemes]){
		NSString *themeId = entry[@"id"];
		BOOL fromFile = entry[@"path"] != nil;
		[themes addObject:TGCheckRow(entry[@"name"],
				fromFile ? [(NSString *)entry[@"path"] pathExtension] : nil,
				[current isEqualToString:themeId], ^{
			if (![[TGTheme shared] selectThemeId:themeId]){
				[TGAlertSheet showMessage:@"This file could not be read as a "
										  @"Telegram theme."
									title:@"Theme" inView:weakSelf.view];
			}
			[weakSelf repaint];
		})];
	}

	NSString *autoNightDetail = (theme.autoNight == TGAutoNightScheduled)
			? [NSString stringWithFormat:@"%02ld:00 - %02ld:00",
					(long)theme.autoNightFromHour, (long)theme.autoNightToHour]
			: @"Disabled";

	return @[
		TGSection(nil, nil, @[TGRow(TGKindPreview, @"")]),

		TGSection(@"Chat", nil, @[
			TGTapRow(@"Message Text Size",
					[NSString stringWithFormat:@"%.0f pt", theme.messageFontSize],
					^{ [weakSelf chooseTextSize]; }),
			TGTapRow(@"Chat Wallpaper", [theme wallpaperTitleForType:theme.wallpaperType], ^{
				TGSettingsViewController *wp = [[TGSettingsViewController alloc] init];
				wp.page = TGSettingsPageWallpaper;
				[weakSelf.navigationController pushViewController:wp animated:YES];
			}),
		]),

		TGSection(@"Auto-Night Mode",
				  @"There is no system dark mode on this OS to follow, so the "
				  @"schedule is the automatic. Picking a theme by hand at night "
				  @"turns the schedule off until morning.", @[
			TGTapRow(@"Auto-Night Mode", autoNightDetail, ^{
				[weakSelf chooseAutoNight];
			}),
		]),

		TGSection(@"Design System",
				  @"Interactive gallery demonstrating iOS 6 Reimagined tactile "
				  @"components, states, and live controls.", @[
			TGTapRow(@"UI Component Gallery", @"Open Lab", ^{
				TGGalleryViewController *gallery = [[TGGalleryViewController alloc] init];
				[weakSelf.navigationController pushViewController:gallery animated:YES];
			}),
		]),

		TGSection(@"Color Theme",
				  @"Theme files made for the official clients - .tgios-theme and "
				  @".attheme - appear here once they are in the app's Documents "
				  @"folder, or once one is opened from a chat.", themes),
	];
}

- (NSArray *)wallpaperSections {
	__weak typeof(self) weakSelf = self;
	TGTheme *theme = [TGTheme shared];
	TGWallpaperType current = [theme wallpaperType];

	id (^textureRow)(NSString *, TGWallpaperType) = ^id(NSString *title, TGWallpaperType type) {
		BOOL checked = (current == type);
		return TGCheckRow(title, nil, checked, ^{
			[[TGTheme shared] setWallpaperType:type];
			[weakSelf rebuild];
		});
	};

	NSArray *textures = @[
		textureRow(@"None (Solid Colour)", TGWallpaperTypeNone),
		textureRow(@"Paper Grain", TGWallpaperTypePaperGrain),
		textureRow(@"Pinstripes", TGWallpaperTypePinstripes),
		textureRow(@"Classic Linen", TGWallpaperTypeLinen),
		textureRow(@"Parchment", TGWallpaperTypeParchment),
		textureRow(@"Game Center Felt", TGWallpaperTypeFelt),
	];

	NSMutableArray *customRows = [NSMutableArray array];
	[customRows addObject:TGTapRow(@"Choose from Photo Library", (current == TGWallpaperTypeCustom ? @"Active" : nil), ^{
		[weakSelf presentWallpaperPicker];
	})];
	if (current != TGWallpaperTypeNone) {
		[customRows addObject:TGActionRow(@"Remove Wallpaper", ^{
			[[TGTheme shared] setWallpaperType:TGWallpaperTypeNone];
			[weakSelf rebuild];
		})];
	}

	return @[
		TGSection(nil, nil, @[TGRow(TGKindPreview, @"")]),
		TGSection(@"Physical Textures",
				  @"Tactile Apple physical textures re-engineered for the chat canvas.",
				  textures),
		TGSection(@"Custom Photo", nil, customRows)
	];
}

@end
