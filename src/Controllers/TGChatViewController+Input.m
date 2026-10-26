#import "TGChatViewControllerInternal.h"
#import "TGTheme.h"
#import "TGIcons.h"
#import "UIImage+WebP.h"
#import "TGAttachSheet.h"
#import "TGAlertSheet.h"
#import "TGSheet.h"
#import "TGScheduledViewController.h"
#import "TGStyle.h"

@implementation TGChatViewController (Input)

- (void)buildInputBar:(CGRect)b {
	CGFloat scale = [UIScreen mainScreen].scale;

	self.inputBar = [[UIView alloc] initWithFrame:
			CGRectMake(0, b.size.height - kInputHeight, b.size.width, kInputHeight)];
	self.inputBar.backgroundColor = [[TGTheme shared] inputBarColour];
	self.inputBar.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleTopMargin;

	UIView *hair = [[UIView alloc] initWithFrame:CGRectMake(0, 0, b.size.width,
			TGMetricBorderWidth)];
	hair.backgroundColor = [[TGTheme shared] separatorColour];
	hair.autoresizingMask = UIViewAutoresizingFlexibleWidth;
	[self.inputBar addSubview:hair];

	CGFloat sendY = TGCenteredOrigin(kInputHeight, kSendSide);

	UIButton *attach = [UIButton buttonWithType:UIButtonTypeCustom];
	attach.frame = CGRectMake(kComposerInset, sendY, kAttachWidth, kSendSide);
	[attach setImage:[TGIcons attach] forState:UIControlStateNormal];
	attach.tintColor = [[TGTheme shared] accentColour];
	[attach addTarget:self action:@selector(attachTapped)
			forControlEvents:UIControlEventTouchUpInside];
	[self.inputBar addSubview:attach];

	self.input = [[UITextField alloc] initWithFrame:
			CGRectMake(kFieldLeft, kFieldInsetV, b.size.width - kFieldRoom,
					kInputHeight - TGDoubled(kFieldInsetV))];
	self.input.borderStyle = UITextBorderStyleNone;
	self.input.background = nil;
	self.input.backgroundColor = [[TGTheme shared] listBackgroundColour];
	self.input.layer.cornerRadius = TGHalf(kInputHeight - TGMetricPadLarge);
	self.input.layer.borderWidth = TGMetricBorderWidth;
	self.input.layer.borderColor = [[TGTheme shared] separatorColour].CGColor;
	self.input.layer.shouldRasterize = YES;
	self.input.layer.rasterizationScale = scale;
	self.input.leftView = [[UIView alloc] initWithFrame:CGRectMake(0, 0, kFieldLeftPad,
			TGMetricBorderWidth)];
	self.input.leftViewMode = UITextFieldViewModeAlways;
	self.input.placeholder = @"Message";
	self.input.textColor = [[TGTheme shared] primaryTextColour];
	self.input.font = TGFontBody();
	self.input.returnKeyType = UIReturnKeySend;
	self.input.keyboardAppearance = [TGTheme shared].isDark
			? UIKeyboardAppearanceAlert : UIKeyboardAppearanceDefault;
	self.input.delegate = self;
	self.input.autoresizingMask = UIViewAutoresizingFlexibleWidth;
	[self.inputBar addSubview:self.input];

	self.sendButton = [UIButton buttonWithType:UIButtonTypeCustom];
	self.sendButton.frame = CGRectMake(b.size.width - kSendSide - kSendInset, sendY,
									   kSendSide, kSendSide);
	self.sendButton.backgroundColor = [[TGTheme shared] accentColour];
	self.sendButton.layer.cornerRadius = TGHalf(kSendSide);
	self.sendButton.layer.shouldRasterize = YES;
	self.sendButton.layer.rasterizationScale = scale;
	[self.sendButton setImage:[TGIcons send] forState:UIControlStateNormal];
	self.sendButton.tintColor = [UIColor whiteColor];
	self.sendButton.imageEdgeInsets = UIEdgeInsetsZero;
	self.sendButton.autoresizingMask = UIViewAutoresizingFlexibleLeftMargin;
	[self.sendButton addTarget:self action:@selector(sendTapped)
			forControlEvents:UIControlEventTouchUpInside];
	// The tap sends; the hold is where sending waits: a date, the other
	// side's next appearance, or the queue already scheduled.
	UILongPressGestureRecognizer *sendHold = [[UILongPressGestureRecognizer alloc]
			initWithTarget:self action:@selector(sendHeld:)];
	sendHold.minimumPressDuration = 0.5;
	[self.sendButton addGestureRecognizer:sendHold];
	[self.inputBar addSubview:self.sendButton];

	// A sticker button beside the composer, as clients place it.
	self.stickerButton = [UIButton buttonWithType:UIButtonTypeCustom];
	self.stickerButton.frame = CGRectMake(b.size.width - kSendSide - kStickerInset, sendY,
										  kStickerWidth, kSendSide);
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

/// The first thing in `text` that could be a link. Not a validator - TDLib
/// decides what has a preview - just enough of a trigger to stop asking on
/// every keystroke of an ordinary sentence.
static NSString *TGFirstLinkIn(NSString *text) {
	for (NSString *word in [text componentsSeparatedByCharactersInSet:
			[NSCharacterSet whitespaceAndNewlineCharacterSet]]){
		if (word.length < 4)
			continue;
		if ([word rangeOfString:@"://"].location != NSNotFound)
			return word;
		// A bare domain needs a dot with something either side of it.
		NSRange dot = [word rangeOfString:@"."];
		if (dot.location != NSNotFound && dot.location > 0 &&
			dot.location + 1 < word.length &&
			[word rangeOfString:@"@"].location == NSNotFound)
			return word;
	}
	return nil;
}

/// What their composer shows once a link is typed: the site and the title
/// Telegram found, so the card that will be attached is not a surprise.
/// Nothing is asked until the typing stops, and never while the banner is
/// already carrying a reply or an edit.
- (void)refreshLinkPreview {
	if (self.replyToId != 0 || self.editingId != 0)
		return;

	NSString *link = TGFirstLinkIn(self.input.text ?: @"");
	if (!link.length){
		if (self.previewedLink.length){
			self.previewedLink = nil;
			self.composeBanner.hidden = YES;
			[self layoutChrome];
		}
		return;
	}
	if ([link isEqualToString:self.previewedLink])
		return;          // already asked about this one
	self.previewedLink = link;

	__weak typeof(self) weakSelf = self;
	[[TGClient shared] linkPreviewForText:self.input.text
							   completion:^(NSDictionary *preview){
		TGChatViewController *me = weakSelf;
		if (!me || ![TGFirstLinkIn(me.input.text ?: @"") isEqualToString:link])
			return;      // the text moved on while the answer was in flight
		if (!preview){
			me.composeBanner.hidden = YES;
			[me layoutChrome];
			return;
		}
		NSString *title = [preview[@"title"] length] ? preview[@"title"]
				: ([preview[@"site"] length] ? preview[@"site"] : link);
		NSString *detail = [preview[@"description"] length]
				? preview[@"description"] : preview[@"url"];
		[me showComposeBanner:title subtitle:detail];
	}];
}

/// "typing..." on the other side. TDLib lets one of these stand for a few
/// seconds, so one per four is enough to keep it up while typing goes on -
/// and sending one per keystroke on this radio would be its own problem.
- (void)reportTyping {
	if (!self.input.text.length){
		self.lastTypingReport = 0;
		return;
	}
	NSTimeInterval now = [NSDate timeIntervalSinceReferenceDate];
	if (now - self.lastTypingReport < 4.0)
		return;
	self.lastTypingReport = now;
	[[TGClient shared] sendTypingToChat:self.chatId thread:self.threadId];
}

#pragma mark - compose banner

/// Back to composing a plain message: no reply, no edit, no banner. Also
/// missing, and reached from the recorder and from the banner's own cancel.
- (void)clearComposeState {
	self.replyToId = 0;
	self.editingId = 0;
	self.editingIsCaption = NO;
	self.previewedLink = nil;
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

		UIView *stripe = [[UIView alloc] initWithFrame:CGRectMake(kBannerStripeX,
				kBannerStripeTop, kQuoteBarWidth,
				kComposeBannerHeight - TGDoubled(kBannerStripeTop))];
		stripe.backgroundColor = [[TGTheme shared] accentColour];
		[self.composeBanner addSubview:stripe];

		UILabel *title = [[UILabel alloc] initWithFrame:
				CGRectMake(kBannerTextX, kBannerTitleTop,
						width - TGMetricComposeBannerTextMarginRight, TGMetricLineSubhead)];
		title.tag = kBannerTitleTag;
		title.font = TGFontCaptionStrong();
		title.textColor = [[TGTheme shared] accentColour];
		title.backgroundColor = [UIColor clearColor];
		title.autoresizingMask = UIViewAutoresizingFlexibleWidth;
		[self.composeBanner addSubview:title];

		UILabel *preview = [[UILabel alloc] initWithFrame:
				CGRectMake(kBannerTextX, kBannerTitleTop + TGMetricLineSubhead,
						width - TGMetricComposeBannerTextMarginRight, TGMetricLineSubhead)];
		preview.tag = kBannerSubtitleTag;
		preview.font = TGFontCaption();
		preview.textColor = [[TGTheme shared] secondaryTextColour];
		preview.backgroundColor = [UIColor clearColor];
		preview.autoresizingMask = UIViewAutoresizingFlexibleWidth;
		[self.composeBanner addSubview:preview];

		UIButton *cancel = [UIButton buttonWithType:UIButtonTypeCustom];
		cancel.frame = CGRectMake(width - TGMetricRow, 0, TGMetricRow, kComposeBannerHeight);
		cancel.autoresizingMask = UIViewAutoresizingFlexibleLeftMargin;
		[cancel setImage:[TGIcons glyphNamed:@"close"
									  colour:[[TGTheme shared] secondaryTextColour]
										side:kBannerCloseGlyph]
				forState:UIControlStateNormal];
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
	CGFloat half = TGHalf(kComposeBannerHeight);
	title.frame = CGRectMake(kBannerTextX,
							 subtitle.length ? kBannerTitleTop
											  : half - TGHalf(TGMetricLineSubhead),
							 self.composeBanner.bounds.size.width - TGMetricComposeBannerTextMarginRight,
							 TGMetricLineSubhead);

	self.composeBanner.hidden = NO;
	[self layoutChrome];
}

#pragma mark - sending

- (void)sendTapped {
	NSString *text = [self.input.text stringByTrimmingCharactersInSet:
			[NSCharacterSet whitespaceAndNewlineCharacterSet]];
	if (!text.length)
		return;

	if (self.editingId != 0 && self.editingIsCaption){
		__weak typeof(self) weakSelf = self;
		[[TGClient shared] editCaption:text
							 ofMessage:self.editingId
								inChat:self.chatId
							completion:^(BOOL ok){
			if (!ok)
				[TGSnackbar showInView:weakSelf.view
								  text:@"Telegram refused that caption"
							   seconds:2 onCommit:nil];
		}];
		self.editingIsCaption = NO;
	} else if (self.editingId != 0)
		[[TGClient shared] editMessage:self.editingId inChat:self.chatId text:text];
	else
		[[TGClient shared] sendText:text toChat:self.chatId
							 thread:self.threadId replyTo:self.replyToId];

	// Before clearComposeState, so inputChanged sees an empty field and puts
	// the microphone back in the send button's place.
	self.input.text = @"";
	[self clearComposeState];
	// The draft was this text; it has been sent, so it is not a draft now.
	[[TGClient shared] setDraft:@"" inChat:self.chatId thread:self.threadId replyTo:0];
	[[TGClient shared] cancelTypingInChat:self.chatId thread:self.threadId];

	// TDLib echoes the message back as an update; refresh shortly after.
	dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(1.0 * NSEC_PER_SEC)),
			dispatch_get_main_queue(), ^{
		[self reload];
	});
}

#pragma mark - sending later

/// Holding Send when there is text offers what a send can wait for. With an
/// empty field there is nothing to wait with, and the hold says nothing.
- (void)sendHeld:(UILongPressGestureRecognizer *)hold {
	if (hold.state != UIGestureRecognizerStateBegan)
		return;
	NSString *text = [self.input.text stringByTrimmingCharactersInSet:
			[NSCharacterSet whitespaceAndNewlineCharacterSet]];
	if (!text.length || self.editingId != 0)
		return;

	__weak typeof(self) weakSelf = self;
	NSString *queue = self.scheduledCount > 0
			? [NSString stringWithFormat:@"Scheduled Messages (%ld)", (long)self.scheduledCount]
			: @"Scheduled Messages";
	[TGAlertSheet showChoices:@[@"Send At a Time...", @"Send When Online", queue]
						title:nil
			 destructiveIndex:-1
					   inView:self.navigationController.view ?: self.view
					 onChoice:^(NSInteger index){
		if (index == 0)
			[weakSelf holdScheduledSheet];
		else if (index == 1)
			[weakSelf sendHeldText:[TGClient scheduledWhenOnline]];
		else {
			TGScheduledViewController *vc = [[TGScheduledViewController alloc] init];
			vc.chatId = weakSelf.chatId;
			vc.chatTitle = weakSelf.chatTitle;
			[weakSelf.navigationController pushViewController:vc animated:YES];
		}
	}];
}

/// The composer's text, sent into whatever state was picked. The draft is
/// lost with the field, which is the whole point: it is no longer waiting
/// here to be sent.
- (void)sendHeldText:(NSDictionary *)state {
	NSString *text = [self.input.text stringByTrimmingCharactersInSet:
			[NSCharacterSet whitespaceAndNewlineCharacterSet]];
	if (!text.length)
		return;
	[[TGClient shared] sendText:text toChat:self.chatId
						 thread:self.threadId replyTo:self.replyToId
					  scheduled:state];
	self.input.text = @"";
	[self clearComposeState];
	[[TGClient shared] setDraft:@"" inChat:self.chatId thread:self.threadId replyTo:0];
	[[TGClient shared] cancelTypingInChat:self.chatId thread:self.threadId];
}

/// The date the composer's text waits for. Done reads the picker, clears
/// the field and sends the held-back send in one move.
- (void)holdScheduledSheet {
	static const CGFloat kBar = TGMetricRow, kPicker = TGMetricPickerHeight;

	TGSheet *sheet = [TGSheet sheetForView:self.view.window ?: self.view];
	UIView *card = [sheet addCardOfHeight:kBar + kPicker edgeToEdge:YES];

	UIDatePicker *picker = [[UIDatePicker alloc] initWithFrame:
			CGRectMake(0, kBar, card.bounds.size.width, kPicker)];
	picker.datePickerMode = UIDatePickerModeDateAndTime;
	picker.minimumDate = [NSDate dateWithTimeIntervalSinceNow:60];
	picker.minuteInterval = 15;
	picker.date = [NSDate dateWithTimeIntervalSinceNow:60 * 60];
	[card addSubview:picker];

	UIToolbar *bar = [[UIToolbar alloc] initWithFrame:
			CGRectMake(0, 0, card.bounds.size.width, kBar)];
	bar.items = @[
		[[UIBarButtonItem alloc] initWithTitle:@"Cancel" style:UIBarButtonItemStylePlain
				target:sheet action:@selector(dismiss)],
		[[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemFlexibleSpace
				target:nil action:nil],
		[[UIBarButtonItem alloc] initWithTitle:@"Schedule" style:UIBarButtonItemStyleDone
				target:self action:@selector(scheduleCommit:)],
	];
	[card addSubview:bar];
	self.pickPicker = picker;
	self.pickSheet = sheet;
	[sheet present];
}

/// The bar's Done. The picker outlives the sheet just long enough to be
/// read: the date is taken first, the sheet dismissed after.
- (void)scheduleCommit:(UIBarButtonItem *)sender {
	NSTimeInterval date = [self.pickPicker.date timeIntervalSince1970];
	[self.pickSheet dismiss];
	self.pickSheet = nil;
	self.pickPicker = nil;
	[self sendHeldText:[TGClient scheduledAtDate:date]];
	// The queue has one more in it than the menu last said.
	self.scheduledCount++;
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
	[UIView animateWithDuration:TGAnimationDurationNormal animations:^{
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
	[UIView animateWithDuration:TGAnimationDurationMedium animations:^{
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


- (void)attachTapped {
	[self.input resignFirstResponder];
	[self hideStickerPanel];
	UIView *host = self.navigationController.view ?: self.view;
	TGAttachSheet *sheet = [TGAttachSheet showInView:host];
	__weak typeof(self) weakSelf = self;
	sheet.onPhoto = ^(UIImage *image){
		[weakSelf sendImage:image];
	};
	sheet.onPhotos = ^(NSArray *images){
		[weakSelf sendImageAlbum:images];
	};
	sheet.onChoice = ^(TGAttachChoice choice){
		switch (choice){
			case TGAttachChoiceGallery:  [weakSelf pickMedia]; break;
			case TGAttachChoiceLocation: [weakSelf sendCurrentLocation]; break;
			case TGAttachChoiceContact:  [weakSelf pickContact]; break;
		}
	};
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
	[UIView animateWithDuration:TGAnimationDurationMedium animations:^{
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
