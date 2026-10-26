#import "TGProfileViewControllerInternal.h"
#import "TGCapabilities.h"
#import "TGStatusText.h"
#import "TGStyle.h"
#import "TGAlertSheet.h"
#import "TGContactsViewController.h"
#import "TGChatViewController.h"
#import "TGProfilePhotosViewController.h"

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
	CGFloat tileW = (width - 2 * margin - gap * (tiles.count - 1)) / tiles.count;
	TGTheme *theme = [TGTheme shared];

	for (NSUInteger i = 0; i < tiles.count; i++){
		UIButton *tile = [UIButton buttonWithType:UIButtonTypeCustom];
		tile.frame = CGRectMake(margin + i * (tileW + gap), y, tileW, kActionTile);
		tile.backgroundColor = [theme actionTileBackgroundColour];
		tile.layer.cornerRadius = 8;
		tile.tag = i;
		[tile addTarget:self action:@selector(actionTileTapped:)
	   forControlEvents:UIControlEventTouchUpInside];
		[header addSubview:tile];

		UIImageView *glyph = [[UIImageView alloc] initWithFrame:
				CGRectMake((tileW - 22) / 2, 8, 22, 22)];
		glyph.image = [TGIcons menuGlyphNamed:tiles[i][0]];
		glyph.contentMode = UIViewContentModeScaleAspectFit;
		glyph.tintColor = [theme accentColour];
		[tile addSubview:glyph];

		UILabel *label = [[UILabel alloc] initWithFrame:
				CGRectMake(0, kActionTile - 18, tileW, 14)];
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
/// allowed to - change what they are in it. Which of those appear is decided
/// by getChatAdministrators rather than guessed, so a plain member's menu is
/// not a list of things that will be refused.
- (void)showMemberActionsFor:(NSDictionary *)member {
	int64_t userId = [member[@"id"] longLongValue];
	NSString *name = [member[@"name"] length] ? member[@"name"]
			: [[TGClient shared] nameForUserId:userId];
	if (!userId || userId == [[TGClient shared].me[@"id"] longLongValue])
		return;

	int64_t chatId = self.chatId;
	__weak typeof(self) weakSelf = self;
	[[TGClient shared] administratorsOfChat:chatId completion:^(NSArray *admins){
		TGProfileViewController *me = weakSelf;
		if (!me)
			return;

		int64_t myId = [[TGClient shared].me[@"id"] longLongValue];
		BOOL iCanEdit = NO, iAmOwner = NO, theyAreAdmin = NO;
		for (NSDictionary *admin in admins){
			int64_t adminId = [admin[@"id"] longLongValue];
			if (adminId == myId){
				iCanEdit = [admin[@"owner"] boolValue] ||
						   [admin[@"editable"] boolValue];
				iAmOwner = [admin[@"owner"] boolValue];
			}
			if (adminId == userId)
				theyAreAdmin = YES;
		}

		NSMutableArray *choices = [NSMutableArray arrayWithObject:@"Send Message"];
		if (iCanEdit){
			[choices addObject:theyAreAdmin ? @"Dismiss as Admin"
											: @"Promote to Admin"];
			[choices addObject:@"Remove from Group"];
			[choices addObject:@"Ban"];
			if (iAmOwner)
				[choices addObject:@"Hand Over Ownership"];
		}

		[TGAlertSheet showChoices:choices
							title:name.length ? name : @"Member"
				 destructiveIndex:(iCanEdit ? (NSInteger)choices.count - 1 : -1)
						   inView:me.view
						 onChoice:^(NSInteger index){
			[me runMemberAction:choices[(NSUInteger)index]
						 onUser:userId named:name];
		}];
	}];
}

- (void)runMemberAction:(NSString *)action onUser:(int64_t)userId named:(NSString *)name {
	int64_t chatId = self.chatId;
	__weak typeof(self) weakSelf = self;
	void (^report)(BOOL) = ^(BOOL ok){
		TGProfileViewController *me = weakSelf;
		if (!ok){
			[TGAlertSheet showMessage:@"Telegram refused that change."
								title:action inView:me.view];
			return;
		}
		[me loadDetails];
	};

	if ([action isEqualToString:@"Send Message"]){
		[[TGClient shared] privateChatWithUser:userId completion:^(int64_t privateId){
			TGProfileViewController *me = weakSelf;
			if (!privateId)
				return;
			Class chatClass = NSClassFromString(@"TGChatViewController");
			UIViewController *chat = [[chatClass alloc] init];
			[chat setValue:@(privateId) forKey:@"chatId"];
			[chat setValue:(name ?: @"") forKey:@"chatTitle"];
			chat.hidesBottomBarWhenPushed = YES;
			[me.navigationController pushViewController:chat animated:YES];
		}];

	} else if ([action isEqualToString:@"Promote to Admin"]){
		[[TGClient shared] setMember:userId inChat:chatId status:@"administrator"
						  completion:report];

	} else if ([action isEqualToString:@"Dismiss as Admin"]){
		[[TGClient shared] setMember:userId inChat:chatId status:@"member"
						  completion:report];

	} else if ([action isEqualToString:@"Remove from Group"]){
		[[TGClient shared] setMember:userId inChat:chatId status:@"left"
						  completion:report];

	} else if ([action isEqualToString:@"Ban"]){
		[TGAlertSheet showConfirm:[NSString stringWithFormat:
						@"%@ is removed and cannot come back on an invite link.",
						name.length ? name : @"They"]
							title:@"Ban"
						   action:@"Ban"
					  destructive:YES
						   inView:self.view
						onConfirm:^{
			[[TGClient shared] banMember:userId inChat:chatId
						  revokeMessages:NO completion:report];
		}];

	} else if ([action isEqualToString:@"Hand Over Ownership"]){
		// The confirm says what handing over is: ownership leaves this
		// account entirely, and TDLib demands the 2FA password for it.
		NSString *who = name.length ? name : @"them";
		[TGAlertSheet showConfirm:[NSString stringWithFormat:
						@"%@ becomes this chat's owner. This account turns "
						@"into an ordinary member of it, and only Telegram "
						@"support can turn it back.", who]
							title:@"Hand Over Ownership"
						   action:@"Hand Over"
					  destructive:NO
						   inView:self.view
						onConfirm:^{
			[[TGClient shared] hasPasswordWithCompletion:
					^(BOOL has, NSString *email){
				void (^hand)(NSString *) = ^(NSString *password){
					[[TGClient shared] transferOwnershipOfChat:chatId
														 toUser:userId
													   password:password
													 completion:report];
				};
				if (!has){
					hand(@"");
					return;
				}
				// Two-step verification is on: the request carries the
				// password, which the screen never stores anywhere.
				[TGAlertSheet showSecureInput:@"Your Password"
									  message:@"Telegram answers a handover "
											  @"only when this is right."
								  placeholder:@"2FA password"
									   action:@"Hand Over"
									   inView:self.view
									 onSubmit:hand];
			}];
		}];
	}
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
	// A group's own management, which was not reachable from anywhere.
	if (!self.userId){
		[items addObject:@{@"title" : @"Add Members", @"icon" : @"select"}];
		[items addObject:@{@"title" : @"Group Name", @"icon" : @"edit"}];
		[items addObject:@{@"title" : @"Group Photo", @"icon" : @"react"}];
		[items addObject:@{@"title" : @"Group Description", @"icon" : @"edit"}];
		[items addObject:@{@"title" : @"Permissions", @"icon" : @"privacy"}];
		[items addObject:@{@"title" : @"Invite Link", @"icon" : @"forward"}];
		[items addObject:@{@"title" : @"Join Requests", @"icon" : @"select"}];
		[items addObject:@{@"title" : @"View with Topics", @"icon" : @"folder"}];
	}
	[items addObject:@{@"title" : @"Auto-delete messages", @"icon" : @"delete"}];
	[items addObject:@{@"title" : @"Clear history", @"icon" : @"delete"}];
	[items addObject:@{@"title" : @"Report", @"icon" : @"privacy",
					   @"destructive" : @YES}];
	if (self.userId)
		[items addObject:@{@"title" : (self.blocked ? @"Unblock" : @"Block"),
						   @"icon" : @"privacy", @"destructive" : @YES}];

	CGPoint where = [tile convertPoint:CGPointMake(tile.bounds.size.width / 2,
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
- (void)showInviteLink {
	int64_t chatId = self.chatId;
	__weak typeof(self) weakSelf = self;
	[[TGClient shared] inviteLinksForChat:chatId completion:^(NSArray *links){
		TGProfileViewController *me = weakSelf;
		if (!me)
			return;

		NSString *primary = nil;
		for (NSDictionary *link in links)
			if ([link[@"primary"] boolValue] && ![link[@"revoked"] boolValue]){
				primary = link[@"link"];
				break;
			}
		if (!primary.length && links.count)
			primary = links[0][@"link"];

		if (!primary.length){
			// A chat with no link is one this account cannot invite to, which
			// is the answer rather than an empty sheet.
			[TGAlertSheet showMessage:@"This chat has no invite link, and only "
									  @"an administrator can make one."
								title:@"Invite Link" inView:me.view];
			return;
		}

		NSMutableArray *choices = [NSMutableArray arrayWithObjects:
				@"Copy Link", @"Create Extra Link", @"All Links...", nil];
		[TGAlertSheet showChoices:choices
							title:primary
				 destructiveIndex:-1
						   inView:me.view
						 onChoice:^(NSInteger index){
			if (index == 0){
				[UIPasteboard generalPasteboard].string = primary;
				[TGAlertSheet showMessage:@"Copied." title:nil inView:me.view];
				return;
			}
			if (index == 1){
				[[TGClient shared] createInviteLinkForChat:chatId
													  name:nil
											   memberLimit:0
												completion:^(NSString *link){
					NSString *say = link.length ? link
							: @"Telegram refused to create a link - only an "
							  @"administrator of a group with a primary link "
							  @"makes extras.";
					UIView *into = weakSelf.view;
					[TGAlertSheet showMessage:say title:@"New Invite Link" inView:into];
				}];
				return;
			}
			[weakSelf showAllInviteLinks];
		}];
	}];
}

/// Every link the chat has, the primary first. Tapping an extra one revokes
/// it after a confirm, which is what a link list is for; the primary is
/// replaced rather than revoked, since a chat cannot be left linkless.
- (void)showAllInviteLinks {
	int64_t chatId = self.chatId;
	__weak typeof(self) weakSelf = self;
	[[TGClient shared] inviteLinksForChat:chatId completion:^(NSArray *links){
		TGProfileViewController *me = weakSelf;
		if (!me)
			return;
		if (!links.count){
			[TGAlertSheet showMessage:@"This chat has no invite links."
								title:@"All Links" inView:me.view];
			return;
		}

		NSMutableArray *rows = [NSMutableArray array];
		for (NSDictionary *link in links)
			[rows addObject:[NSString stringWithFormat:@"%@%@",
					[link[@"revoked"] boolValue] ? @"(revoked) " : @"",
					link[@"link"]]];

		[TGAlertSheet showChoices:rows
							title:@"All Links"
				 destructiveIndex:-1
						   inView:me.view
						 onChoice:^(NSInteger index){
			TGProfileViewController *again = weakSelf;
			NSDictionary *link = links[index];
			NSString *url = link[@"link"];
			if ([link[@"revoked"] boolValue] || !url.length)
				return;

			void (^refresh)(void) = ^{
				[weakSelf showAllInviteLinks];
			};
			NSString *action = [link[@"primary"] boolValue] ? @"Replace" : @"Revoke";
			NSString *warn = [link[@"primary"] boolValue]
					? @"The common link stops working and a new one takes "
					  @"its place."
					: @"The link above stops working at once, and it does "
					  @"not come back.";
			[TGAlertSheet showConfirm:warn
								title:url
							   action:action
						  destructive:YES
							   inView:again.view
							onConfirm:^{
				if ([link[@"primary"] boolValue]){
					[[TGClient shared] replacePrimaryInviteLinkForChat:chatId
															completion:^(NSString *made){
						[TGAlertSheet showMessage:(made.length ? made
								: @"Telegram refused to replace the link.")
											title:@"Invite Link" inView:weakSelf.view];
					}];
					return;
				}
				[[TGClient shared] revokeInviteLink:url
											 inChat:chatId
										 completion:^(BOOL ok){
					if (!ok)
						[TGAlertSheet showMessage:@"Telegram refused to revoke "
												  @"that link."
											title:@"Revoke" inView:weakSelf.view];
					else
						refresh();
				}];
			}];
		}];
	}];
}

/// People waiting at a link that asks before it lets them in: tap a name,
/// accept them in or not. The refresh re-asks the server, because an
/// approved request announces itself as a member update this screen does
/// not listen for.
- (void)showJoinRequests {
	int64_t chatId = self.chatId;
	__weak typeof(self) weakSelf = self;
	[[TGClient shared] joinRequestsForChat:chatId completion:^(NSArray *requests){
		TGProfileViewController *me = weakSelf;
		if (!me)
			return;
		if (!requests.count){
			[TGAlertSheet showMessage:@"Nobody is waiting at the links."
								title:@"Join Requests" inView:me.view];
			return;
		}

		NSMutableArray *rows = [NSMutableArray array];
		for (NSDictionary *request in requests)
			[rows addObject:request[@"name"] ?: @"?"];

		[TGAlertSheet showChoices:rows
							title:@"Join Requests"
				 destructiveIndex:-1
						   inView:me.view
						 onChoice:^(NSInteger index){
			int64_t userId = [requests[index][@"id"] longLongValue];
			NSString *name = requests[index][@"name"] ?: @"them";
			[TGAlertSheet showChoices:@[@"Accept", @"Decline"]
								title:name
					 destructiveIndex:1
							   inView:weakSelf.view
							 onChoice:^(NSInteger pick){
				[[TGClient shared] processJoinRequest:userId
												inChat:chatId
											   approve:(pick == 0)];
				dispatch_after(dispatch_time(DISPATCH_TIME_NOW,
						(int64_t)(0.5 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
					[weakSelf showJoinRequests];
				});
			}];
		}];
	}];
}

/// Telegram asks why before it takes a report, so this runs twice: once with
/// no option to be told the reasons, then once with the one that was picked.
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

	if ([title isEqualToString:@"Add Members"]){
		TGContactsViewController *contacts = [[TGContactsViewController alloc] init];
		contacts.addingToChatId = self.chatId;
		contacts.hidesBottomBarWhenPushed = YES;
		[self.navigationController pushViewController:contacts animated:YES];
		return;
	}

	if ([title isEqualToString:@"Group Name"]){
		int64_t chatId = self.chatId;
		__weak typeof(self) weakSelf = self;
		[TGAlertSheet showInput:@"Group Name" message:nil placeholder:@"Name"
						   text:self.name action:@"Save" inView:self.view
					   onSubmit:^(NSString *newName){
			[[TGClient shared] setChat:chatId title:newName completion:^(BOOL ok){
				TGProfileViewController *me = weakSelf;
				if (!ok){
					[TGAlertSheet showMessage:@"Only an administrator can rename "
											  @"this group."
										title:@"Group Name" inView:me.view];
					return;
				}
				me.name = newName;
				me.title = newName;
				[me buildHeader];
			}];
		}];
		return;
	}

	if ([title isEqualToString:@"Join Requests"]){
		[self showJoinRequests];
		return;
	}

	if ([title isEqualToString:@"Invite Link"]){
		[self showInviteLink];
		return;
	}

	/// The picker answers the same way the settings screen's own does: one
	/// UIImagePicker serves both wallpaper and avatar there, one serves this
	/// screen's group photo here.
	if ([title isEqualToString:@"Group Photo"]){
		if (![UIImagePickerController isSourceTypeAvailable:
				UIImagePickerControllerSourceTypePhotoLibrary]){
			[TGAlertSheet showMessage:@"The photo library is not on this device."
								title:@"Group Photo" inView:self.view];
			return;
		}
		self.pickingChatPhoto = YES;
		UIImagePickerController *picker = [[UIImagePickerController alloc] init];
		picker.sourceType = UIImagePickerControllerSourceTypePhotoLibrary;
		picker.delegate = self;
		[self presentViewController:picker animated:YES completion:nil];
		return;
	}

	if ([title isEqualToString:@"Group Description"]){
		int64_t chatId = self.chatId;
		NSString *what = self.chatDescription ?: @"";
		__weak typeof(self) weakSelf = self;
		[TGAlertSheet showInput:@"Group Description"
						message:nil
					placeholder:@"What this group is about"
						   text:what
						 action:@"Save"
						 inView:self.view
					 onSubmit:^(NSString *description){
			[[TGClient shared] setChat:chatId description:description
							completion:^(BOOL ok){
				TGProfileViewController *me = weakSelf;
				if (!ok){
					[TGAlertSheet showMessage:@"Only a supergroup or a channel "
											  @"carries a description, and only an "
											  @"administrator writes one."
										title:@"Group Description" inView:me.view];
					return;
				}
				me.chatDescription = description;
			}];
		}];
		return;
	}

	if ([title isEqualToString:@"Permissions"]){
		int64_t chatId = self.chatId;
		__weak typeof(self) weakSelf = self;
		[TGAlertSheet showChoices:@[@"Everything allowed", @"Messages only (no media)", @"Read only"]
							title:@"What members may do"
				 destructiveIndex:-1
						   inView:self.view
						 onChoice:^(NSInteger index){
			NSString *preset = index == 0 ? @"all" : (index == 1 ? @"text" : @"read");
			[[TGClient shared] setChatPermissionsFromPreset:preset
													 inChat:chatId
												  completion:^(BOOL ok){
				TGProfileViewController *me = weakSelf;
				if (!ok)
					[TGAlertSheet showMessage:@"Only an administrator can change "
											  @"what members may do."
										title:@"Permissions" inView:me.view];
			}];
		}];
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

	if ([title isEqualToString:@"Report"]){
		[self reportThisChatWithOption:nil];
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

/// The picker's answer becomes a file, because that is what setChatPhoto
/// takes: scaled, JPEG'd and written out like the settings screen does with
/// its avatar.
- (void)imagePickerController:(UIImagePickerController *)picker
		didFinishPickingMediaWithInfo:(NSDictionary *)info {
	[picker dismissViewControllerAnimated:YES completion:nil];
	if (!self.pickingChatPhoto)
		return;
	self.pickingChatPhoto = NO;

	UIImage *image = info[UIImagePickerControllerOriginalImage];
	if (!image)
		return;
	UIImage *scaled = [TGIcons decodedImage:image
								fittingSize:CGSizeMake(640, 640)
									   fill:NO scale:1.0f];
	NSString *path = [NSTemporaryDirectory()
			stringByAppendingPathComponent:@"group-photo.jpg"];
	if (![UIImageJPEGRepresentation(scaled, 0.9f) writeToFile:path atomically:YES]){
		[TGAlertSheet showMessage:@"Could not prepare the picture."
							title:@"Group Photo" inView:self.view];
		return;
	}

	int64_t chatId = self.chatId;
	__weak typeof(self) weakSelf = self;
	[[TGClient shared] setChat:chatId photoAtPath:path completion:^(BOOL ok){
		TGProfileViewController *me = weakSelf;
		if (!ok){
			[TGAlertSheet showMessage:@"Only an administrator can change "
									  @"this group's photo."
								title:@"Group Photo" inView:me.view];
			return;
		}
		[me reloadTableDebounced];
	}];
}

- (void)imagePickerControllerDidCancel:(UIImagePickerController *)picker {
	self.pickingChatPhoto = NO;
	[picker dismissViewControllerAnimated:YES completion:nil];
}

@end
