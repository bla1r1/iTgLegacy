#import "TGProfileViewControllerInternal.h"
#import "TGCapabilities.h"
#import "TGStatusText.h"
#import "TGStyle.h"
#import "TGAlertSheet.h"
#import "TGSnackbar.h"
#import "TGContactsViewController.h"
#import "TGChatViewController.h"
#import "TGProfilePhotosViewController.h"
#import "TGChatToolsViewController.h"

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

		NSMutableArray *choices = [NSMutableArray arrayWithObject:@"Member Info"];
		[choices addObject:@"Send Message"];
		if (iCanEdit){
			[choices addObject:theyAreAdmin ? @"Dismiss as Admin"
											: @"Promote to Admin"];
			[choices addObject:@"Set Member Tag"];
			[choices addObject:@"Clear Their Reactions"];
			[choices addObject:@"Clear Their Messages"];
			[choices addObject:@"Remove from Group"];
			[choices addObject:@"Ban"];
			if (iAmOwner)
				[choices addObject:@"Hand Over Ownership"];
		}

		[TGAlertSheet showChoices:choices
							title:name.length ? name : @"Member"
				 destructiveIndex:(iCanEdit
						 ? (NSInteger)[choices indexOfObject:@"Ban"] : -1)
						   inView:me.view
						 onChoice:^(NSInteger index){
			[me runMemberAction:choices[(NSUInteger)index]
						 onUser:userId named:name];
		}];
	}];
}

/// One member's own record, which the aggregate list does not carry: the
/// status word, the title this group gave them, and when a restriction lifts.
/// getChatMember is the only request that answers for one person.
- (void)showMemberRecordFor:(int64_t)userId named:(NSString *)name {
	int64_t chatId = self.chatId;
	__weak typeof(self) weakSelf = self;
	[[TGClient shared] chatMember:userId inChat:chatId completion:^(NSDictionary *member){
		TGProfileViewController *me = weakSelf;
		if (!me)
			return;
		NSString *sheetTitle = name.length ? name : @"Member";
		if (!member){
			[TGAlertSheet showMessage:@"Telegram keeps no record of them here."
								  title:sheetTitle inView:me.view];
			return;
		}

		NSDictionary *status = [member[@"status"] isKindOfClass:NSDictionary.class]
				? member[@"status"] : @{};
		NSMutableArray *lines = [NSMutableArray array];
		[lines addObject:[NSString stringWithFormat:@"Status: %@",
						  TGMemberStatusName(status)]];
		if ([member[@"tag"] length])
			[lines addObject:[NSString stringWithFormat:@"Title: %@", member[@"tag"]]];

		double until = [status[@"restricted_until_date"] doubleValue];
		if (until > 0)
			[lines addObject:[NSString stringWithFormat:@"Restricted until %@",
					[NSDateFormatter localizedStringFromDate:
							[NSDate dateWithTimeIntervalSince1970:until]
							dateStyle:NSDateFormatterMediumStyle
							timeStyle:NSDateFormatterNoStyle]]];

		NSDictionary *permissions =
				[status[@"permissions"] isKindOfClass:NSDictionary.class]
				? status[@"permissions"] : nil;
		id send = permissions[@"can_send_basic_messages"]
				?: permissions[@"can_send_messages"];
		if (send)
			[lines addObject:[NSString stringWithFormat:@"Can send messages: %@",
							  [send boolValue] ? @"yes" : @"no"]];

		[TGAlertSheet showMessage:[lines componentsJoinedByString:@"\n"]
							 title:sheetTitle inView:me.view];
	}];
}

/// Find Member: getChatMembers is a page, not a search; searchChatMembers
/// answers the query server-side, which is the only way a group of a few
/// thousand is usable from a phone at all.
- (void)showFindMemberSheet {
	int64_t chatId = self.chatId;
	__weak typeof(self) weakSelf = self;
	[TGAlertSheet showInput:@"Find Member"
					message:nil
				placeholder:@"Name or @username"
					   text:nil
					 action:@"Find"
					 inView:self.view
				 onSubmit:^(NSString *query){
		[[TGClient shared] searchMembersInChat:chatId query:query
									completion:^(NSArray *members){
			TGProfileViewController *me = weakSelf;
			if (!me)
				return;
			if (!members.count){
				[TGAlertSheet showMessage:@"Nobody here answers to that."
									  title:@"Find Member" inView:me.view];
				return;
			}
			NSMutableArray *names = [NSMutableArray array];
			for (NSDictionary *member in members)
				[names addObject:[member[@"name"] length]
						? member[@"name"] : @"Member"];
			[TGAlertSheet showChoices:names
								title:@"Find Member"
					 destructiveIndex:-1
							   inView:me.view
							 onChoice:^(NSInteger index){
				NSDictionary *member = members[(NSUInteger)index];
				int64_t userId = [member[@"id"] longLongValue];
				if (!userId)
					return;
				TGProfileViewController *profile = [[TGProfileViewController alloc]
						initWithChatId:userId
								userId:userId
								 title:[member[@"name"] length] ? member[@"name"] : @""];
				profile.hidesBottomBarWhenPushed = YES;
				[me.navigationController pushViewController:profile animated:YES];
			}];
		}];
	}];
}

/// A basic group has a ceiling of two hundred, and no username. Past that it
/// has to become a supergroup, which TDLib does in one request - and which
/// changes the chat id, so the screen behind this one is now stale.
- (void)confirmUpgradeToSupergroup {
	int64_t chatId = self.chatId;
	__weak typeof(self) weakSelf = self;
	[TGAlertSheet showConfirm:@"A basic group becomes a supergroup: it gets a "
			@"link of its own, room past two hundred members, and a new chat "
			@"id. This screen closes with the old one."
						 title:@"Upgrade"
						action:@"Upgrade"
				   destructive:NO
						inView:self.view
					 onConfirm:^{
		[[TGClient shared] upgradeGroupToSupergroup:chatId
										 completion:^(int64_t newChatId){
			TGProfileViewController *me = weakSelf;
			if (!me)
				return;
			if (!newChatId){
				[TGAlertSheet showMessage:@"Telegram refused the upgrade - a "
						@"supergroup or a channel is already one."
										  title:@"Upgrade" inView:me.view];
				return;
			}
			// The chat behind this screen still wears the old id, which the
			// upgrade retired; the list is the first screen that can open the
			// new one.
			UINavigationController *nav = me.navigationController;
			[nav popToRootViewControllerAnimated:YES];
			[TGAlertSheet showMessage:@"The group is now a supergroup."
								  title:@"Upgraded"
								 inView:(nav.view ?: me.view)];
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

	if ([action isEqualToString:@"Member Info"]){
		[self showMemberRecordFor:userId named:name];
		return;

	} else if ([action isEqualToString:@"Send Message"]){
		// The check before the push: a user who takes no messages from
		// non-contacts turns the composer into a doomed one. Telegram's own
		// answer names which of the four refusals this is.
		[[TGClient shared] canSendMessageToUser:userId completion:^(NSString *result){
			TGProfileViewController *me = weakSelf;
			if (!me)
				return;
			if ([result isEqualToString:@"ok"]){
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
				return;
			}
			NSString *say = [result isEqualToString:@"paidMessages"]
					? @"They charge for incoming messages, and this account "
					   @"carries no wallet for that."
					: ([result isEqualToString:@"userRestrictsNewChats"]
					   ? @"They set their profile to messages from contacts only."
					   : @"That profile is gone.");
			[TGAlertSheet showMessage:say
								title:name.length ? name : @"Message"
								   inView:me.view];
		}];
		return;

	} else if ([action isEqualToString:@"Promote to Admin"]){
		[[TGClient shared] setMember:userId inChat:chatId status:@"administrator"
						  completion:report];

	} else if ([action isEqualToString:@"Dismiss as Admin"]){
		[[TGClient shared] setMember:userId inChat:chatId status:@"member"
						  completion:report];

	} else if ([action isEqualToString:@"Set Member Tag"]){
		[TGAlertSheet showInput:@"Member Tag"
						message:@"A short title shown beside their name in this chat."
					placeholder:@"Tag" text:nil action:@"Save" inView:self.view
					 onSubmit:^(NSString *tag){
			[[TGClient shared] setMemberTag:tag forUser:userId inChat:chatId
					completion:^(BOOL ok){
				[TGAlertSheet showMessage:(ok ? @"Tag saved."
											   : @"Telegram refused that tag.")
									title:@"Member Tag" inView:weakSelf.view];
			}];
		}];

	} else if ([action isEqualToString:@"Clear Their Reactions"]){
		NSDictionary *sender = @{@"@type" : @"messageSenderUser", @"user_id" : @(userId)};
		[TGAlertSheet showConfirm:
				@"Every reaction they added in this chat is removed, here "
				@"and across its messages."
					title:(name.length ? name : @"Member")
						   action:@"Clear"
					  destructive:YES
						   inView:self.view
						onConfirm:^{
			[[TGClient shared] deleteAllReactionsOfSender:sender inChat:chatId];
		}];

	} else if ([action isEqualToString:@"Clear Their Messages"]){
		NSDictionary *sender = @{@"@type" : @"messageSenderUser", @"user_id" : @(userId)};
		[TGAlertSheet showConfirm:
				@"Every message they sent in this chat is deleted for everyone, "
				@"including the copies already delivered."
					title:(name.length ? name : @"Member")
						   action:@"Clear"
					  destructive:YES
						   inView:self.view
						onConfirm:^{
			[[TGClient shared] deleteChatMessagesBySender:sender
												   inChat:chatId
												   revoke:YES];
		}];

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
		[items addObject:@{@"title" : @"Find Member", @"icon" : @"search"}];
		[items addObject:@{@"title" : @"Upgrade to Supergroup", @"icon" : @"folder"}];
		[items addObject:@{@"title" : @"Group Name", @"icon" : @"edit"}];
		[items addObject:@{@"title" : @"Group Photo", @"icon" : @"react"}];
		[items addObject:@{@"title" : @"Group Description", @"icon" : @"edit"}];
		[items addObject:@{@"title" : @"Permissions", @"icon" : @"privacy"}];
		[items addObject:@{@"title" : @"Invite Link", @"icon" : @"forward"}];
		[items addObject:@{@"title" : @"Join Requests", @"icon" : @"select"}];
		[items addObject:@{@"title" : @"View with Topics", @"icon" : @"folder"}];
		[items addObject:@{@"title" : @"Sign Messages", @"icon" : @"edit"}];
		[items addObject:@{@"title" : @"Join to Send", @"icon" : @"select"}];
		[items addObject:@{@"title" : @"All History", @"icon" : @"folder"}];
		[items addObject:@{@"title" : @"Welcome Messages", @"icon" : @"edit"}];
		// A channel's readers answer into a group of their own; the same
		// menu owns the switch, because it is the channel's setting.
		[items addObject:@{@"title" : @"Direct Messages", @"icon" : @"chat"}];
		// An exported history from another client comes in through the chat
		// it belongs to, not through Settings.
		[items addObject:@{@"title" : @"Import Messages", @"icon" : @"data"}];
		[items addObject:@{@"title" : @"Clear by Date", @"icon" : @"delete",
						   @"destructive" : @YES}];
		[items addObject:@{@"title" : @"Send as", @"icon" : @"user"}];
		[items addObject:@{@"title" : @"Chat Tools", @"icon" : @"folder"}];
		[items addObject:@{@"title" : @"Group Stickers", @"icon" : @"star"}];
		[items addObject:@{@"title" : @"Custom Emoji Stickers", @"icon" : @"star"}];
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
				@"Copy Link", @"Create Extra Link", @"Create Subscription Link",
				@"All Links...", @"Link Counts", nil];
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
			if (index == 2){
				[weakSelf createSubscriptionLink];
				return;
			}
			if (index == 3){
				[weakSelf showAllInviteLinks];
				return;
			}
			[weakSelf showInviteLinkCounts];
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
			[rows addObject:[NSString stringWithFormat:@"%@%@  ·  %@ joined",
					[link[@"revoked"] boolValue] ? @"(revoked) " : @"",
					link[@"link"], link[@"members"] ?: @(0)]];
		// Housekeeping rides at the bottom so a revoked link has somewhere
		// to be deleted from the same sheet that lists it.
		[rows addObject:@"Link Counts"];
		[rows addObject:@"Delete All Revoked Links"];

		[TGAlertSheet showChoices:rows
							title:@"All Links"
				 destructiveIndex:(NSInteger)rows.count - 1
						   inView:me.view
						 onChoice:^(NSInteger index){
			TGProfileViewController *again = weakSelf;
			if (!again)
				return;
			if (index == (NSInteger)links.count){
				[again showInviteLinkCounts];
				return;
			}
			if (index == (NSInteger)links.count + 1){
				[again deleteAllRevokedLinks];
				return;
			}
			[again showActionsForInviteLink:links[index] inChat:chatId];
		}];
	}];
}

/// One link's actions: the details getChatInviteLink answers, who joined
/// through it, the fields the two edit calls change, and revoking or deleting
/// it. A revoked link can only be deleted, which is why both words share the
/// sheet.
- (void)showActionsForInviteLink:(NSDictionary *)link inChat:(int64_t)chatId {
	NSString *url = link[@"link"];
	if (!url.length)
		return;

	__weak typeof(self) weakSelf = self;
	[[TGClient shared] inviteLink:url inChat:chatId completion:^(NSDictionary *info){
		TGProfileViewController *me = weakSelf;
		if (!me)
			return;
		NSDictionary *fresh = info ?: link;
		BOOL primary = [fresh[@"primary"] boolValue];
		BOOL revoked = [fresh[@"revoked"] boolValue];
		id subscriptionValue = fresh[@"subscription"];
		BOOL subscription = subscriptionValue &&
				subscriptionValue != [NSNull null];

		NSMutableArray *choices = [NSMutableArray arrayWithObject:@"Copy Link"];
		[choices addObject:@"Members"];
		if (!revoked)
			[choices addObject:subscription ? @"Rename Link" : @"Edit Name & Limit"];
		[choices addObject:(revoked ? @"Delete Link" : (primary ? @"Replace" : @"Revoke"))];

		[TGAlertSheet showChoices:choices title:url destructiveIndex:-1
						   inView:me.view onChoice:^(NSInteger index){
			NSString *action = choices[index];
			if ([action isEqualToString:@"Copy Link"]){
				[UIPasteboard generalPasteboard].string = url;
				[TGAlertSheet showMessage:@"Copied." title:nil inView:me.view];
				return;
			}
			if ([action isEqualToString:@"Members"]){
				[me showMembersOfInviteLink:url inChat:chatId];
				return;
			}
			if ([action isEqualToString:@"Rename Link"]){
				[TGAlertSheet showInput:@"Rename Link" message:nil
							placeholder:@"Name" text:fresh[@"name"] ?: @""
								 action:@"Save" inView:me.view
							 onSubmit:^(NSString *name){
					[[TGClient shared] editSubscriptionInviteLink:url inChat:chatId
							name:name completion:^(BOOL ok){
						[TGAlertSheet showMessage:(ok ? @"Link renamed."
											   : @"Telegram refused the edit.")
											title:@"Invite Link" inView:weakSelf.view];
					}];
				}];
				return;
			}
			if ([action isEqualToString:@"Edit Name & Limit"]){
				[TGAlertSheet showInput:@"Edit Link"
								message:@"Leave the limit empty for no limit."
							placeholder:@"Name" text:fresh[@"name"] ?: @""
								 action:@"Next" inView:me.view
							 onSubmit:^(NSString *name){
					[TGAlertSheet showConfirm:@"Set a member limit?" title:@"Member Limit"
									   action:@"Set Limit" destructive:NO
									   inView:weakSelf.view onConfirm:^{
						[TGAlertSheet showInput:@"Member Limit" message:nil
									placeholder:@"0 for no limit" text:@"0"
										 action:@"Save" inView:weakSelf.view
									 onSubmit:^(NSString *limitText){
							[[TGClient shared] editInviteLink:url inChat:chatId
									name:name expiration:0
									memberLimit:limitText.integerValue
									joinRequest:NO completion:^(BOOL ok){
								[TGAlertSheet showMessage:(ok ? @"Link updated."
															   : @"Telegram refused the edit.")
														title:@"Invite Link" inView:weakSelf.view];
							}];
						}];
					}];
				}];
				return;
			}
			if ([action isEqualToString:@"Delete Link"]){
				[[TGClient shared] deleteRevokedInviteLink:url inChat:chatId
										 completion:^(BOOL ok){
					[TGAlertSheet showMessage:(ok ? @"The revoked link is gone."
												   : @"Telegram refused the delete.")
												title:@"Invite Link" inView:weakSelf.view];
				}];
				return;
			}

			NSString *warn = primary
					? @"The common link stops working and a new one takes its place."
					: @"The link above stops working at once, and it does not come back.";
			[TGAlertSheet showConfirm:warn title:url action:(primary ? @"Replace" : @"Revoke")
					  destructive:YES inView:me.view onConfirm:^{
				if (primary){
					[[TGClient shared] replacePrimaryInviteLinkForChat:chatId
													completion:^(NSString *made){
						[TGAlertSheet showMessage:(made.length ? made
								: @"Telegram refused to replace the link.")
											title:@"Invite Link" inView:weakSelf.view];
					}];
					return;
				}
				[[TGClient shared] revokeInviteLink:url inChat:chatId
										 completion:^(BOOL ok){
					if (!ok)
						[TGAlertSheet showMessage:@"Telegram refused to revoke that link."
											title:@"Revoke" inView:weakSelf.view];
					else
						[weakSelf showAllInviteLinks];
				}];
			}];
		}];
	}];
}

- (void)showMembersOfInviteLink:(NSString *)url inChat:(int64_t)chatId {
	__weak typeof(self) weakSelf = self;
	[[TGClient shared] membersOfInviteLink:url inChat:chatId
								completion:^(NSArray *members){
		TGProfileViewController *me = weakSelf;
		if (!me)
			return;
		if (!members.count){
			[TGAlertSheet showMessage:@"Nobody has joined through this link yet."
								title:@"Link Members" inView:me.view];
			return;
		}
		NSMutableArray *rows = [NSMutableArray array];
		for (NSDictionary *member in members){
			NSDate *date = [NSDate dateWithTimeIntervalSince1970:
					[member[@"date"] doubleValue]];
			NSString *when = [NSDateFormatter localizedStringFromDate:date
					dateStyle:NSDateFormatterMediumStyle timeStyle:NSDateFormatterNoStyle];
			[rows addObject:[NSString stringWithFormat:@"%@ · joined %@",
					member[@"name"] ?: @"Member", when]];
		}
		[TGAlertSheet showChoices:rows title:@"Link Members"
				destructiveIndex:-1 inView:me.view onChoice:^(NSInteger index){
			(void)index;
		}];
	}];
}

- (void)showInviteLinkCounts {
	int64_t chatId = self.chatId;
	__weak typeof(self) weakSelf = self;
	[[TGClient shared] inviteLinkCountsForChat:chatId completion:^(NSArray *counts){
		TGProfileViewController *me = weakSelf;
		if (!me)
			return;
		if (!counts.count){
			[TGAlertSheet showMessage:@"Telegram returned no link counts."
								title:@"Link Counts" inView:me.view];
			return;
		}
		NSMutableArray *rows = [NSMutableArray array];
		for (NSDictionary *count in counts)
			[rows addObject:[NSString stringWithFormat:@"%@: %@ active, %@ revoked",
					count[@"name"] ?: @"Administrator",
					count[@"active"] ?: @(0), count[@"revoked"] ?: @(0)]];
		[TGAlertSheet showChoices:rows title:@"Link Counts"
				destructiveIndex:-1 inView:me.view onChoice:^(NSInteger index){
			(void)index;
		}];
	}];
}

- (void)deleteAllRevokedLinks {
	int64_t chatId = self.chatId;
	__weak typeof(self) weakSelf = self;
	int64_t myId = [[TGClient shared].me[@"id"] longLongValue];
	[TGAlertSheet showConfirm:@"Every revoked link this account made in this "
							  @"chat is deleted permanently."
						title:@"Delete All Revoked Links"
					   action:@"Delete" destructive:YES inView:self.view
					onConfirm:^{
		[[TGClient shared] deleteAllRevokedInviteLinks:chatId creator:myId
				completion:^(BOOL ok){
			[TGAlertSheet showMessage:(ok ? @"Revoked links deleted."
										   : @"Telegram refused the delete.")
								title:@"Invite Links" inView:weakSelf.view];
		}];
	}];
}

- (void)createSubscriptionLink {
	int64_t chatId = self.chatId;
	__weak typeof(self) weakSelf = self;
	[TGAlertSheet showInput:@"Subscription Link"
					message:@"A monthly Star subscription in this channel."
				placeholder:@"Name (optional)" text:nil action:@"Create"
					 inView:self.view onSubmit:^(NSString *name){
		[TGAlertSheet showInput:@"Stars Per Month" message:nil
					placeholder:@"1" text:@"1" action:@"Create"
					 inView:weakSelf.view onSubmit:^(NSString *stars){
			[[TGClient shared] createSubscriptionInviteLink:chatId name:name
					stars:MAX(stars.integerValue, 1) period:2592000
					completion:^(NSString *link){
				[TGAlertSheet showMessage:(link.length ? link
						: @"Telegram refused a subscription link - the chat must be "
						  @"a channel and this account its admin.")
									title:@"Subscription Link" inView:weakSelf.view];
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
		[rows addObject:@"Approve All Requests"];
		[rows addObject:@"Decline All Requests"];

		[TGAlertSheet showChoices:rows
							title:@"Join Requests"
				 destructiveIndex:(NSInteger)rows.count - 1
						   inView:me.view
						 onChoice:^(NSInteger index){
			if (index == (NSInteger)requests.count ||
				index == (NSInteger)requests.count + 1){
				BOOL approve = index == (NSInteger)requests.count;
				[[TGClient shared] processAllJoinRequests:chatId link:@""
						approve:approve completion:^(BOOL ok){
					[TGAlertSheet showMessage:(ok ? @"Every request was answered."
												   : @"Telegram refused the batch.")
										title:@"Join Requests" inView:weakSelf.view];
					[weakSelf showJoinRequests];
				}];
				return;
			}
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

	if ([title isEqualToString:@"Group Stickers"] ||
		[title isEqualToString:@"Custom Emoji Stickers"]){
		[self chooseStickerSetForGroupCustomEmoji:
				[title isEqualToString:@"Custom Emoji Stickers"]];
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

	if ([title isEqualToString:@"Import Messages"]){
		int64_t chatId = self.chatId;
		__weak typeof(self) weakSelf = self;
		[TGAlertSheet showInput:@"Import Messages"
						message:@"Name a history file in this app's Documents "
								@"folder. Its media files go in the same folder."
					placeholder:@"export.json"
						   text:nil
						 action:@"Next"
						 inView:self.view
					   onSubmit:^(NSString *name){
			[weakSelf beginImportFromPath:name inChat:chatId];
		}];
		return;
	}

	if ([title isEqualToString:@"Direct Messages"]){
		int64_t chatId = self.chatId;
		__weak typeof(self) weakSelf = self;
		[TGAlertSheet showChoices:@[@"Off", @"On, free", @"On, 1 star per message"]
							title:@"Channel Direct Messages"
				  destructiveIndex:-1
						   inView:self.view
						 onChoice:^(NSInteger index){
			BOOL enabled = index > 0;
			NSInteger stars = index > 1 ? 1 : 0;
			[[TGClient shared] setDirectMessagesEnabled:enabled
											  paidStars:stars
												 inChat:chatId
											 completion:^(BOOL ok){
				TGProfileViewController *me = weakSelf;
				if (!me)
					return;
				[TGSnackbar showInView:me.view
								  text:(ok ? @"Direct messages updated"
										   : @"Only the channel's owner changes this")
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

	if ([title isEqualToString:@"Add Members"]){
		TGContactsViewController *contacts = [[TGContactsViewController alloc] init];
		contacts.addingToChatId = self.chatId;
		contacts.hidesBottomBarWhenPushed = YES;
		[self.navigationController pushViewController:contacts animated:YES];
		return;
	}

	if ([title isEqualToString:@"Find Member"]){
		[self showFindMemberSheet];
		return;
	}

	if ([title isEqualToString:@"Upgrade to Supergroup"]){
		[self confirmUpgradeToSupergroup];
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

	if ([title isEqualToString:@"Chat Tools"]){
		TGChatToolsViewController *tools = [[TGChatToolsViewController alloc] init];
		tools.chatId = self.chatId;
		tools.chatTitle = self.name;
		tools.isGroup = YES;
		tools.hidesBottomBarWhenPushed = YES;
		[self.navigationController pushViewController:tools animated:YES];
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

	if ([title isEqualToString:@"Sign Messages"] ||
			[title isEqualToString:@"Join to Send"] ||
			[title isEqualToString:@"All History"]){
		int64_t chatId = self.chatId;
		NSString *chatTitle = self.name;
		BOOL isSign = [title isEqualToString:@"Sign Messages"];
		BOOL isJoin = [title isEqualToString:@"Join to Send"];
		NSString *flagName = isSign ? @"Signed Messages"
				: (isJoin ? @"Join to Send" : @"All History");
		__weak typeof(self) weakSelf = self;
		// What the switch sits on now is asked for, so the sheet names the
		// move rather than a state it has already made.
		[[TGClient shared] supergroupFlagsForChat:chatId
				completion:^(BOOL signMessages, BOOL joinToSend,
							 BOOL allHistory, BOOL ok){
			TGProfileViewController *me = weakSelf;
			if (!me)
				return;
			if (!ok){
				[TGAlertSheet showMessage:@"Only a supergroup or a channel "
										  @"carries this switch."
									title:flagName
								   inView:me.view];
				return;
			}
			NSString *say = nil;
			NSString *action = nil;
			if (isSign){
				say = signMessages
						? @"Members' names stop showing on their messages."
						: @"Every member's post carries their name on it.";
				action = signMessages ? @"Hide Names" : @"Sign Messages";
			} else if (isJoin){
				say = joinToSend
						? @"Members go back to posting without joining this group."
						: @"Members are added to the group before their composer "
						  @"unlocks.";
				action = joinToSend ? @"Turn Off" : @"Turn On";
			} else {
				say = allHistory
						? @"New members start seeing only what was posted after "
						  @"they joined."
						: @"New members see the whole history, back to the first "
						  @"message.";
				action = allHistory ? @"Hide Old History" : @"Show All History";
			}
			[TGAlertSheet showConfirm:say
								title:(chatTitle ?: flagName)
							   action:action
						  destructive:NO
							   inView:weakSelf.view
							onConfirm:^{
				void (^mark)(BOOL) = ^(BOOL done){
					TGProfileViewController *me2 = weakSelf;
					if (!done && me2)
						[TGAlertSheet showMessage:@"Telegram refused that."
											title:flagName
										   inView:me2.view];
				};
				if (isSign)
					[[TGClient shared] setChatSignMessages:chatId
														on:!signMessages
												completion:mark];
				else if (isJoin)
					[[TGClient shared] setChatJoinToSendMessages:chatId
															  on:!joinToSend
													  completion:mark];
				else
					[[TGClient shared] setSupergroupAllHistoryAvailable:chatId
																	 on:!allHistory
															 completion:mark];
			}];
		}];
		return;
	}

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

	if ([title isEqualToString:@"Welcome Messages"]){
		[self showWelcomeMessagesSheet];
		return;
	}

	if ([title isEqualToString:@"Clear by Date"]){
		__weak typeof(self) weakSelf = self;
		[TGAlertSheet showChoices:@[@"Older than a week", @"Older than a month",
									@"Everything older than today"]
							title:@"Clear by Date"
				 destructiveIndex:-1
						   inView:self.view
						 onChoice:^(NSInteger index){
			NSTimeInterval now = [[NSDate date] timeIntervalSince1970];
			NSInteger days = index == 0 ? 7 : (index == 1 ? 30 : 1);
			NSString *say = [NSString stringWithFormat:
					@"Everything sent before that is deleted for everyone, "
					@"if this account may delete it here."];
			[TGAlertSheet showConfirm:say
								title:@"Clear by Date"
							   action:@"Clear"
						  destructive:YES
							   inView:weakSelf.view
							onConfirm:^{
				[[TGClient shared] deleteChatMessagesByDate:weakSelf.chatId
													 minDate:(NSInteger)0
													 maxDate:(NSInteger)(now - days * 86400)
													  revoke:YES];
			}];
		}];
		return;
	}

	if ([title isEqualToString:@"Send as"]){
		[self showSendAsSheet];
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
								fittingSize:CGSizeMake(TGMetricUploadPhotoSide, TGMetricUploadPhotoSide)
									   fill:NO scale:TGMetricScaleFull];
	NSString *path = [NSTemporaryDirectory()
			stringByAppendingPathComponent:@"group-photo.jpg"];
	if (![UIImageJPEGRepresentation(scaled, TGCompressionQualityStandard) writeToFile:path atomically:YES]){
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

#pragma mark - welcome messages, sent-as, moderation

/// One sheet, everything a welcome message family does: add, edit, delete
/// all. Text is what this client composes; a media welcome stays TDLib-side.
- (void)showWelcomeMessagesSheet {
	__weak typeof(self) weakSelf = self;
	int64_t chatId = self.chatId;
	NSString *groupTitle = self.name;
	[[TGClient shared] welcomeMessagesOfChat:chatId completion:^(NSArray *welcomes){
		TGProfileViewController *me = weakSelf;
		if (!me) return;

		NSMutableArray *rows = [NSMutableArray array];
		NSMutableArray *ids = [NSMutableArray array];
		for (NSDictionary *w in welcomes){
			NSString *text = w[@"text"];
			NSString *preview = text.length
					? [text substringToIndex:MIN(30, (NSUInteger)text.length)]
					: @"(not text)";
			[rows addObject:[NSString stringWithFormat:@"Edit — %@", preview]];
			[ids addObject:w[@"id"]];
		}
		[rows addObject:@"Add"];
		if (welcomes.count)
			[rows addObject:@"Delete One..."];
		[rows addObject:@"Delete All"];

		NSMutableArray *choices = rows;
		NSString *say = welcomes.count
				? @"The first one a joiner sees."
				: @"None yet. A new joiner sees the highest one first.";
		NSInteger destructive = (NSInteger)[choices indexOfObject:@"Delete All"];
		NSString *header = (groupTitle ?: @"Welcome Messages");
		[TGAlertSheet showChoices:choices
							title:header
						 message:say
				 destructiveIndex:destructive
						   inView:weakSelf.view
						 onChoice:^(NSInteger index){
			NSString *what = choices[index];
			void (^tellError)(NSString *) = ^(NSString *sayTwo){
				TGProfileViewController *me = weakSelf;
				if (me)
					[TGAlertSheet showMessage:sayTwo
										title:(groupTitle ?: @"Welcome")
									   inView:me.view];
			};

			if ([what isEqualToString:@"Delete All"]){
				[TGAlertSheet showConfirm:@"Every welcome message this group "
										  @"has is removed."
									title:@"Welcome Messages"
								   action:@"Delete All"
							  destructive:YES
								   inView:weakSelf.view
								onConfirm:^{
					[[TGClient shared] clearAllWelcomeMessagesInChat:chatId];
				}];
				return;
			}
			if ([what isEqualToString:@"Delete One..."]){
				NSMutableArray *previews = [NSMutableArray array];
				for (NSUInteger i = 0; i < welcomes.count; i++){
					NSString *text = welcomes[i][@"text"];
					NSString *preview = text.length
							? [text substringToIndex:MIN(30, text.length)]
							: @"(not text)";
					[previews addObject:[NSString stringWithFormat:@"%lu. %@",
							(unsigned long)(i + 1), preview]];
				}
				[TGAlertSheet showChoices:previews
									title:(groupTitle ?: @"Welcome Messages")
								 message:@"Which welcome goes?"
						 destructiveIndex:0
								   inView:weakSelf.view
								 onChoice:^(NSInteger which){
					NSString *wid = [ids[(NSUInteger)which] isKindOfClass:NSString.class]
							? ids[(NSUInteger)which]
							: [ids[(NSUInteger)which] stringValue];
					[[TGClient shared] deleteWelcomeMessage:[wid longLongValue]
													 inChat:chatId];
				}];
				return;
			}
			if ([what isEqualToString:@"Add"]){
				[TGAlertSheet showInput:@"Add Welcome"
									 message:nil
								   placeholder:@"A word to the joiner"
										  text:nil
										action:@"Add"
										inView:weakSelf.view
									  onSubmit:^(NSString *typed){
					if (!typed.length) return;
					[[TGClient shared] addWelcomeMessageToChat:chatId
														  text:typed
													completion:^(BOOL ok){
						if (!ok)
							tellError(@"Telegram refused that. Only an "
									  @"administrator adds one.");
					}];
				}];
				return;
			}
			if (index >= (NSInteger)ids.count)
				return;
			NSString *old = welcomes[index][@"text"];
			// A welcome id answers as a string; both spellings land in one.
			NSString *welcomeId = [ids[index] isKindOfClass:NSString.class]
					? ids[index] : [ids[index] stringValue];
			[TGAlertSheet showInput:@"Edit Welcome"
								 message:nil
							   placeholder:old ?: @"A word to the joiner"
									  text:old
									action:@"Save"
									inView:weakSelf.view
								  onSubmit:^(NSString *typed){
				if (!typed.length) return;
				[[TGClient shared] setWelcomeMessage:[welcomeId longLongValue]
											   inChat:chatId
												 text:typed
										  completion:^(BOOL ok){
					if (!ok)
						tellError(@"Telegram refused that.");
				}];
			}];
		}];
	}];
}

/// The switch Telegram offers channel owners: post under yourself, or as
/// one of the other accounts you own.
- (void)showSendAsSheet {
	__weak typeof(self) weakSelf = self;
	int64_t chatId = self.chatId;
	NSString *chatTitle = self.name;
	[[TGClient shared] availableMessageSendersInChat:chatId completion:^(NSArray *senders){
		TGProfileViewController *me = weakSelf;
		if (!me)
			return;
		if (!senders.count){
			[TGAlertSheet showMessage:@"Only a chat you may post in carries a "
									  @"Send-as switch."
									title:@"Send as"
								   inView:me.view];
			return;
		}
		NSMutableArray *rows = [NSMutableArray array];
		for (NSDictionary *s in senders){
			NSString *who = nil;
			NSString *userId = s[@"user_id"];
			if (userId)
				who = [[TGClient shared] nameForUserId:[userId longLongValue]];
			if (!who.length && s[@"chat_id"])
				who = [[TGClient shared] titleForChat:
						[s[@"chat_id"] longLongValue]];
			NSString *line = who.length ? who : @"chat";
			NSString *current = [s[@"is_current"] boolValue] ? @" — now" : @"";
			[rows addObject:[line stringByAppendingString:current]];
		}
		[TGAlertSheet showChoices:rows
							title:@"Send as"
						 message:@"What you post here posts under that name."
				 destructiveIndex:-1
						   inView:weakSelf.view
						 onChoice:^(NSInteger index){
			NSDictionary *sender = senders[index];
			[[TGClient shared] setMessageSender:sender inChat:chatId
									 completion:^(BOOL ok){
				TGProfileViewController *me = weakSelf;
				if (!ok && me)
					[TGAlertSheet showMessage:@"Telegram refused that."
										title:(chatTitle ?: @"Send as")
									   inView:me.view];
			}];
		}];
	}];
}

/// Reads an export file's opening lines so Telegram can name it, asks the
/// chat's own confirmation sentence, then imports it. Paths are relative to
/// Documents, which is the folder iTunes file sharing exposes.
- (void)beginImportFromPath:(NSString *)name inChat:(int64_t)chatId {
	NSString *trimmed = [name stringByTrimmingCharactersInSet:
			[NSCharacterSet whitespaceAndNewlineCharacterSet]];
	if (!trimmed.length)
		return;
	NSString *path = trimmed;
	if (!path.isAbsolutePath){
		NSString *documents = [NSSearchPathForDirectoriesInDomains(
				NSDocumentDirectory, NSUserDomainMask, YES) firstObject];
		path = [documents stringByAppendingPathComponent:trimmed];
	}
	if (![[NSFileManager defaultManager] fileExistsAtPath:path]){
		[TGAlertSheet showMessage:[NSString stringWithFormat:
				@"No file at %@. Put the export in the app's Documents folder "
				@"first; iTunes file sharing shows it.", path]
							title:@"Import Messages" inView:self.view];
		return;
	}
	NSStringEncoding encoding = NSUTF8StringEncoding;
	NSError *error = nil;
	NSString *contents = [NSString stringWithContentsOfFile:path
			usedEncoding:&encoding error:&error];
	if (!contents)
		contents = [NSString stringWithContentsOfFile:path
				encoding:NSUTF8StringEncoding error:nil];
	if (!contents.length){
		[TGAlertSheet showMessage:@"The file is not text this app can read."
							title:@"Import Messages" inView:self.view];
		return;
	}
	NSArray *lines = [contents componentsSeparatedByString:@"\n"];
	NSUInteger headCount = MIN((NSUInteger)100, lines.count);
	NSString *head = [[lines subarrayWithRange:NSMakeRange(0, headCount)]
			componentsJoinedByString:@"\n"];

	__weak typeof(self) weakSelf = self;
	[[TGClient shared] messageFileTypeForHead:head
								   completion:^(NSDictionary *fileType){
		TGProfileViewController *me = weakSelf;
		if (!me)
			return;
		NSString *kind = fileType[@"kind"] ?: @"unknown";
		NSString *who = fileType[@"title"];
		[[TGClient shared] importConfirmationTextForChat:chatId
											  completion:^(NSString *text){
			TGProfileViewController *again = weakSelf;
			if (!again)
				return;
			NSString *title = [kind isEqualToString:@"private"]
					? [NSString stringWithFormat:@"Import chat with %@",
							who.length ? who : @"them"]
					: ([kind isEqualToString:@"group"]
							? [NSString stringWithFormat:@"Import group %@",
									who.length ? who : @""]
							: @"Import messages");
			NSString *body = text.length ? text
					: @"This file looks like a history export. Importing "
					  @"adds its messages to this chat.";
			[TGAlertSheet showConfirm:body
								title:title
							   action:@"Import"
						  destructive:YES
							   inView:again.view
							onConfirm:^{
				[[TGClient shared] importMessagesFromFile:path
											attachedFiles:@[]
												 intoChat:chatId
											   completion:^(BOOL ok){
					TGProfileViewController *last = weakSelf;
					if (!last)
						return;
					[TGSnackbar showInView:last.view
									  text:(ok ? @"Import started"
											   : @"Telegram refused the import")
								   seconds:2 onCommit:nil];
				}];
			}];
		}];
	}];
}

/// A group's sticker shelf and its custom emoji shelf are two settings on
/// the supergroup. Both are chosen from the packs this account owns: a pack
/// somebody else owns can be installed but not made the group's shelf.
- (void)chooseStickerSetForGroupCustomEmoji:(BOOL)customEmoji {
	int64_t chatId = self.chatId;
	__weak typeof(self) weakSelf = self;
	[[TGClient shared] ownedStickerSetsWithCompletion:^(NSArray *sets){
		TGProfileViewController *me = weakSelf;
		if (!me)
			return;
		NSMutableArray *titles = [NSMutableArray arrayWithObject:@"None"];
		NSMutableArray *ids = [NSMutableArray arrayWithObject:@(0)];
		for (NSDictionary *set in sets){
			NSString *type = set[@"stickerType"] ?: @"";
			BOOL isCustom = [type isEqualToString:@"stickerTypeCustomEmoji"];
			if (customEmoji != isCustom)
				continue;
			int64_t setId = [set[@"id"] longLongValue];
			if (!setId)
				continue;
			[titles addObject:[NSString stringWithFormat:@"%@  ·  %lu stickers",
					set[@"title"] ?: @"Pack",
					(unsigned long)[set[@"count"] unsignedIntegerValue]]];
			[ids addObject:@(setId)];
		}
		NSString *title = customEmoji ? @"Custom Emoji Stickers" : @"Group Stickers";
		if (titles.count == 1){
			[TGAlertSheet showMessage:
					(customEmoji ? @"This account owns no custom emoji packs."
								 : @"This account owns no sticker packs.")
								  title:title inView:me.view];
			return;
		}
		[TGAlertSheet showChoices:titles title:title
					message:(customEmoji
							? @"Used for the group's emoji status and reactions."
							: @"Shown above the composer for everyone here.")
			 destructiveIndex:-1 inView:me.view
					 onChoice:^(NSInteger index){
			int64_t setId = [ids[(NSUInteger)index] longLongValue];
			void (^done)(BOOL) = ^(BOOL ok){
				[TGAlertSheet showMessage:(ok ? @"The group's shelf is updated."
											  : @"Telegram refused the shelf; only "
												@"an administrator can change it.")
									  title:title inView:me.view];
			};
			if (customEmoji)
				[[TGClient shared] setSupergroupCustomEmojiStickerSet:setId
						inChat:chatId completion:done];
			else
				[[TGClient shared] setSupergroupStickerSet:setId
						inChat:chatId completion:done];
		}];
	}];
}

/// A member's dict turned into what a delete call names as its sender.
static NSDictionary *TGSenderFromMember(NSDictionary *member){
	NSString *userId = member[@"user_id"] ?: member[@"id"];
	NSString *chatId = member[@"chat_id"] ?: member[@"sender_chat_id"];
	if (userId)
		return @{@"@type" : @"messageSenderUser", @"user_id" : userId};
	if (chatId)
		return @{@"@type" : @"messageSenderChat", @"chat_id" : chatId};
	return nil;
}

@end
