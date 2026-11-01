//
// TGClient+Calls.h - the two diagnostics a finished call can send.
//
// The call itself is over TGCall and libtgvoip; these are what the record
// sheet under a call in Recent Calls offers afterwards: the client's own log
// of the call, and the JSON debug record Telegram reads when a call went
// wrong. Both name the call through the message it left in the history, so a
// call that ended can still be reported without keeping its live id.
//
#import "TGClient+Base.h"

@interface TGClient (Calls)

/// The log file this client writes for the call behind a message: its
/// direction, duration, end reason and the device it ran on. TDLib accepts
/// only a local file here, so the text is written to the temporary
/// directory, sent as inputFileLocal and removed when the server answers.
- (void)sendCallLog:(NSString *)log
		 forMessage:(int64_t)messageId
			 inChat:(int64_t)chatId
		 completion:(void (^)(BOOL ok, NSString *error))completion;

/// The same call's debug record, as a JSON string TDLib forwards to
/// Telegram untouched. A user account is usually refused; the screen shows
/// the server's sentence instead of guessing.
- (void)sendCallDebugInformation:(NSString *)information
					  forMessage:(int64_t)messageId
						  inChat:(int64_t)chatId
					  completion:(void (^)(BOOL ok, NSString *error))completion;

@end
