// TGClientStub.m — test-only TGClient.
//
// TGCall.mm sends signalling through TGClient. The real class is a TDLib
// client that only builds for iOS; the call tests feed signalling in directly,
// so all they need is a sink that records what TGCall tried to send.
//
// The class name intentionally matches the production one: the test binary
// compiles this instead of src/TGClient.m.
#import "TGClient.h"

static NSMutableArray<NSDictionary *> *TGSentRequests(void) {
	static NSMutableArray *requests = nil;
	static dispatch_once_t once;
	dispatch_once(&once, ^{ requests = [NSMutableArray array]; });
	return requests;
}

@implementation TGClient

+ (instancetype)shared {
	static TGClient *client = nil;
	static dispatch_once_t once;
	dispatch_once(&once, ^{ client = [[TGClient alloc] init]; });
	return client;
}

- (void)send:(NSDictionary *)request {
	if (request)
		[TGSentRequests() addObject:request];
}

@end

@implementation TGClient (Testing)

+ (NSArray<NSDictionary *> *)sentRequests {
	return [TGSentRequests() copy];
}

+ (void)resetSentRequests {
	[TGSentRequests() removeAllObjects];
}

@end
