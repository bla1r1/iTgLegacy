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

@implementation TGClient (TestSupport)

/// Saved Messages is keyed off the signed-in user; `me` is what a real
/// session would carry. Tests set `me` when they care, default 0.
- (int64_t)savedMessagesChatId {
	return [self.me[@"id"] longLongValue];
}

- (NSString *)nameForUserId:(int64_t)userId {
	NSString *name = self.usersById[@(userId)];
	return name.length ? name : nil;
}

/// The real one asks TDLib for the user and rebuilds when the name lands.
/// On the host the name simply never becomes known — which is the branch
/// the chat-list render tests for anyway.
- (void)ensureUserName:(int64_t)userId completion:(void (^)(void))completion {
	if (completion)
		completion();
}

/// updateUser photo wiring is +Account territory; nothing tests it here.
- (void)cacheProfilePhoto:(NSDictionary *)user {}

/// +Account territory as well.
- (void)flushPendingPhoneNumber {}

@end
