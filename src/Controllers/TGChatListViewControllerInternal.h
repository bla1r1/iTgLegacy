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

@interface TGChatListViewController () <UISearchBarDelegate>

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
@property (nonatomic, assign) CGFloat parkOffset;  // scroll that hides search + archive strip
@property (nonatomic, assign) BOOL userRevealed;   // the strip was pulled out on purpose; keep it
@property (nonatomic, strong) NSArray *mergedChats;   // all chats: main + folders
@property (nonatomic, copy) NSString *mergedSignature;
@property (nonatomic, assign) BOOL mergeInFlight;

- (void)reload;
- (void)mergeAllFolderChats;
- (void)rebuildTableHeader;
- (void)folderTabTapped:(UIButton *)pill;
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
- (NSString *)titleForCurrentList;
- (void)rowHeld:(UILongPressGestureRecognizer *)hold;
- (void)showActionsForRow:(NSInteger)row;
- (void)runChatAction:(NSString *)action;
- (void)confirmDeleteChat:(int64_t)chatId;

@end

@interface TGChatListViewController (Search)

- (void)styleSearchBar;

@end

#endif // TGCHATLISTVIEWCONTROLLERINTERNAL_H
