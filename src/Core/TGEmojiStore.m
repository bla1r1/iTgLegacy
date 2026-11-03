//
// TGEmojiStore.m - categories and metadata the emoji panel draws.
//
#import "TGEmojiStore.h"
#import "TGClient.h"

@interface TGEmojiStore ()
@property (nonatomic, strong) NSArray *categories;
@property (nonatomic, assign) BOOL askingForCategories;
@end

@implementation TGEmojiStore

+ (instancetype)shared {
	static TGEmojiStore *store = nil;
	static dispatch_once_t once;
	dispatch_once(&once, ^{ store = [[TGEmojiStore alloc] init]; });
	return store;
}

- (void)reset {
	self.categories = nil;
	self.askingForCategories = NO;
}

/// A burst of tabs opening asks once. The first non-empty answer is kept: an
/// empty one means TDLib has no file database this session, and caching it
/// would hide the categories after the database finishes building.
- (void)categoriesWithCompletion:(void (^)(NSArray *))completion {
	if (self.categories.count){
		if (completion) completion(self.categories);
		return;
	}
	if (self.askingForCategories){
		if (completion) completion(@[]);
		return;
	}
	self.askingForCategories = YES;
	__weak typeof(self) weakSelf = self;
	[[TGClient shared] emojiCategoriesWithCompletion:^(NSArray *categories){
		TGEmojiStore *me = weakSelf;
		if (!me)
			return;
		me.askingForCategories = NO;
		if (categories.count)
			me.categories = categories;
		if (completion) completion(categories ?: @[]);
	}];
}

/// The input language list TDLib wants: the device's preferences as they are,
/// with the region dropped only when the tag carries one. TDLib matches a
/// language tag, and "en-US" does not match its "en" keyword table.
static NSArray *TGEmojiInputLanguages(void) {
	NSMutableArray *codes = [NSMutableArray array];
	for (NSString *tag in [NSLocale preferredLanguages]){
		if (![tag isKindOfClass:NSString.class] || !tag.length)
			continue;
		NSArray *parts = [tag componentsSeparatedByString:@"-"];
		NSString *base = parts.firstObject;
		if (base.length && ![codes containsObject:base])
			[codes addObject:base];
	}
	return codes;
}

- (void)searchEmojis:(NSString *)text completion:(void (^)(NSArray *))completion {
	[[TGClient shared] searchEmojis:text languageCodes:TGEmojiInputLanguages()
					   completion:completion];
}

- (void)keywordEmojis:(NSString *)text completion:(void (^)(NSArray *))completion {
	[[TGClient shared] keywordEmojis:text languageCodes:TGEmojiInputLanguages()
						completion:completion];
}

- (void)suggestionsUrlForLanguage:(NSString *)languageCode
                       completion:(void (^)(NSString *))completion {
	NSString *code = languageCode.length ? languageCode
			: (TGEmojiInputLanguages().firstObject ?: @"en");
	[[TGClient shared] emojiSuggestionsUrlForLanguage:code completion:completion];
}

- (void)reactionForEmoji:(NSString *)emoji
              completion:(void (^)(NSDictionary *))completion {
	[[TGClient shared] emojiReactionForEmoji:emoji completion:completion];
}

- (void)animatedEmojiForEmoji:(NSString *)emoji
                   completion:(void (^)(NSDictionary *))completion {
	[[TGClient shared] animatedEmojiForEmoji:emoji completion:completion];
}

- (void)customEmojiReactionAnimationsWithCompletion:
		(void (^)(NSArray *))completion {
	[[TGClient shared] customEmojiReactionAnimationsWithCompletion:completion];
}

@end
