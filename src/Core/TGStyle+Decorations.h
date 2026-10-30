//
// TGStyle+Decorations.h
// Shadows, geometry inlines, alpha tokens, transforms, animation timings and strokes.
//
#import <UIKit/UIKit.h>

#ifdef __cplusplus
extern "C" {
#endif

#pragma mark - geometry math helpers

/// Returns half of a dimension without manual / 2 division.
static inline __attribute__((always_inline)) CGFloat TGHalf(CGFloat val) {
	return val * 0.5f;
}

/// Returns double of a dimension without manual * 2 multiplication.
static inline __attribute__((always_inline)) CGFloat TGDoubled(CGFloat val) {
	return val * 2.0f;
}

/// Computes the origin to center an item within a container without manual / 2 division.
static inline __attribute__((always_inline)) CGFloat TGCenteredOrigin(CGFloat containerSize, CGFloat itemSize) {
	return (containerSize - itemSize) * 0.5f;
}

#pragma mark - strokes and borders

/// Primary line-art icon stroke weight (1.8 pt).
static const CGFloat TGMetricStrokeIcon         = 1.8f;
/// Standard iOS hairline separator (0.5 pt on Retina).
static const CGFloat TGMetricHairline           = 0.5f;
/// 0 pt border stroke (flat mode).
static const CGFloat TGMetricBorderNone         = 0.0f;
/// Standard 1 pt border stroke.
static const CGFloat TGMetricBorderWidth        = 1.0f;
/// Standard medium border stroke.
static const CGFloat TGMetricBorderMedium       = 1.5f;
/// Standard thick 2 pt border stroke.
static const CGFloat TGMetricBorderThick        = 2.0f;

#pragma mark - motion and animation

/// Fast transition (150ms): dates, badges, immediate feedback.
static const NSTimeInterval TGAnimationDurationFast   = 0.15;
/// Standard transition (200ms): sheets, popups, viewer chrome.
static const NSTimeInterval TGAnimationDurationNormal = 0.20;
/// Medium transition (250ms): keyboard slide, composer expansion.
static const NSTimeInterval TGAnimationDurationMedium = 0.25;
/// Slow transition (300ms): toasts, screen cross-fades.
static const NSTimeInterval TGAnimationDurationSlow   = 0.30;
/// Long highlight pulse (600ms): jump-to-message highlight dissipation.
static const NSTimeInterval TGAnimationDurationHighlight = 0.60;

#pragma mark - elevation and shadows

/// Floating menu shadow blur radius (10 pt).
static const CGFloat TGMetricShadowMenuRadius   = 10.0f;
/// Floating menu shadow opacity (28%).
static const CGFloat TGMetricShadowMenuOpacity  = 0.28f;
/// Floating button shadow blur radius (2 pt).
static const CGFloat TGMetricShadowButtonRadius = 2.0f;
/// Floating button shadow opacity (18%).
static const CGFloat TGMetricShadowButtonOpacity= 0.18f;
/// Skeuomorphic etched light text shadow offset (0, 1).
static const CGSize TGMetricShadowOffsetEtched  = {0.0f, 1.0f};
/// Skeuomorphic recessed navigation bar title shadow offset (0, -1).
static const CGSize TGMetricShadowOffsetNav     = {0.0f, -1.0f};
/// Floating card / popup menu downward shadow offset (0, 4).
static const CGSize TGMetricShadowOffsetMenu    = {0.0f, 4.0f};

#pragma mark - opacity and alpha tokens

/// Fully opaque (1.0).
static const CGFloat TGAlphaOpaque            = 1.0f;
/// Inactive folder pill / panel tab (0.85).
static const CGFloat TGAlphaPillInactive      = 0.85f;
/// Secondary button / hint icon (0.75).
static const CGFloat TGAlphaSecondary         = 0.75f;
/// Dimmed control / call end button (0.50).
static const CGFloat TGAlphaDimmed            = 0.50f;
/// Disabled button / action item (0.40).
static const CGFloat TGAlphaDisabled          = 0.40f;
/// Message highlight flash start (0.30).
static const CGFloat TGAlphaHighlight         = 0.30f;
/// Pulse ring / track trace opacity (0.25).
static const CGFloat TGAlphaRingTrack         = 0.25f;
/// Minimum threshold alpha to consider non-empty (0.01).
static const CGFloat TGAlphaEpsilon           = 0.01f;
/// Fully transparent (0.0).
static const CGFloat TGAlphaTransparent       = 0.0f;

#pragma mark - transform scales

/// Dragged folder pill active scale (1.08).
static const CGFloat TGTransformScalePillActive   = 1.08f;
/// Active call end button press scale (0.86).
static const CGFloat TGTransformScaleButtonActive = 0.86f;
/// Popup menu appearance initial scale (0.85).
static const CGFloat TGTransformScaleMenuInitial  = 0.85f;
/// The ring a held call control wears: wider than the button it surrounds.
static const CGFloat TGTransformScaleRingHeld     = 1.22f;
/// Audio mic button small scale (0.30).
static const CGFloat TGTransformScaleSmall        = 0.30f;

#pragma mark - gesture damping and rubberband tokens

/// Rubberband damping resistance when pulling beyond threshold (0.25).
static const CGFloat TGDampingRubberband          = 0.25f;
/// Voice lock upward tracking friction multiplier (0.40).
static const CGFloat TGDampingVoiceLock           = 0.40f;
/// Voice slide-to-cancel tracking multiplier (0.70).
static const CGFloat TGDampingVoiceCancel         = 0.70f;
/// Minimum scale of inline reply icon during pull (0.60).
static const CGFloat TGTransformScaleReplyMin     = 0.60f;
/// Growth range scale of inline reply icon during pull (0.40).
static const CGFloat TGTransformScaleReplyRange   = 0.40f;
/// Minimum alpha of voice slide cancel hint (0.10).
static const CGFloat TGAlphaVoiceCancelMin        = 0.10f;
/// Recording pulse breathing scale amplitude (0.08).
static const CGFloat TGAnimationPulseAmplitude    = 0.08f;

#ifdef __cplusplus
}
#endif
