//
// TGDevShowcase.m - Test harness providing placeholder fixtures for all TDLib message types.
//
#import "TGDevShowcase.h"
#import "TGClient.h"
#import "TGClientInternal.h"
#import "TGStyle.h"
#import "TGTheme.h"
#import "TGIcons.h"

@implementation TGDevShowcase

+ (BOOL)isDevChatId:(int64_t)chatId {
	return (chatId == kDevChatId || chatId == kDevDurovChatId || chatId == kDevBotChatId);
}

+ (NSDictionary *)devChatInfo {
	return @{
		@"id"          : @(kDevChatId),
		@"title"       : @"Dev Showcase",
		@"type"        : @"chatTypeBasicGroup",
		@"isGroup"     : @YES,
		@"text"        : @"All 30 TDLib message types running on iOS 7!",
		@"previewText" : @"All 30 TDLib message types running on iOS 7!",
		@"unread"      : @0,
		@"time"        : @"Now",
		@"date"        : @([[NSDate date] timeIntervalSince1970]),
		@"pinned"      : @YES,
	};
}

+ (NSArray *)allShowcaseChats {
	double now = [[NSDate date] timeIntervalSince1970];
	return @[
		[self devChatInfo],
		@{
			@"id"          : @(kDevDurovChatId),
			@"title"       : @"Pavel Durov",
			@"type"        : @"chatTypePrivate",
			@"isGroup"     : @NO,
			@"text"        : @"Freedom and privacy for everyone.",
			@"previewText" : @"Freedom and privacy for everyone.",
			@"unread"      : @1,
			@"time"        : @"19:16",
			@"date"        : @(now - 120),
			@"pinned"      : @NO,
		},
		@{
			@"id"          : @(kDevBotChatId),
			@"title"       : @"Dev Bot",
			@"type"        : @"chatTypePrivate",
			@"isGroup"     : @NO,
			@"text"        : @"/showcase - Open full media harness",
			@"previewText" : @"/showcase - Open full media harness",
			@"unread"      : @0,
			@"time"        : @"19:34",
			@"date"        : @(now - 300),
			@"pinned"      : @NO,
		},
	];
}

+ (NSArray *)allShowcaseContacts {
	return @[
		@{
			@"id" : @(20002),
			@"first_name" : @"Pavel",
			@"last_name" : @"Durov",
			@"phone_number" : @"+971 50 123 4567",
			@"status" : @{@"@type" : @"userStatusOnline"},
		},
		@{
			@"id" : @(10001),
			@"first_name" : @"Dev Bot",
			@"last_name" : @"(BotFather)",
			@"phone_number" : @"+42 777",
			@"type" : @{@"@type" : @"userTypeBot"},
			@"status" : @{@"@type" : @"userStatusEmpty"},
		},
	];
}

+ (NSArray *)messagesForChatId:(int64_t)chatId {
	if (chatId == kDevDurovChatId) {
		return [self pavelDurovMessages];
	} else if (chatId == kDevBotChatId) {
		return [self devBotMessages];
	}
	return [self allShowcaseMessages];
}

+ (NSArray *)pavelDurovMessages {
	double now = [[NSDate date] timeIntervalSince1970];
	double baseTime = now - 600.0;
	int64_t senderPeer = 20002;
	int64_t senderMe = 10001;

	[TGClient shared].usersById[@(senderPeer)] = @"Pavel Durov";

	NSMutableArray *list = [NSMutableArray array];
	[list addObject:@{
		@"id"       : @1,
		@"chatId"   : @(kDevDurovChatId),
		@"senderId" : @(senderPeer),
		@"outgoing" : @NO,
		@"date"     : @(baseTime),
		@"text"     : @"Pavel Durov joined Telegram",
		@"kind"     : @"messageChatAddMembers",
		@"service"  : @YES,
	}];

	[list addObject:@{
		@"id"       : @2,
		@"chatId"   : @(kDevDurovChatId),
		@"senderId" : @(senderMe),
		@"outgoing" : @YES,
		@"date"     : @(baseTime + 60),
		@"text"     : @"Hello Pavel! Welcome to LegacyTG running on iPhone 4S with iOS 6 design.",
		@"kind"     : @"messageText",
	}];

	[list addObject:@{
		@"id"       : @3,
		@"chatId"   : @(kDevDurovChatId),
		@"senderId" : @(senderPeer),
		@"outgoing" : @NO,
		@"date"     : @(baseTime + 120),
		@"text"     : @"Hello! Impressive work on the skeuomorphic iOS 6 design and TDLib integration.",
		@"kind"     : @"messageText",
	}];

	[list addObject:@{
		@"id"       : @4,
		@"chatId"   : @(kDevDurovChatId),
		@"senderId" : @(senderPeer),
		@"outgoing" : @NO,
		@"date"     : @(baseTime + 180),
		@"kind"     : @"messageSticker",
		@"extra"    : @"👍",
		@"photoId"  : @(-201),
	}];

	[list addObject:@{
		@"id"       : @5,
		@"chatId"   : @(kDevDurovChatId),
		@"senderId" : @(senderMe),
		@"outgoing" : @YES,
		@"date"     : @(baseTime + 240),
		@"text"     : @"Vector Lottie stickers and VP9 video stickers are working smoothly too!",
		@"kind"     : @"messageText",
	}];

	[list addObject:@{
		@"id"       : @6,
		@"chatId"   : @(kDevDurovChatId),
		@"senderId" : @(senderPeer),
		@"outgoing" : @NO,
		@"date"     : @(baseTime + 300),
		@"kind"     : @"messagePhoto",
		@"photoId"  : @(-301),
		@"text"     : @"Freedom and privacy for everyone.",
		@"width"    : @400,
		@"height"   : @300,
	}];

	return list;
}

+ (NSArray *)devBotMessages {
	double now = [[NSDate date] timeIntervalSince1970];
	double baseTime = now - 600.0;
	int64_t senderBot = 10001;

	[TGClient shared].usersById[@(senderBot)] = @"Dev Bot";

	NSMutableArray *list = [NSMutableArray array];
	[list addObject:@{
		@"id"       : @1,
		@"chatId"   : @(kDevBotChatId),
		@"senderId" : @(senderBot),
		@"outgoing" : @NO,
		@"date"     : @(baseTime),
		@"text"     : @"Welcome to LegacyTG Dev Bot! 🤖\n\nCommands:\n/showcase - Open full media harness\n/ping - Measure network latency\n/theme - Switch iOS 6 themes\n/poll - Test interactive poll",
		@"kind"     : @"messageText",
	}];

	[list addObject:@{
		@"id"       : @2,
		@"chatId"   : @(kDevBotChatId),
		@"senderId" : @(senderBot),
		@"outgoing" : @YES,
		@"date"     : @(baseTime + 60),
		@"text"     : @"/showcase",
		@"kind"     : @"messageText",
	}];

	[list addObject:@{
		@"id"       : @3,
		@"chatId"   : @(kDevBotChatId),
		@"senderId" : @(senderBot),
		@"outgoing" : @NO,
		@"date"     : @(baseTime + 120),
		@"text"     : @"All 30 TDLib message types verified and running on iOS 7! 🚀",
		@"kind"     : @"messageText",
		@"reaction" : @"🔥",
	}];

	return list;
}

+ (NSString *)devStickerPath {
	NSString *path = [[NSBundle mainBundle] pathForResource:@"dev_sticker" ofType:@"tgs"];
	if (!path) path = [[NSBundle mainBundle].bundlePath stringByAppendingPathComponent:@"dev_sticker.tgs"];
	return path;
}

+ (NSString *)devWebMPath {
	NSString *path = [[NSBundle mainBundle] pathForResource:@"dev_video_sticker" ofType:@"webm"];
	if (!path) path = [[NSBundle mainBundle].bundlePath stringByAppendingPathComponent:@"dev_video_sticker.webm"];
	return path;
}

+ (NSArray *)allShowcaseMessages {
	double now = [[NSDate date] timeIntervalSince1970];
	double baseTime = now - 3600.0;
	int64_t senderBot = 10001;
	int64_t senderPeer = 20002;

	// Register peer names so headers and service messages render properly
	[TGClient shared].usersById[@(senderBot)] = @"Dev Bot";
	[TGClient shared].usersById[@(senderPeer)] = @"Pavel Durov";

	NSMutableArray *list = [NSMutableArray array];

	// 1. Service: Group created
	[list addObject:@{
		@"id"         : @1,
		@"chatId"     : @(kDevChatId),
		@"senderId"   : @(senderBot),
		@"outgoing"   : @NO,
		@"date"       : @(baseTime + 10),
		@"text"       : @"Group \"Dev Showcase\" created",
		@"kind"       : @"messageBasicGroupChatCreate",
		@"service"    : @YES,
	}];

	// 2. Plain Text
	[list addObject:@{
		@"id"         : @2,
		@"chatId"     : @(kDevChatId),
		@"senderId"   : @(senderPeer),
		@"outgoing"   : @NO,
		@"date"       : @(baseTime + 20),
		@"text"       : @"Hello! This is a standard plain text message from peer.",
		@"kind"       : @"messageText",
	}];

	// 3. Formatted Rich Text (Bold, Italic, Code, Link)
	[list addObject:@{
		@"id"         : @3,
		@"chatId"     : @(kDevChatId),
		@"senderId"   : @(senderBot),
		@"outgoing"   : @YES,
		@"date"       : @(baseTime + 30),
		@"text"       : @"Formatted text with Bold, Italic, inline code, and https://telegram.org link.",
		@"kind"       : @"messageText",
		@"entities"   : @[
			@{@"type" : @"bold",   @"offset" : @20, @"length" : @4},
			@{@"type" : @"italic", @"offset" : @26, @"length" : @6},
			@{@"type" : @"code",   @"offset" : @41, @"length" : @4},
			@{@"type" : @"url",    @"offset" : @51, @"length" : @20},
		],
	}];

	// 4. Quote / Reply
	[list addObject:@{
		@"id"         : @4,
		@"chatId"     : @(kDevChatId),
		@"senderId"   : @(senderPeer),
		@"outgoing"   : @NO,
		@"date"       : @(baseTime + 40),
		@"text"       : @"This message quotes and replies to the previous formatted text.",
		@"kind"       : @"messageText",
		@"replyId"    : @3,
		@"replyText"  : @"Formatted text with Bold, Italic...",
		@"replyAuthor": @"Antigravity Dev",
	}];

	// 5. Forwarded message
	[list addObject:@{
		@"id"         : @5,
		@"chatId"     : @(kDevChatId),
		@"senderId"   : @(senderPeer),
		@"outgoing"   : @NO,
		@"date"       : @(baseTime + 50),
		@"text"       : @"Major update: full support for legacy iOS vector and video stickers has landed!",
		@"kind"       : @"messageText",
		@"forward"    : @"Pavel Durov",
	}];

	// 6. Sticker: Static WebP
	[list addObject:@{
		@"id"         : @6,
		@"chatId"     : @(kDevChatId),
		@"senderId"   : @(senderBot),
		@"outgoing"   : @YES,
		@"date"       : @(baseTime + 60),
		@"kind"       : @"messageSticker",
		@"extra"      : @"👍",
		@"photoId"    : @(-201),
	}];

	// 7. Sticker: Lottie Vector Animation (.tgs)
	[list addObject:@{
		@"id"         : @7,
		@"chatId"     : @(kDevChatId),
		@"senderId"   : @(senderPeer),
		@"outgoing"   : @NO,
		@"date"       : @(baseTime + 70),
		@"kind"       : @"messageSticker",
		@"extra"      : @"⭐",
		@"photoId"    : @(-101),
		@"docId"      : @(-101),
		@"docName"    : @"tgs",
		@"isAnimated" : @YES,
	}];

	// 8. Sticker: WebM VP9 Video Sticker (.webm)
	[list addObject:@{
		@"id"         : @8,
		@"chatId"     : @(kDevChatId),
		@"senderId"   : @(senderBot),
		@"outgoing"   : @YES,
		@"date"       : @(baseTime + 80),
		@"kind"       : @"messageSticker",
		@"extra"      : @"🎥",
		@"photoId"    : @(-102),
		@"docId"      : @(-102),
		@"docName"    : @"webm",
		@"isAnimated" : @YES,
	}];

	// 9. Animated Emoji / Dice
	[list addObject:@{
		@"id"         : @9,
		@"chatId"     : @(kDevChatId),
		@"senderId"   : @(senderPeer),
		@"outgoing"   : @NO,
		@"date"       : @(baseTime + 90),
		@"kind"       : @"messageDice",
		@"extra"      : @"🎲",
		@"text"       : @"🎲 Rolled a 6",
	}];

	// 10. Single Photo with Caption
	[list addObject:@{
		@"id"         : @10,
		@"chatId"     : @(kDevChatId),
		@"senderId"   : @(senderPeer),
		@"outgoing"   : @NO,
		@"date"       : @(baseTime + 100),
		@"kind"       : @"messagePhoto",
		@"photoId"    : @(-301),
		@"text"       : @"A scenic view captured in high definition.",
		@"width"      : @400,
		@"height"     : @300,
	}];

	// 11. Dual Photo Album (2 photos)
	[list addObject:@{
		@"id"         : @11,
		@"chatId"     : @(kDevChatId),
		@"senderId"   : @(senderBot),
		@"outgoing"   : @YES,
		@"date"       : @(baseTime + 110),
		@"kind"       : @"messagePhoto",
		@"isAlbum"    : @YES,
		@"albumMessages" : @[
			@{@"id":@111, @"kind":@"messagePhoto", @"photoId":@(-301), @"date":@(baseTime + 110)},
			@{@"id":@112, @"kind":@"messagePhoto", @"photoId":@(-302), @"date":@(baseTime + 110)},
		],
	}];

	// 12. Quad Photo Album (4 photos)
	[list addObject:@{
		@"id"         : @12,
		@"chatId"     : @(kDevChatId),
		@"senderId"   : @(senderPeer),
		@"outgoing"   : @NO,
		@"date"       : @(baseTime + 120),
		@"kind"       : @"messagePhoto",
		@"isAlbum"    : @YES,
		@"albumMessages" : @[
			@{@"id":@121, @"kind":@"messagePhoto", @"photoId":@(-301), @"date":@(baseTime + 120)},
			@{@"id":@122, @"kind":@"messagePhoto", @"photoId":@(-302), @"date":@(baseTime + 120)},
			@{@"id":@123, @"kind":@"messagePhoto", @"photoId":@(-303), @"date":@(baseTime + 120)},
			@{@"id":@124, @"kind":@"messagePhoto", @"photoId":@(-304), @"date":@(baseTime + 120)},
		],
	}];

	// 13. Video Message
	[list addObject:@{
		@"id"         : @13,
		@"chatId"     : @(kDevChatId),
		@"senderId"   : @(senderBot),
		@"outgoing"   : @YES,
		@"date"       : @(baseTime + 130),
		@"kind"       : @"messageVideo",
		@"duration"   : @142,
		@"text"       : @"Video clip with duration stamp and play overlay",
		@"photoId"    : @(-301),
	}];

	// 14. Video Note (Round Telegram circle video)
	[list addObject:@{
		@"id"         : @14,
		@"chatId"     : @(kDevChatId),
		@"senderId"   : @(senderPeer),
		@"outgoing"   : @NO,
		@"date"       : @(baseTime + 140),
		@"kind"       : @"messageVideoNote",
		@"duration"   : @45,
		@"unplayed"   : @YES,
		@"photoId"    : @(-302),
	}];

	// 15. Voice Note
	[list addObject:@{
		@"id"         : @15,
		@"chatId"     : @(kDevChatId),
		@"senderId"   : @(senderBot),
		@"outgoing"   : @YES,
		@"date"       : @(baseTime + 150),
		@"kind"       : @"messageVoiceNote",
		@"duration"   : @28,
	}];

	// 16. Audio Track (Music)
	[list addObject:@{
		@"id"         : @16,
		@"chatId"     : @(kDevChatId),
		@"senderId"   : @(senderPeer),
		@"outgoing"   : @NO,
		@"date"       : @(baseTime + 160),
		@"kind"       : @"messageAudio",
		@"audioTitle" : @"Midnight City",
		@"audioPerformer" : @"M83",
		@"duration"   : @243,
		@"albumCoverId": @(-401),
		@"text"       : @"Midnight City",
	}];

	// 17. Document / File
	[list addObject:@{
		@"id"         : @17,
		@"chatId"     : @(kDevChatId),
		@"senderId"   : @(senderBot),
		@"outgoing"   : @YES,
		@"date"       : @(baseTime + 170),
		@"kind"       : @"messageDocument",
		@"docName"    : @"Telegram_Engineering_Doc.pdf",
		@"docSize"    : @(12582912),
		@"text"       : @"Telegram_Engineering_Doc.pdf",
	}];

	// 18. Contact Card
	[list addObject:@{
		@"id"         : @18,
		@"chatId"     : @(kDevChatId),
		@"senderId"   : @(senderPeer),
		@"outgoing"   : @NO,
		@"date"       : @(baseTime + 180),
		@"kind"       : @"messageContact",
		@"text"       : @"Pavel Durov\n+1 234 567 8900",
		@"extra"      : @"Pavel Durov",
	}];

	// 19. Location & Venue
	[list addObject:@{
		@"id"         : @19,
		@"chatId"     : @(kDevChatId),
		@"senderId"   : @(senderPeer),
		@"outgoing"   : @NO,
		@"date"       : @(baseTime + 190),
		@"kind"       : @"messageLocation",
		@"lat"        : @(48.8584),
		@"lon"        : @(2.2945),
		@"text"       : @"Eiffel Tower, Paris",
	}];

	// 20. Open Regular Poll
	[list addObject:@{
		@"id"         : @20,
		@"chatId"     : @(kDevChatId),
		@"senderId"   : @(senderBot),
		@"outgoing"   : @YES,
		@"date"       : @(baseTime + 200),
		@"kind"       : @"messagePoll",
		@"pollQuestion" : @"Which sticker format is faster on iOS 7?",
		@"pollOptions"  : @[
			@{@"text" : @"Optimized Vector Lottie (.tgs)", @"voter_count" : @45},
			@{@"text" : @"Hardware VP9 Video (.webm)",    @"voter_count" : @65},
		],
		@"pollClosed"   : @NO,
		@"pollQuiz"     : @NO,
	}];

	// 21. Closed Quiz Poll
	[list addObject:@{
		@"id"         : @21,
		@"chatId"     : @(kDevChatId),
		@"senderId"   : @(senderPeer),
		@"outgoing"   : @NO,
		@"date"       : @(baseTime + 210),
		@"kind"       : @"messagePoll",
		@"pollQuestion" : @"What processor powers the iPhone 4S?",
		@"pollOptions"  : @[
			@{@"text" : @"Apple A4", @"voter_count" : @5},
			@{@"text" : @"Apple A5 (Dual Core)", @"voter_count" : @92},
			@{@"text" : @"Apple A6", @"voter_count" : @3},
		],
		@"pollClosed"   : @YES,
		@"pollQuiz"     : @YES,
	}];

	// 22. Voice Call (Answered)
	[list addObject:@{
		@"id"         : @22,
		@"chatId"     : @(kDevChatId),
		@"senderId"   : @(senderBot),
		@"outgoing"   : @YES,
		@"date"       : @(baseTime + 220),
		@"kind"       : @"messageCall",
		@"callState"  : @"answered",
		@"duration"   : @312,
		@"text"       : @"Outgoing Call (5:12)",
	}];

	// 23. Missed Call
	[list addObject:@{
		@"id"         : @23,
		@"chatId"     : @(kDevChatId),
		@"senderId"   : @(senderPeer),
		@"outgoing"   : @NO,
		@"date"       : @(baseTime + 230),
		@"kind"       : @"messageCall",
		@"callState"  : @"missed",
		@"text"       : @"Missed Call",
	}];

	// 24. Game Card
	[list addObject:@{
		@"id"         : @24,
		@"chatId"     : @(kDevChatId),
		@"senderId"   : @(senderBot),
		@"outgoing"   : @YES,
		@"date"       : @(baseTime + 240),
		@"kind"       : @"messageGame",
		@"text"       : @"🎮 Corsairs - HTML5 Telegram Game",
	}];

	// 25. Invoice
	[list addObject:@{
		@"id"         : @25,
		@"chatId"     : @(kDevChatId),
		@"senderId"   : @(senderBot),
		@"outgoing"   : @YES,
		@"date"       : @(baseTime + 250),
		@"kind"       : @"messageInvoice",
		@"text"       : @"Invoice: Telegram Premium (1 Year) — $29.99",
	}];

	// 26. Story
	[list addObject:@{
		@"id"         : @26,
		@"chatId"     : @(kDevChatId),
		@"senderId"   : @(senderPeer),
		@"outgoing"   : @NO,
		@"date"       : @(baseTime + 260),
		@"kind"       : @"messageStory",
		@"text"       : @"Telegram Story",
	}];

	// 27. Unread Separator
	[list addObject:@{
		@"id"         : @27,
		@"chatId"     : @(kDevChatId),
		@"date"       : @(baseTime + 270),
		@"kind"       : @"messageService",
		@"service"    : @YES,
		@"separator"  : @"unread",
		@"text"       : @"Unread messages",
	}];

	// 28. Pinned Message Service
	[list addObject:@{
		@"id"         : @28,
		@"chatId"     : @(kDevChatId),
		@"senderId"   : @(senderPeer),
		@"outgoing"   : @NO,
		@"date"       : @(baseTime + 280),
		@"kind"       : @"messagePinMessage",
		@"service"    : @YES,
		@"text"       : @"pinned a message",
	}];

	// 29. Screenshot Service
	[list addObject:@{
		@"id"         : @29,
		@"chatId"     : @(kDevChatId),
		@"senderId"   : @(senderPeer),
		@"outgoing"   : @NO,
		@"date"       : @(baseTime + 290),
		@"kind"       : @"messageScreenshotTaken",
		@"service"    : @YES,
		@"text"       : @"took a screenshot",
	}];

	// 30. Final interactive text
	[list addObject:@{
		@"id"         : @30,
		@"chatId"     : @(kDevChatId),
		@"senderId"   : @(senderBot),
		@"outgoing"   : @YES,
		@"date"       : @(baseTime + 300),
		@"text"       : @"All 30 TDLib message types verified and running on iOS 7! 🚀",
		@"kind"       : @"messageText",
		@"reaction"   : @"🔥",
	}];

	return list;
}

#pragma mark - Mock Media & Fixtures

+ (UIImage *)imageForPhotoId:(int64_t)photoId {
	static NSMutableDictionary *cache = nil;
	static dispatch_once_t onceToken;
	dispatch_once(&onceToken, ^{
		cache = [NSMutableDictionary dictionary];
	});

	NSNumber *key = @(photoId);
	UIImage *cached = cache[key];
	if (cached) return cached;

	NSString *bundlePath = [NSBundle mainBundle].bundlePath;
	NSString *filename = nil;

	switch (photoId) {
		case -301: filename = @"builtin-wallpaper-4.jpg"; break; // Mountain valley landscape
		case -302: filename = @"builtin-wallpaper-1.jpg"; break; // Colorful umbrellas
		case -303: filename = @"builtin-wallpaper-3.jpg"; break; // City skyline in rain
		case -304: filename = @"builtin-wallpaper-2.jpg"; break; // Rustic wood planks
		case -305: filename = @"builtin-wallpaper-0.jpg"; break; // Telegram doodles pattern
		default: break;
	}

	if (filename) {
		NSString *path = [[NSBundle mainBundle] pathForResource:[filename stringByDeletingPathExtension]
														 ofType:[filename pathExtension]];
		if (!path) path = [bundlePath stringByAppendingPathComponent:filename];
		if (path) {
			UIImage *img = [UIImage imageWithContentsOfFile:path];
			if (img) {
				cache[key] = img;
				return img;
			}
		}
	}

	if (photoId == -201) {
		UIImage *s = [TGIcons thumbsUpSticker];
		if (s) { cache[key] = s; return s; }
	} else if (photoId == -101) {
		UIImage *s = [TGIcons goldStarSticker];
		if (s) { cache[key] = s; return s; }
	} else if (photoId == -102) {
		UIImage *s = [TGIcons cinemaSticker];
		if (s) { cache[key] = s; return s; }
	}

	// Fallback to builtin wallpaper 0
	NSString *fallback = [bundlePath stringByAppendingPathComponent:@"builtin-wallpaper-0.jpg"];
	UIImage *fImg = [UIImage imageWithContentsOfFile:fallback];
	if (fImg) {
		cache[key] = fImg;
		return fImg;
	}
	return nil;
}

+ (UIImage *)avatarForUserId:(int64_t)userId {
	static NSMutableDictionary *avatarCache = nil;
	static dispatch_once_t onceToken;
	dispatch_once(&onceToken, ^{
		avatarCache = [NSMutableDictionary dictionary];
	});

	NSNumber *key = @(userId);
	UIImage *cached = avatarCache[key];
	if (cached) return cached;

	NSString *bundlePath = [NSBundle mainBundle].bundlePath;
	NSString *filename = nil;
	if (userId == 20002) {
		filename = @"avatar-durov.jpg";
	} else if (userId == 10001) {
		filename = @"avatar-bot.jpg";
	}

	if (filename) {
		NSString *path = [[NSBundle mainBundle] pathForResource:[filename stringByDeletingPathExtension]
														 ofType:[filename pathExtension]];
		if (!path) path = [bundlePath stringByAppendingPathComponent:filename];
		if (path) {
			UIImage *img = [UIImage imageWithContentsOfFile:path];
			if (img) {
				avatarCache[key] = img;
				return img;
			}
		}
	}
	return nil;
}

+ (UIImage *)trackArtwork {
	return [TGIcons synthwaveTrackArtwork];
}

@end
