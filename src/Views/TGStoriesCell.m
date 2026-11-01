#import "TGStoriesCell.h"
#import "TGTheme.h"
#import "TGStyle.h"
#import "TGIcons.h"
#import <QuartzCore/QuartzCore.h>

/// The strip scrolls; the cell does not. Ten bubbles fit the first screen and
/// the rest are a swipe away, which is how the official clients keep the row
/// from turning into a second table.
@interface TGStoriesCell () <UIScrollViewDelegate>
@property (nonatomic, strong) UIScrollView *strip;
@end

@implementation TGStoriesCell

- (instancetype)initWithStyle:(UITableViewCellStyle)style
			   reuseIdentifier:(NSString *)reuseIdentifier {
	self = [super initWithStyle:style reuseIdentifier:reuseIdentifier];
	if (self){
		self.selectionStyle = UITableViewCellSelectionStyleNone;
		self.backgroundColor = [[TGTheme shared] listBackgroundColour];
		self.contentView.backgroundColor = self.backgroundColor;
		_strip = [[UIScrollView alloc] initWithFrame:CGRectZero];
		_strip.showsHorizontalScrollIndicator = NO;
		_strip.alwaysBounceHorizontal = YES;
		_strip.backgroundColor = [UIColor clearColor];
		_strip.delegate = self;
		[self.contentView addSubview:_strip];
	}
	return self;
}

- (void)setStories:(NSArray *)stories {
	_stories = [stories copy];
	[self rebuild];
}

- (void)setOwnStory:(NSDictionary *)ownStory {
	_ownStory = [ownStory copy];
	[self rebuild];
}

- (void)layoutSubviews {
	[super layoutSubviews];
	self.strip.frame = CGRectMake(0, 0, self.contentView.bounds.size.width,
								   TGMetricStoryStripRow);
	CGFloat content = [self bubbleCount] * (TGMetricStoryBubble +
			TGMetricStoryBubbleGap) - TGMetricStoryBubbleGap;
	self.strip.contentSize = CGSizeMake(content + TGDoubled(TGMetricStoryBubbleGap),
										TGMetricStoryStripRow);
}

- (NSInteger)bubbleCount {
	return (NSInteger)self.stories.count + 1;   // My Story, then everyone else
}

- (void)rebuild {
	for (UIView *view in [self.strip.subviews copy])
		[view removeFromSuperview];

	CGFloat x = TGMetricStoryBubbleGap;
	NSString *ownTitle = self.ownStory[@"title"];
	UIImage *ownImage = self.ownStory[@"avatarImage"];
	if (!ownImage){
		NSString *first = ownTitle.length
				? [ownTitle substringToIndex:1].uppercaseString : @"?";
		ownImage = [TGIcons avatarWithInitials:first
										 size:TGMetricStoryAvatar
									 colourId:[self.ownStory[@"chatId"] longLongValue]];
	}
	[self addMyStoryAt:x image:ownImage];
	x += TGMetricStoryBubble + TGMetricStoryBubbleGap;

	for (NSInteger i = 0; i < (NSInteger)self.stories.count; i++){
		NSDictionary *row = self.stories[i];
		NSString *title = row[@"title"] ?: @"";
		UIImage *image = row[@"avatarImage"];
		if (!image){
			NSString *first = title.length
					? [title substringToIndex:1].uppercaseString : @"?";
			image = [TGIcons avatarWithInitials:first
										 size:TGMetricStoryAvatar
									 colourId:[row[@"chatId"] longLongValue]];
		}
		BOOL unread = [row[@"unread"] boolValue];
		[self addBubbleAt:x title:title ring:unread ? @YES : @NO image:image tag:i];
		x += TGMetricStoryBubble + TGMetricStoryBubbleGap;
	}

	self.strip.contentSize = CGSizeMake(x, TGMetricStoryStripRow);
	[self setNeedsLayout];
}

/// The own tile is not a story bubble: it is the account's face with a plus
/// badge, and the badge is the way in even when there is nothing to watch.
- (void)addMyStoryAt:(CGFloat)x image:(UIImage *)image {
	UIView *bubble = [[UIView alloc] initWithFrame:CGRectMake(
			x, TGMetricStoryStripTop, TGMetricStoryBubble, TGMetricStoryBubble)];

	UIImageView *picture = [[UIImageView alloc] initWithFrame:bubble.bounds];
	picture.image = image;
	picture.contentMode = UIViewContentModeScaleAspectFill;
	picture.clipsToBounds = YES;
	picture.layer.cornerRadius = TGHalf(TGMetricStoryBubble);
	picture.backgroundColor = [[TGTheme shared] fileTileColour];
	[bubble addSubview:picture];

	CGFloat badge = TGMetricStoryBubble * 0.34f;
	UIView *plate = [[UIView alloc] initWithFrame:CGRectMake(
			CGRectGetMaxX(bubble.bounds) - badge - 1,
			CGRectGetMaxY(bubble.bounds) - badge - 1, badge, badge)];
	plate.backgroundColor = [[TGTheme shared] accentColour];
	plate.layer.cornerRadius = TGHalf(badge);
	plate.layer.borderWidth = 2.0f;
	plate.layer.borderColor = [[TGTheme shared] listBackgroundColour].CGColor;
	[bubble addSubview:plate];

	UIImageView *plus = [[UIImageView alloc] initWithFrame:plate.bounds];
	plus.image = [TGIcons glyphNamed:@"plus"
							  colour:[[TGTheme shared] onAccentColour]
								side:badge * 0.52f];
	plus.contentMode = UIViewContentModeCenter;
	[plate addSubview:plus];

	UILabel *label = [[UILabel alloc] initWithFrame:CGRectMake(
			x, TGMetricStoryStripTop + TGMetricStoryBubble +
			   TGMetricStoryLabelTopGap,
			TGMetricStoryBubble, TGMetricStoryLabelHeight)];
	label.text = self.ownStory[@"title"] ?: @"My Story";
	label.font = TGFontMicro();
	label.textAlignment = NSTextAlignmentCenter;
	label.textColor = [[TGTheme shared] secondaryTextColour];
	label.backgroundColor = [UIColor clearColor];
	label.lineBreakMode = NSLineBreakByTruncatingTail;
	[self.strip addSubview:label];

	UIButton *hit = [UIButton buttonWithType:UIButtonTypeCustom];
	hit.frame = CGRectMake(x, TGMetricStoryStripTop, TGMetricStoryBubble,
						   TGMetricStoryBubble + TGMetricStoryLabelTopGap +
						   TGMetricStoryLabelHeight);
	hit.tag = -1;
	[hit addTarget:self action:@selector(bubbleTapped:)
		  forControlEvents:UIControlEventTouchUpInside];
	UILongPressGestureRecognizer *hold = [[UILongPressGestureRecognizer alloc]
			initWithTarget:self action:@selector(bubbleHeld:)];
	hold.minimumPressDuration = 0.45;
	[hit addGestureRecognizer:hold];
	[self.strip addSubview:bubble];
	[self.strip addSubview:hit];
}

/// One bubble: the ring is a separate view behind the picture, so a read
/// story and an unread one differ by one colour rather than by two images.
- (void)addBubbleAt:(CGFloat)x
			  title:(NSString *)title
			   ring:(NSNumber *)unread
				image:(UIImage *)image
				 tag:(NSInteger)tag {
	UIView *bubble = [[UIView alloc] initWithFrame:CGRectMake(
			x, TGMetricStoryStripTop, TGMetricStoryBubble, TGMetricStoryBubble)];

	if (tag == -1 || tag == -2){
		UIView *plate = [[UIView alloc] initWithFrame:bubble.bounds];
		plate.backgroundColor = tag == -1
				? [[TGTheme shared] accentColour]
				: [[TGTheme shared] cardBackgroundColour];
		plate.layer.cornerRadius = TGHalf(TGMetricStoryBubble);
		plate.layer.borderWidth = TGMetricHairline;
		plate.layer.borderColor = [[TGTheme shared] separatorColour].CGColor;
		[bubble addSubview:plate];
	} else {
		UIView *ring = [[UIView alloc] initWithFrame:bubble.bounds];
		ring.backgroundColor = [UIColor clearColor];
		ring.layer.cornerRadius = TGHalf(TGMetricStoryBubble);
		ring.layer.borderWidth = TGMetricStoryRing;
		ring.layer.borderColor = (unread.boolValue
				? [[TGTheme shared] accentColour]
				: [[TGTheme shared] separatorColour]).CGColor;
		[bubble addSubview:ring];
	}

	CGFloat inset = TGHalf(TGMetricStoryBubble - TGMetricStoryAvatar);
	UIImageView *picture = [[UIImageView alloc] initWithFrame:CGRectMake(
			inset, inset, TGMetricStoryAvatar, TGMetricStoryAvatar)];
	picture.image = image;
	picture.contentMode = UIViewContentModeScaleAspectFill;
	picture.clipsToBounds = YES;
	picture.layer.cornerRadius = TGHalf(TGMetricStoryAvatar);
	picture.backgroundColor = [[TGTheme shared] fileTileColour];
	[bubble addSubview:picture];

	UILabel *label = [[UILabel alloc] initWithFrame:CGRectMake(
			x, TGMetricStoryStripTop + TGMetricStoryBubble +
			   TGMetricStoryLabelTopGap,
			TGMetricStoryBubble, TGMetricStoryLabelHeight)];
	label.text = title;
	label.font = TGFontMicro();
	label.textAlignment = NSTextAlignmentCenter;
	label.textColor = [[TGTheme shared] secondaryTextColour];
	label.backgroundColor = [UIColor clearColor];
	label.lineBreakMode = NSLineBreakByTruncatingTail;
	[self.strip addSubview:label];

	UIButton *hit = [UIButton buttonWithType:UIButtonTypeCustom];
	hit.frame = CGRectMake(x, TGMetricStoryStripTop, TGMetricStoryBubble,
						   TGMetricStoryBubble + TGMetricStoryLabelTopGap +
						   TGMetricStoryLabelHeight);
	hit.tag = tag;
	[hit addTarget:self action:@selector(bubbleTapped:)
		  forControlEvents:UIControlEventTouchUpInside];
	UILongPressGestureRecognizer *hold = [[UILongPressGestureRecognizer alloc]
			initWithTarget:self action:@selector(bubbleHeld:)];
	hold.minimumPressDuration = 0.45;
	[hit addGestureRecognizer:hold];
	[self.strip addSubview:bubble];
	[self.strip addSubview:hit];
}

- (void)bubbleTapped:(UIButton *)button {
	if (button.tag == -1){
		if (self.onMyStoryTapped)
			self.onMyStoryTapped();
		else if (self.onAddStory)
			self.onAddStory();
		return;
	}
	if (button.tag == -2){
		if (self.onMore)
			self.onMore();
		return;
	}
	if (button.tag >= 0 && button.tag < (NSInteger)self.stories.count &&
		self.onStoryTapped)
		self.onStoryTapped(self.stories[button.tag]);
}

- (void)bubbleHeld:(UILongPressGestureRecognizer *)hold {
	if (hold.state != UIGestureRecognizerStateBegan)
		return;
	UIView *view = hold.view;
	if (![view isKindOfClass:UIButton.class])
		return;
	NSInteger tag = ((UIButton *)view).tag;
	if (tag == -1){
		if (self.onMyStoryHeld)
			self.onMyStoryHeld();
		return;
	}
	if (tag >= 0 && tag < (NSInteger)self.stories.count && self.onStoryHeld)
		self.onStoryHeld(self.stories[tag]);
}

@end
