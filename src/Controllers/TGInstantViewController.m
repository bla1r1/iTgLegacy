#import "TGInstantViewController.h"
#import "TGAlertSheet.h"
#import "TGTheme.h"
#import "TGStyle.h"

static NSString *const TGInstantRule = @"────────────────────────────────";

/// Rich text is a tree of wrappers around plain runs. This builder keeps the
/// wrappers that change how a word looks - bold, italic, code, a link - and
/// drops the ones that only exist for the web layout.
static NSAttributedString *TGInstantRichText(NSDictionary *text,
											 UIFont *font,
											 UIColor *colour,
											 UIColor *linkColour);

static NSAttributedString *TGInstantPlain(NSString *string, UIFont *font,
										  UIColor *colour) {
	if (!string.length)
		return [[NSAttributedString alloc] initWithString:@""];
	return [[NSAttributedString alloc] initWithString:string
			attributes:@{NSFontAttributeName : font,
						 NSForegroundColorAttributeName : colour}];
}

static NSAttributedString *TGInstantRichText(NSDictionary *text,
											 UIFont *font,
											 UIColor *colour,
											 UIColor *linkColour) {
	if (![text isKindOfClass:NSDictionary.class])
		return TGInstantPlain(@"", font, colour);
	NSString *type = text[@"@type"] ?: @"";
	if ([type isEqualToString:@"richTextPlain"])
		return TGInstantPlain(text[@"text"] ?: @"", font, colour);
	if ([type isEqualToString:@"richTexts"]) {
		NSMutableAttributedString *out = [[NSMutableAttributedString alloc] init];
		for (NSDictionary *part in text[@"texts"])
			[out appendAttributedString:TGInstantRichText(part, font, colour, linkColour)];
		return out;
	}
	if ([type isEqualToString:@"richTextBold"])
		return TGInstantRichText(text[@"text"], TGFontBoldAtSize(font.pointSize),
				colour, linkColour);
	if ([type isEqualToString:@"richTextItalic"])
		return TGInstantRichText(text[@"text"], TGFontItalicAtSize(font.pointSize),
				colour, linkColour);
	if ([type isEqualToString:@"richTextUnderline"] ||
			[type isEqualToString:@"richTextStrikethrough"]) {
		NSMutableAttributedString *out = [TGInstantRichText(text[@"text"], font,
				colour, linkColour) mutableCopy];
		NSInteger style = [type isEqualToString:@"richTextUnderline"]
				? NSUnderlineStyleSingle : NSUnderlineStyleSingle;
		NSString *key = [type isEqualToString:@"richTextUnderline"]
				? NSUnderlineStyleAttributeName : NSStrikethroughStyleAttributeName;
		[out addAttribute:key value:@(style) range:NSMakeRange(0, out.length)];
		return out;
	}
	if ([type isEqualToString:@"richTextCode"])
		return TGInstantRichText(text[@"text"],
				TGFontCodeAtSize(TGFontSizeMicro), colour, linkColour);
	if ([type isEqualToString:@"richTextUrl"]) {
		NSMutableAttributedString *out = [TGInstantRichText(text[@"text"], font,
				linkColour, linkColour) mutableCopy];
		[out addAttribute:NSUnderlineStyleAttributeName
					value:@(NSUnderlineStyleSingle)
					range:NSMakeRange(0, out.length)];
		return out;
	}
	if ([type isEqualToString:@"richTextCustomEmoji"])
		return TGInstantPlain(text[@"alternative_text"] ?: @"", font, colour);
	if ([type isEqualToString:@"richTextIcon"] || [type isEqualToString:@"richTextAnchor"])
		return TGInstantPlain(@"", font, colour);
	if ([type isEqualToString:@"richTextButton"])
		return TGInstantRichText(text[@"button"][@"text"], font, linkColour, linkColour);
	if ([type isEqualToString:@"richTextEmailAddress"] ||
			[type isEqualToString:@"richTextPhoneNumber"] ||
			[type isEqualToString:@"richTextMention"] ||
			[type isEqualToString:@"richTextHashtag"] ||
			[type isEqualToString:@"richTextCashtag"] ||
			[type isEqualToString:@"richTextBankCard"] ||
			[type isEqualToString:@"richTextAnchorLink"] ||
			[type isEqualToString:@"richTextMarked"] ||
			[type isEqualToString:@"richTextSubscript"] ||
			[type isEqualToString:@"richTextSuperscript"])
		return TGInstantRichText(text[@"text"], font, colour, linkColour);
	// Every other node is a wrapper whose `text` is the content.
	if (text[@"text"])
		return TGInstantRichText(text[@"text"], font, colour, linkColour);
	if (text[@"url"])
		return TGInstantPlain(text[@"url"], font, colour);
	return TGInstantPlain(@"", font, colour);
}

static NSAttributedString *TGInstantCaption(NSDictionary *caption,
											UIColor *colour) {
	NSMutableAttributedString *out = [[NSMutableAttributedString alloc] init];
	NSAttributedString *text = TGInstantRichText(caption[@"text"],
			TGFontCaption(), colour, [[TGTheme shared] accentColour]);
	[out appendAttributedString:text];
	NSAttributedString *credit = TGInstantRichText(caption[@"credit"],
			TGFontCaption(), [[TGTheme shared] secondaryTextColour],
			[[TGTheme shared] accentColour]);
	if (credit.length) {
		[out appendAttributedString:TGInstantPlain(@" — ", TGFontCaption(), colour)];
		[out appendAttributedString:credit];
	}
	return out;
}

static void TGInstantAppend(NSMutableAttributedString *out,
							NSAttributedString *text,
							CGFloat indent,
							CGFloat before,
							CGFloat after) {
	if (!text.length)
		return;
	NSMutableAttributedString *piece = [text mutableCopy];
	NSMutableParagraphStyle *style = [[NSMutableParagraphStyle alloc] init];
	style.firstLineHeadIndent = indent;
	style.headIndent = indent;
	style.paragraphSpacingBefore = before;
	style.paragraphSpacing = after;
	style.lineSpacing = TGMetricPadTiny;
	[piece addAttribute:NSParagraphStyleAttributeName
				  value:style
				  range:NSMakeRange(0, piece.length)];
	[out appendAttributedString:piece];
	NSMutableAttributedString *ending = [[NSMutableAttributedString alloc]
			initWithString:@"\n" attributes:@{
				NSFontAttributeName : TGFontBody(),
				NSForegroundColorAttributeName : [UIColor clearColor],
				NSParagraphStyleAttributeName : style,
			}];
	[out appendAttributedString:ending];
}

static void TGInstantAppendBlocks(NSMutableAttributedString *out,
								  NSArray *blocks,
								  CGFloat indent,
								  TGTheme *theme);

static void TGInstantAppendBlock(NSMutableAttributedString *out,
								 NSDictionary *block,
								 CGFloat indent,
								 TGTheme *theme) {
	if (![block isKindOfClass:NSDictionary.class])
		return;
	NSString *type = block[@"@type"] ?: @"";
	UIColor *primary = [theme primaryTextColour];
	UIColor *secondary = [theme secondaryTextColour];
	UIColor *accent = [theme accentColour];

	if ([type isEqualToString:@"pageBlockTitle"]) {
		TGInstantAppend(out, TGInstantRichText(block[@"title"], TGFontTitle(),
				primary, accent), indent, TGMetricPadLarge, TGMetricPad);
		return;
	}
	if ([type isEqualToString:@"pageBlockSubtitle"]) {
		TGInstantAppend(out, TGInstantRichText(block[@"subtitle"], TGFontBody(),
				secondary, accent), indent, TGMetricZero, TGMetricPadMedium);
		return;
	}
	if ([type isEqualToString:@"pageBlockHeader"]) {
		TGInstantAppend(out, TGInstantRichText(block[@"header"], TGFontHeader(),
				primary, accent), indent, TGMetricPadLarge, TGMetricPadSmall);
		return;
	}
	if ([type isEqualToString:@"pageBlockSubheader"] ||
			[type isEqualToString:@"pageBlockSectionHeading"]) {
		NSDictionary *text = block[@"subheader"] ? block[@"subheader"] : block[@"text"];
		TGInstantAppend(out, TGInstantRichText(text, TGFontRowStrong(), primary,
				accent), indent, TGMetricPadMedium, TGMetricPadSmall);
		return;
	}
	if ([type isEqualToString:@"pageBlockKicker"]) {
		NSAttributedString *kicker = TGInstantRichText(block[@"kicker"],
				TGFontMetaStrong(), secondary, accent);
		NSMutableAttributedString *upper = [kicker mutableCopy];
		NSString *string = [[upper string] uppercaseString];
		[upper replaceCharactersInRange:NSMakeRange(0, upper.length) withString:string];
		TGInstantAppend(out, upper, indent, TGMetricPad, TGMetricPadTiny);
		return;
	}
	if ([type isEqualToString:@"pageBlockParagraph"] ||
			[type isEqualToString:@"pageBlockThinking"]) {
		TGInstantAppend(out, TGInstantRichText(block[@"text"], TGFontBody(),
				primary, accent), indent, TGMetricZero, TGMetricPadMedium);
		return;
	}
	if ([type isEqualToString:@"pageBlockPreformatted"]) {
		TGInstantAppend(out, TGInstantRichText(block[@"text"],
				TGFontCodeAtSize(TGFontSizeMicro), primary, accent),
				indent + TGMetricPadLarge, TGMetricPadSmall, TGMetricPadMedium);
		return;
	}
	if ([type isEqualToString:@"pageBlockFooter"]) {
		TGInstantAppend(out, TGInstantRichText(block[@"footer"], TGFontCaption(),
				secondary, accent), indent, TGMetricPadMedium, TGMetricPadMedium);
		return;
	}
	if ([type isEqualToString:@"pageBlockDivider"]) {
		TGInstantAppend(out, TGInstantPlain(TGInstantRule, TGFontCaption(), secondary),
				indent, TGMetricPadMedium, TGMetricPadMedium);
		return;
	}
	if ([type isEqualToString:@"pageBlockAuthorDate"]) {
		NSMutableAttributedString *line = [[NSMutableAttributedString alloc] init];
		[line appendAttributedString:TGInstantRichText(block[@"author"],
				TGFontCaption(), secondary, accent)];
		NSNumber *date = [block[@"publish_date"] isKindOfClass:NSNumber.class]
				? block[@"publish_date"] : nil;
		if (date.integerValue > 0) {
			NSDateFormatter *formatter = [[NSDateFormatter alloc] init];
			formatter.dateStyle = NSDateFormatterMediumStyle;
			formatter.timeStyle = NSDateFormatterNoStyle;
			NSString *when = [formatter stringFromDate:
					[NSDate dateWithTimeIntervalSince1970:date.doubleValue]];
			if (when.length) {
				if (line.length)
					[line appendAttributedString:TGInstantPlain(@" · ",
							TGFontCaption(), secondary)];
				[line appendAttributedString:TGInstantPlain(when,
						TGFontCaption(), secondary)];
			}
		}
		TGInstantAppend(out, line, indent, TGMetricPadSmall, TGMetricPadLarge);
		return;
	}
	if ([type isEqualToString:@"pageBlockPullQuote"] ||
			[type isEqualToString:@"pageBlockExpandableBlockQuote"]) {
		NSMutableAttributedString *quote = [[NSMutableAttributedString alloc] init];
		[quote appendAttributedString:TGInstantPlain(@"“", TGFontBody(), secondary)];
		[quote appendAttributedString:TGInstantRichText(block[@"text"],
				TGFontItalicAtSize(TGFontBody().pointSize), primary, accent)];
		[quote appendAttributedString:TGInstantPlain(@"”", TGFontBody(), secondary)];
		TGInstantAppend(out, quote, indent + TGMetricPadLarge,
				TGMetricPadMedium, TGMetricPadMedium);
		return;
	}
	if ([type isEqualToString:@"pageBlockBlockQuote"]) {
		TGInstantAppend(out, TGInstantPlain(@"“", TGFontBody(), secondary),
				indent + TGMetricPadLarge, TGMetricPadMedium, TGMetricZero);
		TGInstantAppendBlocks(out, block[@"blocks"], indent + TGMetricPadLarge, theme);
		NSAttributedString *credit = TGInstantRichText(block[@"credit"],
				TGFontCaption(), secondary, accent);
		if (credit.length) {
			NSMutableAttributedString *line = [NSMutableAttributedString new];
			[line appendAttributedString:TGInstantPlain(@"— ", TGFontCaption(), secondary)];
			[line appendAttributedString:credit];
			TGInstantAppend(out, line, indent + TGMetricPadLarge,
					TGMetricZero, TGMetricPadMedium);
		}
		return;
	}
	if ([type isEqualToString:@"pageBlockList"]) {
		for (NSDictionary *item in block[@"items"]) {
			NSString *label = item[@"label"];
			if (!label.length)
				label = @"•";
			NSMutableAttributedString *lead = [[NSMutableAttributedString alloc]
					initWithAttributedString:TGInstantPlain(
							[NSString stringWithFormat:@"%@  ", label],
							TGFontBody(), secondary)];
			[out appendAttributedString:lead];
			NSMutableAttributedString *itemText = [[NSMutableAttributedString alloc] init];
			TGInstantAppendBlocks(itemText, item[@"blocks"], TGMetricZero, theme);
			TGInstantAppend(out, itemText, indent + TGMetricPadLarge,
					TGMetricZero, TGMetricPadSmall);
		}
		return;
	}
	if ([type isEqualToString:@"pageBlockDetails"]) {
		TGInstantAppend(out, TGInstantRichText(block[@"header"], TGFontBodyStrong(),
				primary, accent), indent, TGMetricPadMedium, TGMetricPadSmall);
		TGInstantAppendBlocks(out, block[@"blocks"], indent + TGMetricPadLarge, theme);
		return;
	}
	if ([type isEqualToString:@"pageBlockCollage"] ||
			[type isEqualToString:@"pageBlockSlideshow"]) {
		TGInstantAppendBlocks(out, block[@"blocks"], indent, theme);
		NSAttributedString *caption = TGInstantCaption(block[@"caption"], secondary);
		if (caption.length)
			TGInstantAppend(out, caption, indent, TGMetricZero, TGMetricPadMedium);
		return;
	}
	if ([type isEqualToString:@"pageBlockPhoto"] ||
			[type isEqualToString:@"pageBlockVideo"] ||
			[type isEqualToString:@"pageBlockAnimation"] ||
			[type isEqualToString:@"pageBlockAudio"] ||
			[type isEqualToString:@"pageBlockVoiceNote"] ||
			[type isEqualToString:@"pageBlockDocument"]) {
		NSString *name = @"Photo";
		if ([type isEqualToString:@"pageBlockVideo"])
			name = @"Video";
		else if ([type isEqualToString:@"pageBlockAnimation"])
			name = @"Animation";
		else if ([type isEqualToString:@"pageBlockAudio"])
			name = @"Audio";
		else if ([type isEqualToString:@"pageBlockVoiceNote"])
			name = @"Voice message";
		else if ([type isEqualToString:@"pageBlockDocument"])
			name = @"Document";
		NSAttributedString *caption = TGInstantCaption(block[@"caption"], secondary);
		NSMutableAttributedString *line = [[NSMutableAttributedString alloc] init];
		[line appendAttributedString:TGInstantPlain(name, TGFontCaption(), secondary)];
		if (caption.length) {
			[line appendAttributedString:TGInstantPlain(@" — ", TGFontCaption(), secondary)];
			[line appendAttributedString:caption];
		}
		TGInstantAppend(out, line, indent, TGMetricPadSmall, TGMetricPadMedium);
		return;
	}
	if ([type isEqualToString:@"pageBlockCover"]) {
		TGInstantAppendBlock(out, block[@"cover"], indent, theme);
		return;
	}
	if ([type isEqualToString:@"pageBlockEmbedded"] ||
			[type isEqualToString:@"pageBlockEmbeddedPost"]) {
		NSAttributedString *caption = TGInstantCaption(block[@"caption"], secondary);
		NSString *url = block[@"url"];
		if (!caption.length)
			caption = TGInstantPlain(url ?: @"Embedded content", TGFontCaption(), secondary);
		TGInstantAppend(out, caption, indent, TGMetricPadSmall, TGMetricPadMedium);
		if ([type isEqualToString:@"pageBlockEmbeddedPost"])
			TGInstantAppendBlocks(out, block[@"blocks"], indent + TGMetricPadLarge, theme);
		return;
	}
	if ([type isEqualToString:@"pageBlockTable"]) {
		for (NSArray *row in block[@"cells"]) {
			NSMutableArray *cells = [NSMutableArray array];
			for (NSDictionary *cell in row) {
				NSAttributedString *plain = TGInstantRichText(cell[@"text"],
						TGFontCaption(), primary, accent);
				[cells addObject:plain.string ?: @""];
			}
			NSString *line = [cells componentsJoinedByString:@"  |  "];
			TGInstantAppend(out, TGInstantPlain(line, TGFontCaption(), primary),
					indent, TGMetricPadTiny, TGMetricPadTiny);
		}
		return;
	}
	if ([type isEqualToString:@"pageBlockRelatedArticles"]) {
		TGInstantAppend(out, TGInstantRichText(block[@"header"], TGFontBodyStrong(),
				primary, accent), indent, TGMetricPadMedium, TGMetricPadSmall);
		for (NSDictionary *article in block[@"articles"]) {
			NSString *title = article[@"title"] ?: article[@"url"] ?: @"";
			TGInstantAppend(out, TGInstantPlain(
					[NSString stringWithFormat:@"•  %@", title],
					TGFontBody(), primary),
					indent + TGMetricPadLarge, TGMetricZero, TGMetricPadSmall);
		}
		return;
	}
	if ([type isEqualToString:@"pageBlockChatLink"]) {
		TGInstantAppend(out, TGInstantPlain(block[@"title"] ?: block[@"username"] ?: @"",
				TGFontBodyStrong(), accent), indent, TGMetricPadSmall, TGMetricPadMedium);
		return;
	}
	// Anchors and markup the reader has no use for are simply absent.
	if ([type isEqualToString:@"pageBlockAnchor"] ||
			[type isEqualToString:@"pageBlockUnsupported"] ||
			[type isEqualToString:@"pageBlockMathematicalExpression"])
		return;
}

static void TGInstantAppendBlocks(NSMutableAttributedString *out,
								  NSArray *blocks,
								  CGFloat indent,
								  TGTheme *theme) {
	for (NSDictionary *block in blocks)
		TGInstantAppendBlock(out, block, indent, theme);
}

@implementation TGInstantViewController

- (void)viewDidLoad {
	[super viewDidLoad];

	TGTheme *theme = [TGTheme shared];
	self.view.backgroundColor = [theme listBackgroundColour];
	self.title = self.pageTitle.length ? self.pageTitle : @"Instant View";

	// Telegram's reader keeps its actions in the bar: open the original,
	// copy the address, or pass it on.
	self.navigationItem.rightBarButtonItem = [[UIBarButtonItem alloc]
			initWithTitle:@"Action" style:UIBarButtonItemStylePlain
				   target:self action:@selector(showActions)];

	UITextView *reader = [[UITextView alloc] initWithFrame:self.view.bounds];
	reader.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
	reader.editable = NO;
	reader.selectable = YES;
	reader.backgroundColor = [theme listBackgroundColour];
	reader.textColor = [theme primaryTextColour];
	reader.font = TGFontBody();
	reader.dataDetectorTypes = UIDataDetectorTypeLink;
	reader.contentInset = UIEdgeInsetsMake(TGMetricPadLarge, TGMetricPadLarge,
										   TGMetricPadLarge, TGMetricPadLarge);
	reader.scrollIndicatorInsets = reader.contentInset;

	NSMutableAttributedString *text = [[NSMutableAttributedString alloc] init];
	TGInstantAppendBlocks(text, self.blocks, TGMetricZero, theme);
	if (!self.blocks.count) {
		[text appendAttributedString:TGInstantPlain(
				@"Telegram returned an empty page.", TGFontBody(),
				[theme secondaryTextColour])];
	}
	if (self.sourceURL.length) {
		[text appendAttributedString:TGInstantPlain(@"\n", TGFontBody(),
				[theme secondaryTextColour])];
		[text appendAttributedString:TGInstantPlain(self.sourceURL,
				TGFontCaption(), [theme accentColour])];
	}
	reader.attributedText = text;
	[self.view addSubview:reader];
	[self applyThemeToReader:reader];
}

- (void)applyThemeToReader:(UITextView *)reader {
	reader.backgroundColor = [[TGTheme shared] listBackgroundColour];
	reader.textColor = [[TGTheme shared] primaryTextColour];
}

- (void)showActions {
	NSMutableArray *choices = [NSMutableArray arrayWithObject:@"Open in Browser"];
	if (self.sourceURL.length)
		[choices addObject:@"Copy Link"];
	if (self.sourceURL.length)
		[choices addObject:@"Share"];
	__weak typeof(self) weakSelf = self;
	[TGAlertSheet showChoices:choices
						title:self.pageTitle ?: @"Instant View"
			 destructiveIndex:-1
					   inView:self.view
					 onChoice:^(NSInteger index){
		TGInstantViewController *me = weakSelf;
		if (!me)
			return;
		if (index == 0) {
			NSURL *url = [NSURL URLWithString:me.sourceURL ?: @""];
			if (!url || ![[UIApplication sharedApplication] canOpenURL:url]) {
				[TGAlertSheet showMessage:@"There is no address for this page."
									  title:@"Instant View" inView:me.view];
				return;
			}
			[[UIApplication sharedApplication] openURL:url];
			return;
		}
		if (index == 1) {
			[UIPasteboard generalPasteboard].string = me.sourceURL;
			[TGAlertSheet showMessage:@"The address is on the clipboard."
								  title:@"Link Copied" inView:me.view];
			return;
		}
		NSURL *url = [NSURL URLWithString:me.sourceURL ?: @""];
		if (!url)
			return;
		UIActivityViewController *share = [[UIActivityViewController alloc]
				initWithActivityItems:@[url] applicationActivities:nil];
		if ([share respondsToSelector:@selector(popoverPresentationController)]) {
			share.popoverPresentationController.sourceView = me.view;
			share.popoverPresentationController.sourceRect = me.view.bounds;
		}
		[me presentViewController:share animated:YES completion:nil];
	}];
}

@end
