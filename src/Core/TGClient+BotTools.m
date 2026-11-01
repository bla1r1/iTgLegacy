//
// TGClient+BotTools.m - prepared keyboard buttons.
//
#import "TGClient+BotTools.h"
#import "TGClientInternal.h"

static NSString *TGBotToolError(NSDictionary *result) {
	NSString *message = result[@"message"];
	return [message isKindOfClass:NSString.class] ? message : @"Telegram refused that.";
}

/// "keyboardButtonTypeRequestPoll" reads as "requestPoll" in the card, the
/// same way every other type in this client loses its prefix.
static NSString *TGBotButtonTypeName(NSDictionary *type) {
	if (![type isKindOfClass:NSDictionary.class])
		return @"unknown";
	NSString *name = type[@"@type"];
	if (![name isKindOfClass:NSString.class] || !name.length)
		return @"unknown";
	if ([name hasPrefix:@"keyboardButtonType"]){
		name = [name substringFromIndex:@"keyboardButtonType".length];
		if (!name.length)
			return @"unknown";
		NSString *first = [[name substringToIndex:1] lowercaseString];
		name = [first stringByAppendingString:[name substringFromIndex:1]];
	}
	return name;
}

@implementation TGClient (BotTools)

- (void)preparedKeyboardButtonFromBot:(int64_t)botUserId
					preparedButtonId:(NSString *)preparedButtonId
						   completion:(void (^)(NSDictionary *, NSString *))completion {
	preparedButtonId = [preparedButtonId stringByTrimmingCharactersInSet:
			[NSCharacterSet whitespaceAndNewlineCharacterSet]];
	if (!botUserId || !preparedButtonId.length){
		if (completion) completion(nil, @"A bot id and a prepared button id are both needed.");
		return;
	}
	[self request:@{@"@type" : @"getPreparedKeyboardButton",
					@"bot_user_id" : @(botUserId),
					@"prepared_button_id" : preparedButtonId}
	   completion:^(NSDictionary *result){
		if ([result[@"@type"] isEqualToString:@"error"]){
			if (completion) completion(nil, TGBotToolError(result));
			return;
		}
		if (![result[@"@type"] isEqualToString:@"keyboardButton"]){
			if (completion) completion(nil, @"Telegram answered with something that is not a button.");
			return;
		}
		NSDictionary *style = result[@"style"];
		NSString *styleName = [style isKindOfClass:NSDictionary.class]
				? style[@"@type"] : nil;
		if (![styleName isKindOfClass:NSString.class])
			styleName = nil;
		if ([styleName hasPrefix:@"buttonStyle"])
			styleName = [styleName substringFromIndex:@"buttonStyle".length];
		if (completion)
			completion(@{
				@"text"          : result[@"text"] ?: @"",
				@"type"          : TGBotButtonTypeName(result[@"type"]),
				@"customEmojiId" : result[@"icon_custom_emoji_id"] ?: @0,
				@"style"         : [styleName lowercaseString] ?: @"default",
			}, nil);
	}];
}

- (void)savePreparedKeyboardButtonText:(NSString *)text
							   forUser:(int64_t)userId
							completion:(void (^)(NSString *, NSString *))completion {
	text = [text stringByTrimmingCharactersInSet:
			[NSCharacterSet whitespaceAndNewlineCharacterSet]];
	if (!userId || !text.length){
		if (completion) completion(nil, @"A user id and button text are both needed.");
		return;
	}
	// The whole keyboardButton object, because every field is required: the
	// icon id is 0 for none, the style is the default, and the type is the
	// plain-text one this screen offers.
	NSDictionary *button = @{
		@"@type"                 : @"keyboardButton",
		@"text"                  : text,
		@"icon_custom_emoji_id"  : @0,
		@"style"                 : @{@"@type" : @"buttonStyleDefault"},
		@"type"                  : @{@"@type" : @"keyboardButtonTypeText"},
	};
	[self request:@{@"@type" : @"savePreparedKeyboardButton",
					@"user_id" : @(userId),
					@"button" : button}
	   completion:^(NSDictionary *result){
		if ([result[@"@type"] isEqualToString:@"error"]){
			if (completion) completion(nil, TGBotToolError(result));
			return;
		}
		BOOL isText = [result[@"@type"] isEqualToString:@"text"];
		NSString *preparedId = isText ? result[@"text"] : nil;
		if (![preparedId isKindOfClass:NSString.class] || !preparedId.length){
			if (completion) completion(nil, @"Telegram did not answer with a prepared button id.");
			return;
		}
		if (completion) completion(preparedId, nil);
	}];
}

@end

// vim:ft=objc
