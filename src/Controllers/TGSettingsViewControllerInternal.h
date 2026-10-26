//
// TGSettingsViewControllerInternal.h - Private class extension and row model for TGSettingsViewController
//
#ifndef TGSETTINGSVIEWCONTROLLERINTERNAL_H
#define TGSETTINGSVIEWCONTROLLERINTERNAL_H

#import "TGSettingsViewController.h"
#import "TGClient.h"
#import "TGTheme.h"
#import "TGThemeFile.h"
#import "TGStorageViewController.h"
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

static inline UIColor *TGRGB(CGFloat r, CGFloat g, CGFloat b) {
	return [UIColor colorWithRed:r green:g blue:b alpha:1.0f];
}

static inline NSString *TGBytes(long long bytes) {
	if (bytes <= 0)              return @"0 KB";
	if (bytes < 1024 * 1024)     return [NSString stringWithFormat:@"%.0f KB",
											bytes / 1024.0];
	if (bytes < 1024LL * 1024 * 1024)
		return [NSString stringWithFormat:@"%.1f MB", bytes / (1024.0 * 1024.0)];
	return [NSString stringWithFormat:@"%.2f GB", bytes / (1024.0 * 1024.0 * 1024.0)];
}

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
@property (nonatomic, strong) NSArray *blocked;
@property (nonatomic, strong) NSArray *calls;
@property (nonatomic, assign) NSInteger accountTtl;
@property (nonatomic, assign) BOOL hasPassword;
@property (nonatomic, assign) BOOL passwordKnown;
@property (nonatomic, assign) BOOL suggestFrequent;
@property (nonatomic, assign) long long networkSent;
@property (nonatomic, assign) long long networkReceived;
@property (nonatomic, assign) NSInteger versionTaps;
@property (nonatomic, strong) NSString *tdlibVersion;
@property (nonatomic, assign) BOOL pickingProfilePhoto;
@property (nonatomic, assign) CGFloat lastScrollY;
/// The folders page: the account's own folders and Telegram's suggestions,
/// each loaded once the page opens.
@property (nonatomic, strong) NSArray *recommendedFolders;
/// The proxy page: every proxy TDLib knows, and whether one is on.
@property (nonatomic, strong) NSArray *proxies;
/// The downloads page: the list Telegram keeps, and how many are running.
@property (nonatomic, strong) NSArray *downloads;
@property (nonatomic, assign) NSInteger activeDownloads;

+ (NSArray *)privacySettings;
+ (NSArray *)privacyTitles;

- (void)rebuild;
- (void)repaint;
- (void)applyTheme;
- (void)loadForPage;
- (void)openPage:(TGSettingsPage)page;
- (void)openMyProfile;
- (void)explainAddAccount;
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
- (void)runDownloadActionFor:(NSDictionary *)download;
- (void)showPremiumState;
- (void)showTwoStepState;
- (void)askCurrentPasswordThen:(void (^)(NSString *current))next;
- (void)askNewPasswordReplacing:(NSString *)current;
- (void)commitPassword:(NSString *)new replacing:(NSString *)current hint:(NSString *)hint;
- (void)askTurnPasswordOff;
- (void)askRecoveryAddress;
- (void)askDeleteAccountNow;
- (void)openSupport;
- (void)askPrivacyRuleAtIndex:(NSUInteger)index;
- (void)chooseAutoNight;
- (void)chooseTextSize;
- (void)chooseWallpaper;
- (void)presentWallpaperPicker;
- (void)uploadProfilePhoto:(UIImage *)image;
- (void)pickProfilePhoto;

- (NSArray *)buildSections;
- (NSArray *)rootSections;
- (NSArray *)appearanceSections;
- (NSArray *)dataSections;
- (NSArray *)notificationSections;
- (NSArray *)privacySections;
- (NSArray *)languageSections;
- (NSArray *)blockedSections;
- (NSArray *)powerSavingSections;
- (NSArray *)recentCallSections;
- (NSArray *)debugSections;

@end

#endif // TGSETTINGSVIEWCONTROLLERINTERNAL_H
