//
// TGBench.h - scripted scrolling and chat opening with frame timing, so lag
// on a device nobody is holding becomes numbers in the syslog.
//
//   itglegacy://bench/scroll/<seconds>[/prof]   fling the front table up and down
//   itglegacy://bench/open/<row>[/prof]         tap a chat-list row, time it, go back
//   itglegacy://bench/watch/<seconds>[/prof]    touch nothing, just measure
//   itglegacy://bench/pref/<key>/<0|1>          flip a user default, for A/B runs
//   itglegacy://bench/mem/<label>                resident memory by VM tag
//   itglegacy://bench/memwarn                    post a memory warning
//
// Every run ends with one "[bench] ..." line; with /prof the main thread is
// also sampled into Library/Caches/bench-<what>.txt for scripts/bench.sh.
//
#import <UIKit/UIKit.h>

@interface TGBench : NSObject
+ (void)runWithArguments:(NSArray *)args window:(UIWindow *)window;
@end
