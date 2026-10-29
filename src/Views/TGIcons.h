//
// TGIcons - vector-drawn iconography adapting to TGTheme styling.
//
#import <UIKit/UIKit.h>

@interface TGIcons : NSObject

+ (UIImage *)chats;        ///< tab bar
+ (UIImage *)contacts;
+ (UIImage *)settings;
/// The same three as outlines, for the tabs that are not selected (iOS 7+).
+ (UIImage *)chatsOutline;
+ (UIImage *)contactsOutline;
+ (UIImage *)settingsOutline;

+ (UIImage *)compose;      ///< new message
+ (UIImage *)send;
+ (UIImage *)attach;
+ (UIImage *)play;         ///< over video thumbnails
+ (UIImage *)pause;
+ (UIImage *)previousTrack;  ///< the player strip's queue
+ (UIImage *)nextTrack;
+ (UIImage *)repeatModeIcon:(NSInteger)mode;
+ (UIImage *)shuffleIconActive:(BOOL)active;
+ (UIImage *)volumeMin;
+ (UIImage *)volumeMax;
+ (UIImage *)queueList;
+ (UIImage *)chevronDown;
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

/// The same microphone with a line through it, for a muted call.
+ (UIImage *)microphoneOffOfSide:(CGFloat)side colour:(UIColor *)colour;

/// The padlock on the recorder's lock capsule, drawn rather than set as an
/// emoji - iOS 7 has no colour glyph for it on every device.
+ (UIImage *)lockOfSide:(CGFloat)side colour:(UIColor *)colour;

/// The bars of a voice message, drawn from TDLib's five-bits-per-sample
/// waveform. `played` is how much of it has been listened to, 0 to 1.
+ (UIImage *)waveform:(NSData *)waveform size:(CGSize)size
               played:(CGFloat)played colour:(UIColor *)colour;

/// The tail Telegram hangs off the bottom corner of the last bubble in a run,
/// kTailWidth x kTailHeight; it sits flush against the bubble's edge.
+ (UIImage *)bubbleTailForColour:(UIColor *)colour outgoing:(BOOL)outgoing;
+ (UIImage *)bubbleTailForColour:(UIColor *)colour outgoing:(BOOL)outgoing borderColour:(UIColor *)borderColour;

/// Skeuomorphic metallic silver chevron accessory for grouped table cards.
+ (UIImage *)skeuomorphicDisclosureChevron;
+ (UIImage *)skeuomorphicDisclosureChevronHighlighted;

/// Delivery ticks, drawn the way Telegram draws them: two checks overlapping
/// into one mark, not two separate glyphs side by side.
+ (UIImage *)ticksWhite:(BOOL)white;
/// One check for sent, two for read, in a given colour.
+ (UIImage *)ticksColour:(UIColor *)colour read:(BOOL)read;
+ (UIImage *)selectionCheckboxSelected:(BOOL)selected;

/// The arrow beside a call in a chat: down-left for one that came in, up-right
/// for one that went out, red when it was never answered.
+ (UIImage *)callArrowOutgoing:(BOOL)outgoing missed:(BOOL)missed;

/// Vector search magnifying lens
+ (UIImage *)searchLensOfSize:(CGFloat)size colour:(UIColor *)colour;

/// Custom back chevron for navigation bars
+ (UIImage *)backChevronWithColour:(UIColor *)colour;

/// Phone call handset icon
+ (UIImage *)phoneCall;

/// Official Telegram paper airplane icon
+ (UIImage *)telegramAirplaneOfSide:(CGFloat)size;

/// Verification checkmark badge for channels/bots
+ (UIImage *)verifiedBadge;

/// Empty state vector illustrations
+ (UIImage *)emptyChatsIllustration;
+ (UIImage *)emptyContactsIllustration;
+ (UIImage *)emptySearchIllustration;

/// Drop the cache after a theme change.
+ (void)flush;

@end

@interface TGIcons (Menu)

/// A line glyph for a row of the pop-up menu, by name: "reply", "forward",
/// "copy", "edit", "delete", "pin", "unpin", "mute", "unmute", "archive",
/// "react". Nil for a name it does not draw, which leaves the row plain.
+ (UIImage *)menuGlyphNamed:(NSString *)name;

+ (UIImage *)settingsIconNamed:(NSString *)name color:(UIColor *)color;

/// A menu glyph filled in one colour at a given side. Template tinting does
/// not exist before iOS 7, so a list that needs a grey glyph draws it grey.
+ (UIImage *)glyphNamed:(NSString *)name colour:(UIColor *)colour side:(CGFloat)side;

@end

@interface TGIcons (Avatars)

/// The two rows that stand above the chat list draw a glyph, not a letter:
/// a filled archive box, and the bookmark Telegram uses for Saved Messages.
+ (UIImage *)archiveAvatarOfSide:(CGFloat)side;
+ (UIImage *)savedMessagesAvatarOfSide:(CGFloat)side;

/// Circular avatar with initials, for chats and contacts without a photo.
+ (UIImage *)avatarWithInitials:(NSString *)initials
                           size:(CGFloat)size
                       colourId:(int64_t)colourId;

/// The colour of a name in a group, picked the same way as the placeholder
/// avatar so a sender's name and picture always match.
+ (UIColor *)nameColourForId:(int64_t)colourId dark:(BOOL)dark;

+ (UIImage *)mapPinBadge;
+ (UIImage *)mapPlaceholderSize:(CGSize)size;

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

@end
