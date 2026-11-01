//
// TGMediaStore - forwards the media display's four questions to the client.
//
#import "TGMediaStore.h"
#import "TGClient.h"

@implementation TGMediaStore

+ (TGMediaStore *)shared {
	static TGMediaStore *one;
	static dispatch_once_t once;
	dispatch_once(&once, ^{ one = [[TGMediaStore alloc] init]; });
	return one;
}

- (NSString *)nameForUserId:(int64_t)userId {
	return [[TGClient shared] nameForUserId:userId];
}

- (NSNumber *)photoFileIdForUserId:(int64_t)userId {
	return [[TGClient shared] photoFileIdForUserId:userId];
}

- (void)downloadFile:(NSInteger)fileId completion:(void (^)(NSString *path))completion {
	[[TGClient shared] downloadFile:fileId completion:completion];
}

- (void)downloadFile:(NSInteger)fileId priority:(NSInteger)priority
          completion:(void (^)(NSString *path))completion {
	[[TGClient shared] downloadFile:fileId priority:priority completion:completion];
}

@end
