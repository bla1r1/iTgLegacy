//
// TGClient+TestHarness.m - testCall* and the three plumbing test functions.
//
// The flattening below is deliberately thin: these calls exist so a person
// can see what TDLib does with a value, and hiding the shape behind an
// opinionated row model would defeat that.
//
#import "TGClient+TestHarness.h"
#import "TGClientInternal.h"

static NSArray *TGTHArray(id value) {
	return [value isKindOfClass:NSArray.class] ? value : @[];
}

static NSString *TGTHString(id value) {
	return [value isKindOfClass:NSString.class] ? value : @"";
}

static NSNumber *TGTHNumber(id value) {
	return [value isKindOfClass:NSNumber.class] ? value : @0;
}

static NSString *TGTHErrorText(NSDictionary *result) {
	NSString *message = result[@"message"];
	return [message isKindOfClass:NSString.class] && message.length
			? message : @"Telegram refused that.";
}

static BOOL TGTHFailed(NSDictionary *result) {
	return [result[@"@type"] isEqualToString:@"error"];
}

/// testInt/testString vectors answer with objects, but the shape is only
/// interesting as the values they carry.
static NSArray *TGTHObjectValues(id value) {
	NSMutableArray *out = [NSMutableArray array];
	for (NSDictionary *object in TGTHArray(value)){
		if (![object isKindOfClass:NSDictionary.class])
			continue;
		[out addObject:object[@"value"] ?: @""];
	}
	return out;
}

@implementation TGClient (TestHarness)

- (void)testCallEmptyWithCompletion:(void (^)(BOOL, NSString *))completion {
	[self request:@{@"@type" : @"testCallEmpty"}
	   completion:^(NSDictionary *result){
		BOOL ok = !TGTHFailed(result);
		if (completion) completion(ok, ok ? nil : TGTHErrorText(result));
	}];
}

- (void)testCallString:(NSString *)text
			completion:(void (^)(NSString *, NSString *))completion {
	[self request:@{@"@type" : @"testCallString", @"x" : TGTHString(text)}
	   completion:^(NSDictionary *result){
		if (TGTHFailed(result)){
			if (completion) completion(nil, TGTHErrorText(result));
			return;
		}
		if (completion) completion(TGTHString(result[@"value"]), nil);
	}];
}

- (void)testCallBytes:(NSString *)base64
		   completion:(void (^)(NSString *, NSString *))completion {
	[self request:@{@"@type" : @"testCallBytes", @"x" : TGTHString(base64)}
	   completion:^(NSDictionary *result){
		if (TGTHFailed(result)){
			if (completion) completion(nil, TGTHErrorText(result));
			return;
		}
		if (completion) completion(TGTHString(result[@"value"]), nil);
	}];
}

- (void)testCallVectorInt:(NSArray *)values
			   completion:(void (^)(NSArray *, NSString *))completion {
	NSMutableArray *numbers = [NSMutableArray array];
	for (id value in values)
		[numbers addObject:@([value intValue])];
	[self request:@{@"@type" : @"testCallVectorInt", @"x" : numbers}
	   completion:^(NSDictionary *result){
		if (TGTHFailed(result)){
			if (completion) completion(nil, TGTHErrorText(result));
			return;
		}
		if (completion) completion(TGTHArray(result[@"value"]), nil);
	}];
}

- (void)testCallVectorString:(NSArray *)values
				  completion:(void (^)(NSArray *, NSString *))completion {
	NSMutableArray *strings = [NSMutableArray array];
	for (id value in values)
		[strings addObject:TGTHString(value)];
	[self request:@{@"@type" : @"testCallVectorString", @"x" : strings}
	   completion:^(NSDictionary *result){
		if (TGTHFailed(result)){
			if (completion) completion(nil, TGTHErrorText(result));
			return;
		}
		if (completion) completion(TGTHArray(result[@"value"]), nil);
	}];
}

- (void)testCallVectorIntObject:(NSArray *)values
					 completion:(void (^)(NSArray *, NSString *))completion {
	NSMutableArray *objects = [NSMutableArray array];
	for (id value in values)
		[objects addObject:@{@"@type" : @"testInt",
							 @"value" : @([value intValue])}];
	[self request:@{@"@type" : @"testCallVectorIntObject", @"x" : objects}
	   completion:^(NSDictionary *result){
		if (TGTHFailed(result)){
			if (completion) completion(nil, TGTHErrorText(result));
			return;
		}
		if (completion) completion(TGTHObjectValues(result[@"value"]), nil);
	}];
}

- (void)testCallVectorStringObject:(NSArray *)values
						completion:(void (^)(NSArray *, NSString *))completion {
	NSMutableArray *objects = [NSMutableArray array];
	for (id value in values)
		[objects addObject:@{@"@type" : @"testString",
							 @"value" : TGTHString(value)}];
	[self request:@{@"@type" : @"testCallVectorStringObject", @"x" : objects}
	   completion:^(NSDictionary *result){
		if (TGTHFailed(result)){
			if (completion) completion(nil, TGTHErrorText(result));
			return;
		}
		if (completion) completion(TGTHObjectValues(result[@"value"]), nil);
	}];
}

- (void)testSquareInt:(int32_t)value
		   completion:(void (^)(int32_t, NSString *))completion {
	[self request:@{@"@type" : @"testSquareInt", @"x" : @(value)}
	   completion:^(NSDictionary *result){
		if (TGTHFailed(result)){
			if (completion) completion(0, TGTHErrorText(result));
			return;
		}
		if (completion) completion([TGTHNumber(result[@"value"]) intValue], nil);
	}];
}

- (void)testReturnErrorCode:(int32_t)code
					message:(NSString *)message
				 completion:(void (^)(int32_t, NSString *, NSString *))completion {
	[self request:@{
		@"@type" : @"testReturnError",
		@"error" : @{
			@"@type" : @"error",
			@"code" : @(code),
			@"message" : TGTHString(message),
		},
	} completion:^(NSDictionary *result){
		// The answer *is* the error object the call was asked to return.
		if ([result[@"@type"] isEqualToString:@"error"]){
			if (completion)
				completion([TGTHNumber(result[@"code"]) intValue],
						   TGTHString(result[@"message"]), nil);
			return;
		}
		if (completion) completion(0, @"", @"Telegram did not return the error object.");
	}];
}

- (void)testGetDifferenceWithCompletion:(void (^)(BOOL, NSString *))completion {
	[self request:@{@"@type" : @"testGetDifference"}
	   completion:^(NSDictionary *result){
		BOOL ok = !TGTHFailed(result);
		if (completion) completion(ok, ok ? nil : TGTHErrorText(result));
	}];
}

- (void)testNetworkWithCompletion:(void (^)(BOOL, NSString *))completion {
	[self request:@{@"@type" : @"testNetwork"}
	   completion:^(NSDictionary *result){
		BOOL ok = !TGTHFailed(result);
		if (completion) completion(ok, ok ? nil : TGTHErrorText(result));
	}];
}

- (void)testUseUpdateWithCompletion:(void (^)(NSDictionary *, NSString *))completion {
	[self request:@{@"@type" : @"testUseUpdate"}
	   completion:^(NSDictionary *result){
		if (TGTHFailed(result)){
			if (completion) completion(nil, TGTHErrorText(result));
			return;
		}
		if (completion) completion(result, nil);
	}];
}

@end

// vim:ft=objc
