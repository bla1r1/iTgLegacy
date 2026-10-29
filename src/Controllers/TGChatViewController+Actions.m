#import "TGChatViewControllerInternal.h"
#import "TGForwardPicker.h"
#import "TGPopupMenu.h"
#import "TGStyle.h"
#import "TGAlertSheet.h"
#import "TGReactionPicker.h"

/// What the reply strip shows on its second line. The rows here are already
/// flattened, so TGMessagePreview - which reads a raw TDLib content - cannot
/// be used; a media row carries no text and is named by its kind instead.
static NSString *TGComposePreview(NSDictionary *m) {
	return TGDescribeMessageContent(m);
}

/// The poll's vote graph as lines this OS can draw in a sheet. TDLib hands
/// statisticalGraphData over as a JSON chart: one columns entry per series,
/// its first element naming the answer, the rest counting the votes each
/// bucket took. Whatever the chart says the reader cannot hold falls back
/// to the options' own share the bubble already knows, so the sheet is
/// honest even when the graph arrives in a spelling this file never saw.
static NSString *TGPollGraphLines(NSString *json, NSArray *options) {
	NSData *data = [json dataUsingEncoding:NSUTF8StringEncoding];
	NSDictionary *chart = data.length
			? [NSJSONSerialization JSONObjectWithData:data
					options:NSJSONReadingAllowFragments error:nil] : nil;
	NSArray *columns = [chart isKindOfClass:NSDictionary.class]
			? chart[@"columns"] : nil;
	NSArray *labels = [chart isKindOfClass:NSDictionary.class]
			? (chart[@"labels"] ?: chart[@"x"]) : nil;

	NSMutableString *out = [NSMutableString string];
	if ([columns isKindOfClass:NSArray.class] && columns.count){
		for (NSUInteger i = 1; i < columns.count; i++){
			NSArray *series = [columns[i] isKindOfClass:NSArray.class]
					? columns[i] : nil;
			if (!series || !series.count)
				continue;
			NSString *name = [series[0] isKindOfClass:NSString.class]
					? series[0]
					: [NSString stringWithFormat:@"Answer %lu",
							(unsigned long)i];
			NSInteger votes = 0;
			for (NSUInteger j = 1; j < series.count; j++)
				votes += (NSInteger)[series[j] doubleValue];
			NSString *title = nil;
			NSInteger k = (NSInteger)i - 1;
			if (k >= 0 && k < (NSInteger)options.count){
				NSDictionary *option = options[k];
				id ot = option[@"text"];
				title = [ot isKindOfClass:[NSDictionary class]] ? (ot[@"text"] ?: @"") : ([ot isKindOfClass:[NSString class]] ? (NSString *)ot : @"");
			}
			NSString *who = [title isKindOfClass:NSString.class] && title.length
					? title : name;
			[out appendFormat:@"%@ · %ld votes\n", who, (long)votes];
		}
		if ([labels isKindOfClass:NSArray.class] && labels.count)
			[out appendFormat:@"\n%lu time slices", (unsigned long)labels.count];
		return out.length ? out : nil;
	}

	// The chart said nothing this reader could hold: the options' own
	// percentages from the bubble, which are the same story told plainer.
	for (NSDictionary *option in options){
		id ot = option[@"text"];
		NSString *title = [ot isKindOfClass:[NSDictionary class]] ? (ot[@"text"] ?: @"") : ([ot isKindOfClass:[NSString class]] ? (NSString *)ot : @"?");
		NSString *counts = option[@"voter_count"]
				? [NSString stringWithFormat:@" · %ld votes",
						(long)[option[@"voter_count"] integerValue]]
				: @"";
		[out appendFormat:@"%@%@ · %ld%%\n", title, counts,
				(long)[option[@"vote_percentage"] integerValue]];
	}
	return out.length ? out : nil;
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
		[self showActionsForRow:path.row
						atPoint:[hold locationInView:self.view]];
}

/// Split out from the gesture so itglegacy://holdrow/N can reach it: a long
/// press cannot be delivered through a URL. With no finger to go by, the
/// menu falls back to the corner of the bubble.
- (void)showActionsForRow:(NSInteger)row {
	[self showActionsForRow:row atPoint:CGPointZero];
}

/// `point` is where the finger is, in this view's coordinates, and the menu
/// opens there. CGPointZero means there was no finger - a URL asked for this
/// - and the bubble's own corner stands in.
- (void)showActionsForRow:(NSInteger)row atPoint:(CGPoint)point {
	if (row < 0) {
		row = (NSInteger)self.messages.count + row;
	}
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

	[items addObject:@{@"title" : @"Reply", @"icon" : @"reply"}];

	if ([m[@"text"] length])
		[items addObject:@{@"title" : @"Copy", @"icon" : @"copy"}];

	// A caption is edited by its own request, which is why only text could be
	// edited before: media with a caption got no Edit row at all.
	if (mine && ([m[@"text"] length] || [m[@"photoId"] isKindOfClass:NSNumber.class]))
		[items addObject:@{@"title" : @"Edit", @"icon" : @"edit"}];

	if (![m[@"service"] boolValue])
		[items addObject:@{@"title" : (heldId == self.pinnedMessageId ? @"Unpin" : @"Pin"),
						   @"icon" : @"pin"}];

	[items addObject:@{@"title" : @"Forward", @"icon" : @"forward"}];

	// One reaction at a time is what TDLib allows here, so the menu either
	// offers to remove yours or the reaction bar at top lets you pick one.
	if (myReaction.length)
		[items addObject:@{@"title" : [NSString stringWithFormat:
				@"Remove %@", myReaction], @"icon" : @"react"}];

	[items addObject:@{@"title" : @"Copy Link", @"icon" : @"copy"}];

	// Closing a poll is the sender's to do, and only while it is still open.
	if (mine && [m[@"pollOptions"] count] && ![m[@"pollClosed"] boolValue])
		[items addObject:@{@"title" : @"Stop Poll", @"icon" : @"select"}];
	// A live pin of your own stays on the map until you take it off.
	if (mine && [m[@"kind"] isEqualToString:@"messageLiveLocation"]
			 && [m[@"liveEditable"] boolValue])
		[items addObject:@{@"title" : @"Stop Live Location", @"icon" : @"delete",
						   @"destructive" : @YES}];
	// A poll's crowd and its options: voters answered, an option made after
	// the fact, an option taken out of it.
	if ([m[@"pollOptions"] count]){
		if ([m[@"pollClosed"] boolValue] || [m[@"pollVoters"] boolValue])
			[items addObject:@{@"title" : @"Poll Voters", @"icon" : @"select"}];
		if ([m[@"pollStats"] boolValue])
			[items addObject:@{@"title" : @"Poll Statistics", @"icon" : @"data"}];
		if (mine && [m[@"pollOpen"] boolValue])
			[items addObject:@{@"title" : @"Add Option", @"icon" : @"edit"}];
		if (mine && [m[@"pollOpen"] boolValue] && [m[@"pollDeletable"] boolValue])
			[items addObject:@{@"title" : @"Delete Option", @"icon" : @"delete",
							   @"destructive" : @YES}];
	}
	// A sticker you are holding is a sticker you may want to keep.
	if ([m[@"kind"] isEqualToString:@"messageSticker"] && TGStickerFileId(m) > 0)
		[items addObject:@{@"title" : @"Add to Favourites", @"icon" : @"pin"}];
	// Someone else's message in a group is the only place a spam report has
	// anywhere to go: reportSupergroupSpam wants a supergroup behind it.
	if (!mine && self.isGroup)
		[items addObject:@{@"title" : @"Report Spam", @"icon" : @"privacy",
						   @"destructive" : @YES}];
	// A reaction the flattening could name - the person, not only the
	// emoji - is one confirm away from the report TDLib asks for.
	NSDictionary *reactionReport = m[@"reactionReport"];
	if (reactionReport && ![reactionReport isKindOfClass:NSNull.class] && !mine)
		[items addObject:@{@"title" : @"Report Reaction", @"icon" : @"privacy",
						   @"destructive" : @YES}];
	if (mine)
		[items addObject:@{@"title" : @"Delete", @"icon" : @"delete",
						   @"destructive" : @YES}];

	[items addObject:@{@"title" : @"Select", @"icon" : @"select"}];

	// Beside the message rather than over the whole screen, which is what
	// makes it read as belonging to that bubble.
	// Where the finger is. This used to anchor on the bottom edge of the row
	// whatever the hold had touched, so holding the top of a tall bubble
	// opened the menu somewhere else entirely.
	CGPoint where = point;
	if (CGPointEqualToPoint(point, CGPointZero)){
		NSIndexPath *indexPath = [NSIndexPath indexPathForRow:row inSection:0];
		[self.table scrollToRowAtIndexPath:indexPath
						  atScrollPosition:UITableViewScrollPositionMiddle
								  animated:NO];
		CGRect rect = [self.table rectForRowAtIndexPath:indexPath];
		where = [self.table convertPoint:CGPointMake(
				mine ? CGRectGetMaxX(rect) - TGMetricMenuActionOffset
					 : TGMetricMenuActionOffset,
				CGRectGetMidY(rect)) toView:self.view];
	}

	NSArray *reactions = [TGReactionPicker defaultReactions];
	__weak typeof(self) weakSelf = self;
	[TGPopupMenu showItems:items
				   atPoint:where
					inView:self.view
				 reactions:reactions
		  selectedReaction:myReaction
				onReaction:^(NSString *emoji) {
		TGChatViewController *me = weakSelf;
		if (!me) return;
		if ([emoji isEqualToString:myReaction]) {
			[[TGClient shared] removeReaction:myReaction fromMessage:heldId inChat:me.chatId];
		} else {
			[[TGClient shared] reactTo:heldId inChat:me.chatId emoji:emoji];
		}
		[me reload];
	} onChoice:^(NSInteger index, NSString *title) {
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

	} else if ([action isEqualToString:@"Stop Poll"]){
		__weak typeof(self) weakSelf = self;
		[TGAlertSheet showConfirm:@"Nobody can vote after this, and the result "
								  @"stands as it is."
							title:@"Stop Poll"
						   action:@"Stop"
					  destructive:YES
						   inView:self.view
						onConfirm:^{
			[[TGClient shared] stopPoll:messageId inChat:weakSelf.chatId];
		}];

	} else if ([action isEqualToString:@"Stop Live Location"]){
		// The pin comes off the map: an edit whose period says zero, which
		// is what ending a live location is on the wire.
		int64_t chatId = self.chatId;
		__weak typeof(self) weakSelf = self;
		[TGAlertSheet showConfirm:@"Your location stops updating for everyone, "
								  @"right now."
							title:@"Stop Live Location"
						   action:@"Stop"
					  destructive:YES
						   inView:self.view
						onConfirm:^{
			[[TGClient shared] editLiveLocationOfMessage:messageId
												  inChat:chatId
												latitude:0.0
											   longitude:0.0
											  livePeriod:0
											  completion:nil];
			TGChatViewController *me = weakSelf;
			if (me){
				me.liveLocationMessageId = 0;
				me.liveLocationSeconds = 0;
				[me.locationManager stopUpdatingLocation];
			}
		}];
	} else if ([action isEqualToString:@"Poll Voters"]){
		// Who voted which way: the answers first, the people behind one of
		// them next. A poll without answers to look at says so.
		NSArray *options = m[@"pollOptions"];
		NSMutableArray *titles = [NSMutableArray array];
		for (NSDictionary *option in options) {
			id ot = option[@"text"];
			NSString *otStr = [ot isKindOfClass:[NSDictionary class]] ? (ot[@"text"] ?: @"") : ([ot isKindOfClass:[NSString class]] ? (NSString *)ot : @"?");
			[titles addObject:otStr];
		}
		if (!titles.count){
			[TGAlertSheet showMessage:@"This poll has no answers to look "
									  @"behind." title:@"Poll Voters"
								inView:self.view];
			return;
		}
		int64_t chatId = self.chatId;
		__weak typeof(self) weakSelf = self;
		[TGAlertSheet showChoices:titles
							title:m[@"pollQuestion"] ?: @"Poll"
				 destructiveIndex:-1
						   inView:self.view
						 onChoice:^(NSInteger index){
			[[TGClient shared] pollVotersOfOption:index ofMessage:messageId inChat:chatId
									   completion:^(NSArray *voters, BOOL end){
				TGChatViewController *me = weakSelf;
				if (!me)
					return;
				if (!voters.count){
					[TGAlertSheet showMessage:@"Nobody voted for that."
										title:@"Poll Voters" inView:me.view];
					return;
				}
				NSMutableArray *rows = [NSMutableArray array];
				for (NSDictionary *voter in voters)
					[rows addObject:voter[@"name"] ?: @"?"];
				NSString *head = [NSString stringWithFormat:@"%@ · %lu%@",
						titles[index], (unsigned long)voters.count,
						end ? @"" : @"…"];
				[TGAlertSheet showChoices:rows
									title:head
						 destructiveIndex:-1
								   inView:me.view
								 onChoice:^(NSInteger pick){}];
			}];
		}];

	} else if ([action isEqualToString:@"Poll Statistics"]){
		// The graph of votes gathered in as the poll ran. TDLib hands the
		// chart over as a JSON string; whatever it holds, the sheet reads
		// every column it recognises into a line per option, worst case a
		// sentence instead of a chart.
		int64_t pollChatId = self.chatId;
		__weak typeof(self) weakSelf = self;
		[[TGClient shared] pollVoteStatisticsOfMessage:messageId
												inChat:pollChatId
											completion:^(NSDictionary *graph){
			TGChatViewController *me = weakSelf;
			if (!me)
				return;
			if (!graph){
				[TGAlertSheet showMessage:@"Statistics are not there yet."
									title:@"Poll Statistics"
								   inView:me.view];
				return;
			}
					NSString *lines = TGPollGraphLines(graph[@"json"],
					m[@"pollOptions"]);
			NSString *body = [lines isKindOfClass:NSString.class] && lines.length
					? lines
					: @"Statistics came back as numbers this page cannot "
					@"read. The options' own share still shows in the poll.";
			[TGAlertSheet showMessage:body
								title:m[@"pollQuestion"] ?: @"Poll Statistics"
								   inView:me.view];
		}];

	} else if ([action isEqualToString:@"Add Option"]){
		// A poll that grew after the fact: the line asked for, sent, and the
		// message re-answered by the update the client does not watch for.
		int64_t chatId = self.chatId;
		__weak typeof(self) weakSelf = self;
		[TGAlertSheet showInput:@"Add Option"
						message:nil
					placeholder:@"New answer"
						   text:nil
						 action:@"Add"
						 inView:self.view
					   onSubmit:^(NSString *text){
			NSString *what = [text stringByTrimmingCharactersInSet:
					[NSCharacterSet whitespaceAndNewlineCharacterSet]];
			[[TGClient shared] addPollOption:what toMessage:messageId inChat:chatId
								  completion:^(BOOL ok){
				TGChatViewController *me = weakSelf;
				if (!ok)
					[TGAlertSheet showMessage:@"Telegram refused the new answer - "
											  @"this poll does not grow."
										title:@"Add Option" inView:me.view];
			}];
		}];

	} else if ([action isEqualToString:@"Delete Option"]){
		// The answer taken out: the options with votes on them are not this
		// menu's to guess at - the server owns the refusal, this sheet owns
		// the confirm.
		NSArray *options = m[@"pollOptions"];
		NSMutableArray *titles = [NSMutableArray array];
		for (NSDictionary *option in options) {
			id ot = option[@"text"];
			NSString *otStr = [ot isKindOfClass:[NSDictionary class]] ? (ot[@"text"] ?: @"") : ([ot isKindOfClass:[NSString class]] ? (NSString *)ot : @"?");
			[titles addObject:otStr];
		}
		int64_t chatId = self.chatId;
		__weak typeof(self) weakSelf = self;
		[TGAlertSheet showChoices:titles
							title:m[@"pollQuestion"] ?: @"Poll"
				 destructiveIndex:-1
						   inView:self.view
						 onChoice:^(NSInteger index){
			NSString *optionId = (NSString *)options[index][@"id"];
			NSString *which = titles[index];
			[TGAlertSheet showConfirm:[NSString stringWithFormat:
					@"The answer \"%@\" is removed from the poll, along "
					@"with what it collected so far.", which]
								title:@"Delete Option"
							   action:@"Delete"
						  destructive:YES
							   inView:weakSelf.view
							onConfirm:^{
				[[TGClient shared] deletePollOption:optionId
										  ofMessage:messageId
											 inChat:chatId
										 completion:^(BOOL ok){
					TGChatViewController *me = weakSelf;
					if (!ok)
						[TGAlertSheet showMessage:@"Telegram refused to remove "
												  @"that answer."
											title:@"Delete Option" inView:me.view];
				}];
			}];
		}];

	} else if ([action isEqualToString:@"Report Spam"]){
		int64_t chatId = self.chatId;
		__weak typeof(self) weakSelf = self;
		[TGAlertSheet showChoices:@[@"Report", @"Report and Block Sender"]
							title:@"Report Spam"
						  message:@"Telegram's moderators see the message. "
								  @"Blocking also stops them replying to you "
								  @"again."
				 destructiveIndex:1
						   inView:self.view
						 onChoice:^(NSInteger index){
			TGChatViewController *me = weakSelf;
			if (index == 1)
				[[TGClient shared] blockSenderOfMessage:messageId
										 deleteMessages:YES
											 reportSpam:YES];
			[[TGClient shared] reportSpamMessages:@[@(messageId)]
										   inChat:chatId
									   completion:^(BOOL ok){
				[TGSnackbar showInView:me.view
								  text:(ok ? @"Reported" : @"Telegram refused that")
							   seconds:2 onCommit:nil];
			}];
		}];

	} else if ([action isEqualToString:@"Report Reaction"]){
		// The flattening decided who is being reported: the latest reactor
		// the message named, with the emoji it put on this bubble.
		NSDictionary *choice = m[@"reactionReport"];
		if (![choice isKindOfClass:NSDictionary.class])
			return;
		int64_t reactionChatId = self.chatId;
		NSString *who = nil;
		if ([choice[@"name"] isKindOfClass:NSString.class]){
			NSString *name = choice[@"name"];
			who = name.length ? name : @"someone";
		} else {
			who = @"someone";
		}
		__weak typeof(self) weakSelf = self;
		NSString *note = [NSString stringWithFormat:
				@"The %@ reaction by %@ is reported. Telegram's moderators "
				@"see the message and the reaction.",
				choice[@"emoji"] ?: @"", who];
		[TGAlertSheet showConfirm:note
							title:@"Report Reaction"
						   action:@"Report"
					  destructive:YES
						   inView:self.view
						onConfirm:^{
			[[TGClient shared] reportReactionBySender:choice[@"sender"]
											ofMessage:messageId
												inChat:reactionChatId
										 completion:^(BOOL ok){
				TGChatViewController *me = weakSelf;
				if (!me)
					return;
				[TGSnackbar showInView:me.view
								  text:(ok ? @"Reaction reported"
										   : @"Telegram refused that")
							   seconds:2 onCommit:nil];
			}];
		}];

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
		// Media carries a caption, and a caption is not text: the commit has
		// to know which request to send.
		self.editingIsCaption = [m[@"photoId"] isKindOfClass:NSNumber.class] ||
								[m[@"docId"] isKindOfClass:NSNumber.class];
		NSString *fallback = m[@"text"];
		self.input.text = fallback;
		[self showComposeBanner:self.editingIsCaption ? @"Editing caption" : @"Editing"];
		[self.input becomeFirstResponder];
		// What Telegram puts back as markdown is what the sender typed, and
		// it arrives late: the render is already in the composer, and whatever
		// Telegram says the origin was replaces it - unless another tap has
		// typed over the fallback already.
		int64_t chatId = self.chatId;
		__weak typeof(self) weakSelf = self;
		[[TGClient shared] markdownOfMessage:messageId inChat:chatId
								  completion:^(NSString *markdown){
			TGChatViewController *me = weakSelf;
			NSString *current = me.input.text;
			if (!me || me.editingId != messageId)
				return;
			if ([current isEqualToString:fallback] && markdown.length)
				me.input.text = markdown;
		}];

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

/// One fix, or a trace that keeps moving: the sheet is where the two live
/// apart, the trace with the period a live location is allowed.
- (void)sendCurrentLocation {
	if (!self.locationManager){
		self.locationManager = [[CLLocationManager alloc] init];
		self.locationManager.delegate = self;
		self.locationManager.desiredAccuracy = kCLLocationAccuracyHundredMeters;
	}
	__weak typeof(self) weakSelf = self;
	[TGAlertSheet showChoices:@[@"Share a Fixed Pin", @"Share Live Location..."]
						title:nil
			 destructiveIndex:-1
					   inView:self.view
					 onChoice:^(NSInteger index){
		if (index == 0)
			[weakSelf startLocationUpdates];
		else {
			[TGAlertSheet showChoices:@[@"for 15 minutes", @"for 1 hour", @"for 8 hours"]
								title:@"Live for..."
					 destructiveIndex:-1
							   inView:weakSelf.view
							 onChoice:^(NSInteger periodIndex){
				weakSelf.liveLocationSeconds =
						periodIndex == 0 ? 15 * 60 : (periodIndex == 1 ? 3600 : 28800);
				weakSelf.liveLocationMessageId = 0;
				weakSelf.liveLocationRestarts = 0;
				[weakSelf startLocationUpdates];
			}];
		}
	}];
}

/// The manager itself runs until it has what its caller needs: one fix ends
/// it, a live trace keeps it going until the pin is stopped.
- (void)startLocationUpdates {
	if ([self.locationManager respondsToSelector:@selector(requestWhenInUseAuthorization)])
		[self.locationManager requestWhenInUseAuthorization];
	[self.locationManager startUpdatingLocation];
}

- (void)locationManager:(CLLocationManager *)manager
	 didUpdateLocations:(NSArray *)locations {
	CLLocation *fix = [locations lastObject];
	if (!fix)
		return;
	double lat = fix.coordinate.latitude, lon = fix.coordinate.longitude;

	if (self.liveLocationSeconds){
		// Live: the first fix makes the message, the rest move it - and the
		// queued-up fixes are dropped while TDLib has one in flight, since
		// each edit answers with the message in full.
		if (self.liveLocationInFlight)
			return;
		self.liveLocationInFlight = YES;
		int64_t chatId = self.chatId;
		NSInteger remaining = (NSInteger)(self.liveLocationSeconds -
				([[NSDate date] timeIntervalSince1970] - self.liveLocationSince));
		if (remaining < 1)
			remaining = 0;
		__weak typeof(self) weakSelf = self;
		if (self.liveLocationMessageId){
			[[TGClient shared] editLiveLocationOfMessage:self.liveLocationMessageId
												  inChat:chatId
												latitude:lat
											   longitude:lon
											  livePeriod:remaining
											  completion:^(BOOL ok){
				TGChatViewController *me = weakSelf;
				if (!me)
					return;
				me.liveLocationInFlight = NO;
				if (!ok)
					me.liveLocationRestarts++;
			}];
			return;
		}
		self.liveLocationSince = [[NSDate date] timeIntervalSince1970];
		[[TGClient shared] sendLiveLocation:self.liveLocationSeconds
								   latitude:lat
								  longitude:lon
									 toChat:chatId
								  completion:^(int64_t messageId){
			TGChatViewController *me = weakSelf;
			if (!me)
				return;
			me.liveLocationInFlight = NO;
			me.liveLocationMessageId = messageId;
		}];
		return;
	}

	// Fixed: one fix is the pin, and the manager is done.
	[manager stopUpdatingLocation];
	[[TGClient shared] sendLocation:lat longitude:lon toChat:self.chatId];
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
	if (![UIImageJPEGRepresentation(image, TGCompressionQualityHigh) writeToFile:path atomically:YES]){
		NSLog(@"cannot stage the picked image");
		return;
	}
	[[TGClient shared] sendPhotoAtPath:path toChat:self.chatId];
}

/// Several pictures as one message. Each is staged on disk the way a single
/// one is - TDLib uploads from a file - and the album goes as one request, so
/// they arrive together instead of as a run that happens to be adjacent.
- (void)sendImageAlbum:(NSArray *)images {
	if (!images.count)
		return;
	NSMutableArray *paths = [NSMutableArray array];
	for (UIImage *image in images){
		if (![image isKindOfClass:UIImage.class])
			continue;
		CFUUIDRef uuid = CFUUIDCreate(NULL);
		NSString *name = (__bridge_transfer NSString *)CFUUIDCreateString(NULL, uuid);
		CFRelease(uuid);
		NSString *path = [NSTemporaryDirectory() stringByAppendingPathComponent:
				[NSString stringWithFormat:@"outgoing-%@.jpg", name]];
		if ([UIImageJPEGRepresentation(image, TGCompressionQualityHigh) writeToFile:path atomically:YES])
			[paths addObject:path];
	}
	if (!paths.count){
		NSLog(@"cannot stage the picked album");
		return;
	}
	// Whatever is in the composer rides along as the album's caption, which
	// is where their client puts it too.
	NSString *caption = [self.input.text stringByTrimmingCharactersInSet:
			[NSCharacterSet whitespaceAndNewlineCharacterSet]];
	if (caption.length){
		self.input.text = @"";
		[self inputChanged];
	}
	[[TGClient shared] sendPhotoAlbumAtPaths:paths
									 caption:caption
									  toChat:self.chatId
									  thread:self.threadId];
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
		avatarImg = [TGIcons avatarWithInitials:initials.uppercaseString
										   size:TGMetricCallAvatarSide
									   colourId:uid ?: (int64_t)[fullName hash]];
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
	zoom.minimumZoomScale = TGMetricZoomMin;
	zoom.maximumZoomScale = TGMetricZoomMax;
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
			CGRectMake(0, backdrop.bounds.size.height - TGMetricImageHintBottomOffset,
					backdrop.bounds.size.width, TGMetricLineRow)];
	hint.text = @"Hold to save";
	hint.font = TGFontMeta();
	hint.textAlignment = NSTextAlignmentCenter;
	hint.textColor = [[TGTheme shared] secondaryTextColour];
	hint.backgroundColor = [UIColor clearColor];
	[backdrop addSubview:hint];

	backdrop.alpha = TGAlphaTransparent;
	[window addSubview:backdrop];
	[UIView animateWithDuration:TGAnimationDurationNormal animations:^{ backdrop.alpha = TGAlphaOpaque; }];
}

- (void)dismissFullScreen:(UITapGestureRecognizer *)tap {
	UIView *backdrop = tap.view;
	[UIView animateWithDuration:TGAnimationDurationNormal animations:^{ backdrop.alpha = 0; }
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
		// Telegram knows what its own links mean; this screen used to guess
		// from the path, which read t.me/addstickers/foo as a chat called
		// "addstickers". The guess is still the fallback, because an answer
		// takes a round trip and some links genuinely have no kind.
		__weak typeof(self) weakSelf = self;
		[[TGClient shared] internalLinkKind:clean
								 completion:^(NSString *kind, NSString *value){
			TGChatViewController *me = weakSelf;
			if (!me)
				return;
			if ([kind isEqualToString:@"publicChat"] && value.length){
				[me openChatWithUsername:value];
				return;
			}
			if ([kind isEqualToString:@"inviteLink"] && value.length){
				[me joinChatByInviteLink:value];
				return;
			}
			if ([kind isEqualToString:@"stickerSet"] && value.length){
				// A sticker set is not a chat, and opening one as a chat is
				// what this did before. The pack's record comes in with the
				// id and the count the sheet needs, and Telegram's answer
				// says whether this account already has it.
				[me askForStickerSet:value];
				return;
			}
			if ([kind isEqualToString:@"phoneNumber"] && value.length){
				[me openChatWithPhoneNumber:value];
				return;
			}
			if ([kind isEqualToString:@"deepLink"] && value.length){
				[TGAlertSheet showMessage:value
									title:@"LegacyTG"
									inView:me.navigationController.view ?: me.view];
				return;
			}
			// Anything Telegram has no kind for falls through to the paths
			// this screen has always matched by hand.
			[me openTelegramLinkByPath:clean url:u
							isTelegramHost:isTelegramHost
						  isTelegramScheme:isTelegramScheme
									  host:host];
		}];
		return;
	}

	[self openPlainLink:u];
}

/// Joining by a link, with the snackbar the tap used to get inline.
- (void)joinChatByInviteLink:(NSString *)link {
	__weak typeof(self) weakSelf = self;
	[[TGClient shared] joinChatByInviteLink:link completion:^(int64_t chatId,
															 NSString *title){
		TGChatViewController *me = weakSelf;
		if (!me) return;
		if (chatId != 0){
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
}

/// A pack met through a link, offered the way their clients offer it: named,
/// counted, and installed on one confirm.
- (void)askForStickerSet:(NSString *)shortName {
	__weak typeof(self) weakSelf = self;
	[[TGClient shared] stickerSetByShortName:shortName completion:^(NSDictionary *set){
		TGChatViewController *me = weakSelf;
		if (!me)
			return;
		if (!set){
			[TGSnackbar showInView:me.navigationController.view ?: me.view
							  text:@"Telegram does not know that pack"
						   seconds:2 onCommit:nil];
			return;
		}
		NSString *title = [set[@"title"] length] ? set[@"title"] : shortName;
		if ([set[@"installed"] boolValue]){
			[TGSnackbar showInView:me.navigationController.view ?: me.view
							  text:[NSString stringWithFormat:@"%@ is already installed", title]
						   seconds:2 onCommit:nil];
			return;
		}
		NSString *counted = [NSString stringWithFormat:@"%@ - %lu stickers",
				title, (unsigned long)[set[@"count"] unsignedIntegerValue]];
		__weak typeof(self) weakSelf = self;
		[TGAlertSheet showChoices:@[@"Install"]
							title:counted
				  destructiveIndex:-1
							inView:me.navigationController.view ?: me.view
						  onChoice:^(NSInteger index){
			TGChatViewController *me = weakSelf;
			[[TGClient shared] setStickerSet:set[@"id"] installed:YES archived:NO];
			[TGSnackbar showInView:me ? (me.navigationController.view ?: me.view) : nil
							  text:[NSString stringWithFormat:@"%@ installed", title]
						   seconds:2 onCommit:nil];
		}];
	}];
}

/// Someone by their number, which a tg://resolve link can carry instead of a
/// username.
- (void)openChatWithPhoneNumber:(NSString *)phone {
	__weak typeof(self) weakSelf = self;
	[[TGClient shared] userForPhone:phone completion:^(NSDictionary *user){
		TGChatViewController *me = weakSelf;
		int64_t userId = [user[@"id"] longLongValue];
		if (!me || !userId){
			[TGSnackbar showInView:me.navigationController.view ?: me.view
							  text:@"No Telegram account on that number"
						   seconds:2 onCommit:nil];
			return;
		}
		[[TGClient shared] privateChatWithUser:userId completion:^(int64_t chatId){
			if (!chatId)
				return;
			TGChatViewController *chatVC = [[TGChatViewController alloc] init];
			chatVC.chatId = chatId;
			chatVC.chatTitle = [[TGClient shared] nameForUserId:userId] ?: phone;
			chatVC.hidesBottomBarWhenPushed = YES;
			[me.navigationController pushViewController:chatVC animated:YES];
		}];
	}];
}

/// The paths this screen has always matched by hand, now the fallback for a
/// link Telegram gave no kind for.
- (void)openTelegramLinkByPath:(NSString *)clean
						   url:(NSURL *)u
				isTelegramHost:(BOOL)isTelegramHost
			  isTelegramScheme:(BOOL)isTelegramScheme
						  host:(NSString *)host {
	{
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
			[self joinChatByInviteLink:clean];
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

	[self openPlainLink:u];
}

/// Anything that is not a Telegram link: Safari, which is the whole of what
/// this app does with the web.
- (void)openPlainLink:(NSURL *)url {
	if (url)
		[[UIApplication sharedApplication] openURL:url];
}

@end
