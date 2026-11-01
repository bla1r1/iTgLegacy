//
// TGClient+Payments.m - the four payment reads and the offer write.
//
// Every method here names the server's sentence on failure. A saved order
// that is not there is a 404 like any other, a card number the provider does
// not know is an error, and addOffer on a message that is not a suggested
// post is refused - none of those is a boolean that only says "no".
//
#import "TGClient+Payments.h"
#import "TGClientInternal.h"

static NSString *TGPaymentError(NSDictionary *result) {
	NSString *message = result[@"message"];
	return [message isKindOfClass:NSString.class] ? message : @"Telegram refused that.";
}

static NSString *TGPaymentString(NSDictionary *dictionary, NSString *key) {
	id value = dictionary[key];
	return [value isKindOfClass:NSString.class] ? value : @"";
}

@implementation TGClient (Payments)

- (void)savedOrderInfoWithCompletion:(void (^)(NSDictionary *, NSString *))completion {
	[self request:@{@"@type" : @"getSavedOrderInfo"}
	   completion:^(NSDictionary *result){
		if ([result[@"@type"] isEqualToString:@"error"]){
			if (completion) completion(nil, TGPaymentError(result));
			return;
		}
		if (completion) completion(result, nil);
	}];
}

- (void)deleteSavedOrderInfoWithCompletion:(void (^)(BOOL, NSString *))completion {
	[self request:@{@"@type" : @"deleteSavedOrderInfo"}
	   completion:^(NSDictionary *result){
		BOOL failed = [result[@"@type"] isEqualToString:@"error"];
		if (completion)
			completion(!failed, failed ? TGPaymentError(result) : nil);
	}];
}

- (void)bankCardInfoForNumber:(NSString *)number
				   completion:(void (^)(NSDictionary *, NSString *))completion {
	// The provider reads digits; a card is typed in groups and the lookup
	// counts the spaces as a different number.
	NSMutableString *digits = [NSMutableString string];
	for (NSUInteger i = 0; i < number.length; i++){
		unichar c = [number characterAtIndex:i];
		if (c >= '0' && c <= '9')
			[digits appendFormat:@"%C", c];
	}
	if (digits.length < 6){
		if (completion) completion(nil, @"A card number needs at least six digits.");
		return;
	}
	[self request:@{@"@type" : @"getBankCardInfo", @"bank_card_number" : digits}
	   completion:^(NSDictionary *result){
		if ([result[@"@type"] isEqualToString:@"error"]){
			if (completion) completion(nil, TGPaymentError(result));
			return;
		}
		if (completion) completion(result, nil);
	}];
}

- (void)addOfferToMessage:(int64_t)messageId
				   inChat:(int64_t)chatId
				starCount:(int64_t)starCount
				 sendDate:(int32_t)sendDate
			   completion:(void (^)(NSDictionary *, NSString *))completion {
	if (!chatId || !messageId){
		if (completion) completion(nil, @"Name the chat and the message the offer is for.");
		return;
	}
	if (starCount <= 0){
		if (completion) completion(nil, @"An offer needs a price above zero stars.");
		return;
	}
	// messageSendOptions has no optional members, so every field is written;
	// scheduling_state is null because the suggested post's own send_date is
	// the only time this request sets.
	NSDictionary *options = @{
		@"@type"            : @"messageSendOptions",
		@"suggested_post_info" : @{
			@"@type"     : @"inputSuggestedPostInfo",
			@"price"     : @{@"@type" : @"suggestedPostPriceStar",
							 @"star_count" : @(starCount)},
			@"send_date" : @(sendDate),
		},
		@"disable_notification" : @NO,
		@"from_background"      : @NO,
		@"protect_content"      : @NO,
		@"allow_paid_broadcast" : @NO,
		@"paid_message_star_count" : @0,
		@"update_order_of_installed_sticker_sets" : @NO,
		@"scheduling_state"     : [NSNull null],
		@"effect_id"            : @0,
		@"sending_id"           : @0,
		@"only_preview"         : @NO,
	};

	[self request:@{@"@type" : @"addOffer",
					@"chat_id" : @(chatId),
					@"message_id" : @(messageId),
					@"options" : options}
	   completion:^(NSDictionary *result){
		if ([result[@"@type"] isEqualToString:@"error"]){
			if (completion) completion(nil, TGPaymentError(result));
			return;
		}
		if (completion) completion(result, nil);
	}];
}

- (void)validateOrderInfoForInvoice:(NSString *)invoiceName
							  order:(NSDictionary *)order
						  allowSave:(BOOL)allowSave
						 completion:(void (^)(NSDictionary *, NSString *))completion {
	invoiceName = [invoiceName stringByTrimmingCharactersInSet:
			[NSCharacterSet whitespaceAndNewlineCharacterSet]];
	if (!invoiceName.length){
		if (completion) completion(nil, @"An invoice name is what the order is checked against.");
		return;
	}
	// orderInfo has no optional members: an address the form did not ask for
	// is an empty string, not a missing key Telegram rejects.
	NSDictionary *address = @{
		@"@type"        : @"address",
		@"country_code" : TGPaymentString(order, @"country_code"),
		@"state"        : TGPaymentString(order, @"state"),
		@"city"         : TGPaymentString(order, @"city"),
		@"street_line1" : TGPaymentString(order, @"street_line1"),
		@"street_line2" : TGPaymentString(order, @"street_line2"),
		@"postal_code"  : TGPaymentString(order, @"postal_code"),
	};
	NSDictionary *info = @{
		@"@type"              : @"orderInfo",
		@"name"               : TGPaymentString(order, @"name"),
		@"phone_number"       : TGPaymentString(order, @"phone_number"),
		@"email_address"      : TGPaymentString(order, @"email_address"),
		@"shipping_address"   : address,
	};
	[self request:@{@"@type" : @"validateOrderInfo",
					@"input_invoice" : @{@"@type" : @"inputInvoiceName",
										 @"name" : invoiceName},
					@"order_info" : info,
					@"allow_save" : @(allowSave)}
	   completion:^(NSDictionary *result){
		if ([result[@"@type"] isEqualToString:@"error"]){
			if (completion) completion(nil, TGPaymentError(result));
			return;
		}
		if (completion) completion(result, nil);
	}];
}

@end

// vim:ft=objc
