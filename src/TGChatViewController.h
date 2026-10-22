//
// TGChatViewController - a chat, driven purely by TDLib.
//
// Written from scratch rather than reusing ChatViewController: that one is
// built around libtg's tg_message_t and NSBubbleData, and carries the whole
// old media pipeline with it.
//
#import <UIKit/UIKit.h>
#import <AddressBookUI/AddressBookUI.h>

@interface TGChatViewController : UIViewController
    <UITableViewDataSource, UITableViewDelegate, UITextFieldDelegate,
     UIImagePickerControllerDelegate, UINavigationControllerDelegate,
     UIActionSheetDelegate, ABUnknownPersonViewControllerDelegate>

@property (nonatomic, assign) int64_t chatId;
@property (nonatomic, copy)   NSString *chatTitle;
@property (nonatomic, assign) BOOL isGroup;
/// Non-zero when this is one topic of a forum supergroup.
@property (nonatomic, assign) int64_t threadId;

/// Run the tap handler for a row, without a touch. Used by
/// itglegacy://tap/N so playback and viewers can be exercised remotely.
- (void)simulateTapOnRow:(NSInteger)row;

@end
