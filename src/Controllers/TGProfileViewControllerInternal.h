#ifndef TGPROFILEVIEWCONTROLLERINTERNAL_H
#define TGPROFILEVIEWCONTROLLERINTERNAL_H

#import "TGProfileViewController.h"
#import "TGClient.h"
#import "TGTheme.h"
#import "TGIcons.h"
#import "TGCallViewController.h"
#import "TGPopupMenu.h"
#import "TGForwardPicker.h"

static const CGFloat kActionTile = 52.0f;

static const NSInteger kSectionDetails = 0;
static const NSInteger kSectionStories = 1;
static const NSInteger kSectionGifts   = 2;
static const NSInteger kSectionMembers = 3;
static const NSInteger kSectionMedia   = 4;
static const NSInteger kSectionLogout  = 5;

@interface TGProfileViewController ()

@property (nonatomic, strong) NSMutableSet *thumbnailsRequested;
@property (nonatomic, assign) int64_t chatId;
@property (nonatomic, assign) int64_t userId;
@property (nonatomic, strong) NSString *name;
@property (nonatomic, strong) NSArray *details;   // label/value pairs
@property (nonatomic, strong) NSArray *photos;    // flattened messages
@property (nonatomic, strong) NSArray *files;
@property (nonatomic, strong) NSArray *voice;
@property (nonatomic, strong) NSArray *links;
/// The categories the bar is showing, in order: each is @{"title", "kind"}.
/// Built fresh on every render by currentMediaTabs.
@property (nonatomic, copy)   NSString *storedMediaKind;
@property (nonatomic, strong) NSArray *members;
@property (nonatomic, strong) NSArray *gifts;
@property (nonatomic, strong) NSArray *stories;
@property (nonatomic, assign) BOOL blocked;
@property (nonatomic, strong) UIImageView *avatarView;
// The one grid cell, cached by kind: "story" or "media", per
// mediaGridCacheContent. A fresh cache per kind, invalidated by data or tab.
@property (nonatomic, strong) NSString *mediaGridCacheContent;
@property (nonatomic, strong) UITableViewCell *storyGridCellCache;
@property (nonatomic, strong) UILabel *statusLabel;
// What the status line would say without the network: the last seen that
// answered, or the member count. The network override for TDLib-not-ready
// lives in statusLabelOwnerChanged (B4).
@property (nonatomic, strong) NSString *restingStatus;
- (void)statusLabelOwnerChanged:(NSNotification *)note;
@property (nonatomic, strong) NSArray *actionNames;
@property (nonatomic, assign) BOOL muted;
@property (nonatomic, strong) NSString *phoneNumber;

- (void)buildHeader;
- (void)loadDetails;
- (void)reloadTableDebounced;
- (void)doReloadTable;

@end

@interface TGProfileViewController (Actions)

- (void)buildActionsIn:(UIView *)header atY:(CGFloat)y;
- (void)actionTileTapped:(UIButton *)tile;
- (void)showMoreMenuFrom:(UIView *)tile;
- (void)runMoreAction:(NSString *)title;

@end

@interface TGProfileViewController (Media)

- (void)loadMedia;
- (void)mediaTabChanged:(UISegmentedControl *)sender;
- (NSArray *)currentMediaTabs;
- (NSString *)selectedMediaKind;
- (BOOL)selectedTabIsGrid;
- (CGFloat)storyGridHeight;
- (UITableViewCell *)mediaGridCell:(UITableView *)tableView;
- (NSArray *)selectedMediaRows;
- (void)openStoryAtIndex:(NSInteger)index;
- (void)closeStory:(UITapGestureRecognizer *)tap;
- (void)storyTileTapped:(UIButton *)button;
- (void)stopStoryPlayback;

@end

#endif // TGPROFILEVIEWCONTROLLERINTERNAL_H
