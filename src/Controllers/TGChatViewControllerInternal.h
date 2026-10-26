//
// TGChatViewControllerInternal.h - Private class extension for TGChatViewController categories
//
#ifndef TGCHATVIEWCONTROLLERINTERNAL_H
#define TGCHATVIEWCONTROLLERINTERNAL_H

#import "TGChatViewController.h"
#import "TGClient.h"
#import "TGSheet.h"
#import "TGTheme.h"
#import "TGIcons.h"
#import "TGSnackbar.h"
#import "TGMessageLayout.h"
#import "TGBubbleCell.h"
#import "TGMediaViewer.h"
#import "TGEmojiPanel.h"
#import <MediaPlayer/MediaPlayer.h>
#import <AVFoundation/AVFoundation.h>
#import <CoreLocation/CoreLocation.h>
#import <AddressBookUI/AddressBookUI.h>
#import <MobileCoreServices/MobileCoreServices.h>

static const CGFloat kInputHeight = 48.0f;
/// The reply / edit strip above the composer: two lines, the way their client
/// shows who is being answered and what they said.
static const CGFloat kComposeBannerHeight = 44.0f;

@interface TGChatViewController () <UISearchBarDelegate, CLLocationManagerDelegate, TGEmojiPanelDelegate,
		UIScrollViewDelegate, AVAudioPlayerDelegate,
		ABPeoplePickerNavigationControllerDelegate>

@property (nonatomic, strong) UITableView *table;
@property (nonatomic, strong) UIView *inputBar;
@property (nonatomic, strong) UITextField *input;
@property (nonatomic, strong) UIButton *sendButton;
@property (nonatomic, strong) NSArray *messages;          // flattened TDLib dicts (may contain grouped album composites)
@property (nonatomic, strong) NSArray *rawMessages;       // raw flattened messages before grouping
@property (nonatomic, strong) NSMutableDictionary *images; // fileId -> UIImage
@property (nonatomic, strong) NSMutableSet *imagesRequested;
@property (nonatomic, strong) AVAudioPlayer *voicePlayer;
@property (nonatomic, assign) BOOL anchorToBottom;
@property (nonatomic, strong) NSMutableDictionary *lottiePaths;   // fileId -> path
@property (nonatomic, strong) NSMutableDictionary *maps;          // messageId -> UIImage
@property (nonatomic, strong) NSMutableSet *mapsRequested;
@property (nonatomic, strong) NSMutableDictionary *quotes;       // messageId -> flattened
@property (nonatomic, strong) NSMutableSet *quotesRequested;
@property (nonatomic, strong) NSDictionary *actionMessage;   // long-pressed
@property (nonatomic, assign) int64_t replyToId;             // composing a reply
@property (nonatomic, assign) int64_t editingId;             // editing instead
@property (nonatomic, strong) UIView *composeBanner;         // "Reply to ..."
@property (nonatomic, strong) UIButton *micButton;
@property (nonatomic, strong) UISearchBar *chatSearchBar;
@property (nonatomic, strong) NSArray *messagesBeforeSearch;
@property (nonatomic, strong) NSTimer *recordTimer;
@property (nonatomic, strong) UIView *recordPanel;      // shown while holding
@property (nonatomic, strong) UILabel *recordClock;
@property (nonatomic, strong) UIView *recordDot;
@property (nonatomic, strong) UIView *recordLockView;
@property (nonatomic, strong) UIButton *recordCancelButton;
@property (nonatomic, strong) UIButton *recordSendButton;
@property (nonatomic, strong) UILabel *recordCancelSlideLabel;
@property (nonatomic, assign) int64_t playingMessageId;
@property (nonatomic, assign) BOOL isLoadingMoreHistory;
@property (nonatomic, strong) NSTimer *playbackTimer;
@property (nonatomic, strong) MPMoviePlayerController *videoNotePlayer;
@property (nonatomic, strong) CAShapeLayer *videoNoteProgressLayer;
@property (nonatomic, strong) UIView *playerBar;        // the strip under the header
@property (nonatomic, strong) UIView *playerProgress;   // its line
@property (nonatomic, strong) UIButton *playerToggle;
@property (nonatomic, strong) UIButton *playerSpeed;
@property (nonatomic, strong) UIButton *musicPrevious;
@property (nonatomic, strong) UIButton *musicNext;
@property (nonatomic, strong) UILabel *playerLabel;
@property (nonatomic, strong) NSMutableDictionary *senderAvatars;   // userId -> UIImage
@property (nonatomic, strong) NSMutableSet *senderAvatarsRequested;
@property (nonatomic, strong) UILabel *downloadHUD;
@property (nonatomic, assign) NSInteger downloadingFileId;
@property (nonatomic, strong) CLLocationManager *locationManager;
/// The own live location this screen is holding open while it watches the
/// GPS: the message id that gets edited, the period it was sent for, and
/// the marks it is being edited against.
@property (nonatomic, assign) int64_t liveLocationMessageId;
@property (nonatomic, assign) NSInteger liveLocationSeconds;
@property (nonatomic, assign) NSTimeInterval liveLocationSince;
@property (nonatomic, assign) BOOL liveLocationInFlight;
@property (nonatomic, assign) NSInteger liveLocationRestarts;
@property (nonatomic, strong) UIImage *fullScreenImage;
@property (nonatomic, strong) UIImageView *wallpaperView;
@property (nonatomic, strong) UIButton *stickerButton;
@property (nonatomic, strong) TGEmojiPanel *stickerPanel;   // emoji, stickers, GIFs
@property (nonatomic, strong) NSMutableDictionary *layoutCache;
@property (nonatomic, strong) NSMutableDictionary *gifPaths;       // docId -> local MP4
// Chrome (TGChatViewController+Chrome)
@property (nonatomic, assign) int64_t readInboxAtOpen;   // where you had read up to
@property (nonatomic, assign) int64_t unreadFromId;      // the "Unread Messages" bar goes above it
@property (nonatomic, assign) BOOL unreadChecked;
@property (nonatomic, strong) UILabel *floatingDate;
@property (nonatomic, strong) UIButton *jumpButton;
@property (nonatomic, strong) UILabel *jumpBadge;
@property (nonatomic, assign) NSInteger newWhileAway;
@property (nonatomic, strong) UIPanGestureRecognizer *replyPanRecognizer;
@property (nonatomic, weak) UITableViewCell *replySwipeCell;
@property (nonatomic, assign) NSInteger replySwipeRow;
@property (nonatomic, strong) UIImageView *replyHint;
@property (nonatomic, strong) NSTimer *typingTimer;
@property (nonatomic, copy) NSString *typingBase;
@property (nonatomic, assign) NSInteger typingStep;
// The three owners of the header subtitle. The resting status is what the
// last-seen answered; the network line shows whenever TDLib is not ready
// (B4 - a chat opened offline used to freeze at "last seen...").
@property (nonatomic, strong) NSString *restingSubtitle;
@property (nonatomic, strong) NSString *networkSubtitle;
- (void)titleSubtitleOwnerChanged:(NSNotification *)note;
@property (nonatomic, strong) NSMutableSet *gifsRequested;
@property (nonatomic, strong) UILabel *titleNameLabel;
@property (nonatomic, strong) UILabel *titleSubtitleLabel;
/// The message the chat has pinned, so the menu offers Unpin on that one and
/// Pin on every other. Zero when nothing is pinned.
@property (nonatomic, assign) int64_t pinnedMessageId;
@property (nonatomic, strong) UIView *pinnedBannerView;
@property (nonatomic, strong) UIView *pinnedBannerHair;
@property (nonatomic, assign) BOOL isEditingMessages;
@property (nonatomic, strong) NSMutableSet *selectedMessageIds;
@property (nonatomic, strong) UIView *editToolbar;
@property (nonatomic, strong) UIButton *editDeleteButton;
@property (nonatomic, strong) UIButton *editForwardButton;
/// When "typing..." was last reported, so it is sent at most once every
/// four seconds while the composer is being typed into.
@property (nonatomic, assign) NSTimeInterval lastTypingReport;
/// True while the composer is editing a caption rather than a message's
/// text, which is a different request.
@property (nonatomic, assign) BOOL editingIsCaption;
/// The link the composer has already asked Telegram about, so a second
/// keystroke on the same one does not ask again.
@property (nonatomic, copy) NSString *previewedLink;
/// The player strip's own parts. It is 48 points tall because a track needs
/// its cover, its title and who it is by, which one 36-point line could not
/// hold.
@property (nonatomic, strong) UIImageView *playerArtwork;
@property (nonatomic, strong) UILabel *playerDetail;
@property (nonatomic, strong) UILabel *playerClock;
@property (nonatomic, strong) UIView *playerThumb;
@property (nonatomic, strong) UIButton *playerClose;

@property (nonatomic, strong) UIView *savedTitleView;
@property (nonatomic, strong) UIBarButtonItem *savedRightBarButtonItem;

/// The secret chat behind this chat, 0 when it is not one. Its state is the
/// header subtitle, and updates to it arrive while the chat is open.
@property (nonatomic, assign) NSInteger secretChatId;
- (void)refreshSecretState;

/// The scheduled queue's size, known when the send was last held, and the
/// picker sheet the hold's "Send At a Time..." opens.
@property (nonatomic, assign) NSInteger scheduledCount;
@property (nonatomic, strong) UIDatePicker *pickPicker;
@property (nonatomic, strong) TGSheet *pickSheet;
- (void)holdScheduledSheet;
- (void)sendHeldText:(NSDictionary *)state;

- (void)reload;
- (void)showPlaybackFailure;
- (void)applyTheme;
- (void)inputChanged;
- (void)reportTyping;
- (void)refreshLinkPreview;
- (void)sendImageAlbum:(NSArray *)images;
- (UIImage *)artworkForTrack:(NSDictionary *)m;
- (void)layoutPlayerBarForMusic:(BOOL)music;
- (void)joinChatByInviteLink:(NSString *)link;
- (void)openChatWithPhoneNumber:(NSString *)phone;
- (void)openPlainLink:(NSURL *)url;
- (void)openTelegramLinkByPath:(NSString *)clean
						   url:(NSURL *)u
				isTelegramHost:(BOOL)isTelegramHost
			  isTelegramScheme:(BOOL)isTelegramScheme
						  host:(NSString *)host;
- (void)loadPinnedMessage;
- (void)hidePinnedBanner;
- (void)stopPlayback;
- (void)stopVideoNote;
- (void)playVideoNoteAtPath:(NSString *)path row:(NSInteger)row;
- (void)togglePlayback;
- (void)showMusicBar;
- (void)playVoiceNoteForMessage:(NSDictionary *)m atRow:(NSInteger)row;
- (void)updatePlayerBar;
- (void)scrollToBottomAnimated:(BOOL)animated;
- (TGBubbleCell *)finalizeCell:(TGBubbleCell *)cell message:(NSDictionary *)m layout:(TGMessageLayout *)layout isMine:(BOOL)mine;
- (void)promptDeleteMessages:(NSArray *)ids;
- (void)executeDeleteMessages:(NSArray *)ids revoke:(BOOL)revoke;
- (void)updateEditToolbar;
- (void)openAudioAtPath:(NSString *)path duration:(NSInteger)duration sender:(NSString *)sender title:(NSString *)title;
- (void)downloadFileId:(NSInteger)fileId;
- (void)openFileWithViewer:(NSString *)filePath;
- (void)handleMessageTap:(NSDictionary *)m;
- (void)reloadTableDebounced;

@end

@interface TGChatViewController (Audio)

- (void)recordStart;
- (void)recordFinish;
- (void)recordCancel;
- (void)recordTouchDown:(UIButton *)btn withEvent:(UIEvent *)event;
- (void)recordTouchUp:(UIButton *)btn withEvent:(UIEvent *)event;
- (void)recordTouchCancel;
- (void)recordDrag:(UIButton *)btn withEvent:(UIEvent *)event;
- (void)lockRecording;

@end

@interface TGChatViewController (Actions)

- (void)showActionsForRow:(NSInteger)row;
- (void)messageHeld:(UILongPressGestureRecognizer *)hold;
- (void)runMessageAction:(NSString *)action;
- (void)pickMedia;
- (void)sendCurrentLocation;
- (void)pickContact;
- (void)presentAddContactForMessage:(NSDictionary *)m;
- (void)handleOpenLink:(NSString *)urlStr;

@end

@interface TGChatViewController (Search)

- (void)toggleChatSearch;
- (void)endChatSearch;

@end

@interface TGChatViewController (Input)

- (void)sendTapped;
- (void)buildInputBar:(CGRect)b;
- (void)clearComposeState;
- (void)showComposeBanner:(NSString *)text;
- (void)showComposeBanner:(NSString *)text subtitle:(NSString *)subtitle;
- (void)toggleStickerPanel;
- (void)openStickerPanelTab:(NSString *)name;
- (void)hideStickerPanel;
- (void)attachTapped;
- (void)shiftForKeyboardHeight:(CGFloat)height;
- (void)keyboardWillShow:(NSNotification *)note;
- (void)keyboardWillHide:(NSNotification *)note;

@end

@interface TGChatViewController (Media)

- (void)fetchMissingMaps;
- (void)resolveUnknownSenders;
- (void)fetchMissingQuotes;
- (void)fetchMissingImages;
- (void)applyThemeFromMessage:(NSDictionary *)m;
- (UIImage *)avatarForUser:(int64_t)userId name:(NSString *)name;
- (UIImage *)mapCardForLatitude:(double)lat longitude:(double)lon;
- (void)beginDownloadHUDForFile:(NSInteger)fileId;
- (void)endDownloadHUD;

@end

@interface TGChatViewController ()

// Layout and cell helpers
- (NSString *)quoteTextFor:(NSDictionary *)m;
- (NSString *)quoteAuthorFor:(NSDictionary *)m;
- (CGFloat)decorationHeightFor:(NSDictionary *)m;
- (NSString *)stampFor:(NSDictionary *)m;
- (CGFloat)timeWidthFor:(NSDictionary *)m;
- (BOOL)stampFitsInlineFor:(NSDictionary *)m;
- (CGFloat)layoutForwardIn:(TGBubbleCell *)cell message:(NSDictionary *)m width:(CGFloat)width;
- (CGFloat)pollHeightFor:(NSDictionary *)m;
- (BOOL)stampSitsOnPictureFor:(NSDictionary *)m;
- (CGSize)bodySizeFor:(NSDictionary *)m;
- (UIImage *)imageFor:(NSDictionary *)m;
- (CGSize)imageSizeFor:(NSDictionary *)m;
- (TGMessageLayout *)layoutForMessage:(NSDictionary *)m atRow:(NSInteger)row;
/// Runs: neighbouring bubbles from one sender a few minutes apart.
- (BOOL)runStartsAtRow:(NSInteger)row;
- (BOOL)runEndsAtRow:(NSInteger)row;
- (CGFloat)runHeightChangeAtRow:(NSInteger)row layout:(TGMessageLayout *)layout;
- (UIImage *)ticksForMessage:(NSDictionary *)m white:(BOOL)white;
- (BOOL)continuesAlbumAtRow:(NSInteger)row;
- (BOOL)albumContinuesAfterRow:(NSInteger)row;
- (void)pollOptionTapped:(UIButton *)option;
- (void)callCellButtonTapped:(UIButton *)btn;
- (void)contactCallButtonTapped:(UIButton *)btn;
- (void)contactAddButtonTapped:(UIButton *)btn;
- (void)videoNoteDiscTapped:(UITapGestureRecognizer *)tap;
- (float)playedFraction;
- (void)voiceDiscTapped:(UITapGestureRecognizer *)tap;
- (void)waveformScrubbed:(UIGestureRecognizer *)gesture;

// Chrome
- (NSArray *)messagesWithSeparators:(NSArray *)grouped;
- (void)noteFirstUnreadIn:(NSArray *)raw;
- (NSInteger)unreadSeparatorRow;
- (void)buildChrome;
- (void)applyChromeTheme:(TGTheme *)theme;
- (void)layoutChrome;
- (BOOL)isNearBottom;
- (void)noteArrivedWhileAway;
- (void)chromeDidScroll;
- (void)installSwipeToReply;
- (void)showChatAction:(NSString *)action resting:(NSString *)resting;
- (void)stopChrome;
- (void)sendImage:(UIImage *)image;

@end

UIColor *TGSenderColour(int64_t userId);

#endif // TGCHATVIEWCONTROLLERINTERNAL_H
