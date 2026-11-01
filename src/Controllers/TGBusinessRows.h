//
// TGBusinessRows.h - the small row model every Business screen draws.
//
// These pages are settings lists, not chat surfaces: a row is a name, a value
// on the right, and one verb. Keeping the model here means the main Business
// page, the automated-message pages and the bot connection page all draw the
// same cell instead of three near-copies.
//
#ifndef TGBUSINESSROWS_H
#define TGBUSINESSROWS_H

#import <UIKit/UIKit.h>

typedef NS_ENUM(NSInteger, TGBusinessRowKind) {
	TGBusinessRowInfo = 0,
	TGBusinessRowAction,
	TGBusinessRowSwitch,
	TGBusinessRowDestructive,
};

static inline NSDictionary *TGBRow(NSString *title, NSString *detail,
								   NSString *action, TGBusinessRowKind kind) {
	NSMutableDictionary *row = [@{@"title" : title ?: @"",
								  @"kind" : @(kind)} mutableCopy];
	if (detail)
		row[@"detail"] = detail;
	if (action)
		row[@"action"] = action;
	return row;
}

static inline NSDictionary *TGBInfo(NSString *title, NSString *detail) {
	return TGBRow(title, detail, nil, TGBusinessRowInfo);
}

static inline NSDictionary *TGBAction(NSString *title, NSString *detail,
									  NSString *action) {
	return TGBRow(title, detail, action, TGBusinessRowAction);
}

static inline NSDictionary *TGBDestructive(NSString *title, NSString *action) {
	return TGBRow(title, nil, action, TGBusinessRowDestructive);
}

static inline NSDictionary *TGBSwitch(NSString *title, NSString *detail,
									  NSString *key, BOOL on, BOOL enabled) {
	NSMutableDictionary *row = [TGBRow(title, detail, nil, TGBusinessRowSwitch)
			mutableCopy];
	row[@"switch"] = key;
	row[@"on"] = @(on);
	row[@"enabled"] = @(enabled);
	return row;
}

static inline NSDictionary *TGBSection(NSString *header, NSString *footer,
									   NSArray *rows) {
	NSMutableDictionary *section = [NSMutableDictionary dictionary];
	if (header) section[@"header"] = header;
	if (footer) section[@"footer"] = footer;
	section[@"rows"] = rows ?: @[];
	return section;
}

/// "9:00" from a minute of the day.
static inline NSString *TGBClockTime(NSInteger minuteOfDay) {
	NSInteger minute = ((minuteOfDay % 1440) + 1440) % 1440;
	return [NSString stringWithFormat:@"%02ld:%02ld",
			(long)(minute / 60), (long)(minute % 60)];
}

/// "Mon" for 0, as a week of business hours is counted from Monday.
static inline NSString *TGBDayName(NSInteger day) {
	static NSArray *names = nil;
	if (!names)
		names = @[@"Monday", @"Tuesday", @"Wednesday", @"Thursday",
				  @"Friday", @"Saturday", @"Sunday"];
	return day >= 0 && day < 7 ? names[(NSUInteger)day] : @"";
}

#endif // TGBUSINESSROWS_H

// vim:ft=objc
