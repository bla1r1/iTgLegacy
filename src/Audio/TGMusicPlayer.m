#import "TGMusicPlayer.h"
#import "TGClient.h"
#import "TGIcons.h"
#import <AVFoundation/AVFoundation.h>
#import <MediaPlayer/MediaPlayer.h>
#import <UIKit/UIKit.h>

NSString *const TGMusicPlayerChangedNotification = @"TGMusicPlayerChanged";

@interface TGMusicPlayer () <AVAudioPlayerDelegate>
@property (nonatomic, strong) AVAudioPlayer *player;
@property (nonatomic, strong) NSArray *tracks;
@property (nonatomic, assign) NSInteger index;
@property (nonatomic, assign) int64_t chatId;
@property (nonatomic, strong) NSDictionary *current;
@property (nonatomic, assign) UIBackgroundTaskIdentifier backgroundTask;
@end

@implementation TGMusicPlayer

+ (instancetype)shared {
	static TGMusicPlayer *s = nil;
	static dispatch_once_t once;
	dispatch_once(&once, ^{ s = [[TGMusicPlayer alloc] init]; });
	return s;
}

- (id)init {
	if ((self = [super init])){
		_index = NSNotFound;
		_backgroundTask = UIBackgroundTaskInvalid;
	}
	return self;
}

#pragma mark - queue

- (void)playTracks:(NSArray *)tracks atIndex:(NSInteger)index inChat:(int64_t)chatId {
	// Only the audio, in the order the chat has it: the queue is "the rest of
	// the music in this conversation", which is what a client means by next.
	NSMutableArray *queue = [NSMutableArray array];
	NSInteger adjusted = 0;
	for (NSUInteger i = 0; i < tracks.count; i++){
		if (![tracks[i][@"kind"] isEqualToString:@"messageAudio"])
			continue;
		if ((NSInteger)i <= index)
			adjusted = queue.count;
		[queue addObject:tracks[i]];
	}
	if (!queue.count)
		return;

	self.tracks = queue;
	self.chatId = chatId;
	[self playIndex:MIN(MAX(adjusted, 0), (NSInteger)queue.count - 1)];
}

- (void)playIndex:(NSInteger)index {
	if (index < 0 || index >= (NSInteger)self.tracks.count){
		[self stop];
		return;
	}

	self.index = index;
	self.current = self.tracks[index];
	[self announce];

	NSNumber *docId = self.current[@"docId"];
	if (![docId isKindOfClass:NSNumber.class]){
		[self next];
		return;
	}

	__weak typeof(self) weakSelf = self;
	NSInteger wanted = index;
	[[TGClient shared] downloadFile:docId.integerValue completion:^(NSString *path){
		TGMusicPlayer *me = weakSelf;
		// The user may have skipped on while this was downloading.
		if (!me || me.index != wanted)
			return;
		if (!path.length){
			[me next];
			return;
		}
		[me startFile:path];
	}];
}

- (void)startFile:(NSString *)path {
	[self.player stop];

	NSError *err = nil;
	// Playback, not ambient: this has to keep going with the screen off, which
	// is the whole difference between a track and a voice note.
	[[AVAudioSession sharedInstance] setCategory:AVAudioSessionCategoryPlayback error:nil];
	[[AVAudioSession sharedInstance] setActive:YES error:nil];

	self.player = [[AVAudioPlayer alloc] initWithContentsOfURL:
			[NSURL fileURLWithPath:path] error:&err];
	if (!self.player){
		NSLog(@"music: cannot play %@: %@", path.lastPathComponent, err);
		[self next];
		return;
	}
	self.player.delegate = self;
	self.player.enableRate = YES;
	[self.player play];

	[[UIApplication sharedApplication] beginReceivingRemoteControlEvents];
	[self holdBackground];
	[self announce];
}

#pragma mark - transport

- (void)togglePlayPause {
	if (!self.player)
		return;
	if (self.player.playing)
		[self.player pause];
	else
		[self.player play];
	[self announce];
}

- (void)next {
	[self playIndex:self.index + 1];
}

- (void)previous {
	// Their previous restarts the track first and only steps back when it has
	// barely begun, which is what every player does.
	if (self.player && self.player.currentTime > 3.0){
		self.player.currentTime = 0;
		[self announce];
		return;
	}
	[self playIndex:self.index - 1];
}

- (void)seekToFraction:(CGFloat)fraction {
	if (!self.player)
		return;
	self.player.currentTime = MIN(MAX(fraction, 0.0f), 1.0f) * self.player.duration;
	[self announce];
}

- (void)stop {
	[self.player stop];
	self.player = nil;
	self.current = nil;
	self.index = NSNotFound;
	self.tracks = nil;
	[[UIApplication sharedApplication] endReceivingRemoteControlEvents];
	[self releaseBackground];
	[self clearNowPlaying];
	[[NSNotificationCenter defaultCenter]
			postNotificationName:TGMusicPlayerChangedNotification object:nil];
}

- (void)audioPlayerDidFinishPlaying:(AVAudioPlayer *)player successfully:(BOOL)ok {
	[self next];
}

#pragma mark - state

- (BOOL)playing            { return self.player.playing; }
- (NSTimeInterval)duration { return self.player ? self.player.duration : 0; }
- (NSTimeInterval)position { return self.player ? self.player.currentTime : 0; }
- (int64_t)currentMessageId { return [self.current[@"id"] longLongValue]; }

- (NSString *)titleForTrack:(NSDictionary *)track {
	NSString *title = track[@"audioTitle"];
	if (title.length)
		return title;
	NSString *name = track[@"docName"];
	return name.length ? name : @"Audio";
}

- (NSString *)performerForTrack:(NSDictionary *)track {
	NSString *performer = track[@"audioPerformer"];
	return performer.length ? performer : @"Unknown artist";
}

- (void)announce {
	[self updateNowPlaying];
	[[NSNotificationCenter defaultCenter]
			postNotificationName:TGMusicPlayerChangedNotification object:nil];
}

#pragma mark - lock screen

/// MPNowPlayingInfoCenter is what puts the title, the artist and the position
/// on the lock screen and behind the double-tap tray on this OS.
- (void)updateNowPlaying {
	if (!self.current)
		return;
	MPNowPlayingInfoCenter *centre = [MPNowPlayingInfoCenter defaultCenter];

	NSMutableDictionary *info = [@{
		MPMediaItemPropertyTitle  : [self titleForTrack:self.current],
		MPMediaItemPropertyArtist : [self performerForTrack:self.current],
		MPMediaItemPropertyPlaybackDuration : @(self.duration),
		MPNowPlayingInfoPropertyElapsedPlaybackTime : @(self.position),
		MPNowPlayingInfoPropertyPlaybackRate : @(self.playing ? 1.0 : 0.0),
	} mutableCopy];

	NSNumber *coverId = self.current[@"albumCoverId"];
	if ([coverId isKindOfClass:NSNumber.class]){
		__weak typeof(self) weakSelf = self;
		int64_t forMessage = self.currentMessageId;
		[[TGClient shared] downloadFile:coverId.integerValue completion:^(NSString *path){
			TGMusicPlayer *me = weakSelf;
			if (!me || me.currentMessageId != forMessage || !path.length)
				return;
			UIImage *cover = [UIImage imageWithContentsOfFile:path];
			if (!cover)
				return;
			MPNowPlayingInfoCenter *now = [MPNowPlayingInfoCenter defaultCenter];
			NSMutableDictionary *withArt = now.nowPlayingInfo
					? [now.nowPlayingInfo mutableCopy] : [NSMutableDictionary dictionary];
			withArt[MPMediaItemPropertyArtwork] =
					[[MPMediaItemArtwork alloc] initWithImage:cover];
			now.nowPlayingInfo = withArt;
		}];
	}

	centre.nowPlayingInfo = info;
}

- (void)clearNowPlaying {
	[MPNowPlayingInfoCenter defaultCenter].nowPlayingInfo = nil;
}

#pragma mark - background

/// Info.plist declares the audio background mode, which is what actually keeps
/// the sound going. The task is only so the app is not suspended between one
/// track finishing and the next one being fetched.
- (void)holdBackground {
	if (self.backgroundTask != UIBackgroundTaskInvalid)
		return;
	__weak typeof(self) weakSelf = self;
	self.backgroundTask = [[UIApplication sharedApplication]
			beginBackgroundTaskWithExpirationHandler:^{ [weakSelf releaseBackground]; }];
}

- (void)releaseBackground {
	if (self.backgroundTask == UIBackgroundTaskInvalid)
		return;
	[[UIApplication sharedApplication] endBackgroundTask:self.backgroundTask];
	self.backgroundTask = UIBackgroundTaskInvalid;
}

@end

// vim:ft=objc
