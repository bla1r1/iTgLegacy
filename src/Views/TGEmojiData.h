//
// TGEmojiData - the emoji the panel offers, by category, in Telegram's order.
//
#import <Foundation/Foundation.h>

/// Each entry: "name" (for the strip), "icon" (the emoji standing for the
/// category) and "emoji" (an array of strings). Already filtered down to what
/// this device's font can draw, so nothing shows as an empty box.
NSArray *TGEmojiCategories(void);

/// The emoji picked lately, newest first, filtered the same way.
NSArray *TGRecentEmoji(void);
void TGNoteEmojiUsed(NSString *emoji);
