#import "TGAlertSheet.h"

/// The system's own alerts and sheets behind the block API the app calls:
/// UIAlertView and UIActionSheet up to iOS 7, UIAlertController from 8. They
/// look like every other app on the phone, on whichever OS it runs; the
/// drawn sheet this replaced was an iOS 6 imitation everywhere.
///
/// The pre-8 classes answer a delegate; an instance of this class is that
/// delegate, holds the blocks, and keeps itself alive in sLive until the
/// alert is gone.
@interface TGAlertSheet () <UIAlertViewDelegate, UIActionSheetDelegate>
@property (nonatomic, copy) void (^onButton)(NSInteger buttonIndex, NSString *text);
@end

static NSMutableSet *sLive;

@implementation TGAlertSheet

+ (BOOL)hasAlertController {
	return NSClassFromString(@"UIAlertController") != nil;
}

+ (TGAlertSheet *)holderWith:(void (^)(NSInteger, NSString *))onButton {
	if (!sLive)
		sLive = [NSMutableSet set];
	TGAlertSheet *holder = [[TGAlertSheet alloc] init];
	holder.onButton = onButton;
	[sLive addObject:holder];
	return holder;
}

/// The controller a UIAlertController is presented from: the top of
/// whatever the host's window is showing.
+ (UIViewController *)presenterFor:(UIView *)host {
	UIWindow *window = host.window ?: [UIApplication sharedApplication].keyWindow;
	UIViewController *vc = window.rootViewController;
	while (vc.presentedViewController)
		vc = vc.presentedViewController;
	return vc;
}

+ (void)present:(UIAlertController *)alert from:(UIView *)host {
	// iPad shows a sheet as a popover, which needs somewhere to point.
	UIPopoverPresentationController *pop = alert.popoverPresentationController;
	if (pop) {
		pop.sourceView = host;
		pop.sourceRect = CGRectMake(CGRectGetMidX(host.bounds), CGRectGetMaxY(host.bounds) - 1, 1, 1);
	}
	[[self presenterFor:host] presentViewController:alert animated:YES completion:nil];
}

/// Title and message as one line of an action sheet, which has only a title.
static NSString *TGSheetTitle(NSString *title, NSString *message) {
	if (title.length && message.length)
		return [NSString stringWithFormat:@"%@\n\n%@", title, message];
	return title.length ? title : (message.length ? message : nil);
}

static NSString *TGTrimmed(NSString *text) {
	return [text ?: @"" stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
}

#pragma mark - the four shapes

+ (void)showMessage:(NSString *)message title:(NSString *)title inView:(UIView *)host {
	if ([self hasAlertController]) {
		UIAlertController *alert = [UIAlertController alertControllerWithTitle:title message:message
				preferredStyle:UIAlertControllerStyleAlert];
		[alert addAction:[UIAlertAction actionWithTitle:@"OK" style:UIAlertActionStyleCancel handler:nil]];
		[self present:alert from:host];
		return;
	}
	[[[UIAlertView alloc] initWithTitle:title message:message delegate:nil
					  cancelButtonTitle:@"OK" otherButtonTitles:nil] show];
}

+ (void)showConfirm:(NSString *)message title:(NSString *)title
			 action:(NSString *)actionTitle destructive:(BOOL)destructive
			 inView:(UIView *)host onConfirm:(void (^)(void))onConfirm {
	// An action that destroys something asks from the bottom with a red
	// button, as iOS itself does; anything else is a plain alert.
	if ([self hasAlertController]) {
		UIAlertController *alert = [UIAlertController alertControllerWithTitle:title message:message
				preferredStyle:destructive ? UIAlertControllerStyleActionSheet : UIAlertControllerStyleAlert];
		[alert addAction:[UIAlertAction actionWithTitle:actionTitle
				style:destructive ? UIAlertActionStyleDestructive : UIAlertActionStyleDefault
				handler:^(UIAlertAction *a){ if (onConfirm) onConfirm(); }]];
		[alert addAction:[UIAlertAction actionWithTitle:@"Cancel" style:UIAlertActionStyleCancel handler:nil]];
		[self present:alert from:host];
		return;
	}
	if (destructive) {
		[self showChoices:@[actionTitle] title:title message:message destructiveIndex:0
				   inView:host onChoice:^(NSInteger index){ if (onConfirm) onConfirm(); }];
		return;
	}
	TGAlertSheet *holder = [self holderWith:^(NSInteger button, NSString *text){
		if (button == 1 && onConfirm)
			onConfirm();
	}];
	[[[UIAlertView alloc] initWithTitle:title message:message delegate:holder
					  cancelButtonTitle:@"Cancel" otherButtonTitles:actionTitle, nil] show];
}

+ (void)showChoices:(NSArray *)titles title:(NSString *)title
   destructiveIndex:(NSInteger)destructiveIndex
			 inView:(UIView *)host onChoice:(void (^)(NSInteger index))onChoice {
	[self showChoices:titles title:title message:nil destructiveIndex:destructiveIndex
			   inView:host onChoice:onChoice];
}

+ (void)showChoices:(NSArray *)titles title:(NSString *)title message:(NSString *)message
   destructiveIndex:(NSInteger)destructiveIndex
			 inView:(UIView *)host onChoice:(void (^)(NSInteger index))onChoice {
	if (!titles.count)
		return;
	if ([self hasAlertController]) {
		UIAlertController *sheet = [UIAlertController alertControllerWithTitle:title message:message
				preferredStyle:UIAlertControllerStyleActionSheet];
		[titles enumerateObjectsUsingBlock:^(NSString *t, NSUInteger i, BOOL *stop){
			[sheet addAction:[UIAlertAction actionWithTitle:t
					style:(NSInteger)i == destructiveIndex ? UIAlertActionStyleDestructive : UIAlertActionStyleDefault
					handler:^(UIAlertAction *a){ if (onChoice) onChoice((NSInteger)i); }]];
		}];
		[sheet addAction:[UIAlertAction actionWithTitle:@"Cancel" style:UIAlertActionStyleCancel handler:nil]];
		[self present:sheet from:host];
		return;
	}
	TGAlertSheet *holder = [self holderWith:nil];
	UIActionSheet *sheet = [[UIActionSheet alloc] initWithTitle:TGSheetTitle(title, message) delegate:holder
			cancelButtonTitle:nil destructiveButtonTitle:nil otherButtonTitles:nil];
	for (NSString *t in titles)
		[sheet addButtonWithTitle:t];
	if (destructiveIndex >= 0 && destructiveIndex < (NSInteger)titles.count)
		sheet.destructiveButtonIndex = destructiveIndex;
	sheet.cancelButtonIndex = [sheet addButtonWithTitle:@"Cancel"];
	NSInteger cancel = sheet.cancelButtonIndex;
	holder.onButton = ^(NSInteger button, NSString *text){
		if (button != cancel && button >= 0 && onChoice)
			onChoice(button);
	};
	[sheet showInView:host.window ?: host];
}

+ (void)showInput:(NSString *)title message:(NSString *)message
	  placeholder:(NSString *)placeholder text:(NSString *)text
		   action:(NSString *)actionTitle inView:(UIView *)host
		 onSubmit:(void (^)(NSString *text))onSubmit {
	[self showField:title message:message placeholder:placeholder text:text secure:NO
			 action:actionTitle inView:host onSubmit:onSubmit];
}

+ (void)showSecureInput:(NSString *)title message:(NSString *)message
			placeholder:(NSString *)placeholder action:(NSString *)actionTitle
				 inView:(UIView *)host onSubmit:(void (^)(NSString *text))onSubmit {
	[self showField:title message:message placeholder:placeholder text:nil secure:YES
			 action:actionTitle inView:host onSubmit:onSubmit];
}

/// One field: the submit runs only on the action and never with an empty
/// string, which is what every caller had been checking for itself.
+ (void)showField:(NSString *)title message:(NSString *)message
	  placeholder:(NSString *)placeholder text:(NSString *)text secure:(BOOL)secure
		   action:(NSString *)actionTitle inView:(UIView *)host
		 onSubmit:(void (^)(NSString *text))onSubmit {
	void (^submit)(NSString *) = ^(NSString *typed){
		NSString *clean = TGTrimmed(typed);
		if (clean.length && onSubmit)
			onSubmit(clean);
	};
	if ([self hasAlertController]) {
		UIAlertController *alert = [UIAlertController alertControllerWithTitle:title message:message
				preferredStyle:UIAlertControllerStyleAlert];
		[alert addTextFieldWithConfigurationHandler:^(UITextField *field){
			field.placeholder = placeholder;
			field.text = text;
			field.secureTextEntry = secure;
		}];
		__weak UIAlertController *weakAlert = alert;
		[alert addAction:[UIAlertAction actionWithTitle:@"Cancel" style:UIAlertActionStyleCancel handler:nil]];
		[alert addAction:[UIAlertAction actionWithTitle:actionTitle style:UIAlertActionStyleDefault
				handler:^(UIAlertAction *a){ submit(weakAlert.textFields.firstObject.text); }]];
		[self present:alert from:host];
		return;
	}
	TGAlertSheet *holder = [self holderWith:^(NSInteger button, NSString *typed){
		if (button == 1)
			submit(typed);
	}];
	UIAlertView *alert = [[UIAlertView alloc] initWithTitle:title message:message delegate:holder
										  cancelButtonTitle:@"Cancel" otherButtonTitles:actionTitle, nil];
	alert.alertViewStyle = secure ? UIAlertViewStyleSecureTextInput : UIAlertViewStylePlainTextInput;
	UITextField *field = [alert textFieldAtIndex:0];
	field.placeholder = placeholder;
	field.text = text;
	[alert show];
}

#pragma mark - pre-iOS 8 delegates

- (void)alertView:(UIAlertView *)alertView didDismissWithButtonIndex:(NSInteger)buttonIndex {
	NSString *typed = alertView.alertViewStyle == UIAlertViewStyleDefault
			? nil : [alertView textFieldAtIndex:0].text;
	if (self.onButton)
		self.onButton(buttonIndex, typed);
	[sLive removeObject:self];
}

- (void)actionSheet:(UIActionSheet *)actionSheet didDismissWithButtonIndex:(NSInteger)buttonIndex {
	if (self.onButton)
		self.onButton(buttonIndex, nil);
	[sLive removeObject:self];
}

@end
