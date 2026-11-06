//
// TGCallVideoEngine.h - lightweight camera capture, H.264 encode/decode & rendering.
//
#import <Foundation/Foundation.h>
#import <AVFoundation/AVFoundation.h>
#import <VideoToolbox/VideoToolbox.h>
#import <CoreMedia/CoreMedia.h>
#import <CoreVideo/CoreVideo.h>

#if TARGET_OS_IPHONE
#import <UIKit/UIKit.h>
#else
@class UIView;
#endif

@interface TGCallVideoEngine : NSObject

@property (nonatomic, assign, readonly) BOOL isCapturing;
@property (nonatomic, assign, readonly) BOOL hasRemoteVideo;
@property (nonatomic, assign) AVCaptureDevicePosition cameraPosition;

/// Block called when an encoded H.264 RTP packet is ready to send.
@property (nonatomic, copy) void (^sendVideoRtpBlock)(NSData *rtpPacket);

/// Block called when a decoded frame (CVPixelBufferRef) is produced.
@property (nonatomic, copy) void (^onDecodedPixelBuffer)(CVPixelBufferRef pixelBuffer);

/// Block called on the main queue when remote video active state changes.
@property (nonatomic, copy) void (^onRemoteVideoStateChanged)(BOOL active);

/// The view displaying the remote peer's video (full-screen in video call).
@property (nonatomic, strong, readonly) UIView *remoteVideoView;

/// The view displaying local camera preview (Picture-in-Picture).
@property (nonatomic, strong, readonly) UIView *localPreviewView;

- (instancetype)initWithSsrc:(uint32_t)ssrc;

/// Start local camera capture and hardware H.264 compression.
- (BOOL)startCapture;

/// Stop camera capture and release compression session.
- (void)stopCapture;

/// Switch between front and rear cameras.
- (void)switchCamera;

/// Process an incoming RTP video packet from the peer (type 6 payload).
- (void)handleIncomingVideoRtp:(const uint8_t *)bytes length:(size_t)length;

/// Reset and tear down all capture, compression, decompression and view resources.
- (void)stop;

@end
