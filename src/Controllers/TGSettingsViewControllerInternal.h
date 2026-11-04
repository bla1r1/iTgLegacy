//
// TGSettingsViewControllerInternal.h - Private class extension and row model for TGSettingsViewController
//
#ifndef TGSETTINGSVIEWCONTROLLERINTERNAL_H
#define TGSETTINGSVIEWCONTROLLERINTERNAL_H

#import "TGSettingsViewController.h"
#import "TGUI.h"
#import "TGClient.h"
#import "TGTheme.h"
#import "TGThemeFile.h"
#import "TGStorageViewController.h"
#import "TGFileToolsViewController.h"
#import "TGSessionsViewController.h"
#import "TGDeviceViewController.h"
#import "TGDevice.h"
#import "TGCapabilities.h"
#import "TGEditProfileViewController.h"
#import "TGProfileViewController.h"
#import "TGQRViewController.h"
#import "TGPlaceholderViewController.h"
#import "TGIcons.h"
#import <QuartzCore/QuartzCore.h>

#pragma mark - the row model

static NSString *const TGRowTitle    = @"title";
static NSString *const TGRowDetail   = @"detail";
static NSString *const TGRowKind     = @"kind";
static NSString *const TGRowTap      = @"tap";       // void(^)(void)
static NSString *const TGRowToggle   = @"toggle";    // void(^)(BOOL)
static NSString *const TGRowOn       = @"on";
static NSString *const TGRowChecked  = @"checked";
static NSString *const TGRowIcon     = @"icon";
static NSString *const TGRowColour   = @"colour";
static NSString *const TGRowSubtitle = @"subtitle";

// Kinds
static NSString *const TGKindPlain       = @"plain";
static NSString *const TGKindDisclosure  = @"disclosure";
static NSString *const TGKindToggle      = @"switch";
static NSString *const TGKindCheck       = @"check";
static NSString *const TGKindDestructive = @"destructive";
static NSString *const TGKindProfile     = @"profile";
static NSString *const TGKindPreview     = @"preview";   // the two sample bubbles
static NSString *const TGKindAction      = @"action";    // blue text, no chevron
static NSString *const TGKindToggleInfo  = @"switchinfo";// icon, description, switch

static inline NSDictionary *TGSection(NSString *header, NSString *footer, NSArray *rows) {
	NSMutableDictionary *section = [NSMutableDictionary dictionary];
	if (header) section[@"header"] = header;
	if (footer) section[@"footer"] = footer;
	section[@"rows"] = rows ?: @[];
	return section;
}

static inline NSMutableDictionary *TGRow(NSString *kind, NSString *title) {
	return [@{TGRowKind : kind, TGRowTitle : title ?: @""} mutableCopy];
}

static inline NSDictionary *TGTapRow(NSString *title, NSString *detail, void (^tap)(void)) {
	NSMutableDictionary *row = TGRow(TGKindDisclosure, title);
	if (detail) row[TGRowDetail] = detail;
	if (tap) row[TGRowTap] = [tap copy];
	return row;
}

static inline NSDictionary *TGSwitchRow(NSString *title, BOOL on, void (^changed)(BOOL)) {
	NSMutableDictionary *row = TGRow(TGKindToggle, title);
	row[TGRowOn] = @(on);
	if (changed) row[TGRowToggle] = [changed copy];
	return row;
}

static inline NSDictionary *TGSwitchInfoRow(NSString *title, NSString *detail,
									 NSString *icon, UIColor *colour,
									 BOOL on, void (^changed)(BOOL)) {
	NSMutableDictionary *row = TGRow(TGKindToggleInfo, title);
	if (detail) row[TGRowDetail] = detail;
	if (icon)   row[TGRowIcon]   = icon;
	if (colour) row[TGRowColour] = colour;
	row[TGRowOn] = @(on);
	if (changed) row[TGRowToggle] = [changed copy];
	return row;
}

static inline NSDictionary *TGCheckRow(NSString *title, NSString *detail,
								BOOL checked, void (^tap)(void)) {
	NSMutableDictionary *row = TGRow(TGKindCheck, title);
	if (detail) row[TGRowDetail] = detail;
	row[TGRowChecked] = @(checked);
	if (tap) row[TGRowTap] = [tap copy];
	return row;
}

static inline NSDictionary *TGSubtitleRow(NSString *title, NSString *subtitle,
								   void (^tap)(void)) {
	NSMutableDictionary *row = TGRow(TGKindDisclosure, title);
	if (subtitle) row[TGRowDetail] = subtitle;
	row[TGRowSubtitle] = @YES;
	if (tap) row[TGRowTap] = [tap copy];
	return row;
}

static inline NSString *TGPrivacyLabel(NSString *value) {
	if ([value isEqualToString:@"everybody"]) return @"Everybody";
	if ([value isEqualToString:@"contacts"])  return @"My Contacts";
	if ([value isEqualToString:@"nobody"])    return @"Nobody";
	return @"...";
}

static inline NSDictionary *TGActionRow(NSString *title, void (^tap)(void)) {
	NSMutableDictionary *row = TGRow(TGKindAction, title);
	if (tap) row[TGRowTap] = [tap copy];
	return row;
}

static inline NSDictionary *TGRedRow(NSString *title, void (^tap)(void)) {
	NSMutableDictionary *row = TGRow(TGKindDestructive, title);
	if (tap) row[TGRowTap] = [tap copy];
	return row;
}

static inline NSDictionary *TGIconRow(NSString *title, NSString *icon, UIColor *colour,
							   void (^tap)(void)) {
	NSMutableDictionary *row = TGRow(TGKindDisclosure, title);
	row[TGRowIcon] = icon;
	row[TGRowColour] = colour;
	if (tap) row[TGRowTap] = [tap copy];
	return row;
}

/// Telegram's settings rows pair the glyph with the value the setting holds:
/// "Data and Storage  1.2 GB", "Language  Українська". The plain icon row has
/// nowhere to put that value, so these pages were either glyphs or values.
static inline NSDictionary *TGIconTapRow(NSString *title, NSString *detail,
								  NSString *icon, UIColor *colour,
								  void (^tap)(void)) {
	NSMutableDictionary *row = [TGIconRow(title, icon, colour, tap) mutableCopy];
	if (detail) row[TGRowDetail] = detail;
	return row;
}


static inline NSString *TGBytes(long long bytes) {
	if (bytes <= 0)              return @"0 KB";
	if (bytes < 1024 * 1024)     return [NSString stringWithFormat:@"%.0f KB",
											bytes / 1024.0];
	if (bytes < 1024LL * 1024 * 1024)
		return [NSString stringWithFormat:@"%.1f MB", bytes / (1024.0 * 1024.0)];
	return [NSString stringWithFormat:@"%.2f GB", bytes / (1024.0 * 1024.0 * 1024.0)];
}

@interface TGSettingsViewController (Tier2)
/// The profile-extras card: emoji status, profile audio, text styles and the
/// stake dice panel. Implemented in TGSettingsViewController+Tier2.m so the
/// root page does not grow another list of rows.
- (NSArray *)tier2Sections;
@end

@interface TGSettingsViewController () <
		UIImagePickerControllerDelegate, UINavigationControllerDelegate>

@property (nonatomic, strong) NSArray *sections;
@property (nonatomic, strong) NSMutableDictionary *privacy;    // setting -> value
@property (nonatomic, strong) NSMutableDictionary *muted;      // scope -> NSNumber
@property (nonatomic, strong) NSMutableDictionary *previews;   // scope -> NSNumber
@property (nonatomic, strong) UITableViewCell *profileCell;
@property (nonatomic, strong) UIImageView *avatarView;
@property (nonatomic, strong) NSArray *languages;
@property (nonatomic, strong) NSString *currentLanguage;
/// The current pack's record, read back from getLanguagePackInfo. The actions
/// that edit a pack need the whole object, not only the id.
@property (nonatomic, strong) NSDictionary *languageInfo;
/// The string list this page last read. updateLanguagePackStrings re-reads it
/// so the row's count and the sheet both follow the server.
@property (nonatomic, strong) NSArray *languagePackStrings;
/// The country this device is in, its preferred language and its flag. All
/// three come from Telegram so the page agrees with the phone step.
@property (nonatomic, strong) NSString *countryCode;
@property (nonatomic, strong) NSDictionary *countryInfo;
@property (nonatomic, strong) NSString *preferredCountryLanguage;
@property (nonatomic, strong) NSString *countryFlag;
@property (nonatomic, strong) NSArray *blocked;
@property (nonatomic, strong) NSArray *calls;
@property (nonatomic, assign) NSInteger accountTtl;
/// Privacy page: the lifetime new chats start with, loaded per open.
@property (nonatomic, assign) NSInteger autoDeleteDefault;
@property (nonatomic, assign) BOOL hasPassword;
@property (nonatomic, assign) BOOL passwordKnown;
@property (nonatomic, assign) BOOL suggestFrequent;
@property (nonatomic, assign) long long networkSent;
@property (nonatomic, assign) long long networkReceived;
@property (nonatomic, strong) NSString *tdlibVersion;
@property (nonatomic, assign) BOOL pickingProfilePhoto;
@property (nonatomic, assign) CGFloat lastScrollY;
/// The folders page: the account's own folders and Telegram's suggestions,
/// each loaded once the page opens.
@property (nonatomic, strong) NSArray *recommendedFolders;
/// Chat folder tags: the setting lives on Telegram's side, so the switch
/// starts on and remembers the last move for this launch.
@property (nonatomic, assign) BOOL folderTagsEnabled;
@property (nonatomic, assign) BOOL folderTagsLoaded;
/// Privacy: who may write first, and the chat shown as this account's own.
@property (nonatomic, assign) BOOL newChatAllowUnknown;
@property (nonatomic, assign) BOOL newChatPrivacyLoaded;
@property (nonatomic, assign) int64_t personalChatId;
/// Privacy: the read-date switch and the close-friends count, both read per
/// open. The contacts with a birthday nearby come from the client's update
/// cache, so the row can say how many the hide clears.
@property (nonatomic, assign) BOOL readDateLoaded;
@property (nonatomic, assign) BOOL showReadDate;
@property (nonatomic, assign) BOOL closeFriendsLoaded;
@property (nonatomic, assign) NSInteger closeFriendsCount;
@property (nonatomic, strong) NSArray *closeBirthdayRows;
/// The proxy page: every proxy TDLib knows, and whether one is on.
@property (nonatomic, strong) NSArray *proxies;
/// The downloads page: the list Telegram keeps, and how many are running.
@property (nonatomic, strong) NSArray *downloads;
@property (nonatomic, assign) NSInteger activeDownloads;
/// Custom Sounds: getSavedNotificationSounds answered, and whether it has.
@property (nonatomic, strong) NSArray *savedSounds;
@property (nonatomic, assign) BOOL savedSoundsLoaded;
/// Data and Storage: Telegram's Low/Medium/High auto-download presets, as
/// getAutoDownloadSettingsPresets answered them.
@property (nonatomic, strong) NSDictionary *autoDownloadPresets;
/// The Autosave page: private/group/channel defaults plus per-chat exceptions.
@property (nonatomic, strong) NSDictionary *autosaveSettings;
/// Appearance: the two accent colours this account has selected. -1 is the
/// profile's "none", which is a real value Telegram sends.
@property (nonatomic, assign) BOOL accentColorsLoaded;
@property (nonatomic, assign) NSInteger accentColorId;
@property (nonatomic, assign) NSInteger profileAccentColorId;
/// The payment page: the order Telegram kept from the last checkout. A 404
/// is "none saved", not a read failure, so the error is kept apart.
@property (nonatomic, strong) NSDictionary *savedOrder;
@property (nonatomic, strong) NSString *savedOrderError;
@property (nonatomic, assign) BOOL savedOrderLoaded;
/// Recent Calls: which diagnostics have already gone for a call, keyed by
/// "chatId:messageId" and kept in defaults so the row can say so after a
/// reopen. Sending a log twice is allowed; the row only records that one did.
@property (nonatomic, strong) NSMutableDictionary *callDiagnostics;
/// The root page names what its rows are set to, the way Telegram's does:
/// the cache size under Data and Storage, the current device under Devices,
/// the pack name under Language and the proxy state under Proxy. They are
/// read once per open and stay empty until the client answers, so a slow
/// answer leaves the row as it was rather than a placeholder.
@property (nonatomic, assign) long long rootCacheBytes;
@property (nonatomic, assign) BOOL rootCacheLoaded;
@property (nonatomic, strong) NSString *rootDeviceName;
@property (nonatomic, assign) NSInteger rootSessionCount;
@property (nonatomic, strong) NSString *rootLanguageName;
@property (nonatomic, strong) NSString *rootProxyDetail;

+ (NSArray *)privacySettings;
+ (NSArray *)privacyTitles;

- (void)rebuild;
- (void)repaint;
- (void)applyTheme;
- (void)loadForPage;
- (void)openPage:(TGSettingsPage)page;
- (void)openMyProfile;
- (void)openMyProfileOnTab:(NSString *)tab;
- (void)showAccountChoices;
- (void)toast:(NSString *)text;
- (void)pushPlaceholder:(NSString *)featureName;
- (void)openURL:(NSString *)url;
- (void)openSavedMessages;
- (void)openChat:(int64_t)chatId title:(NSString *)title;
- (void)addProxyByAsking;
- (void)addChatToFolder:(NSInteger)folderId named:(NSString *)title;
- (void)removeChatFromFolder:(NSInteger)folderId named:(NSString *)title;
- (void)runFolderActionFor:(NSDictionary *)folder;
- (void)runProxyActionFor:(NSDictionary *)proxy;
- (void)checkProxy:(NSDictionary *)proxy named:(NSString *)name;
- (void)editProxyAddress:(NSDictionary *)proxy named:(NSString *)name;
- (void)askRecoveryEmailCodeFor:(NSString *)address;
- (void)runDownloadActionFor:(NSDictionary *)download;
- (void)showPremiumState;
- (void)runRecentCallActionFor:(NSDictionary *)call;
- (void)noteCallDiagnostic:(NSString *)kind forCall:(NSDictionary *)call;
- (void)showTwoStepState;
- (void)showLostPasswordFlow;
- (void)askPasswordRecoveryCodeFor:(NSString *)pattern;
- (void)askResetPassword;
- (void)showLoginEmailFlow;
- (void)askLoginEmailCodeFor:(NSString *)pattern;
- (void)showChangePhoneFlow;
- (void)showPhoneChangeCodeStep:(NSDictionary *)info;
- (void)showTemporaryPasswordFlow;
- (void)showVerifyEmailFlow;
- (void)askEmailVerificationCodeFor:(NSString *)pattern;
- (void)showApplicationVerification;
- (void)showFreezeState;
- (void)showSubscriptionState;
- (void)showAgeVerificationState;
- (void)showRecaptchaVerification;
- (void)askCurrentPasswordThen:(void (^)(NSString *current))next;
- (void)askNewPasswordReplacing:(NSString *)current;
- (void)commitPassword:(NSString *)new replacing:(NSString *)current hint:(NSString *)hint;
- (void)askTurnPasswordOff;
- (void)askRecoveryAddress;
- (void)askDeleteAccountNow;
- (void)openSupport;
- (void)askCountryCode;
- (void)showLanguagePackInfo;
- (void)showLanguagePackStrings;
- (void)readLanguagePackString;
- (void)createCustomLanguagePack;
- (void)editLanguagePackName;
- (void)setLanguagePackString;
- (void)deleteLanguagePackString;
- (void)installServerLanguagePack;
- (void)synchronizeCurrentLanguagePack;
- (void)deleteCurrentLanguagePack;
- (void)refreshLanguagePage;
- (void)askPrivacyRuleAtIndex:(NSUInteger)index;
- (void)showCloseFriends;
- (void)hideCloseBirthdays;
- (void)chooseAccentColorForProfile:(BOOL)profile;
- (void)showDefaultBackground;
- (void)showEmojiChatThemes;
- (void)chooseTextSize;
- (void)chooseWallpaper;
- (void)presentWallpaperPicker;
- (void)uploadProfilePhoto:(UIImage *)image;
- (void)pickProfilePhoto;
- (void)clearTemporaryFiles;
- (void)openResolvedChat:(int64_t)chatId title:(NSString *)title;

- (NSArray *)buildSections;
- (NSArray *)rootSections;
/// The one Settings row the Tier 2 hub hangs from. Built in
/// TGSettingsViewController+Tier2.m so the root list stays a list.
- (NSDictionary *)tier2ToolsRow;
- (NSArray *)appearanceSections;
- (NSArray *)dataSections;
- (NSArray *)notificationSections;
- (NSArray *)soundSections;
- (NSArray *)activeNotificationSections;
- (void)addSoundFromBundle;
- (void)addSoundFromDocuments;
- (void)addSavedSoundAtPath:(NSString *)path;
- (void)showSavedSound:(NSDictionary *)sound;
- (void)removeSavedSound:(NSDictionary *)sound;
- (void)removeNotificationRow:(NSDictionary *)notification
                      inGroup:(NSDictionary *)group;
- (void)removeNotificationGroup:(NSDictionary *)group;
- (NSArray *)privacySections;
- (NSArray *)languageSections;
- (NSArray *)blockedSections;
- (NSArray *)powerSavingSections;
- (NSArray *)recentCallSections;
- (NSArray *)wallpaperSections;
- (NSArray *)paymentSections;
- (void)showBankCardLookup;
- (void)addOfferFlow;
- (void)validateOrderFlow;
- (void)askOrderFieldAtIndex:(NSUInteger)index
						keys:(NSArray *)keys
					 prompts:(NSArray *)prompts
					  values:(NSMutableDictionary *)values
				   allowSave:(BOOL)allowSave;
- (void)runOrderValidation:(NSMutableDictionary *)values allowSave:(BOOL)allowSave;
- (NSArray *)debugSections;
- (NSArray *)folderSections;
- (NSArray *)proxySections;
- (NSArray *)downloadSections;
- (NSArray *)autosaveSections;
- (void)chooseAutoDownloadPreset;
- (NSString *)autoDownloadPresetSummary;
- (void)changeAutosaveScope:(NSString *)scope photos:(BOOL)photos videos:(BOOL)videos;
- (void)clearAutosaveExceptions;
- (void)autosaveSettingsChanged;
- (void)languagePackStringsChanged:(NSString *)packId;

@end

#endif // TGSETTINGSVIEWCONTROLLERINTERNAL_H
