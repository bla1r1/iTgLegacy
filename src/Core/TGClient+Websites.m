//
// TGClient+Websites.m - connected websites.
//
#import "TGClient+Websites.h"
#import "TGClientInternal.h"

static NSString *TGWebsiteError(NSDictionary *result) {
	NSString *message = result[@"message"];
	return [message isKindOfClass:NSString.class] ? message : @"Telegram refused that.";
}

static NSString *TGWebsiteString(NSDictionary *site, NSString *key) {
	id value = site[key];
	return [value isKindOfClass:NSString.class] ? value : @"";
}

@implementation TGClient (Websites)

- (void)connectedWebsitesWithCompletion:(void (^)(NSArray *, NSString *))completion {
	[self request:@{@"@type" : @"getConnectedWebsites"}
	   completion:^(NSDictionary *result){
		if ([result[@"@type"] isEqualToString:@"error"]){
			if (completion) completion(nil, TGWebsiteError(result));
			return;
		}
		NSMutableArray *sites = [NSMutableArray array];
		for (NSDictionary *site in result[@"websites"]){
			if (![site isKindOfClass:NSDictionary.class])
				continue;
			[sites addObject:@{
				@"id"         : @([site[@"id"] longLongValue]),
				@"domain"     : TGWebsiteString(site, @"domain_name"),
				@"botUserId"  : @([site[@"bot_user_id"] longLongValue]),
				@"browser"    : TGWebsiteString(site, @"browser"),
				@"platform"   : TGWebsiteString(site, @"platform"),
				@"ip"         : TGWebsiteString(site, @"ip_address"),
				@"location"   : TGWebsiteString(site, @"location"),
				@"loginDate"  : site[@"log_in_date"] ?: @0,
				@"lastActive" : site[@"last_active_date"] ?: @0,
			}];
		}
		if (completion) completion(sites, nil);
	}];
}

- (void)disconnectWebsite:(int64_t)websiteId
			   completion:(void (^)(BOOL, NSString *))completion {
	if (!websiteId){
		if (completion) completion(NO, @"No website was named.");
		return;
	}
	[self request:@{@"@type" : @"disconnectWebsite", @"website_id" : @(websiteId)}
	   completion:^(NSDictionary *result){
		BOOL failed = [result[@"@type"] isEqualToString:@"error"];
		if (completion)
			completion(!failed, failed ? TGWebsiteError(result) : nil);
	}];
}

- (void)disconnectAllWebsitesWithCompletion:(void (^)(BOOL, NSString *))completion {
	[self request:@{@"@type" : @"disconnectAllWebsites"}
	   completion:^(NSDictionary *result){
		BOOL failed = [result[@"@type"] isEqualToString:@"error"];
		if (completion)
			completion(!failed, failed ? TGWebsiteError(result) : nil);
	}];
}

@end

// vim:ft=objc
