// tests/shim/UIKit/UIKitShim.m — implementations backing tests/shim/UIKit.
//
// AppKit carries the real text engine, so measurement is honest system text
// layout; only the iOS-only entry points (deprecated NSString sizeWithFont:
// variants, NSAttributedString boundingRectWithSize:options:context:) and
// the data-holding UIKit classes themselves are provided here.
#import "UIKit.h"

#pragma mark - UIDevice

static UIDevice *TGSharedDevice = nil;

@implementation UIDevice
+ (UIDevice *)currentDevice {
	if (!TGSharedDevice)
		TGSharedDevice = [UIDevice new];
	return TGSharedDevice;
}
- (NSString *)model { return @"iPhone"; }
- (NSString *)systemVersion { return @"7.1.2"; }
@end

#pragma mark - host gaps

@implementation NSFont (UIKitHostShim)
+ (UIFont *)italicSystemFontOfSize:(CGFloat)size {
	// italicSystemFontOfSize: is a UIKit convenience AppKit spells through
	// NSFontManager — what the tested code cares about is "an italic face
	// that differs from the regular face".
	NSFont *base = [NSFont systemFontOfSize:size];
	return [[NSFontManager sharedFontManager] convertFont:base
			toHaveTrait:NSFontItalicTrait];
}
@end

@implementation NSValue (UIKitHostShim)
+ (NSValue *)valueWithCGSize:(CGSize)size {
	return [self valueWithBytes:&size objCType:@encode(CGSize)];
}
- (CGSize)CGSizeValue {
	CGSize s;
	[self getValue:&s];
	return s;
}
@end

#pragma mark - UILabel

@implementation UILabel
@end

#pragma mark - NSString UIKit additions

// Word wrapping through AppKit's own layout engine, which is what iOS's
// NSStringDrawing does on the device as well.
static CGSize TGWrappedSize(NSString *text, UIFont *font, CGSize max) {
	if (!font)
		font = [UIFont systemFontOfSize:14];

	NSMutableParagraphStyle *style = [[NSMutableParagraphStyle alloc] init];
	style.lineBreakMode = NSLineBreakByWordWrapping;
	NSDictionary *attrs = @{ NSFontAttributeName : font,
							 NSParagraphStyleAttributeName : style };

	NSAttributedString *as = [[NSAttributedString alloc]
			initWithString:text attributes:attrs];
	NSRect rect = [as boundingRectWithSize:max
			options:NSStringDrawingUsesLineFragmentOrigin |
					NSStringDrawingUsesFontLeading];

	return CGSizeMake(ceil(rect.size.width), ceil(rect.size.height));
}

@implementation NSString (UIKitHostShim)
- (CGSize)sizeWithFont:(UIFont *)font {
	return TGWrappedSize(self, font, CGSizeMake(CGFLOAT_MAX, CGFLOAT_MAX));
}

- (CGSize)sizeWithFont:(UIFont *)font constrainedToSize:(CGSize)size
		lineBreakMode:(NSInteger)lineBreakMode {
	return TGWrappedSize(self, font, size);
}
@end
