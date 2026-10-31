//
// catalyst_stubs.m - what Mac Catalyst does not carry, so the probe can link.
//
// Everything here is a hole in the platform, not in the app: AddressBook and
// AssetsLibrary are gone from Catalyst, and the four TG classes are the files
// the probe leaves out because their third-party libraries (opus, vpx, webp,
// libtgvoip) have no macabi build yet. A real Mac target replaces each one -
// Contacts for AddressBook, PhotoKit or NSOpenPanel for AssetsLibrary.
//
#import <UIKit/UIKit.h>

// ─── AddressBook ──────────────────────────────────────────────────────────────
typedef const void *ABRecordRef;
const int kABPersonFirstNameProperty = 0;
const int kABPersonLastNameProperty  = 1;
const int kABPersonPhoneProperty     = 3;
CFStringRef kABPersonPhoneMainLabel  = CFSTR("_$!<Main>!$_");

void *ABMultiValueCreateMutable(int type)                                 { return NULL; }
bool  ABMultiValueAddValueAndLabel(void *m, CFTypeRef v, CFStringRef l, int32_t *i) { return false; }
CFTypeRef ABMultiValueCopyValueAtIndex(void *m, long idx)                  { return NULL; }
long  ABMultiValueGetCount(void *m)                                        { return 0; }
ABRecordRef ABPersonCreate(void)                                           { return NULL; }
bool  ABPersonSetImageData(ABRecordRef r, CFDataRef d, CFErrorRef *e)      { return false; }
CFStringRef ABRecordCopyCompositeName(ABRecordRef r)                       { return NULL; }
CFTypeRef ABRecordCopyValue(ABRecordRef r, int property)                   { return NULL; }
bool  ABRecordSetValue(ABRecordRef r, int p, CFTypeRef v, CFErrorRef *e)   { return false; }

@interface ABPeoplePickerNavigationController : UINavigationController
@property (nonatomic, assign) id peoplePickerDelegate;
@property (nonatomic, copy)   NSArray *displayedProperties;
@end
@implementation ABPeoplePickerNavigationController @end

@interface ABUnknownPersonViewController : UIViewController
@property (nonatomic, assign) ABRecordRef displayedPerson;
@property (nonatomic, assign) id unknownPersonViewDelegate;
@property (nonatomic, assign) BOOL allowsAddingToAddressBook;
@property (nonatomic, assign) BOOL allowsActions;
@end
@implementation ABUnknownPersonViewController @end

// ─── AssetsLibrary ────────────────────────────────────────────────────────────
@interface ALAssetsFilter : NSObject
+ (instancetype)allPhotos;
+ (instancetype)allVideos;
+ (instancetype)allAssets;
@end
@implementation ALAssetsFilter
+ (instancetype)allPhotos { return [self new]; }
+ (instancetype)allVideos { return [self new]; }
+ (instancetype)allAssets { return [self new]; }
@end

@interface ALAssetsLibrary : NSObject
+ (int)authorizationStatus;
- (void)enumerateGroupsWithTypes:(unsigned long)types
					  usingBlock:(void (^)(id group, BOOL *stop))block
					failureBlock:(void (^)(NSError *error))failure;
@end
@implementation ALAssetsLibrary
+ (int)authorizationStatus { return 0; }
- (void)enumerateGroupsWithTypes:(unsigned long)types
					  usingBlock:(void (^)(id, BOOL *))block
					failureBlock:(void (^)(NSError *))failure {
	if (block){ BOOL stop = NO; block(nil, &stop); }
}
@end

// kUTTypeImage / kUTTypeMovie are not stubbed: Catalyst has them, they just
// live in CoreServices rather than MobileCoreServices. Linked, not faked.

// ─── the four files the probe leaves out ──────────────────────────────────────
//
// TGCall, TGLottieView, TGStreamingVoicePlayer and TGVoiceRecorder are left
// out because their libraries (libtgvoip, opus, vpx) have no macabi build.
// Rather than retype four public APIs, these swallow whatever is sent to
// them.
//
// ponytail: the forwarder builds an all-object signature, so a method whose
// return value is a float or a struct gets a zeroed object instead. Good
// enough to see the UI stand up; a real Mac target builds the libraries.
//
static NSMethodSignature *TGAnySignature(SEL sel) {
	NSUInteger colons = [[NSStringFromSelector(sel) componentsSeparatedByString:@":"] count] - 1;
	NSMutableString *types = [NSMutableString stringWithString:@"@@:"];
	for (NSUInteger i = 0; i < colons; i++)
		[types appendString:@"@"];
	return [NSMethodSignature signatureWithObjCTypes:types.UTF8String];
}

@interface TGCatalystMissing : NSObject
+ (instancetype)shared;
@end

@implementation TGCatalystMissing
+ (instancetype)shared {
	static NSMutableDictionary *instances = nil;
	if (!instances) instances = [NSMutableDictionary dictionary];
	id existing = instances[NSStringFromClass(self)];
	if (!existing){
		existing = [self new];
		instances[NSStringFromClass(self)] = existing;
	}
	return existing;
}
- (NSMethodSignature *)methodSignatureForSelector:(SEL)sel {
	return [super methodSignatureForSelector:sel] ?: TGAnySignature(sel);
}
- (void)forwardInvocation:(NSInvocation *)invocation {
	NSLog(@"TGCatalystMissing: swallowed %@ on %@",
			NSStringFromSelector(invocation.selector), NSStringFromClass(self.class));
}
@end

@interface TGCall : TGCatalystMissing @end
@implementation TGCall @end

@interface TGStreamingVoicePlayer : TGCatalystMissing @end
@implementation TGStreamingVoicePlayer @end

@interface TGVoiceRecorder : TGCatalystMissing @end
@implementation TGVoiceRecorder @end

@interface TGLottieView : UIView @end
@implementation TGLottieView
- (NSMethodSignature *)methodSignatureForSelector:(SEL)sel {
	return [super methodSignatureForSelector:sel] ?: TGAnySignature(sel);
}
- (void)forwardInvocation:(NSInvocation *)invocation {
	NSLog(@"TGLottieView: swallowed %@", NSStringFromSelector(invocation.selector));
}
@end

// ─── scene lifecycle ──────────────────────────────────────────────────────────
//
// Catalyst on this macOS traps in
// __UIApplicationEvaluateRuntimeIssueForNoSceneLifecycleAdoption unless the
// app declares a scene delegate - the UIWindow-and-makeKeyAndVisible lifecycle
// the app uses on iOS 6 is not enough any more. AppDelegate still builds the
// window in didFinishLaunching, which runs first; this only re-hosts it on the
// scene UIKit hands over, so no iOS code path changes.
//
@interface TGCatalystScene : UIResponder <UIWindowSceneDelegate>
@end

@implementation TGCatalystScene

- (void)scene:(UIScene *)scene
	willConnectToSession:(UISceneSession *)session
				 options:(UISceneConnectionOptions *)options {
	UIWindow *window = [UIApplication sharedApplication].delegate.window;
	if (!window){
		NSLog(@"TGCatalystScene: the app delegate built no window");
		return;
	}
	window.windowScene = (UIWindowScene *)scene;
	[window makeKeyAndVisible];
	NSLog(@"TGCatalystScene: window %@ on scene", NSStringFromCGRect(window.frame));
}

@end
