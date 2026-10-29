//
// TGMusicPlayer - music player with queue management, background audio, and lock screen controls.
//
#import <UIKit/UIKit.h>
#import <CoreGraphics/CoreGraphics.h>   // CGFloat

extern NSString *const TGMusicPlayerChangedNotification;

typedef NS_ENUM(NSInteger, TGMusicRepeatMode) {
    TGMusicRepeatOff = 0,
    TGMusicRepeatAll = 1,
    TGMusicRepeatOne = 2
};

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

- (void)cycleRepeatMode;
- (void)toggleShuffle;

/// Nil when nothing is playing. The flattened message of the current track.
@property (nonatomic, readonly) NSDictionary *current;
@property (nonatomic, readonly) BOOL playing;
@property (nonatomic, readonly) NSTimeInterval duration;
@property (nonatomic, readonly) NSTimeInterval position;
/// The message id being played, or 0 - so a chat can mark the right row.
@property (nonatomic, readonly) int64_t currentMessageId;

@property (nonatomic, assign) TGMusicRepeatMode repeatMode;
@property (nonatomic, assign) BOOL shuffle;
@property (nonatomic, readonly) NSArray *tracks;
@property (nonatomic, readonly) NSInteger index;
@property (nonatomic, strong, readonly) UIImage *currentArtwork;
@property (nonatomic, copy, readonly) NSString *currentArtworkPath;
@property (nonatomic, assign) float volume;

@end
