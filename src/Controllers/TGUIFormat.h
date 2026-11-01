//
// TGUIFormat.h - the small, screen-independent strings several merged screens
// share: a call's clock, a scheduled message's date, a phone number put
// together from its two fields, and the match a forward search makes.
//
// Pure functions on purpose: the host suite can pin them without UIKit, and
// every screen that shows one of these strings then says the same thing.
//
#import <Foundation/Foundation.h>

#ifdef __cplusplus
extern "C" {
#endif

/// A call's duration the way Telegram writes it: 0:07, 12:04, 1:02:09.
NSString *TGUIFormatCallDuration(NSTimeInterval seconds);

/// "Today at 18:30", "Tomorrow at 09:00", "3 Nov at 09:00". `now` is passed in
/// so the host test does not depend on when it runs.
NSString *TGUIFormatScheduledWhen(NSTimeInterval sendDate, NSTimeInterval now);

/// "in 2 h 15 min" under a scheduled message; empty for a stamp in the past.
NSString *TGUIFormatScheduledRelative(NSTimeInterval sendDate, NSTimeInterval now);

/// The full number Telegram is asked to sign in: the prefix's digits, then
/// the national number's, without repeating a prefix already typed into it.
NSString *TGUIFormatFullPhone(NSString *prefix, NSString *number);

/// Whether a forward-picker query names a chat: case and accents do not
/// count, and an empty query matches everything.
BOOL TGUIFormatChatMatches(NSString *title, NSString *query);

#ifdef __cplusplus
}
#endif
