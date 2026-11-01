//
// TGQuickReplyMessagesViewController.h - one shortcut's messages: add, edit,
// delete, re-add and the shortcut's own name.
//
#import "TGTier2ListViewController.h"

@interface TGQuickReplyMessagesViewController : TGTier2ListViewController

- (instancetype)initWithShortcutId:(NSInteger)shortcutId name:(NSString *)name;

@end
