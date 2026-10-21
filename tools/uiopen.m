#import <Foundation/Foundation.h>
#include <dlfcn.h>

@interface LSApplicationWorkspace : NSObject
+ (id)defaultWorkspace;
- (BOOL)openURL:(NSURL *)url;
- (BOOL)openApplicationWithBundleID:(NSString *)bundleID;
@end

int main(int argc, char *argv[]) {
    @autoreleasepool {
        if (argc < 2) {
            printf("Usage: %s <url-or-bundleid>\n", argv[0]);
            return 1;
        }
        dlopen("/System/Library/Frameworks/MobileCoreServices.framework/MobileCoreServices", RTLD_NOW);
        Class cls = NSClassFromString(@"LSApplicationWorkspace");
        if (!cls) {
            printf("No LSApplicationWorkspace class\n");
            return 2;
        }
        id ws = [cls performSelector:@selector(defaultWorkspace)];
        NSString *arg = [NSString stringWithUTF8String:argv[1]];
        if ([arg rangeOfString:@"://"].location != NSNotFound) {
            NSURL *url = [NSURL URLWithString:arg];
            BOOL ok = (BOOL)[ws performSelector:@selector(openURL:) withObject:url];
            printf("openURL: %s -> %d\n", argv[1], ok);
            return ok ? 0 : 1;
        } else {
            BOOL ok = (BOOL)[ws performSelector:@selector(openApplicationWithBundleID:) withObject:arg];
            printf("openApp: %s -> %d\n", argv[1], ok);
            return ok ? 0 : 1;
        }
    }
}
