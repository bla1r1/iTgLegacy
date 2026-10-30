//
// TGFastDate.h - timestamp formatting without NSDateFormatter.
//
// The chat list wrote a date per row per layout pass, and NSDateFormatter is
// an ICU pattern compile, a locale lookup and an NSString behind every one of
// them. On a 4S that was the single most expensive thing in a scroll. This is
// localtime_r, two integer comparisons and snprintf into the caller's buffer:
// no heap, no objects, same three shapes.
//
// Plain C on purpose - the controllers that use it stay Objective-C.
//
#ifndef TGFASTDATE_H
#define TGFASTDATE_H

#include <time.h>
#include <stdio.h>
#include <string.h>

#define TGFastDateBufferSize 16

/// "14:05" within the day, "Thu" within the week, "28.10.25" beyond it -
/// the three shapes the chat list has always shown, written into `out`.
/// `now` is the clock to measure age against. Returns the string length.
static inline size_t TGFastChatDate(time_t unix, time_t now, char *out, size_t cap) {
	static const char *const kWeekdays[7] = {
		"Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat"
	};
	if (!out || cap == 0)
		return 0;
	out[0] = '\0';
	if (unix <= 0)
		return 0;

	struct tm parts;
	if (!localtime_r(&unix, &parts))
		return 0;

	// Precomputed boundaries, so the hot path never divides or multiplies.
	const time_t day  = now - 24 * 3600;
	const time_t week = now - 7 * 24 * 3600;

	int written;
	if (unix >= day) {
		written = snprintf(out, cap, "%02d:%02d", parts.tm_hour, parts.tm_min);
	} else if (unix >= week) {
		int index = parts.tm_wday;
		if (index < 0 || index > 6)
			index = 0;
		written = snprintf(out, cap, "%s", kWeekdays[index]);
	} else {
		written = snprintf(out, cap, "%02d.%02d.%02d", parts.tm_mday,
				parts.tm_mon + 1, parts.tm_year % 100);
	}

	if (written < 0)
		return 0;
	return strlen(out);
}

#endif // TGFASTDATE_H
