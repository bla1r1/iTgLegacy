//
// TGBench.m - see TGBench.h.
//
#import "TGBench.h"
#import "TGPerf.h"
#import "TGSampler.h"
#import <QuartzCore/QuartzCore.h>
#import <dlfcn.h>
#include <stdlib.h>

/// A thumb flick on a 3.5" screen moves content about this fast; slower hides
/// the cell-creation cost, faster than this nobody scrolls a chat.
static const CGFloat kFlingPointsPerSecond = 1600.0f;
static const double kFrameSeconds = 1.0 / 60.0;
enum { kMaxFrames = 4096 };
static const double kOpenWatchSeconds = 2.5;
static const double kPopWatchSeconds = 1.0;

@interface TGBench ()
@property (nonatomic, strong) CADisplayLink *link;
@property (nonatomic, weak) UIScrollView *scroll;
@property (nonatomic, copy) NSString *what;
@property (nonatomic, assign) BOOL profile;
@property (nonatomic, assign) double duration;
@property (nonatomic, assign) double start;
@property (nonatomic, assign) double last;
@property (nonatomic, assign) CGFloat direction;
@property (nonatomic, copy) void (^afterWatch)(void);
@end

@implementation TGBench {
	double _frames[kMaxFrames];     // intervals in seconds
	unsigned _count;
	double _firstFrameMs;
}

static TGBench *sCurrent;
static UIViewController *frontController(UIWindow *window) {
	UIViewController *vc = window.rootViewController;
	for (;;) {
		if (vc.presentedViewController)
			vc = vc.presentedViewController;
		else if ([vc isKindOfClass:UITabBarController.class])
			vc = ((UITabBarController *)vc).selectedViewController;
		else if ([vc isKindOfClass:UINavigationController.class])
			vc = ((UINavigationController *)vc).topViewController;
		else
			return vc;
	}
}

/// The biggest visible scroll view: the chat's table, not the input bar's text view.
static UIScrollView *largestScroll(UIView *view) {
	UIScrollView *best = nil;
	CGFloat bestArea = 0;
	NSMutableArray *queue = [NSMutableArray arrayWithObject:view];
	while (queue.count) {
		UIView *v = queue[0];
		[queue removeObjectAtIndex:0];
		if (v.hidden || v.alpha < 0.01f)
			continue;
		if ([v isKindOfClass:UIScrollView.class] && ![v isKindOfClass:UITextView.class]) {
			CGFloat area = v.bounds.size.width * v.bounds.size.height;
			if (area > bestArea) {
				bestArea = area;
				best = (UIScrollView *)v;
			}
		}
		[queue addObjectsFromArray:v.subviews];
	}
	return best;
}

static NSString *cachesPath(NSString *name) {
	NSString *dir = NSSearchPathForDirectoriesInDomains(NSCachesDirectory,
			NSUserDomainMask, YES)[0];
	return [dir stringByAppendingPathComponent:name];
}

+ (void)runWithArguments:(NSArray *)args window:(UIWindow *)window {
	if (sCurrent) {
		NSLog(@"[bench] busy with %@", sCurrent.what);
		return;
	}
	NSString *mode = args.count > 0 ? args[0] : @"scroll";
	NSString *num = args.count > 1 ? args[1] : @"";
	BOOL prof = [args containsObject:@"prof"];
	if ([mode isEqualToString:@"memwarn"]) {
		// What the system posts first; jetsam comes after if nobody listens.
		[[NSNotificationCenter defaultCenter]
				postNotificationName:UIApplicationDidReceiveMemoryWarningNotification
							  object:[UIApplication sharedApplication]];
		return;
	}
	if ([mode isEqualToString:@"mem"]) {
		char line[512];
		TGMemoryBreakdown(line, sizeof(line));
		NSLog(@"[bench] mem %s %s", num.UTF8String, line);
		char big[1024];
		TGMallocBigBlocks(big, sizeof(big));
		NSLog(@"[bench] mem %s big %s", num.UTF8String, big);
		return;
	}
	if ([mode isEqualToString:@"pref"] && args.count > 2) {
		// A/B a setting without a rebuild: bench/pref/TGWantAnimatedStickers/0
		[[NSUserDefaults standardUserDefaults] setBool:[args[2] boolValue] forKey:num];
		// A run usually ends in killall, which beats the periodic write.
		[[NSUserDefaults standardUserDefaults] synchronize];
		NSLog(@"[bench] pref %@ = %@", num, args[2]);
		return;
	}
	if ([mode isEqualToString:@"null"]) {
		// bench/null: the runtime on this iOS forwards to nil as the host's does.
		id null = [NSNull null];
		NSLog(@"[bench] null long=%lld count=%lu object=%@", [null longLongValue],
				(unsigned long)[null count], [null objectForKey:@"x"]);
		return;
	}
	if ([mode isEqualToString:@"slow"]) {
		// bench/slow/0.25: every animation in the window at a quarter speed.
		window.layer.speed = num.length ? [num floatValue] : 1.0f;
		return;
	}
	if ([mode isEqualToString:@"record"]) {
		// bench/record/<seconds>: what an animation really does on screen. The
		// framebuffer is the only place that shows it, because render-server
		// animations never touch the app's own layers. Frames go to Caches/cap.
		double seconds = num.length ? [num doubleValue] : 3.0;
		[NSThread detachNewThreadSelector:@selector(recordFramesFor:) toTarget:self
							   withObject:@(seconds)];
		return;
	}
	// The iPod auto-locks after a minute, and with the screen off
	// CADisplayLink stops firing: a run would never end. Benching is a
	// developer session, so the screen stays on until the app quits.
	[UIApplication sharedApplication].idleTimerDisabled = YES;

	TGBench *b = [[TGBench alloc] init];
	b.profile = prof;
	if ([mode isEqualToString:@"watch"]) {
		// No input at all: what the screen costs while someone only reads it.
		b.duration = num.length ? [num doubleValue] : 8.0;
		b.what = [NSString stringWithFormat:@"watch-%@", NSStringFromClass(frontController(window).class)];
		[b begin];
	} else if ([mode isEqualToString:@"open"]) {
		// A beat first: uiopen, sshd and SpringBoard's openURL are still on the
		// single core when the URL lands, and inflated "first" by ~100 ms.
		NSInteger row = [num integerValue];
		dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(1.0 * NSEC_PER_SEC)),
				dispatch_get_main_queue(), ^{ [b openRow:row window:window]; });
	} else {
		b.duration = num.length ? [num doubleValue] : 8.0;
		[b scrollIn:window];
	}
}

+ (void)recordFramesFor:(NSNumber *)seconds {
	CGImageRef (*grab)(void) = (CGImageRef (*)(void))dlsym(RTLD_DEFAULT, "UIGetScreenImage");
	NSString *dir = [[NSSearchPathForDirectoriesInDomains(NSCachesDirectory, NSUserDomainMask, YES)
			objectAtIndex:0] stringByAppendingPathComponent:@"cap"];
	NSFileManager *files = [NSFileManager defaultManager];
	[files removeItemAtPath:dir error:nil];
	[files createDirectoryAtPath:dir withIntermediateDirectories:YES attributes:nil error:nil];

	// Held raw and encoded afterwards: a JPEG takes 250 ms on an A4, longer than
	// most of the animations this exists to look at. 2.4 MB each, hence the cap.
	NSMutableArray *held = [NSMutableArray array];
	NSDate *end = [NSDate dateWithTimeIntervalSinceNow:seconds.doubleValue];
	while (grab && [end timeIntervalSinceNow] > 0 && held.count < 30) {
		CGImageRef screen = grab();
		if (!screen)
			break;
		[held addObject:[UIImage imageWithCGImage:screen]];
		CGImageRelease(screen);
		[NSThread sleepForTimeInterval:MAX(0.02, seconds.doubleValue / 30.0 - 0.06)];
	}
	NSInteger frame = 0;
	for (UIImage *image in held) {
		@autoreleasepool {
			[UIImageJPEGRepresentation(image, 0.6f) writeToFile:[dir stringByAppendingPathComponent:
					[NSString stringWithFormat:@"frame_%04ld.jpg", (long)frame++]] atomically:NO];
		}
	}
	NSLog(@"[bench] record %ld frames in %.1f s", (long)frame, seconds.doubleValue);
}

- (void)begin {
	sCurrent = self;
	_count = 0;
	_firstFrameMs = -1;
	if (self.profile)
		TGSamplerStart(2000, 8000);
	char buf[8];
	TGCpuSplit(buf, sizeof(buf));
	self.start = self.last = CACurrentMediaTime();
	self.link = [CADisplayLink displayLinkWithTarget:self selector:@selector(tick:)];
	[self.link addToRunLoop:[NSRunLoop mainRunLoop] forMode:NSRunLoopCommonModes];
}

- (void)scrollIn:(UIWindow *)window {
	UIViewController *vc = frontController(window);
	self.scroll = largestScroll(vc.view);
	if (!self.scroll) {
		NSLog(@"[bench] no scroll view in %@", vc.class);
		return;
	}
	self.what = [NSString stringWithFormat:@"scroll-%@", NSStringFromClass(vc.class)];
	self.direction = 1;
	TGPerfReportMemory("bench start");
	[self begin];
}

- (void)openRow:(NSInteger)row window:(UIWindow *)window {
	UIViewController *vc = frontController(window);
	UITableView *table = (UITableView *)largestScroll(vc.view);
	if (![table isKindOfClass:UITableView.class] || row >= [table numberOfRowsInSection:0]) {
		NSLog(@"[bench] %@ has no row %ld", vc.class, (long)row);
		return;
	}
	UINavigationController *nc = vc.navigationController;
	self.what = [NSString stringWithFormat:@"open-%ld", (long)row];
	self.duration = kOpenWatchSeconds;
	// Strong on purpose: sCurrent lets go before this runs, and the cycle
	// ends when the block clears afterWatch.
	TGBench *me = self;
	self.afterWatch = ^{
		// The way back is part of opening a chat too: the list redraws.
		me.what = [NSString stringWithFormat:@"pop-%ld", (long)row];
		me.duration = kPopWatchSeconds;
		me.afterWatch = nil;
		[me begin];
		double t0 = CACurrentMediaTime();
		[nc popViewControllerAnimated:YES];
		me.start = t0;
	};
	TGPerfReportMemory("bench start");
	[self begin];
	double t0 = CACurrentMediaTime();
	NSIndexPath *path = [NSIndexPath indexPathForRow:row inSection:0];
	[table selectRowAtIndexPath:path animated:NO scrollPosition:UITableViewScrollPositionNone];
	[table.delegate tableView:table didSelectRowAtIndexPath:path];
	self.start = t0;
}

- (void)tick:(CADisplayLink *)link {
	double now = CACurrentMediaTime();
	double dt = now - self.last;
	self.last = now;
	if (_firstFrameMs < 0)
		_firstFrameMs = (now - self.start) * 1000.0;
	else if (_count < kMaxFrames)
		_frames[_count++] = dt;

	UIScrollView *s = self.scroll;
	if (s) {
		// Time-based, so a dropped frame jumps further like a real fling does
		// instead of quietly slowing the scroll down to what the CPU manages.
		CGFloat maxY = MAX(0, s.contentSize.height - s.bounds.size.height + s.contentInset.bottom);
		CGFloat minY = -s.contentInset.top;
		CGFloat y = s.contentOffset.y + self.direction * kFlingPointsPerSecond * (CGFloat)MIN(dt, 0.25);
		if (y >= maxY) { y = maxY; self.direction = -1; }
		if (y <= minY) { y = minY; self.direction = 1; }
		[s setContentOffset:CGPointMake(0, y) animated:NO];
	}
	if (now - self.start >= self.duration)
		[self finish];
}

static int cmpDouble(const void *a, const void *b) {
	double x = *(const double *)a, y = *(const double *)b;
	return x < y ? -1 : x > y;
}

- (void)finish {
	[self.link invalidate];
	self.link = nil;
	int samples = 0;
	NSString *dump = nil;
	if (self.profile) {
		dump = cachesPath([NSString stringWithFormat:@"bench-%@.txt", self.what]);
		samples = TGSamplerStopAndWrite(dump.fileSystemRepresentation);
	}

	unsigned dropped = 0, janky = 0;
	double worst = 0, busy = 0;
	for (unsigned i = 0; i < _count; i++) {
		double f = _frames[i];
		long missed = lround(f / kFrameSeconds) - 1;
		if (missed > 0) {
			dropped += (unsigned)missed;
			janky++;
		}
		worst = MAX(worst, f);
		busy += f;
	}
	qsort(_frames, _count, sizeof(double), cmpDouble);
	double p50 = _count ? _frames[_count / 2] : 0;
	double p95 = _count ? _frames[(_count * 95) / 100] : 0;
	unsigned expected = _count + dropped;
	NSLog(@"[bench] %@ first=%.0fms frames=%u dropped=%u (%.0f%%) janky=%u worst=%.0fms p50=%.1fms p95=%.1fms fps=%.1f samples=%d",
			self.what, _firstFrameMs, _count, dropped,
			expected ? 100.0 * dropped / expected : 0.0, janky, worst * 1000.0,
			p50 * 1000.0, p95 * 1000.0, busy > 0 ? _count / busy : 0.0, samples);
	// Layers per visible row, all and shown: backboardd's work tracks the
	// layer tree, hidden layers included, more than anything drawn.
	if ([self.scroll isKindOfClass:UITableView.class]) {
		unsigned all = 0, shown = 0, rows = 0;
		for (UITableViewCell *c in ((UITableView *)self.scroll).visibleCells) {
			rows++;
			NSMutableArray *q = [NSMutableArray arrayWithObject:c.layer];
			while (q.count) {
				CALayer *l = q.lastObject;
				[q removeLastObject];
				all++;
				BOOL hiddenUp = NO;
				for (CALayer *u = l; u && u != c.layer.superlayer; u = u.superlayer)
					if (u.hidden) { hiddenUp = YES; break; }
				if (!hiddenUp)
					shown++;
				[q addObjectsFromArray:l.sublayers];
			}
		}
		if (rows)
			NSLog(@"[bench] %@ layers/row all=%u shown=%u", self.what, all / rows, shown / rows);
	}
	char cpu[512];
	if (TGCpuSplit(cpu, sizeof(cpu)))
		NSLog(@"[bench] %@ cpu %s", self.what, cpu);
	if (dump)
		NSLog(@"[bench] dump %@", dump);
	char mem[512];
	TGMemoryBreakdown(mem, sizeof(mem));
	NSLog(@"[bench] %@ mem %s", self.what, mem);

	void (^next)(void) = self.afterWatch;
	sCurrent = nil;
	if (next) {
		// A beat for the pushed screen to settle, as a person would read first.
		dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.5 * NSEC_PER_SEC)),
				dispatch_get_main_queue(), next);
	}
}

@end
