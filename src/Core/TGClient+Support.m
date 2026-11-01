//
// TGClient+Support.m
//
#import "TGClient+Support.h"
#import "TGClientInternal.h"

static NSDictionary *TGSUPDict(id value) {
	return [value isKindOfClass:NSDictionary.class] ? value : @{};
}

static NSString *TGSUPString(id value) {
	return [value isKindOfClass:NSString.class] ? value : @"";
}

static NSNumber *TGSUPNumber(id value) {
	return [value isKindOfClass:NSNumber.class] ? value : @0;
}

static NSString *TGSUPErrorText(NSDictionary *result) {
	NSString *message = result[@"message"];
	return [message isKindOfClass:NSString.class] && message.length
			? message : @"Telegram refused that.";
}

static BOOL TGSUPFailed(NSDictionary *result) {
	return [result[@"@type"] isEqualToString:@"error"];
}

static NSDictionary *TGSUPInfo(NSDictionary *result) {
	NSDictionary *text = TGSUPDict(result[@"message"]);
	return @{
		@"message" : TGSUPString(text[@"text"]),
		@"author" : TGSUPString(result[@"author"]),
		@"date" : TGSUPNumber(result[@"date"]),
	};
}

@implementation TGClient (Support)

- (void)supportNameWithCompletion:(void (^)(NSString *, NSString *))completion {
	[self request:@{@"@type" : @"getSupportName"}
	   completion:^(NSDictionary *result){
		if (TGSUPFailed(result)){
			if (completion) completion(nil, TGSUPErrorText(result));
			return;
		}
		if (completion) completion(TGSUPString(result[@"text"]), nil);
	}];
}

- (void)supportInfoForUser:(int64_t)userId
				completion:(void (^)(NSDictionary *, NSString *))completion {
	if (!userId){
		if (completion) completion(nil, @"A user id is needed.");
		return;
	}
	[self request:@{@"@type" : @"getUserSupportInfo", @"user_id" : @(userId)}
	   completion:^(NSDictionary *result){
		if (TGSUPFailed(result)){
			if (completion) completion(nil, TGSUPErrorText(result));
			return;
		}
		if (completion) completion(TGSUPInfo(result), nil);
	}];
}

- (void)setSupportInfo:(NSString *)message
				forUser:(int64_t)userId
			 completion:(void (^)(NSDictionary *, NSString *))completion {
	if (!userId){
		if (completion) completion(nil, @"A user id is needed.");
		return;
	}
	[self request:@{
		@"@type" : @"setUserSupportInfo",
		@"user_id" : @(userId),
		@"message" : TGFormattedText(TGSUPString(message)),
	} completion:^(NSDictionary *result){
		if (TGSUPFailed(result)){
			if (completion) completion(nil, TGSUPErrorText(result));
			return;
		}
		if (completion) completion(TGSUPInfo(result), nil);
	}];
}

@end

// vim:ft=objc
