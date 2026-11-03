#import "TGClientInternal.h"
#import "TGBase64.h"

#include <mutex>
#include <unordered_map>
#include <vector>

/// One pending generation, keyed by its original path. File-scope so the
/// reset on account switch (see -removeAllPendingGenerations) can reach it
/// before the preliminary-upload half of this file declares it again.
static NSMutableDictionary *gPendingGenerations;

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

namespace {

struct TGFileWaiter {
	TGFileWaiterBlock callback;
	bool expired;
};

// Every record used to be an NSNumber key onto an NSMutableArray of
// NSMutableDictionaries holding a block and a boxed BOOL - five objects per
// waiter - under @synchronized on the dictionary itself, which is a global
// recursive lock keyed by object identity. A download reaches this from the
// TDLib receive thread, the watchdog from the main queue, and avatars arrive
// in bursts of dozens. Flat vectors behind one mutex of our own: no boxing,
// no object identity lookup, and the lock is visible in the code that holds
// it.
//
// ponytail: one mutex for the whole table, not one per file. A few hundred
// file ids and three threads never contend; per-id locking if that changes.
std::mutex gWaitersMutex;
std::unordered_map<int32_t, std::vector<TGFileWaiter>> gWaiters;
std::unordered_map<int32_t, int32_t> gPriorities;

}  // namespace

/// Delivers a path (or a fatal nil - an error answer) to every waiter of the
/// file and retires the record.
- (void)notifyFileWaiters:(NSInteger)fileId path:(NSString *)path {
	NSMutableArray *callbacks = nil;
	{
		std::lock_guard<std::mutex> lock(gWaitersMutex);
		auto it = gWaiters.find((int32_t)fileId);
		if (it == gWaiters.end())
			return;
		callbacks = [NSMutableArray arrayWithCapacity:it->second.size()];
		for (const TGFileWaiter &waiter : it->second){
			if (waiter.callback)
				[callbacks addObject:waiter.callback];
		}
		gWaiters.erase(it);
		gPriorities.erase((int32_t)fileId);
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
	{
		std::lock_guard<std::mutex> lock(gWaitersMutex);
		auto it = gWaiters.find((int32_t)fileId);
		if (it == gWaiters.end())
			return;
		for (TGFileWaiter &waiter : it->second){
			if (waiter.expired)
				continue;
			waiter.expired = true;
			if (waiter.callback)
				[callbacks addObject:waiter.callback];
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
	std::lock_guard<std::mutex> lock(gWaitersMutex);
	auto it = gWaiters.find((int32_t)fileId);
	if (it == gWaiters.end())
		return;
	for (const TGFileWaiter &waiter : it->second){
		if (!waiter.expired)
			return;   // a live waiter; its sweep comes later
	}
	gWaiters.erase(it);
	gPriorities.erase((int32_t)fileId);
}

/// Drops the record outright - what a cancelled download leaves behind.
- (void)releaseFileWaiters:(NSInteger)fileId {
	std::lock_guard<std::mutex> lock(gWaitersMutex);
	gWaiters.erase((int32_t)fileId);
	gPriorities.erase((int32_t)fileId);
}

- (void)removeAllFileWaiters {
	std::lock_guard<std::mutex> lock(gWaitersMutex);
	gWaiters.clear();
	gPriorities.clear();
}

- (void)removeAllPendingGenerations {
	[gPendingGenerations removeAllObjects];
}

/// How many waiters a file still has. Zero means no record at all.
- (NSUInteger)fileWaiterCount:(NSInteger)fileId {
	std::lock_guard<std::mutex> lock(gWaitersMutex);
	auto it = gWaiters.find((int32_t)fileId);
	return (it == gWaiters.end()) ? 0 : it->second.size();
}

- (BOOL)hasFileWaiterRecord:(NSInteger)fileId {
	std::lock_guard<std::mutex> lock(gWaitersMutex);
	return gWaiters.find((int32_t)fileId) != gWaiters.end();
}

- (NSInteger)fileWaiterPriority:(NSInteger)fileId {
	std::lock_guard<std::mutex> lock(gWaitersMutex);
	auto it = gPriorities.find((int32_t)fileId);
	return (it == gPriorities.end()) ? 0 : it->second;
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
	{
		std::lock_guard<std::mutex> lock(gWaitersMutex);
		int32_t key = (int32_t)fileId;
		auto it = gWaiters.find(key);
		if (it == gWaiters.end()){
			it = gWaiters.emplace(key, std::vector<TGFileWaiter>()).first;
			sendRequest = YES;
			armWatchdog = YES;
			storedPriority = priority;
			gPriorities[key] = (int32_t)priority;
		} else {
			auto stored = gPriorities.find(key);
			storedPriority = (stored == gPriorities.end()) ? 0 : stored->second;
			BOOL allExpired = YES;
			for (const TGFileWaiter &waiter : it->second){
				if (!waiter.expired){
					allExpired = NO;
					break;
				}
			}
			// The same file asked again at a higher rank re-raises the
			// request: TDLib orders its queue by it, which is how an
			// avatar overtakes a grid of photos (B2).
			if (priority > storedPriority){
				storedPriority = priority;
				gPriorities[key] = (int32_t)priority;
				sendRequest = YES;
			}
			// A retry after every waiter expired re-arms the watchdog - the
			// original timer already fired and cannot expire the newcomer.
			armWatchdog = allExpired;
		}
		if (completion){
			TGFileWaiter waiter;
			waiter.callback = completion;
			waiter.expired = false;
			it->second.push_back(waiter);
		}
	}

	if (sendRequest){
		__weak __typeof__(self) weakSelf = self;
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
		__weak __typeof__(self) weakSelf = self;
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

#pragma mark - file records, names and bytes

/// A text answer from getFileMimeType, getFileExtension, cleanFileName and
/// getSuggestedFileName. Errors are an empty string: the File Info screen
/// still has rows to draw, and a missing MIME is not a failure of the file.
static NSString *TGFileTextAnswer(NSDictionary *result) {
	if (![result isKindOfClass:NSDictionary.class])
		return @"";
	if ([result[@"@type"] isEqualToString:@"error"])
		return @"";
	return [result[@"text"] isKindOfClass:NSString.class] ? result[@"text"] : @"";
}

static NSDictionary *TGFlattenFileRecord(NSDictionary *file) {
	NSDictionary *local = file[@"local"];
	NSDictionary *remote = file[@"remote"];
	if (![local isKindOfClass:NSDictionary.class]) local = @{};
	if (![remote isKindOfClass:NSDictionary.class]) remote = @{};
	return @{
		@"fileId"           : file[@"id"] ?: @(0),
		@"size"             : file[@"size"] ?: @(0),
		@"expectedSize"     : file[@"expected_size"] ?: @(0),
		@"downloadedSize"   : local[@"downloaded_size"] ?: @(0),
		@"localPath"        : local[@"path"] ?: @"",
		@"downloading"      : local[@"is_downloading_active"] ?: @NO,
		@"completed"        : local[@"is_downloading_completed"] ?: @NO,
		@"remoteId"         : remote[@"id"] ?: @"",
		@"remoteUniqueId"   : remote[@"unique_id"] ?: @"",
		@"remoteUploading"  : remote[@"is_uploading_active"] ?: @NO,
		@"remoteUploadedSize" : remote[@"uploaded_size"] ?: @(0),
	};
}

- (void)fileInfo:(NSInteger)fileId completion:(void (^)(NSDictionary *))completion {
	if (fileId <= 0){
		if (completion) completion(nil);
		return;
	}
	[self request:@{@"@type" : @"getFile", @"file_id" : @(fileId)}
	   completion:^(NSDictionary *result){
		if (![result isKindOfClass:NSDictionary.class] ||
			[result[@"@type"] isEqualToString:@"error"]){
			if (completion) completion(nil);
			return;
		}
		NSMutableDictionary *info = [TGFlattenFileRecord(result) mutableCopy];
		NSString *remoteId = info[@"remoteId"];
		if (![remoteId isKindOfClass:NSString.class] || !remoteId.length){
			if (completion) completion(info);
			return;
		}
		// getFile answers with the remote id, not the remote record; the File
		// Info screen's "Remote ID" row is only worth showing if TDLib can
		// still resolve it, so ask and fold the answer back in.
		[self request:@{
			@"@type"          : @"getRemoteFile",
			@"remote_file_id" : remoteId,
			@"file_type"      : @{@"@type" : @"fileTypeUnknown"},
		} completion:^(NSDictionary *remote){
			if ([remote isKindOfClass:NSDictionary.class] &&
				![remote[@"@type"] isEqualToString:@"error"]){
				info[@"remoteResolved"] = @YES;
				info[@"remoteSize"] = remote[@"size"] ?: @(0);
				info[@"remoteExpectedSize"] = remote[@"expected_size"] ?: @(0);
				info[@"remoteUploading"] = remote[@"remote"][@"is_uploading_active"] ?: @NO;
				info[@"remoteUploadedSize"] = remote[@"remote"][@"uploaded_size"] ?: @(0);
			} else {
				info[@"remoteResolved"] = @NO;
			}
			if (completion) completion(info);
		}];
	}];
}

- (void)fileDownloadedPrefixSize:(NSInteger)fileId
						  offset:(long long)offset
					  completion:(void (^)(long long))completion {
	if (fileId <= 0){
		if (completion) completion(0);
		return;
	}
	[self request:@{
		@"@type"   : @"getFileDownloadedPrefixSize",
		@"file_id" : @(fileId),
		@"offset"  : @(offset),
	} completion:^(NSDictionary *result){
		long long bytes = 0;
		if ([result isKindOfClass:NSDictionary.class] &&
			![result[@"@type"] isEqualToString:@"error"])
			bytes = [result[@"size"] longLongValue];
		if (completion) completion(bytes);
	}];
}

- (void)fileNameInfo:(NSString *)name
		  completion:(void (^)(NSDictionary *))completion {
	NSString *value = name ?: @"";
	[self request:@{@"@type" : @"getFileMimeType", @"file_name" : value}
	   completion:^(NSDictionary *mimeAnswer){
		NSString *mime = TGFileTextAnswer(mimeAnswer);
		[self request:@{@"@type" : @"getFileExtension", @"mime_type" : mime}
		   completion:^(NSDictionary *extensionAnswer){
			NSString *extension = TGFileTextAnswer(extensionAnswer);
			[self request:@{@"@type" : @"cleanFileName", @"file_name" : value}
			   completion:^(NSDictionary *cleanAnswer){
				NSDictionary *info = @{
					@"mime"      : mime,
					@"extension" : extension,
					@"cleanName" : TGFileTextAnswer(cleanAnswer),
				};
				if (completion) completion(info);
			}];
		}];
	}];
}

- (void)suggestedFileNameForFile:(NSInteger)fileId
					   directory:(NSString *)directory
					  completion:(void (^)(NSString *))completion {
	if (fileId <= 0){
		if (completion) completion(@"");
		return;
	}
	NSString *folder = directory.length ? directory : NSTemporaryDirectory();
	[self request:@{
		@"@type"     : @"getSuggestedFileName",
		@"file_id"   : @(fileId),
		@"directory" : folder,
	} completion:^(NSDictionary *result){
		if (completion) completion(TGFileTextAnswer(result));
	}];
}

- (void)readFilePartOfFile:(NSInteger)fileId
					offset:(long long)offset
					 count:(NSInteger)count
				completion:(void (^)(NSData *))completion {
	if (fileId <= 0){
		if (completion) completion(nil);
		return;
	}
	[self request:@{
		@"@type"   : @"readFilePart",
		@"file_id" : @(fileId),
		@"offset"  : @(offset),
		@"count"   : @(MAX((NSInteger)0, count)),
	} completion:^(NSDictionary *result){
		NSData *data = nil;
		if ([result isKindOfClass:NSDictionary.class] &&
			[result[@"@type"] isEqualToString:@"data"])
			data = TGBase64Decode(result[@"data"]);
		if (completion) completion(data);
	}];
}

#pragma mark - preliminary upload and generation

/// One pending generation, keyed by its original path. Every field is filled
/// by whichever answer arrives first, and finishGenerationIfReady is what
/// makes the completion run exactly once after both have.
static const NSUInteger TGGenerationChunk = 32 * 1024;

static NSError *TGGenerationError(NSString *reason) {
	return [NSError errorWithDomain:@"LegacyTG.FileGeneration" code:400
						   userInfo:@{NSLocalizedDescriptionKey : reason ?: @"Generation failed"}];
}

/// Runs on the main queue (handleUpdateBatch), like every other screen state.
static void TGGenerationProgress(NSMutableDictionary *pending, NSInteger fileId,
								 float progress, NSString *stage) {
	void (^block)(NSInteger, float, NSString *) = pending[@"progress"];
	if (block)
		block(fileId, progress, stage ?: @"");
}

- (void)finishGenerationIfReady:(NSMutableDictionary *)pending {
	if (![pending[@"generated"] boolValue] || [pending[@"finished"] boolValue])
		return;
	NSInteger fileId = [pending[@"fileId"] integerValue];
	if (fileId <= 0)
		return;   // the preliminary-upload answer still owns the id
	pending[@"finished"] = @YES;

	NSString *path = pending[@"destination"] ?: pending[@"original"];
	TGGenerationProgress(pending, fileId, 1.0f, @"generated");
	void (^done)(NSInteger, NSString *, NSError *) = pending[@"completion"];
	NSString *original = pending[@"original"];
	if (original)
		[gPendingGenerations removeObjectForKey:original];
	if (done)
		done(fileId, path ?: @"", nil);
}

- (void)runGenerationIfReady:(NSMutableDictionary *)pending {
	if ([pending[@"started"] boolValue])
		return;
	id generation = pending[@"generationId"];
	if (![generation isKindOfClass:NSNumber.class] || [generation longLongValue] == 0)
		return;
	pending[@"started"] = @YES;

	long long generationId = [generation longLongValue];
	NSData *data = pending[@"data"] ?: [NSData data];
	long long total = (long long)data.length;
	NSInteger fileId = [pending[@"fileId"] integerValue];

	// Tell TDLib the size before the first part, then one progress report per
	// part as the bytes land. A generated thumbnail is a few KB; a text file
	// this app writes is small, but the same code makes a larger one without
	// holding one giant request in the outbox.
	for (long long offset = 0; offset < total; offset += (long long)TGGenerationChunk){
		NSUInteger length = (NSUInteger)MIN((long long)TGGenerationChunk, total - offset);
		NSData *part = [data subdataWithRange:NSMakeRange((NSUInteger)offset, length)];
		[self send:@{
			@"@type"             : @"setFileGenerationProgress",
			@"generation_id"     : @(generationId),
			@"expected_size"     : @(total),
			@"local_prefix_size" : @(offset),
		}];
		[self send:@{
			@"@type"         : @"writeGeneratedFilePart",
			@"generation_id" : @(generationId),
			@"offset"        : @(offset),
			@"data"          : TGBase64Encode(part),
		}];
		if (total > 0)
			TGGenerationProgress(pending, fileId,
					(float)((offset + (long long)length) / (double)total), @"generating");
	}
	if (total == 0)
		[self send:@{
			@"@type"             : @"setFileGenerationProgress",
			@"generation_id"     : @(generationId),
			@"expected_size"     : @(0),
			@"local_prefix_size" : @(0),
		}];

	[self send:@{
		@"@type"         : @"finishFileGeneration",
		@"generation_id" : @(generationId),
		@"error"         : [NSNull null],
	}];
	pending[@"generated"] = @YES;
	[self finishGenerationIfReady:pending];
}

- (void)handleFileGenerationStart:(NSDictionary *)update {
	NSString *original = update[@"original_path"];
	if (![original isKindOfClass:NSString.class] || !original.length)
		return;
	NSMutableDictionary *pending = gPendingGenerations[original];
	if (!pending)
		return;
	pending[@"generationId"] = update[@"generation_id"] ?: @(0);
	pending[@"destination"] = update[@"destination_path"] ?: @"";
	[self runGenerationIfReady:pending];
}

- (void)handleFileGenerationStop:(NSDictionary *)update {
	NSNumber *generationId = update[@"generation_id"];
	if (![generationId isKindOfClass:NSNumber.class])
		return;
	NSMutableDictionary *found = nil;
	for (NSString *key in gPendingGenerations.allKeys){
		NSMutableDictionary *pending = gPendingGenerations[key];
		if ([pending[@"generationId"] isEqual:generationId]){
			found = pending;
			break;
		}
	}
	if (!found)
		return;
	// A stop that follows our finishFileGeneration is the normal end of the
	// generation, not a failure: the upload still owes a file id, so the
	// pending record waits for that answer.
	if ([found[@"generated"] boolValue])
		return;
	NSString *original = found[@"original"];
	if (original)
		[gPendingGenerations removeObjectForKey:original];
	if (![found[@"finished"] boolValue]){
		found[@"finished"] = @YES;
		void (^done)(NSInteger, NSString *, NSError *) = found[@"completion"];
		if (done)
			done(0, @"", TGGenerationError(@"TDLib stopped the generation."));
	}
}

- (void)handleFileUploadProgress:(NSInteger)fileId file:(NSDictionary *)file {
	if (fileId <= 0)
		return;
	NSMutableDictionary *found = nil;
	for (NSString *key in gPendingGenerations.allKeys){
		NSMutableDictionary *pending = gPendingGenerations[key];
		if ([pending[@"fileId"] integerValue] == fileId){
			found = pending;
			break;
		}
	}
	if (!found)
		return;
	double expected = [file[@"expected_size"] doubleValue];
	if (expected <= 0)
		expected = [found[@"data"] length];
	double uploaded = [file[@"remote"][@"uploaded_size"] doubleValue];
	float fraction = expected > 0 ? (float)(uploaded / expected) : 0;
	TGGenerationProgress(found, fileId, fraction, @"uploading");
}

- (void)generateTextFileNamed:(NSString *)name
					 contents:(NSString *)contents
					 progress:(void (^)(NSInteger, float, NSString *))progress
				   completion:(void (^)(NSInteger, NSString *, NSError *))completion {
	NSString *base = name.lastPathComponent ?: @"legacy-note.txt";
	if (!base.length)
		base = @"legacy-note.txt";
	NSString *extension = base.pathExtension.length ? base.pathExtension : @"txt";
	NSString *unique = [[NSUUID UUID] UUIDString] ?: @"0";
	NSString *original = [[NSTemporaryDirectory()
			stringByAppendingPathComponent:[@"legacy-gen-" stringByAppendingString:unique]]
			stringByAppendingPathExtension:extension];

	NSData *data = [contents ?: @"" dataUsingEncoding:NSUTF8StringEncoding] ?: [NSData data];
	NSMutableDictionary *pending = [@{
		@"original"   : original,
		@"data"       : data,
		@"fileId"     : @(0),
		@"generationId" : @(0),
		@"started"    : @NO,
		@"generated"  : @NO,
		@"finished"   : @NO,
	} mutableCopy];
	if (progress) pending[@"progress"] = [progress copy];
	if (completion) pending[@"completion"] = [completion copy];
	if (!gPendingGenerations)
		gPendingGenerations = [NSMutableDictionary dictionary];
	gPendingGenerations[original] = pending;

	TGGenerationProgress(pending, 0, 0, @"preparing");
	__weak __typeof__(self) weakSelf = self;
	[self request:@{
		@"@type" : @"preliminaryUploadFile",
		@"file"  : @{
			@"@type"         : @"inputFileGenerated",
			@"original_path" : original,
			@"conversion"    : @"legacy-text",
			@"expected_size" : @(data.length),
		},
		@"file_type" : @{@"@type" : @"fileTypeDocument"},
		@"priority"  : @(1),
	} completion:^(NSDictionary *result){
		TGClient *me = weakSelf;
		if (!me) return;
		// A cancel may have retired this record while the answer was on its
		// way; a late answer must not move the screen back to "uploading".
		if (gPendingGenerations[original] != pending ||
			[pending[@"finished"] boolValue])
			return;
		if (![result isKindOfClass:NSDictionary.class] ||
			[result[@"@type"] isEqualToString:@"error"]){
			[gPendingGenerations removeObjectForKey:original];
			if (![pending[@"finished"] boolValue]){
				pending[@"finished"] = @YES;
				void (^done)(NSInteger, NSString *, NSError *) = pending[@"completion"];
				if (done)
					done(0, @"", TGGenerationError(
							result[@"message"] ?: @"Telegram refused the upload."));
			}
			return;
		}
		NSInteger fileId = [result[@"id"] integerValue];
		pending[@"fileId"] = @(fileId);
		TGGenerationProgress(pending, fileId, 0, @"uploading");
		[me finishGenerationIfReady:pending];
	}];
}

- (void)cancelPreliminaryUploadOfFile:(NSInteger)fileId {
	// A file id of 0 means the generation is still in its preparing step and
	// the upload answer has not named one yet. There is at most one such
	// generation per screen, so cancel it rather than leave its completion
	// waiting to fire after the user has walked away.
	if (fileId <= 0){
		NSMutableDictionary *pending = nil;
		for (NSString *key in gPendingGenerations.allKeys){
			NSMutableDictionary *candidate = gPendingGenerations[key];
			if ([candidate[@"fileId"] integerValue] == 0 &&
				![candidate[@"finished"] boolValue]){
				pending = candidate;
				break;
			}
		}
		if (!pending)
			return;
		NSString *original = pending[@"original"];
		if (original)
			[gPendingGenerations removeObjectForKey:original];
		NSNumber *generationId = pending[@"generationId"];
		if ([generationId longLongValue] && ![pending[@"generated"] boolValue]){
			[self send:@{
				@"@type"         : @"finishFileGeneration",
				@"generation_id" : generationId,
				@"error"         : @{@"@type" : @"error", @"code" : @(400),
									 @"message" : @"Cancelled"},
			}];
		}
		if (![pending[@"finished"] boolValue]){
			pending[@"finished"] = @YES;
			void (^done)(NSInteger, NSString *, NSError *) = pending[@"completion"];
			if (done)
				done(0, @"", TGGenerationError(@"Upload cancelled."));
		}
		return;
	}

	[self send:@{@"@type" : @"cancelPreliminaryUploadFile",
				 @"file_id" : @(fileId)}];

	NSMutableDictionary *found = nil;
	for (NSString *key in gPendingGenerations.allKeys){
		NSMutableDictionary *pending = gPendingGenerations[key];
		if ([pending[@"fileId"] integerValue] == fileId){
			found = pending;
			break;
		}
	}
	if (!found)
		return;

	NSString *original = found[@"original"];
	if (original)
		[gPendingGenerations removeObjectForKey:original];
	// A generation in flight has to be told to stop too; cancelling only the
	// upload leaves TDLib waiting for the remaining parts.
	NSNumber *generationId = found[@"generationId"];
	if ([generationId longLongValue] && ![found[@"generated"] boolValue]){
		[self send:@{
			@"@type"         : @"finishFileGeneration",
			@"generation_id" : generationId,
			@"error"         : @{@"@type" : @"error", @"code" : @(400),
								 @"message" : @"Cancelled"},
		}];
	}
	if (![found[@"finished"] boolValue]){
		found[@"finished"] = @YES;
		void (^done)(NSInteger, NSString *, NSError *) = found[@"completion"];
		if (done)
			done(fileId, @"", TGGenerationError(@"Upload cancelled."));
	}
}

#pragma mark - auto-download presets

static NSDictionary *TGFlattenAutoDownloadSettings(NSDictionary *settings) {
	if (![settings isKindOfClass:NSDictionary.class])
		return @{};
	return @{
		@"enabled"         : settings[@"is_auto_download_enabled"] ?: @NO,
		@"maxPhotoSize"    : settings[@"max_photo_file_size"] ?: @(0),
		@"maxVideoSize"    : settings[@"max_video_file_size"] ?: @(0),
		@"maxOtherSize"    : settings[@"max_other_file_size"] ?: @(0),
		@"preloadVideos"   : settings[@"preload_large_videos"] ?: @NO,
		@"preloadAudio"    : settings[@"preload_next_audio"] ?: @NO,
		@"lessDataForCalls" : settings[@"use_less_data_for_calls"] ?: @NO,
	};
}

- (void)autoDownloadSettingsPresetsWithCompletion:(void (^)(NSDictionary *))completion {
	[self request:@{@"@type" : @"getAutoDownloadSettingsPresets"}
	   completion:^(NSDictionary *result){
		if (![result isKindOfClass:NSDictionary.class] ||
			[result[@"@type"] isEqualToString:@"error"]){
			if (completion) completion(nil);
			return;
		}
		NSDictionary *presets = @{
			@"low"    : TGFlattenAutoDownloadSettings(result[@"low"]),
			@"medium" : TGFlattenAutoDownloadSettings(result[@"medium"]),
			@"high"   : TGFlattenAutoDownloadSettings(result[@"high"]),
		};
		if (completion) completion(presets);
	}];
}

- (void)applyAutoDownloadPreset:(NSDictionary *)preset
					 forNetwork:(NSString *)network
					 completion:(void (^)(BOOL))completion {
	if (![preset isKindOfClass:NSDictionary.class]){
		if (completion) completion(NO);
		return;
	}
	NSString *networkType = @"networkTypeWiFi";
	if ([network isEqualToString:@"mobile"])
		networkType = @"networkTypeMobile";
	else if ([network isEqualToString:@"roaming"])
		networkType = @"networkTypeMobileRoaming";

	NSDictionary *settings = @{
		@"@type"                    : @"autoDownloadSettings",
		@"is_auto_download_enabled" : preset[@"enabled"] ?: @NO,
		@"max_photo_file_size"      : preset[@"maxPhotoSize"] ?: @(0),
		@"max_video_file_size"      : preset[@"maxVideoSize"] ?: @(0),
		@"max_other_file_size"      : preset[@"maxOtherSize"] ?: @(0),
		@"video_upload_bitrate"     : @(0),
		@"preload_large_videos"     : preset[@"preloadVideos"] ?: @NO,
		@"preload_next_audio"       : preset[@"preloadAudio"] ?: @NO,
		@"preload_stories"          : @NO,
		@"use_less_data_for_calls"  : preset[@"lessDataForCalls"] ?: @NO,
	};
	[self request:@{
		@"@type"    : @"setAutoDownloadSettings",
		@"settings" : settings,
		@"type"     : @{@"@type" : networkType},
	} completion:^(NSDictionary *result){
		if (completion)
			completion(![result[@"@type"] isEqualToString:@"error"]);
	}];
}

@end
