#import "TGChatViewControllerInternal.h"
#import "TGForwardPicker.h"
#import "TGPopupMenu.h"
#import "TGStyle.h"
#import "TGAlertSheet.h"

/// What the reply strip shows on its second line. The rows here are already
/// flattened, so TGMessagePreview - which reads a raw TDLib content - cannot
/// be used; a media row carries no text and is named by its kind instead.
static NSString *TGComposePreview(NSDictionary *m) {
	NSString *text = m[@"text"];
	if (text.length)
		return text;
	NSString *kind = m[@"kind"] ?: @"";
	if ([kind hasPrefix:@"message"])
		kind = [kind substringFromIndex:7];
	if (!kind.length)
		return @"";
	// "VoiceNote" reads as "Voice note" on the strip.
	NSMutableString *spaced = [NSMutableString stringWithString:[kind substringToIndex:1]];
	for (NSUInteger i = 1; i < kind.length; i++){
		unichar c = [kind characterAtIndex:i];
		if (c >= 'A' && c <= 'Z')
			[spaced appendFormat:@" %c", (char)(c - 'A' + 'a')];
		else
			[spaced appendFormat:@"%C", c];
	}
	return spaced;
}

/// The sticker's own file, whichever shape the message carries it in: a .tgs
/// rides as the document, a .webp as the picture.
static NSInteger TGStickerFileId(NSDictionary *m) {
	NSNumber *docId = [m[@"docId"] isKindOfClass:NSNumber.class] ? m[@"docId"] : nil;
	if (docId.integerValue > 0 && [m[@"docName"] isEqualToString:@"tgs"])
		return docId.integerValue;
	NSNumber *photoId = [m[@"photoId"] isKindOfClass:NSNumber.class] ? m[@"photoId"] : nil;
	return photoId.integerValue > 0 ? photoId.integerValue : docId.integerValue;
}

@implementation TGChatViewController (Actions)

#pragma mark - message actions

- (void)messageHeld:(UILongPressGestureRecognizer *)hold {
	if (self.isEditingMessages)
		return;
	if (hold.state != UIGestureRecognizerStateBegan)
		return;

	NSIndexPath *path = [self.table indexPathForRowAtPoint:[hold locationInView:self.table]];
	if (path)
		[self showActionsForRow:path.row];
}

/// Split out from the gesture so itglegacy://holdrow/N can reach it: a long
/// press cannot be delivered through a URL.
- (void)showActionsForRow:(NSInteger)row {
	if (row < 0 || row >= (NSInteger)self.messages.count)
		return;

	NSDictionary *m = self.messages[row];
	if ([m[@"service"] boolValue])
		return;
	self.actionMessage = m;

	BOOL mine = [m[@"outgoing"] boolValue];
	int64_t heldId = [m[@"id"] longLongValue];
	NSString *myReaction = m[@"myReaction"];

	NSMutableArray *items = [NSMutableArray array];
	// A message that failed has one thing worth doing to it, and it goes first.
	if ([m[@"failed"] boolValue])
		[items addObject:@{@"title" : @"Retry", @"icon" : @"reply"}];
	[items addObjectsFromArray:@[
			@{@"title" : @"Reply",   @"icon" : @"reply"},
			@{@"title" : @"Forward", @"icon" : @"forward"},
	]];
	// One reaction at a time is what TDLib allows here, so the menu either
	// offers to put one on or to take yours off - never both.
	if (myReaction.length)
		[items addObject:@{@"title" : [NSString stringWithFormat:
				@"Remove %@", myReaction], @"icon" : @"react"}];
	else
		[items addObject:@{@"title" : @"React", @"icon" : @"react"}];
	[items addObject:@{@"title" : @"Select", @"icon" : @"select"}];
	if ([m[@"text"] length])
		[items addObject:@{@"title" : @"Copy", @"icon" : @"copy"}];
	if (mine && [m[@"text"] length])
		[items addObject:@{@"title" : @"Edit", @"icon" : @"edit"}];
	if (![m[@"service"] boolValue])
		[items addObject:@{@"title" : (heldId == self.pinnedMessageId ? @"Unpin" : @"Pin"),
						   @"icon" : @"pin"}];
	[items addObject:@{@"title" : @"Copy Link", @"icon" : @"copy"}];
	// A sticker you are holding is a sticker you may want to keep.
	if ([m[@"kind"] isEqualToString:@"messageSticker"] && TGStickerFileId(m) > 0)
		[items addObject:@{@"title" : @"Add to Favourites", @"icon" : @"pin"}];
	if (mine)
		[items addObject:@{@"title" : @"Delete", @"icon" : @"delete",
						   @"destructive" : @YES}];

	// Beside the message rather than over the whole screen, which is what
	// makes it read as belonging to that bubble.
	CGRect rect = [self.table rectForRowAtIndexPath:
			[NSIndexPath indexPathForRow:row inSection:0]];
	CGPoint where = [self.table convertPoint:
			CGPointMake(mine ? CGRectGetMaxX(rect) - 60 : 60, CGRectGetMaxY(rect) - 8)
									  toView:self.view];

	__weak typeof(self) weakSelf = self;
	[TGPopupMenu showItems:items atPoint:where inView:self.view
				  onChoice:^(NSInteger index, NSString *title){
		[weakSelf runMessageAction:title];
	}];
}

- (void)runMessageAction:(NSString *)action {
	NSDictionary *m = self.actionMessage;
	int64_t messageId = [m[@"id"] longLongValue];
	if (!messageId)
		return;

	if ([action isEqualToString:@"Reply"]){
		self.replyToId = messageId;
		self.editingId = 0;
		NSString *who = [m[@"outgoing"] boolValue] ? @"You"
				: ([[TGClient shared] nameForUserId:[m[@"senderId"] longLongValue]] ?: @"Reply");
		[self showComposeBanner:who subtitle:TGComposePreview(m)];
		[self.input becomeFirstResponder];

	} else if ([action isEqualToString:@"Forward"]){
		TGForwardPicker *picker = [[TGForwardPicker alloc] init];
		__weak typeof(self) weakSelf = self;
		picker.onPicked = ^(int64_t targetChatId){
			[[TGClient shared] forwardMessages:@[@(messageId)]
									  fromChat:weakSelf.chatId
										toChat:targetChatId];
		};
		[self.navigationController pushViewController:picker animated:YES];

	} else if ([action isEqualToString:@"Select"]){
		[self enterEditMode];
		[self toggleMessageSelection:messageId];

	} else if ([action isEqualToString:@"Retry"]){
		[[TGClient shared] resendMessages:@[@(messageId)] inChat:self.chatId];

	} else if ([action hasPrefix:@"Remove "]){
		[[TGClient shared] removeReaction:m[@"myReaction"]
							  fromMessage:messageId
								   inChat:self.chatId];
		[self reload];

	} else if ([action hasPrefix:@"React"]){
		[self askReactionForMessage:messageId];

	} else if ([action isEqualToString:@"Pin"]){
		[[TGClient shared] pinMessage:messageId inChat:self.chatId notify:NO];
		[self performSelector:@selector(loadPinnedMessage) withObject:nil afterDelay:0.6];

	} else if ([action isEqualToString:@"Unpin"]){
		[[TGClient shared] unpinMessage:messageId inChat:self.chatId];
		self.pinnedMessageId = 0;
		[self hidePinnedBanner];

	} else if ([action isEqualToString:@"Copy Link"]){
		__weak typeof(self) weakSelf = self;
		[[TGClient shared] linkToMessage:messageId inChat:self.chatId
							  completion:^(NSString *link){
			TGChatViewController *me = weakSelf;
			if (!link.length){
				[TGSnackbar showInView:me.view text:@"This chat has no public link"
							   seconds:2 onCommit:nil];
				return;
			}
			[UIPasteboard generalPasteboard].string = link;
			[TGSnackbar showInView:me.view text:@"Link copied" seconds:2 onCommit:nil];
		}];

	} else if ([action isEqualToString:@"Copy"]){
		[UIPasteboard generalPasteboard].string = m[@"text"];

	} else if ([action isEqualToString:@"Edit"]){
		self.editingId = messageId;
		self.replyToId = 0;
		self.input.text = m[@"text"];
		[self showComposeBanner:@"Editing"];
		[self.input becomeFirstResponder];

	} else if ([action isEqualToString:@"Add to Favourites"]){
		[[TGClient shared] setSticker:TGStickerFileId(m) favourite:YES];
		[TGSnackbar showInView:self.navigationController.view ?: self.view
						  text:@"Added to Favourites" seconds:2 onCommit:nil];

	} else if ([action isEqualToString:@"Delete"]){
		[self promptDeleteMessages:@[@(messageId)]];
	}
	self.actionMessage = nil;
}

/// Their six, in their order. One reaction at a time is all this screen
/// offers; picking a second replaces the first on Telegram's side.
- (void)askReactionForMessage:(int64_t)messageId {
	NSArray *emoji = @[@"\U0001F44D", @"\U0001F44E", @"\U00002764",
					   @"\U0001F525", @"\U0001F389", @"\U0001F62D"];
	__weak typeof(self) weakSelf = self;
	[TGAlertSheet showChoices:emoji
						title:@"React"
			 destructiveIndex:-1
					   inView:self.view
					 onChoice:^(NSInteger index){
		TGChatViewController *me = weakSelf;
		[[TGClient shared] reactTo:messageId inChat:me.chatId emoji:emoji[index]];
		[me reload];
	}];
}

#pragma mark - attachments

- (void)pickMedia {
	if (![UIImagePickerController isSourceTypeAvailable:
			UIImagePickerControllerSourceTypePhotoLibrary])
		return;

	UIImagePickerController *picker = [[UIImagePickerController alloc] init];
	picker.sourceType = UIImagePickerControllerSourceTypePhotoLibrary;
	// Without this the library shows photos only, and video cannot be sent.
	picker.mediaTypes = @[(NSString *)kUTTypeImage, (NSString *)kUTTypeMovie];
	picker.delegate = (id<UIImagePickerControllerDelegate, UINavigationControllerDelegate>)self;
	[self presentViewController:picker animated:YES completion:nil];
}

/// One fix, then stop - a chat wants a pin, not a running trace.
- (void)sendCurrentLocation {
	if (!self.locationManager){
		self.locationManager = [[CLLocationManager alloc] init];
		self.locationManager.delegate = self;
		self.locationManager.desiredAccuracy = kCLLocationAccuracyHundredMeters;
	}
	[self.locationManager startUpdatingLocation];
}

- (void)locationManager:(CLLocationManager *)manager
	 didUpdateLocations:(NSArray *)locations {
	CLLocation *fix = [locations lastObject];
	[manager stopUpdatingLocation];
	if (!fix)
		return;
	[[TGClient shared] sendLocation:fix.coordinate.latitude
						  longitude:fix.coordinate.longitude
							 toChat:self.chatId];
}

- (void)locationManager:(CLLocationManager *)manager didFailWithError:(NSError *)error {
	[manager stopUpdatingLocation];
	NSLog(@"location: %@", error);
}

- (void)pickContact {
	ABPeoplePickerNavigationController *picker =
			[[ABPeoplePickerNavigationController alloc] init];
	picker.peoplePickerDelegate = self;
	[self presentViewController:picker animated:YES completion:nil];
}

- (BOOL)peoplePickerNavigationController:(ABPeoplePickerNavigationController *)picker
      shouldContinueAfterSelectingPerson:(ABRecordRef)person {
	NSString *name = (__bridge_transfer NSString *)
			ABRecordCopyCompositeName(person);
	ABMultiValueRef phones = ABRecordCopyValue(person, kABPersonPhoneProperty);
	NSString *phone = ABMultiValueGetCount(phones) > 0
			? (__bridge_transfer NSString *)ABMultiValueCopyValueAtIndex(phones, 0)
			: nil;
	if (phones) CFRelease(phones);

	[picker dismissViewControllerAnimated:YES completion:nil];
	if (phone.length)
		[[TGClient shared] sendContactNamed:name phone:phone toChat:self.chatId];
	return NO;
}

- (void)peoplePickerNavigationControllerDidCancel:(ABPeoplePickerNavigationController *)picker {
	[picker dismissViewControllerAnimated:YES completion:nil];
}

- (void)imagePickerController:(UIImagePickerController *)picker
		didFinishPickingMediaWithInfo:(NSDictionary *)info
{
	[picker dismissViewControllerAnimated:YES completion:nil];

	NSURL *movie = info[UIImagePickerControllerMediaURL];
	if (movie){
		[[TGClient shared] sendVideoAtPath:movie.path toChat:self.chatId];
		return;
	}

	UIImage *image = info[UIImagePickerControllerOriginalImage];
	if (image)
		[self sendImage:image];
}

/// TDLib wants a path, so the picture is written to a temporary file first -
/// one per photo, since two sent in a row would otherwise overwrite each
/// other before the first has uploaded.
- (void)sendImage:(UIImage *)image {
	if (!image)
		return;
	CFUUIDRef uuid = CFUUIDCreate(NULL);
	NSString *name = (__bridge_transfer NSString *)CFUUIDCreateString(NULL, uuid);
	CFRelease(uuid);
	NSString *path = [NSTemporaryDirectory() stringByAppendingPathComponent:
			[NSString stringWithFormat:@"outgoing-%@.jpg", name]];
	if (![UIImageJPEGRepresentation(image, 0.85f) writeToFile:path atomically:YES]){
		NSLog(@"cannot stage the picked image");
		return;
	}
	[[TGClient shared] sendPhotoAtPath:path toChat:self.chatId];
}

- (void)imagePickerControllerDidCancel:(UIImagePickerController *)picker {
	[picker dismissViewControllerAnimated:YES completion:nil];
}

- (void)presentAddContactForMessage:(NSDictionary *)m {
	NSDictionary *contact = [m[@"contact"] isKindOfClass:NSDictionary.class] ? m[@"contact"] : nil;
	NSString *first = contact[@"firstName"];
	NSString *last = contact[@"lastName"];
	NSString *phone = contact[@"phoneNumber"];
	if (!first && !last && !phone) {
		NSArray *parts = [m[@"text"] componentsSeparatedByString:@"\n"];
		if (parts.count) {
			NSArray *names = [parts[0] componentsSeparatedByString:@" "];
			first = names[0];
			if (names.count > 1) last = names[1];
		}
		if (parts.count > 1) phone = parts[1];
	}

	ABRecordRef person = ABPersonCreate();
	if (first.length)
		ABRecordSetValue(person, kABPersonFirstNameProperty, (__bridge CFStringRef)first, NULL);
	if (last.length)
		ABRecordSetValue(person, kABPersonLastNameProperty, (__bridge CFStringRef)last, NULL);
	if (phone.length) {
		ABMutableMultiValueRef phoneMulti = ABMultiValueCreateMutable(kABMultiStringPropertyType);
		ABMultiValueAddValueAndLabel(phoneMulti, (__bridge CFStringRef)phone, kABPersonPhoneMainLabel, NULL);
		ABRecordSetValue(person, kABPersonPhoneProperty, phoneMulti, NULL);
		CFRelease(phoneMulti);
	}

	NSString *fullName = [NSString stringWithFormat:@"%@%@",
			first.length ? first : @"",
			(first.length && last.length) ? [NSString stringWithFormat:@" %@", last] : (last ?: @"")];
	if (!fullName.length) fullName = @"Contact";

	int64_t uid = [contact[@"userId"] longLongValue];
	UIImage *avatarImg = nil;
	if (uid != 0) {
		avatarImg = self.senderAvatars[@(uid)] ?: self.images[@(uid)];
	}
	if (!avatarImg) {
		int64_t senderId = [m[@"senderId"] longLongValue];
		if (senderId != 0) {
			avatarImg = self.senderAvatars[@(senderId)];
		}
	}
	if (!avatarImg) {
		NSString *initials = fullName.length ? [fullName substringToIndex:1] : @"?";
		avatarImg = [TGIcons avatarWithInitials:initials.uppercaseString size:120 colourId:uid ?: (int64_t)[fullName hash]];
	}
	if (avatarImg) {
		NSData *imgData = UIImagePNGRepresentation(avatarImg);
		if (imgData.length) {
			ABPersonSetImageData(person, (__bridge CFDataRef)imgData, NULL);
		}
	}

	ABUnknownPersonViewController *ctrl = [[ABUnknownPersonViewController alloc] init];
	ctrl.displayedPerson = person;
	ctrl.allowsAddingToAddressBook = YES;
	ctrl.allowsActions = YES;
	ctrl.unknownPersonViewDelegate = (id<ABUnknownPersonViewControllerDelegate>)self;
	CFRelease(person);

	[self.navigationController pushViewController:ctrl animated:YES];
}

- (UIView *)viewForZoomingInScrollView:(UIScrollView *)scrollView {
	return [scrollView viewWithTag:0xF118];
}

- (void)saveFullScreenImage:(UILongPressGestureRecognizer *)hold {
	if (hold.state != UIGestureRecognizerStateBegan || !self.fullScreenImage)
		return;
	UIImageWriteToSavedPhotosAlbum(self.fullScreenImage, self,
			@selector(image:didFinishSavingWithError:contextInfo:), NULL);
}

- (void)image:(UIImage *)image didFinishSavingWithError:(NSError *)error
  contextInfo:(void *)contextInfo {
	[TGAlertSheet showMessage:(error ? @"Could not save" : @"Saved to Camera Roll")
						title:nil inView:self.view];
}

/// Simple full-screen viewer: black backdrop, tap anywhere to dismiss.
- (void)showFullScreenImage:(UIImage *)image {
	UIWindow *window = [UIApplication sharedApplication].keyWindow;

	UIView *backdrop = [[UIView alloc] initWithFrame:window.bounds];
	backdrop.backgroundColor = [UIColor blackColor];
	backdrop.tag = 0xF117;

	// A scroll view is all zooming needs; a 4S has no room for a custom one.
	UIScrollView *zoom = [[UIScrollView alloc] initWithFrame:backdrop.bounds];
	zoom.minimumZoomScale = 1.0f;
	zoom.maximumZoomScale = 4.0f;
	zoom.delegate = self;
	zoom.showsHorizontalScrollIndicator = NO;
	zoom.showsVerticalScrollIndicator = NO;
	[backdrop addSubview:zoom];

	UIImageView *view = [[UIImageView alloc] initWithFrame:backdrop.bounds];
	view.contentMode = UIViewContentModeScaleAspectFit;
	view.image = image;
	view.tag = 0xF118;
	[zoom addSubview:view];

	UITapGestureRecognizer *tap = [[UITapGestureRecognizer alloc]
			initWithTarget:self action:@selector(dismissFullScreen:)];
	[backdrop addGestureRecognizer:tap];

	// Hold the picture to keep it - the only way out of the app for an image.
	self.fullScreenImage = image;
	UILongPressGestureRecognizer *hold = [[UILongPressGestureRecognizer alloc]
			initWithTarget:self action:@selector(saveFullScreenImage:)];
	[backdrop addGestureRecognizer:hold];

	UILabel *hint = [[UILabel alloc] initWithFrame:
			CGRectMake(0, backdrop.bounds.size.height - 34, backdrop.bounds.size.width, 20)];
	hint.text = @"Hold to save";
	hint.font = TGFontMeta();
	hint.textAlignment = NSTextAlignmentCenter;
	hint.textColor = [UIColor colorWithWhite:1 alpha:0.6f];
	hint.backgroundColor = [UIColor clearColor];
	[backdrop addSubview:hint];

	backdrop.alpha = 0;
	[window addSubview:backdrop];
	[UIView animateWithDuration:0.2 animations:^{ backdrop.alpha = 1; }];
}

- (void)dismissFullScreen:(UITapGestureRecognizer *)tap {
	UIView *backdrop = tap.view;
	[UIView animateWithDuration:0.2 animations:^{ backdrop.alpha = 0; }
					 completion:^(BOOL done){ [backdrop removeFromSuperview]; }];
}

- (void)openChatWithUsername:(NSString *)username {
	if (!username.length) return;
	__weak typeof(self) weakSelf = self;
	[[TGClient shared] chatWithUsername:username completion:^(int64_t chatId, NSString *title){
		TGChatViewController *me = weakSelf;
		if (!me) return;
		if (!chatId) {
			[TGSnackbar showInView:me.navigationController.view
							  text:[NSString stringWithFormat:@"No such account: @%@", username]
						   seconds:2 onCommit:nil];
			return;
		}
		TGChatViewController *chatVC = [[TGChatViewController alloc] init];
		chatVC.chatId = chatId;
		chatVC.chatTitle = title.length ? title : username;
		chatVC.hidesBottomBarWhenPushed = YES;
		[me.navigationController pushViewController:chatVC animated:YES];
	}];
}

- (void)handleOpenLink:(NSString *)urlStr {
	if (!urlStr.length) return;

	NSString *clean = [urlStr stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];

	// @mention directly
	if ([clean hasPrefix:@"@"]) {
		[self openChatWithUsername:[clean substringFromIndex:1]];
		return;
	}

	NSURL *u = [NSURL URLWithString:clean];
	if (!u.scheme.length) {
		u = [NSURL URLWithString:[NSString stringWithFormat:@"http://%@", clean]];
	}

	NSString *host = u.host.lowercaseString;
	NSString *scheme = u.scheme.lowercaseString;

	BOOL isTelegramHost = [host isEqualToString:@"t.me"] || [host isEqualToString:@"telegram.me"] || [host isEqualToString:@"telegram.dog"];
	BOOL isTelegramScheme = [scheme isEqualToString:@"tg"];

	if (isTelegramHost || isTelegramScheme) {
		NSString *inviteHash = nil;
		if (isTelegramHost) {
			NSString *path = u.path;
			if ([path hasPrefix:@"/+"]) {
				inviteHash = [path substringFromIndex:2];
			} else if ([path hasPrefix:@"/joinchat/"]) {
				inviteHash = [path substringFromIndex:10];
			}
		} else if (isTelegramScheme && [host isEqualToString:@"join"]) {
			for (NSString *param in [u.query componentsSeparatedByString:@"&"]) {
				NSArray *kv = [param componentsSeparatedByString:@"="];
				if (kv.count == 2 && [kv[0] isEqualToString:@"invite"]) {
					inviteHash = kv[1];
					break;
				}
			}
		}

		if (inviteHash.length) {
			__weak typeof(self) weakSelf = self;
			[[TGClient shared] joinChatByInviteLink:clean completion:^(int64_t chatId, NSString *title) {
				TGChatViewController *me = weakSelf;
				if (!me) return;
				if (chatId != 0) {
					TGChatViewController *chatVC = [[TGChatViewController alloc] init];
					chatVC.chatId = chatId;
					chatVC.chatTitle = title.length ? title : @"Chat";
					chatVC.hidesBottomBarWhenPushed = YES;
					[me.navigationController pushViewController:chatVC animated:YES];
				} else {
					[TGSnackbar showInView:me.navigationController.view
									  text:@"Could not join chat" seconds:2 onCommit:nil];
				}
			}];
			return;
		}

		NSString *username = nil;
		if (isTelegramHost) {
			NSString *path = u.path;
			if ([path hasPrefix:@"/"]) path = [path substringFromIndex:1];
			NSRange slash = [path rangeOfString:@"/"];
			username = (slash.location != NSNotFound) ? [path substringToIndex:slash.location] : path;
		} else if (isTelegramScheme) {
			for (NSString *param in [u.query componentsSeparatedByString:@"&"]) {
				NSArray *kv = [param componentsSeparatedByString:@"="];
				if (kv.count == 2 && [kv[0] isEqualToString:@"domain"]) {
					username = kv[1];
					break;
				}
			}
		}

		if (username.length && ![username isEqualToString:@"joinchat"] && ![username hasPrefix:@"+"]) {
			[self openChatWithUsername:username];
			return;
		}
	}

	if (u) {
		[[UIApplication sharedApplication] openURL:u];
	}
}

@end
