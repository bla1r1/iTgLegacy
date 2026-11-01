//
// TGClient+Files.h - the client surface for file downloads and TDLib's storage on disk.
//
#import "TGClient+Base.h"

@interface TGClient (Files)

/// Download a file by TDLib id. `completion` gets the local path, or nil.
/// Already-downloaded files complete immediately.
/// How eagerly TDLib downloads: see the priorities in TGDownloadPriority.h.
/// A file asked again at a higher rank than its standing request re-raises it
/// on the wire, so an avatar can overtake a photo grid that started earlier.
- (void)downloadFile:(NSInteger)fileId completion:(void (^)(NSString *path))completion;

- (void)downloadFile:(NSInteger)fileId priority:(NSInteger)priority completion:(void (^)(NSString *path))completion;

/// Bytes over the wire since TDLib last reset its counters.
- (void)networkStatsWithCompletion:(void (^)(long long sent, long long received))completion;

- (void)resetNetworkStats;

/// Whether media downloads itself, per network. TDLib cannot read the setting
/// back, so these answer with what the app last wrote.
- (BOOL)autoDownloadOverMobile;

- (BOOL)autoDownloadOverWifi;

- (void)setAutoDownloadOverMobile:(BOOL)mobile wifi:(BOOL)wifi;

/// Cache size on disk, in bytes, and the file count. TDLib's fast variant:
/// the full one walks every file and takes seconds on this hardware.
- (void)storageStatsWithCompletion:(void (^)(long long bytes, NSInteger files))completion;

/// Delete cached media. `kinds` are TDLib FileType names, or nil for all of
/// them; `completion` gets the number of bytes freed.
- (void)clearCacheOfTypes:(NSArray *)kinds completion:(void (^)(long long freed))completion;

/// What the cache is made of, largest first: "name", "bytes", "kinds". Walks
/// the database, so it takes a moment on this hardware - ask once per screen.
- (void)storageBreakdownWithCompletion:(void (^)(NSArray *categories,
                                                 long long total))completion;

/// Drop TDLib's local database. The session stays.
- (void)clearLocalDatabase;

@end
