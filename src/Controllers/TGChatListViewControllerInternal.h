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
#import "TGStoriesCell.h"
#import "TGEmptyView.h"
#import "TGImageLruCache.h"
#import <QuartzCore/QuartzCore.h>

@interface TGChatListViewController () <UISearchBarDelegate>

@property (nonatomic, strong) TGEmptyView *emptyView;
@property (nonatomic, strong) NSArray *chats;
@property (nonatomic, assign) BOOL showsArchive;      // this IS the archive screen
@property (nonatomic, assign) NSInteger folderId;     // 0 = no folder
// A folder pill being dragged to a new slot: where on the pill the finger
// grabbed it, and the frame it lifted from.
@property (nonatomic, assign) CGFloat folderDragOffset;
@property (nonatomic, assign) CGRect folderDragFrame;
@property (nonatomic, strong) TGImageLruCache *avatars;   // fileId -> UIImage (cap 50)
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
/// The stories strip's rows, newest first. Loaded from -activeStoryRowsForList:
/// and only re-read when the last read is a few seconds old, because the
/// chat list reloads for every chat update and each strip read is up to 60
/// getChatActiveStories calls.
@property (nonatomic, strong) NSArray *storyRows;
@property (nonatomic, strong) NSDate *storyRowsReadAt;
@property (nonatomic, assign) BOOL storyRowsLoading;

- (void)reload;
- (void)reloadStoriesIfNeeded;
- (void)showStoryRow:(NSDictionary *)row;
- (void)runStoryRowMenu:(NSDictionary *)row;
- (void)openStoryComposer;
- (void)openStoriesMenu;
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
