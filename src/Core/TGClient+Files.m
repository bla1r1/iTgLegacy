#import "TGClientInternal.h"

// Note: this file is shared with the host test suite (tests/Makefile compiles
// it into TGClientTests); nothing device-only lives here.

#pragma mark - files

@implementation TGClient (Files)

// The watchdog timing: how long a waiter waits for a download answer, and how
// long a fully expired record may still hope for a late updateFile before the
// sweep retires it. Tunables, because the layout of a slow 3G reply is not
// reproducible in a test otherwise (see tests/TGClientFilesTests.m).
double TGFileWaiterTimeoutSeconds = 45.0;
static const NSTimeInterval TGFileWaiterSweepOffset = 15.0 * 60.0;

/// A waiter is a callback plus whether it has already been served nil by the
/// watchdog. Expired waiters stay in the record: a file that finishes
/// downloading past the timeout still reaches them on the second pass (B2 —
/// before this, the watchdog deleted the record and a late updateFile
/// notified nobody, ever).
typedef void (^TGFileWaiterBlock)(NSString *);

static NSMutableDictionary *TGWaiter(TGFileWaiterBlock cb){
	return [NSMutableDictionary dictionaryWithDictionary:
			@{ @"cb" : (cb ? (id)cb : (id)[NSNull null]), @"expired" : @NO }];
}

/// Delivers a path (or a fatal nil - an error answer) to every waiter of the
/// file and retires the record.
- (void)notifyFileWaiters:(NSInteger)fileId path:(NSString *)path {
	NSMutableArray *callbacks = nil;
	@synchronized(self.fileWaiters){
		NSNumber *fid = @(fileId);
		NSArray *waiters = self.fileWaiters[fid];
		if (!waiters)
			return;
		callbacks = [NSMutableArray array];
		for (NSDictionary *waiter in waiters){
			id cb = waiter[@"cb"];
			if (cb != [NSNull null] && cb)
				[callbacks addObject:cb];
		}
		[self.fileWaiters removeObjectForKey:fid];
		[self.fileWaiterPriorities removeObjectForKey:fid];
	}
	if (!callbacks.count)
		return;

	dispatch_async(dispatch_get_main_queue(), ^{
		for (void (^cb)(NSString *) in callbacks){
			cb(path);
		}
	});
}

/// Serves every waiter that has not run yet with a nil - the timeout reached
/// them - but keeps the record itself alive. A watcher who only stuffed a
/// file id into a "requested" set (the chat list marks its avatars that way)
/// clears the mark on nil and tries again on the next pass, while the
/// download itself keeps going: its late updateFile still calls callbacks.
- (void)expireFileWaiters:(NSInteger)fileId {
	NSMutableArray *callbacks = [NSMutableArray array];
	@synchronized(self.fileWaiters){
		NSArray *waiters = self.fileWaiters[@(fileId)];
		if (!waiters)
			return;
		for (NSMutableDictionary *waiter in waiters){
			if ([waiter[@"expired"] boolValue])
				continue;
			waiter[@"expired"] = @YES;
			id cb = waiter[@"cb"];
			if (cb != [NSNull null] && cb)
				[callbacks addObject:cb];
		}
	}
	if (!callbacks.count)
		return;

	dispatch_async(dispatch_get_main_queue(), ^{
		for (void (^cb)(NSString *) in callbacks){
			cb(nil);
		}
	});
}

/// Retires the record of a file nothing ever came back for, and whose waiters
/// have long since been served nil. A fresh (unexpired) waiter keeps the
/// record - its own watchdog will expire it and schedule another sweep.
- (void)sweepFileWaiters:(NSInteger)fileId {
	@synchronized(self.fileWaiters){
		NSNumber *fid = @(fileId);
		NSArray *waiters = self.fileWaiters[fid];
		if (!waiters)
			return;
		for (NSDictionary *waiter in waiters){
			if (![waiter[@"expired"] boolValue])
				return;   // a live waiter; its sweep comes later
		}
		[self.fileWaiters removeObjectForKey:fid];
		[self.fileWaiterPriorities removeObjectForKey:fid];
	}
}

- (void)downloadFile:(NSInteger)fileId
			priority:(NSInteger)priority
		  completion:(void (^)(NSString *path))completion {
	if (fileId <= 0){
		if (completion) completion(nil);
		return;
	}

	NSNumber *fid = @(fileId);
	BOOL sendRequest = NO;
	BOOL armWatchdog = NO;
	NSInteger storedPriority = 0;
	@synchronized(self.fileWaiters){
		NSMutableArray *waiters = self.fileWaiters[fid];
		if (!waiters){
			waiters = [NSMutableArray array];
			self.fileWaiters[fid] = waiters;
			sendRequest = YES;
			armWatchdog = YES;
			storedPriority = priority;
			self.fileWaiterPriorities[fid] = @(priority);
		} else {
			storedPriority = [self.fileWaiterPriorities[fid] integerValue];
			BOOL allExpired = YES;
			for (NSDictionary *waiter in waiters){
				if (![waiter[@"expired"] boolValue]){
					allExpired = NO;
					break;
				}
			}
			// The same file asked again at a higher rank re-raises the
			// request: TDLib orders its queue by it, which is how an
			// avatar overtakes a grid of photos (B2).
			if (priority > storedPriority){
				storedPriority = priority;
				self.fileWaiterPriorities[fid] = @(priority);
				sendRequest = YES;
			}
			// A retry after every waiter expired re-arms the watchdog - the
			// original timer already fired and cannot expire the newcomer.
			armWatchdog = allExpired;
		}
		if (completion)
			[waiters addObject:TGWaiter(completion)];
	}

	if (sendRequest){
		__weak typeof(self) weakSelf = self;
		[self request:@{
			@"@type"       : @"downloadFile",
			@"file_id"     : fid,
			@"priority"    : @(storedPriority),
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
			// Anything else - a file object whose download is still in
			// progress - is waited for through updateFile updates.
		}];
	}

	// The watchdog arms on the first waiter for a file, and re-arms whenever
	// a fresh waiter lands on a record whose waiters had all expired: the
	// original timer already fired and cannot expire the newcomer.
	if (armWatchdog){
		__weak typeof(self) weakSelf = self;
		dispatch_after(dispatch_time(DISPATCH_TIME_NOW,
				(int64_t)(TGFileWaiterTimeoutSeconds * NSEC_PER_SEC)),
				dispatch_get_main_queue(), ^{
			[weakSelf expireFileWaiters:fileId];
		});

		// The sweep is what keeps an abandoned file - a download that never
		// succeeds and never errors - from holding its record (and its
		// callbacks) in memory forever.
		dispatch_after(dispatch_time(DISPATCH_TIME_NOW,
				(int64_t)((TGFileWaiterTimeoutSeconds
						+ TGFileWaiterSweepOffset) * NSEC_PER_SEC)),
				dispatch_get_main_queue(), ^{
			[weakSelf sweepFileWaiters:fileId];
		});
	}
}

- (void)downloadFile:(NSInteger)fileId completion:(void (^)(NSString *path))completion {
	// Long-standing callers carried the lowest rank; keep their behaviour,
	// and let the paths that show something immediately (avatars, visible
	// grids) ask for more through downloadFile:priority:completion:.
	[self downloadFile:fileId priority:TGDownloadPriorityBackground
			 completion:completion];
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
