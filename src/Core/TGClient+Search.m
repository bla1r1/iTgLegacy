//
// TGClient+Search.m - the search box's server half, link resolution and the
// Instant View reader. Everything here is a screen asking Telegram rather
// than a local guess: hashtags, public posts, link previews and quotes all
// change meaning server-side.
//
#import "TGClientInternal.h"

static NSDictionary *TGPlainFormattedText(NSString *text) {
	return @{@"@type" : @"formattedText",
			 @"text" : text ?: @"",
			 @"entities" : @[]};
}

/// The synchronous functions try execute first and fall back to the request
/// loop when the dylib has no execute symbol, which is how the host build
/// sees them.
static void TGSearchTextAnswer(TGClient *client, NSDictionary *request,
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

/// Every hashtag TDLib answers with, as plain strings. The answer repeats
/// the string in two shapes and a row only needs one.
static NSArray *TGHashtagsFrom(NSDictionary *result) {
	NSMutableArray *out = [NSMutableArray array];
	for (id tag in result[@"hashtags"]){
		if ([tag isKindOfClass:NSString.class] && [tag length])
			[out addObject:tag];
	}
	return out;
}

@implementation TGClient (Search)

#pragma mark - hashtags

- (void)searchHashtags:(NSString *)prefix
				 limit:(NSInteger)limit
			completion:(void (^)(NSArray *))completion {
	NSString *clean = [prefix stringByTrimmingCharactersInSet:
			[NSCharacterSet whitespaceAndNewlineCharacterSet]];
	// The hash is the marker, not part of the prefix Telegram matches.
	if ([clean hasPrefix:@"#"])
		clean = [clean substringFromIndex:1];
	[self request:@{@"@type" : @"searchHashtags",
					@"prefix" : clean ?: @"",
					@"limit" : @(limit > 0 ? limit : 10)}
	   completion:^(NSDictionary *result){
		if (completion)
			completion(TGHashtagsFrom(result));
	}];
}

- (void)searchedForTagsWithPrefix:(NSString *)prefix
							limit:(NSInteger)limit
					   completion:(void (^)(NSArray *))completion {
	NSString *clean = [prefix stringByTrimmingCharactersInSet:
			[NSCharacterSet whitespaceAndNewlineCharacterSet]];
	if ([clean hasPrefix:@"#"])
		clean = [clean substringFromIndex:1];
	[self request:@{@"@type" : @"getSearchedForTags",
					@"tag_prefix" : clean ?: @"",
					@"limit" : @(limit > 0 ? limit : 20)}
	   completion:^(NSDictionary *result){
		if (completion)
			completion(TGHashtagsFrom(result));
	}];
}

- (void)recentHashtagsWithCompletion:(void (^)(NSArray *))completion {
	// An empty prefix is the whole recent list, which is what the empty
	// search screen shows under Recently Found.
	[self searchedForTagsWithPrefix:@"" limit:20 completion:completion];
}

- (void)removeRecentHashtag:(NSString *)hashtag {
	if (!hashtag.length)
		return;
	[self send:@{@"@type" : @"removeRecentHashtag",
				 @"hashtag" : hashtag}];
}

- (void)removeSearchedForTag:(NSString *)tag {
	if (!tag.length)
		return;
	[self send:@{@"@type" : @"removeSearchedForTag",
				 @"tag" : tag}];
}

- (void)clearSearchedForTags {
	[self send:@{@"@type" : @"clearSearchedForTags"}];
}

#pragma mark - public post search

- (void)publicPostSearchLimitsForQuery:(NSString *)query
							completion:(void (^)(NSDictionary *))completion {
	[self request:@{@"@type" : @"getPublicPostSearchLimits",
					@"query" : query ?: @""}
	   completion:^(NSDictionary *result){
		if (!completion)
			return;
		if (![result[@"@type"] isEqualToString:@"publicPostSearchLimits"]){
			completion(nil);
			return;
		}
		completion(@{
			@"dailyFree"     : result[@"daily_free_query_count"] ?: @(0),
			@"remainingFree" : result[@"remaining_free_query_count"] ?: @(0),
			@"nextFreeIn"    : result[@"next_free_query_in"] ?: @(0),
			@"starCount"     : result[@"star_count"] ?: @(0),
			@"currentIsFree" : result[@"is_current_query_free"] ?: @NO,
		});
	}];
}

- (void)searchPublicPosts:(NSString *)query
				   offset:(NSString *)offset
					limit:(NSInteger)limit
				starCount:(NSInteger)starCount
			   completion:(void (^)(NSArray *, NSString *, NSDictionary *, BOOL))completion {
	NSString *clean = [query stringByTrimmingCharactersInSet:
			[NSCharacterSet whitespaceAndNewlineCharacterSet]];
	if (!clean.length){
		if (completion)
			completion(@[], nil, nil, NO);
		return;
	}
	[self request:@{@"@type" : @"searchPublicPosts",
					@"query" : clean,
					@"offset" : offset ?: @"",
					@"limit" : @(limit > 0 ? limit : 20),
					@"star_count" : @(MAX(0, starCount))}
	   completion:^(NSDictionary *result){
		if (!completion)
			return;
		if (![result[@"@type"] isEqualToString:@"foundPublicPosts"]){
			// A limit refusal is an error object. Its message is the only
			// sentence Telegram gives, and the screen already has the limits
			// answer that says when the next free query is.
			completion(nil, nil, nil, [result[@"message"] isKindOfClass:NSString.class]);
			return;
		}
		NSDictionary *raw = result[@"search_limits"];
		NSDictionary *limits = nil;
		if ([raw isKindOfClass:NSDictionary.class]){
			limits = @{
				@"dailyFree"     : raw[@"daily_free_query_count"] ?: @(0),
				@"remainingFree" : raw[@"remaining_free_query_count"] ?: @(0),
				@"nextFreeIn"    : raw[@"next_free_query_in"] ?: @(0),
				@"starCount"     : raw[@"star_count"] ?: @(0),
				@"currentIsFree" : raw[@"is_current_query_free"] ?: @NO,
			};
		}
		completion(result[@"messages"] ?: @[],
				   result[@"next_offset"] ?: @"",
				   limits,
				   [result[@"are_limits_exceeded"] boolValue]);
	}];
}

#pragma mark - links

- (void)externalLinkForURL:(NSString *)url
		   allowWriteAccess:(BOOL)allowWriteAccess
				completion:(void (^)(NSString *))completion {
	if (!url.length){
		if (completion) completion(nil);
		return;
	}
	[self request:@{@"@type" : @"getExternalLink",
					@"link" : url,
					@"allow_write_access" : @(allowWriteAccess)}
	   completion:^(NSDictionary *result){
		NSString *link = [result[@"@type"] isEqualToString:@"httpUrl"]
				? result[@"url"] : nil;
		if (completion)
			completion([link isKindOfClass:NSString.class] ? link : nil);
	}];
}

- (void)externalLinkInfoForURL:(NSString *)url
					completion:(void (^)(NSDictionary *))completion {
	if (!url.length){
		if (completion) completion(nil);
		return;
	}
	[self request:@{@"@type" : @"getExternalLinkInfo",
					@"link" : url}
	   completion:^(NSDictionary *result){
		if (!completion)
			return;
		NSString *type = result[@"@type"] ?: @"";
		if ([type isEqualToString:@"loginUrlInfoOpen"]){
			completion(@{
				@"kind" : @"open",
				@"url" : result[@"url"] ?: url,
				@"confirmed" : @([result[@"skip_confirmation"] boolValue]),
				@"requestWriteAccess" : @NO,
			});
		} else if ([type isEqualToString:@"loginUrlInfoRequestConfirmation"]){
			completion(@{
				@"kind" : @"confirm",
				@"url" : result[@"url"] ?: url,
				@"domain" : result[@"domain"] ?: @"",
				@"botUserId" : result[@"bot_user_id"] ?: @(0),
				@"requestWriteAccess" : result[@"request_write_access"] ?: @NO,
				@"confirmed" : @NO,
			});
		} else {
			// A normal link has no login action, and TDLib answers 404. That
			// is not a failure: it means open it and ask nothing.
			completion(nil);
		}
	}];
}

- (void)internalLinkForType:(NSDictionary *)type
					   http:(BOOL)http
				 completion:(void (^)(NSString *))completion {
	if (![type[@"@type"] length]){
		if (completion) completion(nil);
		return;
	}
	[self request:@{@"@type" : @"getInternalLink",
					@"type" : type,
					@"is_http" : @(http)}
	   completion:^(NSDictionary *result){
		NSString *link = [result[@"@type"] isEqualToString:@"httpUrl"]
				? result[@"url"] : nil;
		if (completion)
			completion([link isKindOfClass:NSString.class] ? link : nil);
	}];
}

- (void)webBrowserTypeForURL:(NSString *)url
				  completion:(void (^)(NSString *))completion {
	if (!url.length){
		if (completion) completion(nil);
		return;
	}
	[self request:@{@"@type" : @"getLinkWebBrowserType",
					@"link" : url}
	   completion:^(NSDictionary *result){
		if (!completion)
			return;
		NSString *type = result[@"@type"] ?: @"";
		if ([type isEqualToString:@"webBrowserTypeInApp"])
			completion(@"inApp");
		else if ([type isEqualToString:@"webBrowserTypeExternal"])
			completion(@"external");
		else
			completion(nil);
	}];
}

- (void)stringsMatchingPrefix:(NSArray *)strings
						query:(NSString *)query
						limit:(NSInteger)limit
				   completion:(void (^)(NSArray *))completion {
	NSString *clean = [query stringByTrimmingCharactersInSet:
			[NSCharacterSet whitespaceAndNewlineCharacterSet]];
	if (!strings.count || !clean.length){
		if (completion) completion(@[]);
		return;
	}
	// searchStringsByPrefix is documented as synchronous; the async request
	// is the fallback for a build whose dylib has no execute symbol.
	NSDictionary *request = @{
		@"@type" : @"searchStringsByPrefix",
		@"strings" : strings,
		@"query" : clean,
		@"limit" : @(limit > 0 ? limit : 10),
		@"return_none_for_empty_query" : @YES,
	};
	TGSearchTextAnswer(self, request, ^(NSDictionary *answer){
		if (!completion)
			return;
		if (![answer[@"@type"] isEqualToString:@"foundPositions"]){
			completion(@[]);
			return;
		}
		NSMutableArray *out = [NSMutableArray array];
		for (NSNumber *position in answer[@"positions"]){
			if (![position isKindOfClass:NSNumber.class])
				continue;
			NSInteger index = position.integerValue;
			if (index >= 0 && index < (NSInteger)strings.count)
				[out addObject:strings[(NSUInteger)index]];
		}
		completion(out);
	});
}

- (void)instantViewForURL:(NSString *)url
				onlyLocal:(BOOL)onlyLocal
			   completion:(void (^)(NSDictionary *))completion {
	if (!url.length){
		if (completion) completion(nil);
		return;
	}
	[self request:@{@"@type" : @"getWebPageInstantView",
					@"url" : url,
					@"only_local" : @(onlyLocal)}
	   completion:^(NSDictionary *result){
		if (!completion)
			return;
		if (![result[@"@type"] isEqualToString:@"webPageInstantView"]){
			completion(nil);
			return;
		}
		completion(@{
			@"blocks" : result[@"blocks"] ?: @[],
			@"viewCount" : result[@"view_count"] ?: @(0),
			@"version" : result[@"version"] ?: @(0),
			@"rtl" : result[@"is_rtl"] ?: @NO,
			@"full" : result[@"is_full"] ?: @NO,
		});
	}];
}

- (void)recentlyVisitedTMeUrlsWithReferrer:(NSString *)referrer
								completion:(void (^)(NSArray *))completion {
	[self request:@{@"@type" : @"getRecentlyVisitedTMeUrls",
					@"referrer" : referrer ?: @""}
	   completion:^(NSDictionary *result){
		if (!completion)
			return;
		NSMutableArray *out = [NSMutableArray array];
		for (NSDictionary *entry in result[@"urls"]){
			if (![entry isKindOfClass:NSDictionary.class])
				continue;
			NSDictionary *type = [entry[@"type"] isKindOfClass:NSDictionary.class]
					? entry[@"type"] : @{};
			NSString *kind = [type[@"@type"] isKindOfClass:NSString.class]
					? type[@"@type"] : @"";
			[out addObject:@{
				@"url" : entry[@"url"] ?: @"",
				@"kind" : kind,
				@"userId" : type[@"user_id"] ?: @(0),
				@"supergroupId" : type[@"supergroup_id"] ?: @(0),
			}];
		}
		completion(out);
	}];
}

#pragma mark - quote search

- (void)searchQuote:(NSString *)quote
			 inText:(NSString *)text
		   position:(NSInteger)position
		 completion:(void (^)(NSInteger, BOOL))completion {
	if (!quote.length || !text.length){
		if (completion) completion(-1, NO);
		return;
	}
	NSDictionary *request = @{
		@"@type" : @"searchQuote",
		@"text" : TGPlainFormattedText(text),
		@"quote" : TGPlainFormattedText(quote),
		@"quote_position" : @(MAX(0, position)),
	};

	// searchQuote is documented as synchronous, so on a device it answers
	// without a round trip. The host has no tdjson and a few builds ship
	// without the execute symbol; the async request keeps the screen honest
	// there instead of making the row do nothing.
	NSDictionary *sync = [self executeSynchronously:request];
	if (sync){
		BOOL found = [sync[@"@type"] isEqualToString:@"foundPosition"];
		if (completion)
			completion(found ? [sync[@"position"] integerValue] : -1, found);
		return;
	}
	[self request:request completion:^(NSDictionary *result){
		BOOL found = [result[@"@type"] isEqualToString:@"foundPosition"];
		if (completion)
			completion(found ? [result[@"position"] integerValue] : -1, found);
	}];
}

@end
