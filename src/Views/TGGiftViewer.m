//
// TGGiftViewer.m - the gift detail sheet.
//
#import "TGGiftViewer.h"
#import "TGTheme.h"
#import "TGIcons.h"
#import "TGClient.h"
#import <QuartzCore/QuartzCore.h>
#import "TGStyle.h"

static const CGFloat kSide    = TGMetricPadLarge;   ///< card side margin, as TGAttachSheet pads its rows
static const CGFloat kRow     = TGMetricRow;
static const CGFloat kButton  = TGMetricButtonHeight;
static const CGFloat kClose   = TGMetricCloseSide;
static const CGFloat kAvatar  = TGMetricGiftAvatar;
static const CGFloat kStar    = TGMetricGiftStar;
static const CGFloat kCloseGlyph = 16.0f;   ///< the cross inside kClose
/// The caption column on the left of a row, and the gap between a value and
/// the face or star that sits in front of it.
static const CGFloat kCaptionW   = 100.0f;
static const CGFloat kValueGap   = 6.0f;
static const CGFloat kStarGap    = TGMetricPadSmall;
/// A value's own line, which is set against the middle of its row.
static const CGFloat kValueLine  = TGMetricLineRow;
/// The heading, which is one line of title type set a little tight.
static const CGFloat kTitleLine  = 24.0f;
/// The note a gift may carry, padded as a service plate is.
static const CGFloat kNotePadH   = TGMetricPadMedium + TGMetricPadTiny;
static const CGFloat kNotePadV   = TGMetricPadMedium;

/// sizeWithFont: is gone from iOS 7 on, and sizeWithAttributes: does not
/// exist before it - TGChatCell picks between them the same way.
static CGSize TGGiftTextSize(NSString *text, UIFont *font) {
	if (!text.length)
		return CGSizeZero;
	if ([text respondsToSelector:@selector(sizeWithAttributes:)])
		return [text sizeWithAttributes:@{NSFontAttributeName: font}];
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wdeprecated-declarations"
	return [text sizeWithFont:font];
#pragma clang diagnostic pop
}

static CGFloat TGGiftTextHeight(NSString *text, UIFont *font, CGFloat width) {
	if (!text.length)
		return 0;
	if ([text respondsToSelector:@selector(boundingRectWithSize:options:attributes:context:)])
		return ceilf([text boundingRectWithSize:CGSizeMake(width, TGMetricTextMeasureHeight)
									   options:NSStringDrawingUsesLineFragmentOrigin
									attributes:@{NSFontAttributeName: font}
									   context:nil].size.height);
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wdeprecated-declarations"
	return ceilf([text sizeWithFont:font
				 constrainedToSize:CGSizeMake(width, TGMetricTextMeasureHeight)
					 lineBreakMode:NSLineBreakByWordWrapping].height);
#pragma clang diagnostic pop
}

static UIImage *TGGiftArtworkGlyph(NSString *emoji, CGFloat side) {
	if (!emoji.length)
		emoji = @"🎁";
	static NSCache *cache = nil;
	static dispatch_once_t once;
	dispatch_once(&once, ^{
		cache = [[NSCache alloc] init];
	});
	NSString *key = [emoji stringByAppendingFormat:@"@%g", side];
	UIImage *cached = [cache objectForKey:key];
	if (cached)
		return cached;

	UIGraphicsBeginImageContextWithOptions(CGSizeMake(side, side), NO, 0);
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wdeprecated-declarations"
	CGFloat inset = side * TGMetricEmojiArtworkInsetRatio;
	CGFloat emojiSize = side * TGMetricEmojiArtworkSizeRatio;
	[emoji drawInRect:CGRectMake(inset, inset, emojiSize, emojiSize)
			 withFont:TGFontBoldAtSize(side - inset * TGMetricEmojiArtworkFontInsetRatio)
		lineBreakMode:NSLineBreakByClipping
		   alignment:NSTextAlignmentCenter];
#pragma clang diagnostic pop
	UIImage *img = UIGraphicsGetImageFromCurrentImageContext();
	UIGraphicsEndImageContext();
	[cache setObject:img forKey:key];
	return img;
}

static NSString *TGGiftStamp(NSNumber *unix) {
	if (![unix isKindOfClass:NSNumber.class] || unix.doubleValue <= 0)
		return @"";
	static NSDateFormatter *fmt = nil;
	static dispatch_once_t once;
	dispatch_once(&once, ^{
		// "27.01.26, 23:05" - the stamp the gift table reads.
		fmt = [[NSDateFormatter alloc] init];
		fmt.dateFormat = @"dd.MM.yy, HH:mm";
	});
	return [fmt stringFromDate:[NSDate dateWithTimeIntervalSince1970:unix.doubleValue]];
}

@implementation TGGiftViewer {
	UIView *_card;
}

+ (void)dismiss {
	[TGSheet dismissOpen];
}

+ (void)showGift:(NSDictionary *)gift inView:(UIView *)host {
	if (!gift || !host)
		return;
	TGGiftViewer *viewer = [TGGiftViewer sheetForView:host];
	[viewer buildWithGift:gift];
	[viewer present];
}

- (void)buildWithGift:(NSDictionary *)gift {
	TGTheme *theme = [TGTheme shared];
	CGFloat width = self.bounds.size.width ?: TGMetricScreenWidth;
	CGFloat inner = width - TGDoubled(kSide);

	NSString *emoji = gift[@"emoji"] ?: @"";
	NSString *message = gift[@"message"];
	NSInteger stars = MAX(0, [gift[@"starCount"] integerValue]);

	// Heights first: the card is as tall as its contents, the way the
	// official sheet grows for a gift that carries a note.
	UIFont *messageFont = TGFontBody();
	CGFloat artSide = floorf(MIN(TGMetricGiftArtMaxSide, inner * TGMetricGiftArtRatio));
	CGFloat messageH = message.length
			? TGGiftTextHeight(message, messageFont, inner - 24) + 20 : 0;

	CGFloat y = 12;
	CGFloat artY = y + kClose + 4;
	CGFloat titleY = artY + artSide + 10;
	CGFloat tableY = titleY + 24 + 14;
	CGFloat messageY = tableY + kRow * 3 + (message.length ? 14 : 0);
	CGFloat okY = messageY + messageH + 16;
	CGFloat cardHeight = okY + kButton + 16;

	_card = [self addCardOfHeight:cardHeight edgeToEdge:YES];

	UIButton *close = [UIButton buttonWithType:UIButtonTypeCustom];
	close.frame = CGRectMake(kSide, y, kClose, kClose);
	close.layer.cornerRadius = TGHalf(kClose);
	close.layer.masksToBounds = YES;
	close.backgroundColor = [theme fileTileColour];
	[close setImage:[TGIcons glyphNamed:@"close"
								 colour:[[TGTheme shared] secondaryTextColour]
								   side:kCloseGlyph]
		   forState:UIControlStateNormal];
	[close setTitleColor:[theme secondaryTextColour] forState:UIControlStateNormal];
	[close setTitleColor:[theme placeholderColour] forState:UIControlStateHighlighted];
	close.titleLabel.font = TGFontBody();
	[close addTarget:self action:@selector(dismiss)
		  forControlEvents:UIControlEventTouchUpInside];
	[_card addSubview:close];

	UIImageView *art = [[UIImageView alloc] initWithFrame:CGRectMake(
			TGCenteredOrigin(width, artSide), artY, artSide, artSide)];
	art.contentMode = UIViewContentModeScaleAspectFit;
	art.image = TGGiftArtworkGlyph(emoji, artSide);
	art.clipsToBounds = YES;
	[_card addSubview:art];

	// The artwork is the sticker's still picture; the emoji glyph above is
	// the placeholder it wears until the download lands.
	NSNumber *thumbId = gift[@"thumbFileId"];
	if ([thumbId isKindOfClass:NSNumber.class] && thumbId.integerValue > 0){
		[[TGClient shared] downloadFile:thumbId.integerValue
							   completion:^(NSString *path){
			if (!path.length)
				return;
			dispatch_async(dispatch_get_global_queue(
					DISPATCH_QUEUE_PRIORITY_LOW, 0), ^{
				UIImage *photo = [TGIcons decodedImage:
						[UIImage imageWithContentsOfFile:path]
						fittingSize:CGSizeMake(artSide, artSide)
						fill:NO scale:[UIScreen mainScreen].scale];
				if (!photo)
					return;
				dispatch_async(dispatch_get_main_queue(), ^{
					if (art.superview)
						art.image = photo;
				});
			});
		}];
	}

	// The schema carries no gift name, so the heading is the plain word and
	// the stars ride the Value row, as they do officially.
	UILabel *titleLabel = [[UILabel alloc] initWithFrame:CGRectMake(
			kSide, titleY, inner, kTitleLine)];
	titleLabel.text = @"Gift";
	titleLabel.font = TGFontTitle();
	titleLabel.textColor = [theme primaryTextColour];
	titleLabel.textAlignment = NSTextAlignmentCenter;
	titleLabel.backgroundColor = [UIColor clearColor];
	[_card addSubview:titleLabel];

	[self addTableAtY:tableY width:width gift:gift stars:stars];

	if (message.length){
		// A note comes with the gift the way a service plate carries text
		// in a chat: the same colours, so a theme reaches it too.
		UIView *note = [[UIView alloc] initWithFrame:CGRectMake(
				kSide, messageY, inner, messageH)];
		note.backgroundColor = [theme serviceBubbleColour];
		note.layer.cornerRadius = TGMetricCornerCard;
		note.layer.masksToBounds = YES;
		[_card addSubview:note];

		UILabel *text = [[UILabel alloc] initWithFrame:CGRectMake(
				kNotePadH, kNotePadV, inner - TGDoubled(kNotePadH),
				messageH - TGDoubled(kNotePadV))];
		text.text = message;
		text.font = messageFont;
		text.textColor = [theme serviceTextColour];
		text.numberOfLines = 0;
		text.textAlignment = NSTextAlignmentCenter;
		text.backgroundColor = [UIColor clearColor];
		[note addSubview:text];
	}

	UIButton *ok = [UIButton buttonWithType:UIButtonTypeCustom];
	ok.frame = CGRectMake(kSide, okY, inner, kButton);
	ok.backgroundColor = [theme accentColour];
	ok.layer.cornerRadius = TGMetricCornerCard;
	ok.layer.masksToBounds = YES;
	[ok setTitle:@"OK" forState:UIControlStateNormal];
	ok.titleLabel.font = TGFontHeader();
	[ok setTitleColor:[UIColor whiteColor] forState:UIControlStateNormal];
	[ok addTarget:self action:@selector(dismiss)
		  forControlEvents:UIControlEventTouchUpInside];
	[_card addSubview:ok];
}

/// From / Date / Value, read as settings rows do: the caption grey on the
/// left, the value on the right, a hairline between them. No row fill - the
/// card is the surface, the way the official table sits on the sheet.
- (void)addTableAtY:(CGFloat)tableY
			  width:(CGFloat)width
			   gift:(NSDictionary *)gift
			  stars:(NSInteger)stars {
	TGTheme *theme = [TGTheme shared];
	CGFloat inner = width - TGDoubled(kSide);
	NSArray *labels = @[@"From", @"Date", @"Value"];

	for (NSInteger i = 0; i < (NSInteger)labels.count; i++){
		CGFloat y = tableY + kRow * i;

		UILabel *name = [[UILabel alloc] initWithFrame:CGRectMake(
				kSide, y, kCaptionW, kRow)];
		name.text = labels[i];
		name.font = TGFontBody();
		name.textColor = [theme secondaryTextColour];
		name.backgroundColor = [UIColor clearColor];
		[_card addSubview:name];

		if (i > 0){
			UIView *hair = [[UIView alloc] initWithFrame:CGRectMake(
					kSide, y - TGMetricHairline, inner, TGMetricHairline)];
			hair.backgroundColor = [theme separatorColour];
			[_card addSubview:hair];
		}

		// The value hugs the right edge; its width is whatever the text needs.
		CGFloat right = width - kSide;
		if (i == 1){
			[self addRightLabel:TGGiftStamp(gift[@"date"])
							 at:CGPointMake(right, y + TGHalf(kRow))
						   bold:NO
						 colour:[theme primaryTextColour]];
		} else if (i == 2){
			UIFont *font = TGFontBodyStrong();
			NSString *count = [NSString stringWithFormat:@"%ld", (long)stars];
			CGFloat countW = ceilf(TGGiftTextSize(count, font).width);
			[self addRightLabel:count
							 at:CGPointMake(right, y + TGHalf(kRow))
						   bold:YES
						 colour:[theme primaryTextColour]];
			// Telegram Stars are gold wherever they appear, theme or not.
			UIImageView *star = [[UIImageView alloc] initWithFrame:CGRectMake(
					right - countW - kStarGap - kStar, y + TGCenteredOrigin(kRow, kStar),
					kStar, kStar)];
			star.image = [TGIcons glyphNamed:@"star"
									  colour:[[TGTheme shared] giftStarColour]
										side:kStar];
			[_card addSubview:star];
		} else {
			[self addFromRowAtY:y right:right gift:gift];
		}
	}
}

- (UILabel *)addRightLabel:(NSString *)text
						at:(CGPoint)rightCentre
					  bold:(BOOL)bold
					colour:(UIColor *)colour {
	UIFont *font = bold ? TGFontBodyStrong()
						: TGFontBody();
	CGFloat w = ceilf(TGGiftTextSize(text, font).width) + 1;
	UILabel *label = [[UILabel alloc] initWithFrame:CGRectMake(
			rightCentre.x - w, rightCentre.y - TGHalf(kValueLine), w, kValueLine)];
	label.text = text;
	label.font = font;
	label.textColor = colour;
	label.textAlignment = NSTextAlignmentRight;
	label.backgroundColor = [UIColor clearColor];
	[_card addSubview:label];
	return label;
}

/// The sender rides the right of the From row: their face beside their name
/// in the accent colour, the face downloaded like every other avatar here.
- (void)addFromRowAtY:(CGFloat)y right:(CGFloat)right gift:(NSDictionary *)gift {
	NSInteger userId = [gift[@"senderUserId"] longLongValue];
	NSString *name = [[TGClient shared] nameForUserId:userId];
	if (!name.length)
		name = @"Unknown";

	UIFont *font = TGFontBodyStrong();
	CGFloat available = right - kSide - kCaptionW - kAvatar - kValueGap;
	CGFloat nameW = MIN(ceilf(TGGiftTextSize(name, font).width) + 1, available);
	UILabel *label = [[UILabel alloc] initWithFrame:CGRectMake(
			right - nameW, y + TGHalf(kRow) - TGHalf(kValueLine), nameW, kValueLine)];
	label.text = name;
	label.font = font;
	label.textColor = [[TGTheme shared] accentColour];
	label.textAlignment = NSTextAlignmentRight;
	label.lineBreakMode = NSLineBreakByTruncatingTail;
	label.backgroundColor = [UIColor clearColor];
	[_card addSubview:label];

	UIImageView *face = [[UIImageView alloc] initWithFrame:CGRectMake(
			right - nameW - kValueGap - kAvatar, y + TGCenteredOrigin(kRow, kAvatar),
			kAvatar, kAvatar)];
	face.layer.cornerRadius = TGHalf(kAvatar);
	face.clipsToBounds = YES;
	NSString *first = [name substringToIndex:1].uppercaseString;
	face.image = [TGIcons avatarWithInitials:first size:kAvatar colourId:userId];
	[_card addSubview:face];

	// The cached initials give way to the photo when it lands.
	NSNumber *fileId = [[TGClient shared] photoFileIdForUserId:userId];
	if ([fileId isKindOfClass:NSNumber.class] && fileId.integerValue > 0){
		__weak UIImageView *weakFace = face;
		[[TGClient shared] downloadFile:fileId.integerValue
							   completion:^(NSString *path){
			if (!path.length)
				return;
			dispatch_async(dispatch_get_global_queue(
					DISPATCH_QUEUE_PRIORITY_LOW, 0), ^{
				UIImage *photo = [TGIcons decodedImage:
						[UIImage imageWithContentsOfFile:path]
						fittingSize:CGSizeMake(kAvatar, kAvatar)
						fill:YES scale:[UIScreen mainScreen].scale];
				if (!photo)
					return;
				dispatch_async(dispatch_get_main_queue(), ^{
					weakFace.image = photo;
				});
			});
		}];
	}
}

@end
