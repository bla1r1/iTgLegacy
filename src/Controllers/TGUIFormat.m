#import "TGUIFormat.h"

static NSString *TGUIDigits(NSString *raw) {
	NSMutableString *digits = [NSMutableString stringWithCapacity:raw.length];
	for (NSUInteger i = 0; i < raw.length; i++) {
		unichar c = [raw characterAtIndex:i];
		if (c >= '0' && c <= '9')
			[digits appendFormat:@"%C", c];
	}
	return digits;
}

NSString *TGUIFormatCallDuration(NSTimeInterval seconds) {
	NSInteger total = (NSInteger)MAX(0.0, seconds);
	NSInteger hours = total / 3600;
	NSInteger minutes = (total % 3600) / 60;
	NSInteger secs = total % 60;
	if (hours > 0)
		return [NSString stringWithFormat:@"%ld:%02ld:%02ld",
				(long)hours, (long)minutes, (long)secs];
	return [NSString stringWithFormat:@"%ld:%02ld", (long)minutes, (long)secs];
}

NSString *TGUIFormatScheduledWhen(NSTimeInterval sendDate, NSTimeInterval now) {
	if (sendDate <= 0)
		return @"";
	NSDate *date = [NSDate dateWithTimeIntervalSince1970:sendDate];
	NSDate *today = [NSDate dateWithTimeIntervalSince1970:now];

	NSDateFormatter *timeFormatter = [[NSDateFormatter alloc] init];
	timeFormatter.dateStyle = NSDateFormatterNoStyle;
	timeFormatter.timeStyle = NSDateFormatterShortStyle;
	NSString *clock = [timeFormatter stringFromDate:date];

	NSCalendar *calendar = [NSCalendar currentCalendar];
	NSDate *day = [calendar dateFromComponents:
			[calendar components:(NSYearCalendarUnit | NSMonthCalendarUnit |
								   NSDayCalendarUnit) fromDate:date]];
	NSDate *base = [calendar dateFromComponents:
			[calendar components:(NSYearCalendarUnit | NSMonthCalendarUnit |
								   NSDayCalendarUnit) fromDate:today]];
	NSDateComponents *oneDay = [[NSDateComponents alloc] init];
	oneDay.day = 1;
	NSDate *tomorrow = [calendar dateByAddingComponents:oneDay toDate:base options:0];

	if ([day isEqualToDate:base])
		return [NSString stringWithFormat:@"Today at %@", clock];
	if ([day isEqualToDate:tomorrow])
		return [NSString stringWithFormat:@"Tomorrow at %@", clock];

	NSDateFormatter *dateFormatter = [[NSDateFormatter alloc] init];
	dateFormatter.dateStyle = NSDateFormatterMediumStyle;
	dateFormatter.timeStyle = NSDateFormatterNoStyle;
	return [NSString stringWithFormat:@"%@ at %@",
			[dateFormatter stringFromDate:date], clock];
}

NSString *TGUIFormatScheduledRelative(NSTimeInterval sendDate, NSTimeInterval now) {
	if (sendDate <= 0)
		return @"";
	NSInteger gap = (NSInteger)(sendDate - now);
	if (gap < 0)
		gap = 0;
	if (gap < 60)
		return @"in less than a minute";
	NSInteger minutes = gap / 60;
	if (minutes < 60)
		return [NSString stringWithFormat:@"in %ld min", (long)minutes];
	NSInteger hours = minutes / 60;
	minutes -= hours * 60;
	if (hours < 24)
		return minutes > 0
				? [NSString stringWithFormat:@"in %ld h %ld min", (long)hours, (long)minutes]
				: [NSString stringWithFormat:@"in %ld h", (long)hours];
	NSInteger days = hours / 24;
	hours -= days * 24;
	return hours > 0
			? [NSString stringWithFormat:@"in %ld d %ld h", (long)days, (long)hours]
			: [NSString stringWithFormat:@"in %ld d", (long)days];
}

NSString *TGUIFormatFullPhone(NSString *prefix, NSString *number) {
	NSString *prefixDigits = TGUIDigits(prefix ?: @"");
	NSString *numberDigits = TGUIDigits(number ?: @"");
	if (prefixDigits.length > 0 &&
			[numberDigits rangeOfString:prefixDigits].location == 0)
		numberDigits = [numberDigits substringFromIndex:prefixDigits.length];
	// A national number is often typed with its trunk zero ("067..." in
	// Ukraine); E.164 drops it. Italy is the country where the zero is part
	// of the number, so it is the one prefix that keeps it.
	if (prefixDigits.length > 0 && [numberDigits hasPrefix:@"0"] &&
			![prefixDigits isEqualToString:@"39"])
		numberDigits = [numberDigits substringFromIndex:1];
	return [NSString stringWithFormat:@"+%@%@", prefixDigits, numberDigits];
}

BOOL TGUIFormatChatMatches(NSString *title, NSString *query) {
	if (!query.length)
		return YES;
	NSString *haystack = [title isKindOfClass:NSString.class] ? title : @"";
	return [haystack rangeOfString:query
						   options:(NSCaseInsensitiveSearch |
									NSDiacriticInsensitiveSearch)].location != NSNotFound;
}
