// TGClientTestSupport.m — host-mode stand-ins around the real TGClient.
//
// The regression binary compiles the real src/Core/TGClient.m plus the
// +Chats, +Messages and +Stickers categories. What it deliberately does not
// compile is TGClient+Account.m (contacts, privacy, sessions — nothing the
// dialog-loading tests touch). The few internal methods that category
// provides get minimal, deterministic answers here; tdjson itself is never
// loaded, so requests merely sit in the outbox and can be inspected.
//
// TGClient.m routes call updates to TGCall, which lives in the iOS-only
// TGCall.mm furthest concern; a do-nothing class of the same name stands in.
#import "TGClient.h"
#import "TGClientInternal.h"
#import "TGCall.h"

#pragma mark - TGCall stand-in

@implementation TGCall

+ (instancetype)shared {
	static TGCall *s = nil;
	static dispatch_once_t once;
	dispatch_once(&once, ^{ s = [[TGCall alloc] init]; });
	return s;
}

- (void)handleSignalingData:(NSData *)data {}
- (void)handleUpdate:(NSDictionary *)update {}

@end

#pragma mark - TGClient (TestSupport)

// +Account and +Auth are now compiled into this binary, so the stand-ins the
// dialog tests once needed around them are gone: the real ones had better be
// testable too, and they are - requests land in the outbox, answers come back
// through handleUpdate the same way.

@implementation TGClient (TestSupport)
@end
