#import "TGChatViewControllerInternal.h"
#import "TGForwardPicker.h"
#import "TGPopupMenu.h"
#import "TGStyle.h"
#import "TGAlertSheet.h"
#import "TGReactionPicker.h"
#import "TGFastDate.h"
#import "TGOptions.h"
#import "TGClientInternal.h"
#import "TGInstantViewController.h"

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

/// The reaction Telegram names as the default leads their bar; the rest keep
/// the app's order. A default the message does not offer is left where it is,
/// because reacting with it would be refused.
- (NSArray *)reactionsWithDefaultFirst:(NSArray *)reactions {
	NSString *first = [TGClient shared].defaultReactionEmoji;
	if (!first.length || ![reactions containsObject:first])
		return reactions;
	NSMutableArray *out = [NSMutableArray arrayWithObject:first];
	for (NSString *emoji in reactions)
		if (![emoji isEqualToString:first])
			[out addObject:emoji];
	return out;
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

	// A caption is not the picture: replacing the picture itself is
	// editMessageMedia, and only the sender may.
	if (mine && [m[@"photoId"] isKindOfClass:NSNumber.class])
		[items addObject:@{@"title" : @"Replace Photo", @"icon" : @"react"}];

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

	// A dice or a ball is a message whose whole point is the tap.
	if ([m[@"kind"] isEqualToString:@"messageAnimatedEmoji"])
		[items addObject:@{@"title" : @"Click Emoji", @"icon" : @"react"}];
	// A bot's buttons are the message's furniture; a bot account can take
	// them off, and the row is where that interaction already lives.
	if ([m[@"inlineRows"] count])
		[items addObject:@{@"title" : @"Clear Buttons", @"icon" : @"delete",
						   @"destructive" : @YES}];
	// The record of the message itself: what is cached, where it sits, what
	// the channel's graphs say, and the view report TDLib wants.
	[items addObject:@{@"title" : @"Message Info", @"icon" : @"data"}];
	[items addObject:@{@"title" : @"Shared Media Map", @"icon" : @"data"}];
	if ([m[@"effectId"] longLongValue] > 0)
		[items addObject:@{@"title" : @"Message Effect", @"icon" : @"react"}];

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
	// The record of a post that left this account: who opened it, who
	// reacted, whether Telegram names the hand behind "Channel Admin".
	// Rows over-reach on purpose: the server refuses what the chat is not,
	// and the refusal is one honest sheet line.
	if (mine && ![[TGClient shared] chatIsSavedMessages:self.chatId])
		[items addObject:@{@"title" : @"Who Read This", @"icon" : @"select"}];
	[items addObject:@{@"title" : @"Public Forwards", @"icon" : @"forward"}];
	[items addObject:@{@"title" : @"Reactions", @"icon" : @"react"}];
	if (!mine)
		[items addObject:@{@"title" : @"Author", @"icon" : @"select"}];
	NSString *text = m[@"text"] ?: @"";
	if (text.length)
		[items addObject:@{@"title" : @"Translate", @"icon" : @"edit"}];
	if (text.length)
		[items addObject:@{@"title" : @"Find Quote", @"icon" : @"data"}];
	if ([text containsString:@"#"])
		[items addObject:@{@"title" : @"Search by Hashtag", @"icon" : @"data"}];
	if ([m[@"kind"] isEqualToString:@"messageLocation"] ||
			[m[@"kind"] isEqualToString:@"messageLiveLocation"])
		[items addObject:@{@"title" : @"Recent Locations", @"icon" : @"data"}];
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

	NSArray *reactions = [self reactionsWithDefaultFirst:[TGReactionPicker defaultReactions]];
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
		// A chat can forbid replies to this particular message; can_be_replied
		// is the server's word on it, and opening a composer that would be
		// refused is worse than one line saying so.
		__weak typeof(self) weakSelf = self;
		[[TGClient shared] messagePropertiesForChat:self.chatId
										  messageId:messageId
										 completion:^(NSDictionary *properties){
			TGChatViewController *me = weakSelf;
			if (!me)
				return;
			id allowed = properties[@"can_be_replied"];
			if (allowed && ![allowed boolValue]){
				[TGAlertSheet showMessage:@"Telegram does not allow a reply "
							@"to this message." title:@"Reply" inView:me.view];
				return;
			}
			me.replyToId = messageId;
			me.editingId = 0;
			NSString *who = [m[@"outgoing"] boolValue] ? @"You"
					: ([[TGClient shared] nameForUserId:
							[m[@"senderId"] longLongValue]] ?: @"Reply");
			[me showComposeBanner:who subtitle:TGComposePreview(m)];
			[me.input becomeFirstResponder];
		}];

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

	} else if ([action isEqualToString:@"Click Emoji"]){
		int64_t chatId = self.chatId;
		__weak typeof(self) weakSelf = self;
		[[TGClient shared] clickAnimatedEmojiMessage:messageId inChat:chatId
										 completion:^(NSString *emoji){
			TGChatViewController *me = weakSelf;
			if (!me)
				return;
			[TGSnackbar showInView:me.view
							  text:(emoji.length
									? [NSString stringWithFormat:@"%@ rolled", emoji]
									: @"No animation this time")
						   seconds:2 onCommit:nil];
		}];

	} else if ([action isEqualToString:@"Message Info"]){
		[self showInfoOfActionMessage];

	} else if ([action isEqualToString:@"Shared Media Map"]){
		[self showSparsePositionsOfActionMessage];

	} else if ([action isEqualToString:@"Clear Buttons"]){
		int64_t chatId = self.chatId;
		__weak typeof(self) weakSelf = self;
		[[TGClient shared] clearReplyMarkupOfMessage:messageId inChat:chatId
										 completion:^(BOOL ok){
			TGChatViewController *me = weakSelf;
			if (!me)
				return;
			[TGSnackbar showInView:me.view
							  text:(ok ? @"Buttons removed"
									   : @"Telegram refused that")
						   seconds:2 onCommit:nil];
		}];

	} else if ([action isEqualToString:@"Message Effect"]){
		int64_t effectId = [m[@"effectId"] longLongValue];
		__weak typeof(self) weakSelf = self;
		[[TGClient shared] messageEffectWithId:effectId
									completion:^(NSDictionary *effect){
			TGChatViewController *me = weakSelf;
			if (!me)
				return;
			if (!effect){
				[TGAlertSheet showMessage:@"Telegram has no effect with that id."
									title:@"Message Effect" inView:me.view];
				return;
			}
			NSString *premium = [effect[@"premium"] boolValue] ? @" (Premium)" : @"";
			[TGAlertSheet showMessage:[NSString stringWithFormat:@"%@%@",
					effect[@"emoji"] ?: @"", premium]
								title:@"Message Effect" inView:me.view];
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

	} else if ([action isEqualToString:@"Who Read This"]){
		[self showViewersOfActionMessage];

	} else if ([action isEqualToString:@"Public Forwards"]){
		[self showPublicForwardsOfActionMessage];

	} else if ([action isEqualToString:@"Reactions"]){
		[self showReactorsOfActionMessage];

	} else if ([action isEqualToString:@"Author"]){
		[self showAuthorOfActionMessage];

	} else if ([action isEqualToString:@"Translate"]){
		[self translateActionMessage];

	} else if ([action isEqualToString:@"Find Quote"]){
		[self findQuoteInActionMessage];

	} else if ([action isEqualToString:@"Search by Hashtag"]){
		NSString *query = m[@"text"] ?: @"";
		NSRange first = [query rangeOfString:@"#"];
		NSString *tag = [query substringFromIndex:first.location];
		NSString *clean = [[tag componentsSeparatedByCharactersInSet:
				[NSCharacterSet whitespaceAndNewlineCharacterSet]] firstObject]
				?: tag;
		// The in-chat search bar owns the results view; a hashtag rides it,
		// just typed for the user.
		[self toggleChatSearchOpenWithTag:clean ?: tag];

	} else if ([action isEqualToString:@"Recent Locations"]){
		[self showRecentLocationsInActionMessage];

	} else if ([action isEqualToString:@"Copy Embed Code"]){
		int64_t chatId = self.chatId;
		__weak typeof(self) weakSelf = self;
		[[TGClient shared] embeddingCodeOfMessage:messageId inChat:chatId
											album:[m[@"isAlbum"] boolValue]
									   completion:^(NSString *code){
			TGChatViewController *me = weakSelf;
			if (!me) return;
			if (!code.length){
				[TGSnackbar showInView:me.view
								  text:@"No embed for this message" seconds:2 onCommit:nil];
				return;
			}
			[UIPasteboard generalPasteboard].string = code;
			[TGSnackbar showInView:me.view text:@"Embed copied" seconds:2 onCommit:nil];
		}];

	} else if ([action isEqualToString:@"Replace Photo"]){
		self.editingId = messageId;
		self.editingIsCaption = NO;
		self.replacingPhoto = YES;
		self.replacingPhotoCaption = m[@"text"] ?: @"";
		[self pickReplacementPhoto];

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

/// One graph as a line: an error, a loading token, or the sums of its
/// series. The chart arrives as JSON; nothing here invents a number it does
/// not contain.
static NSString *TGStatGraphLine(NSDictionary *graph, NSString *label) {
	if (![graph isKindOfClass:NSDictionary.class])
		return nil;
	NSString *error = graph[@"error_message"];
	if ([error isKindOfClass:NSString.class] && error.length)
		return [NSString stringWithFormat:@"%@: %@", label, error];
	if ([graph[@"token"] isKindOfClass:NSString.class])
		return [NSString stringWithFormat:@"%@: still loading", label];
	NSString *json = graph[@"json_data"];
	NSData *data = [json dataUsingEncoding:NSUTF8StringEncoding];
	NSDictionary *chart = data.length
			? [NSJSONSerialization JSONObjectWithData:data
					options:NSJSONReadingAllowFragments error:nil] : nil;
	NSArray *columns = [chart isKindOfClass:NSDictionary.class]
			? chart[@"columns"] : nil;
	if ([columns isKindOfClass:NSArray.class] && columns.count > 1){
		NSMutableString *parts = [NSMutableString string];
		for (NSUInteger i = 1; i < columns.count; i++){
			NSArray *series = [columns[i] isKindOfClass:NSArray.class]
					? columns[i] : nil;
			if (!series.count)
				continue;
			double total = 0;
			for (NSUInteger j = 1; j < series.count; j++)
				total += [series[j] doubleValue];
			NSString *name = [series[0] isKindOfClass:NSString.class]
					? series[0]
					: [NSString stringWithFormat:@"Series %lu", (unsigned long)i];
			[parts appendFormat:@"%@ %.0f  ", name, total];
		}
		if (parts.length)
			return [NSString stringWithFormat:@"%@: %@", label, parts];
	}
	return [NSString stringWithFormat:@"%@: chart available", label];
}

/// The message's own record, gathered in one sheet: what is cached, where it
/// sits, the channel graphs, the effect it carries, and the view report TDLib
/// asks for whenever a message has been seen. Any of those can be refused
/// without taking the rest down - the sheet says which.
- (void)showInfoOfActionMessage {
	NSDictionary *m = self.actionMessage;
	int64_t messageId = [m[@"id"] longLongValue];
	if (!messageId)
		return;
	int64_t chatId = self.chatId;

	// How much of the viewport the row takes, which is the ratio TDLib
	// stores. A row that cannot be found still reports as fully seen.
	NSInteger heightPerMille = 1000;
	for (NSInteger row = 0; row < (NSInteger)self.messages.count; row++){
		if ([self.messages[row][@"id"] longLongValue] != messageId)
			continue;
		CGRect rect = [self.table rectForRowAtIndexPath:
				[NSIndexPath indexPathForRow:row inSection:0]];
		CGFloat viewport = CGRectGetHeight(self.table.bounds);
		if (viewport > 0)
			heightPerMille = (NSInteger)(CGRectGetHeight(rect) / viewport * 1000);
		break;
	}
	if (heightPerMille <= 0)
		heightPerMille = 1000;

	dispatch_group_t group = dispatch_group_create();
	__block NSString *localLine = @"Local copy: not cached";
	__block NSInteger position = 0;
	__block NSDictionary *statistics = nil;
	__block NSString *effectLine = nil;
	int64_t effectId = [m[@"effectId"] longLongValue];
	__weak typeof(self) weakSelf = self;

	dispatch_group_enter(group);
	[[TGClient shared] localMessageWithId:messageId inChat:chatId
							   completion:^(NSDictionary *local){
		if (local){
			NSString *text = local[@"text"];
			localLine = text.length
					? [NSString stringWithFormat:@"Local copy: %@", text]
					: @"Local copy: cached";
		}
		dispatch_group_leave(group);
	}];

	dispatch_group_enter(group);
	[[TGClient shared] positionOfMessage:messageId inChat:chatId
								  thread:self.threadId
							  completion:^(NSInteger found){
		position = found;
		dispatch_group_leave(group);
	}];

	dispatch_group_enter(group);
	[[TGClient shared] statisticsOfMessage:messageId inChat:chatId
								completion:^(NSDictionary *found){
		statistics = found;
		dispatch_group_leave(group);
	}];

	if (effectId > 0){
		dispatch_group_enter(group);
		[[TGClient shared] messageEffectWithId:effectId
									completion:^(NSDictionary *effect){
			if (effect)
				effectLine = [NSString stringWithFormat:@"Effect: %@%@",
						effect[@"emoji"] ?: @"",
						[effect[@"premium"] boolValue] ? @" (Premium)" : @""];
			dispatch_group_leave(group);
		}];
	}

	// The message is on screen while its menu is open, which is the thing
	// this report is for; one second is TDLib's own floor for counting it.
	// It does not hold the sheet open: the report is a side effect.
	[[TGClient shared] reportViewOfMessage:messageId inChat:chatId
							  timeInViewMs:1000
						activeTimeInViewMs:1000
							   heightRatio:heightPerMille
						 seenRangeRatio:1000
								completion:nil];

	dispatch_group_notify(group, dispatch_get_main_queue(), ^{
		TGChatViewController *me = weakSelf;
		if (!me)
			return;
		NSMutableArray *lines = [NSMutableArray arrayWithObject:localLine];
		if (position > 0)
			[lines addObject:[NSString stringWithFormat:@"Position: %ld in this chat",
					(long)position]];
		else
			[lines addObject:@"Position: not counted here"];
		if (effectLine.length)
			[lines addObject:effectLine];
		NSString *interaction = TGStatGraphLine(
				statistics[@"message_interaction_graph"], @"Views");
		NSString *reactions = TGStatGraphLine(
				statistics[@"message_reaction_graph"], @"Reactions");
		if (interaction.length)
			[lines addObject:interaction];
		if (reactions.length)
			[lines addObject:reactions];
		if (!statistics)
			[lines addObject:@"Statistics: not a channel post, or not "
							  @"released to this account"];
		[TGAlertSheet showMessage:[lines componentsJoinedByString:@"\n"]
							title:@"Message Info" inView:me.view];
	});
}

/// The sparse positions a shared-media scroll is built from, shown as the
/// ids Telegram returned. A chat with no positions says so rather than
/// opening an empty list.
- (void)showSparsePositionsOfActionMessage {
	NSDictionary *m = self.actionMessage;
	int64_t messageId = [m[@"id"] longLongValue];
	if (!messageId)
		return;
	int64_t chatId = self.chatId;
	__weak typeof(self) weakSelf = self;
	[[TGClient shared] sparsePositionsInChat:chatId fromMessageId:messageId
									  thread:self.threadId limit:200
								  completion:^(NSArray *ids){
		TGChatViewController *me = weakSelf;
		if (!me)
			return;
		if (!ids.count){
			[TGAlertSheet showMessage:@"Telegram returned no positions from here."
								title:@"Shared Media Map" inView:me.view];
			return;
		}
		NSMutableArray *rows = [NSMutableArray array];
		for (NSNumber *position in ids)
			[rows addObject:[NSString stringWithFormat:@"Message %lld",
					(long long)[position longLongValue]]];
		[TGAlertSheet showChoices:rows
							title:[NSString stringWithFormat:@"%lu positions",
									(unsigned long)rows.count]
				  destructiveIndex:-1
						   inView:me.view
						 onChoice:^(NSInteger index){
			int64_t target = [ids[index] longLongValue];
			[me showMessageId:target gone:nil];
		}];
	}];
}
/// Their six, in their order. One reaction at a time is all this screen
/// offers; picking a second replaces the first on Telegram's side.
- (void)askReactionForMessage:(int64_t)messageId {
	NSArray *fallback = @[@"\U0001F44D", @"\U0001F44E", @"\U00002764",
						  @"\U0001F525", @"\U0001F389", @"\U0001F62D"];
	__weak typeof(self) weakSelf = self;
	// The chat sets what may be reacted with, and getMessageAvailableReactions
	// says which of those this message itself offers; the fixed six are only
	// what answers a chat that allows everything.
	[[TGClient shared] availableReactionsForMessage:messageId
											 inChat:self.chatId
										 completion:^(NSArray *offered){
		TGChatViewController *me = weakSelf;
		if (!me)
			return;
		NSArray *emoji = [me reactionsWithDefaultFirst:
				(offered.count ? offered : fallback)];
		[TGAlertSheet showChoices:emoji
							title:@"React"
				 destructiveIndex:-1
						   inView:me.view
						 onChoice:^(NSInteger index){
			[[TGClient shared] reactTo:messageId inChat:me.chatId emoji:emoji[index]];
			[me reload];
		}];
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

/// A replacement picture, not a new one: the library is opened for an image
/// and the pick goes back into the message it came from.
- (void)pickReplacementPhoto {
	if (![UIImagePickerController isSourceTypeAvailable:
			UIImagePickerControllerSourceTypePhotoLibrary])
		return;

	UIImagePickerController *picker = [[UIImagePickerController alloc] init];
	picker.sourceType = UIImagePickerControllerSourceTypePhotoLibrary;
	picker.mediaTypes = @[(NSString *)kUTTypeImage];
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
	if (image && self.replacingPhoto){
		int64_t messageId = self.editingId;
		self.replacingPhoto = NO;
		self.editingId = 0;
		[self replacePhotoOfMessage:messageId withImage:image];
		return;
	}
	if (image)
		[self sendImage:image];
}

/// The picked picture replaces the one already on Telegram: the same message
/// id, the same place in the history, the same caption. Leaving the caption
/// out would clear it, since editMessageMedia takes the whole content.
- (void)replacePhotoOfMessage:(int64_t)messageId withImage:(UIImage *)image {
	if (!messageId || !image)
		return;
	CFUUIDRef uuid = CFUUIDCreate(NULL);
	NSString *name = (__bridge_transfer NSString *)CFUUIDCreateString(NULL, uuid);
	CFRelease(uuid);
	NSString *path = [NSTemporaryDirectory() stringByAppendingPathComponent:
			[NSString stringWithFormat:@"replacement-%@.jpg", name]];
	if (![UIImageJPEGRepresentation(image, TGCompressionQualityHigh) writeToFile:path atomically:YES]){
		NSLog(@"cannot stage the replacement image");
		return;
	}
	NSString *caption = self.replacingPhotoCaption ?: @"";
	self.replacingPhotoCaption = nil;
	__weak typeof(self) weakSelf = self;
	[[TGClient shared] editPhotoAtPath:path
							   caption:caption
							 ofMessage:messageId
								inChat:self.chatId
							completion:^(BOOL ok){
		TGChatViewController *me = weakSelf;
		if (!me)
			return;
		[TGSnackbar showInView:me.view
						  text:(ok ? @"Photo replaced" : @"Telegram refused that photo")
					   seconds:2 onCommit:nil];
	}];
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

/// A link to one message, the way internalLinkKind says "message" for it:
/// Telegram names the chat and the message, and the chat opens to it.
- (void)openMessageLink:(NSString *)link {
	if (!link.length) return;
	__weak typeof(self) weakSelf = self;
	[[TGClient shared] messageLinkInfo:link completion:^(int64_t chatId, int64_t messageId){
		TGChatViewController *me = weakSelf;
		if (!me) return;
		if (!chatId){
			[TGSnackbar showInView:me.navigationController.view
							  text:@"That link points at no open message"
						   seconds:2 onCommit:nil];
			return;
		}
		TGChatViewController *chatVC = [[TGChatViewController alloc] init];
		chatVC.chatId = chatId;
		NSString *title = [[TGClient shared] titleForChat:chatId];
		chatVC.chatTitle = title.length ? title : @"Chat";
		chatVC.hidesBottomBarWhenPushed = YES;
		chatVC.initialMessageId = messageId;
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
			// Telegram can spell one link many ways. Asking it for the
			// canonical form before opening means a share link, a short
			// link and a copied link all land on the same chat.
			[me resolveInternalLinkKind:kind value:value original:clean
						 isTelegramHost:isTelegramHost
					   isTelegramScheme:isTelegramScheme];
		}];
		return;
	}

	[self presentExternalLink:clean];
}

/// The canonical t.me/tg:// form of a link Telegram has already classified,
/// then the screen acts on that form. A failed conversion falls back to the
/// text the message carried.
- (void)resolveInternalLinkKind:(NSString *)kind
						  value:(NSString *)value
					   original:(NSString *)original
				 isTelegramHost:(BOOL)isTelegramHost
			   isTelegramScheme:(BOOL)isTelegramScheme {
	NSDictionary *type = nil;
	if ([kind isEqualToString:@"publicChat"] && value.length)
		type = @{@"@type" : @"internalLinkTypePublicChat",
				 @"chat_username" : value,
				 @"draft_text" : @"",
				 @"open_profile" : @NO,
				 @"unpaid_messages_token" : @""};
	else if ([kind isEqualToString:@"message"] && value.length)
		type = @{@"@type" : @"internalLinkTypeMessage", @"url" : value};
	else if ([kind isEqualToString:@"inviteLink"] && value.length)
		type = @{@"@type" : @"internalLinkTypeChatInvite", @"invite_link" : value};
	else if ([kind isEqualToString:@"stickerSet"] && value.length)
		type = @{@"@type" : @"internalLinkTypeStickerSet",
				 @"sticker_set_name" : value,
				 @"expect_custom_emoji" : @NO};
	else if ([kind isEqualToString:@"phoneNumber"] && value.length)
		type = @{@"@type" : @"internalLinkTypeUserPhoneNumber",
				 @"phone_number" : value,
				 @"draft_text" : @"",
				 @"open_profile" : @NO,
				 @"unpaid_messages_token" : @""};
	else if ([kind isEqualToString:@"userToken"] && value.length)
		type = @{@"@type" : @"internalLinkTypeUserToken", @"token" : value};

	if (!type){
		// A deep link has no InternalLinkType to convert, and the path
		// fallback reads the original text.
		[self continueInternalLinkKind:kind value:value link:original
						isTelegramHost:isTelegramHost
					  isTelegramScheme:isTelegramScheme];
		return;
	}

	__weak typeof(self) weakSelf = self;
	[[TGClient shared] internalLinkForType:type http:YES completion:^(NSString *link){
		TGChatViewController *me = weakSelf;
		if (!me)
			return;
		NSString *resolved = link.length ? link : original;
		if (link.length && ![resolved isEqualToString:original])
			[TGSnackbar showInView:me.navigationController.view ?: me.view
							  text:[NSString stringWithFormat:@"Opened %@", resolved]
						   seconds:2 onCommit:nil];
		[me continueInternalLinkKind:kind value:value link:resolved
					  isTelegramHost:isTelegramHost
					isTelegramScheme:isTelegramScheme];
	}];
}

/// The branches that act on a classified internal link, now reading the
/// canonical URL rather than the text that was tapped.
- (void)continueInternalLinkKind:(NSString *)kind
						   value:(NSString *)value
							link:(NSString *)link
				   isTelegramHost:(BOOL)isTelegramHost
				 isTelegramScheme:(BOOL)isTelegramScheme {
	NSURL *u = [NSURL URLWithString:link];
	if (!u.scheme.length)
		u = [NSURL URLWithString:[NSString stringWithFormat:@"http://%@", link]];
	NSString *host = u.host.lowercaseString;

	if ([kind isEqualToString:@"publicChat"] && value.length){
		[self openChatWithUsername:value];
		return;
	}
	if ([kind isEqualToString:@"message"] && value.length){
		// A link to the exact message, t.me/name/12345: the chat is
		// resolved and the message jumped to, by Telegram's own
		// answer at getMessageLinkInfo.
		[self openMessageLink:value];
		return;
	}
	if ([kind isEqualToString:@"inviteLink"] && value.length){
		[self joinChatByInviteLink:value];
		return;
	}
	if ([kind isEqualToString:@"stickerSet"] && value.length){
		// A sticker set is not a chat, and opening one as a chat is
		// what this did before. The pack's record comes in with the
		// id and the count the sheet needs, and Telegram's answer
		// says whether this account already has it.
		[self askForStickerSet:value];
		return;
	}
	if ([kind isEqualToString:@"phoneNumber"] && value.length){
		[self openChatWithPhoneNumber:value];
		return;
	}
	if ([kind isEqualToString:@"userToken"] && value.length){
		// A user link that carries no username: the token is the only handle
		// Telegram gives, and searchUserByToken resolves it.
		[self openChatWithUserToken:value];
		return;
	}
	if ([kind isEqualToString:@"deepLink"] && value.length){
		[TGAlertSheet showMessage:value
							title:@"LegacyTG"
							inView:self.navigationController.view ?: self.view];
		return;
	}
	// Anything Telegram has no kind for falls through to the paths
	// this screen has always matched by hand.
	[self openTelegramLinkByPath:link url:u
					isTelegramHost:isTelegramHost
				  isTelegramScheme:isTelegramScheme
							  host:host];
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

/// A user link whose only handle is a token - the form Telegram gives for an
/// account with no username. searchUserByToken is the one request that turns
/// it into a name; a refusal is the server's words, not a guessed chat.
- (void)openChatWithUserToken:(NSString *)token {
	__weak typeof(self) weakSelf = self;
	[[TGClient shared] searchUserByToken:token completion:^(NSDictionary *user,
															NSString *error){
		TGChatViewController *me = weakSelf;
		if (!me)
			return;
		int64_t userId = [user[@"id"] longLongValue];
		if (!userId){
			[TGSnackbar showInView:me.navigationController.view ?: me.view
							  text:(error ?: @"That user link names no account")
						   seconds:2 onCommit:nil];
			return;
		}
		[[TGClient shared] privateChatWithUser:userId completion:^(int64_t chatId){
			if (!chatId)
				return;
			TGChatViewController *chatVC = [[TGChatViewController alloc] init];
			chatVC.chatId = chatId;
			chatVC.chatTitle = user[@"name"] ?: user[@"username"] ?: @"Chat";
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

/// An external link gets one sheet before it leaves the app. Telegram is
/// asked twice: which browser the host needs, and whether the link signs in
/// or asks for write access. A login link is not opened until the user has
/// seen the domain and the permission, which is the whole reason TDLib
/// exposes getExternalLinkInfo.
- (void)presentExternalLink:(NSString *)link {
	__weak typeof(self) weakSelf = self;
	[[TGClient shared] webBrowserTypeForURL:link completion:^(NSString *browser){
		[[TGClient shared] externalLinkInfoForURL:link completion:^(NSDictionary *info){
			TGChatViewController *me = weakSelf;
			if (!me)
				return;
			[me showExternalLink:link browser:browser info:info];
		}];
	}];
}

- (void)showExternalLink:(NSString *)link
				 browser:(NSString *)browser
					info:(NSDictionary *)info {
	NSString *host = [NSURL URLWithString:link].host ?: link;
	BOOL confirm = [info[@"kind"] isEqualToString:@"confirm"];
	BOOL write = [info[@"requestWriteAccess"] boolValue];
	NSString *domain = info[@"domain"];

	NSMutableString *message = [NSMutableString string];
	if (browser.length)
		[message appendFormat:@"Telegram says this opens in %@.\n",
				[browser isEqualToString:@"inApp"] ? @"its own browser" : @"Safari"];
	else
		[message appendString:@"Telegram does not name a browser for this host.\n"];
	if (confirm && domain.length)
		[message appendFormat:@"You will sign in to %@.", domain];
	else if (confirm)
		[message appendString:@"The site asks you to sign in."];
	if (write)
		[message appendString:@"\nIt will be allowed to message you."];

	__weak typeof(self) weakSelf = self;
	[TGAlertSheet showChoices:@[@"Open Link", @"Instant View", @"Copy Link"]
						title:host
					  message:message
			 destructiveIndex:-1
					   inView:self.navigationController.view ?: self.view
					 onChoice:^(NSInteger index){
		TGChatViewController *me = weakSelf;
		if (!me)
			return;
		if (index == 0){
			[[TGClient shared] externalLinkForURL:link
								 allowWriteAccess:write
									  completion:^(NSString *resolved){
				NSString *target = resolved.length ? resolved : link;
				[me openPlainLink:[NSURL URLWithString:target]];
			}];
		} else if (index == 1){
			[me openInstantViewForLink:link];
		} else {
			[UIPasteboard generalPasteboard].string = link;
			[TGSnackbar showInView:me.navigationController.view ?: me.view
							  text:@"Link copied" seconds:2 onCommit:nil];
		}
	}];
}

/// Telegram's reader view, pushed as its own screen. A page without one is
/// not an error worth a screen: the sheet says so and the user can open it
/// in Safari instead.
- (void)openInstantViewForLink:(NSString *)link {
	__weak typeof(self) weakSelf = self;
	[[TGClient shared] instantViewForURL:link onlyLocal:NO
							  completion:^(NSDictionary *view){
		TGChatViewController *me = weakSelf;
		if (!me)
			return;
		NSArray *blocks = view[@"blocks"];
		if (![blocks isKindOfClass:NSArray.class] || !blocks.count){
			[TGAlertSheet showMessage:@"Telegram has no Instant View for this page."
							   title:@"Instant View"
							   inView:me.navigationController.view ?: me.view];
			return;
		}
		TGInstantViewController *reader = [[TGInstantViewController alloc] init];
		reader.pageTitle = [NSURL URLWithString:link].host ?: @"Instant View";
		reader.sourceURL = link;
		reader.blocks = blocks;
		reader.hidesBottomBarWhenPushed = YES;
		[me.navigationController pushViewController:reader animated:YES];
	}];
}


#pragma mark - message record sheets

/// One-shared-shape date for the sheets: three shapes the chat list shows.
static NSString *TGSheetDate(NSTimeInterval unix) {
	char buf[TGFastDateBufferSize + 1] = {0};
	size_t len = TGFastChatDate((time_t)unix, (time_t)TGOptionNow(), buf, TGFastDateBufferSize);
	return len ? [[NSString alloc] initWithBytes:buf length:len encoding:NSUTF8StringEncoding]
			   : @"";
}

/// The helper behind five of the menu rows: the action message is read into
/// a bound pair, since a sheet can arrive after the chat scrolled on.
- (void)withActionMessage:(void (^)(int64_t messageId, int64_t chatId, NSDictionary *m))block {
	NSDictionary *m = self.actionMessage;
	if (!m || !block)
		return;
	block([m[@"id"] longLongValue], self.chatId, m);
}

/// Names come off the client's user cache; a viewer nobody knows about is
/// still a row, said as "User".
- (void)showViewersOfActionMessage {
	__weak typeof(self) weakSelf = self;
	[self withActionMessage:^(int64_t messageId, int64_t chatId, NSDictionary *m){
		[[TGClient shared] viewersOfMessage:messageId inChat:chatId completion:^(NSArray *viewers){
			TGChatViewController *me = weakSelf;
			if (!me) return;
			if (!viewers.count){
				// A one-to-one chat has no viewer list; Telegram still knows
				// when the message was read, and that is the whole answer
				// there. The reason words come from TDLib, not guessed.
				[[TGClient shared] readDateOfMessage:messageId inChat:chatId
										  completion:^(NSTimeInterval date, NSString *reason){
					TGChatViewController *me = weakSelf;
					if (!me)
						return;
					NSString *say = date > 0
							? [NSString stringWithFormat:@"Read %@.",
									TGSheetDate(date)]
							: (reason ?: @"Telegram cannot say.");
					[TGAlertSheet showMessage:say title:@"Who Read This" inView:me.view];
				}];
				return;
			}
			NSMutableArray *names = [NSMutableArray array];
			for (NSDictionary *v in viewers){
				NSString *name = [[TGClient shared] nameForUserId:
						[v[@"user_id"] longLongValue]] ?: @"User";
				NSString *when = TGSheetDate([v[@"view_date"] doubleValue]);
				NSString *line = name ?: @"User";
				if (when.length)
					line = [NSString stringWithFormat:@"%@ — %@", line, when];
				[names addObject:line];
			}
			[TGAlertSheet showChoices:names
								title:@"Read by"
					 destructiveIndex:-1
							   inView:me.view
							 onChoice:nil];
		}];
	}];
}

/// The sheet's first page lists what is on the message per emoji (the
/// interaction info a flattened message already carries); a tap lists that
/// reaction's adders, where an administrator takes one person's set off.
/// Every public copy of this message TDLib knows about: channels and open
/// groups that forwarded it. A copy opens where it was posted, at the same
/// message id the forward carries.
- (void)showPublicForwardsOfActionMessage {
	__weak typeof(self) weakSelf = self;
	[self withActionMessage:^(int64_t messageId, int64_t chatId, NSDictionary *m){
		[[TGClient shared] publicForwardsOfMessage:messageId
											 inChat:chatId
										 completion:^(NSArray *forwards){
			TGChatViewController *me = weakSelf;
			if (!me)
				return;
			if (!forwards.count){
				[TGAlertSheet showMessage:@"Telegram knows no public copies "
							@"of this message." title:@"Public Forwards"
										inView:me.view];
				return;
			}
			NSMutableArray *rows = [NSMutableArray array];
			for (NSDictionary *copy in forwards){
				int64_t where = [copy[@"chat_id"] longLongValue];
				NSString *title = where
						? ([[TGClient shared] titleForChat:where] ?: @"A chat")
						: @"Unknown chat";
				[rows addObject:[NSString stringWithFormat:@"%@  ·  #%@",
						title, copy[@"message_id"] ?: @""]];
			}
			[TGAlertSheet showChoices:rows
								title:@"Public Forwards"
					 destructiveIndex:-1
							   inView:me.view
							 onChoice:^(NSInteger index){
				NSDictionary *copy = forwards[(NSUInteger)index];
				int64_t where = [copy[@"chat_id"] longLongValue];
				int64_t copyId = [copy[@"message_id"] longLongValue];
				if (!where || !copyId)
					return;
				TGChatViewController *vc = [[TGChatViewController alloc] init];
				vc.chatId = where;
				vc.chatTitle = [[TGClient shared] titleForChat:where] ?: @"";
				vc.isGroup = YES;
				vc.initialMessageId = copyId;
				vc.hidesBottomBarWhenPushed = YES;
				[me.navigationController pushViewController:vc animated:YES];
			}];
		}];
	}];
}

- (void)showReactorsOfActionMessage {
	__weak typeof(self) weakSelf = self;
	[self withActionMessage:^(int64_t messageId, int64_t chatId, NSDictionary *m){
		NSArray *groups = m[@"interaction_info"][@"reactions"][@"reactions"];
		if (![groups isKindOfClass:NSArray.class] || !groups.count){
			[TGAlertSheet showMessage:@"This message carries no reactions."
								title:@"Reactions"
								inView:weakSelf.view];
			return;
		}
		NSMutableArray *lines = [NSMutableArray array];
		for (NSDictionary *r in groups){
			NSString *emoji = r[@"type"][@"emoji"];
			NSString *name = emoji.length ? emoji : @"★";
			[lines addObject:[NSString stringWithFormat:@"%@  ×%@", name,
							  r[@"total_count"] ?: @(0)]];
		}
		[TGAlertSheet showChoices:lines
							title:@"Reactions"
				 destructiveIndex:-1
						   inView:weakSelf.view
						 onChoice:^(NSInteger index){
			NSString *emoji = groups[index][@"type"][@"emoji"] ?: @"";
			[[TGClient shared] addedReactionsOfMessage:messageId
												 inChat:chatId
												 emoji:emoji
												offset:nil
											completion:^(NSArray *rows, NSString *next){
				TGChatViewController *me = weakSelf;
				if (!me) return;
				if (!rows.count){
					[TGAlertSheet showMessage:@"Telegram keeps that list closed here."
										 title:@"Reactions"
										inView:me.view];
					return;
				}
				NSMutableArray *names = [NSMutableArray array];
				for (NSDictionary *r in rows){
					NSDictionary *sender = r[@"sender"];
					NSString *label = nil;
					NSString *userId = sender[@"user_id"];
					if (userId)
						label = [[TGClient shared] nameForUserId:[userId longLongValue]];
					if (!label.length)
						label = sender[@"chat_id"] ? @"Another chat" : @"User";
					NSString *mine = [r[@"mine"] boolValue] ? @" (you)" : @"";
					NSString *line = label ?: @"User";
					[names addObject:[line stringByAppendingString:mine]];
				}
				[TGAlertSheet showChoices:names
									title:[NSString stringWithFormat:@"Who set %@", emoji ?: @"★"]
						 destructiveIndex:-1
								   inView:me.view
								 onChoice:^(NSInteger choice){
					// An administrator takes one person's reactions here -
					// on this message and every other one in this chat.
					NSDictionary *sender = rows[choice][@"sender"];
					if (!sender)
						return;
					[TGAlertSheet showConfirm:
							@"This removes everything that account reacted "
							@"with, here and across this chat."
								title:@"Clear Reactions"
							   action:@"Remove"
						  destructive:YES
							   inView:weakSelf.view
							onConfirm:^{
						[[TGClient shared] deleteReactionsOfSender:sender
														  ofMessage:messageId
															 inChat:weakSelf.chatId];
						[[TGClient shared] deleteAllReactionsOfSender:sender
															   inChat:weakSelf.chatId];
					}];
				}];
			}];
		}];
	}];
}

- (void)showAuthorOfActionMessage {
	__weak typeof(self) weakSelf = self;
	[self withActionMessage:^(int64_t messageId, int64_t chatId, NSDictionary *m){
		[[TGClient shared] authorOfMessage:messageId inChat:chatId completion:^(NSDictionary *user){
			TGChatViewController *me = weakSelf;
			if (!me || !user){
				[TGAlertSheet showMessage:@"Telegram names an author only for a "
										  @"post an anonymous admin made."
									 title:@"Author" inView:me.view];
				return;
			}
			NSString *name = [NSString stringWithFormat:@"%@ %@",
					user[@"first_name"] ?: @"", user[@"last_name"] ?: @""];
			[TGAlertSheet showMessage:name ?: @"The server named nobody"
							   title:@"Author" inView:me.view];
		}];
	}];
}

- (void)translateActionMessage {
	__weak typeof(self) weakSelf = self;
	[self withActionMessage:^(int64_t messageId, int64_t chatId, NSDictionary *m){
		NSString *language = [[NSLocale currentLocale] objectForKey:
				NSLocaleLanguageCode] ?: @"en";
		NSString *text = m[@"text"] ?: @"";
		// translateText keeps the text's entities and takes a tone, which is
		// what a plain message needs. translateMessageText remains the
		// fallback for a message with no flattened text, where Telegram can
		// still translate the content it holds.
		if (text.length){
			[[TGClient shared] translateText:text toLanguageCode:language tone:@""
								  completion:^(NSString *translated){
				TGChatViewController *me = weakSelf;
				if (!me)
					return;
				if (translated.length){
					[TGAlertSheet showMessage:translated
									   title:@"Translation"
									   inView:me.view];
					return;
				}
				[[TGClient shared] translateMessage:messageId inChat:chatId
											 toCode:language
										  completion:^(NSString *fallback){
					[TGAlertSheet showMessage:(fallback.length ? fallback : @"Not translatable")
									   title:@"Translation"
									   inView:me.view];
				}];
			}];
			return;
		}
		[[TGClient shared] translateMessage:messageId inChat:chatId
									 toCode:language
								  completion:^(NSString *translated){
			TGChatViewController *me = weakSelf;
			if (!me) return;
			[TGAlertSheet showMessage:(translated.length ? translated : @"Not translatable")
							   title:@"Translation"
							   inView:me.view];
		}];
	}];
}

/// Where a phrase sits in this message, found by Telegram rather than by
/// NSString. The position is UTF-16 units, so it is the same number a
/// selection API on this OS would use.
- (void)findQuoteInActionMessage {
	__weak typeof(self) weakSelf = self;
	[self withActionMessage:^(int64_t messageId, int64_t chatId, NSDictionary *m){
		NSString *text = m[@"text"] ?: @"";
		if (!text.length)
			return;
		TGChatViewController *me = weakSelf;
		if (!me)
			return;
		[TGAlertSheet showInput:@"Find Quote"
						message:@"Telegram returns the character position of the phrase."
					placeholder:@"Phrase in this message"
						   text:@""
						 action:@"Find"
						 inView:me.view
					 onSubmit:^(NSString *quote){
			[[TGClient shared] searchQuote:quote inText:text position:0
								completion:^(NSInteger position, BOOL found){
				TGChatViewController *live = weakSelf;
				if (!live)
					return;
				if (!found){
					[TGAlertSheet showMessage:@"That phrase is not in this message."
									   title:@"Find Quote"
									   inView:live.view];
					return;
				}
				[TGAlertSheet showMessage:
						[NSString stringWithFormat:@"“%@” starts at character %ld.",
								quote, (long)position]
								   title:@"Find Quote"
								   inView:live.view];
			}];
		}];
	}];
}


- (void)showRecentLocationsInActionMessage {
	__weak typeof(self) weakSelf = self;
	[self withActionMessage:^(int64_t messageId, int64_t chatId, NSDictionary *m){
		[[TGClient shared] recentLocationsInChat:chatId completion:^(NSArray *messages){
			TGChatViewController *me = weakSelf;
			if (!me) return;
			if (!messages.count){
				[TGAlertSheet showMessage:@"No location pins in this chat."
									 title:@"Recent Locations" inView:me.view];
				return;
			}
			NSMutableArray *rows = [NSMutableArray array];
			for (NSDictionary *loc in messages){
				NSString *who = [loc[@"sender_id"] isKindOfClass:NSDictionary.class]
						? ([[TGClient shared] nameForUserId:
						   [loc[@"sender_id"][@"user_id"] longLongValue]]) ?: @"User"
						: @"Location";
				NSString *day = TGSheetDate([loc[@"date"] doubleValue]);
				NSString *live = [loc[@"content"][@"@type"]
						isEqualToString:@"messageLiveLocation"] ? @" · live" : @"";
				NSString *line = [NSString stringWithFormat:@"%@%@%@",
						who ?: @"Location", day.length ? @" · " : @"", day ?: @""];
				[rows addObject:[line stringByAppendingString:live]];
			}
			[TGAlertSheet showChoices:rows
								title:@"Recent Locations"
					 destructiveIndex:-1
							   inView:me.view
							 onChoice:^(NSInteger index){
				if (index >= (NSInteger)messages.count)
					return;
				[weakSelf showMessageId:[messages[index][@"id"] longLongValue]
									 gone:@"That location is gone"];
			}];
		}];
	}];
}

- (void)toggleChatSearchOpenWithTag:(NSString *)tag {
	[self toggleChatSearch];
	if (!self.chatSearchBar)
		return;
	self.chatSearchBar.text = tag;
	[self searchBar:self.chatSearchBar textDidChange:tag];
}

@end
