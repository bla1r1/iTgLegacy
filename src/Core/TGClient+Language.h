//
// TGClient+Language.h - language packs, country data and the text tools the
// composer's preview and the Translate row use.
//
#import "TGClient+Base.h"

@interface TGClient (Language)

#pragma mark - language packs

/// One pack's record: "id", "base", "name", "nativeName", "pluralCode",
/// "official", "rtl", "beta", "installed", "total", "translated", "local"
/// and "translationUrl". nil when Telegram has no such pack.
- (void)languagePackInfo:(NSString *)packId
			  completion:(void (^)(NSDictionary *info))completion;

/// The pack's strings. An empty key list asks for every one it has.
- (void)languagePackStrings:(NSString *)packId
					   keys:(NSArray *)keys
				 completion:(void (^)(NSArray *strings))completion;

/// The strings the last updateLanguagePackStrings carried for each pack,
/// keyed by pack id. A change, not the whole pack - the page re-reads the
/// list it was showing rather than pretending a partial answer is complete.
@property (nonatomic, readonly) NSDictionary *languagePackStringsByPack;

/// One string, read back from the local pack database. `kind` is "ordinary",
/// "pluralized" or "deleted"; nil when the key is not in the pack.
- (void)languagePackString:(NSString *)key
					  pack:(NSString *)packId
				completion:(void (^)(NSString *value, NSString *kind))completion;

/// Install a pack Telegram serves for this api_id.
- (void)addCustomServerLanguagePack:(NSString *)packId
						 completion:(void (^)(BOOL ok))completion;

/// Create or replace a local custom pack. `strings` are dictionaries with
/// "key" and "value"; an empty list makes a pack with no overrides.
- (void)setCustomLanguagePack:(NSString *)packId
						 name:(NSString *)name
				   nativeName:(NSString *)nativeName
					  strings:(NSArray *)strings
				   completion:(void (^)(BOOL ok))completion;

/// Add, change or delete one string in a local custom pack. A nil `value`
/// sends the deleted marker, which is how a custom pack says "use the base".
- (void)setCustomLanguagePackString:(NSString *)key
							  value:(NSString *)value
							   pack:(NSString *)packId
						 completion:(void (^)(BOOL ok))completion;

/// Edit a custom pack's record without touching its strings.
- (void)editCustomLanguagePackInfo:(NSDictionary *)info
						completion:(void (^)(BOOL ok))completion;

/// Ask Telegram for the latest strings, then redraw.
- (void)synchronizeLanguagePack:(NSString *)packId
					 completion:(void (^)(BOOL ok))completion;

- (void)deleteLanguagePack:(NSString *)packId
				completion:(void (^)(BOOL ok))completion;

#pragma mark - countries

/// "code", "name", "englishName", "flag", "hidden" and "callingCodes" for an
/// ISO 3166-1 alpha-2 code. nil when Telegram does not know it.
- (void)countryInfoForCode:(NSString *)countryCode
				completion:(void (^)(NSDictionary *country))completion;

/// The IETF language tag Telegram prefers for a country, or nil.
- (void)preferredCountryLanguageForCode:(NSString *)countryCode
							 completion:(void (^)(NSString *languageCode))completion;

/// The flag emoji for a country code, read synchronously where the library
/// supports it. nil when Telegram has no flag for it.
- (void)countryFlagEmojiForCode:(NSString *)countryCode
					 completion:(void (^)(NSString *emoji))completion;

#pragma mark - formatting and translation

/// Run the composer's text through TDLib's Markdown parser. The answer is a
/// formattedText dictionary with "text" and "entities".
- (void)parseMarkdownText:(NSString *)text
			   completion:(void (^)(NSDictionary *formatted))completion;

/// Mentions, hashtags, URLs, emails and the rest TDLib finds in a string.
/// Each entity carries "offset", "length" and "type" (the TextEntityType
/// name).
- (void)textEntitiesInText:(NSString *)text
				completion:(void (^)(NSArray *entities))completion;

/// Translate one piece of text into `languageCode`, keeping its formatting.
- (void)translateText:(NSString *)text
	   toLanguageCode:(NSString *)languageCode
				 tone:(NSString *)tone
		   completion:(void (^)(NSString *text))completion;

@end
