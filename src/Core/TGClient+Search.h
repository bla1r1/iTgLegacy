//
// TGClient+Search.h - hashtags, public post search, link resolution and the
// web page reader. The search screen and the link sheet read from here.
//
#import "TGClient+Base.h"

@interface TGClient (Search)

#pragma mark - hashtags

/// Hashtags Telegram knows that start with `prefix`, which is what the
/// search screen offers under the query as it is typed.
- (void)searchHashtags:(NSString *)prefix
				 limit:(NSInteger)limit
			completion:(void (^)(NSArray *hashtags))completion;

/// The tags this account has searched for before. An empty prefix asks for
/// the whole recent list, which is the empty state of the search screen.
- (void)searchedForTagsWithPrefix:(NSString *)prefix
							limit:(NSInteger)limit
					   completion:(void (^)(NSArray *hashtags))completion;

/// The older spellings the screen uses for its two lists. Both are the same
/// request with a different name, kept apart because the removal methods act
/// on different lists.
- (void)recentHashtagsWithCompletion:(void (^)(NSArray *hashtags))completion;

/// Drop one tag out of the recent-hashtag log the composer's suggestions
/// read, and out of the searched-for list the search screen shows.
- (void)removeRecentHashtag:(NSString *)hashtag;
- (void)removeSearchedForTag:(NSString *)tag;

/// Forget every searched-for tag in one request.
- (void)clearSearchedForTags;

#pragma mark - public post search

/// What Telegram will charge for a public post search, and how many free
/// queries are left today. The search screen reads this before it asks.
- (void)publicPostSearchLimitsForQuery:(NSString *)query
							completion:(void (^)(NSDictionary *limits))completion;

/// Public posts matching `query`, newest first. `offset` is the string the
/// previous answer named; `starCount` is 0 while a free query is available.
/// The completion gets the raw message list, the next offset, the limits the
/// answer carried and whether Telegram refused because the allowance ran out.
- (void)searchPublicPosts:(NSString *)query
				   offset:(NSString *)offset
					limit:(NSInteger)limit
				starCount:(NSInteger)starCount
			   completion:(void (^)(NSArray *messages, NSString *next,
									NSDictionary *limits, BOOL exceeded))completion;

#pragma mark - links

/// The URL Telegram wants opened for an external link, after the optional
/// write-access confirmation. Empty when the link is not a login link, which
/// is the usual case.
- (void)externalLinkForURL:(NSString *)url
		   allowWriteAccess:(BOOL)allowWriteAccess
				completion:(void (^)(NSString *link))completion;

/// What an external link will do: open straight away, or ask before signing
/// in. The dictionary carries "kind" ("open" or "confirm"), "url", "domain",
/// "botUserId" and "requestWriteAccess".
- (void)externalLinkInfoForURL:(NSString *)url
					completion:(void (^)(NSDictionary *info))completion;

/// The canonical t.me or tg:// URL for an internalLinkType object. `http`
/// asks for an HTTPS link where Telegram can make one.
- (void)internalLinkForType:(NSDictionary *)type
					   http:(BOOL)http
				 completion:(void (^)(NSString *link))completion;
/// "external" or "inApp": the browser Telegram requires for a link. An empty
/// answer means Telegram did not recognise the host.
- (void)webBrowserTypeForURL:(NSString *)url
				  completion:(void (^)(NSString *kind))completion;

/// The entries of `strings` whose words start with `query`, in the order
/// Telegram ranked them. The search screen feeds it the chat titles it
/// already has, so a prefix suggestion costs one local round trip.
- (void)stringsMatchingPrefix:(NSArray *)strings
						query:(NSString *)query
						limit:(NSInteger)limit
				   completion:(void (^)(NSArray *matches))completion;

/// The reader view of a web page: "blocks" (PageBlock dictionaries),
/// "viewCount", "version", "rtl" and "full". nil when Telegram has no
/// instant view for the URL.
- (void)instantViewForURL:(NSString *)url
				onlyLocal:(BOOL)onlyLocal
			   completion:(void (^)(NSDictionary *view))completion;

/// t.me links a newly registered account followed before it had a chat
/// list. Each entry carries "url" and "kind" (the TMeUrlType name).
- (void)recentlyVisitedTMeUrlsWithReferrer:(NSString *)referrer
								completion:(void (^)(NSArray *urls))completion;

#pragma mark - quote search

/// Where `quote` starts in `text`, in UTF-16 units, starting from the
/// caller's approximate position. `found` is NO when Telegram answers 404.
- (void)searchQuote:(NSString *)quote
			 inText:(NSString *)text
		   position:(NSInteger)position
		 completion:(void (^)(NSInteger position, BOOL found))completion;

@end
