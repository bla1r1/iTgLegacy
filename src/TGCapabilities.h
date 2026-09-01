//
// TGCapabilities - what this build may switch on, decided at runtime.
//
// The app targets iPhone 3GS through anything current, so a feature is not
// "impossible" so much as "not available here". Each flag answers one question
// about the machine the code is running on, and the screens ask rather than
// assume. Anything the API cannot do at all - buying Stars, for one - is not a
// capability and does not appear here.
//
#import <Foundation/Foundation.h>
#import "TGDevice.h"

/// One capability, so a screen can list them with a reason rather than just
/// hiding things silently.
@interface TGCapability : NSObject
@property (nonatomic, strong) NSString *name;
@property (nonatomic, assign) BOOL available;
@property (nonatomic, strong) NSString *requirement;   ///< what it waits for
@end

@interface TGCapabilities : NSObject

/// iOS version as a number: 7.12 for 7.1.2, 12.4 for 12.4.
+ (double)systemVersion;
/// 64-bit device: iPhone 5s and later.
+ (BOOL)is64Bit;
/// Physical memory in megabytes.
+ (NSUInteger)memoryMB;

/// A modern web view, which mini apps and payment pages need. WKWebView
/// arrived in iOS 8, and its JavaScript is only usable from about iOS 9.
+ (BOOL)canRunWebApps;

/// Animated stickers and custom emoji: one Lottie frame per message is more
/// than an A5 has to spare.
+ (BOOL)canAnimateInline;

/// A second TDLib client for another account. Each costs tens of megabytes.
+ (BOOL)canHoldMultipleAccounts;

/// Video calls need a hardware H.264 encoder driven in real time, which
/// starts at the A7. Voice calls are a separate question - libtgvoip ran on
/// an iPhone 4S when Telegram shipped calls, so that one is a build problem
/// rather than a hardware one.
+ (BOOL)canEncodeVideoCall;

/// Animated .tgs stickers play rather than showing their first frame.
+ (BOOL)canPlayAnimatedStickers;
/// Wallpapers, which cost a full-screen image held in memory.
+ (BOOL)canShowWallpaper;

/// Power Saving. These say what the user has asked for, not what the device
/// can manage - nothing here turns on what the hardware cannot do, it only
/// turns off what it can. Default on.
+ (BOOL)animatedStickersWanted;
+ (void)setAnimatedStickersWanted:(BOOL)wanted;
+ (BOOL)wallpaperWanted;
+ (void)setWallpaperWanted:(BOOL)wanted;

/// Every capability with its state, for the Device screen.
+ (NSArray *)all;

@end
