//
// TGClient+ProfileAudio.m - the list, its order, and the add/remove calls.
//
#import "TGClient+ProfileAudio.h"
#import "TGClientInternal.h"

static NSString *TGProfileAudioError(NSDictionary *result) {
	if (![result[@"@type"] isEqualToString:@"error"])
		return nil;
	NSString *message = result[@"message"];
	return message.length ? message : @"Telegram refused that.";
}

/// One audio object flattened for a row. The player needs the file id and a
/// title; the row shows the performer and the length as its second line.
static NSDictionary *TGProfileAudioRow(NSDictionary *audio) {
	if (![audio isKindOfClass:NSDictionary.class])
		return nil;
	NSNumber *fileId = audio[@"audio"][@"id"];
	if (![fileId isKindOfClass:NSNumber.class])
		return nil;
	NSNumber *coverId = audio[@"album_cover_thumbnail"][@"file"][@"id"];
	return @{
		@"fileId"       : fileId,
		@"title"        : audio[@"title"] ?: @"",
		@"performer"    : audio[@"performer"] ?: @"",
		@"duration"     : audio[@"duration"] ?: @(0),
		@"fileName"     : audio[@"file_name"] ?: @"",
		@"mimeType"     : audio[@"mime_type"] ?: @"",
		@"albumCoverId" : [coverId isKindOfClass:NSNumber.class]
				? coverId : (id)[NSNull null],
	};
}

@implementation TGClient (ProfileAudio)

- (void)profileAudiosForUser:(int64_t)userId
                      offset:(NSInteger)offset
                       limit:(NSInteger)limit
                  completion:(void (^)(NSArray *, NSInteger, NSString *))completion {
	[self request:@{
		@"@type" : @"getUserProfileAudios",
		@"user_id" : @(userId),
		@"offset" : @(offset),
		@"limit" : @(limit),
	} completion:^(NSDictionary *result){
		NSString *error = TGProfileAudioError(result);
		if (error){
			if (completion)
				completion(@[], 0, error);
			return;
		}
		NSMutableArray *rows = [NSMutableArray array];
		NSArray *audios = result[@"audios"];
		if ([audios isKindOfClass:NSArray.class])
			for (NSDictionary *audio in audios){
				NSDictionary *row = TGProfileAudioRow(audio);
				if (row)
					[rows addObject:row];
			}
		if (completion)
			completion(rows, [result[@"total_count"] integerValue], nil);
	}];
}

- (void)addProfileAudioAtPath:(NSString *)path
                        title:(NSString *)title
                    performer:(NSString *)performer
                     duration:(NSInteger)duration
                   completion:(void (^)(BOOL, NSString *))completion {
	if (!path.length){
		if (completion)
			completion(NO, @"No audio file to add.");
		return;
	}
	NSDictionary *input = @{
		@"@type" : @"inputAudio",
		@"audio" : @{@"@type" : @"inputFileLocal", @"path" : path},
		@"album_cover_thumbnail" : [NSNull null],
		@"duration" : @(duration),
		@"title" : title ?: @"",
		@"performer" : performer ?: @"",
	};
	[self request:@{@"@type" : @"addProfileAudio", @"audio" : input}
	   completion:^(NSDictionary *result){
		if (completion)
			completion(TGProfileAudioError(result) == nil,
					   TGProfileAudioError(result));
	}];
}

- (void)removeProfileAudioFileId:(NSInteger)fileId
                     completion:(void (^)(BOOL, NSString *))completion {
	[self request:@{
		@"@type" : @"removeProfileAudio",
		@"file_id" : @(fileId),
	} completion:^(NSDictionary *result){
		if (completion)
			completion(TGProfileAudioError(result) == nil,
					   TGProfileAudioError(result));
	}];
}

- (void)setProfileAudioFileId:(NSInteger)fileId
                  afterFileId:(NSInteger)afterFileId
                   completion:(void (^)(BOOL, NSString *))completion {
	[self request:@{
		@"@type" : @"setProfileAudioPosition",
		@"file_id" : @(fileId),
		@"after_file_id" : @(afterFileId),
	} completion:^(NSDictionary *result){
		if (completion)
			completion(TGProfileAudioError(result) == nil,
					   TGProfileAudioError(result));
	}];
}

- (void)isProfileAudioFileId:(NSInteger)fileId
                  completion:(void (^)(BOOL, NSString *))completion {
	[self request:@{@"@type" : @"isProfileAudio", @"file_id" : @(fileId)}
	   completion:^(NSDictionary *result){
		NSString *error = TGProfileAudioError(result);
		if (completion)
			completion(error == nil, error);
	}];
}

@end
