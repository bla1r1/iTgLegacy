//
// TGClient+Support.h - Telegram's support identity and the optional note a
// person can attach to their support request.
//
// getSupportName and the two UserSupportInfo calls are support-staff
// plumbing: a normal account often gets Telegram's refusal. The Settings
// page sends them and prints that sentence rather than hiding the row.
//
#import "TGClient+Base.h"

@interface TGClient (Support)

- (void)supportNameWithCompletion:(void (^)(NSString *name,
											NSString *error))completion;

/// "message", "author" and "date" for one user's support note.
- (void)supportInfoForUser:(int64_t)userId
				completion:(void (^)(NSDictionary *info,
									 NSString *error))completion;

/// Sets the note; the answer is the updated UserSupportInfo.
- (void)setSupportInfo:(NSString *)message
				forUser:(int64_t)userId
			 completion:(void (^)(NSDictionary *info,
								  NSString *error))completion;

@end

// vim:ft=objc
