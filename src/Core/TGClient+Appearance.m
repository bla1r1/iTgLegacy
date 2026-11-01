//
// TGClient+Appearance.m - the background catalogue and the default chat
// background.
//
// Every request here answers with Telegram's own record. The screen needs a
// name, the default flag and something to draw, so the flattening happens
// once here rather than in two table cells that would drift.
//
#import "TGClient+Appearance.h"
#import "TGClientInternal.h"

static NSString *TGAppearanceError(NSDictionary *result) {
	NSString *message = result[@"message"];
	return [message isKindOfClass:NSString.class] ? message : @"Telegram refused that.";
}

static NSString *TGBackgroundTypeName(NSDictionary *type) {
	NSString *name = type[@"@type"];
	if (![name isKindOfClass:NSString.class] || ![name hasPrefix:@"backgroundType"])
		return @"wallpaper";
	NSString *suffix = [name substringFromIndex:@"backgroundType".length];
	if (!suffix.length)
		return @"wallpaper";
	// The wire name is backgroundTypePattern; the screens and tests use
	// "pattern", the way the rest of the client lowercases a type suffix.
	NSString *first = [[suffix substringToIndex:1] lowercaseString];
	return [first stringByAppendingString:[suffix substringFromIndex:1]];
}

/// The solid colour a fill or pattern background is built on, as 0xRRGGBB.
/// A picture background has none and answers -1. The screen draws this while
/// the thumbnail is still downloading, and for backgrounds Telegram keeps as
/// a colour rather than a file.
static NSNumber *TGBackgroundFillColour(NSDictionary *type) {
	NSDictionary *fill = type[@"fill"];
	if (![fill isKindOfClass:NSDictionary.class])
		return @(-1);
	NSString *kind = fill[@"@type"];
	id colour = nil;
	if ([kind isEqualToString:@"backgroundFillSolid"])
		colour = fill[@"color"];
	else if ([kind isEqualToString:@"backgroundFillGradient"])
		colour = fill[@"top_color"];
	else if ([kind isEqualToString:@"backgroundFillFreeformGradient"]){
		NSArray *colours = fill[@"colors"];
		if ([colours isKindOfClass:NSArray.class] && colours.count)
			colour = colours[0];
	}
	return [colour isKindOfClass:NSNumber.class] ? colour : @(-1);
}

static NSNumber *TGBackgroundFileId(NSDictionary *background) {
	NSDictionary *document = background[@"document"];
	if (![document isKindOfClass:NSDictionary.class])
		return @0;
	NSNumber *fileId = document[@"thumbnail"][@"file"][@"id"];
	if (![fileId isKindOfClass:NSNumber.class] || fileId.longLongValue <= 0)
		fileId = document[@"document"][@"id"];
	return [fileId isKindOfClass:NSNumber.class] ? fileId : @0;
}

/// One background record as the list draws it. Nil for anything that is not
/// a background, so an error never reaches the table as a half-built row.
static NSDictionary *TGFlattenBackground(NSDictionary *background) {
	if (![background isKindOfClass:NSDictionary.class] ||
		![background[@"@type"] isEqualToString:@"background"])
		return nil;

	NSNumber *backgroundId = background[@"id"];
	if (![backgroundId isKindOfClass:NSNumber.class])
		return nil;

	NSDictionary *type = [background[@"type"] isKindOfClass:NSDictionary.class]
			? background[@"type"] : @{};
	NSString *name = background[@"name"];
	if (![name isKindOfClass:NSString.class])
		name = @"";
	// A fill background can be local-only and carry no name. The remote name
	// is kept empty so getBackgroundUrl refuses it instead of asking Telegram
	// for a made-up address; "title" is only what the row draws.
	NSString *title = name.length ? name
			: [NSString stringWithFormat:@"Background %@", backgroundId];

	return @{
		@"id"         : backgroundId,
		@"name"       : name,
		@"title"      : title,
		@"isDefault"  : @([background[@"is_default"] boolValue]),
		@"isDark"     : @([background[@"is_dark"] boolValue]),
		@"typeName"   : TGBackgroundTypeName(type),
		@"type"       : type,
		@"fileId"     : TGBackgroundFileId(background),
		@"fillColour" : TGBackgroundFillColour(type),
	};
}

@implementation TGClient (Appearance)

- (void)installedBackgroundsForDarkTheme:(BOOL)darkTheme
							  completion:(void (^)(NSArray *backgrounds,
												   NSString *error))completion {
	[self request:@{@"@type" : @"getInstalledBackgrounds",
					@"for_dark_theme" : @(darkTheme)}
	   completion:^(NSDictionary *result){
		if ([result[@"@type"] isEqualToString:@"error"]){
			if (completion)
				completion(@[], TGAppearanceError(result));
			return;
		}
		NSArray *records = result[@"backgrounds"];
		if (![records isKindOfClass:NSArray.class])
			records = @[];
		NSMutableArray *rows = [NSMutableArray arrayWithCapacity:records.count];
		for (NSDictionary *record in records){
			NSDictionary *row = TGFlattenBackground(record);
			if (row)
				[rows addObject:row];
		}
		if (completion)
			completion(rows, nil);
	}];
}

- (void)searchBackgroundNamed:(NSString *)name
				   completion:(void (^)(NSDictionary *background,
										NSString *error))completion {
	if (!name.length){
		if (completion)
			completion(nil, @"No background name was given.");
		return;
	}
	[self request:@{@"@type" : @"searchBackground", @"name" : name}
	   completion:^(NSDictionary *result){
		if ([result[@"@type"] isEqualToString:@"error"]){
			if (completion)
				completion(nil, TGAppearanceError(result));
			return;
		}
		NSDictionary *background = TGFlattenBackground(result);
		if (completion)
			completion(background, background ? nil :
					@"Telegram answered with something that is not a background.");
	}];
}

- (void)setDefaultBackground:(NSDictionary *)background
				forDarkTheme:(BOOL)darkTheme
				  completion:(void (^)(NSDictionary *installed,
									   NSString *error))completion {
	NSNumber *backgroundId = background[@"id"];
	if (![backgroundId isKindOfClass:NSNumber.class] ||
		backgroundId.longLongValue == 0){
		if (completion)
			completion(nil, @"That background has no id to install.");
		return;
	}

	NSMutableDictionary *request = [@{
		@"@type" : @"setDefaultBackground",
		@"background" : @{@"@type" : @"inputBackgroundRemote",
						  @"background_id" : backgroundId},
		@"for_dark_theme" : @(darkTheme),
	} mutableCopy];

	// A chat theme is not a background type setDefaultBackground accepts;
	// the remote background's own type is the one to keep. Passing it also
	// preserves a pattern's intensity instead of flattening it to wallpaper.
	NSDictionary *type = [background[@"type"] isKindOfClass:NSDictionary.class]
			? background[@"type"] : nil;
	NSString *typeName = background[@"typeName"];
	if (type && ![typeName isEqualToString:@"chatTheme"])
		request[@"type"] = type;

	[self request:request completion:^(NSDictionary *result){
		if ([result[@"@type"] isEqualToString:@"error"]){
			if (completion)
				completion(nil, TGAppearanceError(result));
			return;
		}
		NSDictionary *installed = TGFlattenBackground(result);
		if (completion)
			completion(installed, installed ? nil :
					@"Telegram answered without the installed background.");
	}];
}

- (void)removeInstalledBackground:(int64_t)backgroundId
					   completion:(void (^)(BOOL ok, NSString *error))completion {
	if (backgroundId == 0){
		if (completion)
			completion(NO, @"That background has no id to remove.");
		return;
	}
	[self request:@{@"@type" : @"removeInstalledBackground",
					@"background_id" : @(backgroundId)}
	   completion:^(NSDictionary *result){
		BOOL failed = [result[@"@type"] isEqualToString:@"error"];
		if (completion)
			completion(!failed, failed ? TGAppearanceError(result) : nil);
	}];
}

- (void)resetInstalledBackgroundsWithCompletion:
		(void (^)(BOOL ok, NSString *error))completion {
	[self request:@{@"@type" : @"resetInstalledBackgrounds"}
	   completion:^(NSDictionary *result){
		BOOL failed = [result[@"@type"] isEqualToString:@"error"];
		if (completion)
			completion(!failed, failed ? TGAppearanceError(result) : nil);
	}];
}

- (void)deleteDefaultBackgroundForDarkTheme:(BOOL)darkTheme
								 completion:(void (^)(BOOL ok,
													  NSString *error))completion {
	[self request:@{@"@type" : @"deleteDefaultBackground",
					@"for_dark_theme" : @(darkTheme)}
	   completion:^(NSDictionary *result){
		BOOL failed = [result[@"@type"] isEqualToString:@"error"];
		if (completion)
			completion(!failed, failed ? TGAppearanceError(result) : nil);
	}];
}

- (void)backgroundUrlForBackground:(NSDictionary *)background
						completion:(void (^)(NSString *url,
											 NSString *error))completion {
	NSString *name = background[@"name"];
	NSDictionary *type = background[@"type"];
	if (![name isKindOfClass:NSString.class] || !name.length){
		if (completion)
			completion(nil, @"Telegram has no address for a background with no name.");
		return;
	}
	if (![type isKindOfClass:NSDictionary.class] ||
		[background[@"typeName"] isEqualToString:@"chatTheme"]){
		if (completion)
			completion(nil, @"A chat theme has no background address.");
		return;
	}
	[self request:@{@"@type" : @"getBackgroundUrl",
					@"name" : name,
					@"type" : type}
	   completion:^(NSDictionary *result){
		if ([result[@"@type"] isEqualToString:@"error"]){
			if (completion)
				completion(nil, TGAppearanceError(result));
			return;
		}
		NSString *url = result[@"url"];
		if (completion)
			completion([url isKindOfClass:NSString.class] ? url : nil,
					[url isKindOfClass:NSString.class] ? nil :
					@"Telegram answered without an address.");
	}];
}

@end
