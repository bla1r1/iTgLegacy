//
// TGMessageAudienceViewController.h - who reacted to, or read, one message.
//
// The reaction chips and the "Viewed by N" row both land here: a plain list
// of people with their picture, the day it happened and - for reactions -
// the emoji itself. It is a pushed screen, so the navigation bar's back
// control is what closes it.
//
#import <UIKit/UIKit.h>

typedef NS_ENUM(NSInteger, TGMessageAudienceKind) {
	TGMessageAudienceKindReactions = 0,
	TGMessageAudienceKindViewers,
};

@interface TGMessageAudienceViewController : UITableViewController

/// `emoji` is the reaction group's glyph; `customEmojiId` is set instead when
/// the group is a custom emoji and there is no character to send.
- (instancetype)initWithKind:(TGMessageAudienceKind)kind
						chat:(int64_t)chatId
					 message:(int64_t)messageId
					   emoji:(NSString *)emoji
			   customEmojiId:(int64_t)customEmojiId;

@end
