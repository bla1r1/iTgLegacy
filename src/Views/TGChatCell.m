#import "TGChatCell.h"
#import "TGTheme.h"
#import <QuartzCore/QuartzCore.h>
#import "TGStyle.h"

static const CGFloat kInset    = TGMetricPadMedium;   // picture from the left edge, text from the right
static const CGFloat kTextLeft = kInset + kAvatar + TGMetricPadMedium;
/// The row carries two lines: the name with the date and ticks beside it,
/// then the preview with the unread badge or the pin beside that.
static const CGFloat kFirstLineTop  = TGMetricPadMedium;
static const CGFloat kSecondLineTop = 32.0f;
static const CGFloat kPreviewMax    = 40.0f;
static const CGFloat kMuteGlyph     = 16.0f;
static const CGFloat kMuteRoom      = 20.0f;
static const CGFloat kPinGlyph      = 16.0f;
static const CGFloat kBadgePad      = TGMetricPadMedium + TGMetricPadTiny;

static CGSize TGChatCellTextSize(NSString *text, UIFont *font) {
	if (!text.length || !font) return CGSizeZero;
	if ([text respondsToSelector:@selector(sizeWithAttributes:)]) {
		return [text sizeWithAttributes:@{NSFontAttributeName: font}];
	}
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wdeprecated-declarations"
	return [text sizeWithFont:font];
#pragma clang diagnostic pop
}

/// Their titles are a medium weight, not bold; Helvetica Neue has carried one
/// since iOS 5, and bold is the fallback where it does not.
static UIFont *TGChatCellTitleFont(void) {
	return TGFontListTitle();
}

@implementation TGChatCell

- (id)initWithStyle:(UITableViewCellStyle)style reuseIdentifier:(NSString *)reuseIdentifier {
	self = [super initWithStyle:style reuseIdentifier:reuseIdentifier];
	if (!self)
		return nil;

	CGFloat scale = [UIScreen mainScreen].scale;
	TGTheme *theme = [TGTheme shared];

	self.backgroundColor = [theme listBackgroundColour];
	self.contentView.backgroundColor = [theme listBackgroundColour];

	self.avatar = [[UIImageView alloc] initWithFrame:CGRectMake(kInset, TGCenteredOrigin(kRowHeight, kAvatar), kAvatar, kAvatar)];
	self.avatar.layer.cornerRadius = TGHalf(kAvatar);
	self.avatar.clipsToBounds = YES;
	self.avatar.layer.shouldRasterize = YES;
	self.avatar.layer.rasterizationScale = scale;
	self.avatar.layer.borderColor = [theme separatorColour].CGColor;
	self.avatar.layer.borderWidth = 1.0f;
	self.avatar.backgroundColor = [theme fileTileColour];
	self.avatar.contentMode = UIViewContentModeScaleAspectFill;
	[self.contentView addSubview:self.avatar];

	self.titleLabel = [[UILabel alloc] init];
	self.titleLabel.font = TGChatCellTitleFont();
	self.titleLabel.textColor = [theme primaryTextColour];
	self.titleLabel.lineBreakMode = NSLineBreakByTruncatingTail;
	[self.contentView addSubview:self.titleLabel];

	self.previewLabel = [[UILabel alloc] init];
	self.previewLabel.font = TGFontBody();
	self.previewLabel.textColor = [theme secondaryTextColour];
	self.previewLabel.numberOfLines = 2;
	self.previewLabel.lineBreakMode = NSLineBreakByTruncatingTail;
	[self.contentView addSubview:self.previewLabel];

	self.dateLabel = [[UILabel alloc] init];
	self.dateLabel.font = TGFontSubhead();
	self.dateLabel.textColor = [theme listDateColour];
	self.dateLabel.textAlignment = NSTextAlignmentRight;
	[self.contentView addSubview:self.dateLabel];

	self.badge = [[UILabel alloc] init];
	self.badge.font = TGFontCaptionStrong();
	self.badge.textColor = [UIColor whiteColor];
	self.badge.backgroundColor = [theme badgeColour];
	self.badge.textAlignment = NSTextAlignmentCenter;
	self.badge.layer.cornerRadius = TGHalf(TGMetricChatBadgeHeight);
	self.badge.clipsToBounds = YES;
	self.badge.layer.shouldRasterize = YES;
	self.badge.layer.rasterizationScale = scale;
	self.badge.hidden = YES;
	[self.contentView addSubview:self.badge];

	CGFloat dot = 15;
	self.onlineDot = [[UIView alloc] initWithFrame:
			CGRectMake(kInset + kAvatar - dot, TGCenteredOrigin(kRowHeight, kAvatar) + kAvatar - dot, dot, dot)];
	self.onlineDot.backgroundColor = [theme onlineColour];
	self.onlineDot.layer.cornerRadius = TGHalf(dot);
	self.onlineDot.layer.borderWidth = TGMetricBorderThick;
	self.onlineDot.layer.borderColor = [theme listBackgroundColour].CGColor;
	self.onlineDot.layer.shouldRasterize = YES;
	self.onlineDot.layer.rasterizationScale = scale;
	self.onlineDot.hidden = YES;
	[self.contentView addSubview:self.onlineDot];

	self.tick = [[UIImageView alloc] init];
	self.tick.hidden = YES;
	[self.contentView addSubview:self.tick];

	self.pin = [[UIImageView alloc] init];
	self.pin.contentMode = UIViewContentModeScaleAspectFit;
	self.pin.hidden = YES;
	[self.contentView addSubview:self.pin];

	self.muteIcon = [[UIImageView alloc] init];
	self.muteIcon.contentMode = UIViewContentModeScaleAspectFit;
	self.muteIcon.hidden = YES;
	[self.contentView addSubview:self.muteIcon];

	// The table's own separator runs under the picture and cannot be inset
	// before iOS 7, so the row draws its own.
	self.separator = [[UIView alloc] init];
	self.separator.backgroundColor = [theme separatorColour];
	[self.contentView addSubview:self.separator];

	// No disclosure arrow: a chat row is not a settings row.
	self.accessoryType = UITableViewCellAccessoryNone;
	return self;
}

- (void)setPreview:(NSString *)text author:(NSString *)author {
	TGTheme *theme = [TGTheme shared];
	text = text ?: @"";
	if (!author.length || ![self.previewLabel respondsToSelector:@selector(setAttributedText:)]) {
		self.previewLabel.text = author.length ? [NSString stringWithFormat:@"%@: %@", author, text] : text;
		return;
	}
	NSString *prefix = [author stringByAppendingString:@": "];
	NSMutableAttributedString *line = [[NSMutableAttributedString alloc]
			initWithString:[prefix stringByAppendingString:text]
				attributes:@{NSFontAttributeName: self.previewLabel.font,
							 NSForegroundColorAttributeName: [theme secondaryTextColour]}];
	[line addAttribute:NSForegroundColorAttributeName
				 value:[theme primaryTextColour]
				 range:NSMakeRange(0, prefix.length)];
	self.previewLabel.attributedText = line;
}

- (void)layoutSubviews {
	[super layoutSubviews];
	CGFloat w = self.contentView.bounds.size.width;
	CGFloat h = self.contentView.bounds.size.height;
	CGFloat right = w - kInset;

	// The first line: the date pinned to the right edge, the ticks before it,
	// and the title taking whatever is left.
	CGSize date = TGChatCellTextSize(self.dateLabel.text, self.dateLabel.font);
	self.dateLabel.frame = CGRectMake(right - ceilf(date.width), kFirstLineTop + TGMetricBorderWidth,
			ceilf(date.width), TGMetricLineBody);
	CGFloat titleRight = CGRectGetMinX(self.dateLabel.frame) - TGMetricChatCellDateGap;
	if (!self.tick.hidden) {
		self.tick.frame = CGRectMake(titleRight - TGMetricTicksWidth,
				kFirstLineTop + TGMetricPadSmall, TGMetricTicksWidth,
				TGMetricTicksHeight);
		titleRight -= (TGMetricTicksWidth + TGMetricPadSmall);
	}

	CGFloat muteW = self.muteIcon.hidden ? 0 : kMuteRoom;
	CGFloat titleRoom = MAX(0, titleRight - kTextLeft - muteW);
	CGFloat titleW = MIN(ceilf(TGChatCellTextSize(self.titleLabel.text, self.titleLabel.font).width), titleRoom);
	self.titleLabel.frame = CGRectMake(kTextLeft, kFirstLineTop, titleW, TGMetricLineRow);
	if (!self.muteIcon.hidden)
		self.muteIcon.frame = CGRectMake(kTextLeft + titleW + TGMetricBubbleRowInset,
				kFirstLineTop + TGMetricPadTiny, kMuteGlyph, kMuteGlyph);

	// The second line: the badge (or the pin) at the right edge, and the
	// preview wrapping onto a second line up to it.
	CGFloat previewRight = right;
	if (!self.badge.hidden) {
		CGSize s = TGChatCellTextSize(self.badge.text, self.badge.font);
		CGFloat bw = MAX(TGMetricChatBadgeHeight, ceilf(s.width) + kBadgePad);
		self.badge.frame = CGRectMake(right - bw, TGMetricChatBadgeTop, bw,
								  TGMetricChatBadgeHeight);
		previewRight = right - bw - TGMetricPad;
	} else if (!self.pin.hidden) {
		self.pin.frame = CGRectMake(right - kPinGlyph, TGMetricChatBadgeTop + TGMetricPadTiny,
				kPinGlyph, kPinGlyph);
		previewRight = right - kPinGlyph - TGMetricPad;
	}
	CGFloat previewW = MAX(0, previewRight - kTextLeft);
	CGSize fit = [self.previewLabel sizeThatFits:CGSizeMake(previewW, kPreviewMax)];
	self.previewLabel.frame = CGRectMake(kTextLeft, kSecondLineTop, previewW,
			MIN(ceilf(fit.height), kPreviewMax - TGMetricPadTiny));

	CGFloat hair = TGMetricHairline;
	self.separator.frame = CGRectMake(kTextLeft, h - hair, w - kTextLeft, hair);
}

- (void)applyTheme {
	TGTheme *theme = [TGTheme shared];
	self.backgroundColor = [theme listBackgroundColour];
	self.contentView.backgroundColor = [theme listBackgroundColour];
	self.titleLabel.textColor = [theme primaryTextColour];
	self.previewLabel.textColor = [theme secondaryTextColour];
	self.dateLabel.textColor = [theme listDateColour];
	self.badge.backgroundColor = [theme badgeColour];
	self.onlineDot.backgroundColor = [theme onlineColour];
	self.onlineDot.layer.borderColor = [theme listBackgroundColour].CGColor;
	self.separator.backgroundColor = [theme separatorColour];
}

@end
