//
// TGPasscode.h - App passcode lock management and security.
//
#import <Foundation/Foundation.h>

FOUNDATION_EXPORT NSString *const TGPasscodeDidChangeNotification;
FOUNDATION_EXPORT NSString *const TGPasscodeDidLockNotification;
FOUNDATION_EXPORT NSString *const TGPasscodeDidUnlockNotification;

@interface TGPasscode : NSObject

+ (BOOL)hasPasscode;
+ (BOOL)verifyPasscode:(NSString *)pin;
+ (void)setPasscode:(NSString *)pin;
+ (void)clearPasscode;

/// Seconds before the app locks itself while backgrounded:
/// 0: immediately
/// 60: 1 minute
/// 300: 5 minutes (default)
/// 3600: 1 hour
/// -1: disabled
+ (NSInteger)autoLockTimeout;
+ (void)setAutoLockTimeout:(NSInteger)seconds;
+ (NSString *)autoLockTitleForSeconds:(NSInteger)seconds;

+ (BOOL)isLocked;
+ (void)setLocked:(BOOL)locked;
+ (void)noteAppBackgrounded;
+ (BOOL)shouldLockOnForeground;

@end
