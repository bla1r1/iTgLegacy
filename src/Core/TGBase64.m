//
// TGBase64.m - the two spellings of base64 across the OS line (see header).
//
#import "TGBase64.h"

NSData *TGBase64Decode(NSString *b64) {
	if (![b64 isKindOfClass:NSString.class] || !b64.length)
		return [NSData data];
	if ([NSData instancesRespondToSelector:@selector(initWithBase64EncodedString:options:)])
		return [[NSData alloc] initWithBase64EncodedString:b64 options:0];
	// iOS 6:NSConcreteData answers only the legacy selector.
	return [[NSData alloc] initWithBase64Encoding:b64];
}

NSString *TGBase64Encode(NSData *data) {
	if (!data)
		return @"";
	if ([NSString instancesRespondToSelector:@selector(base64EncodedStringWithOptions:)])
		return [data base64EncodedStringWithOptions:0];
	return [data base64Encoding];
}
