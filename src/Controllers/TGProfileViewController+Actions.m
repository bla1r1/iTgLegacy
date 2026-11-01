#import "TGProfileViewControllerInternal.h"
#import "TGCapabilities.h"
#import "TGStatusText.h"
#import "TGStyle.h"
#import "TGAlertSheet.h"
#import "TGSnackbar.h"
#import "TGChatViewController.h"
#import "TGProfilePhotosViewController.h"
#import "TGGroupSettingsViewController.h"
#import "TGGroupMemberActions.h"
#import "TGGroupCallViewController.h"

/// The glyph on an action tile, over the word that names it.
static const CGFloat kTileGlyph = TGMetricMenuGlyph;

@implementation TGProfileViewController (Actions)

/// The avatar's tap: other accounts' profiles go straight to the photo
/// history; the signed-in one asks, because its photo is also something this
/// app can take back - and the t.me link is a copy away.
- (void)avatarTapped {
	BOOL mine = !self.userId
			|| self.userId == [[TGClient shared].me[@"id"] longLongValue];
	if (!mine){
		TGProfilePhotosViewController *photos =
				[[TGProfilePhotosViewController alloc] initWithUserId:self.userId];
		photos.hidesBottomBarWhenPushed = YES;
		[self.navigationController pushViewController:photos animated:YES];
		return;
	}

	__weak typeof(self) weakSelf = self;
	NSMutableArray *choices = [NSMutableArray arrayWithObjects:
			@"View All Photos", @"Copy Profile Link", nil];
	NSString *sheetTitle = self.name.length ? self.name : @"Profile";
	// The account wears no photo, so there is nothing to take back.
	if ([TGClient shared].me[@"profile_photo"])
		[choices addObject:@"Remove Photo"];
	[TGAlertSheet showChoices:choices
						title:sheetTitle
			 destructiveIndex:[choices indexOfObject:@"Remove Photo"]
					   inView:self.view
					 onChoice:^(NSInteger index){
		NSString *picked = choices[index];
		if ([picked isEqualToString:@"View All Photos"]){
			TGProfilePhotosViewController *photos =
					[[TGProfilePhotosViewController alloc] initWithUserId:self.userId];
			photos.hidesBottomBarWhenPushed = YES;
			[weakSelf.navigationController pushViewController:photos animated:YES];
			return;
		}
		if ([picked isEqualToString:@"Copy Profile Link"]){
			[[TGClient shared] myUserLink:^(NSString *link){
				if (link.length){
					[UIPasteboard generalPasteboard].string = link;
					[TGAlertSheet showMessage:@"Copied." title:nil
									   inView:weakSelf.view];
				}
			}];
			return;
		}
		if ([picked isEqualToString:@"Remove Photo"]){
			// The photo to drop is the one the account wears now - the first
			// of the history is what Telegram wears back.
			[[TGClient shared] userProfilePhotos:self.userId completion:^(NSArray *photos){
				NSDictionary *first = photos.firstObject;
				[[TGClient shared] deleteProfilePhoto:
						[first[@"photoId"] longLongValue] completion:^(BOOL ok){
					if (ok)
						[weakSelf buildHeader];
				}];
			}];
		}
	}];
}

/// Whose phrase the status line carries: the network state first, then the
/// resting answer (last seen or member count). B4: a profile opened offline
/// used to freeze at its captured status instead of saying why it cannot
/// answer - "Waiting for network".
- (void)statusLabelOwnerChanged:(NSNotification *)note {
	NSString *network = TGNetworkSubtitleForState(
			(NSInteger)[TGClient shared].connectionState, nil);
	NSString *line = network ?: (self.restingStatus ?: @"");
	if (line.length && ![self.statusLabel.text isEqualToString:line])
		self.statusLabel.text = line;
}

/// The tiles under the name: a glyph over a word, on a soft rounded plate.
/// Only the ones that mean something here - a group has no one to call.
- (void)buildActionsIn:(UIView *)header atY:(CGFloat)y {
	NSMutableArray *tiles = [NSMutableArray array];
	if (self.userId){
		[tiles addObject:@[@"call",  @"call"]];
		if ([TGCapabilities canEncodeVideoCall])
			[tiles addObject:@[@"video", @"video"]];
	}
	[tiles addObject:@[(self.muted ? @"unmute" : @"mute"),
					   (self.muted ? @"unmute" : @"mute")]];
	if (self.onSearchTapped)
		[tiles addObject:@[@"search", @"search"]];
	[tiles addObject:@[@"more", @"more"]];

	CGFloat width = header.bounds.size.width;
	CGFloat gap = 6, margin = 10;
	CGFloat tileW = (width - TGDoubled(margin) - gap * (tiles.count - 1)) / tiles.count;
	TGTheme *theme = [TGTheme shared];

	for (NSUInteger i = 0; i < tiles.count; i++){
		UIButton *tile = [UIButton buttonWithType:UIButtonTypeCustom];
		tile.frame = CGRectMake(margin + i * (tileW + gap), y, tileW, kActionTile);
		[tile setBackgroundImage:[TGTheme buttonImageForStyle:TGButtonStyleSecondary highlighted:NO height:kActionTile] forState:UIControlStateNormal];
		[tile setBackgroundImage:[TGTheme buttonImageForStyle:TGButtonStyleSecondary highlighted:YES height:kActionTile] forState:UIControlStateHighlighted];
		tile.backgroundColor = [UIColor clearColor];
		tile.layer.cornerRadius = TGMetricCornerControl;
		tile.clipsToBounds = YES;
		tile.tag = i;
		[tile addTarget:self action:@selector(actionTileTapped:)
	   forControlEvents:UIControlEventTouchUpInside];
		[header addSubview:tile];

		UIImageView *glyph = [[UIImageView alloc] initWithFrame:
				CGRectMake(TGCenteredOrigin(tileW, kTileGlyph), TGMetricPad, kTileGlyph, kTileGlyph)];
		glyph.image = [TGIcons menuGlyphNamed:tiles[i][0]];
		glyph.contentMode = UIViewContentModeScaleAspectFit;
		[TGIcons tintImageView:glyph colour:[theme accentColour]];
		[tile addSubview:glyph];

		UILabel *label = [[UILabel alloc] initWithFrame:
				CGRectMake(0, kActionTile - TGMetricQuoteForwardLine, tileW, TGMetricLineMicro)];
		label.text = tiles[i][1];
		label.font = TGFontMicro();
		label.textAlignment = NSTextAlignmentCenter;
		label.textColor = [theme accentColour];
		label.backgroundColor = [UIColor clearColor];
		[tile addSubview:label];
	}
	self.actionNames = tiles;
}

- (void)actionTileTapped:(UIButton *)tile {
	NSString *action = self.actionNames[tile.tag][1];

	if ([action isEqualToString:@"call"] || [action isEqualToString:@"video"]){
		[TGCallViewController presentForUserId:self.userId
										  name:self.name
									  outgoing:YES];
	} else if ([action hasSuffix:@"mute"]){
		self.muted = !self.muted;
		[[TGClient shared] setChat:self.chatId muted:self.muted];
		[self buildHeader];              // the tile says the opposite now
	} else if ([action isEqualToString:@"search"]){
		if (self.onSearchTapped) self.onSearchTapped();
	} else {
		[self showMoreMenuFrom:tile];
	}
}

/// Tapping a member of a group: message them, or - where this account is
/// allowed to - change what they are in it. The sheet moved to
/// TGGroupMemberActions so Group Settings opens the same one.
- (void)showMemberActionsFor:(NSDictionary *)member {
	__weak typeof(self) weakSelf = self;
	[TGGroupMemberActions showForMember:member
								 inChat:self.chatId
								   from:self
							  onChanged:^{
		[weakSelf loadDetails];
	}];
}

/// The "more" menu from the current client, minus what this app cannot do:
/// no secret chats, no gifts.
- (void)showMoreMenuFrom:(UIView *)tile {
	NSMutableArray *items = [NSMutableArray array];
	if (self.userId){
		[items addObject:@{@"title" : @"Share contact", @"icon" : @"forward"}];
		if (self.userId == [[TGClient shared].me[@"id"] longLongValue])
			[items addObject:@{@"title" : @"Copy Profile Link", @"icon" : @"forward"}];
		else
			[items addObject:@{@"title" : @"Groups in Common", @"icon" : @"folder"}];
		[items addObject:@{@"title" : @"Start Secret Chat", @"icon" : @"privacy"}];
	}
	// The things one person can do to another's profile: a note only this
	// account reads, a photo or birthday they may accept, the picture only
	// this account sees, and the card their link opens with.
	if (self.userId && self.userId != [[TGClient shared].me[@"id"] longLongValue]){
		[items addObject:@{@"title" : (self.personalNote.length
				? @"Personal Note" : @"Add Personal Note"), @"icon" : @"edit"}];
		[items addObject:@{@"title" : @"Suggest Profile Photo", @"icon" : @"react"}];
		[items addObject:@{@"title" : @"Suggest Birthday", @"icon" : @"star"}];
		[items addObject:@{@"title" : (self.hasPersonalPhoto
				? @"Change Personal Photo" : @"Set Personal Photo"), @"icon" : @"user"}];
		if (self.hasPersonalPhoto)
			[items addObject:@{@"title" : @"Remove Personal Photo", @"icon" : @"delete",
							   @"destructive" : @YES}];
		[items addObject:@{@"title" : @"Share Theme", @"icon" : @"folder"}];
	}
	// A group's own management lives on one screen now. The menu keeps the
	// way in and the rows that are not group management (a note, the date
	// picker, the chat's own history actions).
	if (!self.userId){
		[items addObject:@{@"title" : @"Group Settings", @"icon" : @"privacy"}];
		[items addObject:@{@"title" : @"Calls", @"icon" : @"call"}];
		[items addObject:@{@"title" : @"View with Topics", @"icon" : @"folder"}];
	}
	// A note kept in the chat without being sent to anyone. It is the only
	// way to make a message that never leaves this device.
	[items addObject:@{@"title" : @"Add Local Note", @"icon" : @"edit"}];
	if ([[TGClient shared] chatIsSavedMessages:self.chatId])
		[items insertObject:@{@"title" : @"Topics", @"icon" : @"folder"} atIndex:0];
	if (self.onJumpToDateTapped)
		[items addObject:@{@"title" : @"Jump to Date", @"icon" : @"folder"}];
	[items addObject:@{@"title" : @"Auto-delete messages", @"icon" : @"delete"}];
	[items addObject:@{@"title" : @"Clear history", @"icon" : @"delete"}];
	[items addObject:@{@"title" : @"Report", @"icon" : @"privacy",
					   @"destructive" : @YES}];
	BOOL isMe = self.userId == [[TGClient shared].me[@"id"] longLongValue];
	if (self.userId && !isMe)
		[items addObject:@{@"title" : @"Delete Contact", @"icon" : @"delete", @"destructive" : @YES}];
	// Owners only; Telegram says so to anyone else, and the menu does not
	// know the role without asking.
	if (!self.userId)
		[items addObject:@{@"title" : @"Delete for Everyone", @"icon" : @"delete", @"destructive" : @YES}];
	if (self.userId)
		[items addObject:@{@"title" : (self.blocked ? @"Unblock" : @"Block"),
						   @"icon" : @"privacy", @"destructive" : @YES}];

	CGPoint where = [tile convertPoint:CGPointMake(TGHalf(tile.bounds.size.width),
												   tile.bounds.size.height)
								toView:self.navigationController.view];
	__weak typeof(self) weakSelf = self;
	[TGPopupMenu showItems:items atPoint:where inView:self.navigationController.view
				  onChoice:^(NSInteger index, NSString *title){
		[weakSelf runMoreAction:title];
	}];
}

/// The chat's own link, with the two things worth doing to it: copying it,
/// and replacing it so the old one stops working.
- (void)reportThisChatWithOption:(NSString *)optionId {
	__weak typeof(self) weakSelf = self;
	[[TGClient shared] reportChat:self.chatId
						 optionId:optionId
							 text:@""
					   completion:^(NSString *title, NSArray *options, BOOL done){
		TGProfileViewController *me = weakSelf;
		if (!me)
			return;
		if (done){
			[TGAlertSheet showMessage:@"Thank you. Telegram has the report."
								title:@"Reported" inView:me.view];
			return;
		}
		if (!options.count){
			// A reason this screen has no step for - free text, or a report
			// that has to name messages. Saying so beats a dead menu row.
			[TGAlertSheet showMessage:@"This report needs a reason this app "
									  @"cannot ask for yet."
								title:@"Report" inView:me.view];
			return;
		}

		NSMutableArray *titles = [NSMutableArray array];
		for (NSDictionary *option in options)
			[titles addObject:option[@"text"]];
		[TGAlertSheet showChoices:titles
							title:title.length ? title : @"Report"
				 destructiveIndex:-1
						   inView:me.view
						 onChoice:^(NSInteger index){
			[me reportThisChatWithOption:options[(NSUInteger)index][@"id"]];
		}];
	}];
}

- (void)runMoreAction:(NSString *)title {
	if ([title isEqualToString:@"Copy Profile Link"]){
		// The link is Telegram's, not the username's spellcheck: ask whose
		// account it hands out, which here is the signed-in one.
		NSString *name = self.name;
		__weak typeof(self) weakSelf = self;
		[[TGClient shared] myUserLink:^(NSString *link){
			if (!link.length){
				[TGAlertSheet showMessage:@"Telegram did not hand a link back."
									title:@"Copy Profile Link"
								   inView:weakSelf.view];
				return;
			}
			[UIPasteboard generalPasteboard].string = link;
			NSString *who = name.length ? name : @"link";
			NSString *message = [NSString stringWithFormat:@"%@ copied:\n%@",
					who, link];
			[TGAlertSheet showMessage:message
								title:@"Copy Profile Link"
							   inView:weakSelf.view];
		}];
		return;
	}

	if ([title isEqualToString:@"Groups in Common"]){
		// The chats both accounts sit in, and each openable the way a chat
		// row opens - because a group nobody can enter from here is listed
		// for nothing.
		int64_t userId = self.userId;
		NSString *who = self.name;
		__weak typeof(self) weakSelf = self;
		[[TGClient shared] groupsInCommonWithUser:userId completion:^(NSArray *chats){
			if (!chats.count){
				NSString *message = [NSString stringWithFormat:
						@"You are not in any groups with %@.", who ?: @"them"];
				[TGAlertSheet showMessage:message
									title:@"Groups in Common"
								   inView:weakSelf.view];
				return;
			}
			NSMutableArray *titles = [NSMutableArray array];
			for (NSDictionary *c in chats)
				[titles addObject:c[@"title"] ?: @""];
			[TGAlertSheet showChoices:titles
								title:(who.length
										? [NSString stringWithFormat:
												@"With %@", who]
										: @"Groups in Common")
					 destructiveIndex:-1
							   inView:weakSelf.view
							 onChoice:^(NSInteger index){
				NSDictionary *c = chats[index];
				TGChatViewController *vc = [[TGChatViewController alloc] init];
				vc.chatId = [c[@"chatId"] longLongValue];
				vc.chatTitle = c[@"title"];
				vc.isGroup = YES;
				vc.hidesBottomBarWhenPushed = YES;
				[weakSelf.navigationController pushViewController:vc animated:YES];
			}];
		}];
		return;
	}

	if ([title isEqualToString:@"Share contact"]){
		TGForwardPicker *picker = [[TGForwardPicker alloc] init];
		NSString *name = self.name;
		int64_t userId = self.userId;
		__weak typeof(self) weakSelf = self;
		picker.onPicked = ^(int64_t targetChatId){
			NSString *phone = weakSelf.phoneNumber;
			if (!phone.length){
				[TGAlertSheet showMessage:@"This account does not show its phone number."
									title:@"Share contact"
								   inView:weakSelf.view];
				return;
			}
			[[TGClient shared] sendContactNamed:name phone:phone toChat:targetChatId];
		};
		(void)userId;
		[self.navigationController pushViewController:picker animated:YES];
		return;
	}


	if ([title isEqualToString:@"Auto-delete messages"]){
		int64_t chatId = self.chatId;
		[TGAlertSheet showChoices:@[@"Off", @"1 day", @"1 week", @"1 month"]
							title:@"Delete messages after"
				 destructiveIndex:-1
						   inView:self.view
						 onChoice:^(NSInteger index){
			static const NSInteger seconds[4] = {0, 86400, 604800, 2592000};
			[[TGClient shared] setChat:chatId autoDeleteSeconds:seconds[index]];
		}];
		return;
	}

	if ([title isEqualToString:@"Add Local Note"]){
		int64_t chatId = self.chatId;
		__weak typeof(self) weakSelf = self;
		[TGAlertSheet showInput:@"Add Local Note"
						message:@"Kept in this chat on this device; never sent."
					placeholder:@"Note"
						   text:nil
						 action:@"Add"
						 inView:self.view
					   onSubmit:^(NSString *text){
			[[TGClient shared] addLocalTextMessage:text toChat:chatId
										completion:^(int64_t messageId){
				TGProfileViewController *me = weakSelf;
				if (!me)
					return;
				[TGSnackbar showInView:me.view
								  text:(messageId ? @"Note added"
												  : @"Telegram refused the note")
							   seconds:2 onCommit:nil];
			}];
		}];
		return;
	}



	if ([title isEqualToString:@"Start Secret Chat"]){
		int64_t userId = self.userId;
		NSString *name = self.name;
		__weak typeof(self) weakSelf = self;
		[[TGClient shared] createSecretChatWithUser:userId
										completion:^(int64_t chatId){
			TGProfileViewController *me = weakSelf;
			if (!chatId){
				[TGAlertSheet showMessage:@"Telegram refused a secret chat with "
										  @"this account."
									title:@"Secret Chat" inView:me.view];
				return;
			}
			// It exists but is not usable until their device answers the key
			// exchange, and a chat that silently refuses to send reads as a
			// bug rather than as waiting.
			Class chatClass = NSClassFromString(@"TGChatViewController");
			UIViewController *chat = [[chatClass alloc] init];
			[chat setValue:@(chatId) forKey:@"chatId"];
			[chat setValue:[NSString stringWithFormat:@"%@ (secret)",
					name.length ? name : @"Secret"] forKey:@"chatTitle"];
			chat.hidesBottomBarWhenPushed = YES;
			[me.navigationController pushViewController:chat animated:YES];
			[TGAlertSheet showMessage:@"Nothing can be sent until their device "
									  @"comes online and accepts the key."
								title:@"Secret Chat" inView:chat.view];
		}];
		return;
	}








	if ([title isEqualToString:@"Calls"]){
		TGGroupCallViewController *screen = [[TGGroupCallViewController alloc]
				initWithChatId:self.chatId groupCallId:0];
		screen.hidesBottomBarWhenPushed = YES;
		TGPresentControllerFrom(screen, self);
		return;
	}
	if ([title isEqualToString:@"Group Settings"]){
		// Build through the runtime class name so a build that somehow lost
		// the screen says so in the log instead of pushing nil and looking
		// like a dead row.
		Class settingsClass = NSClassFromString(@"TGGroupSettingsViewController");
		TGGroupSettingsViewController *settings = settingsClass
				? [[settingsClass alloc] init] : nil;
		if (!settings){
			NSLog(@"TGProfile: Group Settings unavailable (class %@, chat %lld)",
				  settingsClass ? @"present but init returned nil" : @"missing",
				  self.chatId);
			[TGAlertSheet showMessage:@"Group Settings could not be opened on this build."
								title:@"Group Settings" inView:self.view];
			return;
		}
		settings.chatId = self.chatId;
		settings.chatTitle = self.name;
		settings.hidesBottomBarWhenPushed = YES;
		NSLog(@"TGProfile: opening Group Settings for chat %lld", self.chatId);
		// Pushing is right when this profile is on a stack. A profile shown
		// modally has none, and `[nil pushViewController:]` is the tap that
		// does nothing; the shared helper presents it instead.
		TGPresentControllerFrom(settings, self);
		return;
	}

	/// The picker answers the same way the settings screen's own does: one
	/// UIImagePicker serves both wallpaper and avatar there, one serves this
	/// screen's group photo here.



	if ([title isEqualToString:@"Topics"]){
		__weak typeof(self) weakSelf = self;
		Class topicsClass = NSClassFromString(@"TGSavedTopicsViewController");
		UIViewController *topics = [[topicsClass alloc] init];
		if (topics){
			topics.hidesBottomBarWhenPushed = YES;
			[weakSelf.navigationController pushViewController:topics animated:YES];
		}
		return;
	}





	if ([title isEqualToString:@"View with Topics"]){
		int64_t chatId = self.chatId;
		NSString *chatTitle = self.name;
		__weak typeof(self) weakSelf = self;
		// What it is now is read off the chat, so the menu row says the
		// move it is about to make rather than one it has already made.
		NSString *next = @"Show Topics";
		NSString *warn = @"The channel is shown as one flow of messages now; "
						 @"showing it as a list of topics instead.";
		NSString *now = @"Show as One Flow";
		NSString *warnBack = @"The channel is shown as topics now; showing "
							 @"it as one flow of messages instead.";
		[[TGClient shared] chatWithViewAsTopics:chatId completion:^(BOOL viewAsTopics){
			NSString *action = viewAsTopics ? now : next;
			NSString *say = viewAsTopics ? warnBack : warn;
			[TGAlertSheet showConfirm:say
								title:nil
							   action:action
						  destructive:NO
							   inView:weakSelf.view
							onConfirm:^{
				[[TGClient shared] setChatViewAsTopics:chatId
										  viewAsTopics:!viewAsTopics
											completion:^(BOOL ok){
					TGProfileViewController *me = weakSelf;
					if (!ok)
						[TGAlertSheet showMessage:@"Telegram refused that. Only "
												  @"an administrator of a forum "
												  @"supergroup or a channel "
												  @"flips this."
											title:(chatTitle ?: @"Topics")
										   inView:me.view];
				}];
			}];
		}];
		return;
	}

	if ([title isEqualToString:@"Add Personal Note"] ||
			[title isEqualToString:@"Personal Note"]){
		int64_t userId = self.userId;
		__weak typeof(self) weakSelf = self;
		void (^write)(void) = ^{
			[TGAlertSheet showInput:@"Personal Note"
							message:@"Only you see this. An empty note removes it."
						placeholder:@"A few words"
							   text:weakSelf.personalNote
							 action:@"Save"
							 inView:weakSelf.view
						   onSubmit:^(NSString *text){
				[[TGClient shared] setUserNote:text forUser:userId
									completion:^(BOOL ok, NSString *error){
					TGProfileViewController *me = weakSelf;
					if (!ok){
						[TGAlertSheet showMessage:(error ?: @"Telegram refused that.")
											title:@"Personal Note" inView:me.view];
						return;
					}
					me.personalNote = text;
					[me loadDetails];
					[TGAlertSheet showMessage:@"Note saved."
										title:@"Personal Note" inView:me.view];
				}];
			}];
		};
		if (!self.personalNote.length){
			write();
			return;
		}
		[TGAlertSheet showChoices:@[@"Edit Note", @"Remove Note"]
							title:@"Personal Note"
				 destructiveIndex:1
						   inView:self.view
						 onChoice:^(NSInteger index){
			if (index == 0){
				write();
				return;
			}
			[[TGClient shared] setUserNote:@"" forUser:userId
								completion:^(BOOL ok, NSString *error){
				TGProfileViewController *me = weakSelf;
				if (!ok){
					[TGAlertSheet showMessage:(error ?: @"Telegram refused that.")
										title:@"Personal Note" inView:me.view];
					return;
				}
				me.personalNote = @"";
				[me loadDetails];
				[TGAlertSheet showMessage:@"Note removed."
									title:@"Personal Note" inView:me.view];
			}];
		}];
		return;
	}

	if ([title isEqualToString:@"Suggest Birthday"]){
		int64_t userId = self.userId;
		__weak typeof(self) weakSelf = self;
		[TGAlertSheet showInput:@"Suggest Birthday"
						message:@"Telegram asks them to accept it; their profile "
								@"does not change until they do."
					placeholder:@"YYYY-MM-DD"
						   text:nil
						 action:@"Suggest"
						 inView:self.view
					   onSubmit:^(NSString *text){
			NSArray *parts = [text componentsSeparatedByString:@"-"];
			NSInteger year = parts.count > 0 ? [parts[0] integerValue] : 0;
			NSInteger month = parts.count > 1 ? [parts[1] integerValue] : 0;
			NSInteger day = parts.count > 2 ? [parts[2] integerValue] : 0;
			if (day < 1 || day > 31 || month < 1 || month > 12){
				[TGAlertSheet showMessage:@"Write the date as YYYY-MM-DD."
									title:@"Suggest Birthday" inView:weakSelf.view];
				return;
			}
			[[TGClient shared] suggestBirthdateDay:day month:month year:year
										  forUser:userId
									   completion:^(BOOL ok, NSString *error){
				TGProfileViewController *me = weakSelf;
				[TGAlertSheet showMessage:(ok
						? @"Birthday suggested."
						: (error ?: @"Telegram refused that."))
									title:@"Suggest Birthday" inView:me.view];
			}];
		}];
		return;
	}

	if ([title isEqualToString:@"Suggest Profile Photo"] ||
			[title isEqualToString:@"Set Personal Photo"] ||
			[title isEqualToString:@"Change Personal Photo"]){
		self.pendingPhotoAction = [title isEqualToString:@"Suggest Profile Photo"]
				? @"suggest" : @"personal";
		UIImagePickerController *picker = [[UIImagePickerController alloc] init];
		picker.sourceType = UIImagePickerControllerSourceTypePhotoLibrary;
		picker.delegate = self;
		[self presentViewController:picker animated:YES completion:nil];
		return;
	}

	if ([title isEqualToString:@"Remove Personal Photo"]){
		int64_t userId = self.userId;
		__weak typeof(self) weakSelf = self;
		[TGAlertSheet showConfirm:@"The picture only you see for them is removed."
							title:@"Remove Personal Photo"
						   action:@"Remove"
					  destructive:YES
						   inView:self.view
						onConfirm:^{
			[[TGClient shared] setPersonalProfilePhotoAtPath:nil forUser:userId
												  completion:^(BOOL ok, NSString *error){
				TGProfileViewController *me = weakSelf;
				if (!ok){
					[TGAlertSheet showMessage:(error ?: @"Telegram refused that.")
										title:@"Personal Photo" inView:me.view];
					return;
				}
				me.hasPersonalPhoto = NO;
				[me loadDetails];
				[TGAlertSheet showMessage:@"Personal photo removed."
									title:@"Personal Photo" inView:me.view];
			}];
		}];
		return;
	}

	if ([title isEqualToString:@"Share Theme"]){
		int64_t userId = self.userId;
		__weak typeof(self) weakSelf = self;
		[[TGClient shared] profileShareThemeBackdropsWithCompletion:^(NSArray *backdrops,
																	   NSString *error){
			TGProfileViewController *me = weakSelf;
			if (!me)
				return;
			if (error.length){
				[TGAlertSheet showMessage:error title:@"Share Theme" inView:me.view];
				return;
			}
			NSMutableArray *titles = [NSMutableArray arrayWithObject:@"Default"];
			for (NSDictionary *backdrop in backdrops)
				[titles addObject:backdrop[@"name"] ?: @"Backdrop"];
			if (titles.count == 1){
				[TGAlertSheet showMessage:@"Telegram did not send any backdrops."
									title:@"Share Theme" inView:me.view];
				return;
			}
			[TGAlertSheet showChoices:titles
								title:@"Share Theme"
							  message:@"The card shown when your link to them is shared."
					 destructiveIndex:-1
							   inView:me.view
							 onChoice:^(NSInteger index){
				[[TGClient shared] privateChatWithUser:userId completion:^(int64_t chatId){
					if (!chatId){
						[TGAlertSheet showMessage:@"Telegram did not open a chat for the theme."
											title:@"Share Theme" inView:me.view];
						return;
					}
					void (^answer)(BOOL, NSString *) = ^(BOOL ok, NSString *error){
						[TGAlertSheet showMessage:(ok
								? @"Share theme updated."
								: (error ?: @"Telegram refused that."))
											title:@"Share Theme" inView:me.view];
						if (ok)
							[me loadDetails];
					};
					if (index == 0){
						[[TGClient shared] clearProfileShareThemeForChat:chatId
															  completion:answer];
						return;
					}
					NSDictionary *backdrop = backdrops[(NSUInteger)index - 1];
					[[TGClient shared] setProfileShareThemeForChat:chatId
														backdropId:[backdrop[@"id"] integerValue]
														useDefault:NO
														completion:answer];
				}];
			}];
		}];
		return;
	}

	if ([title isEqualToString:@"Report"]){
		[self reportThisChatWithOption:nil];
		return;
	}

	if ([title isEqualToString:@"Jump to Date"]){
		if (self.onJumpToDateTapped)
			self.onJumpToDateTapped();
		return;
	}

	if ([title isEqualToString:@"Delete Contact"]){
		int64_t userId = self.userId;
		__weak typeof(self) weakSelf = self;
		[TGAlertSheet showConfirm:@"They leave your contacts. The chat with them stays."
							title:@"Delete Contact"
						   action:@"Delete"
					  destructive:YES
						   inView:self.view
						onConfirm:^{
			[[TGClient shared] removeContactWithUserId:userId completion:^(BOOL ok){
				[TGAlertSheet showMessage:(ok ? @"Removed from your contacts." : @"Telegram refused that.")
									title:@"Delete Contact" inView:weakSelf.view];
			}];
		}];
		return;
	}

	if ([title isEqualToString:@"Delete for Everyone"]){
		int64_t chatId = self.chatId;
		__weak typeof(self) weakSelf = self;
		[TGAlertSheet showConfirm:@"The group and every message in it are deleted for all members. This cannot be undone."
							title:@"Delete for Everyone"
						   action:@"Delete"
					  destructive:YES
						   inView:self.view
						onConfirm:^{
			[[TGClient shared] deleteChatForEveryone:chatId completion:^(NSString *error){
				TGProfileViewController *me = weakSelf;
				if (error) {
					[TGAlertSheet showMessage:error title:@"Delete for Everyone" inView:me.view];
					return;
				}
				[me.navigationController popToRootViewControllerAnimated:YES];
			}];
		}];
		return;
	}

	if ([title isEqualToString:@"Clear history"]){
		int64_t chatId = self.chatId;
		[TGAlertSheet showConfirm:@"Every message in this chat will be removed for you."
							title:@"Clear history"
						   action:@"Clear"
					  destructive:YES
						   inView:self.view
						onConfirm:^{ [[TGClient shared] clearHistoryInChat:chatId]; }];
		return;
	}

	[[TGClient shared] setUser:self.userId blocked:!self.blocked];
	self.blocked = !self.blocked;
}

/// The picker's answer becomes a file, because that is what the photo
/// requests take: scaled, JPEG'd and written out like the settings screen
/// does with its avatar.
- (void)imagePickerController:(UIImagePickerController *)picker
		didFinishPickingMediaWithInfo:(NSDictionary *)info {
	[picker dismissViewControllerAnimated:YES completion:nil];
	if (self.pendingPhotoAction.length){
		NSString *action = self.pendingPhotoAction;
		self.pendingPhotoAction = nil;
		UIImage *image = info[UIImagePickerControllerOriginalImage];
		if (!image)
			return;
		UIImage *scaled = [TGIcons decodedImage:image
								fittingSize:CGSizeMake(TGMetricUploadPhotoSide, TGMetricUploadPhotoSide)
									   fill:NO scale:TGMetricScaleFull];
		NSString *path = [NSTemporaryDirectory()
				stringByAppendingPathComponent:@"profile-suggestion.jpg"];
		if (![UIImageJPEGRepresentation(scaled, TGCompressionQualityStandard) writeToFile:path atomically:YES]){
			[TGAlertSheet showMessage:@"Could not prepare the picture."
								title:@"Profile Photo" inView:self.view];
			return;
		}
		int64_t userId = self.userId;
		__weak typeof(self) weakSelf = self;
		BOOL suggest = [action isEqualToString:@"suggest"];
		void (^answer)(BOOL, NSString *) = ^(BOOL ok, NSString *error){
			TGProfileViewController *me = weakSelf;
			if (!ok){
				[TGAlertSheet showMessage:(error ?: @"Telegram refused that.")
									title:@"Profile Photo" inView:me.view];
				return;
			}
			[TGAlertSheet showMessage:(suggest
					? @"Photo suggested."
					: @"Personal photo saved.")
								title:@"Profile Photo" inView:me.view];
			if (!suggest)
				[me loadDetails];
		};
		if (suggest)
			[[TGClient shared] suggestProfilePhotoAtPath:path forUser:userId
											  completion:answer];
		else
			[[TGClient shared] setPersonalProfilePhotoAtPath:path forUser:userId
												  completion:answer];
		return;
	}
}

- (void)imagePickerControllerDidCancel:(UIImagePickerController *)picker {
	self.pendingPhotoAction = nil;
	[picker dismissViewControllerAnimated:YES completion:nil];
}

@end
