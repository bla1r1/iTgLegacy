//
// TGClient+Affiliate.m
//
// Telegram pays affiliates through Fragment. This build has no wallet and
// cannot withdraw, but the program records are ordinary TDLib reads and
// writes: the catalogue, the connection and a channel's own parameters. The
// screen prints Telegram's answer, including a refusal on an account that
// owns neither a bot nor a channel.
//
#import "TGClient+Affiliate.h"
#import "TGClientInternal.h"

static NSDictionary *TGAFFDict(id value) {
	return [value isKindOfClass:NSDictionary.class] ? value : @{};
}

static NSArray *TGAFFArray(id value) {
	return [value isKindOfClass:NSArray.class] ? value : @[];
}

static NSString *TGAFFString(id value) {
	return [value isKindOfClass:NSString.class] ? value : @"";
}

static NSNumber *TGAFFNumber(id value) {
	return [value isKindOfClass:NSNumber.class] ? value : @0;
}

static NSString *TGAFFErrorText(NSDictionary *result) {
	NSString *message = result[@"message"];
	return [message isKindOfClass:NSString.class] && message.length
			? message : @"Telegram refused that.";
}

static BOOL TGAFFFailed(NSDictionary *result) {
	return [result[@"@type"] isEqualToString:@"error"];
}

/// affiliateType from the three kinds the screen offers. The channel case
/// uses the chat id because that is the id the affiliate record is keyed on.
static NSDictionary *TGAFFAffiliate(NSString *kind, int64_t botUserId,
									int64_t chatId) {
	if ([kind isEqualToString:@"bot"])
		return @{@"@type" : @"affiliateTypeBot", @"user_id" : @(botUserId)};
	if ([kind isEqualToString:@"channel"])
		return @{@"@type" : @"affiliateTypeChannel", @"chat_id" : @(chatId)};
	return @{@"@type" : @"affiliateTypeCurrentUser"};
}

static NSDictionary *TGAFFParameters(NSDictionary *parameters) {
	return @{
		@"@type" : @"affiliateProgramParameters",
		@"commission_per_mille" : TGAFFNumber(parameters[@"commission_per_mille"]),
		@"month_count" : TGAFFNumber(parameters[@"month_count"]),
	};
}

static NSDictionary *TGAFFStarAmount(NSDictionary *amount) {
	return @{
		@"starCount" : TGAFFNumber(amount[@"star_count"]),
		@"nanostarCount" : TGAFFNumber(amount[@"nanostar_count"]),
	};
}

static NSDictionary *TGAFFProgramInfo(NSDictionary *info) {
	NSDictionary *parameters = TGAFFDict(info[@"parameters"]);
	return @{
		@"commissionPerMille" : TGAFFNumber(parameters[@"commission_per_mille"]),
		@"monthCount" : TGAFFNumber(parameters[@"month_count"]),
		@"endDate" : TGAFFNumber(info[@"end_date"]),
		@"dailyRevenue" : TGAFFStarAmount(TGAFFDict(
				info[@"daily_revenue_per_user_amount"])),
	};
}

static NSDictionary *TGAFFConnected(NSDictionary *program) {
	NSDictionary *parameters = TGAFFDict(program[@"parameters"]);
	return @{
		@"url" : TGAFFString(program[@"url"]),
		@"botUserId" : TGAFFNumber(program[@"bot_user_id"]),
		@"commissionPerMille" : TGAFFNumber(parameters[@"commission_per_mille"]),
		@"monthCount" : TGAFFNumber(parameters[@"month_count"]),
		@"connectionDate" : TGAFFNumber(program[@"connection_date"]),
		@"disconnected" : @([program[@"is_disconnected"] boolValue]),
		@"userCount" : TGAFFNumber(program[@"user_count"]),
		@"revenueStarCount" : TGAFFNumber(program[@"revenue_star_count"]),
	};
}

static NSDictionary *TGAFFFound(NSDictionary *program) {
	NSDictionary *info = TGAFFDict(program[@"info"]);
	return @{
		@"botUserId" : TGAFFNumber(program[@"bot_user_id"]),
		@"info" : TGAFFProgramInfo(info),
	};
}

static NSDictionary *TGAFFPage(NSDictionary *result) {
	NSMutableArray *rows = [NSMutableArray array];
	NSString *type = TGAFFString(result[@"@type"]);
	for (NSDictionary *program in TGAFFArray(result[@"programs"])){
		if (![program isKindOfClass:NSDictionary.class])
			continue;
		[rows addObject:[type isEqualToString:@"foundAffiliatePrograms"]
				? TGAFFFound(program) : TGAFFConnected(program)];
	}
	return @{
		@"totalCount" : TGAFFNumber(result[@"total_count"]),
		@"nextOffset" : TGAFFString(result[@"next_offset"]),
		@"programs" : rows,
		@"found" : @([type isEqualToString:@"foundAffiliatePrograms"]),
	};
}

@implementation TGClient (Affiliate)

- (void)searchAffiliateProgramsForKind:(NSString *)kind
							 botUserId:(int64_t)botUserId
								chatId:(int64_t)chatId
							  sortOrder:(NSString *)sort
								 offset:(NSString *)offset
								  limit:(int32_t)limit
							 completion:(void (^)(NSDictionary *, NSString *))completion {
	NSString *sortType = @"affiliateProgramSortOrderProfitability";
	if ([sort isEqualToString:@"creationDate"])
		sortType = @"affiliateProgramSortOrderCreationDate";
	else if ([sort isEqualToString:@"revenue"])
		sortType = @"affiliateProgramSortOrderRevenue";
	[self request:@{
		@"@type" : @"searchAffiliatePrograms",
		@"affiliate" : TGAFFAffiliate(kind, botUserId, chatId),
		@"sort_order" : @{@"@type" : sortType},
		@"offset" : TGAFFString(offset),
		@"limit" : @(limit > 0 ? limit : 20),
	} completion:^(NSDictionary *result){
		if (TGAFFFailed(result)){
			if (completion) completion(nil, TGAFFErrorText(result));
			return;
		}
		if (completion) completion(TGAFFPage(result), nil);
	}];
}

- (void)connectedAffiliateProgramsForKind:(NSString *)kind
								botUserId:(int64_t)botUserId
								   chatId:(int64_t)chatId
								   offset:(NSString *)offset
									limit:(int32_t)limit
							   completion:(void (^)(NSDictionary *, NSString *))completion {
	[self request:@{
		@"@type" : @"getConnectedAffiliatePrograms",
		@"affiliate" : TGAFFAffiliate(kind, botUserId, chatId),
		@"offset" : TGAFFString(offset),
		@"limit" : @(limit > 0 ? limit : 20),
	} completion:^(NSDictionary *result){
		if (TGAFFFailed(result)){
			if (completion) completion(nil, TGAFFErrorText(result));
			return;
		}
		if (completion) completion(TGAFFPage(result), nil);
	}];
}

- (void)connectedAffiliateProgramForKind:(NSString *)kind
							   botUserId:(int64_t)botUserId
								  chatId:(int64_t)chatId
						  programBotUserId:(int64_t)programBotUserId
							  completion:(void (^)(NSDictionary *, NSString *))completion {
	if (!programBotUserId){
		if (completion) completion(nil, @"The program's bot user id is needed.");
		return;
	}
	[self request:@{
		@"@type" : @"getConnectedAffiliateProgram",
		@"affiliate" : TGAFFAffiliate(kind, botUserId, chatId),
		@"bot_user_id" : @(programBotUserId),
	} completion:^(NSDictionary *result){
		if (TGAFFFailed(result)){
			if (completion) completion(nil, TGAFFErrorText(result));
			return;
		}
		if (completion) completion(TGAFFConnected(result), nil);
	}];
}

- (void)connectAffiliateProgramForKind:(NSString *)kind
							 botUserId:(int64_t)botUserId
								chatId:(int64_t)chatId
						programBotUserId:(int64_t)programBotUserId
							completion:(void (^)(NSDictionary *, NSString *))completion {
	if (!programBotUserId){
		if (completion) completion(nil, @"The program's bot user id is needed.");
		return;
	}
	[self request:@{
		@"@type" : @"connectAffiliateProgram",
		@"affiliate" : TGAFFAffiliate(kind, botUserId, chatId),
		@"bot_user_id" : @(programBotUserId),
	} completion:^(NSDictionary *result){
		if (TGAFFFailed(result)){
			if (completion) completion(nil, TGAFFErrorText(result));
			return;
		}
		if (completion) completion(TGAFFConnected(result), nil);
	}];
}

- (void)disconnectAffiliateProgramForKind:(NSString *)kind
								botUserId:(int64_t)botUserId
								   chatId:(int64_t)chatId
									  url:(NSString *)url
							   completion:(void (^)(NSDictionary *, NSString *))completion {
	NSString *address = TGAFFString(url);
	if (!address.length){
		if (completion) completion(nil, @"A connection URL is needed.");
		return;
	}
	[self request:@{
		@"@type" : @"disconnectAffiliateProgram",
		@"affiliate" : TGAFFAffiliate(kind, botUserId, chatId),
		@"url" : address,
	} completion:^(NSDictionary *result){
		if (TGAFFFailed(result)){
			if (completion) completion(nil, TGAFFErrorText(result));
			return;
		}
		if (completion) completion(TGAFFConnected(result), nil);
	}];
}

- (void)searchChatAffiliateProgram:(NSString *)username
						  referrer:(NSString *)referrer
						completion:(void (^)(NSDictionary *, NSString *))completion {
	NSString *name = TGAFFString(username);
	if (!name.length){
		if (completion) completion(nil, @"A username is needed.");
		return;
	}
	[self request:@{
		@"@type" : @"searchChatAffiliateProgram",
		@"username" : name,
		@"referrer" : TGAFFString(referrer),
	} completion:^(NSDictionary *result){
		if (TGAFFFailed(result)){
			if (completion) completion(nil, TGAFFErrorText(result));
			return;
		}
		NSDictionary *chat = @{
			@"id" : TGAFFNumber(result[@"id"]),
			@"title" : TGAFFString(result[@"title"]),
		};
		if (completion) completion(chat, nil);
	}];
}

- (void)setChatAffiliateProgram:(int64_t)chatId
			 commissionPerMille:(int32_t)commissionPerMille
					 monthCount:(int32_t)monthCount
					 completion:(void (^)(BOOL, NSString *))completion {
	if (!chatId){
		if (completion) completion(NO, @"A chat id is needed.");
		return;
	}
	[self request:@{
		@"@type" : @"setChatAffiliateProgram",
		@"chat_id" : @(chatId),
		@"parameters" : TGAFFParameters(@{
			@"commission_per_mille" : @(commissionPerMille),
			@"month_count" : @(monthCount),
		}),
	} completion:^(NSDictionary *result){
		BOOL ok = !TGAFFFailed(result);
		if (completion) completion(ok, ok ? nil : TGAFFErrorText(result));
	}];
}

@end

// vim:ft=objc
