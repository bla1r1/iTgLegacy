//
// TGBarButtonItem.m
// TGUI Component Framework
//
#import "TGBarButtonItem.h"
#import "TGButton.h"
#import "TGStyle.h"
#import "TGTheme.h"
#import "TGIcons.h"
#import <QuartzCore/QuartzCore.h>

static const CGFloat kBarButtonHeight       = 30.0f;
static const CGFloat kBarButtonImageWidth   = 34.0f;
static const CGFloat kBarButtonMinTextWidth = 48.0f;
static const CGFloat kBackExtraWidth        = 24.0f;
static const CGFloat kStandardExtraWidth    = 20.0f;

@interface TGBarButtonItem ()
@property (nonatomic, strong) UIButton *customButton;
@end

@implementation TGBarButtonItem

- (instancetype)initWithTitle:(NSString *)title style:(TGBarButtonItemStyle)style target:(id)target action:(SEL)action {
	_itemStyle = style;
	
	UIButton *btn = [self createButtonForStyle:style title:title image:nil target:target action:action];
	self = [super initWithCustomView:btn];
	if (self) {
		_customButton = btn;
	}
	return self;
}

- (instancetype)initWithImage:(UIImage *)image style:(TGBarButtonItemStyle)style target:(id)target action:(SEL)action {
	_itemStyle = style;
	
	UIButton *btn = [self createButtonForStyle:style title:nil image:image target:target action:action];
	self = [super initWithCustomView:btn];
	if (self) {
		_customButton = btn;
	}
	return self;
}

- (instancetype)initBackButtonWithTitle:(NSString *)title target:(id)target action:(SEL)action {
	return [self initWithTitle:title ?: @"Back" style:TGBarButtonItemStyleBack target:target action:action];
}

- (UIButton *)createButtonForStyle:(TGBarButtonItemStyle)style title:(NSString *)title image:(UIImage *)image target:(id)target action:(SEL)action {
	UIButton *btn = [UIButton buttonWithType:UIButtonTypeCustom];
	[btn addTarget:target action:action forControlEvents:UIControlEventTouchUpInside];
	
	CGFloat h = kBarButtonHeight;
	btn.titleLabel.font = (style == TGBarButtonItemStyleDone) ? TGFontRowStrong() : TGFontRow();
	
	if (title) {
		[btn setTitle:title forState:UIControlStateNormal];
	}
	if (image) {
		[btn setImage:image forState:UIControlStateNormal];
	}
	
	CGSize textSize = title ? [title sizeWithFont:btn.titleLabel.font] : CGSizeZero;
	CGFloat extra = (style == TGBarButtonItemStyleBack) ? kBackExtraWidth : kStandardExtraWidth;
	CGFloat w = (image && !title) ? kBarButtonImageWidth : MAX(kBarButtonMinTextWidth, textSize.width + extra);
	btn.frame = CGRectMake(0, 0, w, h);
	
	if (style == TGBarButtonItemStyleBack) {
		UIImage *chevron = [TGIcons backChevronWithColour:[UIColor whiteColor]];
		[btn setImage:chevron forState:UIControlStateNormal];
		btn.imageEdgeInsets = UIEdgeInsetsMake(0, -TGMetricPadSmall, 0, 0);
		btn.titleEdgeInsets = UIEdgeInsetsMake(0, TGMetricPadTiny, 0, 0);
	}
	
	// Skeuomorphic background
	btn.layer.cornerRadius = (style == TGBarButtonItemStyleBack) ? TGHalf(h) : TGMetricCornerSmall;
	btn.layer.masksToBounds = YES;
	btn.layer.borderWidth = 1.0f;
	
	TGTheme *theme = [TGTheme shared];
	if (style == TGBarButtonItemStyleDone) {
		btn.backgroundColor = [theme accentColour];
		btn.layer.borderColor = [theme barButtonColour].CGColor;
	} else {
		btn.backgroundColor = [theme barColour];
		btn.layer.borderColor = [theme separatorColour].CGColor;
	}
	
	[btn setTitleColor:[theme barTitleColour] forState:UIControlStateNormal];
	
	return btn;
}

@end
