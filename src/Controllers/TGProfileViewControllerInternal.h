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

@interface TGProfileViewController () <UIActionSheetDelegate, UIAlertViewDelegate, UIScrollViewDelegate>

@property (nonatomic, strong) UIScrollView *mediaStrip;
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
@property (nonatomic, strong) NSArray *mediaTabs;
@property (nonatomic, strong) NSArray *members;
@property (nonatomic, strong) NSArray *gifts;
@property (nonatomic, strong) NSArray *stories;
@property (nonatomic, assign) BOOL blocked;
@property (nonatomic, strong) UIImageView *avatarView;
@property (nonatomic, strong) UITableViewCell *mediaStripCell;
@property (nonatomic, strong) UITableViewCell *storyGridCellCache;
@property (nonatomic, strong) UILabel *statusLabel;
@property (nonatomic, strong) NSArray *actionNames;
@property (nonatomic, assign) BOOL muted;
@property (nonatomic, strong) NSString *phoneNumber;
@property (nonatomic, assign) NSInteger selectedMediaTab;

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
- (BOOL)selectedTabIsStrip;
- (BOOL)selectedTabIsGrid;
- (CGFloat)storyGridHeight;
- (UITableViewCell *)storyGridCell:(UITableView *)tableView;
- (NSArray *)selectedMediaRows;
- (UITableViewCell *)photoStripCell:(UITableView *)tableView;
- (void)fetchVisibleThumbnails;
- (void)openStoryAtIndex:(NSInteger)index;
- (void)closeStory:(UITapGestureRecognizer *)tap;
- (void)storyTileTapped:(UIButton *)button;
- (void)stopStoryPlayback;

@end

#endif // TGPROFILEVIEWCONTROLLERINTERNAL_H
