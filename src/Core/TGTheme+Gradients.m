//
// TGTheme+Gradients - multi-stop colour sets.
//
// Everything in the app that is painted as a run of colours rather than a
// single fill lives here: the call backdrop moods, the bubble verticals, the
// button shine, and the chart ring palette. Each set answers one question -
// "which colours, top to bottom" - and the drawing engine in TGTheme+Drawing.m
// rasterises them. Single-stop depth materials are in TGTheme+Effects.m.
//
#import "TGThemeInternal.h"

#define rgb TGThemeRGB

@implementation TGTheme (Gradients)

#pragma mark - the call screen backdrop

// Satin in the classic palette, not a neon smear: DESIGN_SPEC §1.1 bans the
// purple-cyan gradient look, §2 asks for a "dynamic gradient backdrop" in
// the same family as the satin navigation header.

/// Two colours, top to bottom, behind a call in each of its three moods.
- (NSArray *)callGradientColours {
	return @[rgb(0x51, 0x7D, 0xA2), rgb(0x3B, 0x64, 0x88)];   // classic header satin
}

- (NSArray *)callGradientColoursConnected {
	return @[rgb(0x3F, 0x9B, 0x6B), rgb(0x2B, 0x74, 0x4F)];   // green satin
}

- (NSArray *)callGradientColoursFailed {
	return @[rgb(0x9E, 0x30, 0x30), rgb(0x52, 0x1B, 0x20)];   // deep crimson satin
}

#pragma mark - bubbles

/// Vertical celestial blue for your own skeuomorphic bubble, with deep blue in Night.
- (NSArray *)skeuoBubbleMineGradientColours {
	if (self.isDarkStyle) {
		return @[
			(id)rgb(0x28, 0x6E, 0x9B).CGColor,
			(id)rgb(0x1C, 0x58, 0x82).CGColor,
			(id)rgb(0x14, 0x46, 0x6A).CGColor
		];
	}
	return @[
		(id)rgb(0xE6, 0xF2, 0xFD).CGColor,
		(id)rgb(0xD6, 0xEB, 0xFA).CGColor,
		(id)rgb(0xC4, 0xE2, 0xF8).CGColor,
		(id)rgb(0xB4, 0xDA, 0xF5).CGColor
	];
}

/// Vertical whites in light, vertical charcoals in dark. Gradients run
/// top to bottom, so the first stop is always the lightest.
- (NSArray *)skeuoBubbleTheirsGradientColours {
	if (self.isDarkStyle) {
		return @[
			(id)rgb(0x2C, 0x2E, 0x33).CGColor,
			(id)rgb(0x24, 0x26, 0x2A).CGColor,
			(id)rgb(0x1B, 0x1C, 0x1F).CGColor
		];
	}
	return @[
		(id)rgb(0xFF, 0xFF, 0xFF).CGColor,
		(id)rgb(0xF2, 0xF2, 0xF5).CGColor,
		(id)rgb(0xDC, 0xDC, 0xE0).CGColor,
		(id)rgb(0xD0, 0xD0, 0xD6).CGColor
	];
}

/// Top glossy highlight on iOS 6 buttons. Three stops landing on full
/// transparency: the gloss plate ends at ~45% of the bubble height, and a
/// 4%-alpha tail used to leave a visible "two colours meet in the middle"
/// seam across every bubble.
- (NSArray *)skeuoShineGradientColours {
	return @[
		(id)[UIColor colorWithWhite:1.0f alpha:0.45f].CGColor,
		(id)[UIColor colorWithWhite:1.0f alpha:0.18f].CGColor,
		(id)[UIColor colorWithWhite:1.0f alpha:0.0f].CGColor
	];
}

#pragma mark - charts

/// The muted classic family, one tone per slice; the ring draws them in row
/// order, so the six must stay distinguishable side by side (the Telegram
/// parity colours were too web-bright against the iOS 6 canvas).
- (NSArray *)chartPalette {
	return @[rgb(0x51, 0x7D, 0xA2),   // classic header blue
			 rgb(0x4C, 0x9C, 0xC0),   // steel blue
			 rgb(0x6D, 0x9B, 0x57),   // sage green
			 rgb(0xC4, 0x9A, 0x3F),   // muted gold
			 rgb(0x9B, 0x6A, 0x4B),   // rust
			 rgb(0x86, 0x6B, 0x86)];  // plum
}

@end

// vim:ft=objc
