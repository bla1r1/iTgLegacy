#import "TGGhostMode.h"

static BOOL sGhostRead;
static BOOL sGhostOn;

BOOL TGGhostModeOn(void) {
#if !TG_DEV
	// A test tool for a real account, never something a release can be left in.
	return NO;
#endif
	if (!sGhostRead){
		sGhostOn = [[NSUserDefaults standardUserDefaults] boolForKey:@"TGGhostMode"];
		sGhostRead = YES;
	}
	return sGhostOn;
}

void TGGhostModeSetOn(BOOL on) {
	sGhostOn = on;
	sGhostRead = YES;
}

BOOL TGGhostModeBlocks(NSDictionary *request) {
	NSString *type = request[@"@type"];
	if ([type isEqualToString:@"setOption"]){
		// Going offline is fine; going online is the thing being avoided.
		return [request[@"name"] isEqualToString:@"online"] &&
				[request[@"value"][@"value"] boolValue];
	}
	static NSSet *telling;
	static dispatch_once_t once;
	dispatch_once(&once, ^{
		telling = [NSSet setWithArray:@[
			@"viewMessages", @"openMessageContent", @"readChatList",
			@"readAllChatMentions", @"readAllChatReactions", @"readAllChatPollVotes",
			@"readAllMessageThreadMentions", @"readAllMessageThreadReactions",
			@"sendChatAction", @"openStory", @"readBusinessMessage",
		]];
	});
	return type && [telling containsObject:type];
}
