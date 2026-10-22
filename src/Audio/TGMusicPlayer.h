//
// TGMusicPlayer - music player with queue management, background audio, and lock screen controls.
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
