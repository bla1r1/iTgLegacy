#import "TGProfileAudioViewController.h"
#import "TGAlertSheet.h"
#import "TGClient.h"
#import "TGMusicPlayer.h"
#import "TGTheme.h"
#import "TGStyle.h"
#import "TGSnackbar.h"

@interface TGProfileAudioViewController ()
@property (nonatomic, strong) NSArray *audios;
@property (nonatomic, assign) NSInteger total;
@property (nonatomic, assign) BOOL loading;
@end

@implementation TGProfileAudioViewController

- (id)init {
	return [super initWithStyle:UITableViewStyleGrouped];
}

- (BOOL)isOwnProfile {
	return self.userId == [[TGClient shared].me[@"id"] longLongValue];
}

- (void)viewDidLoad {
	[super viewDidLoad];
	if ([self respondsToSelector:@selector(setEdgesForExtendedLayout:)])
		self.edgesForExtendedLayout = UIRectEdgeNone;
	self.title = self.subjectTitle.length ? self.subjectTitle : @"Profile Audio";
	self.audios = @[];
	self.tableView.rowHeight = TGMetricPersonRow;
	self.tableView.separatorColor = [[TGTheme shared] separatorColour];
	self.tableView.backgroundColor = [[TGTheme shared] groupedBackgroundColour];
	[[TGTheme shared] styleNavigationBar:self.navigationController.navigationBar];
	if ([self isOwnProfile])
		self.navigationItem.rightBarButtonItem = [[UIBarButtonItem alloc]
				initWithBarButtonSystemItem:UIBarButtonSystemItemAdd
									 target:self action:@selector(addTapped)];
	// A row's verbs do not fit on a tap: the hold is the menu.
	UILongPressGestureRecognizer *hold = [[UILongPressGestureRecognizer alloc]
			initWithTarget:self action:@selector(rowHeld:)];
	hold.minimumPressDuration = 0.5;
	[self.tableView addGestureRecognizer:hold];
	[self load];
}

- (void)viewWillAppear:(BOOL)animated {
	[super viewWillAppear:animated];
	[[TGTheme shared] styleNavigationBar:self.navigationController.navigationBar];
}

- (void)load {
	if (self.loading)
		return;
	self.loading = YES;
	__weak typeof(self) weakSelf = self;
	[[TGClient shared] profileAudiosForUser:self.userId offset:0 limit:100
								 completion:^(NSArray *audios, NSInteger total,
											  NSString *error){
		TGProfileAudioViewController *me = weakSelf;
		if (!me)
			return;
		me.loading = NO;
		if (error.length){
			[TGAlertSheet showMessage:error title:@"Profile Audio" inView:me.view];
			return;
		}
		me.audios = audios;
		me.total = total;
		[me.tableView reloadData];
	}];
}

- (NSString *)durationText:(NSNumber *)seconds {
	NSInteger value = [seconds integerValue];
	if (value <= 0)
		return @"";
	return [NSString stringWithFormat:@"%ld:%02ld", (long)(value / 60),
			(long)(value % 60)];
}

#pragma mark - table

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView {
	return 1;
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
	return self.audios.count;
}

- (NSString *)tableView:(UITableView *)tableView titleForHeaderInSection:(NSInteger)section {
	if (!self.audios.count)
		return nil;
	return [NSString stringWithFormat:@"%ld tracks", (long)self.total];
}

- (NSString *)tableView:(UITableView *)tableView titleForFooterInSection:(NSInteger)section {
	if (self.audios.count)
		return @"Tap to play through the music player. Hold a row to reorder it "
			   @"or take it off the profile.";
	return @"No audio on this profile. Telegram keeps the list empty until "
		   @"the owner adds a track.";
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
	UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:@"audio"];
	if (!cell)
		cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleSubtitle
									  reuseIdentifier:@"audio"];
	[[TGTheme shared] styleCell:cell];
	NSDictionary *audio = self.audios[indexPath.row];
	cell.textLabel.text = [audio[@"title"] length] ? audio[@"title"]
			: ([audio[@"fileName"] length] ? audio[@"fileName"] : @"Audio");
	cell.textLabel.font = TGFontBody();
	cell.textLabel.textColor = [[TGTheme shared] primaryTextColour];
	NSString *performer = [audio[@"performer"] length] ? audio[@"performer"]
			: @"Unknown artist";
	NSString *length = [self durationText:audio[@"duration"]];
	cell.detailTextLabel.text = length.length
			? [NSString stringWithFormat:@"%@ · %@", performer, length]
			: performer;
	cell.detailTextLabel.font = TGFontSubhead();
	cell.detailTextLabel.textColor = [[TGTheme shared] secondaryTextColour];
	cell.accessoryType = UITableViewCellAccessoryNone;
	return cell;
}

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
	[tableView deselectRowAtIndexPath:indexPath animated:YES];
	[self playAtIndex:indexPath.row];
}

- (void)playAtIndex:(NSInteger)index {
	if (index < 0 || index >= (NSInteger)self.audios.count)
		return;
	NSMutableArray *tracks = [NSMutableArray array];
	for (NSDictionary *audio in self.audios){
		[tracks addObject:@{
			@"kind" : @"messageAudio",
			@"docId" : audio[@"fileId"] ?: @(0),
			@"audioTitle" : audio[@"title"] ?: @"",
			@"audioPerformer" : audio[@"performer"] ?: @"",
			@"duration" : audio[@"duration"] ?: @(0),
		}];
	}
	[[TGMusicPlayer shared] playTracks:tracks atIndex:index inChat:0];
	[TGSnackbar showInView:self.view
					  text:[NSString stringWithFormat:@"Playing %@",
							  self.audios[index][@"title"] ?: @"audio"]
				   seconds:2 onCommit:nil];
}

#pragma mark - own profile: reorder and remove

/// The order operations all go through one sheet so the row number the user
/// sees is the row number sent, not an index into a filtered list.
- (void)rowHeld:(UILongPressGestureRecognizer *)hold {
	if (hold.state != UIGestureRecognizerStateBegan)
		return;
	CGPoint where = [hold locationInView:self.tableView];
	NSIndexPath *path = [self.tableView indexPathForRowAtPoint:where];
	if (!path || path.row >= (NSInteger)self.audios.count)
		return;
	NSDictionary *audio = self.audios[path.row];
	NSMutableArray *choices = [NSMutableArray arrayWithObjects:
			@"Play", @"Check in Profile", nil];
	BOOL own = [self isOwnProfile];
	if (own){
		[choices addObject:@"Move to Beginning"];
		if (path.row > 0)
			[choices addObject:@"Move After Previous"];
		[choices addObject:@"Remove from Profile"];
	}
	__weak typeof(self) weakSelf = self;
	[TGAlertSheet showChoices:choices
						title:(audio[@"title"] ?: @"Audio")
			 destructiveIndex:(own ? (NSInteger)choices.count - 1 : -1)
					   inView:self.view
					 onChoice:^(NSInteger index){
		NSString *choice = choices[index];
		if ([choice isEqualToString:@"Play"]){
			[weakSelf playAtIndex:path.row];
			return;
		}
		if ([choice isEqualToString:@"Check in Profile"]){
			[weakSelf checkAudio:audio];
			return;
		}
		if ([choice isEqualToString:@"Move to Beginning"]){
			[weakSelf moveAudio:audio after:0];
			return;
		}
		if ([choice isEqualToString:@"Move After Previous"]){
			NSDictionary *previous = weakSelf.audios[path.row - 1];
			[weakSelf moveAudio:audio after:[previous[@"fileId"] integerValue]];
			return;
		}
		if ([choice isEqualToString:@"Remove from Profile"]){
			[weakSelf removeAudio:audio];
		}
	}];
}

- (void)checkAudio:(NSDictionary *)audio {
	__weak typeof(self) weakSelf = self;
	[[TGClient shared] isProfileAudioFileId:[audio[@"fileId"] integerValue]
								 completion:^(BOOL isAudio, NSString *error){
		NSString *text = isAudio
				? @"This file is in the profile audio list."
				: ([error length] ? error : @"Telegram does not have it there.");
		[TGAlertSheet showMessage:text title:@"Profile Audio"
						   inView:weakSelf.view];
	}];
}

- (void)moveAudio:(NSDictionary *)audio after:(NSInteger)afterFileId {
	__weak typeof(self) weakSelf = self;
	[[TGClient shared] setProfileAudioFileId:[audio[@"fileId"] integerValue]
								 afterFileId:afterFileId
								  completion:^(BOOL ok, NSString *error){
		if (!ok){
			[TGAlertSheet showMessage:(error ?: @"Telegram refused the move.")
								title:@"Profile Audio" inView:weakSelf.view];
			return;
		}
		[weakSelf load];
	}];
}

- (void)removeAudio:(NSDictionary *)audio {
	__weak typeof(self) weakSelf = self;
	[TGAlertSheet showConfirm:@"Take this track off the profile?"
						title:(audio[@"title"] ?: @"Profile Audio")
					   action:@"Remove"
				  destructive:YES
					   inView:self.view
					onConfirm:^{
		[[TGClient shared] removeProfileAudioFileId:[audio[@"fileId"] integerValue]
										 completion:^(BOOL ok, NSString *error){
			if (!ok){
				[TGAlertSheet showMessage:(error ?: @"Telegram refused the removal.")
									title:@"Profile Audio" inView:weakSelf.view];
				return;
			}
			[weakSelf load];
		}];
	}];
}

#pragma mark - adding from Saved Messages

/// There is no document picker on this OS, but the files TDLib already holds
/// are a real source: pick an audio message from Saved Messages, download its
/// bytes, and add that path. The profile is the account's own list, so a
/// track already sent to Saved Messages is the honest way in.
- (void)addTapped {
	__weak typeof(self) weakSelf = self;
	[[TGClient shared] historyForChat:[[TGClient shared] savedMessagesChatId]
								limit:100
						   completion:^(NSArray *messages){
		TGProfileAudioViewController *me = weakSelf;
		if (!me)
			return;
		NSMutableArray *tracks = [NSMutableArray array];
		for (NSDictionary *message in messages)
			if ([message[@"kind"] isEqualToString:@"messageAudio"])
				[tracks addObject:message];
		if (!tracks.count){
			[TGAlertSheet showMessage:@"Send an audio file to Saved Messages "
									  @"first; this screen adds from there."
								title:@"Add Profile Audio" inView:me.view];
			return;
		}
		NSMutableArray *titles = [NSMutableArray array];
		for (NSDictionary *track in tracks)
			[titles addObject:[NSString stringWithFormat:@"%@ — %@",
					track[@"audioTitle"] ?: track[@"docName"] ?: @"Audio",
					track[@"audioPerformer"] ?: @"Unknown artist"]];
		[TGAlertSheet showChoices:titles title:@"Add Profile Audio"
				destructiveIndex:-1 inView:me.view onChoice:^(NSInteger index){
			[me addTrack:tracks[index]];
		}];
	}];
}

- (void)addTrack:(NSDictionary *)track {
	NSNumber *fileId = track[@"docId"];
	if ([fileId longLongValue] <= 0){
		[TGAlertSheet showMessage:@"That message carries no downloadable audio."
							title:@"Add Profile Audio" inView:self.view];
		return;
	}
	__weak typeof(self) weakSelf = self;
	[[TGClient shared] downloadFile:fileId.integerValue
						 completion:^(NSString *path){
		TGProfileAudioViewController *me = weakSelf;
		if (!me || !path.length){
			[TGAlertSheet showMessage:@"The audio file could not be downloaded."
								title:@"Add Profile Audio" inView:me.view];
			return;
		}
		[[TGClient shared] addProfileAudioAtPath:path
										   title:track[@"audioTitle"] ?: @""
									   performer:track[@"audioPerformer"] ?: @""
										duration:[track[@"duration"] integerValue]
									  completion:^(BOOL ok, NSString *error){
			if (!ok){
				[TGAlertSheet showMessage:(error ?: @"Telegram refused that audio.")
									title:@"Add Profile Audio" inView:me.view];
				return;
			}
			[me load];
		}];
	}];
}

@end
