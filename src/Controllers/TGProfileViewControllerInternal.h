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
#import "TGStreamingVoicePlayer.h"

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
/// The pill bar that picks a media tab, on a header of its own.
static const CGFloat kMediaTabsRow = TGMetricFolderTabRow;
static const CGFloat kMediaTabs    = TGMetricSearchScopeHeight;
/// A verified badge or an emoji status drawn beside the name, baked as a
/// static image rather than a masked layer on a scrolling header.
static const CGFloat kNameBadge     = TGMetricLineCaption;
/// The saved-music strip under the action plates: one glyph, the track, the
/// artist and a chevron, in a row tall enough to hit on a 3.5" screen.
static const CGFloat kMusicStripHeight = TGMetricRow;
static const CGFloat kMusicStripGlyph  = TGMetricSearchIconSize;
/// A story's thumbnail, and the emoji tile a gift is drawn into.
static const CGFloat kStoryThumb    = TGMetricListAvatar;
static const CGFloat kGiftTile      = TGMetricListAvatar;
static const CGFloat kGiftTileInset = TGMetricBorderWidth;
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

static const NSInteger kStoryGridCols  = 3;
static const CGFloat   kStoryGridGap   = TGMetricCollageGap;

/// The address a piece of text links to; nil when it has none.
NSURL *TGProfileFirstURL(NSString *text, NSArray *entities);

@interface TGProfileViewController () <TGStreamingVoicePlayerDelegate>

@property (nonatomic, strong) NSMutableSet *thumbnailsRequested;
@property (nonatomic, assign) int64_t chatId;
@property (nonatomic, assign) int64_t userId;
@property (nonatomic, strong) NSString *name;
@property (nonatomic, strong) NSArray *details;   // label/value pairs
@property (nonatomic, strong) NSArray *photos;    // flattened messages
@property (nonatomic, strong) NSArray *files;
@property (nonatomic, strong) NSArray *voice;
@property (nonatomic, strong) NSArray *links;
@property (nonatomic, strong) NSArray *music;     // audio messages (Music tab)
@property (nonatomic, strong) NSArray *groupsInCommon;
@property (nonatomic, strong) NSMutableDictionary *coverImages;
@property (nonatomic, assign) BOOL isLoadingMoreMedia;
/// The categories the bar is showing, in order: each is @{"title", "kind"}.
/// Built fresh on every render by currentMediaTabs.
@property (nonatomic, copy)   NSString *storedMediaKind;
@property (nonatomic, copy)   NSString *mainMediaKind;
/// Kinds whose page has already been asked for, so a re-selected tab does not
/// re-request its list on every switch (item 8: fetch when opened).
@property (nonatomic, strong) NSMutableSet *loadedMediaKinds;
@property (nonatomic, strong) NSMutableSet *loadingMediaKinds;
/// The total a tab reports, keyed by kind, for the subtitle under the header.
@property (nonatomic, strong) NSMutableDictionary *mediaCounts;
@property (nonatomic, strong) NSArray *members;
@property (nonatomic, strong) NSArray *gifts;
@property (nonatomic, strong) NSArray *stories;
/// The first saved track from userFullInfo, shown under the action plates
/// before the full profile-audio page answers.
@property (nonatomic, strong) NSDictionary *firstProfileAudio;
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
/// The note kept on this person's profile, and whether a private picture is
/// already set. Both are read back from userFullInfo and change the menu.
@property (nonatomic, copy) NSString *personalNote;
@property (nonatomic, assign) BOOL hasPersonalPhoto;
/// Which user action the photo picker is answering: "suggest", "personal".
@property (nonatomic, copy) NSString *pendingPhotoAction;

// Wave 1 additions: what the header and card read from the two profile calls.
@property (nonatomic, assign) NSInteger onlineCount;
@property (nonatomic, assign) NSInteger commonGroupCount;
@property (nonatomic, assign) BOOL isVerified;
@property (nonatomic, assign) BOOL isScam;
@property (nonatomic, assign) BOOL isFake;
@property (nonatomic, assign) BOOL isContact;
@property (nonatomic, assign) BOOL isBot;
@property (nonatomic, assign) BOOL birthdayToday;
@property (nonatomic, assign) int64_t emojiStatusId;
@property (nonatomic, strong) UIImage *emojiStatusImage;
@property (nonatomic, assign) CGFloat mediaTabsOffset;
@property (nonatomic, strong) UIImage *avatarImage;
@property (nonatomic, strong) NSNumber *avatarFileId;
/// Whether the owner allows calls and video calls; the tiles follow these
/// instead of the device's own codec support.
@property (nonatomic, assign) BOOL canCall;
@property (nonatomic, assign) BOOL canVideoCall;
/// The person's personal channel: "chatId", "title", "photoFileId". nil when
/// none is set.
@property (nonatomic, strong) NSDictionary *personalChannel;
/// The bio's entities, so the wrapped row keeps its links and mentions.
@property (nonatomic, strong) NSArray *bioEntities;
@property (nonatomic, strong) NSArray *noteEntities;
/// The active username, kept apart from the rows so the full-info pass can
/// rebuild the card without a second getUser.
@property (nonatomic, copy) NSString *username;
/// The voice/round note playing from the Voice tab, and which message id.
@property (nonatomic, strong) TGStreamingVoicePlayer *voicePlayer;
@property (nonatomic, assign) int64_t playingVoiceId;

- (void)buildHeader;
- (void)loadDetails;
- (void)reloadTableDebounced;
- (void)doReloadTable;
- (void)showMemberActionsFor:(NSDictionary *)member;
- (void)applyAvatarImageAtPath:(NSString *)path;
- (void)buildMusicStripIn:(UIView *)header atY:(CGFloat)y;
- (void)musicStripTapped;

/// The description the group profile's details section reads.
@property (nonatomic, copy) NSString *chatDescription;
/// A group's total member count. The member list is capped at what Telegram
/// returned first, so the header cannot count the rows.
@property (nonatomic, assign) NSInteger memberCount;
/// "owner", "admin", "member" or nil while getChatMember is still running.
/// Used for the same gating Group Settings does: only an administrator's
/// menu offers adding people or deleting the group.
@property (nonatomic, copy) NSString *myStatus;
@property (nonatomic, strong) NSDictionary *myRights;
@property (nonatomic, assign) BOOL canManage;
@property (nonatomic, assign) BOOL canInvite;
@property (nonatomic, assign) BOOL isGroup;
@property (nonatomic, assign) BOOL isChannel;
@property (nonatomic, strong) NSDictionary *chatPermissions;
/// The invite link the info card and menu copy; kept apart from the rows so
/// a reload can name it without rebuilding the card.
@property (nonatomic, copy) NSString *inviteLink;

- (void)loadOwnRole;
- (void)updateGroupStatus;
- (BOOL)isOwner;
- (BOOL)isOwnProfile;

@end

@interface TGProfileViewController (Actions)

- (void)buildActionsIn:(UIView *)header atY:(CGFloat)y;
- (void)actionTileTapped:(UIButton *)tile;
- (void)showMoreMenuFrom:(UIView *)tile;
- (void)runMoreAction:(NSString *)title;
- (void)addMemberTapped;
- (void)messageTapped;
- (void)addToContactsTapped;

@end

@interface TGProfileViewController (Media)

+ (CGFloat)storySideForWidth:(CGFloat)width;
- (void)loadMedia;
- (void)fetchMediaForKind:(NSString *)kind;
- (void)mediaTabSelected:(NSString *)kind;
- (BOOL)showsSavedMessages;
- (void)loadVisibleMediaTabIfNeeded;
- (NSArray *)currentMediaTabs;
- (NSString *)selectedMediaKind;
- (BOOL)selectedTabIsGrid;
- (CGFloat)storyGridHeight;
- (UITableViewCell *)mediaGridCell:(UITableView *)tableView;
- (UITableViewCell *)mediaGridCellForTableView:(UITableView *)tableView atRow:(NSInteger)row;
- (NSArray *)selectedMediaRows;
- (void)openStoryAtIndex:(NSInteger)index;
- (void)closeStory:(UITapGestureRecognizer *)tap;
- (void)storyTileTapped:(UIButton *)button;
- (void)photoTileTapped:(UIButton *)button;
- (void)stopStoryPlayback;
- (void)loadMoreMediaForCurrentTab;
- (void)applyArtworkToTrackCell:(UITableViewCell *)cell
						message:(NSDictionary *)message
					  indexPath:(NSIndexPath *)indexPath;
- (NSString *)linkDomainForMessage:(NSDictionary *)message;

@end

#endif // TGPROFILEVIEWCONTROLLERINTERNAL_H
