//
// TGClient+Downloads.m - the download manager, and the two things a download
// could not do: stop, and go away.
//
// Downloading worked from the first day (TGClient+Files). What had no request
// at all was cancelling one, deleting the file afterwards, and the list
// Telegram keeps of everything this account has pulled down.
//
#import "TGClientInternal.h"

@implementation TGClient (Downloads)

/// Stops a download. `onlyIfPending` leaves one that has already started
/// alone, which is what a list sweep wants; a user's Cancel does not.
- (void)cancelDownloadOfFile:(NSInteger)fileId onlyIfPending:(BOOL)onlyIfPending {
	[self send:@{
		@"@type"           : @"cancelDownloadFile",
		@"file_id"         : @(fileId),
		@"only_if_pending" : @(onlyIfPending),
	}];
	// The waiter records in +Files outlive the request otherwise, and every
	// caller of downloadFile: would sit there until the watchdog fired.
	[self.fileWaiters removeObjectForKey:@(fileId)];
	[self.fileWaiterPriorities removeObjectForKey:@(fileId)];
}

/// Deletes the local copy. The file stays on Telegram and can be fetched
/// again; this is what frees the disk.
- (void)deleteLocalFile:(NSInteger)fileId {
	[self send:@{@"@type" : @"deleteFile", @"file_id" : @(fileId)}];
}

/// Puts a file in the download list, which is what their Download Manager
/// shows. A file pulled down by downloadFile: alone never appears there.
- (void)addFileToDownloads:(NSInteger)fileId
					inChat:(int64_t)chatId
				   message:(int64_t)messageId {
	[self send:@{
		@"@type"      : @"addFileToDownloads",
		@"file_id"    : @(fileId),
		@"chat_id"    : @(chatId),
		@"message_id" : @(messageId),
		@"priority"   : @(1),
	}];
}

/// The download list. Entries carry "fileId", "name", "size", "paused" and
/// "done"; `activeOnly` is the "in progress" tab of their manager.
- (void)fileDownloadsMatching:(NSString *)query
				   activeOnly:(BOOL)activeOnly
				   completion:(void (^)(NSArray *downloads,
										NSInteger activeCount))completion {
	[self request:@{
		@"@type"          : @"searchFileDownloads",
		@"query"          : query ?: @"",
		@"only_active"    : @(activeOnly),
		@"only_completed" : @NO,
		@"offset"         : @"",
		@"limit"          : @(50),
	} completion:^(NSDictionary *result){
		NSMutableArray *out = [NSMutableArray array];
		for (NSDictionary *download in result[@"files"]){
			NSDictionary *message = download[@"message"];
			NSDictionary *document = message[@"content"][@"document"]
					?: message[@"content"][@"audio"]
					?: message[@"content"][@"video"];
			NSDictionary *file = document[@"document"] ?: document[@"audio"]
					?: document[@"video"];
			NSString *name = document[@"file_name"];
			if (!name.length)
				name = message[@"content"][@"caption"][@"text"];
			[out addObject:@{
				@"fileId" : download[@"file_id"] ?: @(0),
				@"name"   : name.length ? name : @"File",
				@"size"   : file[@"size"] ?: @(0),
				@"paused" : download[@"is_paused"] ?: @NO,
				@"done"   : @([download[@"complete_date"] integerValue] > 0),
			}];
		}
		if (completion)
			completion(out, [result[@"total_counts"][@"active_count"] integerValue]);
	}];
}

- (void)setDownloadOfFile:(NSInteger)fileId paused:(BOOL)paused {
	[self send:@{@"@type" : @"toggleDownloadIsPaused",
				 @"file_id" : @(fileId), @"is_paused" : @(paused)}];
}

- (void)setAllDownloadsPaused:(BOOL)paused {
	[self send:@{@"@type" : @"toggleAllDownloadsArePaused",
				 @"are_paused" : @(paused)}];
}

/// Out of the list. `deleteFromCache` also frees the disk, which is the only
/// version of this worth offering on a phone with 8 GB in it.
- (void)removeFileFromDownloads:(NSInteger)fileId deleteFromCache:(BOOL)deleteFromCache {
	[self send:@{@"@type" : @"removeFileFromDownloads",
				 @"file_id" : @(fileId),
				 @"delete_from_cache" : @(deleteFromCache)}];
}

- (void)clearDownloadsDeletingFromCache:(BOOL)deleteFromCache {
	[self send:@{@"@type" : @"removeAllFilesFromDownloads",
				 @"only_active"    : @NO,
				 @"only_completed" : @NO,
				 @"delete_from_cache" : @(deleteFromCache)}];
}

@end

// vim:ft=objc
