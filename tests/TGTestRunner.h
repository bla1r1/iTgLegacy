// TGTestRunner.h — minimal test shim for macOS Command Line Tools.
//
// Provides XCTestCase + XCTAssert* macros, runs test* methods via ObjC
// runtime, prints TAP output.  No Xcode required.
#pragma once
#import <Foundation/Foundation.h>
#include <stdio.h>
#include <objc/runtime.h>
#include <string.h>

// ─── globals ──────────────────────────────────────────────────────────────────
static int  _tg_total   = 0;
static int  _tg_passed  = 0;
static int  _tg_failed  = 0;
static BOOL _tg_ok      = YES;
static const char *_tg_method = "(unknown)";

// Accept both NSString* and const char* messages via a helper function.
static inline void _TGFail(const char *file, int line, NSString *msg) {
    _tg_ok = NO;
    fprintf(stderr, "    # FAIL: %s  (%s:%d)\n",
            msg.length ? msg.UTF8String : "(assertion failed)", file, line);
}

// ─── assert macros ────────────────────────────────────────────────────────────
// Message argument is optional NSString* (same as XCTest).

#define XCTAssertTrue(expr, ...) \
    do { if (!(expr)) _TGFail(__FILE__,__LINE__, \
        ([NSString stringWithFormat:@"" __VA_ARGS__] ?: @(#expr " must be true"))); } while(0)

#define XCTAssertFalse(expr, ...) \
    do { if (!!(expr)) _TGFail(__FILE__,__LINE__, \
        ([NSString stringWithFormat:@"" __VA_ARGS__] ?: @(#expr " must be false"))); } while(0)

#define XCTAssertEqual(a, b, ...) \
    do { if (!((a)==(b))) _TGFail(__FILE__,__LINE__, \
        ([NSString stringWithFormat:@"" __VA_ARGS__] ?: @(#a " == " #b))); } while(0)

#define XCTAssertNotEqual(a, b, ...) \
    do { if ((a)==(b)) _TGFail(__FILE__,__LINE__, \
        ([NSString stringWithFormat:@"" __VA_ARGS__] ?: @(#a " != " #b))); } while(0)

#define XCTAssertGreaterThan(a, b, ...) \
    do { if (!((a)>(b))) _TGFail(__FILE__,__LINE__, \
        ([NSString stringWithFormat:@"" __VA_ARGS__] ?: @(#a " > " #b))); } while(0)

#define XCTAssertGreaterThanOrEqual(a, b, ...) \
    do { if (!((a)>=(b))) _TGFail(__FILE__,__LINE__, \
        ([NSString stringWithFormat:@"" __VA_ARGS__] ?: @(#a " >= " #b))); } while(0)

#define XCTAssertLessThan(a, b, ...) \
    do { if (!((a)<(b))) _TGFail(__FILE__,__LINE__, \
        ([NSString stringWithFormat:@"" __VA_ARGS__] ?: @(#a " < " #b))); } while(0)

#define XCTAssertLessThanOrEqual(a, b, ...) \
    do { if (!((a)<=(b))) _TGFail(__FILE__,__LINE__, \
        ([NSString stringWithFormat:@"" __VA_ARGS__] ?: @(#a " <= " #b))); } while(0)

#define XCTAssertNil(expr, ...) \
    do { if ((expr) != nil) _TGFail(__FILE__,__LINE__, \
        ([NSString stringWithFormat:@"" __VA_ARGS__] ?: @(#expr " must be nil"))); } while(0)

#define XCTAssertNotNil(expr, ...) \
    do { if ((expr) == nil) _TGFail(__FILE__,__LINE__, \
        ([NSString stringWithFormat:@"" __VA_ARGS__] ?: @(#expr " must not be nil"))); } while(0)

#define XCTAssertEqualObjects(a, b, ...) \
    do { BOOL _eq=((a)==(b))||[(a) isEqual:(b)]; \
         if (!_eq) _TGFail(__FILE__,__LINE__, \
             ([NSString stringWithFormat:@"" __VA_ARGS__] ?: @(#a " isEqual: " #b))); } while(0)

#define XCTAssertNoThrow(expr, ...) \
    do { @try { (void)(expr); } \
         @catch(id _ex) { _TGFail(__FILE__,__LINE__, \
             ([NSString stringWithFormat:@"" __VA_ARGS__] ?: @("threw: " #expr))); } } while(0)

#define XCTSkip(msg) \
    do { printf("ok %d - %s # SKIP %s\n", ++_tg_total, _tg_method, (msg)); \
         _tg_passed++; return; } while(0)

// ─── XCTestCase ───────────────────────────────────────────────────────────────
@interface XCTestCase : NSObject
- (void)setUp;
- (void)tearDown;
@end
@implementation XCTestCase
- (void)setUp    {}
- (void)tearDown {}
@end

// ─── runner ───────────────────────────────────────────────────────────────────
static inline void TGTestRunnerRun(void) {
    // Collect XCTestCase subclasses registered in this binary.
    NSMutableArray *classNames = [NSMutableArray array];
    int cnt = objc_getClassList(NULL, 0);
    Class *buf = (Class *)malloc((size_t)cnt * sizeof(Class));
    objc_getClassList(buf, cnt);
    for (int i = 0; i < cnt; i++) {
        Class sup = class_getSuperclass(buf[i]);
        if (sup && strcmp(class_getName(sup), "XCTestCase") == 0)
            [classNames addObject:@(class_getName(buf[i]))];
    }
    free(buf);

    [classNames sortedArrayUsingSelector:@selector(compare:)];
    classNames = [NSMutableArray arrayWithArray:
        [classNames sortedArrayUsingSelector:@selector(compare:)]];

    for (NSString *clsName in classNames) {
        Class cls = NSClassFromString(clsName);
        if (!cls) continue;
        printf("\n# %s\n", clsName.UTF8String);

        unsigned int n = 0;
        Method *methods = class_copyMethodList(cls, &n);
        // Sort alphabetically.
        for (unsigned i = 0; i < n; i++)
            for (unsigned j = i+1; j < n; j++) {
                const char *ni = sel_getName(method_getName(methods[i]));
                const char *nj = sel_getName(method_getName(methods[j]));
                if (strcmp(ni, nj) > 0) { Method t=methods[i]; methods[i]=methods[j]; methods[j]=t; }
            }

        for (unsigned i = 0; i < n; i++) {
            SEL sel = method_getName(methods[i]);
            const char *name = sel_getName(sel);
            if (strncmp(name, "test", 4) != 0) continue;

            _tg_ok = YES;
            _tg_method = name;
            _tg_total++;

            XCTestCase *inst = [cls new];
            [inst setUp];
            @try {
                #pragma clang diagnostic push
                #pragma clang diagnostic ignored "-Warc-performSelector-leaks"
                [inst performSelector:sel];
                #pragma clang diagnostic pop
            } @catch (id ex) {
                _tg_ok = NO;
                fprintf(stderr, "    # EXCEPTION: %s\n",
                        [[ex description] UTF8String] ?: "?");
            }
            [inst tearDown];

            if (_tg_ok) {
                printf("ok %d - %s.%s\n", _tg_total, clsName.UTF8String, name);
                _tg_passed++;
            } else {
                printf("not ok %d - %s.%s\n", _tg_total, clsName.UTF8String, name);
                _tg_failed++;
            }
        }
        free(methods);
    }

    printf("\n1..%d\n# %d passed, %d failed\n",
           _tg_total, _tg_passed, _tg_failed);
}
