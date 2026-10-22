//
// TGIcons - the icon set, drawn rather than shipped as artwork.
//
// Drawing them means they follow TGTheme: line art with flat, and shaded
// glyphs with a highlight when skeuomorphic. It also means one source for
// every scale instead of a folder of PNGs per size.
//
#import <UIKit/UIKit.h>

@interface TGIcons : NSObject

+ (UIImage *)chats;        ///< tab bar
+ (UIImage *)contacts;
+ (UIImage *)settings;

+ (UIImage *)compose;      ///< new message
+ (UIImage *)send;
+ (UIImage *)attach;
+ (UIImage *)play;         ///< over video thumbnails
+ (UIImage *)pause;
+ (UIImage *)document;
+ (UIImage *)pin;
+ (UIImage *)microphone;
+ (UIImage *)sticker;

/// The circular play button their media blocks use: a 42dp disc in blue with
/// a white glyph, scaled to whatever side is asked for.
+ (UIImage *)mediaDiscOfSide:(CGFloat)side playing:(BOOL)playing;

/// The same disc carrying a sheet of paper, which is what their file block puts
/// on its tile.
+ (UIImage *)fileDiscOfSide:(CGFloat)side;

/// The microphone drawn solid in one colour, for the record button - the tab
/// bar glyphs are template images and cannot carry a fill of their own.
+ (UIImage *)microphoneOfSide:(CGFloat)side colour:(UIColor *)colour;

/// The bars of a voice message, drawn from TDLib's five-bits-per-sample
/// waveform. `played` is how much of it has been listened to, 0 to 1.
+ (UIImage *)waveform:(NSData *)waveform size:(CGSize)size
               played:(CGFloat)played colour:(UIColor *)colour;

/// The 6x10 tail Telegram hangs off the corner of a bubble.
+ (UIImage *)bubbleTailForColour:(UIColor *)colour outgoing:(BOOL)outgoing;          ///< map marker

/// Delivery ticks, drawn the way Telegram draws them: two checks overlapping
/// into one mark, not two separate glyphs side by side.
+ (UIImage *)ticksWhite:(BOOL)white;
+ (UIImage *)selectionCheckboxSelected:(BOOL)selected;

/// The two rows that stand above the chat list draw a glyph, not a letter:
/// a filled archive box, and the bookmark Telegram uses for Saved Messages.
+ (UIImage *)archiveAvatarOfSide:(CGFloat)side;
+ (UIImage *)savedMessagesAvatarOfSide:(CGFloat)side;

/// Circular avatar with initials, for chats and contacts without a photo.
+ (UIImage *)avatarWithInitials:(NSString *)initials
                           size:(CGFloat)size
                       colourId:(int64_t)colourId;

+ (UIImage *)mapPinBadge;
+ (UIImage *)mapPlaceholderSize:(CGSize)size;

/// The arrow beside a call in a chat: down-left for one that came in, up-right
/// for one that went out, red when it was never answered.
+ (UIImage *)callArrowOutgoing:(BOOL)outgoing missed:(BOOL)missed;

/// A line glyph for a row of the pop-up menu, by name: "reply", "forward",
/// "copy", "edit", "delete", "pin", "unpin", "mute", "unmute", "archive",
/// "react". Nil for a name it does not draw, which leaves the row plain.
+ (UIImage *)menuGlyphNamed:(NSString *)name;

+ (UIImage *)settingsIconNamed:(NSString *)name color:(UIColor *)color;

/// Read and decode a downloaded picture off the main thread, then hand it to
/// the view. UIImage's own decode is lazy and lands on the main thread at draw
/// time, which is what made a profile stutter as its pictures arrived.
+ (void)loadImageAtPath:(NSString *)path into:(UIImageView *)view;

/// The same decode without a view to hand it to: call it off the main thread.
/// `fill` covers the box, otherwise the picture is fitted inside it.
+ (UIImage *)decodedImage:(UIImage *)image
			  fittingSize:(CGSize)target
					 fill:(BOOL)fill
					scale:(CGFloat)scale;

/// Drop the cache after a theme change.
+ (void)flush;

@end
