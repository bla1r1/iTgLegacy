#ifndef TGPROFILEVIEWCONTROLLERINTERNAL_H
#define TGPROFILEVIEWCONTROLLERINTERNAL_H

#import "TGProfileViewController.h"
#import "TGClient.h"
#import "TGTheme.h"
#import "TGIcons.h"
#import "TGCallViewController.h"
#import "TGPopupMenu.h"
#import "TGForwardPicker.h"
#import "TGStyle.h"

static const CGFloat kActionTile = TGMetricActionTile;

// ── the profile's own geometry ───────────────────────────────────────────────
// The header stacks a picture, a name and a status line; the lists below it
// carry a thumbnail each. Built out of TGStyle's scales, named here because
// no other screen stacks them this way.

/// The picture's gap from the top of the header, then the name under it, then
/// the status line, then the row of action tiles.
static const CGFloat kAvatarTop     = TGMetricPadLarge;
static const CGFloat kNameTop       = TGMetricPad;
static const CGFloat kStatusTop     = TGMetricPad + TGMetricLineTitle;
static const CGFloat kActionsTop    = TGMetricPad + TGMetricLineTitle + TGMetricLineBody
		+ TGMetricPadMedium;
/// The side inset the header's text keeps, which is its own and not the
/// table's: the labels are centred, so this only stops a long name touching
/// the edge.
static const CGFloat kHeaderTextInset = TGMetricPadMedium;
/// The segmented control that picks a media tab, on a header of its own.
static const CGFloat kMediaTabsRow  = 38.0f;
static const CGFloat kMediaTabs     = 30.0f;
/// A story's thumbnail, and the emoji tile a gift is drawn into.
static const CGFloat kStoryThumb    = TGMetricListAvatar;
static const CGFloat kGiftTile      = TGMetricListAvatar;
static const CGFloat kGiftTileInset = TGMetricBorderWidth;
/// A member's picture, which is smaller than a list avatar because the row
/// it sits in is a settings row and not a person row.
static const CGFloat kMemberAvatar  = 32.0f;
/// The glyph beside a link in the media list.
static const CGFloat kLinkGlyph     = 24.0f;
/// The "Copied" toast, which is as wide as that word needs and no wider.
static const CGFloat kToastWidth    = 120.0f;
static const CGFloat kToastHeight   = 34.0f;

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
@property (nonatomic, assign) BOOL isLoadingMoreMedia;
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
- (void)showMemberActionsFor:(NSDictionary *)member;
- (void)runMemberAction:(NSString *)action onUser:(int64_t)userId named:(NSString *)name;
- (void)showInviteLink;

/// The photo-library picker the group photo opens, and the text it edits.
@property (nonatomic, assign) BOOL pickingChatPhoto;
@property (nonatomic, copy) NSString *chatDescription;

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
- (void)loadMoreMediaForCurrentTab;

@end

#endif // TGPROFILEVIEWCONTROLLERINTERNAL_H
