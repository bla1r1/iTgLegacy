//
// TGClient+Websites.h - the sites signed in to this account through a bot.
//
// A website login is a bot handshake: the site shows a Telegram login, the
// account approves it, and TDLib keeps a connectedWebsite record. These three
// calls are the whole screen: read the list, sign one out, or sign them all
// out in one stroke.
//
#import "TGClient+Base.h"

@interface TGClient (Websites)

/// Every site still signed in: "id" (NSNumber, what disconnectWebsite takes),
/// "domain", "botUserId", "browser", "platform", "ip", "location",
/// "loginDate" and "lastActive" (unix seconds). Nil with `error` when
/// Telegram refuses the read.
- (void)connectedWebsitesWithCompletion:(void (^)(NSArray *sites,
												  NSString *error))completion;

/// Signs one site out. The site loses the token on its next request, not
/// when this call returns, so the screen re-reads the list after a moment.
- (void)disconnectWebsite:(int64_t)websiteId
			   completion:(void (^)(BOOL ok, NSString *error))completion;

- (void)disconnectAllWebsitesWithCompletion:(void (^)(BOOL ok,
													  NSString *error))completion;

@end
