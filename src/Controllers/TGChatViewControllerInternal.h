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
#import "TGStyle.h"

static const CGFloat kInputHeight = TGMetricInputBarHeight;
/// The reply / edit strip above the composer: two lines, the way their client
/// shows who is being answered and what they said.
static const CGFloat kComposeBannerHeight = TGMetricRow;

// ── the chat's own geometry ──────────────────────────────────────────────────
// This screen's own dimensions, which no other screen has any use for: a call
// bubble's width allowance means nothing to the settings list. They live here
// instead of in TGStyle because a name in TGStyle that only one file reads is
// how the token layer came to hold more names than values. What they are built
// from is TGStyle's, so a change to the spacing or the line scale reaches them.

/// The gap between the last word of a message and the stamp on its line.
static const CGFloat kStampGap        = TGMetricPad;
/// A quote block: the author's line, then what they said, then a gap.
static const CGFloat kQuoteLine       = TGMetricLineSubhead;
static const CGFloat kQuoteBlock      = TGMetricLineSubhead + TGMetricLineSubhead + TGMetricPadSmall;
/// The stripe down the left of a quote block, and the text's indent past it.
static const CGFloat kQuoteBarWidth   = TGMetricPadTiny;
static const CGFloat kQuoteTextInset  = TGMetricPad;
/// A service plate - a day, or an event like "pinned a message" - sits on a
/// row of its own: a gap, one line of header type, the same gap again.
static const CGFloat kServiceGap      = TGMetricPad;
static const CGFloat kServiceEventGap = TGMetricPadSmall;
static const CGFloat kServicePlate    = TGMetricLineHeader;
static const CGFloat kServiceRow      = TGMetricPad + TGMetricLineHeader + TGMetricPad;
static const CGFloat kServiceEventRow = TGMetricPadSmall + TGMetricLineHeader + TGMetricPadSmall;
/// Text from the end of a service plate, and the margin the plate keeps from
/// the sides of the table so a long day never runs edge to edge.
static const CGFloat kServicePlatePad    = TGMetricPadMedium;
static const CGFloat kServicePlateMargin = TGMetricPadWide + TGMetricPadMedium;
/// The unread marker, which is a band across the table rather than a plate.
static const CGFloat kUnreadBar       = TGMetricLineBody + TGMetricPadSmall;
/// A call bubble: a glyph beside two lines, at a height that does not vary.
static const CGFloat kCallBubble      = TGMetricButtonHeight;
/// What a call bubble keeps beside its text for the glyph and the button, and
/// the least width it will shrink to so a short "Missed call" is still a card.
static const CGFloat kCallBubbleRoom  = 80.0f;
static const CGFloat kCallBubbleMin   = 190.0f;
/// A document bubble, wide enough for a file name beside its tile.
static const CGFloat kDocBubble       = 225.0f;
/// A contact bubble: a disc, a name and a number, with a call button under.
static const CGFloat kContactBubble   = 230.0f;
static const CGFloat kContactBubbleH  = TGMetricPersonRow + TGMetricButtonHeightSmall;
/// A location bubble: the map card, with a caption strip beneath it.
static const CGFloat kLocationBubble  = 224.0f;
static const CGFloat kLocationBubbleH = TGMetricMapHeight + TGMetricRow;
/// A round video message, and an animated sticker. Both square.
static const CGFloat kRoundSide       = 180.0f;
static const CGFloat kLottieSide      = 128.0f;
/// The narrowest a text bubble will be, so one word is still a bubble.
static const CGFloat kBubbleMinW      = 170.0f;
/// A bubble that carries a picture is this wide whatever the picture is.
static const CGFloat kPicBubbleW      = 190.0f;
/// The shortest a bubble row gets, so a one-word message still reads as a
/// row and not as a line of text in a list.
static const CGFloat kBubbleRowMin    = TGMetricRow - TGMetricPadSmall;
/// A poll row: the dot's column, then the option, then its share on the right,
/// over a track that runs the row's width.
static const CGFloat kPollTextColumn  = TGMetricPadLarge + TGMetricPad;
static const CGFloat kPollShareWidth  = 40.0f;
static const CGFloat kPollTrackDrop   = TGMetricPadSmall;
static const CGFloat kPollTrackHeight = TGMetricPadTiny;
/// The "N voted" line under a poll's question.
static const CGFloat kPollVotedLine   = TGMetricPadTiny + TGMetricLineRow;
/// A call bubble's arrow, and the button on its right.
static const CGFloat kCallArrow       = 16.0f;
static const CGFloat kCallButton      = 32.0f;
/// A contact bubble: the initials disc, and where its two buttons begin.
static const CGFloat kContactDisc     = 42.0f;
static const CGFloat kContactDiscTop  = TGMetricPad;
static const CGFloat kContactButtons  = TGMetricPersonRow;
/// A file or contact bubble's text column, which clears the tile beside it.
static const CGFloat kTileTextGap     = TGMetricPadMedium;
/// A file bubble's name, which may wrap to two lines, and its meta line.
static const CGFloat kFileNameBlock   = TGMetricLineBody + TGMetricLineBody;
static const CGFloat kFileMetaTop     = TGMetricPad + TGMetricLineBody + TGMetricLineBody
		+ TGMetricPadTiny;
/// A location bubble: the pin over the map, and the attribution strip.
static const CGFloat kMapPinWidth     = 28.0f;
static const CGFloat kMapPinHeight    = 36.0f;
static const CGFloat kMapPinLift      = TGMetricPadSmall;
static const CGFloat kMapCreditWidth  = 68.0f;
/// A voice note: the play disc, the waveform, and the duration under it.
static const CGFloat kVoiceDisc       = 36.0f;
static const CGFloat kVoiceWaveHeight = TGMetricLineBody;
static const CGFloat kVoiceWaveTop    = TGMetricPadMedium;
static const CGFloat kVoiceClockWidth = 44.0f;
/// The play disc over a video, and the one over an animation.
static const CGFloat kVideoDisc       = 48.0f;
static const CGFloat kGifDisc         = 42.0f;
/// A caption plate on a picture: how far in it sits, and the room it keeps.
static const CGFloat kCaptionInset    = TGMetricPadSmall;
/// How far a stamp on a picture sits in from its corner.
static const CGFloat kMediaStampInset = TGMetricPadSmall;

// ── the record bar and the player bar ───────────────────────────────────────
// The two strips that take the composer's place: one while a voice note is
// being recorded, one while a track is playing.

/// The red dot, the running clock beside it, and the "slide to cancel" line.
static const CGFloat kRecordDotX      = TGMetricPadLarge;
static const CGFloat kRecordClockX    = 32.0f;
static const CGFloat kRecordClockW    = 62.0f;
static const CGFloat kRecordSlideX    = 100.0f;
static const CGFloat kRecordSlideRoom = 180.0f;
/// The Cancel button that replaces all of it once recording is locked.
static const CGFloat kRecordCancelW   = 100.0f;
static const CGFloat kRecordCancelH   = 32.0f;
/// The lock pill above the mic: a padlock over an arrow.
static const CGFloat kRecordLockGlyph = 18.0f;
static const CGFloat kRecordLockArrow = 16.0f;
static const CGFloat kRecordLockArrowY = 36.0f;
static const CGFloat kRecordLockRest  = TGMetricPadMedium;
static const CGFloat kRecordLockLift  = TGMetricPadLarge;
/// The player bar: artwork, a play button, two lines of text, a clock, and
/// the transport buttons that only a music track gets.
static const CGFloat kPlayerArtX      = TGMetricPad;
static const CGFloat kPlayerArtLift   = 1.0f;
static const CGFloat kPlayerButton    = 28.0f;
static const CGFloat kPlayerButtonGap = TGMetricPadSmall;
static const CGFloat kPlayerArtGap    = 6.0f;
static const CGFloat kPlayerCloseW    = TGMetricCloseSide;
static const CGFloat kPlayerRightEdge = 38.0f;
static const CGFloat kPlayerClockW    = 72.0f;
static const CGFloat kPlayerClockDrop = TGMetricPad;
static const CGFloat kPlayerSpeedW    = 40.0f;
static const CGFloat kPlayerTextMin   = 40.0f;
static const CGFloat kPlayerProgressH = TGMetricPadTiny;
/// The bar's two lines are packed into the height of the button beside them,
/// so they are tighter than the line scale and say so here rather than
/// borrowing a name from it.
static const CGFloat kPlayerTitleLine  = 15.0f;
static const CGFloat kPlayerDetailLine = 13.0f;
/// The composer: the attach button, the field between them, the send button
/// and the sticker button tucked in beside it.
static const CGFloat kAttachWidth     = 34.0f;
static const CGFloat kComposerInset   = TGMetricPadSmall;
static const CGFloat kSendInset       = 6.0f;
static const CGFloat kStickerInset    = TGMetricSendSide + 6.0f;
static const CGFloat kStickerWidth    = 30.0f;
static const CGFloat kFieldLeft       = 40.0f;
static const CGFloat kFieldRoom       = 120.0f;
static const CGFloat kFieldInsetV     = TGMetricPad;
static const CGFloat kFieldLeftPad    = TGMetricPadMedium;
/// The reply / edit banner above the composer: a stripe, then two lines.
static const CGFloat kBannerStripeX   = TGMetricPadMedium + TGMetricPadTiny;
static const CGFloat kBannerStripeTop = TGMetricPad;
static const CGFloat kBannerTextX     = 22.0f;
static const CGFloat kBannerTitleTop  = TGMetricPadSmall;
/// The title view in the navigation bar: the chat's name over who is there.
static const CGFloat kTitleWidth      = 200.0f;
static const CGFloat kTitleRow        = TGMetricListAvatar;
/// The pinned-message strip under the navigation bar.
static const CGFloat kPinnedBanner    = 34.0f;
/// The cross that dismisses the banner.
static const CGFloat kBannerCloseGlyph = 16.0f;

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
- (void)pinnedBannerTapped;
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
- (void)showActionsForRow:(NSInteger)row atPoint:(CGPoint)point;
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
