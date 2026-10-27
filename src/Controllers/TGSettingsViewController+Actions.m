#import "TGSettingsViewControllerInternal.h"
#import "TGAlertSheet.h"
#import "TGStyle.h"

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

- (void)showPremiumState {
	__weak typeof(self) weakSelf = self;
	[[TGClient shared] premiumStateWithCompletion:^(NSString *summary){
		[TGAlertSheet showMessage:(summary.length ? summary
						: @"This account does not have Premium. It is bought in "
						  @"an official client; what it unlocks works here.")
							title:@"Telegram Premium" inView:weakSelf.view];
	}];
}

/// Their Two-Step Verification page, as a sheet: what the state is, and the
/// three things that can be done to it. The password is never held - each
/// request carries the one just typed and nothing keeps it afterwards.
- (void)showTwoStepState {
	__weak typeof(self) weakSelf = self;
	[[TGClient shared] hasPasswordWithCompletion:^(BOOL has, NSString *email){
		TGSettingsViewController *me = weakSelf;
		if (!me)
			return;

		NSString *message = has
				? (email.length
						? @"A password is set, with a recovery address behind it."
						: @"A password is set. There is no recovery address, so "
						  @"forgetting it means waiting a week to reset.")
				: @"Off. With it on, signing in on a new device asks for this "
				  @"password as well as the code.";
		NSArray *choices = has
				? @[@"Change Password", @"Recovery Address", @"Turn Off"]
				: @[@"Set a Password"];

		[TGAlertSheet showChoices:choices
							title:@"Two-Step Verification"
						  message:message
				 destructiveIndex:(has ? 2 : -1)
						   inView:me.view
						 onChoice:^(NSInteger index){
			if (!has){
				[me askNewPasswordReplacing:nil];
				return;
			}
			if (index == 0)
				[me askCurrentPasswordThen:^(NSString *current){
					[me askNewPasswordReplacing:current];
				}];
			else if (index == 1)
				[me askRecoveryAddress];
			else
				[me askTurnPasswordOff];
		}];
	}];
}

/// The gate every change goes through. Asked once, handed on, forgotten.
- (void)askCurrentPasswordThen:(void (^)(NSString *current))next {
	[TGAlertSheet showSecureInput:@"Current Password"
						  message:nil
					  placeholder:@"Password"
						   action:@"Continue"
						   inView:self.view
						 onSubmit:^(NSString *current){
		if (next) next(current);
	}];
}

/// A new password, then its hint. Telegram shows the hint to whoever is
/// signing in, so it is asked for separately rather than guessed at.
- (void)askNewPasswordReplacing:(NSString *)current {
	__weak typeof(self) weakSelf = self;
	[TGAlertSheet showSecureInput:@"New Password"
						  message:@"Eight characters or more is the usual advice."
					  placeholder:@"Password"
						   action:@"Next"
						   inView:self.view
						 onSubmit:^(NSString *new){
		TGSettingsViewController *me = weakSelf;
		[TGAlertSheet showInput:@"Hint"
						message:@"Shown when this password is asked for. It can "
								@"be left empty."
					placeholder:@"Hint"
						   text:nil
						 action:@"Set Password"
						 inView:me.view
					   onSubmit:^(NSString *hint){
			[me commitPassword:new replacing:current hint:hint];
		}];
	}];
}

/// Set Password with an empty hint has to be reachable too, so the hint sheet
/// being cancelled is not the end of the flow - this is the shared landing.
- (void)commitPassword:(NSString *)new replacing:(NSString *)current
				  hint:(NSString *)hint {
	__weak typeof(self) weakSelf = self;
	[[TGClient shared] setPassword:current
							   new:new
							  hint:hint
				   setEmailAddress:NO
							 email:nil
						completion:^(BOOL ok){
		TGSettingsViewController *me = weakSelf;
		if (!ok){
			[TGAlertSheet showMessage:@"Telegram refused that. A wrong current "
									  @"password is the usual reason."
								title:@"Two-Step Verification" inView:me.view];
			return;
		}
		me.hasPassword = YES;
		me.passwordKnown = YES;
		[me rebuild];
		[TGAlertSheet showMessage:@"Set. Signing in on a new device now asks "
								  @"for it. Add a recovery address so that "
								  @"forgetting it is not final."
							title:@"Two-Step Verification" inView:me.view];
	}];
}

/// Off is an empty new password, not a request of its own - and it still
/// needs the current one.
- (void)askTurnPasswordOff {
	__weak typeof(self) weakSelf = self;
	[TGAlertSheet showConfirm:@"Signing in will only need the code again."
						title:@"Turn Off"
					   action:@"Turn Off"
				  destructive:YES
					   inView:self.view
					onConfirm:^{
		TGSettingsViewController *me = weakSelf;
		[me askCurrentPasswordThen:^(NSString *current){
			[[TGClient shared] setPassword:current
									   new:@""
									  hint:@""
						   setEmailAddress:NO
									 email:nil
								completion:^(BOOL ok){
				if (!ok){
					[TGAlertSheet showMessage:@"Wrong password."
										title:@"Turn Off" inView:me.view];
					return;
				}
				me.hasPassword = NO;
				me.passwordKnown = YES;
				[me rebuild];
				[TGAlertSheet showMessage:@"Two-step verification is off."
									title:@"Turn Off" inView:me.view];
			}];
		}];
	}];
}

/// Reading the address back needs the password, which is the whole point of
/// it - so the same sheet shows what is there and offers to change it.
- (void)askRecoveryAddress {
	__weak typeof(self) weakSelf = self;
	[self askCurrentPasswordThen:^(NSString *current){
		TGSettingsViewController *me = weakSelf;
		[[TGClient shared] recoveryEmailAddress:current completion:^(NSString *email){
			[TGAlertSheet showChoices:@[@"Change Address"]
								title:@"Recovery Address"
							  message:(email.length
									? [NSString stringWithFormat:@"Letters go to %@.",
											email]
									: @"There is none, or the password was wrong.")
					 destructiveIndex:-1
							   inView:me.view
							 onChoice:^(NSInteger index){
				[TGAlertSheet showInput:@"Recovery Address"
								message:@"Telegram writes to it to confirm."
							placeholder:@"you@example.com"
								   text:email
								 action:@"Save"
								 inView:me.view
							   onSubmit:^(NSString *address){
					[[TGClient shared] setRecoveryEmailAddress:current
															to:address
													completion:^(BOOL ok){
						if (!ok){
							[TGAlertSheet showMessage:@"Telegram refused that address."
												title:@"Recovery Address"
											   inView:me.view];
							return;
						}
						// The address is not in force until the code sent to
						// it is entered, so the flow has to ask for it rather
						// than stopping at "we have written".
						[me askRecoveryEmailCodeFor:address];
					}];
				}];
			}];
		}];
	}];
}

/// The code Telegram emails to a new recovery address. Cancelling leaves the
/// old address standing, which is said rather than left to be discovered.
- (void)askRecoveryEmailCodeFor:(NSString *)address {
	__weak typeof(self) weakSelf = self;
	[TGAlertSheet showInput:@"Confirm Address"
					message:[NSString stringWithFormat:
							@"Telegram sent a code to %@. Until it is entered, "
							@"the address is not in use.", address]
				placeholder:@"Code"
					   text:nil
					 action:@"Confirm"
					 inView:self.view
				   onSubmit:^(NSString *code){
		TGSettingsViewController *me = weakSelf;
		[[TGClient shared] checkRecoveryEmailCode:code completion:^(BOOL ok){
			if (ok){
				[TGAlertSheet showMessage:[NSString stringWithFormat:
								@"%@ is now the recovery address.", address]
									title:@"Recovery Address" inView:me.view];
				return;
			}
			[TGAlertSheet showChoices:@[@"Send It Again"]
								title:@"Recovery Address"
							  message:@"That code was refused."
					 destructiveIndex:-1
							   inView:me.view
							 onChoice:^(NSInteger index){
				[[TGClient shared] resendRecoveryEmailCode];
				[me askRecoveryEmailCodeFor:address];
			}];
		}];
	}];
}

/// The end of the road. Two confirmations, then the reason their own form
/// asks for, then the password when two-step verification is on.
- (void)askDeleteAccountNow {
	__weak typeof(self) weakSelf = self;
	[TGAlertSheet showConfirm:@"Every message, chat, contact and the account "
							  @"itself go, on every device, and none of it "
							  @"comes back."
						title:@"Delete Account"
					   action:@"Delete Account"
				  destructive:YES
					   inView:self.view
					onConfirm:^{
		TGSettingsViewController *me = weakSelf;
		[TGAlertSheet showInput:@"Why"
						message:@"Telegram asks. It can be left empty."
					placeholder:@"Reason"
						   text:nil
						 action:@"Continue"
						 inView:me.view
					   onSubmit:^(NSString *reason){
			void (^finish)(NSString *) = ^(NSString *password){
				[[TGClient shared] deleteAccountWithReason:reason
												  password:password
												completion:^(BOOL ok){
					if (!ok)
						[TGAlertSheet showMessage:@"Telegram refused. A wrong "
												  @"password is the usual reason."
											title:@"Delete Account" inView:me.view];
					// On success TDLib logs out on its own and the login
					// screen takes over; there is nothing left to say.
				}];
			};
			if (me.hasPassword)
				[me askCurrentPasswordThen:finish];
			else
				finish(nil);
		}];
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
		[TGTheme shared].messageFontSize = TGFontMessageBaseSize + index * TGFontMessageStep;
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
								fittingSize:CGSizeMake(TGMetricUploadPhotoSide, TGMetricUploadPhotoSide)
									   fill:NO scale:TGMetricScaleFull];
	NSString *path = [NSTemporaryDirectory()
			stringByAppendingPathComponent:@"profile-photo.jpg"];
	if (![UIImageJPEGRepresentation(scaled, TGCompressionQualityStandard) writeToFile:path atomically:YES]){
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
