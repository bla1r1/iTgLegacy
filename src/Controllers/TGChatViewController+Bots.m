//
// TGChatViewController+Bots.m - what a bot puts in a chat besides text: the
// buttons under its messages and the keyboard it can swap in for the system
// one. Neither was drawn before, so a bot that asked a question offered no
// way to answer it.
//
#import "TGChatViewControllerInternal.h"
#import "TGProfileViewController.h"
#import "TGDevShowcase.h"

@implementation TGChatViewController (Bots)

#pragma mark - inline buttons

/// The tapped button's message and place come from where it sits: the tag is
/// row * 16 + column, and the row is found from the table.
- (void)botButtonTapped:(UIButton *)key {
	CGPoint at = [key convertPoint:CGPointZero toView:self.table];
	NSIndexPath *path = [self.table indexPathForRowAtPoint:at];
	if (!path || path.row >= (NSInteger)self.messages.count)
		return;
	NSDictionary *m = self.messages[path.row];
	NSArray *rows = m[@"inlineRows"];
	NSUInteger r = (NSUInteger)key.tag / 16, c = (NSUInteger)key.tag % 16;
	if (r >= rows.count || c >= [rows[r] count])
		return;
	[self pressBotButton:rows[r][c] onMessage:m];
}

- (void)pressBotButton:(NSDictionary *)button onMessage:(NSDictionary *)m {
	NSString *kind = button[@"kind"];
	int64_t chatId = self.chatId, messageId = [m[@"id"] longLongValue];
	__weak typeof(self) weakSelf = self;

	if ([kind isEqualToString:@"callback"]) {
		[[TGClient shared] pressCallbackButton:button inChat:chatId messageId:messageId
									completion:^(NSString *text, BOOL alert, NSString *url, NSString *error){
			TGChatViewController *me = weakSelf;
			if (error)
				[TGSnackbar showInView:me.view text:error seconds:2 onCommit:nil];
			else if (url.length)
				[me handleOpenLink:url];
			else if (text.length && alert)
				[TGAlertSheet showMessage:text title:(button[@"text"] ?: @"") inView:me.view];
			else if (text.length)
				[TGSnackbar showInView:me.view text:text seconds:2 onCommit:nil];
		}];
	} else if ([kind isEqualToString:@"url"]) {
		[self handleOpenLink:button[@"url"]];
	} else if ([kind isEqualToString:@"login"]) {
		[[TGClient shared] loginURLForButton:button inChat:chatId messageId:messageId
								  completion:^(NSString *url, NSString *domain, NSString *error){
			TGChatViewController *me = weakSelf;
			if (url.length) {
				[me handleOpenLink:url];
				return;
			}
			if (!domain.length)
				return;
			[TGAlertSheet showConfirm:[NSString stringWithFormat:@"Log in to %@ with your Telegram account?", domain]
								title:@"Log In"
							   action:@"Log In"
						  destructive:NO
							   inView:me.view
							onConfirm:^{
				[[TGClient shared] confirmLoginButton:button inChat:chatId messageId:messageId
										   completion:^(NSString *link, NSString *refused){
					if (link.length)
						[weakSelf handleOpenLink:link];
					else
						[TGSnackbar showInView:weakSelf.view text:refused seconds:2 onCommit:nil];
				}];
			}];
		}];
	} else if ([kind isEqualToString:@"switch"]) {
		// Inline mode is typed into the composer: "@bot query".
		[[TGClient shared] userInfo:[m[@"senderId"] longLongValue] completion:^(NSDictionary *user){
			TGChatViewController *me = weakSelf;
			NSArray *names = user[@"usernames"][@"active_usernames"];
			NSString *bot = names.count ? [@"@" stringByAppendingString:names[0]] : @"";
			me.input.text = [[NSString stringWithFormat:@"%@ %@", bot, button[@"query"] ?: @""]
					stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceCharacterSet]];
			[me.input becomeFirstResponder];
			[me inputChanged];
		}];
	} else if ([kind isEqualToString:@"copy"]) {
		[UIPasteboard generalPasteboard].string = button[@"copy"] ?: @"";
		[TGSnackbar showInView:self.view text:@"Copied" seconds:1 onCommit:nil];
	} else if ([kind isEqualToString:@"user"]) {
		int64_t userId = [button[@"userId"] longLongValue];
		TGProfileViewController *profile = [[TGProfileViewController alloc]
				initWithChatId:userId userId:userId title:button[@"text"]];
		[self.navigationController pushViewController:profile animated:YES];
	} else {
		[TGSnackbar showInView:self.view text:@"This button needs a newer Telegram" seconds:2 onCommit:nil];
	}
}

#pragma mark - reply keyboard

/// Asks for the chat's keyboard and shows or hides the key in the composer.
/// Run on open and whenever the chat's keyboard changes.
- (void)refreshReplyKeyboard {
	__weak typeof(self) weakSelf = self;
	void (^apply)(NSDictionary *) = ^(NSDictionary *keyboard){
		TGChatViewController *me = weakSelf;
		if (!me)
			return;
		me.replyKeyboard = keyboard;
		if (!keyboard) {
			[me hideBotKeyboard];
			me.input.rightView = nil;
			me.input.rightViewMode = UITextFieldViewModeNever;
			return;
		}
		if (!me.botKeyboardToggle) {
			UIButton *toggle = [UIButton buttonWithType:UIButtonTypeCustom];
			toggle.frame = CGRectMake(0, 0, TGMetricRow - TGMetricPadMedium, me.input.bounds.size.height);
			[toggle setImage:[TGIcons botKeyboard] forState:UIControlStateNormal];
			toggle.tintColor = [[TGTheme shared] secondaryTextColour];
			[toggle addTarget:me action:@selector(toggleBotKeyboard)
			 forControlEvents:UIControlEventTouchUpInside];
			me.botKeyboardToggle = toggle;
		}
		me.input.rightView = me.botKeyboardToggle;
		me.input.rightViewMode = UITextFieldViewModeAlways;
		NSString *placeholder = keyboard[@"placeholder"];
		if (placeholder.length)
			me.input.placeholder = placeholder;
	};
#if TG_DEV
	NSDictionary *fixture = [TGDevShowcase replyKeyboardForChatId:self.chatId];
	if (fixture) {
		apply(fixture);
		return;
	}
#endif
	[[TGClient shared] replyKeyboardForChat:self.chatId completion:apply];
}

- (void)replyMarkupChanged:(NSNotification *)note {
	if ([note.userInfo[@"chatId"] longLongValue] == self.chatId)
		[self refreshReplyKeyboard];
}

- (BOOL)botKeyboardShown {
	return self.botKeyboardPanel && !self.botKeyboardPanel.hidden;
}

- (void)toggleBotKeyboard {
	if ([self botKeyboardShown]) {
		[self.input becomeFirstResponder];     // its arrival puts the panel away
		return;
	}
	NSArray *rows = self.replyKeyboard[@"rows"];
	if (!rows.count)
		return;
	[self hideStickerPanel];
	if ([self.input isFirstResponder])
		[self.input resignFirstResponder];

	CGRect b = self.view.bounds;
	CGFloat height = MIN((CGFloat)rows.count, (CGFloat)TGMetricBotKeyRowsShown) * TGMetricBotKeyHeight
			+ TGMetricBotButtonGap;
	[self.botKeyboardPanel removeFromSuperview];
	UIScrollView *panel = [[UIScrollView alloc] initWithFrame:CGRectMake(0, b.size.height, b.size.width, height)];
	panel.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleTopMargin;
	TGTheme *theme = [TGTheme shared];
	panel.backgroundColor = [theme inputBarColour];
	CGFloat gap = TGMetricBotButtonGap;
	for (NSUInteger r = 0; r < rows.count; r++) {
		NSArray *row = rows[r];
		CGFloat w = (b.size.width - gap * (row.count + 1)) / row.count;
		for (NSUInteger c = 0; c < row.count; c++) {
			UIButton *key = [UIButton buttonWithType:UIButtonTypeCustom];
			key.frame = CGRectMake(gap + c * (w + gap), gap + r * TGMetricBotKeyHeight,
								   w, TGMetricBotKeyHeight - gap);
			key.backgroundColor = [theme cardBackgroundColour];
			key.layer.cornerRadius = TGMetricCornerSmall;
			key.layer.borderWidth = TGMetricBorderWidth;
			key.layer.borderColor = [theme separatorColour].CGColor;
			key.titleLabel.font = TGFontBody();
			[key setTitle:row[c] forState:UIControlStateNormal];
			[key setTitleColor:[theme primaryTextColour] forState:UIControlStateNormal];
			[key addTarget:self action:@selector(botKeyTapped:) forControlEvents:UIControlEventTouchUpInside];
			[panel addSubview:key];
		}
	}
	panel.contentSize = CGSizeMake(b.size.width, rows.count * TGMetricBotKeyHeight + gap);
	[self.view addSubview:panel];
	self.botKeyboardPanel = panel;
	[UIView animateWithDuration:TGAnimationDurationMedium animations:^{
		panel.frame = CGRectMake(0, b.size.height - height, b.size.width, height);
	}];
	[self shiftForKeyboardHeight:height];
}

- (void)hideBotKeyboard {
	if (![self botKeyboardShown])
		return;
	UIView *panel = self.botKeyboardPanel;
	CGRect b = self.view.bounds;
	[UIView animateWithDuration:TGAnimationDurationNormal animations:^{
		CGRect f = panel.frame;
		f.origin.y = b.size.height;
		panel.frame = f;
	} completion:^(BOOL finished) {
		panel.hidden = YES;
	}];
	if (![self.input isFirstResponder])
		[self shiftForKeyboardHeight:0];
}

/// A key sends its own label, which is the whole protocol of a reply
/// keyboard. A one-time keyboard folds away after one key.
- (void)botKeyTapped:(UIButton *)key {
	NSString *text = key.currentTitle;
	if (!text.length)
		return;
	[[TGClient shared] sendText:text toChat:self.chatId thread:self.threadId];
	if ([self.replyKeyboard[@"oneTime"] boolValue]){
		// A one-time keyboard is spent; TDLib wants the markup dropped so a
		// reload of the chat does not bring the dead keys back.
		[[TGClient shared] dismissReplyMarkupInChat:self.chatId];
		[self hideBotKeyboard];
	}
}

@end
