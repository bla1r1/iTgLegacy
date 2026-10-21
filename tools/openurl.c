#include <stdio.h>
#include <dlfcn.h>
#include <CoreFoundation/CoreFoundation.h>

typedef int (*SBSLaunchURLFunc)(CFStringRef identifier, CFURLRef url);

int main(int argc, char *argv[]) {
    if (argc < 2) {
        printf("Usage: %s <url>\n", argv[0]);
        return 1;
    }
    void *h = dlopen("/System/Library/PrivateFrameworks/SpringBoardServices.framework/SpringBoardServices", RTLD_LAZY);
    if (!h) {
        printf("Failed to dlopen SpringBoardServices\n");
        return 2;
    }
    SBSLaunchURLFunc launch = (SBSLaunchURLFunc)dlsym(h, "SBSLaunchApplicationWithIdentifierAndURL");
    if (!launch) {
        printf("Failed to find SBSLaunchApplicationWithIdentifierAndURL\n");
        return 3;
    }
    CFStringRef bid = CFSTR("kuzm.ig.telegram");
    CFStringRef urlStr = CFStringCreateWithCString(kCFAllocatorDefault, argv[1], kCFStringEncodingUTF8);
    CFURLRef url = CFURLCreateWithString(kCFAllocatorDefault, urlStr, NULL);
    int res = launch(bid, url);
    printf("SBSLaunchApplicationWithIdentifierAndURL -> %d\n", res);
    CFRelease(url);
    CFRelease(urlStr);
    return res;
}
