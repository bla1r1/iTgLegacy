#import "TGClientInternal.h"

@implementation TGClient (Files)

#pragma mark - files

- (void)notifyFileWaiters:(NSInteger)fileId path:(NSString *)path {
	NSNumber *fid = @(fileId);
	NSArray *callbacks = nil;
	@synchronized(self.fileWaiters){
		callbacks = [self.fileWaiters[fid] copy];
		[self.fileWaiters removeObjectForKey:fid];
	}
	if (!callbacks.count)
		return;

	dispatch_async(dispatch_get_main_queue(), ^{
		for (void (^cb)(NSString *) in callbacks){
			cb(path);
		}
	});
}

- (void)downloadFile:(NSInteger)fileId completion:(void (^)(NSString *))completion {
	if (fileId <= 0){
		if (completion) completion(nil);
		return;
	}

	NSNumber *fid = @(fileId);
	BOOL firstWaiter = NO;
	@synchronized(self.fileWaiters){
		NSMutableArray *waiters = self.fileWaiters[fid];
		if (!waiters){
			waiters = [NSMutableArray array];
			self.fileWaiters[fid] = waiters;
			firstWaiter = YES;
		}
		if (completion){
			[waiters addObject:[completion copy]];
		}
	}

	if (!firstWaiter)
		return;

	__weak typeof(self) weakSelf = self;
	[self request:@{
		@"@type"       : @"downloadFile",
		@"file_id"     : fid,
		@"priority"    : @(1),
		@"offset"      : @(0),
		@"limit"       : @(0),
		@"synchronous" : @NO,
	} completion:^(NSDictionary *result){
		TGClient *me = weakSelf;
		if (!me) return;
		NSString *path = result[@"local"][@"path"];
		BOOL done = [result[@"local"][@"is_downloading_completed"] boolValue];
		if (done && path.length){
			[me notifyFileWaiters:fileId path:path];
		} else if ([result[@"@type"] isEqualToString:@"error"]){
			[me notifyFileWaiters:fileId path:nil];
		}
	}];

	dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(45 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
		[weakSelf notifyFileWaiters:fileId path:nil];
	});
}

#pragma mark - network and downloads

- (void)networkStatsWithCompletion:(void (^)(long long, long long))completion {
	[self request:@{@"@type" : @"getNetworkStatistics", @"only_current" : @NO}
	   completion:^(NSDictionary *stats){
		long long sent = 0, received = 0;
		for (NSDictionary *entry in stats[@"entries"]){
			sent     += [entry[@"sent_bytes"] longLongValue];
			received += [entry[@"received_bytes"] longLongValue];
		}
		if (completion) completion(sent, received);
	}];
}

- (void)resetNetworkStats {
	[self send:@{@"@type" : @"resetNetworkStatistics"}];
}

/// TDLib only offers presets through getAutoDownloadSettingsPresets; what is
/// actually in force is not readable back, so the app keeps the answer it
/// wrote. Off over mobile by default: this is a 3G phone with a small disk.
- (BOOL)autoDownloadOverMobile {
	NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
	return [defaults objectForKey:@"TGAutoDownloadMobile"]
			? [defaults boolForKey:@"TGAutoDownloadMobile"] : NO;
}

- (BOOL)autoDownloadOverWifi {
	NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
	return [defaults objectForKey:@"TGAutoDownloadWifi"]
			? [defaults boolForKey:@"TGAutoDownloadWifi"] : YES;
}

- (void)setAutoDownloadOverMobile:(BOOL)mobile wifi:(BOOL)wifi {
	NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
	[defaults setBool:mobile forKey:@"TGAutoDownloadMobile"];
	[defaults setBool:wifi forKey:@"TGAutoDownloadWifi"];
	[defaults synchronize];

	// "Off" here means off in TDLib too, not merely hidden in the interface.
	NSDictionary *(^settingsFor)(BOOL) = ^NSDictionary *(BOOL enabled){
		return @{
			@"@type"                    : @"autoDownloadSettings",
			@"is_auto_download_enabled" : @(enabled),
			@"max_photo_file_size"      : @(10 * 1024 * 1024),
			@"max_video_file_size"      : @(10 * 1024 * 1024),
			@"max_other_file_size"      : @(10 * 1024 * 1024),
			@"video_upload_bitrate"     : @(0),
			@"preload_large_videos"     : @NO,
			@"preload_next_audio"       : @NO,
			@"use_less_data_for_calls"  : @YES,
		};
	};
	[self send:@{@"@type" : @"setAutoDownloadSettings", @"settings" : settingsFor(mobile),
				 @"type"  : @{@"@type" : @"networkTypeMobile"}}];
	[self send:@{@"@type" : @"setAutoDownloadSettings", @"settings" : settingsFor(wifi),
				 @"type"  : @{@"@type" : @"networkTypeWiFi"}}];
}

#pragma mark - storage

- (void)storageStatsWithCompletion:(void (^)(long long, NSInteger))completion {
	[self request:@{@"@type" : @"getStorageStatisticsFast"}
	   completion:^(NSDictionary *stats){
		if (completion)
			completion([stats[@"files_size"] longLongValue],
					   [stats[@"file_count"] integerValue]);
	}];
}

- (void)clearCacheOfTypes:(NSArray *)kinds completion:(void (^)(long long))completion {
	NSMutableArray *types = [NSMutableArray array];
	for (NSString *kind in kinds)
		[types addObject:@{@"@type" : kind}];

	// count/ttl/size of -1 mean "no limit of that sort", so only the file
	// types listed decide what goes.
	[self request:@{
		@"@type"          : @"optimizeStorage",
		@"size"           : @(-1),
		@"ttl"            : @(-1),
		@"count"          : @(-1),
		@"immunity_delay" : @(0),
		@"file_types"     : types,
		@"chat_ids"       : @[],
		@"exclude_chat_ids" : @[],
		@"return_deleted_file_statistics" : @YES,
		@"chat_limit"     : @(0),
	} completion:^(NSDictionary *stats){
		long long freed = 0;
		for (NSDictionary *byChat in stats[@"by_chat"])
			for (NSDictionary *byType in byChat[@"by_file_type"])
				freed += [byType[@"size"] longLongValue];
		if (completion) completion(freed);
	}];
}

/// Computes storage breakdown by file category and returns total bytes.
- (void)storageBreakdownWithCompletion:(void (^)(NSArray *, long long))completion {
	// The categories their page shows, and the TDLib file types under each.
	static NSArray *groups = nil;
	if (!groups)
		groups = @[
			@[@"Photos",   @[@"fileTypePhoto", @"fileTypeProfilePhoto", @"fileTypeThumbnail"]],
			@[@"Video",    @[@"fileTypeVideo", @"fileTypeVideoNote", @"fileTypeAnimation"]],
			@[@"Stickers", @[@"fileTypeSticker"]],
			@[@"Music",    @[@"fileTypeAudio", @"fileTypeVoiceNote"]],
			@[@"Files",    @[@"fileTypeDocument"]],
		];

	[self request:@{@"@type" : @"getStorageStatistics", @"chat_limit" : @(256)}
	   completion:^(NSDictionary *stats){
		NSMutableDictionary *bytesByType = [NSMutableDictionary dictionary];
		for (NSDictionary *chat in stats[@"by_chat"]){
			for (NSDictionary *entry in chat[@"by_file_type"]){
				NSString *type = entry[@"file_type"][@"@type"];
				if (!type) continue;
				long long previous = [bytesByType[type] longLongValue];
				bytesByType[type] = @(previous + [entry[@"size"] longLongValue]);
			}
		}

		long long total = [stats[@"size"] longLongValue];
		long long accounted = 0;
		NSMutableArray *out = [NSMutableArray array];
		for (NSArray *group in groups){
			long long bytes = 0;
			for (NSString *kind in group[1])
				bytes += [bytesByType[kind] longLongValue];
			accounted += bytes;
			if (bytes > 0)
				[out addObject:@{@"name" : group[0], @"bytes" : @(bytes),
								 @"kinds" : group[1]}];
		}

		// Whatever the walk did not attribute is still on the disk, and a chart
		// that silently drops it does not add up to the number above it.
		if (total > accounted)
			[out addObject:@{@"name"  : @"Other",
							 @"bytes" : @(total - accounted),
							 @"kinds" : @[]}];

		[out sortUsingComparator:^NSComparisonResult(NSDictionary *a, NSDictionary *b){
			long long x = [a[@"bytes"] longLongValue], y = [b[@"bytes"] longLongValue];
			return x > y ? NSOrderedAscending : (x < y ? NSOrderedDescending : NSOrderedSame);
		}];
		if (completion) completion(out, total);
	}];
}

- (void)clearLocalDatabase {
	// Wipes cached chats/messages but keeps the session.
	[self send:@{@"@type" : @"optimizeStorage", @"chat_limit" : @(0)}];
	[self.chatsById removeAllObjects];
	[self rebuildChats];
}

@end
