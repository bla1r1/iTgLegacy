#import "TGChatViewControllerInternal.h"
#import "TGTheme.h"
#import "TGIcons.h"
#import "UIImage+WebP.h"
#import "TGAttachSheet.h"

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
	[self layoutChrome];
}

/// A strip above the composer saying what the next message will be: a reply,
/// an edit, or a recording in progress. Declared and used from three places
/// but never written, so holding the microphone brought the app down.
- (void)showComposeBanner:(NSString *)text {
	[self showComposeBanner:text subtitle:nil];
}

static const NSInteger kBannerTitleTag    = 71;
static const NSInteger kBannerSubtitleTag = 72;

/// Their layout: an accent stripe, who is being answered on the first line and
/// what they said on the second. `subtitle` nil keeps the one-line form the
/// recorder and the editor use.
- (void)showComposeBanner:(NSString *)text subtitle:(NSString *)subtitle {
	CGFloat width = self.view.bounds.size.width;
	if (!self.composeBanner){
		self.composeBanner = [[UIView alloc] initWithFrame:
				CGRectMake(0, CGRectGetMinY(self.inputBar.frame) - kComposeBannerHeight,
						   width, kComposeBannerHeight)];
		self.composeBanner.backgroundColor = [[TGTheme shared] inputBarColour];
		self.composeBanner.autoresizingMask = UIViewAutoresizingFlexibleWidth |
											  UIViewAutoresizingFlexibleTopMargin;

		UIView *stripe = [[UIView alloc] initWithFrame:CGRectMake(12, 7, 2, kComposeBannerHeight - 14)];
		stripe.backgroundColor = [[TGTheme shared] accentColour];
		[self.composeBanner addSubview:stripe];

		UILabel *title = [[UILabel alloc] initWithFrame:
				CGRectMake(22, 5, width - 66, 17)];
		title.tag = kBannerTitleTag;
		title.font = [UIFont boldSystemFontOfSize:13];
		title.textColor = [[TGTheme shared] accentColour];
		title.backgroundColor = [UIColor clearColor];
		title.autoresizingMask = UIViewAutoresizingFlexibleWidth;
		[self.composeBanner addSubview:title];

		UILabel *preview = [[UILabel alloc] initWithFrame:
				CGRectMake(22, 22, width - 66, 17)];
		preview.tag = kBannerSubtitleTag;
		preview.font = [UIFont systemFontOfSize:13];
		preview.textColor = [[TGTheme shared] secondaryTextColour];
		preview.backgroundColor = [UIColor clearColor];
		preview.autoresizingMask = UIViewAutoresizingFlexibleWidth;
		[self.composeBanner addSubview:preview];

		UIButton *cancel = [UIButton buttonWithType:UIButtonTypeCustom];
		cancel.frame = CGRectMake(width - 44, 0, 44, kComposeBannerHeight);
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

	UILabel *title   = (UILabel *)[self.composeBanner viewWithTag:kBannerTitleTag];
	UILabel *preview = (UILabel *)[self.composeBanner viewWithTag:kBannerSubtitleTag];
	title.text   = text;
	preview.text = subtitle ?: @"";
	// One line centres itself; two share the strip.
	CGFloat half = kComposeBannerHeight / 2;
	title.frame = CGRectMake(22, subtitle.length ? 5 : half - 9,
							 self.composeBanner.bounds.size.width - 66, 17);

	self.composeBanner.hidden = NO;
	[self layoutChrome];
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

	// Before clearComposeState, so inputChanged sees an empty field and puts
	// the microphone back in the send button's place.
	self.input.text = @"";
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

#pragma mark - emoji, stickers, GIFs

- (BOOL)stickerPanelShown {
	return self.stickerPanel && !self.stickerPanel.hidden;
}

- (void)hideStickerPanel {
	if (![self stickerPanelShown])
		return;
	CGRect b = self.view.bounds;
	[UIView animateWithDuration:0.2 animations:^{
		CGRect f = self.stickerPanel.frame;
		f.origin.y = b.size.height;
		self.stickerPanel.frame = f;
	} completion:^(BOOL finished) {
		self.stickerPanel.hidden = YES;
	}];
	// The keyboard may be on its way up in place of the panel; it moves the
	// bar itself then.
	if (![self.input isFirstResponder])
		[self shiftForKeyboardHeight:0];
}

/// The panel takes the keyboard's place - same height, same spot - and the
/// chat moves up for it the way it does for the keyboard.
- (void)toggleStickerPanel {
	if ([self stickerPanelShown]){
		// Back to the keyboard; its arrival puts the panel away.
		[self.input becomeFirstResponder];
		return;
	}

	CGRect b = self.view.bounds;
	CGFloat height = [TGEmojiPanel preferredHeight];
	if (!self.stickerPanel){
		TGEmojiPanel *panel = [[TGEmojiPanel alloc] initWithFrame:
				CGRectMake(0, b.size.height, b.size.width, height)];
		panel.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleTopMargin;
		panel.delegate = self;
		panel.chatId = self.chatId;
		[self.view addSubview:panel];
		self.stickerPanel = panel;
	}

	if ([self.input isFirstResponder])
		[self.input resignFirstResponder];

	self.stickerPanel.frame = CGRectMake(0, b.size.height, b.size.width, height);
	self.stickerPanel.hidden = NO;
	[self.view bringSubviewToFront:self.stickerPanel];
	[UIView animateWithDuration:0.25 animations:^{
		self.stickerPanel.frame = CGRectMake(0, b.size.height - height, b.size.width, height);
	}];
	[self shiftForKeyboardHeight:height];
}

/// itglegacy://stickers/<emoji|stickers|gifs> - open the panel on a given tab,
/// which is the only way a URL can reach a tab a finger would tap.
- (void)openStickerPanelTab:(NSString *)name {
	if (![self stickerPanelShown])
		[self toggleStickerPanel];
	TGEmojiPanelTab tab = TGEmojiPanelTabEmoji;
	if ([name isEqualToString:@"stickers"])
		tab = TGEmojiPanelTabStickers;
	else if ([name isEqualToString:@"gifs"])
		tab = TGEmojiPanelTabGIFs;
	[self.stickerPanel selectTab:tab];
}

- (void)emojiPanel:(TGEmojiPanel *)panel didPickEmoji:(NSString *)emoji {
	self.input.text = [(self.input.text ?: @"") stringByAppendingString:emoji];
	[self inputChanged];
}

- (void)emojiPanelDidBackspace:(TGEmojiPanel *)panel {
	NSString *text = self.input.text ?: @"";
	if (!text.length)
		return;
	// One emoji is several UTF-16 units, and a flag is two emoji-sized ones;
	// delete what the eye sees as one character.
	NSRange last = [text rangeOfComposedCharacterSequenceAtIndex:text.length - 1];
	self.input.text = [text substringToIndex:last.location];
	[self inputChanged];
}

- (void)emojiPanel:(TGEmojiPanel *)panel didPickSticker:(NSDictionary *)sticker {
	NSInteger fileId = [sticker[@"fileId"] integerValue];
	if (fileId <= 0)
		return;
	[[TGClient shared] sendStickerWithFileId:fileId toChat:self.chatId thread:self.threadId];
}

- (void)emojiPanel:(TGEmojiPanel *)panel didPickAnimation:(NSDictionary *)animation {
	[[TGClient shared] sendAnimation:animation toChat:self.chatId thread:self.threadId];
}

#pragma mark - attachments

static const NSInteger kAttachSheetTag  = 41;
static const NSInteger kMessageSheetTag = 42;

- (void)attachTapped {
	[self.input resignFirstResponder];
	[self hideStickerPanel];
	UIView *host = self.navigationController.view ?: self.view;
	TGAttachSheet *sheet = [TGAttachSheet showInView:host];
	__weak typeof(self) weakSelf = self;
	sheet.onPhoto = ^(UIImage *image){
		[weakSelf sendImage:image];
	};
	sheet.onChoice = ^(TGAttachChoice choice){
		switch (choice){
			case TGAttachChoiceGallery:  [weakSelf pickMedia]; break;
			case TGAttachChoiceLocation: [weakSelf sendCurrentLocation]; break;
			case TGAttachChoiceContact:  [weakSelf pickContact]; break;
		}
	};
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
	if ([self stickerPanelShown])
		[self hideStickerPanel];
	CGRect kb = [[note.userInfo objectForKey:UIKeyboardFrameEndUserInfoKey] CGRectValue];
	[self shiftForKeyboardHeight:kb.size.height];
}

- (void)keyboardWillHide:(NSNotification *)note {
	// Going down because the panel is coming up: the panel moves the bar.
	if ([self stickerPanelShown])
		return;
	[self shiftForKeyboardHeight:0];
}

- (void)shiftForKeyboardHeight:(CGFloat)height {
	CGRect b = self.view.bounds;
	[UIView animateWithDuration:0.25 animations:^{
		self.inputBar.frame = CGRectMake(0, b.size.height - kInputHeight - height,
				b.size.width, kInputHeight);
		self.table.frame = CGRectMake(0, 0, b.size.width,
				b.size.height - kInputHeight - height);
		[self layoutChrome];
	} completion:^(BOOL done){
		[self scrollToBottomAnimated:NO];
	}];
}

@end
