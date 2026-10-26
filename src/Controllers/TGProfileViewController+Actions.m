#import "TGProfileViewControllerInternal.h"
#import "TGCapabilities.h"
#import "TGStatusText.h"
#import "TGStyle.h"
#import "TGAlertSheet.h"

@implementation TGProfileViewController (Actions)

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

/// The "more" menu from the current client, minus what this app cannot do:
/// no secret chats, no gifts.
- (void)showMoreMenuFrom:(UIView *)tile {
	NSMutableArray *items = [NSMutableArray array];
	if (self.userId)
		[items addObject:@{@"title" : @"Share contact", @"icon" : @"forward"}];
	[items addObject:@{@"title" : @"Auto-delete messages", @"icon" : @"delete"}];
	[items addObject:@{@"title" : @"Clear history", @"icon" : @"delete"}];
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

- (void)runMoreAction:(NSString *)title {
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

@end
