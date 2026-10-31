//
// TGTextDraw.m - see TGTextDraw.h for why this exists.
//
#import "TGTextDraw.h"
#import "TGStyle.h"

/// respondsToSelector: is not the test. On 6.1.6 NSString answers YES for
/// drawInRect:withAttributes: and the send then dies inside objc_msgSend
/// resolving it (EXC_BAD_ACCESS, the fault address is the selector slot, not
/// the string) - the method is declared in that UIKit without being usable.
/// The OS version is the only honest question, so it is asked once.
static BOOL TGAttributedTextDrawing(void) {
	static BOOL modern = NO;
	static BOOL asked = NO;
	if (!asked){
		asked = YES;
		modern = NSFoundationVersionNumber > NSFoundationVersionNumber_iOS_6_1;
		NSLog(@"[LegacyTG] text drawing: %s (Foundation %.2f)",
				modern ? "attributes" : "pre-7", NSFoundationVersionNumber);
	}
	return modern;
}

CGSize TGLineTextSize(NSString *text, UIFont *font) {
	if (!text.length || !font)
		return CGSizeZero;
	if (TGAttributedTextDrawing())
		return [text sizeWithAttributes:@{NSFontAttributeName : font}];
	return [text sizeWithFont:font];
}

CGFloat TGTextHeight(NSString *text, UIFont *font, CGFloat width) {
	if (!text.length || !font || width <= 0.0f)
		return 0.0f;
	CGSize bound = CGSizeMake(width, TGMetricTextMeasureHeight);
	if (TGAttributedTextDrawing())
		return ceilf([text boundingRectWithSize:bound
									   options:NSStringDrawingUsesLineFragmentOrigin
									attributes:@{NSFontAttributeName : font}
									   context:nil].size.height);
	return ceilf([text sizeWithFont:font constrainedToSize:bound
					  lineBreakMode:NSLineBreakByWordWrapping].height);
}

void TGDrawText(NSString *text, CGRect rect, UIFont *font, UIColor *colour,
				NSTextAlignment alignment, NSShadow *shadow) {
	if (!text.length || !font)
		return;

	if (TGAttributedTextDrawing()){
		NSMutableParagraphStyle *style = [[NSMutableParagraphStyle alloc] init];
		style.alignment = alignment;
		NSMutableDictionary *attrs = [NSMutableDictionary dictionaryWithCapacity:4];
		attrs[NSFontAttributeName] = font;
		attrs[NSParagraphStyleAttributeName] = style;
		if (colour)
			attrs[NSForegroundColorAttributeName] = colour;
		if (shadow)
			attrs[NSShadowAttributeName] = shadow;
		[text drawInRect:rect withAttributes:attrs];
		return;
	}

	// Pre-7 there is no attribute dictionary to carry them, so the colour is
	// the context's fill colour and the shadow is the context's shadow.
	CGContextRef ctx = UIGraphicsGetCurrentContext();
	if (ctx)
		CGContextSaveGState(ctx);
	if (ctx && shadow){
		id shadowColour = shadow.shadowColor;
		CGContextSetShadowWithColor(ctx, shadow.shadowOffset, shadow.shadowBlurRadius,
				[shadowColour isKindOfClass:UIColor.class]
						? ((UIColor *)shadowColour).CGColor : NULL);
	}
	[(colour ?: [UIColor blackColor]) set];
	[text drawInRect:rect withFont:font lineBreakMode:NSLineBreakByClipping
		   alignment:alignment];
	if (ctx)
		CGContextRestoreGState(ctx);
}
