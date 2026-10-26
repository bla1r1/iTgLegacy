#import "TGChatListViewControllerInternal.h"

@implementation TGChatListViewController (Search)

- (void)styleSearchBar {
	TGTheme *theme = [TGTheme shared];
	self.searchBar.barStyle = theme.isDark ? UIBarStyleBlack : UIBarStyleDefault;
	if ([self.searchBar respondsToSelector:@selector(setBarTintColor:)])
		self.searchBar.barTintColor = [theme searchBarBackgroundColour];
	self.searchBar.tintColor = [theme accentColour];
	self.searchBar.backgroundColor = [theme searchBarBackgroundColour];
	if ([self.searchBar respondsToSelector:@selector(setImage:forSearchBarIcon:state:)]) {
		[self.searchBar setImage:[TGIcons searchLensOfSize:TGMetricSearchIconSize colour:[theme secondaryTextColour]]
				forSearchBarIcon:UISearchBarIconSearch
						   state:UIControlStateNormal];
	}
}

- (BOOL)searchBarShouldBeginEditing:(UISearchBar *)searchBar {
	TGSearchViewController *search = [[TGSearchViewController alloc] init];
	search.hidesBottomBarWhenPushed = YES;
	[self.navigationController pushViewController:search animated:YES];
	return NO;
}

- (void)searchBar:(UISearchBar *)searchBar textDidChange:(NSString *)query {
	if (!query.length){
		self.searchResults = nil;
		[self.tableView reloadData];
		return;
	}

	// Chat titles match locally and instantly; messages need the server. Both
	// land in one list, chats first, which is what the query usually means.
	NSMutableArray *results = [NSMutableArray array];
	for (NSDictionary *c in [TGClient shared].chats)
		if ([c[@"title"] rangeOfString:query options:NSCaseInsensitiveSearch].location != NSNotFound)
			[results addObject:c];
	self.searchResults = results;
	[self.tableView reloadData];

	__weak typeof(self) weakSelf = self;
	[[TGClient shared] searchMessages:query completion:^(NSArray *messages){
		TGChatListViewController *me = weakSelf;
		// A slower answer to an older query must not replace a newer one.
		if (!me || ![me.searchBar.text isEqualToString:query])
			return;
		NSMutableArray *combined = [results mutableCopy];
		for (NSDictionary *m in messages)
			[combined addObject:@{
				@"id"    : m[@"chatId"] ?: @0,
				@"title" : m[@"chatTitle"] ?: @"",
				@"text"  : m[@"text"] ?: @"",
				@"date"  : m[@"date"] ?: @0,
			}];
		me.searchResults = combined;
		[me.tableView reloadData];
	}];
}

- (void)searchBarSearchButtonClicked:(UISearchBar *)searchBar {
	[searchBar resignFirstResponder];
}

- (void)searchBarCancelButtonClicked:(UISearchBar *)searchBar {
	searchBar.text = @"";
	self.searchResults = nil;
	[searchBar resignFirstResponder];
	[self.tableView reloadData];
}

@end
