//
// TGClient+Affiliate.h - Telegram's affiliate programs: the catalogue, the
// programs this account or bot has connected, and the program a channel
// shows under its posts.
//
// Every call names the affiliate it is about. `kind` is "user" (this
// account), "bot" (a bot user id) or "channel" (a chat id); the screen that
// asks for it says which id belongs in the field.
//
#import "TGClient+Base.h"

@interface TGClient (Affiliate)

/// `sort` is "profitability", "creationDate" or "revenue"; anything else
/// falls back to Telegram's default.
- (void)searchAffiliateProgramsForKind:(NSString *)kind
							 botUserId:(int64_t)botUserId
								chatId:(int64_t)chatId
							  sortOrder:(NSString *)sort
								 offset:(NSString *)offset
								  limit:(int32_t)limit
							 completion:(void (^)(NSDictionary *page,
												  NSString *error))completion;

- (void)connectedAffiliateProgramsForKind:(NSString *)kind
								botUserId:(int64_t)botUserId
								   chatId:(int64_t)chatId
								   offset:(NSString *)offset
									limit:(int32_t)limit
							   completion:(void (^)(NSDictionary *page,
													NSString *error))completion;

/// One connection. `programBotUserId` is the bot that owns the program, not
/// the affiliate the connection belongs to.
- (void)connectedAffiliateProgramForKind:(NSString *)kind
							   botUserId:(int64_t)botUserId
								  chatId:(int64_t)chatId
						  programBotUserId:(int64_t)programBotUserId
							  completion:(void (^)(NSDictionary *program,
												   NSString *error))completion;

- (void)connectAffiliateProgramForKind:(NSString *)kind
							 botUserId:(int64_t)botUserId
								chatId:(int64_t)chatId
						programBotUserId:(int64_t)programBotUserId
							completion:(void (^)(NSDictionary *program,
												 NSString *error))completion;

- (void)disconnectAffiliateProgramForKind:(NSString *)kind
								botUserId:(int64_t)botUserId
								   chatId:(int64_t)chatId
									  url:(NSString *)url
							   completion:(void (^)(NSDictionary *program,
													NSString *error))completion;

/// The chat behind a t.me affiliate link, or Telegram's refusal.
- (void)searchChatAffiliateProgram:(NSString *)username
						  referrer:(NSString *)referrer
						completion:(void (^)(NSDictionary *chat,
											 NSString *error))completion;

/// Sets the commission and duration a channel shows to affiliates.
- (void)setChatAffiliateProgram:(int64_t)chatId
			 commissionPerMille:(int32_t)commissionPerMille
					 monthCount:(int32_t)monthCount
					 completion:(void (^)(BOOL ok, NSString *error))completion;

@end

// vim:ft=objc
