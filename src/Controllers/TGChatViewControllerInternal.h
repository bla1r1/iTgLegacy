//
// TGChatViewControllerInternal.h - Private class extension for TGChatViewController categories
//
#ifndef TGCHATVIEWCONTROLLERINTERNAL_H
#define TGCHATVIEWCONTROLLERINTERNAL_H

#import "TGChatViewController.h"
#import "TGUI.h"
#import "TGClient.h"
#import "TGVideoNoteViewController.h"
#import "TGRecordBar.h"
#import "TGSheet.h"
#import "TGTheme.h"
#import "TGIcons.h"
#import "TGSnackbar.h"
#import "TGMessageLayout.h"
#import "TGBubbleCell.h"
#import "TGMediaViewer.h"
#import "TGEmojiPanel.h"
#import "TGStreamingVoicePlayer.h"
#import "TGImageLruCache.h"
#import <MediaPlayer/MediaPlayer.h>
#import <AVFoundation/AVFoundation.h>
#import <CoreLocation/CoreLocation.h>
#import <AddressBookUI/AddressBookUI.h>
#import <MobileCoreServices/MobileCoreServices.h>
#import "TGStyle.h"

#import "TGChatGeometry.h"

@class TGMessageStreamStore;

@interface TGChatViewController () <UISearchBarDelegate, CLLocationManagerDelegate, TGEmojiPanelDelegate,
		UIScrollViewDelegate, AVAudioPlayerDelegate, TGStreamingVoicePlayerDelegate,
		ABPeoplePickerNavigationControllerDelegate, UIDocumentInteractionControllerDelegate>

@property (nonatomic, strong) UIDocumentInteractionController *docInteractionController;

@property (nonatomic, strong) UITableView *table;
@property (nonatomic, strong) UIView *inputBar;
@property (nonatomic, strong) UITextField *input;
@property (nonatomic, strong) UIButton *sendButton;
@property (nonatomic, strong) NSArray *messages;          // flattened TDLib dicts (may contain grouped album composites)
@property (nonatomic, strong) NSArray *rawMessages;       // raw flattened messages before grouping
@property (nonatomic, strong) TGImageLruCache *images;    // fileId -> UIImage (cap 40)
@property (nonatomic, strong) NSMutableSet *imagesRequested;
@property (nonatomic, strong) TGStreamingVoicePlayer *voicePlayer;
@property (nonatomic, assign) BOOL anchorToBottom;
@property (nonatomic, strong) NSMutableDictionary *lottiePaths;   // fileId -> path
@property (nonatomic, strong) TGImageLruCache *maps;             // messageId -> UIImage (cap 20)
@property (nonatomic, strong) NSMutableSet *mapsRequested;
@property (nonatomic, strong) NSMutableDictionary *quotes;       // messageId -> flattened
@property (nonatomic, strong) NSMutableSet *quotesRequested;
@property (nonatomic, strong) NSDictionary *actionMessage;   // long-pressed
/// Where the hold opened the menu, so the More card can appear beside the
/// same bubble after the first card is dismissed.
@property (nonatomic, assign) CGPoint actionMenuPoint;
/// The held message's presentation: the dimmed, blurred chat behind it and
/// its own snapshot lifted clear of the table. The cell itself never moves;
/// these are the two views the hold owns and takes down when the menu closes.
@property (nonatomic, strong) UIView *holdBackdropView;
@property (nonatomic, strong) UIImageView *holdBackdropImageView;
@property (nonatomic, strong) UIImageView *holdLiftView;
/// Where the lift started, so dismissing can put it back before removing it.
@property (nonatomic, assign) CGRect holdLiftOriginRect;
/// Bumped for every lift and every dismissal; a late blur or animation
/// completion that no longer matches this belongs to a hold that is gone.
@property (nonatomic, assign) NSInteger holdGeneration;
/// Whether the table was scrolling before the hold pinned it, so a dismiss
/// gives the chat back exactly as it was.
@property (nonatomic, assign) BOOL holdTableWasScrollable;
/// True while the lifted picture is animating back into the list. A second
/// dismiss in that window is the same dismissal, not a new one.
@property (nonatomic, assign) BOOL holdReturning;
@property (nonatomic, assign) int64_t replyToId;             // composing a reply
@property (nonatomic, assign) int64_t editingId;             // editing instead
@property (nonatomic, strong) UIView *composeBanner;         // "Reply to ..."
@property (nonatomic, strong) UIButton *micButton;
/// NO records a voice note, YES a round video note. A tap on the mic
/// switches the mode; a hold records the selected one.
@property (nonatomic, assign) BOOL videoNoteMode;
/// The wait before the touch turns into a recording, so a short tap can stay
/// a mode switch instead of beginning to write.
@property (nonatomic, strong) NSTimer *recordStartPendingTimer;
/// YES while the note being recorded was toggled view-once ("1"): one open
/// and it is gone, per Telegram's self destruct immediately.
@property (nonatomic, assign) BOOL recordOnce;
@property (nonatomic, strong) NSDate *recordBeganAt;
@property (nonatomic, assign) BOOL videoNoteOverlayActive;
@property (nonatomic, strong) TGVideoNoteViewController *videoNoteOverlay;
/// The local row a round note shows while it is still being transcoded, and
/// the pending message id TDLib gives it once sendMessage answers.
@property (nonatomic, assign) int64_t pendingNoteRowId;
@property (nonatomic, assign) int64_t pendingNoteRealId;
/// The same line the ring draws: transcode is the first half, upload the
/// second. Voice has no transcode, so its fraction is used as it is.
@property (nonatomic, assign) CGFloat pendingNoteProgress;
/// Set when the local row is cancelled while the transcode has already ended
/// and sendMessage is in flight; the answer is deleted instead of sent.
@property (nonatomic, assign) BOOL pendingNoteCancelled;
- (NSArray *)groupedMessagesFromMessages:(NSArray *)messages;
- (void)resumeGifAutoplayAfterScrolling;
- (void)refreshSendRings;
- (CGFloat)ringProgressForMessage:(NSDictionary *)m;
- (void)cancelSendingRow:(NSDictionary *)m;
// The bar over a chat nobody has spoken to: report spam, add to contacts.
@property (nonatomic, strong) UIView *actionBarView;
@property (nonatomic, strong) UILabel *actionBarLabel;
/// Following a reply: the quote header is the button; this is where it lands.
- (void)jumpToReplyById:(int64_t)replyId;
- (void)refreshActionBar;
@property (nonatomic, strong) UISearchBar *chatSearchBar;
@property (nonatomic, strong) NSArray *messagesBeforeSearch;
@property (nonatomic, strong) NSTimer *recordTimer;
@property (nonatomic, strong) TGRecordBar *recordPanel;      // shown while holding
/// Bumped on every show, so a hide still sliding knows it has been overtaken.
/// Not the views' tags: the banner finds its labels with viewWithTag:, which
/// also looks at the banner itself.
@property (nonatomic, assign) NSUInteger composeBannerShows;
@property (nonatomic, assign) NSUInteger stickerPanelShows;
@property (nonatomic, strong) UIView *recordLockView;
@property (nonatomic, strong) UIButton *recordCancelButton;
@property (nonatomic, strong) UIButton *recordSendButton;
@property (nonatomic, strong) UIButton *recordPauseButton;
@property (nonatomic, strong) UIButton *recordOnceButton;
@property (nonatomic, strong) UILabel *recordCancelSlideLabel;
@property (nonatomic, assign) int64_t playingMessageId;
@property (nonatomic, assign) BOOL isLoadingMoreHistory;
@property (nonatomic, assign) BOOL isLoadingNewerHistory;
@property (nonatomic, assign) BOOL atChatEnd;
/// The other end of the same thing: the history is open to its first message
/// and asking for more only costs a round trip.
@property (nonatomic, assign) BOOL atChatStart;
@property (nonatomic, strong) TGMessageStreamStore *streamStore;
@property (nonatomic, strong) NSTimer *playbackTimer;
@property (nonatomic, strong) MPMoviePlayerController *videoNotePlayer;
@property (nonatomic, strong) CAShapeLayer *videoNoteProgressLayer;
@property (nonatomic, strong) UIView *playerBar;        // the strip under the header
@property (nonatomic, strong) UIView *playerProgress;   // its line
@property (nonatomic, strong) UIButton *playerToggle;
@property (nonatomic, strong) UIButton *playerSpeed;
/// The speed chosen on the strip. It carries over to the next note in the queue.
@property (nonatomic, assign) float playbackRate;
@property (nonatomic, strong) UIButton *musicPrevious;
@property (nonatomic, strong) UIButton *musicNext;
@property (nonatomic, strong) UILabel *playerLabel;
@property (nonatomic, strong) TGImageLruCache *senderAvatars;   // userId -> UIImage (cap 50)
@property (nonatomic, strong) NSMutableSet *senderAvatarsRequested;
@property (nonatomic, strong) UIView *downloadHUD;
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
@property (nonatomic, strong) TGMessageLayoutCache *layoutCache;
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
/// Scroll to a message, fetching history around it when it is not loaded.
- (void)showMessageId:(int64_t)messageId gone:(NSString *)gone;
- (void)showJumpToDateSheet;
- (void)openCommentsForMessage:(NSDictionary *)m;

// Bots (TGChatViewController+Bots.m)
@property (nonatomic, strong) NSDictionary *replyKeyboard;
@property (nonatomic, strong) UIScrollView *botKeyboardPanel;
@property (nonatomic, strong) UIButton *botKeyboardToggle;
- (void)botButtonTapped:(UIButton *)key;
- (void)refreshReplyKeyboard;
- (void)replyMarkupChanged:(NSNotification *)note;
- (void)hideBotKeyboard;
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
/// True while the photo picker is choosing a replacement for an already
/// sent picture; the pick is an editMessageMedia, not a new message.
@property (nonatomic, assign) BOOL replacingPhoto;
/// The caption the replaced picture has to keep, since the picker may come
/// back long after the menu that named the message closed.
@property (nonatomic, copy) NSString *replacingPhotoCaption;
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
/// Jump-to-date sheet: the "N messages" line, filled when the count lands.
@property (nonatomic, strong) UILabel *pickCountLabel;
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
- (void)openChatWithUserToken:(NSString *)token;
- (void)presentExternalLink:(NSString *)link;
- (void)showExternalLink:(NSString *)link browser:(NSString *)browser info:(NSDictionary *)info;
- (void)openInstantViewForLink:(NSString *)link;
- (void)resolveInternalLinkKind:(NSString *)kind value:(NSString *)value
					   original:(NSString *)original
				 isTelegramHost:(BOOL)isTelegramHost
			   isTelegramScheme:(BOOL)isTelegramScheme;
- (void)continueInternalLinkKind:(NSString *)kind value:(NSString *)value
							link:(NSString *)link
				   isTelegramHost:(BOOL)isTelegramHost
				 isTelegramScheme:(BOOL)isTelegramScheme;
- (void)openPlainLink:(NSURL *)url;
- (void)openTelegramLinkByPath:(NSString *)clean
						   url:(NSURL *)u
				isTelegramHost:(BOOL)isTelegramHost
			  isTelegramScheme:(BOOL)isTelegramScheme
						  host:(NSString *)host;
- (void)loadPinnedMessage;
- (void)hidePinnedBanner;
- (void)pinnedBannerTapped;
- (void)stopPlayback;
- (void)stopVideoNote;
- (BOOL)showsUnplayedMarkFor:(NSDictionary *)m;
- (void)playVideoNoteForMessage:(NSDictionary *)m atRow:(NSInteger)row;
- (void)playVideoNoteAtPath:(NSString *)path row:(NSInteger)row;
- (void)togglePlayback;
- (void)cyclePlaybackSpeed;
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

- (void)updateRecordModeIcon;
- (void)toggleRecordMode;
- (void)recordStart;
- (void)recordFinish;
- (void)sendRecordedNoteOnce:(BOOL)once;
- (void)removeLocalNoteRow;
- (void)removeLocalNoteRowWithId:(int64_t)rowId;
- (void)recordPauseToggled;
- (void)toggleRecordOnce;
- (void)recordCancel;
- (void)recordTouchDown:(UIButton *)btn withEvent:(UIEvent *)event;
- (void)recordTouchUp:(UIButton *)btn withEvent:(UIEvent *)event;
- (void)recordTouchCancel;
- (void)recordDrag:(UIButton *)btn withEvent:(UIEvent *)event;
- (void)lockRecording;

@end

@interface TGChatViewController (Actions)

- (void)showActionsForRow:(NSInteger)row;
- (void)showActionsForRow:(NSInteger)row atPoint:(CGPoint)point;
- (void)messageHeld:(UILongPressGestureRecognizer *)hold;
/// Take the lift, the backdrop and the table's scroll state down. Safe to
/// call when nothing is lifted; the hold menu calls it as its dismissal.
- (void)endHoldPresentation;
/// Snapshot `cell`'s bubble, dim and blur the chat behind it, and lift the
/// copy to the top of the screen. Returns the rect it lands on - the menu's
/// anchor - or CGRectZero when the cell is not a bubble to lift, in which
/// case the caller keeps the old point-anchored menu. `didLift` runs when
/// the lift animation lands, so the menu appears under the settled copy.
- (CGRect)beginHoldPresentationForCell:(TGBubbleCell *)cell
                              didLift:(void (^)(CGRect anchor))didLift;
/// Remove any lift still on screen without its return animation. Used when a
/// new hold replaces one that is still fading, so its backdrop is not baked
/// into the next capture.
- (void)discardHoldPresentation;
- (void)runMessageAction:(NSString *)action;
- (void)showMoreActions;
- (void)showReactorsOfMessage:(NSDictionary *)m;
- (void)showReactorsOfMessage:(NSDictionary *)m
						emoji:(NSString *)emoji
				customEmojiId:(int64_t)customEmojiId;
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
- (void)fetchImageForMessage:(NSDictionary *)m;
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
- (void)docRowTapped:(UIButton *)sender;
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

- (BOOL)configureServiceCell:(TGBubbleCell *)cell message:(NSDictionary *)m layout:(TGMessageLayout *)layout isMine:(BOOL)mine indexPath:(NSIndexPath *)indexPath;
- (BOOL)configureAudioCell:(TGBubbleCell *)cell message:(NSDictionary *)m layout:(TGMessageLayout *)layout isMine:(BOOL)mine indexPath:(NSIndexPath *)indexPath;
- (BOOL)configureRoundOrStickerCell:(TGBubbleCell *)cell message:(NSDictionary *)m layout:(TGMessageLayout *)layout isMine:(BOOL)mine;
- (void)configureMediaForCell:(TGBubbleCell *)cell message:(NSDictionary *)m layout:(TGMessageLayout *)layout isMine:(BOOL)mine;
- (void)configureReactionChipsForCell:(TGBubbleCell *)cell message:(NSDictionary *)m layout:(TGMessageLayout *)layout;
- (void)reactionChipTapped:(UITapGestureRecognizer *)tap;
- (void)placeStickerEmoji:(TGBubbleCell *)cell message:(NSDictionary *)m inFrame:(CGRect)frame;
- (void)startGifIfWantedIn:(TGBubbleCell *)cell message:(NSDictionary *)m;

@end

// Cell placers and the sender colour palette live in TGChatGeometry.h.

#endif // TGCHATVIEWCONTROLLERINTERNAL_H
