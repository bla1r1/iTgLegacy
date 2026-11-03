//
// TGCapabilities - runtime device and OS feature capability detection.
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

/// One TDLib client runs at a time, so a second account costs disk, not memory.
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

/// GIFs loop silently inside their bubble. They are small H.264 files, which
/// the A5 decodes in hardware a couple at a time; the A4 and older cannot
/// keep up while the list scrolls, so there a GIF plays on tap.
+ (BOOL)canAutoplayGIFs;
/// How many GIFs may play at once on this device.
+ (NSUInteger)maxConcurrentGIFs;

/// The system's row actions for a swiped chat row, from iOS 8. Earlier systems
/// get the chat list's own swipe.
+ (BOOL)canSwipeRowActions;

/// Emoji the system font can draw. Each iOS knows a later Unicode, and one
/// it does not know renders as nothing at all, so lists are filtered by it.
+ (BOOL)canDrawEmoji:(NSString *)emoji;

/// Power Saving. These say what the user has asked for, not what the device
/// can manage - nothing here turns on what the hardware cannot do, it only
/// turns off what it can. Default on.
+ (BOOL)animatedStickersWanted;
+ (void)setAnimatedStickersWanted:(BOOL)wanted;
+ (BOOL)wallpaperWanted;
+ (void)setWallpaperWanted:(BOOL)wanted;
+ (BOOL)gifAutoplayWanted;
+ (void)setGifAutoplayWanted:(BOOL)wanted;

/// Every capability with its state, for the Device screen.
+ (NSArray *)all;

@end
