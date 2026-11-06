//
// TGEmojiData - the emoji the panel offers, by category, in Telegram's order.
//
#import <Foundation/Foundation.h>

/// Each entry: "name" (for the strip), "icon" (the emoji standing for the
/// category) and "emoji" (an array of strings). Already filtered down to what
/// this device's font can draw, so nothing shows as an empty box.
NSArray *TGEmojiCategories(void);

/// Builds the categories on a background queue, once per process. Checking
/// ~1800 emoji with CoreText, and the font-database scan its first fallback
/// triggers, cost 180 + 356 ms on the main thread of an iPhone 4S when the
/// first sticker panel of a launch opened.
void TGWarmEmojiData(void);

/// The emoji picked lately, newest first, filtered the same way.
NSArray *TGRecentEmoji(void);
void TGNoteEmojiUsed(NSString *emoji);
