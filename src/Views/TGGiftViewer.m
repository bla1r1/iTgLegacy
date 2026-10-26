//
// TGGiftViewer.m - the gift detail sheet.
//
#import "TGGiftViewer.h"
#import "TGTheme.h"
#import "TGIcons.h"
#import "TGClient.h"
#import <QuartzCore/QuartzCore.h>
#import "TGStyle.h"

static const CGFloat kSide    = 16.0f;   ///< card side margin, as TGAttachSheet pads its rows
static const CGFloat kRow     = 44.0f;   ///< one attribute row, settings height
static const CGFloat kButton  = 48.0f;
static const CGFloat kClose   = 30.0f;
static const CGFloat kAvatar  = 22.0f;
static const CGFloat kStar    = 15.0f;

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
		return ceilf([text boundingRectWithSize:CGSizeMake(width, 10000)
									   options:NSStringDrawingUsesLineFragmentOrigin
									attributes:@{NSFontAttributeName: font}
									   context:nil].size.height);
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wdeprecated-declarations"
	return ceilf([text sizeWithFont:font
				 constrainedToSize:CGSizeMake(width, 10000)
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
	[emoji drawInRect:CGRectMake(side * 0.08f, side * 0.08f, side * 0.84f, side * 0.84f)
			 withFont:TGFontBoldAtSize(side * 0.72f)
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
	CGFloat width = self.bounds.size.width ?: 320;
	CGFloat inner = width - 2 * kSide;

	NSString *emoji = gift[@"emoji"] ?: @"";
	NSString *message = gift[@"message"];
	NSInteger stars = MAX(0, [gift[@"starCount"] integerValue]);

	// Heights first: the card is as tall as its contents, the way the
	// official sheet grows for a gift that carries a note.
	UIFont *messageFont = TGFontBody();
	CGFloat artSide = floorf(MIN(150, inner * 0.55f));
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
	close.layer.cornerRadius = kClose / 2;
	close.layer.masksToBounds = YES;
	close.backgroundColor = [theme fileTileColour];
	[close setTitle:@"✕" forState:UIControlStateNormal];
	[close setTitleColor:[theme secondaryTextColour] forState:UIControlStateNormal];
	[close setTitleColor:[theme placeholderColour] forState:UIControlStateHighlighted];
	close.titleLabel.font = TGFontBody();
	[close addTarget:self action:@selector(dismiss)
		  forControlEvents:UIControlEventTouchUpInside];
	[_card addSubview:close];

	UIImageView *art = [[UIImageView alloc] initWithFrame:CGRectMake(
			(width - artSide) / 2, artY, artSide, artSide)];
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
			kSide, titleY, inner, 24)];
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
		note.layer.cornerRadius = 12;
		note.layer.masksToBounds = YES;
		[_card addSubview:note];

		UILabel *text = [[UILabel alloc] initWithFrame:CGRectMake(
				12, 10, inner - 24, messageH - 20)];
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
	ok.layer.cornerRadius = 12;
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
	CGFloat inner = width - 2 * kSide;
	NSArray *labels = @[@"From", @"Date", @"Value"];

	for (NSInteger i = 0; i < (NSInteger)labels.count; i++){
		CGFloat y = tableY + kRow * i;

		UILabel *name = [[UILabel alloc] initWithFrame:CGRectMake(
				kSide, y, 100, kRow)];
		name.text = labels[i];
		name.font = TGFontBody();
		name.textColor = [theme secondaryTextColour];
		name.backgroundColor = [UIColor clearColor];
		[_card addSubview:name];

		if (i > 0){
			UIView *hair = [[UIView alloc] initWithFrame:CGRectMake(
					kSide, y - 0.5f, inner, 0.5f)];
			hair.backgroundColor = [theme separatorColour];
			[_card addSubview:hair];
		}

		// The value hugs the right edge; its width is whatever the text needs.
		CGFloat right = width - kSide;
		if (i == 1){
			[self addRightLabel:TGGiftStamp(gift[@"date"])
							 at:CGPointMake(right, y + kRow / 2)
						   bold:NO
						 colour:[theme primaryTextColour]];
		} else if (i == 2){
			UIFont *font = TGFontBodyStrong();
			NSString *count = [NSString stringWithFormat:@"%ld", (long)stars];
			CGFloat countW = ceilf(TGGiftTextSize(count, font).width);
			[self addRightLabel:count
							 at:CGPointMake(right, y + kRow / 2)
						   bold:YES
						 colour:[theme primaryTextColour]];
			// Telegram Stars are gold wherever they appear, theme or not.
			UIImageView *star = [[UIImageView alloc] initWithFrame:CGRectMake(
					right - countW - 4 - kStar, y + (kRow - kStar) / 2,
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
			rightCentre.x - w, rightCentre.y - 10, w, 20)];
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
	CGFloat available = right - kSide - 100 - kAvatar - 6;
	CGFloat nameW = MIN(ceilf(TGGiftTextSize(name, font).width) + 1, available);
	UILabel *label = [[UILabel alloc] initWithFrame:CGRectMake(
			right - nameW, y + kRow / 2 - 10, nameW, 20)];
	label.text = name;
	label.font = font;
	label.textColor = [[TGTheme shared] accentColour];
	label.textAlignment = NSTextAlignmentRight;
	label.lineBreakMode = NSLineBreakByTruncatingTail;
	label.backgroundColor = [UIColor clearColor];
	[_card addSubview:label];

	UIImageView *face = [[UIImageView alloc] initWithFrame:CGRectMake(
			right - nameW - 6 - kAvatar, y + (kRow - kAvatar) / 2,
			kAvatar, kAvatar)];
	face.layer.cornerRadius = kAvatar / 2;
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
