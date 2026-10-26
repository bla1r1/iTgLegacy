#import "TGAlertSheet.h"
#import "TGTheme.h"
#import "TGStyle.h"

static const CGFloat kRow      = TGMetricActionRow; ///< one button
static const CGFloat kPad      = TGMetricAlertPad;  ///< text from the card's edge
static const CGFloat kTextGap  = TGMetricAlertTextGap; ///< title to message
static const CGFloat kFieldTop = TGMetricAlertFieldTop;

/// The list shape is the one the others are built on, and it takes a message
/// the public list form has no room for.
@interface TGAlertSheet ()
+ (void)showChoices:(NSArray *)titles
			  title:(NSString *)title
			message:(NSString *)message
   destructiveIndex:(NSInteger)destructiveIndex
			 inView:(UIView *)host
		   onChoice:(void (^)(NSInteger index))onChoice;
@end

@implementation TGAlertSheet {
	UITextField *_field;
	void (^_onSubmit)(NSString *);
	void (^_onChoice)(NSInteger);
}

#pragma mark - the pieces every shape is built from

/// The block of text at the top of a card: a bold title, a message under it,
/// or either on its own. Returns the height it took.
+ (CGFloat)addTextTo:(UIView *)card title:(NSString *)title message:(NSString *)message {
	TGTheme *theme = [TGTheme shared];
	CGFloat width = card.bounds.size.width - TGDoubled(kPad);
	CGFloat y = kPad;

	if (title.length){
		CGSize size = [self sizeOfText:title font:TGFontRowStrong() width:width];
		UILabel *label = [[UILabel alloc] initWithFrame:
				CGRectMake(kPad, y, width, size.height)];
		label.text = title;
		label.font = TGFontRowStrong();
		label.textColor = [theme primaryTextColour];
		label.numberOfLines = 0;
		label.textAlignment = NSTextAlignmentCenter;
		label.backgroundColor = [UIColor clearColor];
		[card addSubview:label];
		y += size.height + (message.length ? kTextGap : 0);
	}

	if (message.length){
		CGSize size = [self sizeOfText:message font:TGFontCaption() width:width];
		UILabel *label = [[UILabel alloc] initWithFrame:
				CGRectMake(kPad, y, width, size.height)];
		label.text = message;
		label.font = TGFontCaption();
		label.textColor = [theme secondaryTextColour];
		label.numberOfLines = 0;
		label.textAlignment = NSTextAlignmentCenter;
		label.backgroundColor = [UIColor clearColor];
		[card addSubview:label];
		y += size.height;
	}

	return y > kPad ? y + kPad : 0;
}

/// Text height, through whichever measuring call this OS has.
+ (CGSize)sizeOfText:(NSString *)text font:(UIFont *)font width:(CGFloat)width {
	CGSize bound = CGSizeMake(width, 10000);
	if ([text respondsToSelector:@selector(boundingRectWithSize:options:attributes:context:)]){
		CGRect rect = [text boundingRectWithSize:bound
										 options:NSStringDrawingUsesLineFragmentOrigin
									  attributes:@{NSFontAttributeName : font}
										 context:nil];
		return CGSizeMake(width, ceilf(rect.size.height));
	}
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wdeprecated-declarations"
	CGSize size = [text sizeWithFont:font constrainedToSize:bound
					   lineBreakMode:NSLineBreakByWordWrapping];
#pragma clang diagnostic pop
	return CGSizeMake(width, ceilf(size.height));
}

/// One button row, with the hairline above it that separates it from whatever
/// it follows.
- (UIButton *)addRowTo:(UIView *)card atY:(CGFloat)y title:(NSString *)title
		   destructive:(BOOL)destructive separator:(BOOL)separator {
	TGTheme *theme = [TGTheme shared];
	if (separator){
		UIView *line = [[UIView alloc] initWithFrame:
				CGRectMake(0, y, card.bounds.size.width, TGMetricHairline)];
		line.backgroundColor = [theme separatorColour];
		[card addSubview:line];
	}
	UIButton *button = [UIButton buttonWithType:UIButtonTypeCustom];
	button.frame = CGRectMake(0, y, card.bounds.size.width, kRow);
	button.titleLabel.font = destructive ? TGFontRowStrong() : TGFontRow();
	[button setTitle:title forState:UIControlStateNormal];
	[button setTitleColor:destructive ? [theme destructiveColour] : [theme accentColour]
				 forState:UIControlStateNormal];
	[button setTitleColor:[theme secondaryTextColour] forState:UIControlStateHighlighted];
	[card addSubview:button];
	return button;
}

/// The Cancel card that sits on its own under the stack, as an action sheet's
/// does. Dismissing is all it ever means, so it needs no block.
- (void)addCancelCardTitled:(NSString *)title {
	UIView *card = [self addCardOfHeight:kRow edgeToEdge:NO];
	UIButton *cancel = [self addRowTo:card atY:0 title:(title ?: @"Cancel")
						  destructive:NO separator:NO];
	cancel.titleLabel.font = TGFontRowStrong();
	[cancel addTarget:self action:@selector(dismiss)
	 forControlEvents:UIControlEventTouchUpInside];
}

#pragma mark - the four shapes

+ (void)showMessage:(NSString *)message title:(NSString *)title inView:(UIView *)host {
	if (!host || (!message.length && !title.length))
		return;
	TGAlertSheet *sheet = [self sheetForView:host];
	CGFloat width = host.bounds.size.width - TGDoubled(TGMetricCardMargin);
	CGFloat textHeight = [self addTextTo:[[UIView alloc] initWithFrame:
			CGRectMake(0, 0, width, 0)] title:title message:message];

	UIView *card = [sheet addCardOfHeight:textHeight + kRow edgeToEdge:NO];
	[self addTextTo:card title:title message:message];
	UIButton *ok = [sheet addRowTo:card atY:textHeight title:@"OK"
					   destructive:NO separator:YES];
	[ok addTarget:sheet action:@selector(dismiss)
 forControlEvents:UIControlEventTouchUpInside];
	[sheet present];
}

+ (void)showConfirm:(NSString *)message title:(NSString *)title
			 action:(NSString *)actionTitle destructive:(BOOL)destructive
			 inView:(UIView *)host onConfirm:(void (^)(void))onConfirm {
	if (!host)
		return;
	[self showChoices:@[actionTitle ?: @"OK"]
				title:title
			  message:message
	 destructiveIndex:destructive ? 0 : -1
			   inView:host
			 onChoice:^(NSInteger index){ if (onConfirm) onConfirm(); }];
}

+ (void)showChoices:(NSArray *)titles title:(NSString *)title
   destructiveIndex:(NSInteger)destructiveIndex inView:(UIView *)host
		   onChoice:(void (^)(NSInteger index))onChoice {
	[self showChoices:titles title:title message:nil
	 destructiveIndex:destructiveIndex inView:host onChoice:onChoice];
}

/// The one the other three end up in. A message under the title is what
/// separates a confirmation from a plain list, and nothing else does.
+ (void)showChoices:(NSArray *)titles title:(NSString *)title message:(NSString *)message
   destructiveIndex:(NSInteger)destructiveIndex inView:(UIView *)host
		   onChoice:(void (^)(NSInteger index))onChoice {
	if (!host || titles.count == 0)
		return;
	TGAlertSheet *sheet = [self sheetForView:host];
	CGFloat width = host.bounds.size.width - TGDoubled(TGMetricCardMargin);
	CGFloat textHeight = [self addTextTo:[[UIView alloc] initWithFrame:
			CGRectMake(0, 0, width, 0)] title:title message:message];

	UIView *card = [sheet addCardOfHeight:textHeight + kRow * titles.count
							   edgeToEdge:NO];
	[self addTextTo:card title:title message:message];

	for (NSUInteger i = 0; i < titles.count; i++){
		UIButton *button = [sheet addRowTo:card
									   atY:textHeight + kRow * i
									 title:titles[i]
							   destructive:(NSInteger)i == destructiveIndex
								 separator:(i > 0 || textHeight > 0)];
		button.tag = (NSInteger)i;
		[button addTarget:sheet action:@selector(choiceTapped:)
		 forControlEvents:UIControlEventTouchUpInside];
	}

	sheet->_onChoice = [onChoice copy];
	[sheet addCancelCardTitled:nil];
	[sheet present];
}

+ (void)showInput:(NSString *)title message:(NSString *)message
	  placeholder:(NSString *)placeholder text:(NSString *)text
		   action:(NSString *)actionTitle inView:(UIView *)host
		 onSubmit:(void (^)(NSString *))onSubmit {
	[self showTextFieldInput:title message:message
				   placeholder:placeholder text:text secure:NO
					   action:actionTitle inView:host
					 onSubmit:onSubmit];
}

/// The same card with dots instead of letters - what a password is worth
/// asking for with. Everything else about the flow is the ordinary input.
+ (void)showSecureInput:(NSString *)title message:(NSString *)message
			placeholder:(NSString *)placeholder
				 action:(NSString *)actionTitle
				 inView:(UIView *)host
			  onSubmit:(void (^)(NSString *text))onSubmit {
	[self showTextFieldInput:title message:message
				   placeholder:placeholder text:nil secure:YES
					   action:actionTitle inView:host
					 onSubmit:onSubmit];
}

+ (void)showTextFieldInput:(NSString *)title message:(NSString *)message
			   placeholder:(NSString *)placeholder text:(NSString *)text
					secure:(BOOL)secure
					action:(NSString *)actionTitle inView:(UIView *)host
				  onSubmit:(void (^)(NSString *text))onSubmit {
	if (!host)
		return;
	TGTheme *theme = [TGTheme shared];
	TGAlertSheet *sheet = [self sheetForView:host];
	CGFloat width = host.bounds.size.width - TGDoubled(TGMetricCardMargin);
	CGFloat textHeight = [self addTextTo:[[UIView alloc] initWithFrame:
			CGRectMake(0, 0, width, 0)] title:title message:message];
	CGFloat fieldHeight = TGMetricRow - kFieldTop;

	UIView *card = [sheet addCardOfHeight:textHeight + kFieldTop + fieldHeight + kRow
							   edgeToEdge:NO];
	[self addTextTo:card title:title message:message];

	UITextField *field = [[UITextField alloc] initWithFrame:
			CGRectMake(kPad, textHeight + kFieldTop, width - TGDoubled(kPad), fieldHeight)];
	field.font = TGFontRow();
	field.text = text ?: @"";
	field.placeholder = placeholder;
	field.textColor = [theme primaryTextColour];
	field.borderStyle = UITextBorderStyleRoundedRect;
	field.autocorrectionType = UITextAutocorrectionTypeNo;
	field.returnKeyType = UIReturnKeyDone;
	field.clearButtonMode = UITextFieldViewModeWhileEditing;
	field.secureTextEntry = secure;
	field.autocapitalizationType = UITextAutocapitalizationTypeNone;
	[card addSubview:field];
	sheet->_field = field;
	sheet->_onSubmit = [onSubmit copy];

	UIButton *done = [sheet addRowTo:card atY:textHeight + kFieldTop + fieldHeight
							   title:(actionTitle ?: @"OK") destructive:NO separator:YES];
	[done addTarget:sheet action:@selector(submitTapped)
   forControlEvents:UIControlEventTouchUpInside];
	[field addTarget:sheet action:@selector(submitTapped)
	forControlEvents:UIControlEventEditingDidEndOnExit];

	[sheet addCancelCardTitled:nil];
	// The keyboard comes up with the sheet, so the inset is in place before
	// the slide rather than shoving the card a second time.
	[[NSNotificationCenter defaultCenter] addObserver:sheet
											 selector:@selector(keyboardChanged:)
												 name:UIKeyboardWillShowNotification
											   object:nil];
	[sheet present];
	[field becomeFirstResponder];
}

#pragma mark - answering

- (void)choiceTapped:(UIButton *)button {
	void (^choice)(NSInteger) = _onChoice;
	NSInteger index = button.tag;
	[self dismiss];
	if (choice)
		choice(index);
}

- (void)submitTapped {
	NSString *text = [_field.text stringByTrimmingCharactersInSet:
			[NSCharacterSet whitespaceAndNewlineCharacterSet]];
	void (^submit)(NSString *) = _onSubmit;
	[_field resignFirstResponder];
	[self dismiss];
	if (submit && text.length)
		submit(text);
}

- (void)keyboardChanged:(NSNotification *)note {
	CGRect frame = [note.userInfo[UIKeyboardFrameEndUserInfoKey] CGRectValue];
	// Before iOS 8 the frame arrives in unrotated screen coordinates, so in
	// landscape its width is what covers the screen's height. The shorter side
	// is the keyboard's own height either way.
	CGFloat height = UIInterfaceOrientationIsLandscape(
			[UIApplication sharedApplication].statusBarOrientation)
			? MIN(frame.size.width, frame.size.height)
			: frame.size.height;
	[UIView animateWithDuration:TGAnimationDurationMedium animations:^{ self.bottomInset = height; }];
}

- (void)dismiss {
	[[NSNotificationCenter defaultCenter] removeObserver:self];
	[_field resignFirstResponder];
	[super dismiss];
}

- (void)dealloc {
	[[NSNotificationCenter defaultCenter] removeObserver:self];
}

@end

// vim:ft=objc
