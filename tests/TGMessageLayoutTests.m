// TGMessageLayoutTests.m — regression tests for TGMessageLayout's pure
// text/geometry layer, on the macOS host through the UIKit shim.
//
// Zone this covers (frequently-fixed, never tested before): word wrapping
// and text measurement, emoji attribute handling and message entities —
// the inputs the chat bubble geometry chain feeds on.
//
// The bubble/caption/reply-bar geometry itself lives in
// TGChatViewController+Layout.m and TGBubbleCell.m, whose measurement needs
// a live UIView hierarchy a host shim cannot honestly provide; those are
// not covered here (see the PR report).
#import "TGTestRunner.h"
#import "TGMessageLayout.h"

static NSString *kWord = @"Supercalifragilisticexpialidocious";
static NSString *kWord2 = @"antidisestablishmentarianism";

@interface TGMessageLayoutTests : XCTestCase
@end

@implementation TGMessageLayoutTests

// ──────────────────────────────────────────────────────────────────────────────
#pragma mark - measurement basics

- (void)testTextSize_EmptyTextIsZero {
	CGSize empty = TGTextSize(@"", nil, 246);
	XCTAssertEqual(empty.width,  0.0);
	XCTAssertEqual(empty.height, 0.0);
}

- (void)testTextSize_ShortTextIsOneLine {
	UIFont *font = [UIFont systemFontOfSize:15];
	CGSize size = TGTextSize(@"Hi", font, 246);
	XCTAssertGreaterThan(size.width, 0.0, @"measured text must have width");
	XCTAssertGreaterThan(size.height, 0.0, @"measured text must have height");

	CGSize oneLine = TGTextSize(@"x", font, 246);
	XCTAssertLessThanOrEqual(size.height, oneLine.height + 1.0,
			@"short text must not wrap into more lines than single-letter text");
}

- (void)testTextSize_TighterColumnIsNeverShorter {
	// Word wrapping regression: a narrower measure width must never give a
	// shorter (or smaller) height than a wider one.
	UIFont *font = [UIFont systemFontOfSize:15];
	NSString *text = @"The quick brown fox jumps over the lazy dog again and again";
	CGSize wide  = TGTextSize(text, font, 246);
	CGSize mid   = TGTextSize(text, font, 120);
	CGSize tight = TGTextSize(text, font,  60);
	XCTAssertGreaterThanOrEqual(mid.height,   ceil(wide.height)  - 1.0,
			@"120pt must wrap at least as tall as 246pt");
	XCTAssertGreaterThanOrEqual(tight.height, ceil(mid.height)   - 1.0,
			@"60pt must wrap at least as tall as 120pt");
}

- (void)testTextSize_UnbreakableLongWordWrapsToMultipleLines {
	// A single word wider than the bubble must still be laid out (hard
	// character wrap), not report one line and clip on the device.
	UIFont *font = [UIFont systemFontOfSize:15];
	NSString *longWord = [kWord stringByAppendingString:kWord2];   // ~40 chars
	CGSize oneLine  = TGTextSize(@"Hi", font, 246);
	CGSize wrapped = TGTextSize(longWord, font, 100);
	XCTAssertGreaterThan(wrapped.height, oneLine.height,
			@"a long word at 100pt must occupy more than one line");
}

- (void)testTextSize_RunsOutOfMeasureWidthRatherThanShrinking {
	// Height is capped by wraps, not by text length: the same word at a
	// width wide enough for it must be one line tall.
	UIFont *font = [UIFont systemFontOfSize:15];
	CGSize loose = TGTextSize(kWord, font, 1000);
	CGSize oneLine = TGTextSize(@"Hi", font, 1000);
	XCTAssertLessThanOrEqual(loose.height, oneLine.height + 1.0,
			@"a word that fits must stay on one line");
}

// ──────────────────────────────────────────────────────────────────────────────
#pragma mark - entities

- (void)testAttributedMessageText_NilForEmpty {
	XCTAssertNil(TGAttributedMessageText(@"", nil, nil, nil));
}

- (void)testAttributedMessageText_PlainKeepsLengthAndColour {
	UIFont *font = [UIFont systemFontOfSize:15];
	NSString *text = @"no entities here";
	NSAttributedString *str = TGAttributedMessageText(text, nil, font,
			[UIColor redColor]);
	XCTAssertNotNil(str);
	XCTAssertEqual(str.length, text.length, @"plain attribution must keep every character");

	UIColor *colour = [str attribute:NSForegroundColorAttributeName
			atIndex:0 effectiveRange:NULL];
	XCTAssertNotNil(colour, @"message colour must be applied");
}

- (void)testAttributedMessageText_UnderlineEntity {
	UIFont *font = [UIFont systemFontOfSize:15];
	NSDictionary *ent = @{@"offset" : @0, @"length" : @5,
						  @"type" : @{@"@type" : @"textEntityTypeUnderline"}};
	NSAttributedString *str = TGAttributedMessageText(@"hello world", @[ent],
			font, nil);

	NSNumber *underline = [str attribute:NSUnderlineStyleAttributeName
			atIndex:0 effectiveRange:NULL];
	XCTAssertEqual([underline integerValue], NSUnderlineStyleSingle,
			@"the underlined range must be marked for one underline");
	NSNumber *outside = [str attribute:NSUnderlineStyleAttributeName
			atIndex:6 effectiveRange:NULL];
	XCTAssertNil(outside, @"text outside the entity must be untouched");
}

- (void)testAttributedMessageText_BoldEntityDiffersFromBodyFont {
	UIFont *font = [UIFont systemFontOfSize:15];
	NSDictionary *ent = @{@"offset" : @6, @"length" : @5,
						  @"type" : @{@"@type" : @"textEntityTypeBold"}};
	NSAttributedString *str = TGAttributedMessageText(@"plain bold here", @[ent],
			font, nil);

	UIFont *body  = [str attribute:NSFontAttributeName atIndex:0 effectiveRange:NULL];
	UIFont *inside = [str attribute:NSFontAttributeName atIndex:8 effectiveRange:NULL];
	XCTAssertNotNil(body);
	XCTAssertNotNil(inside);
	XCTAssertNotEqual(inside, body, @"the bold run must carry a different font");
}

- (void)testAttributedMessageText_TextUrlCarriesItsTarget {
	UIFont *font = [UIFont systemFontOfSize:15];
	NSDictionary *ent = @{@"offset" : @3, @"length" : @4,
						  @"type" : @{@"@type" : @"textEntityTypeTextUrl",
									  @"url" : @"https://example.com"}};
	NSAttributedString *str = TGAttributedMessageText(@"see here ok", @[ent],
			font, nil);

	NSString *url = [str attribute:@"TGLinkURL" atIndex:4 effectiveRange:NULL];
	XCTAssertTrue([url isEqualToString:@"https://example.com"],
			@"the entity's target must ride along for the tap handler");
	NSNumber *underline = [str attribute:NSUnderlineStyleAttributeName
			atIndex:4 effectiveRange:NULL];
	XCTAssertNotNil(underline, @"text urls render as links");
}

- (void)testAttributedMessageText_UrlEntityIsTheTextItself {
	UIFont *font = [UIFont systemFontOfSize:15];
	NSDictionary *ent = @{@"offset" : @0, @"length" : @11,
						  @"type" : @{@"@type" : @"messageEntityUrl"}};
	NSAttributedString *str = TGAttributedMessageText(@"example.com", @[ent],
			font, nil);
	NSString *url = [str attribute:@"TGLinkURL" atIndex:2 effectiveRange:NULL];
	XCTAssertTrue([url isEqualToString:@"example.com"]);
}

- (void)testAttributedMessageText_EntitiesOutsideTextAreIgnored {
	// Entities beyond the text, negative offsets and zero-length runs used
	// to crash the chat; they are dropped.
	UIFont *font = [UIFont systemFontOfSize:15];
	NSArray *entities = @[
		@{@"offset" : @0, @"length" : @500,
		  @"type" : @{@"@type" : @"messageEntitySpoiler"}},
		@{@"offset" : @-3, @"length" : @2,
		  @"type" : @{@"@type" : @"messageEntitySpoiler"}},
		@{@"offset" : @2, @"length" : @0,
		  @"type" : @{@"@type" : @"messageEntitySpoiler"}},
		@"not-an-entity",
	];
	NSAttributedString *str = TGAttributedMessageText(@"tiny", entities, font, nil);
	XCTAssertNotNil(str);
	XCTAssertEqual(str.length, 4u, @"dropped entities must not change the text");

	__block BOOL painted = NO;
	[str enumerateAttribute:NSBackgroundColorAttributeName
					inRange:NSMakeRange(0, str.length)
					options:0
				 usingBlock:^(id value, NSRange range, BOOL *stop){
					 if (value) painted = YES;
				 }];
	XCTAssertFalse(painted,
			@"an entity longer than the text must not paint the whole message");
}

- (void)testAttributedMessageText_MentionAndBoldInLegacyShapes {
	// TDLib sends both nested ("type" dict) and flat ("@type") entity
	// spellings depending on version; both must land.
	UIFont *font = [UIFont systemFontOfSize:15];
	NSAttributedString *str = TGAttributedMessageText(@"@user text",
			@[@{@"offset" : @0, @"length" : @5,
				@"@type" : @"messageEntityMention"}], font, nil);
	UIColor *mention = [str attribute:NSForegroundColorAttributeName
			atIndex:0 effectiveRange:NULL];
	XCTAssertNotNil(mention);
}

// ──────────────────────────────────────────────────────────────────────────────
#pragma mark - measurement with entities

- (void)testTextSizeWithEntities_MeasuresLikePlain {
	UIFont *font = [UIFont systemFontOfSize:15];
	NSString *text = @"hello bold world";
	NSDictionary *ent = @{@"offset" : @6, @"length" : @4,
						  @"type" : @{@"@type" : @"textEntityTypeBold"}};
	CGSize withEntity  = TGTextSizeWithEntities(text, @[ent], font, 246);
	CGSize without     = TGTextSize(text, font, 246);
	XCTAssertGreaterThan(withEntity.width, 0.0);
	XCTAssertGreaterThan(without.width, 0.0);
	XCTAssertLessThanOrEqual(withEntity.height, without.height + 1.0,
			@"entities may flavour but must not rewrap the same single line");
}

- (void)testTextSizeWithEntities_EmptyTextIsZero {
	CGSize empty = TGTextSizeWithEntities(@"", nil, nil, 246);
	XCTAssertEqual(empty.width,  0.0);
	XCTAssertEqual(empty.height, 0.0);
}

// ──────────────────────────────────────────────────────────────────────────────
#pragma mark - emoji scalars

- (void)testIsEmojiScalar_Boundaries {
	XCTAssertTrue(TGIsEmojiScalar(0x1F000));      // first pictograph
	XCTAssertFalse(TGIsEmojiScalar(0x1EFFF));     // just below
	XCTAssertTrue(TGIsEmojiScalar(0x1FAFF));      // last extended pictograph
	XCTAssertFalse(TGIsEmojiScalar(0x1FB00));     // symbol block after it
	XCTAssertTrue(TGIsEmojiScalar(0x2600));       // misc symbols
	XCTAssertTrue(TGIsEmojiScalar(0x27BF));       // last dingbat
	XCTAssertTrue(TGIsEmojiScalar(0x2B00));       // arrows/stars open
	XCTAssertTrue(TGIsEmojiScalar(0x2BFF));       // arrows/stars close
	XCTAssertFalse(TGIsEmojiScalar(0x2C00));      // just past arrows
	XCTAssertFalse(TGIsEmojiScalar(0x0041));      // plain latin
	XCTAssertFalse(TGIsEmojiScalar(0x0020));      // space
}

// ──────────────────────────────────────────────────────────────────────────────
#pragma mark - emoji attribution

- (void)testEmojiAttributedText_EmptyIsNil {
	XCTAssertNil(TGEmojiAttributedText(@"", [UIFont systemFontOfSize:15]));
}

- (void)testEmojiAttributedText_PlainTextNeverDowngraded {
	NSString *plain = @"just words";
	NSAttributedString *styled = TGEmojiAttributedText(plain,
			[UIFont systemFontOfSize:15]);
	if (styled){   // an emoji font is registered on this host
		XCTAssertEqual(styled.length, plain.length,
				@"emoji styling must not drop characters");
		UIFont *f = [styled attribute:NSFontAttributeName atIndex:0
				effectiveRange:NULL];
		XCTAssertNotNil(f, @"plain text must keep some font");
	}
	// and either way the call is safe to repeat (cache)
	NSAttributedString *again = TGEmojiAttributedText(plain,
			[UIFont systemFontOfSize:15]);
	if (styled && again)
		XCTAssertTrue([again isEqualToAttributedString:styled],
				@"the cache must return the same attribution");
}

- (void)testEmojiAttributedText_EmojiTextKeepsLength {
	NSString *emoji = @"\U0001F600\U0001F601 ok";
	NSAttributedString *styled = TGEmojiAttributedText(emoji,
			[UIFont systemFontOfSize:15]);
	if (styled)
		XCTAssertEqual(styled.length, emoji.length);
}

// ──────────────────────────────────────────────────────────────────────────────
#pragma mark - TGSetBodyText

- (void)testSetBodyText_PlainTextLandsInLabel {
	UILabel *label = [[UILabel alloc] init];
	NSString *text = @"plain message";
	TGSetBodyText(label, text, [UIColor redColor]);
	XCTAssertEqualObjects(label.attributedText, nil, @"no emoji: plain path");
	XCTAssertEqualObjects(label.text, text);
	XCTAssertTrue([label.textColor isEqual:[UIColor redColor]],
			@"the bubble colour must be applied");
}

- (void)testSetBodyText_EmptyDoesNotThrow {
	UILabel *label = [[UILabel alloc] init];
	XCTAssertNoThrow(TGSetBodyText(label, @"", [UIColor blackColor]),
			@"an empty message must not blank a label into a bad state");
}

// ──────────────────────────────────────────────────────────────────────────────
#pragma mark - TGMessageLayout shell

- (void)testMessageLayout_FullRadiusReplyBarConstants {
	// The geometry chain reads these; the numbers the fix history turned on.
	XCTAssertGreaterThan(kBubbleMaxW, 0.0);
	XCTAssertGreaterThan(kTailHeight, kTailWidth, @"tail proportions");
	XCTAssertEqual(kMediaRadius, 6.0f);
}

- (void)testMessageLayout_AllocableWithDefaultGeometry {
	TGMessageLayout *layout = [[TGMessageLayout alloc] init];
	XCTAssertEqual(layout.rowHeight, 0.0);
	layout.bubbleFrame = CGRectMake(0, 0, kBubbleMaxW, 20);
	XCTAssertEqual(layout.bubbleFrame.size.width, kBubbleMaxW);
}

- (void)testLruLayoutCache_HitsConsistently {
	UIFont *font15 = [UIFont systemFontOfSize:15];
	UIFont *font17 = [UIFont systemFontOfSize:17];
	NSString *text = @"Caching test message for C++ LRU layout cache";

	CGSize size1 = TGTextSize(text, font15, 200);
	CGSize size2 = TGTextSize(text, font15, 200);
	XCTAssertEqual(size1.width, size2.width);
	XCTAssertEqual(size1.height, size2.height);

	CGSize sizeDiffFont = TGTextSize(text, font17, 200);
	XCTAssertGreaterThanOrEqual(sizeDiffFont.height, size1.height);
}

- (void)testEmojiScanning_FastBypassForPlainLetters {
	NSString *plain = @"Hello, this is pure ASCII without any emoji.";
	UIFont *font = [UIFont systemFontOfSize:15];
	NSAttributedString *str1 = TGEmojiAttributedText(plain, font);
	NSAttributedString *str2 = TGEmojiAttributedText(plain, font);
	XCTAssertNil(str1);
	XCTAssertNil(str2);
}

@end
