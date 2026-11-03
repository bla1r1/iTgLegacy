//
// TGSettingsViewController+AppearancePages.m
// Settings pages for theme styling, chat appearance, and skeuomorphic wallpapers.
//
#import "TGSettingsViewControllerInternal.h"
#import "TGAlertSheet.h"
#import "TGBackgroundsViewController.h"
#import "TGProfileAppearanceViewController.h"
#import "TGStyle.h"

/// The background type is a td_api object name; "backgroundTypeFill" reads
/// better as "Fill" in a sheet, and an absent type is said plainly.
static NSString *TGBackgroundTypeLabel(id type) {
	NSString *name = [type isKindOfClass:NSDictionary.class] ? type[@"@type"] : nil;
	if (![name isKindOfClass:NSString.class] || !name.length)
		return @"Unknown";
	NSString *prefix = @"backgroundType";
	if ([name rangeOfString:prefix].location == 0)
		return [name substringFromIndex:prefix.length];
	return name;
}

static NSString *TGDefaultBackgroundDetail(NSDictionary *state) {
	if (![state isKindOfClass:NSDictionary.class])
		return @"Not received";
	NSDictionary *background = state[@"background"];
	NSString *name = [background isKindOfClass:NSDictionary.class]
			? background[@"name"] : nil;
	NSString *which = [state[@"for_dark_theme"] boolValue] ? @"Dark" : @"Light";
	if ([name isKindOfClass:NSString.class] && name.length)
		return [NSString stringWithFormat:@"%@ - %@", which, name];
	return [NSString stringWithFormat:@"%@ default", which];
}

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

	return @[
		TGSection(nil, nil, @[TGRow(TGKindPreview, @"")]),

		TGSection(@"CHAT SETTINGS", nil, @[
			TGIconTapRow(@"Message Text Size",
					[NSString stringWithFormat:@"%.0f pt", theme.messageFontSize],
					@"chat", TGIconTileSky(),
					^{ [weakSelf chooseTextSize]; }),
			TGIconTapRow(@"Chat Background",
					[theme wallpaperTitleForType:theme.wallpaperType],
					@"data", TGIconTileGreen(), ^{
				TGSettingsViewController *wp = [[TGSettingsViewController alloc] init];
				wp.page = TGSettingsPageWallpaper;
				[weakSelf.navigationController pushViewController:wp animated:YES];
			}),
		]),


		TGSection(@"TELEGRAM DEFAULTS",
				  @"What Telegram itself offers for new chats: the default "
				  @"background and the chat themes built from emoji. Both are "
				  @"pushed by the server, so the rows fill in while you watch.",
				  @[
			TGTapRow(@"Default Background",
					TGDefaultBackgroundDetail([TGClient shared].defaultBackground), ^{
				[weakSelf showDefaultBackground];
			}),
			TGTapRow(@"Emoji Chat Themes",
					[TGClient shared].emojiChatThemes.count
							? [NSString stringWithFormat:@"%lu",
									(unsigned long)[TGClient shared].emojiChatThemes.count]
							: @"None",
					^{ [weakSelf showEmojiChatThemes]; }),
		]),

		TGSection(@"YOUR COLOR",
				  @"Telegram draws your name and the background behind your "
				  @"profile photo with these colours. They are stored on the "
				  @"account, not in this app's theme.",
				  @[
			TGIconTapRow(@"Your Color", @"Name and profile colour",
					@"star", TGIconTilePurple(), ^{
				TGProfileAppearanceViewController *colours =
						[[TGProfileAppearanceViewController alloc] init];
				colours.hidesBottomBarWhenPushed = YES;
				[weakSelf.navigationController pushViewController:colours animated:YES];
			}),
		]),

		TGSection(@"CHAT BACKGROUNDS",
				  @"Telegram keeps chat backgrounds on the account. The list "
				  @"here is the one Telegram installed, and the catalogue is "
				  @"searched on its server.", @[
			TGIconTapRow(@"Chat Backgrounds", @"Installed, search, default",
					@"data", TGIconTileGreen(), ^{
				TGBackgroundsViewController *backgrounds =
						[[TGBackgroundsViewController alloc] init];
				backgrounds.hidesBottomBarWhenPushed = YES;
				[weakSelf.navigationController pushViewController:backgrounds animated:YES];
			}),
		]),

		TGSection(@"THEMES",
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

/// The default background is one record, so the sheet can name its id, which
/// side of the theme it belongs to, and its type. A background not received
/// yet says so rather than drawing a made-up one.
- (void)showDefaultBackground {
	NSDictionary *state = [TGClient shared].defaultBackground;
	if (![state isKindOfClass:NSDictionary.class]){
		[TGAlertSheet showMessage:@"Telegram has not sent a default background yet."
							title:@"Default Background" inView:self.view];
		return;
	}
	NSDictionary *background = state[@"background"];
	NSString *name = [background isKindOfClass:NSDictionary.class]
			? background[@"name"] : nil;
	NSString *details = [NSString stringWithFormat:
			@"%@\nId: %lld\nName: %@\nDark variant: %@\nDefault: %@\nType: %@",
			TGDefaultBackgroundDetail(state),
			(long long)[background[@"id"] longLongValue],
			([name isKindOfClass:NSString.class] && name.length) ? name : @"unnamed",
			[background[@"is_dark"] boolValue] ? @"yes" : @"no",
			[background[@"is_default"] boolValue] ? @"yes" : @"no",
			TGBackgroundTypeLabel(background[@"type"])];
	[TGAlertSheet showMessage:details title:@"Default Background" inView:self.view];
}

/// Each emoji chat theme carries a light and a dark settings record. The list
/// is the names the server sent; the sheet behind one shows the accent and
/// background it would apply, without pretending this client can select it.
- (void)showEmojiChatThemes {
	NSArray *themes = [TGClient shared].emojiChatThemes;
	if (!themes.count){
		[TGAlertSheet showMessage:@"Telegram has not sent any emoji chat themes."
							title:@"Emoji Chat Themes" inView:self.view];
		return;
	}
	NSMutableArray *titles = [NSMutableArray array];
	for (NSDictionary *theme in themes){
		NSString *name = [theme isKindOfClass:NSDictionary.class] ? theme[@"name"] : nil;
		[titles addObject:([name isKindOfClass:NSString.class] && name.length)
				? name : @"Unnamed theme"];
	}
	[TGAlertSheet showChoices:titles
						title:@"Emoji Chat Themes"
					  message:@"The chat themes Telegram offers, newest list first."
			 destructiveIndex:-1
					   inView:self.view
					 onChoice:^(NSInteger index){
		if (index < 0 || (NSUInteger)index >= themes.count)
			return;
		id chosen = themes[(NSUInteger)index];
		if (![chosen isKindOfClass:NSDictionary.class])
			return;
		NSDictionary *theme = chosen;
		NSDictionary *light = theme[@"light_settings"];
		NSDictionary *dark = theme[@"dark_settings"];
		NSDictionary *lightBackground = light[@"background"];
		NSDictionary *darkBackground = dark[@"background"];
		NSString *details = [NSString stringWithFormat:
				@"%@\nLight accent: %ld\nLight background: %@\n"
				@"Dark accent: %ld\nDark background: %@",
				titles[(NSUInteger)index],
				(long)[light[@"accent_color"] integerValue],
				TGBackgroundTypeLabel(lightBackground[@"type"]),
				(long)[dark[@"accent_color"] integerValue],
				TGBackgroundTypeLabel(darkBackground[@"type"])];
		[TGAlertSheet showMessage:details
							title:titles[(NSUInteger)index]
						   inView:self.view];
	}];
}

@end
