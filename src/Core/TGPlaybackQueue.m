#import "TGPlaybackQueue.h"

NSInteger TGNextPlayableRow(NSArray *messages, int64_t currentId) {
	BOOL passed = NO;
	for (NSUInteger row = 0; row < messages.count; row++){
		NSDictionary *message = messages[row];
		if (!passed){
			passed = [message[@"id"] longLongValue] == currentId;
			continue;
		}
		NSString *kind = message[@"kind"];
		BOOL playable = [message[@"type"] isEqualToString:@"voice"] ||
				[kind isEqualToString:@"messageVoiceNote"] ||
				[kind isEqualToString:@"messageVideoNote"];
		if (playable && ![message[@"sending"] boolValue] &&
				[message[@"docId"] isKindOfClass:NSNumber.class])
			return (NSInteger)row;
	}
	return NSNotFound;
}

BOOL TGShowsUnplayedMark(NSDictionary *message, BOOL inSavedMessages) {
	if (![message[@"unplayed"] boolValue])
		return NO;
	if (![message[@"outgoing"] boolValue])
		return YES;
	return !inSavedMessages && ![message[@"channelPost"] boolValue];
}

NSNumber *TGTrackToPrefetch(NSArray *tracks, NSInteger index, BOOL shuffle, BOOL repeatAll) {
	if (shuffle || tracks.count < 2)
		return nil;
	NSInteger next = index + 1;
	if (next >= (NSInteger)tracks.count){
		if (!repeatAll)
			return nil;
		next = 0;
	}
	NSDictionary *track = tracks[(NSUInteger)next];
	NSNumber *fileId = track[@"docId"];
	if (![fileId isKindOfClass:NSNumber.class] ||
			[track[@"docSize"] longLongValue] > 32LL * 1024 * 1024)
		return nil;
	return fileId;
}
