//
// TGActiveNotificationsViewController.h - TDLib's own notification list.
//
// APNs draws a banner; this screen draws the groups TDLib would have shown
// while the app was closed. Settings > Notifications and Sounds > Active is
// the way in. The client keeps the state; the screen only reads and removes.
//
#import <UIKit/UIKit.h>

@interface TGActiveNotificationsViewController : UITableViewController
@end
