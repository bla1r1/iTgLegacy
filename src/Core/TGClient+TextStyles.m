//
// TGClient+TextStyles.m - the text composition styles wire.
//
// Telegram has no getTextCompositionStyles: the used list arrives whole in
// updateTextCompositionStyles and changes only through the calls below. The
// cache is therefore the list, and every call patches it with the answer so
// a manager opened twice does not show a stale row.
//
#import "TGClient+TextStyles.h"
#import "TGClientInternal.h"

static NSString *TGTextStyleError(NSDictionary *result) {
	if (![result[@"@type"] isEqualToString:@"error"])
		return nil;
	NSString *message = result[@"message"];
	return message.length ? message : @"Telegram refused that.";
}

/// One textCompositionStyle, with the example made optional because the
/// list update never carries it.
static NSDictionary *TGTextStyleRow(NSDictionary *style) {
	if (![style isKindOfClass:NSDictionary.class])
		return nil;
	NSString *name = style[@"name"];
	if (![name isKindOfClass:NSString.class] || !name.length)
		return nil;
	return @{
		@"name"         : name,
		@"title"        : style[@"title"] ?: name,
		@"emojiId"      : style[@"custom_emoji_id"] ?: @(0),
		@"isCustom"     : @([style[@"is_custom"] boolValue]),
		@"isCreator"    : @([style[@"is_creator"] boolValue]),
		@"installCount" : style[@"install_count"] ?: @(0),
		@"prompt"       : style[@"prompt"] ?: @"",
		@"creatorUserId": style[@"creator_user_id"] ?: @(0),
	};
}

static NSDictionary *TGTextStyleExampleRow(NSDictionary *example) {
	if (![example isKindOfClass:NSDictionary.class])
		return nil;
	NSDictionary *source = example[@"source_text"];
	NSDictionary *result = example[@"result_text"];
	return @{
		@"sourceText"      : source[@"text"] ?: @"",
		@"sourceEntities"  : source[@"entities"] ?: @[],
		@"resultText"      : result[@"text"] ?: @"",
		@"resultEntities"  : result[@"entities"] ?: @[],
	};
}

@implementation TGClient (TextStyles)

/// The update is the whole used list, not a delta: a style added on another
/// client appears and one removed disappears without a request from here.
- (void)applyTextCompositionStylesUpdate:(NSDictionary *)update {
	NSMutableArray *rows = [NSMutableArray array];
	NSArray *styles = update[@"styles"];
	if ([styles isKindOfClass:NSArray.class])
		for (NSDictionary *style in styles){
			NSDictionary *row = TGTextStyleRow(style);
			if (row)
				[rows addObject:row];
		}
	self.textCompositionStylesValue = rows;
	[[NSNotificationCenter defaultCenter]
			postNotificationName:TGTextCompositionStylesChangedNotification
						  object:self];
}

- (NSArray *)textCompositionStyles {
	return self.textCompositionStylesValue ?: @[];
}

/// The list is one unit: a style edited or added is replaced by name, and a
/// style deleted disappears. Keeping the order Telegram sent matters - the
/// composer shows it in that order.
- (void)mergeTextCompositionStyle:(NSDictionary *)style remove:(BOOL)remove {
	NSDictionary *row = TGTextStyleRow(style);
	NSString *name = row[@"name"];
	if (!name.length)
		return;
	NSMutableArray *rows = [self.textCompositionStylesValue mutableCopy]
			?: [NSMutableArray array];
	NSUInteger found = NSNotFound;
	for (NSUInteger i = 0; i < rows.count; i++)
		if ([rows[i][@"name"] isEqualToString:name]){
			found = i;
			break;
		}
	if (remove){
		if (found != NSNotFound)
			[rows removeObjectAtIndex:found];
	} else if (found != NSNotFound)
		[rows replaceObjectAtIndex:found withObject:row];
	else
		[rows addObject:row];
	self.textCompositionStylesValue = rows;
	[[NSNotificationCenter defaultCenter]
			postNotificationName:TGTextCompositionStylesChangedNotification
						  object:nil];
}

- (void)createTextCompositionStyle:(NSString *)title
                           emojiId:(int64_t)customEmojiId
                            prompt:(NSString *)prompt
                       showCreator:(BOOL)showCreator
                        completion:(void (^)(NSDictionary *, NSString *))completion {
	[self request:@{
		@"@type" : @"createTextCompositionStyle",
		@"title" : title ?: @"",
		@"custom_emoji_id" : @(customEmojiId),
		@"prompt" : prompt ?: @"",
		@"show_creator" : @(showCreator),
	} completion:^(NSDictionary *result){
		NSString *error = TGTextStyleError(result);
		if (error){
			if (completion)
				completion(nil, error);
			return;
		}
		NSDictionary *row = TGTextStyleRow(result);
		[self mergeTextCompositionStyle:result remove:NO];
		if (completion)
			completion(row, nil);
	}];
}

- (void)editTextCompositionStyleNamed:(NSString *)name
                                title:(NSString *)title
                              emojiId:(int64_t)customEmojiId
                               prompt:(NSString *)prompt
                          showCreator:(BOOL)showCreator
                           completion:(void (^)(NSDictionary *, NSString *))completion {
	[self request:@{
		@"@type" : @"editTextCompositionStyle",
		@"name" : name ?: @"",
		@"title" : title ?: @"",
		@"custom_emoji_id" : @(customEmojiId),
		@"prompt" : prompt ?: @"",
		@"show_creator" : @(showCreator),
	} completion:^(NSDictionary *result){
		NSString *error = TGTextStyleError(result);
		if (error){
			if (completion)
				completion(nil, error);
			return;
		}
		NSDictionary *row = TGTextStyleRow(result);
		[self mergeTextCompositionStyle:result remove:NO];
		if (completion)
			completion(row, nil);
	}];
}

- (void)deleteTextCompositionStyleNamed:(NSString *)name
                             completion:(void (^)(BOOL, NSString *))completion {
	[self request:@{
		@"@type" : @"deleteTextCompositionStyle",
		@"name" : name ?: @"",
	} completion:^(NSDictionary *result){
		NSString *error = TGTextStyleError(result);
		if (!error)
			[self mergeTextCompositionStyle:@{@"name" : name ?: @""} remove:YES];
		if (completion)
			completion(error == nil, error);
	}];
}

- (void)searchTextCompositionStyleNamed:(NSString *)name
                             completion:(void (^)(NSDictionary *, NSString *))completion {
	[self request:@{
		@"@type" : @"searchTextCompositionStyle",
		@"name" : name ?: @"",
	} completion:^(NSDictionary *result){
		NSString *error = TGTextStyleError(result);
		if (error){
			if (completion)
				completion(nil, error);
			return;
		}
		NSDictionary *row = TGTextStyleRow(result);
		[self mergeTextCompositionStyle:result remove:NO];
		if (completion)
			completion(row, nil);
	}];
}

- (void)textCompositionStyleExampleNamed:(NSString *)name
                                  number:(NSInteger)number
                              completion:(void (^)(NSDictionary *, NSString *))completion {
	[self request:@{
		@"@type" : @"getTextCompositionStyleExample",
		@"name" : name ?: @"",
		@"example_number" : @(number),
	} completion:^(NSDictionary *result){
		NSString *error = TGTextStyleError(result);
		if (completion)
			completion(error ? nil : TGTextStyleExampleRow(result), error);
	}];
}

- (void)addTextCompositionStyleNamed:(NSString *)name
                          completion:(void (^)(BOOL, NSString *))completion {
	[self request:@{
		@"@type" : @"addTextCompositionStyle",
		@"name" : name ?: @"",
	} completion:^(NSDictionary *result){
		NSString *error = TGTextStyleError(result);
		if (completion)
			completion(error == nil, error);
	}];
}

- (void)removeTextCompositionStyleNamed:(NSString *)name
                             completion:(void (^)(BOOL, NSString *))completion {
	[self request:@{
		@"@type" : @"removeTextCompositionStyle",
		@"name" : name ?: @"",
	} completion:^(NSDictionary *result){
		NSString *error = TGTextStyleError(result);
		if (completion)
			completion(error == nil, error);
	}];
}

@end
