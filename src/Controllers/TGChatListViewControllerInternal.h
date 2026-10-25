#ifndef TGCHATLISTVIEWCONTROLLERINTERNAL_H
#define TGCHATLISTVIEWCONTROLLERINTERNAL_H

#import "TGChatListViewController.h"
#import "TGChatViewController.h"
#import "TGClient.h"
#import "TGTheme.h"
#import "TGIcons.h"
#import "TGContactsViewController.h"
#import "TGTopicsViewController.h"
#import "TGPopupMenu.h"
#import "TGSnackbar.h"
#import "TGSearchViewController.h"
#import "TGChatCell.h"
#import <QuartzCore/QuartzCore.h>

@interface TGChatListViewController () <UISearchBarDelegate, UIAlertViewDelegate>

@property (nonatomic, strong) NSArray *chats;
@property (nonatomic, assign) BOOL showsArchive;      // this IS the archive screen
@property (nonatomic, assign) NSInteger folderId;     // 0 = no folder
@property (nonatomic, strong) NSMutableDictionary *avatars;   // fileId -> UIImage
@property (nonatomic, strong) NSMutableSet *avatarsRequested;
@property (nonatomic, strong) UISearchBar *searchBar;
@property (nonatomic, strong) NSArray *searchResults;   // nil = not searching
@property (nonatomic, strong) NSDictionary *actionChat; // long-pressed row
@property (nonatomic, assign) int64_t chatPendingDeletion;
@property (nonatomic, assign) CGFloat headerHeight;

- (void)reload;
- (void)rebuildTableHeader;
- (void)hideHeaderAboveFrom:(CGFloat)previousHeight;
- (NSArray *)visibleChats;
- (NSArray *)headerRows;
- (void)openArchive;
- (void)openSavedMessages;
- (void)reloadTableDebounced;
- (void)fetchMissingAvatars;

@end

@interface TGChatListViewController (Actions)

- (void)foldersTapped;
- (void)runFolderChoice:(NSInteger)choice;
- (void)rowHeld:(UILongPressGestureRecognizer *)hold;
- (void)showActionsForRow:(NSInteger)row;
- (void)runChatAction:(NSInteger)choice;
- (void)confirmDeleteChat:(int64_t)chatId;

@end

@interface TGChatListViewController (Search)

- (void)styleSearchBar;

@end

#endif // TGCHATLISTVIEWCONTROLLERINTERNAL_H
