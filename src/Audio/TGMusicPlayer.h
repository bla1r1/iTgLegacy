//
// TGMusicPlayer - music from a chat, played the way a music player plays it.
//
// Audio used to go through the same path as a voice note: one file, decoded,
// played, and when it ended everything stopped. A track is not a voice note -
// it has a name and a performer, it belongs to a run of other tracks in the
// same chat, and leaving the app is not a reason to stop it.
//
// So this owns a queue, moves through it, keeps playing in the background, and
// puts what is playing on the lock screen where the buttons there can reach it.
//
#import <Foundation/Foundation.h>
#import <CoreGraphics/CoreGraphics.h>   // CGFloat

extern NSString *const TGMusicPlayerChangedNotification;

@interface TGMusicPlayer : NSObject

+ (instancetype)shared;

/// Play `index` of `tracks`, which are flattened messages of kind
/// "messageAudio" in the order they appear in the chat.
- (void)playTracks:(NSArray *)tracks atIndex:(NSInteger)index inChat:(int64_t)chatId;

- (void)togglePlayPause;
- (void)next;
- (void)previous;
- (void)stop;
/// 0..1 along the current track.
- (void)seekToFraction:(CGFloat)fraction;

/// Nil when nothing is playing. The flattened message of the current track.
@property (nonatomic, readonly) NSDictionary *current;
@property (nonatomic, readonly) BOOL playing;
@property (nonatomic, readonly) NSTimeInterval duration;
@property (nonatomic, readonly) NSTimeInterval position;
/// The message id being played, or 0 - so a chat can mark the right row.
@property (nonatomic, readonly) int64_t currentMessageId;

@end
