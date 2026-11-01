//
// TGClient+ProfileAudio - the music a profile puts above its photos.
//
#import "TGClient+Base.h"

@interface TGClient (ProfileAudio)

/// One page of a user's profile audio. Each entry: "fileId", "title",
/// "performer", "duration", "fileName", "mimeType" and "albumCoverId" (or
/// NSNull). `total` is what Telegram counts for the whole list.
- (void)profileAudiosForUser:(int64_t)userId
                      offset:(NSInteger)offset
                       limit:(NSInteger)limit
                  completion:(void (^)(NSArray *audios, NSInteger total,
                                       NSString *error))completion;

/// Adds a local audio file. TDLib uploads it and puts it at the beginning of
/// the list, which is where Telegram shows the newest.
- (void)addProfileAudioAtPath:(NSString *)path
                        title:(NSString *)title
                    performer:(NSString *)performer
                     duration:(NSInteger)duration
                   completion:(void (^)(BOOL ok, NSString *error))completion;

- (void)removeProfileAudioFileId:(NSInteger)fileId
                     completion:(void (^)(BOOL ok, NSString *error))completion;

/// Moves `fileId` after `afterFileId`; 0 moves it to the beginning.
- (void)setProfileAudioFileId:(NSInteger)fileId
                  afterFileId:(NSInteger)afterFileId
                   completion:(void (^)(BOOL ok, NSString *error))completion;

/// Telegram answers OK when the file is in the list and a 404 otherwise, so
/// both are a real answer and not a failure. `error` is set only for the
/// latter, with the server's wording.
- (void)isProfileAudioFileId:(NSInteger)fileId
                  completion:(void (^)(BOOL isProfileAudio,
                                       NSString *error))completion;

@end
