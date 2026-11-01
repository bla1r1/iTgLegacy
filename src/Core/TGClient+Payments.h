//
// TGClient+Payments.h - saved order info, a card lookup, a suggested post's
// offer and the validation step a checkout runs before it charges anything.
//
// None of these puts money on a card: the saved order is the address and
// phone Telegram kept from an earlier checkout, the card lookup reads the
// provider's title and links for a number, validateOrderInfo asks Telegram
// what shipping exists for a basket, and addOffer is the price line a channel
// direct-messages post carries. A user account sends all of them; Telegram
// decides which of its endpoints answer, and the screen shows that answer.
//
#import "TGClient+Base.h"

@interface TGClient (Payments)

/// The order Telegram saved from the last checkout. Nil with `error` set
/// when there is nothing saved - TDLib answers 404 for "none" - or when the
/// account may not read it.
- (void)savedOrderInfoWithCompletion:(void (^)(NSDictionary *order,
											   NSString *error))completion;

/// Forgets the saved order. The next checkout asks for the fields again.
- (void)deleteSavedOrderInfoWithCompletion:(void (^)(BOOL ok,
													NSString *error))completion;

/// What the provider knows about a card number: its title, and the links its
/// own page opens (3-D Secure, support, the issuer). The number is not kept.
- (void)bankCardInfoForNumber:(NSString *)number
				   completion:(void (^)(NSDictionary *info,
										NSString *error))completion;

/// Puts a price on a suggested post. `starCount` is the whole price in
/// Telegram Stars; `sendDate` is when it should be published, 0 for now.
/// TDLib only accepts it on a message whose properties say an offer can be
/// added, so a user account usually sees the server's refusal instead.
- (void)addOfferToMessage:(int64_t)messageId
				   inChat:(int64_t)chatId
				starCount:(int64_t)starCount
				sendDate:(int32_t)sendDate
			   completion:(void (^)(NSDictionary *message,
									NSString *error))completion;

/// Checks an order against a named invoice and returns the order-info id the
/// payment form needs, plus every shipping option Telegram offers. `order`
/// carries the checkout fields; missing ones are sent as empty strings
/// because orderInfo has no optional members.
- (void)validateOrderInfoForInvoice:(NSString *)invoiceName
							  order:(NSDictionary *)order
						  allowSave:(BOOL)allowSave
						 completion:(void (^)(NSDictionary *validated,
											  NSString *error))completion;

@end
