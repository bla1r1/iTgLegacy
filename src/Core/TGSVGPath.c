#include "TGSVGPath.h"
#include <math.h>
#include <stdlib.h>
#include <ctype.h>

typedef struct {
	const char *p;
	int ok;
} TGSVGReader;

static void TGSkip(TGSVGReader *r) {
	while (*r->p && (isspace((unsigned char)*r->p) || *r->p == ','))
		r->p++;
}

static int TGAtNumber(TGSVGReader *r) {
	TGSkip(r);
	char c = *r->p;
	return c == '-' || c == '+' || c == '.' || isdigit((unsigned char)c);
}

/// strtod reads "1.5.5" as 1.5 then ".5", and "1-2" as 1 then "-2", which is
/// exactly the packing the icon sets use.
static CGFloat TGNumber(TGSVGReader *r) {
	TGSkip(r);
	char *end = NULL;
	double v = strtod(r->p, &end);
	if (end == r->p) {
		r->ok = 0;
		return 0;
	}
	r->p = end;
	return (CGFloat)v;
}

/// An arc flag is one character and may touch the next number: "0120".
static int TGFlag(TGSVGReader *r) {
	TGSkip(r);
	char c = *r->p;
	if (c != '0' && c != '1') {
		r->ok = 0;
		return 0;
	}
	r->p++;
	return c == '1';
}

/// SVG's endpoint arc as cubic Béziers, a quarter turn at most per piece
/// (SVG 1.1 appendix F.6.5 for the centre, the usual 4/3·tan(θ/4) handles).
static void TGAddArc(CGMutablePathRef path, const CGAffineTransform *t,
					 CGFloat x1, CGFloat y1, CGFloat rx, CGFloat ry, CGFloat angle,
					 int large, int sweep, CGFloat x2, CGFloat y2) {
	if (x1 == x2 && y1 == y2)
		return;
	rx = fabs(rx);
	ry = fabs(ry);
	if (rx == 0 || ry == 0) {
		CGPathAddLineToPoint(path, t, x2, y2);
		return;
	}
	double phi = angle * M_PI / 180.0, cp = cos(phi), sp = sin(phi);
	double dx = (x1 - x2) / 2.0, dy = (y1 - y2) / 2.0;
	double x1p = cp * dx + sp * dy, y1p = -sp * dx + cp * dy;
	double lambda = (x1p * x1p) / (rx * rx) + (y1p * y1p) / (ry * ry);
	if (lambda > 1) {
		rx *= sqrt(lambda);
		ry *= sqrt(lambda);
	}
	double num = rx * rx * ry * ry - rx * rx * y1p * y1p - ry * ry * x1p * x1p;
	double den = rx * rx * y1p * y1p + ry * ry * x1p * x1p;
	double coef = (den == 0 || num < 0) ? 0 : sqrt(num / den);
	if (large == sweep)
		coef = -coef;
	double cxp = coef * rx * y1p / ry, cyp = -coef * ry * x1p / rx;
	double cx = cp * cxp - sp * cyp + (x1 + x2) / 2.0;
	double cy = sp * cxp + cp * cyp + (y1 + y2) / 2.0;

	double ux = (x1p - cxp) / rx, uy = (y1p - cyp) / ry;
	double vx = (-x1p - cxp) / rx, vy = (-y1p - cyp) / ry;
	double start = atan2(uy, ux);
	double delta = atan2(ux * vy - uy * vx, ux * vx + uy * vy);
	if (!sweep && delta > 0)
		delta -= 2 * M_PI;
	else if (sweep && delta < 0)
		delta += 2 * M_PI;

	int pieces = (int)ceil(fabs(delta) / (M_PI / 2) - 1e-9);
	if (pieces < 1)
		pieces = 1;
	double step = delta / pieces, k = 4.0 / 3.0 * tan(step / 4);
	for (int i = 0; i < pieces; i++) {
		double a = start + i * step, b = a + step;
		double ca = cos(a), sa = sin(a), cb = cos(b), sb = sin(b);
		// the unit-circle piece, stretched by the radii and turned by phi
		double p1x = ca - k * sa, p1y = sa + k * ca;
		double p2x = cb + k * sb, p2y = sb - k * cb;
#define TGARC_X(ux_, uy_) (cx + cp * rx * (ux_) - sp * ry * (uy_))
#define TGARC_Y(ux_, uy_) (cy + sp * rx * (ux_) + cp * ry * (uy_))
		CGPathAddCurveToPoint(path, t,
				TGARC_X(p1x, p1y), TGARC_Y(p1x, p1y),
				TGARC_X(p2x, p2y), TGARC_Y(p2x, p2y),
				TGARC_X(cb, sb), TGARC_Y(cb, sb));
#undef TGARC_X
#undef TGARC_Y
	}
}

CGPathRef TGSVGPathCreate(const char *d, CGFloat viewW, CGFloat viewH, CGRect box) {
	if (!d || viewW <= 0 || viewH <= 0)
		return NULL;

	CGFloat scale = fmin(box.size.width / viewW, box.size.height / viewH);
	CGAffineTransform t = CGAffineTransformMakeTranslation(
			box.origin.x + (box.size.width - viewW * scale) / 2,
			box.origin.y + (box.size.height - viewH * scale) / 2);
	t = CGAffineTransformScale(t, scale, scale);

	CGMutablePathRef path = CGPathCreateMutable();
	TGSVGReader r = {d, 1};
	CGFloat x = 0, y = 0, startX = 0, startY = 0;
	CGFloat lastCX = 0, lastCY = 0;     // the previous curve's last control point
	char cmd = 0, prev = 0;
	int segments = 0;

	for (;;) {
		TGSkip(&r);
		if (!*r.p)
			break;
		if (isalpha((unsigned char)*r.p)) {
			cmd = *r.p++;
		} else if (!cmd || toupper((unsigned char)cmd) == 'Z' || !TGAtNumber(&r)) {
			r.ok = 0;
			break;
		}
		// After a moveto, bare numbers are linetos of the same case.
		int rel = islower((unsigned char)cmd);
		char up = (char)toupper((unsigned char)cmd);
		CGFloat ox = rel ? x : 0, oy = rel ? y : 0;

		switch (up) {
		case 'M':
			x = ox + TGNumber(&r); y = oy + TGNumber(&r);
			CGPathMoveToPoint(path, &t, x, y);
			startX = x; startY = y;
			cmd = rel ? 'l' : 'L';
			break;
		case 'L':
			x = ox + TGNumber(&r); y = oy + TGNumber(&r);
			CGPathAddLineToPoint(path, &t, x, y);
			break;
		case 'H':
			x = ox + TGNumber(&r);
			CGPathAddLineToPoint(path, &t, x, y);
			break;
		case 'V':
			y = oy + TGNumber(&r);
			CGPathAddLineToPoint(path, &t, x, y);
			break;
		case 'C': {
			CGFloat x1 = ox + TGNumber(&r), y1 = oy + TGNumber(&r);
			CGFloat x2 = ox + TGNumber(&r), y2 = oy + TGNumber(&r);
			x = ox + TGNumber(&r); y = oy + TGNumber(&r);
			CGPathAddCurveToPoint(path, &t, x1, y1, x2, y2, x, y);
			lastCX = x2; lastCY = y2;
			break;
		}
		case 'S': {
			int smooth = prev == 'C' || prev == 'S';
			CGFloat x1 = smooth ? 2 * x - lastCX : x, y1 = smooth ? 2 * y - lastCY : y;
			CGFloat x2 = ox + TGNumber(&r), y2 = oy + TGNumber(&r);
			x = ox + TGNumber(&r); y = oy + TGNumber(&r);
			CGPathAddCurveToPoint(path, &t, x1, y1, x2, y2, x, y);
			lastCX = x2; lastCY = y2;
			break;
		}
		case 'Q': {
			CGFloat x1 = ox + TGNumber(&r), y1 = oy + TGNumber(&r);
			x = ox + TGNumber(&r); y = oy + TGNumber(&r);
			CGPathAddQuadCurveToPoint(path, &t, x1, y1, x, y);
			lastCX = x1; lastCY = y1;
			break;
		}
		case 'T': {
			int smooth = prev == 'Q' || prev == 'T';
			CGFloat x1 = smooth ? 2 * x - lastCX : x, y1 = smooth ? 2 * y - lastCY : y;
			x = ox + TGNumber(&r); y = oy + TGNumber(&r);
			CGPathAddQuadCurveToPoint(path, &t, x1, y1, x, y);
			lastCX = x1; lastCY = y1;
			break;
		}
		case 'A': {
			CGFloat rx = TGNumber(&r), ry = TGNumber(&r), angle = TGNumber(&r);
			int large = TGFlag(&r), sweep = TGFlag(&r);
			CGFloat nx = ox + TGNumber(&r), ny = oy + TGNumber(&r);
			if (r.ok)
				TGAddArc(path, &t, x, y, rx, ry, angle, large, sweep, nx, ny);
			x = nx; y = ny;
			break;
		}
		case 'Z':
			CGPathCloseSubpath(path);
			x = startX; y = startY;
			break;
		default:
			r.ok = 0;
			break;
		}
		if (!r.ok)
			break;
		prev = up;
		segments++;
	}

	if (!r.ok || segments == 0 || CGPathIsEmpty(path)) {
		CGPathRelease(path);
		return NULL;
	}
	return path;
}
