//
// TGClient+Dice.m - the stake state and the five ephemeral requests.
//
#import "TGClient+Dice.h"
#import "TGClientInternal.h"

static NSString *TGDiceError(NSDictionary *result) {
	if (![result[@"@type"] isEqualToString:@"error"])
		return nil;
	NSString *message = result[@"message"];
	return message.length ? message : @"Telegram refused that.";
}

/// The order of prize_per_mille is faces 1..6, so the array is kept whole and
/// a row indexes it by the face it names.
static NSDictionary *TGStakeDiceRow(NSDictionary *state) {
	if (![state isKindOfClass:NSDictionary.class])
		return nil;
	return @{
		@"stateHash"             : state[@"state_hash"] ?: @"",
		@"stakeGramAmount"       : state[@"stake_gram_amount"] ?: @(0),
		@"suggestedStakeGramAmounts" : state[@"suggested_stake_gram_amounts"] ?: @[],
		@"currentStreak"         : state[@"current_streak"] ?: @(0),
		@"prizePerMille"         : state[@"prize_per_mille"] ?: @[],
		@"streakPrizePerMille"   : state[@"streak_prize_per_mille"] ?: @(0),
	};
}

/// inputMessageText is what both the send and the edit carry. A null
/// link-preview object asks Telegram to decide, which is what a bot message
/// needs; clear_draft stays false because an ephemeral send is not a draft.
static NSDictionary *TGEphemeralTextContent(NSString *text) {
	return @{
		@"@type" : @"inputMessageText",
		@"text" : TGFormattedText(text ?: @""),
		@"link_preview_options" : [NSNull null],
		@"clear_draft" : @NO,
	};
}

@implementation TGClient (Dice)

/// The state hash expires, so the panel reads this one rather than keeping
/// the hash it opened with.
- (void)applyStakeDiceStateUpdate:(NSDictionary *)update {
	NSDictionary *row = TGStakeDiceRow(update[@"state"]);
	if (!row)
		return;
	self.stakeDiceStateValue = row;
	[[NSNotificationCenter defaultCenter]
			postNotificationName:TGStakeDiceStateChangedNotification object:self];
}

- (void)stakeDiceStateWithCompletion:(void (^)(NSDictionary *, NSString *))completion {
	[self request:@{@"@type" : @"getStakeDiceState"}
	   completion:^(NSDictionary *result){
		NSString *error = TGDiceError(result);
		NSDictionary *row = error ? nil : TGStakeDiceRow(result);
		if (row)
			self.stakeDiceStateValue = row;
		if (completion)
			completion(row, error);
	}];
}

- (void)sendEphemeralText:(NSString *)text
                   toChat:(int64_t)chatId
           receiverUserId:(int64_t)receiverUserId
          ephemeralReplyId:(NSInteger)ephemeralReplyId
               completion:(void (^)(NSDictionary *, NSString *))completion {
	id replyTo = ephemeralReplyId > 0
			? @{@"@type" : @"inputMessageReplyToEphemeralMessage",
				@"ephemeral_message_id" : @(ephemeralReplyId)}
			: (id)[NSNull null];
	[self request:@{
		@"@type" : @"sendEphemeralMessage",
		@"chat_id" : @(chatId),
		@"topic_id" : [NSNull null],
		@"receiver_user_id" : @(receiverUserId),
		@"callback_query_id" : @(0),
		@"replace_callback_query_message" : @NO,
		@"reply_to" : replyTo,
		@"protect_content" : @NO,
		@"sending_id" : @(0),
		@"only_preview" : @NO,
		@"reply_markup" : [NSNull null],
		@"input_message_content" : TGEphemeralTextContent(text),
	} completion:^(NSDictionary *result){
		NSString *error = TGDiceError(result);
		NSDictionary *message = nil;
		if (!error && [result[@"@type"] isEqualToString:@"message"])
			message = TGFlattenMessage(result);
		if (completion)
			completion(message, error);
	}];
}

- (void)editEphemeralMessage:(NSInteger)ephemeralMessageId
                        text:(NSString *)text
                    receiver:(int64_t)receiverUserId
                      inChat:(int64_t)chatId
                  completion:(void (^)(BOOL, NSString *))completion {
	[self request:@{
		@"@type" : @"editEphemeralMessage",
		@"chat_id" : @(chatId),
		@"receiver_user_id" : @(receiverUserId),
		@"ephemeral_message_id" : @(ephemeralMessageId),
		@"reply_markup" : [NSNull null],
		@"input_message_content" : TGEphemeralTextContent(text),
	} completion:^(NSDictionary *result){
		NSString *error = TGDiceError(result);
		if (completion)
			completion(error == nil, error);
	}];
}

- (void)editEphemeralMessageCaption:(NSInteger)ephemeralMessageId
                            caption:(NSString *)caption
                           receiver:(int64_t)receiverUserId
                             inChat:(int64_t)chatId
                         completion:(void (^)(BOOL, NSString *))completion {
	[self request:@{
		@"@type" : @"editEphemeralMessageCaption",
		@"chat_id" : @(chatId),
		@"receiver_user_id" : @(receiverUserId),
		@"ephemeral_message_id" : @(ephemeralMessageId),
		@"reply_markup" : [NSNull null],
		@"caption" : TGFormattedText(caption ?: @""),
		@"show_caption_above_media" : @NO,
	} completion:^(NSDictionary *result){
		NSString *error = TGDiceError(result);
		if (completion)
			completion(error == nil, error);
	}];
}

- (void)deleteEphemeralMessage:(NSInteger)ephemeralMessageId
                      receiver:(int64_t)receiverUserId
                        inChat:(int64_t)chatId
                    completion:(void (^)(BOOL, NSString *))completion {
	[self request:@{
		@"@type" : @"deleteEphemeralMessage",
		@"chat_id" : @(chatId),
		@"receiver_user_id" : @(receiverUserId),
		@"ephemeral_message_id" : @(ephemeralMessageId),
	} completion:^(NSDictionary *result){
		NSString *error = TGDiceError(result);
		if (completion)
			completion(error == nil, error);
	}];
}

- (void)deleteMessageEphemeralContent:(int64_t)messageId
                              inChat:(int64_t)chatId
                          completion:(void (^)(BOOL, NSString *))completion {
	[self request:@{
		@"@type" : @"deleteMessageEphemeralContent",
		@"chat_id" : @(chatId),
		@"message_id" : @(messageId),
	} completion:^(NSDictionary *result){
		NSString *error = TGDiceError(result);
		if (completion)
			completion(error == nil, error);
	}];
}

@end
