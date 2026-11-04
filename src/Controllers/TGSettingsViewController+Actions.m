#import "TGProfileViewController.h"
#import "TGSettingsViewControllerInternal.h"
#import "TGAlertSheet.h"
#import "TGStyle.h"

@implementation TGSettingsViewController (Actions)

#pragma mark - actions

/// Your own profile, as everyone else sees it - their "My Profile" row.
- (void)openMyProfile {
	[self openMyProfileOnTab:nil];
}

- (void)openMyProfileOnTab:(NSString *)tab {
	int64_t userId = [[TGClient shared].me[@"id"] longLongValue];
	if (!userId)
		return;
	TGProfileViewController *profile = [[TGProfileViewController alloc]
			initWithChatId:userId userId:userId
					 title:[TGClient shared].me[@"first_name"] ?: @"Profile"];
	profile.storedMediaKind = tab;
	profile.hidesBottomBarWhenPushed = YES;
	[self.navigationController pushViewController:profile animated:YES];
}

/// The account switcher: each account's title with the active one marked,
/// then Add Account while fewer than three are in use. Picking an account
/// switches to it; Add Account makes a new slot and switches straight over,
/// so an empty slot lands on the login screen.
- (void)showAccountChoices {
	__weak typeof(self) weakSelf = self;
	NSArray *slots = [TGClient accountSlots];
	NSInteger active = [TGClient activeAccountSlot];

	NSMutableArray *choices = [NSMutableArray arrayWithCapacity:slots.count + 1];
	NSMutableArray *choiceSlots = [NSMutableArray arrayWithCapacity:slots.count];
	for (NSDictionary *entry in slots){
		NSInteger slot = [entry[@"slot"] integerValue];
		NSString *title = [entry[@"title"] length] ? entry[@"title"]
				: ([entry[@"phone"] length] ? entry[@"phone"] : @"Account");
		[choiceSlots addObject:@(slot)];
		[choices addObject:slot == active
				? [NSString stringWithFormat:@"%@ ✓", title] : title];
	}
	if (slots.count < 3)
		[choices addObject:@"Add Account"];

	[TGAlertSheet showChoices:choices
						title:@"Accounts"
					  message:@"Accounts other than the active one receive no notifications."
			 destructiveIndex:-1
					   inView:self.view
					 onChoice:^(NSInteger index){
		TGSettingsViewController *me = weakSelf;
		if (!me)
			return;
		if (index < (NSInteger)choiceSlots.count){
			NSInteger slot = [choiceSlots[index] integerValue];
			if (slot != active)
				[[TGClient shared] switchToAccountSlot:slot];
			return;
		}
		// The one row after the accounts is Add Account.
		NSInteger newSlot = [TGClient addAccount];
		if (newSlot >= 0)
			[[TGClient shared] switchToAccountSlot:newSlot];
	}];
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
				? @[@"Change Password", @"Recovery Address", @"Turn Off",
					@"Forgot Password?"]
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
			else if (index == 3)
				[me showLostPasswordFlow];
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
/// old address standing - and the cancel is a request of its own, so the
/// server's answer replaces the guess that nothing happened.
- (void)askRecoveryEmailCodeFor:(NSString *)address {
	__weak typeof(self) weakSelf = self;
	[TGAlertSheet showChoices:@[@"Enter the Code", @"Cancel the Change"]
						title:@"Confirm Address"
					  message:[NSString stringWithFormat:
							@"Telegram sent a code to %@. Until it is entered, "
							@"the address is not in use.", address]
			 destructiveIndex:1
					   inView:self.view
					 onChoice:^(NSInteger index){
		TGSettingsViewController *me = weakSelf;
		if (index == 1){
			[[TGClient shared] cancelRecoveryEmailAddressVerificationWithCompletion:
					^(NSDictionary *state, NSString *error){
				NSString *said = error;
				if (!said){
					said = [state[@"hasRecoveryEmail"] boolValue]
							? [NSString stringWithFormat:@"The change was cancelled. "
									@"%@ is still the recovery address.",
									state[@"recoveryPattern"] ?: @"The old address"]
							: @"The change was cancelled. There is no recovery "
							  @"address, as before.";
				}
				[TGAlertSheet showMessage:said title:@"Recovery Address"
								   inView:me.view];
			}];
			return;
		}
		[TGAlertSheet showInput:@"Confirm Address"
						message:[NSString stringWithFormat:
								@"Telegram sent a code to %@. Until it is entered, "
								@"the address is not in use.", address]
					placeholder:@"Code"
						   text:nil
						 action:@"Confirm"
						 inView:me.view
					   onSubmit:^(NSString *code){
			[[TGClient shared] checkRecoveryEmailCode:code completion:^(BOOL ok){
				if (ok){
					[TGAlertSheet showMessage:[NSString stringWithFormat:
									@"%@ is now the recovery address.", address]
										title:@"Recovery Address" inView:me.view];
					return;
				}
				[TGAlertSheet showChoices:@[@"Send It Again", @"Enter It Again"]
									title:@"Recovery Address"
								  message:@"That code was refused."
						 destructiveIndex:-1
								   inView:me.view
								 onChoice:^(NSInteger choice){
					if (choice == 1){
						[me askRecoveryEmailCodeFor:address];
						return;
					}
					[[TGClient shared] resendRecoveryEmailCode];
					[me askRecoveryEmailCodeFor:address];
				}];
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
	// Their support is a chat, not a web page. Telegram names the account;
	// opening a guessed @BotSupport was a second request that could disagree
	// with the one the server actually named.
	__weak typeof(self) weakSelf = self;
	[[TGClient shared] supportUserWithCompletion:^(NSDictionary *user, NSString *error){
		if (!user){
			[TGAlertSheet showMessage:(error ?: @"Support is not reachable "
									  @"from this account right now.")
								title:@"Support" inView:weakSelf.view];
			return;
		}
		int64_t userId = [user[@"id"] longLongValue];
		[[TGClient shared] privateChatWithUser:userId completion:^(int64_t chatId){
			if (!chatId){
				[TGAlertSheet showMessage:@"Telegram did not open a chat with support."
									title:@"Support" inView:weakSelf.view];
				return;
			}
			[weakSelf openChat:chatId title:(user[@"name"] ?: @"Telegram Support")];
		}];
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

#pragma mark - password recovery inside the account

/// A time Telegram named, written as a day rather than a Unix stamp. The
/// reset flow answers "try again after this", which is unusable as seconds.
static NSString *TGSettingsDateString(double stamp) {
	if (stamp <= 0)
		return @"a later date";
	return [NSDateFormatter localizedStringFromDate:
			[NSDate dateWithTimeIntervalSince1970:stamp]
			dateStyle:NSDateFormatterMediumStyle
			timeStyle:NSDateFormatterShortStyle];
}

/// The two roads open to an account that has a password it cannot type: the
/// recovery address, or the slow reset Telegram allows without one. Both
/// requests answer with their own refusal, which is what the sheets show.
- (void)showLostPasswordFlow {
	__weak typeof(self) weakSelf = self;
	[TGAlertSheet showChoices:@[@"Email a Recovery Code", @"Reset Without Email"]
						title:@"Lost Password"
					  message:@"The recovery address, when there is one, gets a "
							  @"code that can replace the password. Without it "
							  @"Telegram makes the account wait."
			 destructiveIndex:-1
					   inView:self.view
					 onChoice:^(NSInteger index){
		TGSettingsViewController *me = weakSelf;
		if (index == 1){
			[me askResetPassword];
			return;
		}
		[[TGClient shared] requestAccountPasswordRecoveryWithCompletion:
				^(NSString *pattern, NSString *error){
			if (error){
				[TGAlertSheet showChoices:@[@"Reset Without Email"]
									title:@"Lost Password"
								  message:[NSString stringWithFormat:
										  @"%@\n\nThe recovery address is the only "
										  @"fast way, so the slow reset is the rest.",
										  error]
						 destructiveIndex:-1
								   inView:me.view
								 onChoice:^(NSInteger ignored){
					[me askResetPassword];
				}];
				return;
			}
			[me askPasswordRecoveryCodeFor:pattern];
		}];
	}];
}

- (void)askPasswordRecoveryCodeFor:(NSString *)pattern {
	__weak typeof(self) weakSelf = self;
	[TGAlertSheet showInput:@"Recovery Code"
					message:[NSString stringWithFormat:
							@"Telegram mailed a code to %@. Entering it lets a new "
							@"password be set.", pattern.length ? pattern : @"the recovery address"]
				placeholder:@"Code"
					   text:nil
					 action:@"Check"
					 inView:self.view
				   onSubmit:^(NSString *code){
		TGSettingsViewController *me = weakSelf;
		[[TGClient shared] checkAccountPasswordRecoveryCode:code completion:^(NSString *error){
			if (error){
				[TGAlertSheet showChoices:@[@"Enter It Again"]
									title:@"Recovery Code"
								  message:error
						 destructiveIndex:-1
								   inView:me.view
								 onChoice:^(NSInteger ignored){
					[me askPasswordRecoveryCodeFor:pattern];
				}];
				return;
			}
			[TGAlertSheet showSecureInput:@"New Password"
								  message:@"This replaces the password Telegram "
										  @"could not be given."
							  placeholder:@"Password"
								   action:@"Next"
								   inView:me.view
								 onSubmit:^(NSString *password){
				[TGAlertSheet showInput:@"Hint"
								message:@"Shown when this password is asked for. "
										@"It can be left empty."
							placeholder:@"Hint"
								   text:nil
								 action:@"Set Password"
								 inView:me.view
							   onSubmit:^(NSString *hint){
					[[TGClient shared] recoverAccountPasswordWithCode:code
														   newPassword:password
																  hint:hint
															completion:^(NSDictionary *state,
																		 NSString *recoverError){
						if (recoverError){
							[TGAlertSheet showMessage:recoverError
												title:@"Lost Password"
											   inView:me.view];
							return;
						}
						me.hasPassword = [state[@"hasPassword"] boolValue];
						me.passwordKnown = YES;
						[me rebuild];
						[TGAlertSheet showMessage:[state[@"hasPassword"] boolValue]
								? @"The password was replaced."
								: @"The password was removed."
											title:@"Lost Password" inView:me.view];
					}];
				}];
			}];
		}];
	}];
}

/// The reset Telegram allows without the address: repeated calls move a date
/// forward until the password can be dropped. The reply names which stage it
/// is at, and a pending one can still be called off.
- (void)askResetPassword {
	__weak typeof(self) weakSelf = self;
	[TGAlertSheet showConfirm:@"Without the password or its recovery address, "
							  @"Telegram makes the account wait before the "
							  @"password can be removed."
						title:@"Reset Without Email"
					   action:@"Ask Telegram"
				  destructive:YES
					   inView:self.view
					onConfirm:^{
		TGSettingsViewController *me = weakSelf;
		[[TGClient shared] resetAccountPasswordWithCompletion:
				^(NSString *result, double date, NSString *error){
			if ([result isEqualToString:@"ok"]){
				me.hasPassword = NO;
				me.passwordKnown = YES;
				[me rebuild];
				[TGAlertSheet showMessage:@"Two-step verification is off."
									title:@"Reset Without Email" inView:me.view];
				return;
			}
			if ([result isEqualToString:@"pending"]){
				[TGAlertSheet showChoices:@[@"Cancel the Reset"]
									title:@"Reset Pending"
								  message:[NSString stringWithFormat:
										  @"Telegram will allow the password to be "
										  @"removed after %@.",
										  TGSettingsDateString(date)]
						 destructiveIndex:1
								   inView:me.view
								 onChoice:^(NSInteger ignored){
					[[TGClient shared] cancelAccountPasswordResetWithCompletion:
							^(NSString *cancelError){
						[TGAlertSheet showMessage:(cancelError
								?: @"The reset was cancelled. The password stays.")
											title:@"Reset Without Email"
										   inView:me.view];
					}];
				}];
				return;
			}
			if ([result isEqualToString:@"declined"]){
				[TGAlertSheet showMessage:[NSString stringWithFormat:
						@"Telegram declined. This account can ask again after %@.",
						TGSettingsDateString(date)]
									title:@"Reset Without Email" inView:me.view];
				return;
			}
			[TGAlertSheet showMessage:(error ?: @"Telegram did not answer.")
								title:@"Reset Without Email" inView:me.view];
		}];
	}];
}

#pragma mark - login email address

/// The login email is the address Telegram mails when a new device signs in.
/// Whether the account may change it is the server's call, and that answer
/// is said before the field is offered rather than after it is refused.
- (void)showLoginEmailFlow {
	__weak typeof(self) weakSelf = self;
	[[TGClient shared] loginEmailAddressRequiredWithCompletion:
			^(BOOL required, NSString *error){
		TGSettingsViewController *me = weakSelf;
		NSString *said = required
				? @"Telegram requires this account to have a login email."
				: [NSString stringWithFormat:@"Telegram's answer: %@",
						error ?: @"not required"];
		[TGAlertSheet showChoices:@[@"Set a Login Email"]
							title:@"Login Email Address"
						  message:said
				 destructiveIndex:-1
						   inView:me.view
						 onChoice:^(NSInteger ignored){
			[TGAlertSheet showInput:@"Login Email Address"
							message:@"Telegram mails a code here; the address is "
									@"not in force until that code is entered."
						placeholder:@"you@example.com"
							   text:nil
							 action:@"Send Code"
							 inView:me.view
						   onSubmit:^(NSString *email){
				[[TGClient shared] setLoginEmailAddress:email
											completion:^(NSString *pattern,
														  NSString *setError){
					if (setError){
						[TGAlertSheet showMessage:setError
											title:@"Login Email Address"
										   inView:me.view];
						return;
					}
					[me askLoginEmailCodeFor:(pattern.length ? pattern : email)];
				}];
			}];
		}];
	}];
}

/// The code sheet loops: a refusal offers the code again, and the resend
/// request is the server's answer for the masked address it mails to.
- (void)askLoginEmailCodeFor:(NSString *)pattern {
	__weak typeof(self) weakSelf = self;
	[TGAlertSheet showChoices:@[@"Enter the Code", @"Send It Again"]
						title:@"Login Email Address"
					  message:[NSString stringWithFormat:
							  @"Telegram sent a code to %@.", pattern]
			 destructiveIndex:-1
					   inView:self.view
					 onChoice:^(NSInteger index){
		TGSettingsViewController *me = weakSelf;
		if (index == 1){
			[[TGClient shared] resendLoginEmailAddressCodeWithCompletion:
					^(NSString *resent, NSString *error){
				[TGAlertSheet showMessage:(error
						?: [NSString stringWithFormat:@"Sent again to %@.",
								resent.length ? resent : pattern])
									title:@"Login Email Address" inView:me.view];
				[me askLoginEmailCodeFor:(resent.length ? resent : pattern)];
			}];
			return;
		}
		[TGAlertSheet showInput:@"Login Email Code"
						message:pattern
					placeholder:@"Code"
						   text:nil
						 action:@"Confirm"
						 inView:me.view
					   onSubmit:^(NSString *code){
			[[TGClient shared] checkLoginEmailAddressCode:code
											   completion:^(NSString *error){
				if (error){
					[TGAlertSheet showMessage:error
										title:@"Login Email Address"
									   inView:me.view];
					[me askLoginEmailCodeFor:pattern];
					return;
				}
				[TGAlertSheet showMessage:[NSString stringWithFormat:
						@"%@ is now this account's login email.", pattern]
									title:@"Login Email Address" inView:me.view];
			}];
		}];
	}];
}

#pragma mark - phone number

/// The change-number flow. Telegram sends the code to the new number and
/// only moves the account when it is checked; the old number keeps working
/// until then, which is what the first sheet has to say.
- (void)showChangePhoneFlow {
	__weak typeof(self) weakSelf = self;
	[TGAlertSheet showInput:@"Change Phone Number"
					message:@"The new number, in international form. Telegram "
							@"sends it a code; nothing moves until that code is in."
				placeholder:@"+380..."
					   text:nil
					 action:@"Next"
					 inView:self.view
				   onSubmit:^(NSString *number){
		TGSettingsViewController *me = weakSelf;
		// The synchronous answer is what a sheet needs before it can name the
		// country and the way Telegram would write the number.
		NSDictionary *info = [[TGClient shared] phoneNumberInfoForPrefixSync:number];
		NSString *said = info
				? [NSString stringWithFormat:@"%@ %@\n%@",
						info[@"flag"] ?: @"", info[@"name"] ?: @"",
						info[@"formatted"] ?: number]
				: number;
		[TGAlertSheet showConfirm:[NSString stringWithFormat:
						@"Send a confirmation code to\n%@?", said]
							title:@"Change Phone Number"
						   action:@"Send Code"
					  destructive:NO
						   inView:me.view
						onConfirm:^{
			[[TGClient shared] sendPhoneNumberChangeCode:number
											  completion:^(NSDictionary *codeInfo,
														   NSString *error){
				if (error){
					[TGAlertSheet showMessage:error title:@"Change Phone Number"
									   inView:me.view];
					return;
				}
				[me showPhoneChangeCodeStep:codeInfo];
			}];
		}];
	}];
}

- (void)showPhoneChangeCodeStep:(NSDictionary *)info {
	__weak typeof(self) weakSelf = self;
	NSString *type = info[@"type"] ?: @"";
	BOOL firebase = [type hasPrefix:@"authenticationCodeTypeFirebase"];
	NSMutableArray *choices = [NSMutableArray arrayWithObjects:
			@"Enter the Code", @"Send It Again", @"It Never Arrived", nil];
	if (firebase)
		[choices addObject:@"Send Push Secret"];

	[TGAlertSheet showChoices:choices
						title:@"Change Phone Number"
					  message:[NSString stringWithFormat:
							  @"A code was sent to %@.",
							  info[@"phone"] ?: @"the new number"]
			 destructiveIndex:-1
					   inView:self.view
					 onChoice:^(NSInteger index){
		TGSettingsViewController *me = weakSelf;
		if (index == 1){
			[[TGClient shared] resendPhoneNumberChangeCodeWithCompletion:
					^(NSDictionary *resent, NSString *error){
				if (error){
					[TGAlertSheet showMessage:error
										title:@"Change Phone Number" inView:me.view];
					return;
				}
				[me showPhoneChangeCodeStep:resent];
			}];
			return;
		}
		if (index == 2){
			[[TGClient shared] reportPhoneNumberCodeMissingWithCompletion:
					^(NSString *error){
				[TGAlertSheet showMessage:(error
						?: @"Telegram was told the code did not arrive.")
									title:@"Change Phone Number" inView:me.view];
				[me showPhoneChangeCodeStep:info];
			}];
			return;
		}
		if (index == 3){
			[TGAlertSheet showInput:@"Push Verification"
							message:@"The secret from the verification push."
						placeholder:@"Secret"
							   text:nil
							 action:@"Send"
							 inView:me.view
						   onSubmit:^(NSString *token){
				[[TGClient shared] sendPhoneNumberFirebaseSms:token
												   completion:^(NSString *error){
					[TGAlertSheet showMessage:(error
							?: @"Telegram accepted the verification.")
												title:@"Change Phone Number"
											   inView:me.view];
					[me showPhoneChangeCodeStep:info];
				}];
			}];
			return;
		}
		[TGAlertSheet showInput:@"Confirmation Code"
						message:[NSString stringWithFormat:@"Sent to %@.",
								info[@"phone"] ?: @"the new number"]
					placeholder:@"Code"
						   text:nil
						 action:@"Confirm"
						 inView:me.view
					   onSubmit:^(NSString *code){
			[[TGClient shared] checkPhoneNumberChangeCode:code
											   completion:^(NSString *error){
				if (error){
					[TGAlertSheet showMessage:error
										title:@"Change Phone Number" inView:me.view];
					[me showPhoneChangeCodeStep:info];
					return;
				}
				[TGAlertSheet showMessage:@"The number was changed. The old one "
										  @"stops receiving codes."
									title:@"Change Phone Number" inView:me.view];
			}];
		}];
	}];
}

#pragma mark - temporary password

/// The temporary password is what pays for things without typing the real
/// one each time. Both the read and the create answer the same state, so the
/// sheet can always say whether one exists and for how long.
- (void)showTemporaryPasswordFlow {
	__weak typeof(self) weakSelf = self;
	[[TGClient shared] temporaryPasswordStateWithCompletion:
			^(BOOL has, NSInteger validFor, NSString *error){
		TGSettingsViewController *me = weakSelf;
		NSString *said;
		if (error){
			said = error;
		} else if (has){
			said = [NSString stringWithFormat:
					@"A temporary password is active for another %ld minutes.",
					(long)(validFor / 60)];
		} else {
			said = @"There is no temporary password right now.";
		}
		[TGAlertSheet showChoices:@[@"Create a New One"]
							title:@"Temporary Password"
						  message:said
				 destructiveIndex:-1
						   inView:me.view
						 onChoice:^(NSInteger ignored){
			[me askCurrentPasswordThen:^(NSString *current){
				[TGAlertSheet showChoices:@[@"1 hour", @"1 day"]
									title:@"Valid For"
						 destructiveIndex:-1
								   inView:me.view
								 onChoice:^(NSInteger index){
					static const NSInteger seconds[2] = {3600, 86400};
					[[TGClient shared] createTemporaryPassword:current
													  validFor:seconds[index]
													completion:^(BOOL created,
																 NSInteger left,
																 NSString *createError){
						[TGAlertSheet showMessage:(createError
								?: [NSString stringWithFormat:
										@"The temporary password is good for %ld minutes.",
										(long)(left / 60)])
													title:@"Temporary Password"
												   inView:me.view];
					}];
				}];
			}];
		}];
	}];
}

#pragma mark - email address verification

/// Passport's address half: Telegram mails a code, and entering it marks the
/// address verified. The app has no Passport form, but a refusal from the
/// server is still the answer this flow shows.
- (void)showVerifyEmailFlow {
	__weak typeof(self) weakSelf = self;
	[TGAlertSheet showInput:@"Verify an Email Address"
					message:@"Telegram sends a code to the address; entering it "
							@"verifies it for Passport."
				placeholder:@"you@example.com"
					   text:nil
					 action:@"Send Code"
					 inView:self.view
				   onSubmit:^(NSString *email){
		TGSettingsViewController *me = weakSelf;
		[[TGClient shared] sendEmailAddressVerificationCodeTo:email
												  completion:^(NSString *pattern,
															   NSString *error){
			if (error){
				[TGAlertSheet showMessage:error
									title:@"Verify an Email Address"
								   inView:me.view];
				return;
			}
			[me askEmailVerificationCodeFor:(pattern.length ? pattern : email)];
		}];
	}];
}

- (void)askEmailVerificationCodeFor:(NSString *)pattern {
	__weak typeof(self) weakSelf = self;
	[TGAlertSheet showChoices:@[@"Enter the Code", @"Send It Again"]
						title:@"Verify an Email Address"
					  message:[NSString stringWithFormat:
							  @"A code was sent to %@.", pattern]
			 destructiveIndex:-1
					   inView:self.view
					 onChoice:^(NSInteger index){
		TGSettingsViewController *me = weakSelf;
		if (index == 1){
			[[TGClient shared] resendEmailAddressVerificationCodeWithCompletion:
					^(NSString *resent, NSString *error){
				[TGAlertSheet showMessage:(error
						?: [NSString stringWithFormat:@"Sent again to %@.",
								resent.length ? resent : pattern])
									title:@"Verify an Email Address"
								   inView:me.view];
				[me askEmailVerificationCodeFor:(resent.length ? resent : pattern)];
			}];
			return;
		}
		[TGAlertSheet showInput:@"Email Code"
						message:pattern
					placeholder:@"Code"
						   text:nil
						 action:@"Verify"
						 inView:me.view
					   onSubmit:^(NSString *code){
			[[TGClient shared] checkEmailAddressVerificationCode:code
													  completion:^(NSString *error){
				if (error){
					[TGAlertSheet showMessage:error
										title:@"Verify an Email Address"
									   inView:me.view];
					[me askEmailVerificationCodeFor:pattern];
					return;
				}
				[TGAlertSheet showMessage:[NSString stringWithFormat:
						@"%@ is verified.", pattern]
									title:@"Verify an Email Address"
								   inView:me.view];
			}];
		}];
	}];
}

#pragma mark - application verification

/// Telegram asks the app to prove itself through the platform's
/// verification service. The update names the request; this sheet hands the
/// service's token back and shows whether the server accepted it.
- (void)showApplicationVerification {
	__weak typeof(self) weakSelf = self;
	int64_t verificationId = [TGClient shared].pendingApplicationVerificationId;
	if (!verificationId){
		[TGAlertSheet showMessage:@"Telegram has not asked this app to verify "
								  @"itself. The row fills in when it does."
							title:@"Application Verification" inView:self.view];
		return;
	}
	NSString *nonce = [TGClient shared].pendingApplicationVerificationNonce;
	[TGAlertSheet showInput:@"Application Verification"
					message:[NSString stringWithFormat:
							@"Request %lld waits for the verification service's "
							@"token.\nNonce: %@",
							(long long)verificationId,
							nonce.length ? nonce : @"(none)"]
				placeholder:@"Token"
					   text:nil
					 action:@"Send"
					 inView:self.view
				   onSubmit:^(NSString *token){
		TGSettingsViewController *me = weakSelf;
		[[TGClient shared] setApplicationVerificationToken:token
											verificationId:verificationId
												completion:^(NSString *error){
			[TGAlertSheet showMessage:(error
					?: @"Telegram accepted the token; the request can go through.")
								title:@"Application Verification"
							   inView:me.view];
			[me rebuild];
		}];
	}];
}

@end
