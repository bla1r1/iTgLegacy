//
// TGChatViewController - chat message history and composer controller.
//
#import <UIKit/UIKit.h>
#import <AddressBookUI/AddressBookUI.h>

@interface TGChatViewController : UIViewController
    <UITableViewDataSource, UITableViewDelegate, UITextFieldDelegate,
     UIImagePickerControllerDelegate, UINavigationControllerDelegate,
     UIActionSheetDelegate, ABUnknownPersonViewControllerDelegate,
     UIGestureRecognizerDelegate>

@property (nonatomic, assign) int64_t chatId;
@property (nonatomic, copy)   NSString *chatTitle;
@property (nonatomic, assign) BOOL isGroup;
/// Non-zero when this is one topic of a forum supergroup.
@property (nonatomic, assign) int64_t threadId;

/// Run the tap handler for a row, without a touch. Used by
/// itglegacy://tap/N so playback and viewers can be exercised remotely.
- (void)simulateTapOnRow:(NSInteger)row;

@property (nonatomic, assign, readonly) BOOL isEditingMessages;
@property (nonatomic, strong, readonly) NSMutableSet *selectedMessageIds;
- (void)enterEditMode;
- (void)exitEditMode;
- (void)toggleMessageSelection:(int64_t)messageId;
- (void)selectMessageAtIndex:(NSInteger)index;
- (void)deleteSelectedMessages;
- (void)executeDeleteMessages:(NSArray *)ids revoke:(BOOL)revoke;
- (void)forwardSelectedMessages;

@end
