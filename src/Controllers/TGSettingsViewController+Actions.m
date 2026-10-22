#import "TGSettingsViewControllerInternal.h"

@implementation TGSettingsViewController (Actions)

#pragma mark - actions

/// Your own profile, as everyone else sees it - their "My Profile" row.
- (void)openMyProfile {
	int64_t userId = [[TGClient shared].me[@"id"] longLongValue];
	if (!userId)
		return;
	Class profileClass = NSClassFromString(@"TGProfileViewController");
	UIViewController *profile = [[profileClass alloc]
			initWithChatId:userId userId:userId
					 title:[TGClient shared].me[@"first_name"] ?: @"Profile"];
	profile.hidesBottomBarWhenPushed = YES;
	[self.navigationController pushViewController:profile animated:YES];
}

/// A second account is a second TDLib client: another database, another
/// connection, and the whole message cache twice over. On 504MB that is not a
/// switch to flip, so the row says what it is waiting for rather than failing
/// after the user has typed a phone number into it.
- (void)explainAddAccount {
	if ([TGCapabilities canHoldMultipleAccounts]){
		[self toast:@"Multiple accounts are not wired up yet on this build."];
		return;
	}
	UIAlertView *alert = [[UIAlertView alloc] initWithTitle:@"Add Account"
			message:[NSString stringWithFormat:
					@"A second account needs a second TDLib client and a second "
					@"copy of the cache. This is a %@ device with %lu MB, and "
					@"that needs the Full tier - 2 GB or more.",
					[TGDevice tierName] ?: @"Legacy", (unsigned long)[TGCapabilities memoryMB]]
		   delegate:nil cancelButtonTitle:@"OK" otherButtonTitles:nil];
	[alert show];
}

- (void)pickProfilePhoto {
	if (![UIImagePickerController isSourceTypeAvailable:
			UIImagePickerControllerSourceTypePhotoLibrary])
		return;
	self.pickingProfilePhoto = YES;
	UIImagePickerController *picker = [[UIImagePickerController alloc] init];
	picker.sourceType = UIImagePickerControllerSourceTypePhotoLibrary;
	picker.delegate = self;
	[self presentViewController:picker animated:YES completion:nil];
}

- (void)pushPlaceholder:(NSString *)featureName {
	TGPlaceholderViewController *placeholder = [[TGPlaceholderViewController alloc] init];
	placeholder.featureName = featureName;
	placeholder.hidesBottomBarWhenPushed = YES;
	[self.navigationController pushViewController:placeholder animated:YES];
}

- (void)openURL:(NSString *)url {
	[[UIApplication sharedApplication] openURL:[NSURL URLWithString:url]];
}

/// Saved Messages is a real chat - your own - so it opens as one rather than
/// as a page saying the feature is missing.
- (void)openSavedMessages {
	int64_t chatId = [[TGClient shared] savedMessagesChatId];
	if (!chatId){
		UIAlertView *alert = [[UIAlertView alloc] initWithTitle:@"Saved Messages"
				message:@"This account is still loading."
			   delegate:nil cancelButtonTitle:@"OK" otherButtonTitles:nil];
		[alert show];
		return;
	}
	[self openChat:chatId title:@"Saved Messages"];
}

- (void)openChat:(int64_t)chatId title:(NSString *)title {
	// Loaded by name to keep the settings screen from knowing about chats in
	// general; it only ever opens one at a time.
	Class chatClass = NSClassFromString(@"TGChatViewController");
	UIViewController *chat = [[chatClass alloc] init];
	[chat setValue:@(chatId) forKey:@"chatId"];
	[chat setValue:(title ?: @"") forKey:@"chatTitle"];
	chat.hidesBottomBarWhenPushed = YES;
	[self.navigationController pushViewController:chat animated:YES];
}

/// Folders are a filter over the chat list, so this says where they are rather
/// than building a second copy of the same sheet.
- (void)showFolders {
	NSArray *folders = [TGClient shared].folders;
	NSString *message = folders.count
			? [NSString stringWithFormat:@"%lu folders. Pick one from Folders "
					@"above the chat list.", (unsigned long)folders.count]
			: @"This account has no chat folders. They are set up in Telegram "
			  @"on a desktop or a newer phone, and appear here.";
	UIAlertView *alert = [[UIAlertView alloc] initWithTitle:@"Folders"
			message:message delegate:nil cancelButtonTitle:@"OK" otherButtonTitles:nil];
	[alert show];
}

- (void)showPremiumState {
	[[TGClient shared] premiumStateWithCompletion:^(NSString *summary){
		UIAlertView *alert = [[UIAlertView alloc] initWithTitle:@"Telegram Premium"
				message:summary.length ? summary
						: @"This account does not have Premium. It is bought in "
						  @"an official client; what it unlocks works here."
			   delegate:nil cancelButtonTitle:@"OK" otherButtonTitles:nil];
		[alert show];
	}];
}

/// Setting a password is a multi-step flow with a recovery address; this screen
/// reports the state and says where to change it rather than pretending to.
- (void)showTwoStepState {
	[[TGClient shared] hasPasswordWithCompletion:^(BOOL has, NSString *email){
		NSString *message = has
				? [NSString stringWithFormat:@"Two-step verification is on.%@",
						email.length ? [NSString stringWithFormat:
								@"\nRecovery address: %@", email] : @""]
				: @"Two-step verification is off. It is set up in an official "
				  @"client; once it is on, this app asks for the password when "
				  @"signing in.";
		UIAlertView *alert = [[UIAlertView alloc] initWithTitle:@"Two-Step Verification"
				message:message delegate:nil cancelButtonTitle:@"OK" otherButtonTitles:nil];
		[alert show];
	}];
}

- (void)openSupport {
	// Their support is a chat, not a web page.
	__weak typeof(self) weakSelf = self;
	[[TGClient shared] chatWithUsername:@"BotSupport"
							 completion:^(int64_t chatId, NSString *title){
		if (!chatId){
			UIAlertView *alert = [[UIAlertView alloc] initWithTitle:@"Support"
					message:@"Support is not reachable from this account right now."
				   delegate:nil cancelButtonTitle:@"OK" otherButtonTitles:nil];
			[alert show];
			return;
		}
		[weakSelf openChat:chatId title:(title ?: @"Telegram Support")];
	}];
}

- (void)askPrivacyRuleAtIndex:(NSUInteger)index {
	UIActionSheet *sheet = [[UIActionSheet alloc]
			initWithTitle:[TGSettingsViewController privacyTitles][index]
				 delegate:self
		cancelButtonTitle:nil
   destructiveButtonTitle:nil
		otherButtonTitles:@"Everybody", @"My Contacts", @"Nobody", nil];
	sheet.cancelButtonIndex = [sheet addButtonWithTitle:@"Cancel"];
	sheet.tag = 91 + index;
	[sheet showInView:self.view];
}

- (void)chooseAutoNight {
	UIActionSheet *sheet = [[UIActionSheet alloc] initWithTitle:@"Auto-Night Mode"
													  delegate:self
											 cancelButtonTitle:nil
										destructiveButtonTitle:nil
											 otherButtonTitles:@"Disabled",
														   @"22:00 - 07:00",
														   @"21:00 - 08:00",
														   @"23:00 - 06:00", nil];
	sheet.cancelButtonIndex = [sheet addButtonWithTitle:@"Cancel"];
	sheet.tag = 87;
	[sheet showInView:self.view];
}

/// Four sizes is enough on a 3.5-inch screen; a slider would be finer than
/// the difference it makes.
- (void)chooseTextSize {
	UIActionSheet *sheet = [[UIActionSheet alloc] initWithTitle:@"Message text size"
													  delegate:self
											 cancelButtonTitle:nil
										destructiveButtonTitle:nil
											 otherButtonTitles:@"13 pt", @"15 pt",
														   @"17 pt", @"19 pt", nil];
	sheet.cancelButtonIndex = [sheet addButtonWithTitle:@"Cancel"];
	sheet.tag = 88;
	[sheet showInView:self.view];
}

#pragma mark - wallpaper

- (void)chooseWallpaper {
	if ([TGTheme shared].wallpaper){
		UIActionSheet *sheet = [[UIActionSheet alloc] initWithTitle:@"Chat wallpaper"
														  delegate:self
												 cancelButtonTitle:nil
											destructiveButtonTitle:@"Remove"
												 otherButtonTitles:@"Choose another", nil];
		sheet.cancelButtonIndex = [sheet addButtonWithTitle:@"Cancel"];
		sheet.tag = 89;
		[sheet showInView:self.view];
		return;
	}
	[self presentWallpaperPicker];
}

- (void)presentWallpaperPicker {
	if (![UIImagePickerController isSourceTypeAvailable:
			UIImagePickerControllerSourceTypePhotoLibrary])
		return;
	UIImagePickerController *picker = [[UIImagePickerController alloc] init];
	picker.sourceType = UIImagePickerControllerSourceTypePhotoLibrary;
	picker.delegate = self;
	[self presentViewController:picker animated:YES completion:nil];
}

- (void)imagePickerController:(UIImagePickerController *)picker
		didFinishPickingMediaWithInfo:(NSDictionary *)info {
	[picker dismissViewControllerAnimated:YES completion:nil];
	UIImage *image = info[UIImagePickerControllerOriginalImage];
	if (!image){
		self.pickingProfilePhoto = NO;
		return;
	}

	// One picker serves the wallpaper and the profile picture, so it has to
	// know which row opened it.
	if (self.pickingProfilePhoto){
		self.pickingProfilePhoto = NO;
		[self uploadProfilePhoto:image];
		return;
	}
	[[TGTheme shared] setWallpaperImage:image];
	[self rebuild];
}

/// TDLib uploads from a file, and a camera frame is far larger than a picture
/// anyone will ever see as an avatar - so it is scaled before it is written.
- (void)uploadProfilePhoto:(UIImage *)image {
	UIImage *scaled = [TGIcons decodedImage:image
								fittingSize:CGSizeMake(640, 640)
									   fill:NO scale:1.0f];
	NSString *path = [NSTemporaryDirectory()
			stringByAppendingPathComponent:@"profile-photo.jpg"];
	if (![UIImageJPEGRepresentation(scaled, 0.9f) writeToFile:path atomically:YES]){
		[self toast:@"Could not prepare the picture."];
		return;
	}

	__weak typeof(self) weakSelf = self;
	[[TGClient shared] setProfilePhotoAtPath:path completion:^(BOOL ok){
		if (!ok){
			[weakSelf toast:@"Telegram refused the picture."];
			return;
		}
		// The new file id arrives with the updateUser that follows.
		weakSelf.profileCell = nil;
		[weakSelf rebuild];
	}];
}

- (void)imagePickerControllerDidCancel:(UIImagePickerController *)picker {
	self.pickingProfilePhoto = NO;
	[picker dismissViewControllerAnimated:YES completion:nil];
}

#pragma mark - sheets and alerts

- (void)actionSheet:(UIActionSheet *)sheet clickedButtonAtIndex:(NSInteger)index {
	if (index == sheet.cancelButtonIndex)
		return;

	if (sheet.tag == 87){
		TGTheme *theme = [TGTheme shared];
		if (index == 0){
			theme.autoNight = TGAutoNightOff;
		} else {
			static const NSInteger from[3] = {22, 21, 23};
			static const NSInteger to[3]   = { 7,  8,  6};
			theme.autoNightFromHour = from[index - 1];
			theme.autoNightToHour   = to[index - 1];
			theme.autoNight = TGAutoNightScheduled;
		}
		[self rebuild];
		return;
	}

	if (sheet.tag == 88){
		[TGTheme shared].messageFontSize = 13.0f + index * 2.0f;
		[self rebuild];
		return;
	}

	if (sheet.tag == 89){
		if (index == sheet.destructiveButtonIndex)
			[[TGTheme shared] setWallpaperImage:nil];
		else
			[self presentWallpaperPicker];
		[self rebuild];
		return;
	}

	if (sheet.tag == 90){
		static const NSInteger months[4] = {1, 3, 6, 12};
		[[TGClient shared] setAccountTtlDays:months[index] * 30];
		self.accountTtl = months[index] * 30;
		[self rebuild];
		return;
	}

	if (sheet.tag >= 91){
		NSInteger row = sheet.tag - 91;
		NSString *setting = [TGSettingsViewController privacySettings][row];
		NSString *value = @[@"everybody", @"contacts", @"nobody"][index];
		[[TGClient shared] setPrivacyRule:setting to:value];
		self.privacy[setting] = value;
		[self rebuild];
	}
}

- (void)alertView:(UIAlertView *)alert clickedButtonAtIndex:(NSInteger)index {
	if (index == alert.cancelButtonIndex)
		return;

	switch (alert.tag){
		case 61:
			[[TGClient shared] resetAllNotificationSettings];
			[self loadForPage];
			break;
		case 62:
			[[TGClient shared] clearImportedContacts];
			break;
		case 63:
			[[TGClient shared] resetNetworkStats];
			self.networkSent = 0;
			self.networkReceived = 0;
			[self rebuild];
			break;
		case 64:
			[[TGClient shared] clearLocalDatabase];
			break;
		case 65: {
			NSString *domain = [NSBundle mainBundle].bundleIdentifier;
			[NSUserDefaults.standardUserDefaults removePersistentDomainForName:domain];
			[NSUserDefaults.standardUserDefaults synchronize];
			[self repaint];
			[self toast:@"Preferences reset."];
			break;
		}
		default:
			if ([alert.title isEqualToString:@"Log out"])
				[[TGClient shared] logOut];
			break;
	}
}

@end
