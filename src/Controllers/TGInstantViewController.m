#import "TGInstantViewController.h"
#import "TGTheme.h"
#import "TGStyle.h"

static NSString *const TGInstantIndent = @"    ";
static NSString *const TGInstantRule = @"────────────────";

/// Rich text is a tree of wrappers around plain runs. The reader wants the
/// words; the formatting is already what the surrounding block's font says.
static NSString *TGInstantRichText(NSDictionary *text) {
	if (![text isKindOfClass:NSDictionary.class])
		return @"";
	NSString *type = text[@"@type"] ?: @"";
	if ([type isEqualToString:@"richTextPlain"])
		return text[@"text"] ?: @"";
	if ([type isEqualToString:@"richTexts"]){
		NSMutableString *out = [NSMutableString string];
		for (NSDictionary *part in text[@"texts"])
			[out appendString:TGInstantRichText(part)];
		return out;
	}
	if ([type isEqualToString:@"richTextCustomEmoji"])
		return text[@"alternative_text"] ?: @"";
	if ([type isEqualToString:@"richTextIcon"])
		return @"";
	if ([type isEqualToString:@"richTextAnchor"])
		return @"";
	if ([type isEqualToString:@"richTextButton"])
		return TGInstantRichText(text[@"button"][@"text"]);
	// Every other node is a wrapper whose `text` is the content.
	if (text[@"text"])
		return TGInstantRichText(text[@"text"]);
	if (text[@"url"])
		return text[@"url"];
	return @"";
}

static NSString *TGInstantCaption(NSDictionary *caption) {
	NSString *text = TGInstantRichText(caption[@"text"]);
	NSString *credit = TGInstantRichText(caption[@"credit"]);
	if (credit.length)
		return text.length ? [NSString stringWithFormat:@"%@ — %@", text, credit] : credit;
	return text;
}

static void TGInstantAppendBlocks(NSMutableString *out, NSArray *blocks, NSString *indent);

static void TGInstantAppendBlock(NSMutableString *out, NSDictionary *block, NSString *indent) {
	if (![block isKindOfClass:NSDictionary.class])
		return;
	NSString *type = block[@"@type"] ?: @"";
	NSString *line = nil;

	if ([type isEqualToString:@"pageBlockTitle"])
		line = [@"# " stringByAppendingString:TGInstantRichText(block[@"title"])];
	else if ([type isEqualToString:@"pageBlockSubtitle"])
		line = TGInstantRichText(block[@"subtitle"]);
	else if ([type isEqualToString:@"pageBlockHeader"])
		line = [@"## " stringByAppendingString:TGInstantRichText(block[@"header"])];
	else if ([type isEqualToString:@"pageBlockSubheader"])
		line = [@"### " stringByAppendingString:TGInstantRichText(block[@"subheader"])];
	else if ([type isEqualToString:@"pageBlockSectionHeading"])
		line = TGInstantRichText(block[@"text"]);
	else if ([type isEqualToString:@"pageBlockKicker"])
		line = TGInstantRichText(block[@"kicker"]).uppercaseString;
	else if ([type isEqualToString:@"pageBlockParagraph"])
		line = TGInstantRichText(block[@"text"]);
	else if ([type isEqualToString:@"pageBlockPreformatted"])
		line = TGInstantRichText(block[@"text"]);
	else if ([type isEqualToString:@"pageBlockFooter"] || [type isEqualToString:@"pageBlockThinking"])
		line = TGInstantRichText(block[@"footer"] ?: block[@"text"]);
	else if ([type isEqualToString:@"pageBlockDivider"])
		line = TGInstantRule;
	else if ([type isEqualToString:@"pageBlockAuthorDate"]){
		NSString *author = TGInstantRichText(block[@"author"]);
		NSNumber *date = [block[@"publish_date"] isKindOfClass:NSNumber.class]
				? block[@"publish_date"] : nil;
		if (date.integerValue > 0){
			NSDateFormatter *formatter = [[NSDateFormatter alloc] init];
			formatter.dateStyle = NSDateFormatterMediumStyle;
			formatter.timeStyle = NSDateFormatterNoStyle;
			NSString *when = [formatter stringFromDate:
					[NSDate dateWithTimeIntervalSince1970:date.doubleValue]];
			line = author.length ? [NSString stringWithFormat:@"%@ · %@", author, when] : when;
		} else {
			line = author;
		}
	}
	else if ([type isEqualToString:@"pageBlockPullQuote"] ||
			 [type isEqualToString:@"pageBlockExpandableBlockQuote"])
		line = [@"> " stringByAppendingString:TGInstantRichText(block[@"text"])];
	else if ([type isEqualToString:@"pageBlockBlockQuote"]){
		[out appendFormat:@"\n%@> ", indent];
		TGInstantAppendBlocks(out, block[@"blocks"], [indent stringByAppendingString:@"> "]);
		NSString *credit = TGInstantRichText(block[@"credit"]);
		if (credit.length)
			[out appendFormat:@"\n%@> — %@", indent, credit];
		[out appendString:@"\n"];
		return;
	}
	else if ([type isEqualToString:@"pageBlockList"]){
		for (NSDictionary *item in block[@"items"]){
			NSString *label = item[@"label"] ?: @"•";
			[out appendFormat:@"\n%@%@ ", indent, label];
			TGInstantAppendBlocks(out, item[@"blocks"], [indent stringByAppendingString:TGInstantIndent]);
		}
		return;
	}
	else if ([type isEqualToString:@"pageBlockDetails"]){
		line = TGInstantRichText(block[@"header"]);
		if (line.length)
			[out appendFormat:@"\n%@%@", indent, line];
		TGInstantAppendBlocks(out, block[@"blocks"], [indent stringByAppendingString:TGInstantIndent]);
		return;
	}
	else if ([type isEqualToString:@"pageBlockCollage"] ||
			 [type isEqualToString:@"pageBlockSlideshow"]){
		TGInstantAppendBlocks(out, block[@"blocks"], indent);
		line = TGInstantCaption(block[@"caption"]);
	}
	else if ([type isEqualToString:@"pageBlockPhoto"] ||
			 [type isEqualToString:@"pageBlockVideo"] ||
			 [type isEqualToString:@"pageBlockAnimation"] ||
			 [type isEqualToString:@"pageBlockAudio"] ||
			 [type isEqualToString:@"pageBlockVoiceNote"] ||
			 [type isEqualToString:@"pageBlockDocument"])
		line = TGInstantCaption(block[@"caption"]);
	else if ([type isEqualToString:@"pageBlockCover"]){
		TGInstantAppendBlock(out, block[@"cover"], indent);
		return;
	}
	else if ([type isEqualToString:@"pageBlockEmbedded"] ||
			 [type isEqualToString:@"pageBlockEmbeddedPost"]){
		NSString *url = block[@"url"];
		line = TGInstantCaption(block[@"caption"]);
		if (!line.length)
			line = url;
		if ([type isEqualToString:@"pageBlockEmbeddedPost"])
			TGInstantAppendBlocks(out, block[@"blocks"], indent);
	}
	else if ([type isEqualToString:@"pageBlockTable"]){
		NSMutableArray *rows = [NSMutableArray array];
		for (NSArray *row in block[@"cells"]){
			NSMutableArray *cells = [NSMutableArray array];
			for (NSDictionary *cell in row)
				[cells addObject:TGInstantRichText(cell[@"text"])];
			[rows addObject:[cells componentsJoinedByString:@" | "]];
		}
		line = [rows componentsJoinedByString:@"\n"];
	}
	else if ([type isEqualToString:@"pageBlockRelatedArticles"]){
		line = TGInstantRichText(block[@"header"]);
		for (NSDictionary *article in block[@"articles"]){
			NSString *title = article[@"title"] ?: article[@"url"] ?: @"";
			[out appendFormat:@"\n%@• %@", indent, title];
		}
	}
	else if ([type isEqualToString:@"pageBlockChatLink"]){
		line = block[@"title"] ?: block[@"username"];
	}
	else if ([type isEqualToString:@"pageBlockAnchor"] ||
			 [type isEqualToString:@"pageBlockUnsupported"] ||
			 [type isEqualToString:@"pageBlockMathematicalExpression"]){
		return;
	}

	if (line.length)
		[out appendFormat:@"\n%@%@\n", indent, line];
}

static void TGInstantAppendBlocks(NSMutableString *out, NSArray *blocks, NSString *indent) {
	for (NSDictionary *block in blocks)
		TGInstantAppendBlock(out, block, indent);
}

@implementation TGInstantViewController

- (void)viewDidLoad {
	[super viewDidLoad];

	TGTheme *theme = [TGTheme shared];
	self.view.backgroundColor = [theme listBackgroundColour];
	self.title = self.pageTitle.length ? self.pageTitle : @"Instant View";

	UITextView *reader = [[UITextView alloc] initWithFrame:self.view.bounds];
	reader.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
	reader.editable = NO;
	reader.selectable = YES;
	reader.backgroundColor = [theme listBackgroundColour];
	reader.textColor = [theme primaryTextColour];
	reader.font = TGFontBody();
	reader.contentInset = UIEdgeInsetsMake(TGMetricPadLarge, TGMetricPadLarge,
										   TGMetricPadLarge, TGMetricPadLarge);
	reader.scrollIndicatorInsets = reader.contentInset;

	NSMutableString *text = [NSMutableString string];
	TGInstantAppendBlocks(text, self.blocks, @"");
	if (!text.length)
		[text appendString:@"Telegram returned an empty page."];
	if (self.sourceURL.length)
		[text appendFormat:@"\n\n%@", self.sourceURL];
	reader.text = text;
	[self.view addSubview:reader];
}

@end
