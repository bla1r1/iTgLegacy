#import "TGSettingsViewControllerInternal.h"
#import "TGAlertSheet.h"

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

/// Explains device memory constraints when attempting to add another account.
- (void)explainAddAccount {
	if ([TGCapabilities canHoldMultipleAccounts]){
		[self toast:@"Multiple accounts are not wired up yet on this build."];
		return;
	}
	[TGAlertSheet showMessage:[NSString stringWithFormat:
					@"A second account needs a second TDLib client and a second "
					@"copy of the cache. This is a %@ device with %lu MB, and "
					@"that needs the Full tier - 2 GB or more.",
					[TGDevice tierName] ?: @"Legacy",
					(unsigned long)[TGCapabilities memoryMB]]
						title:@"Add Account" inView:self.view];
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
		[TGAlertSheet showMessage:@"This account is still loading."
							title:@"Saved Messages" inView:self.view];
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
	[TGAlertSheet showMessage:message title:@"Folders" inView:self.view];
}

- (void)showPremiumState {
	__weak typeof(self) weakSelf = self;
	[[TGClient shared] premiumStateWithCompletion:^(NSString *summary){
		[TGAlertSheet showMessage:(summary.length ? summary
						: @"This account does not have Premium. It is bought in "
						  @"an official client; what it unlocks works here.")
							title:@"Telegram Premium" inView:weakSelf.view];
	}];
}

/// Setting a password is a multi-step flow with a recovery address; this screen
/// reports the state and says where to change it rather than pretending to.
- (void)showTwoStepState {
	__weak typeof(self) weakSelf = self;
	[[TGClient shared] hasPasswordWithCompletion:^(BOOL has, NSString *email){
		NSString *message = has
				? [NSString stringWithFormat:@"Two-step verification is on.%@",
						email.length ? [NSString stringWithFormat:
								@"\nRecovery address: %@", email] : @""]
				: @"Two-step verification is off. It is set up in an official "
				  @"client; once it is on, this app asks for the password when "
				  @"signing in.";
		[TGAlertSheet showMessage:message title:@"Two-Step Verification"
						   inView:weakSelf.view];
	}];
}

- (void)openSupport {
	// Their support is a chat, not a web page.
	__weak typeof(self) weakSelf = self;
	[[TGClient shared] chatWithUsername:@"BotSupport"
							 completion:^(int64_t chatId, NSString *title){
		if (!chatId){
			[TGAlertSheet showMessage:@"Support is not reachable from this "
									  @"account right now."
								title:@"Support" inView:weakSelf.view];
			return;
		}
		[weakSelf openChat:chatId title:(title ?: @"Telegram Support")];
	}];
}

- (void)askPrivacyRuleAtIndex:(NSUInteger)index {
	NSString *setting = [TGSettingsViewController privacySettings][index];
	__weak typeof(self) weakSelf = self;
	[TGAlertSheet showChoices:@[@"Everybody", @"My Contacts", @"Nobody"]
						title:[TGSettingsViewController privacyTitles][index]
			 destructiveIndex:-1
					   inView:self.view
					 onChoice:^(NSInteger choice){
		NSString *value = @[@"everybody", @"contacts", @"nobody"][choice];
		[[TGClient shared] setPrivacyRule:setting to:value];
		weakSelf.privacy[setting] = value;
		[weakSelf rebuild];
	}];
}

- (void)chooseAutoNight {
	__weak typeof(self) weakSelf = self;
	[TGAlertSheet showChoices:@[@"Disabled", @"22:00 - 07:00",
								@"21:00 - 08:00", @"23:00 - 06:00"]
						title:@"Auto-Night Mode"
			 destructiveIndex:-1
					   inView:self.view
					 onChoice:^(NSInteger index){
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
		[weakSelf rebuild];
	}];
}

/// Four sizes is enough on a 3.5-inch screen; a slider would be finer than
/// the difference it makes.
- (void)chooseTextSize {
	__weak typeof(self) weakSelf = self;
	[TGAlertSheet showChoices:@[@"13 pt", @"15 pt", @"17 pt", @"19 pt"]
						title:@"Message text size"
			 destructiveIndex:-1
					   inView:self.view
					 onChoice:^(NSInteger index){
		[TGTheme shared].messageFontSize = 13.0f + index * 2.0f;
		[weakSelf rebuild];
	}];
}

#pragma mark - wallpaper

- (void)chooseWallpaper {
	if ([TGTheme shared].wallpaper){
		__weak typeof(self) weakSelf = self;
		[TGAlertSheet showChoices:@[@"Remove", @"Choose another"]
							title:@"Chat wallpaper"
				 destructiveIndex:0
						   inView:self.view
						 onChoice:^(NSInteger index){
			if (index == 0)
				[[TGTheme shared] setWallpaperImage:nil];
			else
				[weakSelf presentWallpaperPicker];
			[weakSelf rebuild];
		}];
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

@end
