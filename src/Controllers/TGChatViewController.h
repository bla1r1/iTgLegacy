//
// TGChatViewController - chat message history and composer controller.
//
#import <UIKit/UIKit.h>
#import <AddressBookUI/AddressBookUI.h>

@interface TGChatViewController : UIViewController
    <UITableViewDataSource, UITableViewDelegate, UITextFieldDelegate,
     UIImagePickerControllerDelegate, UINavigationControllerDelegate,
     ABUnknownPersonViewControllerDelegate,
     UIGestureRecognizerDelegate>

@property (nonatomic, assign) int64_t chatId;
@property (nonatomic, copy)   NSString *chatTitle;
@property (nonatomic, assign) BOOL isGroup;
@property (nonatomic, assign) int64_t linkedChatId;
@property (nonatomic, assign) int64_t directMessagesChatId;
@property (nonatomic, assign) BOOL hasDirectMessages;
@property (nonatomic, assign) BOOL canManageDirectMessages;
/// Non-zero when this is one topic of a forum supergroup.
@property (nonatomic, assign) int64_t threadId;
/// The message a link opened this chat to show: scrolled to on the first
/// load, fetched around if the first page does not carry it.
@property (nonatomic, assign) int64_t initialMessageId;

/// Run the tap handler for a row, without a touch. Used by
/// itglegacy://tap/N so playback and viewers can be exercised remotely.
- (void)simulateTapOnRow:(NSInteger)row;

/// The in-chat search bar opened on a tag the user tapped, collecting the
/// public wall or this account's saved notes.
- (void)toggleChatSearchOpenWithTag:(NSString *)tag;

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
