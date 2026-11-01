#import "TGPublicStoriesViewController.h"
#import "TGClient.h"
#import "TGTheme.h"
#import "TGStyle.h"
#import "TGAlertSheet.h"
#import "TGStoryViewerViewController.h"

@interface TGPublicStoriesViewController ()
@property (nonatomic, copy) NSString *mode;
@property (nonatomic, copy) NSString *query;
@property (nonatomic, copy) NSString *nextOffset;
@property (nonatomic, strong) NSMutableArray *results;
@end

@implementation TGPublicStoriesViewController

- (instancetype)initWithTag:(NSString *)tag {
	self = [super init];
	if (self){
		self.listTitle = @"Public Stories";
		self.emptyText = @"Search Telegram's public stories by hashtag, "
				@"location or venue.";
		_results = [NSMutableArray array];
		if (tag.length){
			_mode = @"tag";
			_query = [tag copy];
		}
	}
	return self;
}

- (void)viewDidLoad {
	[super viewDidLoad];
	self.listFooter = @"Public stories come from Telegram's discovery; a story "
			@"opens in the same viewer as a chat's.";
	[self rebuildRows];
	if (self.query.length)
		[self searchMode:self.mode query:self.query offset:@""];
}

- (void)rebuildRows {
	NSMutableArray *rows = [NSMutableArray array];
	__weak typeof(self) weakSelf = self;
	[rows addObject:@{@"title" : @"Search by Hashtag",
					  @"detail" : @"#tag",
					  @"tap" : ^{ [weakSelf askTag]; }}];
	[rows addObject:@{@"title" : @"Search by Location",
					  @"detail" : @"country, state, city, street",
					  @"tap" : ^{ [weakSelf askLocation]; }}];
	[rows addObject:@{@"title" : @"Search by Venue",
					  @"detail" : @"provider, venue id",
					  @"tap" : ^{ [weakSelf askVenue]; }}];
	for (NSDictionary *story in self.results){
		NSString *title = story[@"title"];
		if (!title.length)
			title = @"Public story";
		NSString *detail = story[@"caption"];
		if (!detail.length)
			detail = [story[@"isVideo"] boolValue] ? @"Video story" : @"Photo story";
		[rows addObject:@{@"title" : title, @"detail" : detail,
						  @"tap" : ^{ [weakSelf openStory:story]; }}];
	}
	if (self.nextOffset.length)
		[rows addObject:@{@"title" : @"Load More",
						  @"detail" : @"Next page",
						  @"tap" : ^{ [weakSelf loadMore]; }}];
	self.rows = rows;
	[self.tableView reloadData];
}

- (void)askTag {
	__weak typeof(self) weakSelf = self;
	[TGAlertSheet showInput:@"Public Stories by Hashtag"
					message:@"The # is optional."
				placeholder:@"tag"
					   text:self.query
					 action:@"Search"
					 inView:self.view
				   onSubmit:^(NSString *text){
		[weakSelf beginMode:@"tag" query:text];
	}];
}

- (void)askLocation {
	__weak typeof(self) weakSelf = self;
	[TGAlertSheet showInput:@"Public Stories by Location"
					message:@"Country, state, city, street - any of them."
				placeholder:@"Ukraine, Kyiv"
					   text:self.query
					 action:@"Search"
					 inView:self.view
				   onSubmit:^(NSString *text){
		[weakSelf beginMode:@"location" query:text];
	}];
}

- (void)askVenue {
	__weak typeof(self) weakSelf = self;
	[TGAlertSheet showInput:@"Public Stories by Venue"
					message:@"Provider and venue id, comma-separated."
				placeholder:@"foursquare, 1234"
					   text:self.query
					 action:@"Search"
					 inView:self.view
				   onSubmit:^(NSString *text){
		[weakSelf beginMode:@"venue" query:text];
	}];
}

- (void)beginMode:(NSString *)mode query:(NSString *)query {
	self.mode = mode;
	self.query = query;
	self.nextOffset = @"";
	self.results = [NSMutableArray array];
	[self rebuildRows];
	[self searchMode:mode query:query offset:@""];
}

- (void)loadMore {
	[self searchMode:self.mode query:self.query offset:self.nextOffset ?: @""];
}

- (void)searchMode:(NSString *)mode query:(NSString *)query offset:(NSString *)offset {
	__weak typeof(self) weakSelf = self;
	void (^done)(NSDictionary *, NSString *) = ^(NSDictionary *page, NSString *error){
		TGPublicStoriesViewController *me = weakSelf;
		if (!me)
			return;
		if (!page){
			[TGAlertSheet showMessage:error ?: @"Telegram refused the search."
								title:@"Public Stories" inView:me.view];
			return;
		}
		NSArray *found = [page[@"stories"] isKindOfClass:NSArray.class]
				? page[@"stories"] : @[];
		[me.results addObjectsFromArray:found];
		me.nextOffset = page[@"nextOffset"] ?: @"";
		[me rebuildRows];
		if (!me.results.count)
			[TGAlertSheet showMessage:@"Telegram returned no public stories."
								title:@"Public Stories" inView:me.view];
	};
	if ([mode isEqualToString:@"tag"]){
		[[TGClient shared] searchPublicStoriesByTag:query offset:offset limit:20
										 completion:done];
		return;
	}
	if ([mode isEqualToString:@"venue"]){
		NSArray *parts = [query componentsSeparatedByString:@","];
		NSString *provider = parts.count > 0
				? [parts[0] stringByTrimmingCharactersInSet:
						[NSCharacterSet whitespaceCharacterSet]] : @"";
		NSString *venueId = parts.count > 1
				? [parts[1] stringByTrimmingCharactersInSet:
						[NSCharacterSet whitespaceCharacterSet]] : @"";
		[[TGClient shared] searchPublicStoriesByVenue:provider venueId:venueId
											   offset:offset limit:20 completion:done];
		return;
	}
	NSArray *parts = [query componentsSeparatedByString:@","];
	NSMutableArray *fields = [NSMutableArray array];
	for (NSString *part in parts)
		[fields addObject:[part stringByTrimmingCharactersInSet:
				[NSCharacterSet whitespaceCharacterSet]]];
	// One field is a city, two are country and city, three add a state and
	// four add a street: the order the sheet's message names.
	NSString *country = @"", *state = @"", *city = @"", *street = @"";
	if (fields.count == 1){
		city = fields[0];
	} else if (fields.count == 2){
		country = fields[0]; city = fields[1];
	} else if (fields.count == 3){
		country = fields[0]; state = fields[1]; city = fields[2];
	} else if (fields.count >= 4){
		country = fields[0]; state = fields[1]; city = fields[2]; street = fields[3];
	}
	[[TGClient shared] searchPublicStoriesByLocation:
			@{@"countryCode" : country, @"state" : state,
			  @"city" : city, @"street" : street}
											  offset:offset limit:20 completion:done];
}

- (void)openStory:(NSDictionary *)story {
	TGStoryViewerViewController *viewer = [[TGStoryViewerViewController alloc]
			initWithChatId:[story[@"chatId"] longLongValue]
					 title:story[@"title"] ?: @"Public Story"
				   stories:@[story]
				startIndex:0
				 canManage:NO];
	viewer.hidesBottomBarWhenPushed = YES;
	[self.navigationController pushViewController:viewer animated:YES];
}

@end
