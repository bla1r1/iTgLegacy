//
// TGClient+Appearance.h - Telegram's chat backgrounds: the installed list,
// the catalogue search, the default, and the URL behind a name.
//
#import "TGClient+Base.h"

@interface TGClient (Appearance)

/// The backgrounds this account has installed. Each dictionary carries "id",
/// "name" (Telegram's remote name, empty for a local fill), "title" (always
/// drawable), "isDefault", "isDark", "typeName" ("wallpaper", "pattern",
/// "fill" or "chatTheme"), the raw "type" object TDLib answers with, "fileId"
/// (a preview thumbnail when the background has one, otherwise 0) and
/// "fillColour" (an RGB integer, or -1 when the background is a picture).
- (void)installedBackgroundsForDarkTheme:(BOOL)darkTheme
							  completion:(void (^)(NSArray *backgrounds,
												   NSString *error))completion;

/// Telegram's catalogue by name. One background, or nil and the server's
/// sentence.
- (void)searchBackgroundNamed:(NSString *)name
				   completion:(void (^)(NSDictionary *background,
										NSString *error))completion;

/// Makes `background` the default for chats and adds it to the installed
/// list. The returned dictionary is TDLib's background record, flattened the
/// same way as the installed list. Nil and the refusal otherwise.
- (void)setDefaultBackground:(NSDictionary *)background
				forDarkTheme:(BOOL)darkTheme
				  completion:(void (^)(NSDictionary *installed,
									   NSString *error))completion;

/// Drops one id from the installed list. A background that is the default
/// stays the default for chats until deleteDefaultBackground is sent.
- (void)removeInstalledBackground:(int64_t)backgroundId
					   completion:(void (^)(BOOL ok, NSString *error))completion;

/// Puts the installed list back to Telegram's default set.
- (void)resetInstalledBackgroundsWithCompletion:
		(void (^)(BOOL ok, NSString *error))completion;

/// Removes the default chat background. `darkTheme` chooses which theme's
/// default is removed.
- (void)deleteDefaultBackgroundForDarkTheme:(BOOL)darkTheme
								 completion:(void (^)(BOOL ok,
													  NSString *error))completion;

/// The persistent HTTP address Telegram serves this background from.
/// `background` is one of the flattened dictionaries above. A chat theme has
/// no address and answers an error without a request.
- (void)backgroundUrlForBackground:(NSDictionary *)background
						completion:(void (^)(NSString *url,
											 NSString *error))completion;

@end
