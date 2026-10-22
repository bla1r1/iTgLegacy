#import "TGChatViewControllerInternal.h"
#import "TGTheme.h"
#import "TGIcons.h"
#import "UIImage+WebP.h"

@implementation TGChatViewController (Input)

- (void)buildInputBar:(CGRect)b {
	CGFloat scale = [UIScreen mainScreen].scale;

	self.inputBar = [[UIView alloc] initWithFrame:
			CGRectMake(0, b.size.height - kInputHeight, b.size.width, kInputHeight)];
	self.inputBar.backgroundColor = [[TGTheme shared] inputBarColour];
	self.inputBar.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleTopMargin;

	UIView *hair = [[UIView alloc] initWithFrame:CGRectMake(0, 0, b.size.width, 1)];
	hair.backgroundColor = [[TGTheme shared] separatorColour];
	hair.autoresizingMask = UIViewAutoresizingFlexibleWidth;
	[self.inputBar addSubview:hair];

	CGFloat sendY = (kInputHeight - kSendSide) / 2;

	UIButton *attach = [UIButton buttonWithType:UIButtonTypeCustom];
	attach.frame = CGRectMake(4, sendY, 34, kSendSide);
	[attach setImage:[TGIcons attach] forState:UIControlStateNormal];
	attach.tintColor = [[TGTheme shared] accentColour];
	[attach addTarget:self action:@selector(attachTapped)
			forControlEvents:UIControlEventTouchUpInside];
	[self.inputBar addSubview:attach];

	self.input = [[UITextField alloc] initWithFrame:
			CGRectMake(40, 7, b.size.width - 120, kInputHeight - 14)];
	self.input.borderStyle = UITextBorderStyleNone;
	self.input.background = nil;
	self.input.backgroundColor = [[TGTheme shared] listBackgroundColour];
	self.input.layer.cornerRadius = (kInputHeight - 14) / 2;
	self.input.layer.borderWidth = 1.0f;
	self.input.layer.borderColor = [[TGTheme shared] separatorColour].CGColor;
	self.input.layer.shouldRasterize = YES;
	self.input.layer.rasterizationScale = scale;
	self.input.leftView = [[UIView alloc] initWithFrame:CGRectMake(0, 0, 10, 1)];
	self.input.leftViewMode = UITextFieldViewModeAlways;
	self.input.placeholder = @"Message";
	self.input.textColor = [[TGTheme shared] primaryTextColour];
	self.input.font = [UIFont systemFontOfSize:15];
	self.input.returnKeyType = UIReturnKeySend;
	self.input.keyboardAppearance = [TGTheme shared].isDark
			? UIKeyboardAppearanceAlert : UIKeyboardAppearanceDefault;
	self.input.delegate = self;
	self.input.autoresizingMask = UIViewAutoresizingFlexibleWidth;
	[self.inputBar addSubview:self.input];

	self.sendButton = [UIButton buttonWithType:UIButtonTypeCustom];
	self.sendButton.frame = CGRectMake(b.size.width - kSendSide - 6, sendY,
									   kSendSide, kSendSide);
	self.sendButton.backgroundColor = [[TGTheme shared] accentColour];
	self.sendButton.layer.cornerRadius = kSendSide / 2;
	self.sendButton.layer.shouldRasterize = YES;
	self.sendButton.layer.rasterizationScale = scale;
	[self.sendButton setImage:[TGIcons send] forState:UIControlStateNormal];
	self.sendButton.tintColor = [UIColor whiteColor];
	self.sendButton.imageEdgeInsets = UIEdgeInsetsZero;
	self.sendButton.autoresizingMask = UIViewAutoresizingFlexibleLeftMargin;
	[self.sendButton addTarget:self action:@selector(sendTapped)
			forControlEvents:UIControlEventTouchUpInside];
	[self.inputBar addSubview:self.sendButton];

	// A sticker button beside the composer, as clients place it.
	self.stickerButton = [UIButton buttonWithType:UIButtonTypeCustom];
	self.stickerButton.frame = CGRectMake(b.size.width - kSendSide - 42, sendY,
										  30, kSendSide);
	[self.stickerButton setImage:[TGIcons sticker] forState:UIControlStateNormal];
	self.stickerButton.tintColor = [[TGTheme shared] secondaryTextColour];
	self.stickerButton.autoresizingMask = UIViewAutoresizingFlexibleLeftMargin;
	[self.stickerButton addTarget:self action:@selector(toggleStickerPanel)
				 forControlEvents:UIControlEventTouchUpInside];
	[self.inputBar addSubview:self.stickerButton];

	// Hold to record, release to send - the gesture every client uses. It sits
	// where Send is and swaps with it depending on whether anything is typed.
	self.micButton = [UIButton buttonWithType:UIButtonTypeCustom];
	self.micButton.frame = self.sendButton.frame;
	[self.micButton setImage:[TGIcons microphone] forState:UIControlStateNormal];
	self.micButton.tintColor = [[TGTheme shared] secondaryTextColour];
	self.micButton.autoresizingMask = UIViewAutoresizingFlexibleLeftMargin;
	[self.micButton addTarget:self action:@selector(recordTouchDown:withEvent:)
			 forControlEvents:UIControlEventTouchDown];
	[self.micButton addTarget:self action:@selector(recordTouchUp:withEvent:)
			 forControlEvents:UIControlEventTouchUpInside | UIControlEventTouchUpOutside];
	[self.micButton addTarget:self action:@selector(recordTouchCancel)
			 forControlEvents:UIControlEventTouchCancel];
	[self.micButton addTarget:self action:@selector(recordDrag:withEvent:)
			 forControlEvents:UIControlEventTouchDragInside | UIControlEventTouchDragOutside];
	[self.inputBar addSubview:self.micButton];

	[self.input addTarget:self action:@selector(inputChanged)
		 forControlEvents:UIControlEventEditingChanged];
	[self inputChanged];

	[self.view addSubview:self.inputBar];
}

#pragma mark - compose banner

/// Back to composing a plain message: no reply, no edit, no banner. Also
/// missing, and reached from the recorder and from the banner's own cancel.
- (void)clearComposeState {
	self.replyToId = 0;
	self.editingId = 0;
	self.composeBanner.hidden = YES;
	[self inputChanged];
}

/// A strip above the composer saying what the next message will be: a reply,
/// an edit, or a recording in progress. Declared and used from three places
/// but never written, so holding the microphone brought the app down.
- (void)showComposeBanner:(NSString *)text {
	if (!self.composeBanner){
		CGRect b = self.view.bounds;
		self.composeBanner = [[UIView alloc] initWithFrame:
				CGRectMake(0, CGRectGetMinY(self.inputBar.frame) - 28, b.size.width, 28)];
		self.composeBanner.backgroundColor = [[TGTheme shared] inputBarColour];
		self.composeBanner.autoresizingMask = UIViewAutoresizingFlexibleWidth |
											  UIViewAutoresizingFlexibleTopMargin;

		UILabel *label = [[UILabel alloc] initWithFrame:
				CGRectMake(10, 4, b.size.width - 50, 20)];
		label.font = [UIFont systemFontOfSize:13];
		label.textColor = [[TGTheme shared] accentColour];
		label.backgroundColor = [UIColor clearColor];
		label.autoresizingMask = UIViewAutoresizingFlexibleWidth;
		[self.composeBanner addSubview:label];

		UIButton *cancel = [UIButton buttonWithType:UIButtonTypeCustom];
		cancel.frame = CGRectMake(b.size.width - 40, 0, 40, 28);
		cancel.autoresizingMask = UIViewAutoresizingFlexibleLeftMargin;
		[cancel setTitle:@"\u00d7" forState:UIControlStateNormal];
		[cancel setTitleColor:[[TGTheme shared] secondaryTextColour]
					 forState:UIControlStateNormal];
		cancel.titleLabel.font = [UIFont systemFontOfSize:22];
		[cancel addTarget:self action:@selector(clearComposeState)
		 forControlEvents:UIControlEventTouchUpInside];
		[self.composeBanner addSubview:cancel];

		[self.view addSubview:self.composeBanner];
	}

	UILabel *label = (UILabel *)[self.composeBanner.subviews firstObject];
	if ([label isKindOfClass:UILabel.class])
		label.text = text;
	self.composeBanner.hidden = NO;
}

#pragma mark - sending

- (void)sendTapped {
	NSString *text = [self.input.text stringByTrimmingCharactersInSet:
			[NSCharacterSet whitespaceAndNewlineCharacterSet]];
	if (!text.length)
		return;

	if (self.editingId != 0)
		[[TGClient shared] editMessage:self.editingId inChat:self.chatId text:text];
	else
		[[TGClient shared] sendText:text toChat:self.chatId
							 thread:self.threadId replyTo:self.replyToId];

	[self clearComposeState];

	// TDLib echoes the message back as an update; refresh shortly after.
	dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(1.0 * NSEC_PER_SEC)),
			dispatch_get_main_queue(), ^{
		[self reload];
	});
}

- (BOOL)textFieldShouldReturn:(UITextField *)textField {
	[self sendTapped];
	return NO;
}

static NSMutableDictionary *sStickerImageCache = nil;

#pragma mark - stickers

- (void)hideStickerPanel {
	if (!self.stickerPanel || self.stickerPanel.hidden)
		return;
	[UIView animateWithDuration:0.2 animations:^{
		CGRect f = self.stickerPanel.frame;
		f.origin.y = CGRectGetMinY(self.inputBar.frame);
		self.stickerPanel.frame = f;
		self.stickerPanel.alpha = 0.0f;
	} completion:^(BOOL finished) {
		self.stickerPanel.hidden = YES;
	}];
}

- (void)toggleStickerPanel {
	if (self.stickerPanel && !self.stickerPanel.hidden) {
		[self hideStickerPanel];
		return;
	}

	BOOL wasKb = [self.input isFirstResponder];
	if (wasKb) {
		[self.input resignFirstResponder];
	}

	CGRect b = self.view.bounds;
	CGFloat height = 96;
	CGFloat panelY = b.size.height - kInputHeight - height;

	if (!self.stickerPanel) {
		UIScrollView *panel = [[UIScrollView alloc] initWithFrame:
				CGRectMake(0, b.size.height - kInputHeight, b.size.width, height)];
		panel.backgroundColor = [[TGTheme shared] inputBarColour];
		panel.autoresizingMask = UIViewAutoresizingFlexibleWidth |
								 UIViewAutoresizingFlexibleTopMargin;
		panel.showsHorizontalScrollIndicator = NO;
		panel.alwaysBounceHorizontal = YES;

		// Fast swipe down to dismiss
		UISwipeGestureRecognizer *swipeDown = [[UISwipeGestureRecognizer alloc]
				initWithTarget:self action:@selector(hideStickerPanel)];
		swipeDown.direction = UISwipeGestureRecognizerDirectionDown;
		[panel addGestureRecognizer:swipeDown];

		// Smooth interactive pan down to dismiss
		UIPanGestureRecognizer *panDown = [[UIPanGestureRecognizer alloc]
				initWithTarget:self action:@selector(handleStickerPan:)];
		panDown.delegate = self;
		[panel addGestureRecognizer:panDown];

		[self.view addSubview:panel];
		self.stickerPanel = panel;

		// Populate emojis instantly!
		[self fillStickerPanel:panel with:nil];

		__weak typeof(self) weakSelf = self;
		[[TGClient shared] recentStickersWithCompletion:^(NSArray *stickers){
			TGChatViewController *me = weakSelf;
			if (!me || me.stickerPanel != panel || !stickers.count)
				return;
			[me appendRecentStickers:stickers toPanel:panel];
		}];
	}

	self.stickerPanel.frame = CGRectMake(0, b.size.height - kInputHeight, b.size.width, height);
	self.stickerPanel.alpha = 0.0f;
	self.stickerPanel.hidden = NO;
	[self.view bringSubviewToFront:self.stickerPanel];

	NSTimeInterval dur = wasKb ? 0.25 : 0.2;
	[UIView animateWithDuration:dur animations:^{
		self.stickerPanel.frame = CGRectMake(0, panelY, b.size.width, height);
		self.stickerPanel.alpha = 1.0f;
	}];
}

- (void)handleStickerPan:(UIPanGestureRecognizer *)pan {
	CGPoint trans = [pan translationInView:self.stickerPanel];
	CGPoint vel = [pan velocityInView:self.stickerPanel];
	CGFloat height = 96;
	CGFloat panelY = self.view.bounds.size.height - kInputHeight - height;

	if (pan.state == UIGestureRecognizerStateChanged) {
		if (trans.y > 0) {
			self.stickerPanel.frame = CGRectMake(0, panelY + trans.y, self.stickerPanel.bounds.size.width, height);
			self.stickerPanel.alpha = MAX(0.0f, 1.0f - (trans.y / height));
		}
	} else if (pan.state == UIGestureRecognizerStateEnded || pan.state == UIGestureRecognizerStateCancelled) {
		if (trans.y > 25.0f || vel.y > 150.0f) {
			[self hideStickerPanel];
		} else {
			[UIView animateWithDuration:0.15 animations:^{
				self.stickerPanel.frame = CGRectMake(0, panelY, self.stickerPanel.bounds.size.width, height);
				self.stickerPanel.alpha = 1.0f;
			}];
		}
	}
}

- (BOOL)gestureRecognizerShouldBegin:(UIGestureRecognizer *)gestureRecognizer {
	if ([gestureRecognizer isKindOfClass:[UIPanGestureRecognizer class]]) {
		UIPanGestureRecognizer *pan = (UIPanGestureRecognizer *)gestureRecognizer;
		if (pan.view == self.stickerPanel) {
			CGPoint vel = [pan velocityInView:self.stickerPanel];
			return (vel.y > 0 && fabs(vel.y) > fabs(vel.x));
		}
	}
	return YES;
}

- (BOOL)gestureRecognizer:(UIGestureRecognizer *)gestureRecognizer shouldRecognizeSimultaneouslyWithGestureRecognizer:(UIGestureRecognizer *)otherGestureRecognizer {
	if (gestureRecognizer.view == self.stickerPanel || otherGestureRecognizer.view == self.stickerPanel) {
		return YES;
	}
	return NO;
}

- (void)fillStickerPanel:(UIScrollView *)panel with:(NSArray *)stickers {
	CGFloat side = 38.0f, gap = 4.0f;
	UIFont *emojiFont = [UIFont systemFontOfSize:24.0f];

	// Top 36 most used emojis in 2 compact rows for instant rendering and 60 FPS scrolling
	NSArray *quickEmojis = @[
		@"😂", @"❤️", @"👍", @"😍", @"🙏", @"🔥", @"😊", @"😭", @"🤣", @"😘",
		@"🤔", @"🥺", @"👏", @"🥳", @"😎", @"🙄", @"💔", @"💯",
		@"✨", @"😡", @"😱", @"😴", @"🤩", @"😅", @"😬", @"🤝", @"✌️", @"👋",
		@"🙈", @"🎉", @"🎂", @"🍻", @"🎁", @"☀️", @"💪", @"🚀"
	];

	NSUInteger cols = 18;
	for (NSUInteger i = 0; i < quickEmojis.count; i++) {
		NSUInteger row = i / cols;
		NSUInteger col = i % cols;
		CGFloat x = 6.0f + col * (side + gap);
		CGFloat y = (row == 0) ? 6.0f : 48.0f;

		UIButton *btn = [UIButton buttonWithType:UIButtonTypeCustom];
		btn.frame = CGRectMake(x, y, side, side);
		btn.tag = 0;
		[btn setTitle:quickEmojis[i] forState:UIControlStateNormal];
		btn.titleLabel.font = emojiFont;
		[btn addTarget:self action:@selector(stickerTapped:)
		 forControlEvents:UIControlEventTouchUpInside];
		[panel addSubview:btn];
	}

	CGFloat totalEmojiWidth = 6.0f + cols * (side + gap) + 6.0f;
	panel.contentSize = CGSizeMake(totalEmojiWidth, panel.bounds.size.height);

	if (stickers.count > 0) {
		[self appendRecentStickers:stickers toPanel:panel];
	}
}

- (void)appendRecentStickers:(NSArray *)stickers toPanel:(UIScrollView *)panel {
	if (!stickers.count) return;
	static dispatch_once_t onceToken;
	dispatch_once(&onceToken, ^{
		sStickerImageCache = [[NSMutableDictionary alloc] init];
	});

	CGFloat x = panel.contentSize.width;
	CGFloat gap = 6.0f;

	// Separator between emojis and recent stickers
	UIView *sep = [[UIView alloc] initWithFrame:CGRectMake(x, 14, 1, 68)];
	sep.backgroundColor = [[TGTheme shared] separatorColour];
	[panel addSubview:sep];
	x += 12.0f;

	NSUInteger stickerLimit = MIN((NSUInteger)6, stickers.count);
	for (NSUInteger i = 0; i < stickerLimit; i++){
		NSDictionary *sticker = stickers[i];
		NSInteger fileId = [sticker[@"fileId"] integerValue];
		UIButton *button = [UIButton buttonWithType:UIButtonTypeCustom];
		button.frame = CGRectMake(x, 12, 72, 72);
		button.tag = fileId;
		[button addTarget:self action:@selector(stickerTapped:)
		 forControlEvents:UIControlEventTouchUpInside];
		[button setTitle:sticker[@"emoji"] forState:UIControlStateNormal];
		button.titleLabel.font = [UIFont systemFontOfSize:28];
		[panel addSubview:button];
		x += 72 + gap;

		UIImage *cached = sStickerImageCache[@(fileId)];
		if (cached) {
			[button setTitle:@"" forState:UIControlStateNormal];
			[button setImage:cached forState:UIControlStateNormal];
			button.imageView.contentMode = UIViewContentModeScaleAspectFit;
			continue;
		}

		NSInteger downloadId = [sticker[@"thumbId"] integerValue] ?: fileId;
		if (downloadId <= 0) continue;

		__weak UIButton *weakButton = button;
		[[TGClient shared] downloadFile:downloadId completion:^(NSString *path){
			if (!path.length) return;
			dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_LOW, 0), ^{
				UIImage *image = [UIImage convertFromWebP:path compressedData:nil error:nil];
				if (!image) return;
				dispatch_async(dispatch_get_main_queue(), ^{
					sStickerImageCache[@(fileId)] = image;
					UIButton *btn = weakButton;
					if (!btn) return;
					[btn setTitle:@"" forState:UIControlStateNormal];
					[btn setImage:image forState:UIControlStateNormal];
					btn.imageView.contentMode = UIViewContentModeScaleAspectFit;
				});
			});
		}];
	}
	panel.contentSize = CGSizeMake(x + 10, panel.bounds.size.height);
}

- (void)stickerTapped:(UIButton *)button {
	if (button.tag != 0) {
		[[TGClient shared] sendStickerWithFileId:button.tag
										  toChat:self.chatId
										  thread:self.threadId];
		[self toggleStickerPanel];
	} else if (button.currentTitle.length) {
		NSString *emoji = button.currentTitle;
		NSString *curr = self.input.text ?: @"";
		self.input.text = [curr stringByAppendingString:emoji];
		[self inputChanged];
	}
}

#pragma mark - attachments

static const NSInteger kAttachSheetTag  = 41;
static const NSInteger kMessageSheetTag = 42;

- (void)attachTapped {
	UIActionSheet *sheet = [[UIActionSheet alloc] initWithTitle:nil
													  delegate:self
											 cancelButtonTitle:nil
										destructiveButtonTitle:nil
											 otherButtonTitles:@"Photo or Video",
														   @"Location",
														   @"Contact", nil];
	sheet.cancelButtonIndex = [sheet addButtonWithTitle:@"Cancel"];
	sheet.tag = kAttachSheetTag;
	[sheet showInView:self.view];
}

- (void)actionSheet:(UIActionSheet *)sheet clickedButtonAtIndex:(NSInteger)index {
	if (index == sheet.cancelButtonIndex)
		return;

	if (sheet.tag == 0xDE1E) {
		NSArray *ids = self.pendingDeleteMessageIds;
		self.pendingDeleteMessageIds = nil;
		if (index == sheet.cancelButtonIndex || !ids.count)
			return;

		BOOL isSaved = (self.chatId == [[TGClient shared] savedMessagesChatId]);
		if (isSaved) {
			if (index == 0) {
				[self executeDeleteMessages:ids revoke:YES];
			}
		} else {
			if (index == 0) {
				// Delete for both / Delete for everyone
				[self executeDeleteMessages:ids revoke:YES];
			} else if (index == 1) {
				// Delete for me
				[self executeDeleteMessages:ids revoke:NO];
			}
		}
		return;
	}

	if (sheet.tag == kMessageSheetTag){
		[self runMessageAction:[sheet buttonTitleAtIndex:index]];
		return;
	}
	if (sheet.tag == 0xC047){
		NSDictionary *m = self.contactActionMessage;
		NSDictionary *contact = [m[@"contact"] isKindOfClass:NSDictionary.class] ? m[@"contact"] : nil;
		NSString *phone = contact[@"phoneNumber"] ?: @"";
		if (!phone.length) {
			NSArray *parts = [m[@"text"] componentsSeparatedByString:@"\n"];
			if (parts.count > 1) phone = parts[1];
		}
		if (index == 0) {
			NSString *clean = [[phone componentsSeparatedByCharactersInSet:[[NSCharacterSet characterSetWithCharactersInString:@"+0123456789"] invertedSet]] componentsJoinedByString:@""];
			if (clean.length)
				[[UIApplication sharedApplication] openURL:[NSURL URLWithString:[NSString stringWithFormat:@"tel:%@", clean]]];
		} else if (index == 1) {
			[self presentAddContactForMessage:m];
		} else if (index == 2) {
			[UIPasteboard generalPasteboard].string = phone ?: @"";
			[TGSnackbar showInView:self.view text:@"Phone number copied" seconds:2 onCommit:^{}];
		}
		return;
	}
	if (sheet.tag != kAttachSheetTag)
		return;
	if (index == 0)      [self pickMedia];
	else if (index == 1) [self sendCurrentLocation];
	else                 [self pickContact];
}

#pragma mark - keyboard

- (void)keyboardWillShow:(NSNotification *)note {
	if (self.stickerPanel) {
		self.stickerPanel.hidden = YES;
	}
	CGRect kb = [[note.userInfo objectForKey:UIKeyboardFrameEndUserInfoKey] CGRectValue];
	[self shiftForKeyboardHeight:kb.size.height];
}

- (void)keyboardWillHide:(NSNotification *)note {
	[self shiftForKeyboardHeight:0];
}

- (void)shiftForKeyboardHeight:(CGFloat)height {
	CGRect b = self.view.bounds;
	[UIView animateWithDuration:0.25 animations:^{
		self.inputBar.frame = CGRectMake(0, b.size.height - kInputHeight - height,
				b.size.width, kInputHeight);
		self.table.frame = CGRectMake(0, 0, b.size.width,
				b.size.height - kInputHeight - height);
	} completion:^(BOOL done){
		[self scrollToBottomAnimated:NO];
	}];
}

@end
