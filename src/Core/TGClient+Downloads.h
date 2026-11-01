//
// TGClient+Downloads.h - the client surface for the download manager: cancelling, deleting, the download list.
//
#import "TGClient+Base.h"

@interface TGClient (Downloads)

/// Stops a download. `onlyIfPending` leaves one that has already started.
- (void)cancelDownloadOfFile:(NSInteger)fileId onlyIfPending:(BOOL)onlyIfPending;

/// Deletes the local copy; the file can be fetched again.
- (void)deleteLocalFile:(NSInteger)fileId;

/// Puts a file in the download list their Download Manager shows.
- (void)addFileToDownloads:(NSInteger)fileId
					inChat:(int64_t)chatId
				   message:(int64_t)messageId;

/// The list. Entries carry "fileId", "name", "size", "paused" and "done".
- (void)fileDownloadsMatching:(NSString *)query
				   activeOnly:(BOOL)activeOnly
				   completion:(void (^)(NSArray *downloads,
										NSInteger activeCount))completion;

- (void)setDownloadOfFile:(NSInteger)fileId paused:(BOOL)paused;

- (void)setAllDownloadsPaused:(BOOL)paused;

- (void)removeFileFromDownloads:(NSInteger)fileId deleteFromCache:(BOOL)deleteFromCache;

- (void)clearDownloadsDeletingFromCache:(BOOL)deleteFromCache;

@end
