//
// TGChatListViewController - the chat list, driven purely by TDLib.
//
// Deliberately does not reuse TGDialog, DialogViewCell or anything from libtg:
// that pipeline carries the old C structs and their assumptions. This one
// takes [TGClient shared].chats and nothing else.
//
#import <UIKit/UIKit.h>

@interface TGChatListViewController : UITableViewController <UIActionSheetDelegate>
@end
