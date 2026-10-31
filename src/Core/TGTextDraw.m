//
// TGTextDraw.m - see TGTextDraw.h for why this exists.
//
#import "TGTextDraw.h"
#import "TGStyle.h"
#import "TGPerf.h"
#import <CoreText/CoreText.h>

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

// The first chat opened spent 130 ms of a 1.3 s open in read() on font files,
// inside the first text measure: CoreText loads a face, and the fallback faces
// for Cyrillic and emoji, the first time a glyph needs them. CGFont's cache is
// process-wide and thread-safe, so asking for glyph metrics on a background
// thread pays that cost while the user is still looking at the chat list.
// DEFAULT, not LOW or BACKGROUND: during launch TDLib keeps
// the default band busy and the lower ones did not run for 15-30 s, long
// after the first chat was open. The main thread still outranks it.
void TGWarmFonts(CGFloat bodySize) {
	NSArray *names = [NSArray arrayWithObjects:
			[UIFont systemFontOfSize:bodySize].fontName,
			[UIFont boldSystemFontOfSize:bodySize].fontName,
			[UIFont italicSystemFontOfSize:bodySize].fontName, nil];
	// Not the bundled OpenMoji: CoreText and UIKit's text system each load
	// their own 6.4 MB copy of its glyph tables, so warming it here doubled
	// it for good rather than sharing it.
	dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(1.0 * NSEC_PER_SEC)),
			dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
		double start = TGPerfNow();
		// Advances for every Latin and Cyrillic letter: CGFreetype reads
		// metrics from disk in pieces as glyphs first appear, and a cold open
		// spent 84 ms in fread under its first text measures. Not every glyph
		// and no drawing: all of OpenMojiColor's glyphs took 6 s, and drawing
		// a sample line with an emoji 300 ms per face.
		UniChar chars[0x60 + 0x100];
		CGGlyph ids[0x60 + 0x100];
		CFIndex n = 0;
		for (UniChar c = 0x20; c < 0x80; c++) chars[n++] = c;
		for (UniChar c = 0x400; c < 0x500; c++) chars[n++] = c;
		for (NSString *name in names) {
			CTFontRef font = CTFontCreateWithName((__bridge CFStringRef)name, bodySize, NULL);
			if (!font)
				continue;
			CTFontGetGlyphsForCharacters(font, chars, ids, n);
			CTFontGetAdvancesForGlyphs(font, kCTFontDefaultOrientation, ids, NULL, n);
			CFRelease(font);
		}
		TGPerfReport("fonts warmed", NULL, start, 0.0);
	});
}
