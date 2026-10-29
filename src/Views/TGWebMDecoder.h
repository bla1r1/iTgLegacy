//
// TGWebMDecoder.h - Lightweight WebM VP9 video sticker decoder for iOS.
//
#import <UIKit/UIKit.h>

@interface TGWebMDecoder : NSObject

/// Decodes a WebM video sticker (VP9 with optional alpha stream) into an array of CGImageRef frames.
/// Returns an NSArray of id (where each element is a (__bridge id)CGImageRef).
/// Returns nil if decoding fails.
+ (NSArray *)decodeFramesFromFile:(NSString *)path
                              fps:(double *)outFps
                         duration:(NSTimeInterval *)outDuration;

/// Returns the first frame of a WebM file as a UIImage.
+ (UIImage *)firstFrameFromFile:(NSString *)path;

@end
