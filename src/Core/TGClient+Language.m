//
// TGClient+Language.m - the language page's server half, country data, and
// the two text tools behind the composer's formatting preview.
//
#import "TGClientInternal.h"

/// The localization target this client reads. Telegram ships one pack per
/// target, and the user clients all read the "ios" target.
static NSString *const TGLocalizationTarget = @"ios";

static NSDictionary *TGLanguagePackInfo(NSDictionary *info) {
	if (![info isKindOfClass:NSDictionary.class])
		return nil;
	NSString *packId = info[@"id"];
	if (![packId isKindOfClass:NSString.class] || !packId.length)
		return nil;
	return @{
		@"id"        : packId,
		@"base"      : info[@"base_language_pack_id"] ?: @"",
		@"name"      : info[@"name"] ?: @"",
		@"nativeName": info[@"native_name"] ?: @"",
		@"pluralCode": info[@"plural_code"] ?: @"",
		@"official"  : info[@"is_official"] ?: @NO,
		@"rtl"       : info[@"is_rtl"] ?: @NO,
		@"beta"      : info[@"is_beta"] ?: @NO,
		@"installed" : info[@"is_installed"] ?: @NO,
		@"total"     : info[@"total_string_count"] ?: @(0),
		@"translated": info[@"translated_string_count"] ?: @(0),
		@"local"     : info[@"local_string_count"] ?: @(0),
		@"translationUrl" : info[@"translation_url"] ?: @"",
	};
}

/// The normalized record back into the shape setCustomLanguagePack and
/// editCustomLanguagePackInfo take.
static NSDictionary *TGLanguagePackInfoObject(NSDictionary *info) {
	return @{
		@"@type" : @"languagePackInfo",
		@"id" : info[@"id"] ?: @"",
		@"base_language_pack_id" : info[@"base"] ?: @"",
		@"name" : info[@"name"] ?: @"",
		@"native_name" : info[@"nativeName"] ?: info[@"name"] ?: @"",
		@"plural_code" : info[@"pluralCode"] ?: @"other",
		@"is_official" : info[@"official"] ?: @NO,
		@"is_rtl" : info[@"rtl"] ?: @NO,
		@"is_beta" : info[@"beta"] ?: @NO,
		@"is_installed" : info[@"installed"] ?: @YES,
		@"total_string_count" : info[@"total"] ?: @(0),
		@"translated_string_count" : info[@"translated"] ?: @(0),
		@"local_string_count" : info[@"local"] ?: @(0),
		@"translation_url" : info[@"translationUrl"] ?: @"",
	};
}

static NSArray *TGLanguagePackStrings(NSDictionary *result) {
	NSMutableArray *out = [NSMutableArray array];
	for (NSDictionary *string in result[@"strings"]){
		if (![string isKindOfClass:NSDictionary.class])
			continue;
		NSDictionary *value = [string[@"value"] isKindOfClass:NSDictionary.class]
				? string[@"value"] : @{};
		NSString *type = value[@"@type"] ?: @"";
		if ([type isEqualToString:@"languagePackStringValueOrdinary"]){
			[out addObject:@{
				@"key" : string[@"key"] ?: @"",
				@"value" : value[@"value"] ?: @"",
				@"kind" : @"ordinary",
			}];
		} else if ([type isEqualToString:@"languagePackStringValuePluralized"]){
			[out addObject:@{
				@"key" : string[@"key"] ?: @"",
				@"value" : value[@"other_value"] ?: @"",
				@"kind" : @"pluralized",
			}];
		} else if ([type isEqualToString:@"languagePackStringValueDeleted"]){
			[out addObject:@{
				@"key" : string[@"key"] ?: @"",
				@"value" : @"",
				@"kind" : @"deleted",
			}];
		}
	}
	return out;
}

/// The synchronous text functions all have the same shape: try execute, and
/// fall back to the request loop where the dylib has no execute symbol.
static void TGTextAnswer(TGClient *client, NSDictionary *request,
						 void (^take)(NSDictionary *answer)) {
	NSDictionary *sync = [client executeSynchronously:request];
	if (sync){
		if (take) take(sync);
		return;
	}
	[client request:request completion:^(NSDictionary *answer){
		if (take) take(answer);
	}];
}

@implementation TGClient (Language)

#pragma mark - language packs

- (void)languagePackInfo:(NSString *)packId
			  completion:(void (^)(NSDictionary *))completion {
	if (!packId.length){
		if (completion) completion(nil);
		return;
	}
	[self request:@{@"@type" : @"getLanguagePackInfo",
					@"language_pack_id" : packId}
	   completion:^(NSDictionary *result){
		if (completion)
			completion(TGLanguagePackInfo(result));
	}];
}

- (void)languagePackStrings:(NSString *)packId
					   keys:(NSArray *)keys
				 completion:(void (^)(NSArray *))completion {
	if (!packId.length){
		if (completion) completion(@[]);
		return;
	}
	[self request:@{@"@type" : @"getLanguagePackStrings",
					@"language_pack_id" : packId,
					@"keys" : keys ?: @[]}
	   completion:^(NSDictionary *result){
		if (completion)
			completion(TGLanguagePackStrings(result));
	}];
}

- (void)languagePackString:(NSString *)key
					  pack:(NSString *)packId
				completion:(void (^)(NSString *, NSString *))completion {
	if (!key.length || !packId.length){
		if (completion) completion(nil, nil);
		return;
	}
	// The synchronous call needs the database the client already has open,
	// and TDLib keeps that path in an option. Reading it first is what makes
	// the read-back work against the real pack instead of an empty database.
	[self request:@{@"@type" : @"getOption",
					@"name" : @"language_pack_database_path"}
	   completion:^(NSDictionary *option){
		NSDictionary *value = [option[@"value"] isKindOfClass:NSDictionary.class]
				? option[@"value"] : nil;
		NSString *databasePath = [value[@"value"] isKindOfClass:NSString.class]
				? value[@"value"] : @"";
		NSDictionary *request = @{
			@"@type" : @"getLanguagePackString",
			@"language_pack_database_path" : databasePath ?: @"",
			@"localization_target" : TGLocalizationTarget,
			@"language_pack_id" : packId,
			@"key" : key,
		};
		TGTextAnswer(self, request, ^(NSDictionary *answer){
			if (!completion)
				return;
			NSString *type = answer[@"@type"] ?: @"";
			if ([type isEqualToString:@"languagePackStringValueOrdinary"])
				completion(answer[@"value"] ?: @"", @"ordinary");
			else if ([type isEqualToString:@"languagePackStringValuePluralized"])
				completion(answer[@"other_value"] ?: @"", @"pluralized");
			else if ([type isEqualToString:@"languagePackStringValueDeleted"])
				completion(@"", @"deleted");
			else
				completion(nil, nil);
		});
	}];
}

- (void)addCustomServerLanguagePack:(NSString *)packId
						 completion:(void (^)(BOOL))completion {
	if (!packId.length){
		if (completion) completion(NO);
		return;
	}
	[self request:@{@"@type" : @"addCustomServerLanguagePack",
					@"language_pack_id" : packId}
	   completion:^(NSDictionary *result){
		if (completion)
			completion([result[@"@type"] isEqualToString:@"ok"]);
	}];
}

- (void)setCustomLanguagePack:(NSString *)packId
						 name:(NSString *)name
				   nativeName:(NSString *)nativeName
					  strings:(NSArray *)strings
				   completion:(void (^)(BOOL))completion {
	if (!packId.length || !name.length){
		if (completion) completion(NO);
		return;
	}
	// A local pack is identified by an id beginning with X. The page asks
	// for a readable one; a leading X is added once rather than refused.
	NSString *customId = [packId hasPrefix:@"X"] ? packId : [@"X" stringByAppendingString:packId];
	NSMutableArray *out = [NSMutableArray array];
	for (NSDictionary *string in strings){
		NSString *key = string[@"key"];
		if (!key.length)
			continue;
		[out addObject:@{
			@"@type" : @"languagePackString",
			@"key" : key,
			@"value" : @{
				@"@type" : @"languagePackStringValueOrdinary",
				@"value" : string[@"value"] ?: @"",
			},
		}];
	}
	NSDictionary *info = TGLanguagePackInfoObject(@{
		@"id" : customId,
		@"base" : @"en",
		@"name" : name,
		@"nativeName" : nativeName.length ? nativeName : name,
		@"pluralCode" : @"other",
		@"installed" : @YES,
	});
	[self request:@{@"@type" : @"setCustomLanguagePack",
					@"info" : info,
					@"strings" : out}
	   completion:^(NSDictionary *result){
		if (completion)
			completion([result[@"@type"] isEqualToString:@"ok"]);
	}];
}

- (void)setCustomLanguagePackString:(NSString *)key
							  value:(NSString *)value
							   pack:(NSString *)packId
						 completion:(void (^)(BOOL))completion {
	if (!key.length || !packId.length){
		if (completion) completion(NO);
		return;
	}
	// A nil value deletes the override; an empty one is a real empty string.
	NSDictionary *stringValue = value == nil
			? @{@"@type" : @"languagePackStringValueDeleted"}
			: @{@"@type" : @"languagePackStringValueOrdinary",
				@"value" : value};
	[self request:@{@"@type" : @"setCustomLanguagePackString",
					@"language_pack_id" : packId,
					@"new_string" : @{
						@"@type" : @"languagePackString",
						@"key" : key,
						@"value" : stringValue,
					}}
	   completion:^(NSDictionary *result){
		if (completion)
			completion([result[@"@type"] isEqualToString:@"ok"]);
	}];
}

- (void)editCustomLanguagePackInfo:(NSDictionary *)info
						completion:(void (^)(BOOL))completion {
	if (![info[@"id"] length]){
		if (completion) completion(NO);
		return;
	}
	[self request:@{@"@type" : @"editCustomLanguagePackInfo",
					@"info" : TGLanguagePackInfoObject(info)}
	   completion:^(NSDictionary *result){
		if (completion)
			completion([result[@"@type"] isEqualToString:@"ok"]);
	}];
}

- (void)synchronizeLanguagePack:(NSString *)packId
					 completion:(void (^)(BOOL))completion {
	if (!packId.length){
		if (completion) completion(NO);
		return;
	}
	[self request:@{@"@type" : @"synchronizeLanguagePack",
					@"language_pack_id" : packId}
	   completion:^(NSDictionary *result){
		if (completion)
			completion([result[@"@type"] isEqualToString:@"ok"]);
	}];
}

- (void)deleteLanguagePack:(NSString *)packId
				completion:(void (^)(BOOL))completion {
	if (!packId.length){
		if (completion) completion(NO);
		return;
	}
	[self request:@{@"@type" : @"deleteLanguagePack",
					@"language_pack_id" : packId}
	   completion:^(NSDictionary *result){
		if (completion)
			completion([result[@"@type"] isEqualToString:@"ok"]);
	}];
}

#pragma mark - countries

- (void)countryInfoForCode:(NSString *)countryCode
				completion:(void (^)(NSDictionary *))completion {
	NSString *code = [countryCode uppercaseString];
	if (!code.length){
		if (completion) completion(nil);
		return;
	}
	[self request:@{@"@type" : @"getCountry",
					@"country_code" : code}
	   completion:^(NSDictionary *result){
		if (!completion)
			return;
		if (![result[@"@type"] isEqualToString:@"countryInfo"]){
			completion(nil);
			return;
		}
		completion(@{
			@"code" : result[@"country_code"] ?: code,
			@"name" : result[@"name"] ?: @"",
			@"englishName" : result[@"english_name"] ?: @"",
			@"flag" : result[@"flag_emoji"] ?: @"",
			@"hidden" : result[@"is_hidden"] ?: @NO,
			@"callingCodes" : result[@"calling_codes"] ?: @[],
		});
	}];
}

- (void)preferredCountryLanguageForCode:(NSString *)countryCode
							 completion:(void (^)(NSString *))completion {
	NSString *code = [countryCode uppercaseString];
	if (!code.length){
		if (completion) completion(nil);
		return;
	}
	[self request:@{@"@type" : @"getPreferredCountryLanguage",
					@"country_code" : code}
	   completion:^(NSDictionary *result){
		if (!completion)
			return;
		NSString *language = [result[@"@type"] isEqualToString:@"text"]
				? result[@"text"] : nil;
		completion([language isKindOfClass:NSString.class] && language.length
				? language : nil);
	}];
}

- (void)countryFlagEmojiForCode:(NSString *)countryCode
					 completion:(void (^)(NSString *))completion {
	NSString *code = [countryCode uppercaseString];
	if (!code.length){
		if (completion) completion(nil);
		return;
	}
	TGTextAnswer(self,
				 @{@"@type" : @"getCountryFlagEmoji",
				   @"country_code" : code},
				 ^(NSDictionary *answer){
		if (!completion)
			return;
		NSString *text = [answer[@"@type"] isEqualToString:@"text"]
				? answer[@"text"] : nil;
		completion([text isKindOfClass:NSString.class] && text.length
				? text : nil);
	});
}

#pragma mark - formatting and translation

- (void)parseMarkdownText:(NSString *)text
			   completion:(void (^)(NSDictionary *))completion {
	if (!text.length){
		if (completion)
			completion(@{@"@type" : @"formattedText",
						 @"text" : @"",
						 @"entities" : @[]});
		return;
	}
	TGTextAnswer(self,
				 @{@"@type" : @"parseMarkdown",
				   @"text" : @{@"@type" : @"formattedText",
							   @"text" : text,
							   @"entities" : @[]}},
				 ^(NSDictionary *answer){
		if (!completion)
			return;
		if (![answer[@"@type"] isEqualToString:@"formattedText"]){
			completion(nil);
			return;
		}
		completion(@{
			@"@type" : @"formattedText",
			@"text" : answer[@"text"] ?: text,
			@"entities" : answer[@"entities"] ?: @[],
		});
	});
}

- (void)textEntitiesInText:(NSString *)text
				completion:(void (^)(NSArray *))completion {
	if (!text.length){
		if (completion) completion(@[]);
		return;
	}
	TGTextAnswer(self,
				 @{@"@type" : @"getTextEntities",
				   @"text" : text},
				 ^(NSDictionary *answer){
		if (!completion)
			return;
		if (![answer[@"@type"] isEqualToString:@"textEntities"]){
			completion(@[]);
			return;
		}
		completion(answer[@"entities"] ?: @[]);
	});
}

- (void)translateText:(NSString *)text
	   toLanguageCode:(NSString *)languageCode
				 tone:(NSString *)tone
		   completion:(void (^)(NSString *))completion {
	if (!text.length){
		if (completion) completion(nil);
		return;
	}
	NSString *code = languageCode.length ? languageCode
			: ([[NSLocale currentLocale] objectForKey:NSLocaleLanguageCode] ?: @"en");
	[self request:@{
		@"@type" : @"translateText",
		@"text" : @{@"@type" : @"formattedText",
					@"text" : text,
					@"entities" : @[]},
		@"to_language_code" : code,
		@"tone" : tone ?: @"",
	} completion:^(NSDictionary *result){
		if (!completion)
			return;
		NSString *translated = [result[@"@type"] isEqualToString:@"formattedText"]
				? result[@"text"] : nil;
		completion([translated isKindOfClass:NSString.class] ? translated : nil);
	}];
}

@end
