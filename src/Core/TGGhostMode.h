//
// TGGhostMode.h
// Testing on a real account without leaving a trace on it. With this on, the
// client still receives everything but tells nobody it looked: messages stay
// unread and keep notifying the other clients, stories count no view, nobody
// sees typing and the account does not go online.
//
// Off by default, and only a developer turns it on, through
// itglegacy://bench/pref/TGGhostMode/1 and a relaunch. Sending stays possible:
// what a test sends is its own decision.
//
#import <Foundation/Foundation.h>

#ifdef __cplusplus
extern "C" {
#endif

BOOL TGGhostModeOn(void);
/// For the host tests: the launch-time reading of the preference, overridden.
void TGGhostModeSetOn(BOOL on);
/// Whether this request would give the account away.
BOOL TGGhostModeBlocks(NSDictionary *request);

#ifdef __cplusplus
}
#endif
