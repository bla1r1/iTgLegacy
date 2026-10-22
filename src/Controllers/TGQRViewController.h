//
// TGQRViewController - reads a QR code with the camera.
//
// No library: iOS 7 gained AVCaptureMetadataOutput, which recognises QR codes
// itself. A t.me link opens that chat; anything else is shown as text, because
// silently doing nothing with a code you just scanned is worse than saying you
// do not know what it is.
//
#import <UIKit/UIKit.h>

@interface TGQRViewController : UIViewController
@end
