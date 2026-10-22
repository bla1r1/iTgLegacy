//
// TGDevice - which iPhone this is, and what may be asked of it.
//
// The app runs from an iPhone 3GS on iOS 6 to anything that still takes a
// sideloaded build, and the difference between the ends of that range is a
// factor of thirty in memory and more in CPU. Rather than scatter version
// checks, every device falls into one of four tiers, and features ask for a
// tier.
//
//   Vintage  armv7, 256-512MB, iOS 6-7      3GS, 4
//   Legacy   armv7, 512MB-1GB, iOS 8-10     4S, 5, 5c, iPod touch 5
//   Modern   arm64, 1GB,       iOS 11-12    5s, 6, 6 Plus, iPod touch 6
//   Full     arm64, 2GB+,      iOS 12+      6s and later
//
#import <Foundation/Foundation.h>

typedef NS_ENUM(NSInteger, TGDeviceTier) {
    TGDeviceTierVintage = 0,
    TGDeviceTierLegacy  = 1,
    TGDeviceTierModern  = 2,
    TGDeviceTierFull    = 3
};

@interface TGDevice : NSObject

/// "iPhone4,1" - the identifier the hardware reports.
+ (NSString *)machine;
/// "iPhone 4S", or the raw identifier for anything not in the table.
+ (NSString *)modelName;
/// "A5", or nil.
+ (NSString *)chip;
/// Memory the model shipped with; falls back to what the OS reports.
+ (NSUInteger)memoryMB;
/// Highest iOS the model ever ran, as a number. 0 when unknown.
+ (double)maximumIOS;

+ (TGDeviceTier)tier;
+ (NSString *)tierName;
/// One line for a settings screen: "iPhone 4S - A5, 512 MB, iOS 7.1.2".
+ (NSString *)summary;

@end
