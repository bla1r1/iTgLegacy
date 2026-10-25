#import "TGStatusText.h"
#import "TGClient.h"

// Which local calendar day an instant belongs to, as a running day count.
// The offset shifts the Unix midnights onto local ones, and plain floor
// division counts the days; the +12h anchor people reach for first actually
// moves the boundary to local NOON, so a chat unchanged since morning read
// as "yesterday" the moment the clock passed 12:00.
static NSInteger TGDayIndex(NSDate *date){
	NSTimeInterval local = date.timeIntervalSince1970
			+ [NSTimeZone.systemTimeZone secondsFromGMTForDate:date];
	return (NSInteger)floor(local / 86400.0);
}

static NSString *TGHourString(NSTimeInterval unix){
	static NSDateFormatter *fmt = nil;
	if (!fmt){
		fmt = [[NSDateFormatter alloc] init];
		[fmt setDateFormat:@"HH:mm"];
	}
	return [fmt stringFromDate:[NSDate dateWithTimeIntervalSince1970:unix]];
}

/// Every distance the offline branch can name, in the phrasing the official
/// clients use. B4: the old formatter knew only "today", so anyone seen
/// yesterday or earlier read as "last seen a long time ago", and a
/// was_online of 0 fell into the far past as "1970".
static NSString *TGOfflinePhrase(NSTimeInterval was){
	NSString *at = TGHourString(was);
	NSInteger dayGap = TGDayIndex([NSDate date])
			- TGDayIndex([NSDate dateWithTimeIntervalSince1970:was]);
	NSTimeInterval ago = [NSDate date].timeIntervalSince1970 - was;

	if (dayGap <= 0)    return [NSString stringWithFormat:@"last seen at %@", at];
	if (dayGap == 1)    return [NSString stringWithFormat:@"last seen yesterday at %@", at];
	if (ago <= 7 * 86400)   return @"last seen within a week";
	if (ago <= 30 * 86400)  return @"last seen within a month";
	return @"last seen a long time ago";
}

NSString *TGStatusTextFromTDStatus(NSDictionary *status){
	NSString *kind = status[@"@type"];
	NSString *text = nil;

	if ([kind isEqualToString:@"userStatusOnline"]){
		text = @"online";
	} else if ([kind isEqualToString:@"userStatusRecently"]){
		text = @"last seen recently";
	} else if ([kind isEqualToString:@"userStatusLastWeek"]){
		text = @"last seen within a week";
	} else if ([kind isEqualToString:@"userStatusLastMonth"]){
		text = @"last seen within a month";
	} else if ([kind isEqualToString:@"userStatusOffline"]){
		NSTimeInterval was = [status[@"was_online"] doubleValue];
		// Someone with no last seen at all, or a clock gone sideways, reads
		// exactly like the phrase every other client shows.
		if (was <= 0)
			return @"last seen a long time ago";
		text = TGOfflinePhrase(was);
	} else {
		// userStatusEmpty is what TDLib sends for someone who has turned
		// their last-seen off, and for a user it will not talk about. Every
		// client shows the same phrase rather than an empty subtitle.
		text = @"last seen recently";
	}
	return text;
}

NSString *TGNetworkSubtitleForState(NSInteger state, NSString *text){
	// These mirror the phrases TGClient.m maps out of updateConnectionState;
	// the mapping lives here so every subtitle owner shows the same words.
	NSString *pg = nil;
	if (state == (NSInteger)TGConnectionStateWaitingForNetwork){
		pg = @"Waiting for network";
	} else if (state == (NSInteger)TGConnectionStateConnecting){
		pg = @"Connecting...";
	} else if (state == (NSInteger)TGConnectionStateUpdating){
		pg = @"Updating...";
	} else if (state == (NSInteger)TGConnectionStateReady){
		pg = nil;
	} else {
		pg = text.length ? text : nil;
	}
	return pg;
}
