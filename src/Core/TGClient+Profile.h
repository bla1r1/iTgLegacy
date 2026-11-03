//
// TGClient+Profile - the profile surface between two people: the private
// note, who is a close friend, the read-date switch, suggested photos and
// birthdays, the sharing theme, and the account's own accent colours.
//
#import "TGClient+Base.h"
#import <UIKit/UIKit.h>

@interface TGClient (Profile)

/// A note only this account can see, kept on the other person's profile.
/// An empty note removes it.
- (void)setUserNote:(NSString *)note
			forUser:(int64_t)userId
		 completion:(void (^)(BOOL ok, NSString *error))completion;

/// The ids of every close friend, in Telegram's order.
- (void)closeFriendsWithCompletion:(void (^)(NSArray *userIds))completion;

/// Replaces the whole close-friends list. Telegram accepts contacts only, so
/// a refusal carries the server's reason.
- (void)setCloseFriends:(NSArray *)userIds
			 completion:(void (^)(BOOL ok, NSString *error))completion;

/// Whether other people see when this account has read their messages.
- (void)readDatePrivacySettingsWithCompletion:(void (^)(BOOL showReadDate))completion;

- (void)setReadDateShown:(BOOL)shown
			  completion:(void (^)(BOOL ok, NSString *error))completion;

/// Suggests a birthday the other person may accept; it does not change the
/// profile until they do.
- (void)suggestBirthdateDay:(NSInteger)day
					  month:(NSInteger)month
					   year:(NSInteger)year
					 forUser:(int64_t)userId
				  completion:(void (^)(BOOL ok, NSString *error))completion;

/// Sends a picture to the other person as a suggested profile photo.
- (void)suggestProfilePhotoAtPath:(NSString *)path
						  forUser:(int64_t)userId
					   completion:(void (^)(BOOL ok, NSString *error))completion;

/// Sets the picture only this account sees for a contact. A nil path removes
/// the personal picture.
- (void)setPersonalProfilePhotoAtPath:(NSString *)path
							  forUser:(int64_t)userId
						   completion:(void (^)(BOOL ok, NSString *error))completion;

/// The tab the account's profile opens on: "posts", "gifts", "media",
/// "files", "links", "music", "voice" or "gifs".
- (void)myMainProfileTabWithCompletion:(void (^)(NSString *tab))completion;

- (void)setMainProfileTab:(NSString *)tab
			   completion:(void (^)(BOOL ok, NSString *error))completion;

/// Drops the close-birthday strip for 24 hours.
- (void)hideContactCloseBirthdaysWithCompletion:(void (^)(BOOL ok, NSString *error))completion;

/// Contacts Telegram says have a birthday nearby. Kept live by
/// updateContactCloseBirthdays.
- (NSArray *)contactCloseBirthdayUsers;

/// The account Telegram names as support, with the server's refusal when it
/// cannot.
- (void)supportUserWithCompletion:(void (^)(NSDictionary *user, NSString *error))completion;

/// Accent colour ids to offer, in Telegram's order. 0-6 are always valid;
/// updateAccentColors adds the rest.
- (NSArray *)availableAccentColorIds;
- (NSArray *)availableProfileAccentColorIds;

/// The two colours this account has selected. -1 means the profile colour is
/// off, which Telegram expresses as -1.
- (void)myAccentColorsWithCompletion:(void (^)(NSInteger accentId,
											  NSInteger profileAccentId))completion;

/// The same two ids plus the two background-emoji ids. Setting a colour has to
/// hand these back to TDLib untouched, otherwise a colour change erases the
/// emoji pattern already on the account.
- (void)myAccentColoursWithCompletion:(void (^)(NSInteger accentId,
											   NSInteger profileAccentId,
											   int64_t backgroundEmojiId,
											   int64_t profileBackgroundEmojiId))completion;

/// The server's colour for one accent id, from the updateAccentColors record.
/// Nil when the record has not arrived for that id yet; callers draw a neutral
/// tile until it does.
- (UIColor *)accentColourForId:(NSInteger)colourId profile:(BOOL)profile;

- (void)setAccountAccentColor:(NSInteger)accentId
	   backgroundEmojiId:(int64_t)emojiId
			  completion:(void (^)(BOOL ok, NSString *error))completion;

- (void)setAccountProfileAccentColor:(NSInteger)accentId
				 backgroundEmojiId:(int64_t)emojiId
						completion:(void (^)(BOOL ok, NSString *error))completion;

/// Picking a colour must keep the background emoji the account already has.
/// These read the current ids first and pass them through, so a caller cannot
/// send 0 by forgetting them.
- (void)setAccountAccentColorPreservingBackgroundEmoji:(NSInteger)accentId
											completion:(void (^)(BOOL ok,
																 NSString *error))completion;
- (void)setAccountProfileAccentColorPreservingBackgroundEmoji:(NSInteger)accentId
												   completion:(void (^)(BOOL ok,
																		 NSString *error))completion;

/// Backgrounds the sharing screen can use: each is a dictionary with "id",
/// "name" and "colors". A refusal carries the server's sentence.
- (void)profileShareThemeBackdropsWithCompletion:(void (^)(NSArray *backdrops,
														  NSString *error))completion;

/// Sets the theme of the screen shown when this account's link is shared.
/// `backdropId` 0 with `useDefault` YES asks Telegram for its own background.
- (void)setProfileShareThemeForChat:(int64_t)chatId
						 backdropId:(NSInteger)backdropId
						 useDefault:(BOOL)useDefault
						 completion:(void (^)(BOOL ok, NSString *error))completion;

/// Returns the sharing screen to the default theme.
- (void)clearProfileShareThemeForChat:(int64_t)chatId
						   completion:(void (^)(BOOL ok, NSString *error))completion;

@end
