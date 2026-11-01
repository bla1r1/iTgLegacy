//
// TGMediaStore - what a media display may ask for.
//
// A viewer loads files and looks up who sent a picture; that is the whole
// of its reach into the account. Collecting those four calls here keeps
// TGClient.h out of the views and the seam named.
//
#import <Foundation/Foundation.h>
#import "TGDownloadPriority.h"

@interface TGMediaStore : NSObject

+ (TGMediaStore *)shared;

/// The display name the account knows for a user id.
- (NSString *)nameForUserId:(int64_t)userId;
/// The profile photo file id of a user, or nil when there is none.
- (NSNumber *)photoFileIdForUserId:(int64_t)userId;

- (void)downloadFile:(NSInteger)fileId completion:(void (^)(NSString *path))completion;
- (void)downloadFile:(NSInteger)fileId priority:(NSInteger)priority
          completion:(void (^)(NSString *path))completion;

@end
