//
// TGFileInfoViewController - the file record behind a picture or document.
//
#import <UIKit/UIKit.h>

@interface TGFileInfoViewController : UITableViewController

/// Set before the view loads. A file id of 0 shows the "unavailable" state.
@property (nonatomic, assign) NSInteger fileId;

/// Opens the sheet over whatever is on screen. The media viewer and the
/// download list have no navigation controller of their own to push onto.
+ (void)presentForFile:(NSInteger)fileId fromView:(UIView *)host;

@end

// vim:ft=objc
