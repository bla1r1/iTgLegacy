//
// TGClient+TestHarness.h - td_api's test* calls. They exist to exercise the
// schema, not a user action, so their screen is Debug → TDLib Test Harness.
//
// Each method sends the real request and hands back what Telegram answered.
// A build whose server does not expose a test function gets its refusal; the
// harness prints it instead of drawing a made-up result.
//
#import "TGClient+Base.h"

@interface TGClient (TestHarness)

- (void)testCallEmptyWithCompletion:(void (^)(BOOL ok, NSString *error))completion;

- (void)testCallString:(NSString *)text
			completion:(void (^)(NSString *value, NSString *error))completion;

/// `base64` is what TDLib's JSON wants for a byte vector.
- (void)testCallBytes:(NSString *)base64
		   completion:(void (^)(NSString *base64, NSString *error))completion;

- (void)testCallVectorInt:(NSArray *)values
			   completion:(void (^)(NSArray *result, NSString *error))completion;

- (void)testCallVectorString:(NSArray *)values
				  completion:(void (^)(NSArray *result, NSString *error))completion;

- (void)testCallVectorIntObject:(NSArray *)values
					 completion:(void (^)(NSArray *result,
										  NSString *error))completion;

- (void)testCallVectorStringObject:(NSArray *)values
						completion:(void (^)(NSArray *result,
											 NSString *error))completion;

- (void)testSquareInt:(int32_t)value
		   completion:(void (^)(int32_t result, NSString *error))completion;

/// Telegram answers the error object this call names. That is a successful
/// call returning an error, not a refusal by Telegram, so it comes back as
/// code and message with no `error`.
- (void)testReturnErrorCode:(int32_t)code
					message:(NSString *)message
				 completion:(void (^)(int32_t code, NSString *message,
									  NSString *error))completion;

- (void)testGetDifferenceWithCompletion:(void (^)(BOOL ok,
												  NSString *error))completion;

- (void)testNetworkWithCompletion:(void (^)(BOOL ok, NSString *error))completion;

/// The update Telegram returns. The harness names its type; nothing in the
/// app acts on it.
- (void)testUseUpdateWithCompletion:(void (^)(NSDictionary *update,
											 NSString *error))completion;

@end

// vim:ft=objc
