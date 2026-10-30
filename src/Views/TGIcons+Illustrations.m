//
// TGIcons+Illustrations.m
// Full-canvas empty state vector illustrations.
//
#import "TGIconsInternal.h"

@implementation TGIcons (Illustrations)

+ (UIImage *)emptyChatsIllustration {
	return [self iconNamed:@"emptyChats" draw:^(CGContextRef ctx, CGFloat s){
		// Stylized dual speech bubbles with tactile overlapping depth
		CGContextSetLineWidth(ctx, TGIconStroke);
		CGContextSetLineJoin(ctx, kCGLineJoinRound);

		// Back bubble
		UIBezierPath *b1 = [UIBezierPath bezierPathWithRoundedRect:CGRectMake(8.0f, 4.0f, s - 14.0f, s * 0.44f) cornerRadius:6.0f];
		CGContextAddPath(ctx, b1.CGPath);
		CGContextStrokePath(ctx);

		// Front bubble with offset
		UIBezierPath *b2 = [UIBezierPath bezierPathWithRoundedRect:CGRectMake(4.0f, 13.0f, s - 14.0f, s * 0.44f) cornerRadius:6.0f];
		CGContextAddPath(ctx, b2.CGPath);
		CGContextStrokePath(ctx);
	}];
}

+ (UIImage *)emptyContactsIllustration {
	return [self iconNamed:@"emptyContacts" draw:^(CGContextRef ctx, CGFloat s){
		CGContextSetLineWidth(ctx, TGIconStroke);
		CGContextSetLineJoin(ctx, kCGLineJoinRound);

		// Address book outline
		CGRect r = CGRectMake(6.0f, 4.0f, s - 12.0f, s - 8.0f);
		UIBezierPath *book = [UIBezierPath bezierPathWithRoundedRect:r cornerRadius:4.0f];
		CGContextAddPath(ctx, book.CGPath);
		CGContextStrokePath(ctx);

		// Profile silhouette inside
		CGFloat mid = TGHalf(s);
		CGContextFillEllipseInRect(ctx, CGRectMake(mid - 4.0f, 9.0f, 8.0f, 8.0f));
		UIBezierPath *body = [UIBezierPath bezierPathWithRoundedRect:CGRectMake(mid - 7.0f, 19.0f, 14.0f, 7.0f) cornerRadius:3.5f];
		CGContextAddPath(ctx, body.CGPath);
		CGContextFillPath(ctx);
	}];
}

+ (UIImage *)emptySearchIllustration {
	return [self iconNamed:@"emptySearch" draw:^(CGContextRef ctx, CGFloat s){
		CGContextSetLineWidth(ctx, TGIconStroke);
		CGContextSetLineCap(ctx, kCGLineCapRound);

		// Large magnifying glass
		CGFloat r = 8.0f;
		CGPoint c = CGPointMake(TGHalf(s) - 2.0f, TGHalf(s) - 2.0f);
		CGContextAddArc(ctx, c.x, c.y, r, 0, (CGFloat)(M_PI * 2.0), 1);
		CGContextStrokePath(ctx);

		// Handle
		CGContextMoveToPoint(ctx, c.x + 5.5f, c.y + 5.5f);
		CGContextAddLineToPoint(ctx, s - 6.0f, s - 6.0f);
		CGContextStrokePath(ctx);
	}];
}

@end
