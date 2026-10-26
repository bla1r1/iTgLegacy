#import "TGChatViewControllerInternal.h"
#import "TGForwardPicker.h"
#import "TGStyle.h"
#import "TGAlertSheet.h"

@implementation TGChatViewController (Selection)

#pragma mark - multi-select edit mode

- (void)enterEditMode {
	if (self.isEditingMessages) return;
	self.isEditingMessages = YES;
	if (!self.selectedMessageIds) {
		self.selectedMessageIds = [NSMutableSet set];
	} else {
		[self.selectedMessageIds removeAllObjects];
	}

	[self.input resignFirstResponder];
	self.inputBar.hidden = YES;

	if (!self.editToolbar) {
		CGRect b = self.view.bounds;
		self.editToolbar = [[UIView alloc] initWithFrame:CGRectMake(0, b.size.height - kInputHeight, b.size.width, kInputHeight)];
		self.editToolbar.backgroundColor = [[TGTheme shared] inputBarColour];
		self.editToolbar.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleTopMargin;

		UIView *hair = [[UIView alloc] initWithFrame:CGRectMake(0, 0, b.size.width, 0.5f)];
		hair.backgroundColor = [[TGTheme shared] separatorColour];
		hair.autoresizingMask = UIViewAutoresizingFlexibleWidth;
		[self.editToolbar addSubview:hair];

		self.editDeleteButton = [UIButton buttonWithType:UIButtonTypeCustom];
		self.editDeleteButton.frame = CGRectMake(14, 6, 140, 36);
		self.editDeleteButton.contentHorizontalAlignment = UIControlContentHorizontalAlignmentLeft;
		self.editDeleteButton.titleLabel.font = TGFontRow();
		[self.editDeleteButton setTitleColor:[[TGTheme shared] destructiveColour] forState:UIControlStateNormal];
		[self.editDeleteButton setTitle:@"Delete" forState:UIControlStateNormal];
		[self.editDeleteButton addTarget:self action:@selector(deleteSelectedMessages) forControlEvents:UIControlEventTouchUpInside];
		[self.editToolbar addSubview:self.editDeleteButton];

		self.editForwardButton = [UIButton buttonWithType:UIButtonTypeCustom];
		self.editForwardButton.frame = CGRectMake(b.size.width - 154, 6, 140, 36);
		self.editForwardButton.contentHorizontalAlignment = UIControlContentHorizontalAlignmentRight;
		self.editForwardButton.titleLabel.font = TGFontRowStrong();
		[self.editForwardButton setTitleColor:[[TGTheme shared] accentColour] forState:UIControlStateNormal];
		[self.editForwardButton setTitle:@"Forward" forState:UIControlStateNormal];
		[self.editForwardButton addTarget:self action:@selector(forwardSelectedMessages) forControlEvents:UIControlEventTouchUpInside];
		[self.editToolbar addSubview:self.editForwardButton];

		[self.view addSubview:self.editToolbar];
	}
	self.editToolbar.hidden = NO;
	[self.view bringSubviewToFront:self.editToolbar];

	self.savedTitleView = self.navigationItem.titleView;
	self.savedRightBarButtonItem = self.navigationItem.rightBarButtonItem;

	self.navigationItem.titleView = nil;
	self.navigationItem.rightBarButtonItem = nil;
	self.navigationItem.leftBarButtonItem = [[UIBarButtonItem alloc] initWithTitle:@"Cancel"
																			 style:UIBarButtonItemStylePlain
																			target:self
																			action:@selector(exitEditMode)];

	[self updateEditToolbar];
	[self.table reloadData];
}

- (void)exitEditMode {
	if (!self.isEditingMessages) return;
	self.isEditingMessages = NO;
	[self.selectedMessageIds removeAllObjects];

	self.editToolbar.hidden = YES;
	self.inputBar.hidden = NO;

	self.navigationItem.leftBarButtonItem = nil;
	self.navigationItem.titleView = self.savedTitleView;
	self.navigationItem.rightBarButtonItem = self.savedRightBarButtonItem;
	self.title = nil;

	[self.table reloadData];
}

- (void)updateEditToolbar {
	NSUInteger count = self.selectedMessageIds.count;
	BOOL enabled = (count > 0);

	self.editDeleteButton.enabled = enabled;
	self.editDeleteButton.alpha = enabled ? 1.0f : 0.4f;
	if (count > 0) {
		[self.editDeleteButton setTitle:[NSString stringWithFormat:@"Delete (%lu)", (unsigned long)count] forState:UIControlStateNormal];
	} else {
		[self.editDeleteButton setTitle:@"Delete" forState:UIControlStateNormal];
	}

	self.editForwardButton.enabled = enabled;
	self.editForwardButton.alpha = enabled ? 1.0f : 0.4f;
	if (count > 0) {
		[self.editForwardButton setTitle:[NSString stringWithFormat:@"Forward (%lu)", (unsigned long)count] forState:UIControlStateNormal];
	} else {
		[self.editForwardButton setTitle:@"Forward" forState:UIControlStateNormal];
	}

	if (count == 0) {
		self.title = @"Select Messages";
	} else if (count == 1) {
		self.title = @"1 selected";
	} else {
		self.title = [NSString stringWithFormat:@"%lu selected", (unsigned long)count];
	}
}

- (void)toggleMessageSelection:(int64_t)messageId {
	if (!messageId) return;
	NSNumber *num = @(messageId);
	if ([self.selectedMessageIds containsObject:num]) {
		[self.selectedMessageIds removeObject:num];
	} else {
		[self.selectedMessageIds addObject:num];
	}
	[self updateEditToolbar];
	[self.table reloadData];
}

- (void)selectMessageAtIndex:(NSInteger)index {
	if (index < 0 || index >= (NSInteger)self.messages.count) return;
	if (!self.isEditingMessages) {
		[self enterEditMode];
	}
	NSDictionary *m = self.messages[index];
	if ([m[@"service"] boolValue])
		return;
	int64_t msgId = [m[@"id"] longLongValue];
	if (msgId) {
		[self toggleMessageSelection:msgId];
	}
}

- (void)promptDeleteMessages:(NSArray *)ids {
	if (!ids.count) return;

	// Saved Messages has nobody else to revoke from, so there is one choice
	// there and two everywhere else. Either way the first one revokes.
	BOOL isSaved = (self.chatId == [[TGClient shared] savedMessagesChatId]);
	NSString *forBoth = self.isGroup
			? @"Delete for Everyone"
			: [NSString stringWithFormat:@"Delete for me and %@",
					self.chatTitle.length ? self.chatTitle : @"them"];
	NSArray *choices = isSaved ? @[@"Delete"] : @[forBoth, @"Delete for Me"];

	__weak typeof(self) weakSelf = self;
	[TGAlertSheet showChoices:choices
						title:nil
			 destructiveIndex:0
					   inView:self.view
					 onChoice:^(NSInteger index){
		[weakSelf executeDeleteMessages:ids revoke:(index == 0)];
	}];
}

- (void)deleteSelectedMessages {
	if (!self.selectedMessageIds.count) return;
	[self promptDeleteMessages:[self.selectedMessageIds allObjects]];
}

- (void)executeDeleteMessages:(NSArray *)ids revoke:(BOOL)revoke {
	if (!ids.count) return;
	NSUInteger count = ids.count;
	int64_t chatId = self.chatId;
	NSSet *idSet = [NSSet setWithArray:ids];

	NSMutableArray *without = [NSMutableArray arrayWithCapacity:self.messages.count];
	for (NSDictionary *m in self.messages) {
		if (![idSet containsObject:m[@"id"]]) {
			[without addObject:m];
		}
	}
	self.messages = without;

	if (self.isEditingMessages) {
		[self exitEditMode];
	} else {
		[self.table reloadData];
	}

	[[TGClient shared] deleteMessages:ids inChat:chatId revoke:revoke];

	NSString *text = (count == 1) ? @"Message deleted" : [NSString stringWithFormat:@"%lu messages deleted", (unsigned long)count];
	[TGSnackbar showInView:self.view text:text seconds:3 onCommit:^{}];

	__weak typeof(self) weakSelf = self;
	dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(4.0 * NSEC_PER_SEC)),
			dispatch_get_main_queue(), ^{ [weakSelf reload]; });
}

- (void)forwardSelectedMessages {
	if (!self.selectedMessageIds.count) return;
	NSArray *ids = [self.selectedMessageIds allObjects];
	int64_t chatId = self.chatId;

	TGForwardPicker *picker = [[TGForwardPicker alloc] init];
	__weak typeof(self) weakSelf = self;
	picker.onPicked = ^(int64_t targetChatId){
		[[TGClient shared] forwardMessages:ids
								  fromChat:chatId
									toChat:targetChatId];
		[weakSelf exitEditMode];
		[TGSnackbar showInView:weakSelf.view
						  text:[NSString stringWithFormat:@"%lu forwarded", (unsigned long)ids.count]
					   seconds:3
					  onCommit:^{}];
	};
	[self.navigationController pushViewController:picker animated:YES];
}

- (TGBubbleCell *)finalizeCell:(TGBubbleCell *)cell message:(NSDictionary *)m layout:(TGMessageLayout *)layout isMine:(BOOL)mine {
	if (!self.isEditingMessages || layout.isService) {
		cell.checkbox.hidden = YES;
		cell.bubble.userInteractionEnabled = YES;
		return cell;
	}

	cell.checkbox.hidden = NO;
	cell.bubble.userInteractionEnabled = NO;

	int64_t msgId = [m[@"id"] longLongValue];
	BOOL isSelected = [self.selectedMessageIds containsObject:@(msgId)];
	cell.checkbox.image = [TGIcons selectionCheckboxSelected:isSelected];

	if (!mine) {
		CGRect bf = cell.bubble.frame;
		bf.origin.x += 34.0f;
		cell.bubble.frame = bf;

		if (!cell.senderAvatar.hidden) {
			CGRect af = cell.senderAvatar.frame;
			af.origin.x += 34.0f;
			cell.senderAvatar.frame = af;
		}
		if (!cell.sender.hidden && cell.sender.superview != cell.bubble) {
			CGRect sf = cell.sender.frame;
			sf.origin.x += 34.0f;
			cell.sender.frame = sf;
		}
	}

	CGFloat cy = CGRectGetMidY(cell.bubble.frame);
	cell.checkbox.frame = CGRectMake(10, cy - 11, 22, 22);
	return cell;
}

@end
