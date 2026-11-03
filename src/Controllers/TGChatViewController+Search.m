#import "TGChatViewControllerInternal.h"
#import "TGAlertSheet.h"
#import "TGClientInternal.h"

@implementation TGChatViewController (Search)

#pragma mark - search

/// The table already knows how to draw a list of flattened messages, so search
/// just swaps the list underneath it rather than building a second screen.
- (void)toggleChatSearch {
	if (self.chatSearchBar){
		[self endChatSearch];
		return;
	}

	CGRect b = self.view.bounds;
	self.chatSearchBar = [[UISearchBar alloc] initWithFrame:CGRectMake(0, 0, b.size.width, TGMetricRow)];
	[[TGTheme shared] styleSearchBar:self.chatSearchBar];
	self.chatSearchBar.delegate = self;
	self.chatSearchBar.placeholder = @"Search in chat";
	self.chatSearchBar.autoresizingMask = UIViewAutoresizingFlexibleWidth;
	self.chatSearchBar.alpha = TGAlphaTransparent;
	[self.view addSubview:self.chatSearchBar];
	[self.chatSearchBar setShowsCancelButton:YES animated:NO];
	[self.chatSearchBar becomeFirstResponder];

	self.messagesBeforeSearch = self.messages;

	// The bar fades over the header. The table stays put: the keyboard is moving
	// its frame at this moment, and a frame set under a transform comes out wrong.
	__weak typeof(self) weakSelf = self;
	[UIView animateWithDuration:TGAnimationDurationNormal animations:^{
		weakSelf.chatSearchBar.alpha = TGAlphaOpaque;
	}];
}

- (void)endChatSearch {
	UISearchBar *bar = self.chatSearchBar;
	if (!bar)
		return;
	self.chatSearchBar = nil;
	[bar resignFirstResponder];

	// Restore at once rather than in the completion below: a second search
	// opened during the slide would otherwise capture the old results as the
	// list it has to return to.
	if (self.messagesBeforeSearch){
		self.messages = self.messagesBeforeSearch;
		self.messagesBeforeSearch = nil;
		[self.table reloadData];
		[self scrollToBottomAnimated:NO];
	}

	// The old bar is removed by its own pointer, so a new search opened during
	// the fade keeps its bar.
	[UIView animateWithDuration:TGAnimationDurationNormal animations:^{
		bar.alpha = TGAlphaTransparent;
	} completion:^(BOOL finished){
		[bar removeFromSuperview];
	}];
}

- (void)searchBarCancelButtonClicked:(id)searchBar {
	[self endChatSearch];
}

- (void)searchBar:(id)searchBar textDidChange:(NSString *)query {
	if (!query.length){
		self.messages = self.messagesBeforeSearch ?: @[];
		[self.table reloadData];
		return;
	}

	NSString *clean = [query stringByTrimmingCharactersInSet:
			[NSCharacterSet whitespaceAndNewlineCharacterSet]];
	NSString *tag = [clean hasPrefix:@"#"] ? [clean substringFromIndex:1] : clean;
	NSString *flatTag = tag.length ? tag : nil;
	__weak typeof(self) weakSelf = self;
	void (^takeAnswer)(NSArray *raw) = ^void(NSArray *raw){
		TGChatViewController *me = weakSelf;
		if (!me) return;
		// These two answers arrive as raw message dicts, and the table
		// reads the flattened kind.
		NSMutableArray *flat = [NSMutableArray array];
		for (NSDictionary *m in raw ?: @[]){
			NSDictionary *f = TGFlattenMessage(m);
			if (f) [flat addObject:f];
		}
		me.messages = [[flat reverseObjectEnumerator] allObjects];
		[me.table reloadData];
	};

	// A word starting in # is Telegram's own searchable tag, and the server
	// owns those searches: in Saved Messages the tag answers from this
	// account's notes; everywhere else it is the public wall.
	if ([clean hasPrefix:@"#"]){
		if ([TGClient shared].savedMessagesChatId == self.chatId && self.threadId){
			[[TGClient shared] searchSavedMessagesInTopic:self.threadId
													  query:@""
														tag:@{@"@type" : @"reactionTypeEmoji",
															  @"emoji" : flatTag ?: @""}
														   from:0
													completion:^(NSArray *found, int64_t next){
				takeAnswer(found);
			}];
		} else {
			[[TGClient shared] publicMessagesByTag:flatTag ?: @""
											offset:nil
										completion:^(NSArray *found, NSString *next){
				takeAnswer(found);
			}];
		}
		return;
	}

	[[TGClient shared] searchInChat:self.chatId query:query completion:^(NSArray *found){
		TGChatViewController *me = weakSelf;
		if (!me || ![me.chatSearchBar.text isEqualToString:query])
			return;   // a stale answer must not replace a newer query
		// searchChatMessages answers newest first; the table reads oldest first.
		me.messages = [[found reverseObjectEnumerator] allObjects];
		[me.table reloadData];
	}];
}

@end
