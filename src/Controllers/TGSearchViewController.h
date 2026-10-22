//
// TGSearchViewController - search on a page of its own.
//
// A search bar pinned over the chat list left nowhere for the keyboard to go:
// the results were under it and there was no way to put it away without
// giving up the query. Their design gives search a screen, and dragging the
// results dismisses the keyboard.
//
#import <UIKit/UIKit.h>

@interface TGSearchViewController : UITableViewController
@end
