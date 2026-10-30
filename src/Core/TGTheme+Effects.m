//
// TGTheme+Effects - depth: glass, shadows, gloss, bevels.
//
// This is the file to read when something looks "frosted" or "embossed".
//
// There is deliberately no GPU blur anywhere (no UIVisualEffectView, no
// CoreImage): this app targets A5/A6 chips where an offscreen blur eats the
// whole frame budget (DESIGN_SPEC.md, performance section). Frost and glass
// are imitated with translucent flat colours instead - the callout family
// below is a full kit for that: the plate, its recessed tray, hairline
// border, etched dividers and the two-stop gloss reflection.
//
// Drawing those materials onto pixels is the engine's job (TGTheme+Drawing.m).
//
#import "TGThemeInternal.h"
#import "TGStyle.h"

#define rgb TGThemeRGB

@implementation TGTheme (Effects)

#pragma mark - frosted glass (the "blur" substitute)

- (UIColor *)calloutBackgroundColour {
	///< the satin glass plate behind popup callouts and reaction bars
	if (self.isDarkStyle) {
		return rgb(0x22, 0x24, 0x28);
	}
	// Light / White theme: luminous white/pearl skeuomorphic card
	return [UIColor colorWithRed:0.96f green:0.97f blue:0.98f alpha:0.98f];
}

- (UIColor *)calloutTrayColour {
	///< recessed dark well for reactions
	if (self.isDarkStyle) {
		return [UIColor colorWithWhite:0.0f alpha:0.35f];
	}
	return [UIColor colorWithWhite:0.0f alpha:0.06f];
}

- (UIColor *)calloutBorderColour {
	if (self.isDarkStyle) {
		return [UIColor colorWithWhite:1.0f alpha:0.25f];
	}
	return [UIColor colorWithRed:0.72f green:0.75f blue:0.78f alpha:0.90f];
}

- (UIColor *)calloutDividerDarkColour {
	///< etched dark groove
	if (self.isDarkStyle) {
		return [UIColor colorWithWhite:0.0f alpha:0.45f];
	}
	return [UIColor colorWithWhite:0.0f alpha:0.12f];
}

- (UIColor *)calloutDividerLightColour {
	///< etched specular highlight
	if (self.isDarkStyle) {
		return [UIColor colorWithWhite:1.0f alpha:0.08f];
	}
	return [UIColor colorWithWhite:1.0f alpha:0.85f];
}

- (UIColor *)calloutGlossTopColour {
	///< specular top reflection for callout popup menu
	return TGRole(@"calloutGlossTop", [UIColor colorWithWhite:1.0f alpha:0.18f],
			[UIColor colorWithWhite:1.0f alpha:0.65f]);
}

- (UIColor *)calloutGlossBottomColour {
	///< specular fade for callout popup menu
	return TGRole(@"calloutGlossBottom", [UIColor colorWithWhite:1.0f alpha:0.04f],
			[UIColor colorWithWhite:1.0f alpha:0.10f]);
}

#pragma mark - shadows and etching

- (UIColor *)skeuoShineColour {
	return [UIColor colorWithWhite:1.0f alpha:0.18f];   ///< shine on iOS 6 buttons
}

- (UIColor *)etchedTextShadowColour {
	return [UIColor colorWithWhite:1.0f alpha:0.7f];    ///< light drop shadow under text
}

- (UIColor *)navBarTextShadowColour {
	return [UIColor colorWithWhite:0.0f alpha:0.4f];    ///< dark shadow under nav titles
}

- (UIColor *)buttonHighlightColour {
	return [[self accentColour] colorWithAlphaComponent:0.4f];
}

#pragma mark - bubble bevels and geometry

- (UIColor *)skeuoBubbleMineBorderColour {
	///< soft celestial blue stroke in light, hairline blue-white in dark
	if (self.isDarkStyle) {
		return [UIColor colorWithRed:0.25f green:0.55f blue:0.75f alpha:0.40f];
	}
	return rgb(0x99, 0xC4, 0xE8);
}

- (UIColor *)skeuoBubbleTheirsBorderColour {
	///< tactile outer border on theirs
	if (self.isDarkStyle) {
		return [UIColor colorWithWhite:1.0f alpha:0.12f];
	}
	return rgb(0xB0, 0xB0, 0xB6);
}

- (CGFloat)bubbleCornerRadius {
	return TGMetricCornerBubbleSkeuo;
}

- (CGFloat)bubbleJoinedCornerRadius {
	return TGMetricCornerBubbleJoined;
}

- (CGFloat)bubbleBorderWidth {
	return TGMetricBorderWidth;         ///< 0 when flat
}

@end

// vim:ft=objc
