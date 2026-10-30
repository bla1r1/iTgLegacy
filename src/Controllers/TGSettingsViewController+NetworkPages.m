//
// TGSettingsViewController+NetworkPages.m
// Settings pages for data usage, network stats, power saving, folders, downloads, and proxies.
//
#import "TGSettingsViewControllerInternal.h"
#import "TGAlertSheet.h"
#import "TGForwardPicker.h"
#import "TGStorageViewController.h"

static NSString *TGChatNameForId(NSNumber *chatId) {
	for (NSArray *list in @[[TGClient shared].chats ?: @[],
							[TGClient shared].archivedChats ?: @[]])
		for (NSDictionary *chat in list)
			if ([chat[@"id"] longLongValue] == chatId.longLongValue){
				NSString *title = chat[@"title"];
				if (title.length)
					return title;
			}
	return [NSString stringWithFormat:@"Chat %@", chatId];
}

@implementation TGSettingsViewController (NetworkPages)

- (NSArray *)dataSections {
	__weak typeof(self) weakSelf = self;
	BOOL mobile = [[TGClient shared] autoDownloadOverMobile];
	BOOL wifi   = [[TGClient shared] autoDownloadOverWifi];
	NSDictionary *archiveSettings = [TGClient shared].archiveSettings ?: @{};

	return @[
		TGSection(@"Usage", nil, @[
			TGTapRow(@"Downloads", nil, ^{
				[weakSelf openPage:TGSettingsPageDownloads];
			}),
			TGTapRow(@"Storage Usage", nil, ^{
				TGStorageViewController *storage = [[TGStorageViewController alloc] init];
				storage.hidesBottomBarWhenPushed = YES;
				[weakSelf.navigationController pushViewController:storage animated:YES];
			}),
			TGTapRow(@"Network Usage",
					[NSString stringWithFormat:@"%@ in, %@ out",
							TGBytes(weakSelf.networkReceived), TGBytes(weakSelf.networkSent)],
					^{
				[TGAlertSheet showConfirm:@"Reset the counters?"
									title:@"Network Usage"
								   action:@"Reset"
							  destructive:NO
								   inView:weakSelf.view
								onConfirm:^{
					[[TGClient shared] resetNetworkStats];
					weakSelf.networkSent = 0;
					weakSelf.networkReceived = 0;
					[weakSelf rebuild];
				}];
			}),
		]),

		TGSection(@"Automatic media download",
				  @"Off over mobile by default: this radio is slow and the "
				  @"cache lives on a small disk.", @[
			TGSwitchRow(@"Over Mobile Data", mobile, ^(BOOL on){
				[[TGClient shared] setAutoDownloadOverMobile:on
														wifi:[[TGClient shared] autoDownloadOverWifi]];
				[weakSelf rebuild];
			}),
			TGSwitchRow(@"Over Wi-Fi", wifi, ^(BOOL on){
				[[TGClient shared] setAutoDownloadOverMobile:[[TGClient shared] autoDownloadOverMobile]
														wifi:on];
				[weakSelf rebuild];
			}),
		]),

		TGSection(@"Archive", @"New chats from non-contacts can be archived "
				  @"and muted instead of ringing in. A new message can drag "
				  @"an archived chat back to the main list - the last two "
				  @"switches decide whether it does.", @[
			TGSwitchRow(@"Archive New Chats From Non-Contacts",
					[archiveSettings[@"archive_and_mute_new_chats_from_unknown_users"] boolValue],
					^(BOOL on){
				NSDictionary *old = [TGClient shared].archiveSettings ?: @{};
				[[TGClient shared] setArchiveSettingsArchiveAndMute:on
											keepUnmutedArchived:[old[@"keep_unmuted_chats_archived"] boolValue]
									  keepFolderChatsArchived:[old[@"keep_chats_from_folders_archived"] boolValue]];
				[weakSelf rebuild];
			}),
			TGSwitchRow(@"Keep Unmuted Chats Archived",
					[archiveSettings[@"keep_unmuted_chats_archived"] boolValue],
					^(BOOL on){
				NSDictionary *old = [TGClient shared].archiveSettings ?: @{};
				[[TGClient shared] setArchiveSettingsArchiveAndMute:[old[@"archive_and_mute_new_chats_from_unknown_users"] boolValue]
											keepUnmutedArchived:on
									  keepFolderChatsArchived:[old[@"keep_chats_from_folders_archived"] boolValue]];
				[weakSelf rebuild];
			}),
			TGSwitchRow(@"Keep Folder Chats Archived",
					[archiveSettings[@"keep_chats_from_folders_archived"] boolValue],
					^(BOOL on){
				NSDictionary *old = [TGClient shared].archiveSettings ?: @{};
				[[TGClient shared] setArchiveSettingsArchiveAndMute:[old[@"archive_and_mute_new_chats_from_unknown_users"] boolValue]
											keepUnmutedArchived:[old[@"keep_unmuted_chats_archived"] boolValue]
									  keepFolderChatsArchived:on];
				[weakSelf rebuild];
			}),
		]),

		TGSection(nil, nil, @[
			TGRedRow(@"Clear Local Database", ^{
				[TGAlertSheet showConfirm:@"Cached chats and messages are dropped "
										  @"and fetched again. The session stays."
									title:@"Clear Local Database"
								   action:@"Clear"
							  destructive:YES
								   inView:weakSelf.view
								onConfirm:^{
					[[TGClient shared] clearLocalDatabase];
				}];
			}),
		]),
	];
}

- (NSArray *)powerSavingSections {
	__weak typeof(self) weakSelf = self;
	TGClient *client = [TGClient shared];
	BOOL possible = [TGDevice tier] >= TGDeviceTierLegacy;

	NSString *footer = possible
			? @"Each of these redraws the screen while nothing is being touched, "
			  @"which is where an A5 spends its battery. Turning one off leaves "
			  @"the still picture."
			: @"This device is below the tier that plays these at all, so these "
			  @"switches change nothing here.";

	return @[
		TGSection(@"Resource-intensive processes", footer, @[
			TGSwitchInfoRow(@"Sticker Animation",
					@"Loop animated stickers in chats instead of showing the "
					@"first frame.",
					@"sticker", TGIconTileGreen(),
					[TGCapabilities animatedStickersWanted] && possible, ^(BOOL on){
				[TGCapabilities setAnimatedStickersWanted:on];
				[weakSelf rebuild];
			}),
			TGSwitchInfoRow(@"Chat Wallpaper",
					@"Draw the wallpaper behind messages. A plain background "
					@"scrolls faster.",
					@"chat", TGIconTileSky(),
					[TGCapabilities wallpaperWanted] && possible, ^(BOOL on){
				[TGCapabilities setWallpaperWanted:on];
				[weakSelf rebuild];
			}),
			TGSwitchInfoRow(@"Autoplay GIFs",
					@"Loop GIFs silently in the chat. Off, a GIF plays when "
					@"tapped.",
					@"video", TGIconTileOrchid(),
					[TGCapabilities gifAutoplayWanted] && possible, ^(BOOL on){
				[TGCapabilities setGifAutoplayWanted:on];
				[weakSelf rebuild];
			}),
		]),

		TGSection(@"Media preloading",
				  @"Downloading nothing until it is asked for is the largest "
				  @"saving of the three - it costs radio time as well as CPU.", @[
			TGSwitchInfoRow(@"Over Mobile Data",
					@"Start downloading photos and files before you open them, "
					@"on the cellular radio.",
					@"data", TGIconTileAmber(),
					[client autoDownloadOverMobile], ^(BOOL on){
				[client setAutoDownloadOverMobile:on wifi:[client autoDownloadOverWifi]];
				[weakSelf rebuild];
			}),
			TGSwitchInfoRow(@"Over Wi-Fi",
					@"The same, on Wi-Fi.",
					@"data", TGIconTileCyan(),
					[client autoDownloadOverWifi], ^(BOOL on){
				[client setAutoDownloadOverMobile:[client autoDownloadOverMobile] wifi:on];
				[weakSelf rebuild];
			}),
		]),
	];
}

- (NSArray *)folderSections {
	__weak typeof(self) weakSelf = self;
	NSArray *folders = [TGClient shared].folders;

	NSMutableArray *rows = [NSMutableArray array];
	for (NSDictionary *folder in folders){
		NSString *title = folder[@"title"];
		if (!title.length)
			continue;
		[rows addObject:TGTapRow(title, nil, ^{
			[weakSelf runFolderActionFor:folder];
		})];
	}
	[rows addObject:TGActionRow(@"Create New Folder", ^{
		[TGAlertSheet showInput:@"New Folder"
						message:@"Folders appear as a strip above the chat list."
					placeholder:@"Name"
						   text:nil
						 action:@"Create"
						 inView:weakSelf.view
					   onSubmit:^(NSString *name){
			[[TGClient shared] createFolderNamed:name icon:nil withChats:@[]
									  completion:^(NSInteger folderId){
				if (!folderId){
					[weakSelf toast:@"Telegram refused that name."];
					return;
				}
				[weakSelf toast:[NSString stringWithFormat:
						@"%@ created. Tap it to choose its chats.", name]];
			}];
		}];
	})];

	NSMutableArray *sections = [NSMutableArray array];
	[sections addObject:TGSection(folders.count ? @"Folders" : nil,
			folders.count
					? @"Tap a folder to rename it, choose its chats, or delete it."
					: @"This account has no folders yet. A folder is a filter "
					  @"over the chat list, not a copy of it: a chat in a "
					  @"folder is still in All Chats.",
			rows)];

	NSMutableArray *suggested = [NSMutableArray array];
	for (NSDictionary *entry in self.recommendedFolders){
		NSString *title = entry[@"title"];
		if (!title.length)
			continue;
		[suggested addObject:TGTapRow(title, entry[@"description"], ^{
			[[TGClient shared] createRecommendedFolder:entry[@"folder"]
											completion:^(NSInteger folderId){
				[weakSelf toast:folderId ? [NSString stringWithFormat:@"%@ added.", title]
										 : @"Telegram refused that folder."];
			}];
		})];
	}
	if (suggested.count)
		[sections addObject:TGSection(@"Recommended",
				@"Telegram's own, ready made. Adding one does not move any chat.",
				suggested)];

	return sections;
}

- (void)runFolderActionFor:(NSDictionary *)folder {
	NSInteger folderId = [folder[@"id"] integerValue];
	NSString *title = folder[@"title"] ?: @"Folder";
	if (!folderId)
		return;

	__weak typeof(self) weakSelf = self;
	[TGAlertSheet showChoices:@[@"Rename", @"Add a Chat", @"Remove a Chat",
								@"Delete Folder"]
						title:title
			 destructiveIndex:3
					   inView:self.view
					 onChoice:^(NSInteger index){
		TGSettingsViewController *me = weakSelf;
		if (index == 0){
			[TGAlertSheet showInput:@"Rename Folder" message:nil
						placeholder:@"Name" text:title action:@"Save"
							 inView:me.view onSubmit:^(NSString *name){
				[[TGClient shared] editFolder:folderId name:name chats:nil
								   completion:^(BOOL ok){
					if (!ok)
						[me toast:@"Telegram refused that name."];
				}];
			}];
		} else if (index == 1){
			[me addChatToFolder:folderId named:title];
		} else if (index == 2){
			[me removeChatFromFolder:folderId named:title];
		} else {
			[TGAlertSheet showConfirm:[NSString stringWithFormat:
							@"%@ goes away. The chats in it stay where they are.",
							title]
								title:@"Delete Folder"
							   action:@"Delete"
						  destructive:YES
							   inView:me.view
							onConfirm:^{
				[[TGClient shared] deleteFolder:folderId leavingChats:@[]];
				[me toast:[NSString stringWithFormat:@"%@ deleted.", title]];
			}];
		}
	}];
}

- (void)addChatToFolder:(NSInteger)folderId named:(NSString *)title {
	TGForwardPicker *picker = [[TGForwardPicker alloc] init];
	__weak typeof(self) weakSelf = self;
	picker.onPicked = ^(int64_t chatId){
		[[TGClient shared] folderDetails:folderId completion:^(NSDictionary *current){
			TGSettingsViewController *me = weakSelf;
			if (!current){
				[me toast:@"That folder is gone."];
				return;
			}
			NSArray *included = current[@"included_chat_ids"] ?: @[];
			if ([included containsObject:@(chatId)]){
				[me toast:[NSString stringWithFormat:@"Already in %@.", title]];
				return;
			}
			[[TGClient shared] editFolder:folderId
									 name:nil
									chats:[included arrayByAddingObject:@(chatId)]
							   completion:^(BOOL ok){
				[me toast:ok ? [NSString stringWithFormat:@"Added to %@.", title]
							 : @"Telegram refused that change."];
			}];
		}];
	};
	picker.hidesBottomBarWhenPushed = YES;
	[self.navigationController pushViewController:picker animated:YES];
}

- (void)removeChatFromFolder:(NSInteger)folderId named:(NSString *)title {
	__weak typeof(self) weakSelf = self;
	[[TGClient shared] folderDetails:folderId completion:^(NSDictionary *current){
		TGSettingsViewController *me = weakSelf;
		NSArray *included = current[@"included_chat_ids"] ?: @[];
		if (!included.count){
			[me toast:[NSString stringWithFormat:@"%@ holds no chats yet.", title]];
			return;
		}

		NSMutableArray *names = [NSMutableArray array];
		for (NSNumber *chatId in included)
			[names addObject:TGChatNameForId(chatId)];
		[TGAlertSheet showChoices:names
							title:[NSString stringWithFormat:@"Remove from %@", title]
				 destructiveIndex:-1
						   inView:me.view
						 onChoice:^(NSInteger index){
			NSMutableArray *left = [included mutableCopy];
			[left removeObjectAtIndex:(NSUInteger)index];
			[[TGClient shared] editFolder:folderId name:nil chats:left
							   completion:^(BOOL ok){
				[me toast:ok ? [NSString stringWithFormat:@"Removed from %@.", title]
							 : @"Telegram refused that change."];
			}];
		}];
	}];
}

- (NSArray *)downloadSections {
	__weak typeof(self) weakSelf = self;

	NSMutableArray *rows = [NSMutableArray array];
	for (NSDictionary *download in self.downloads){
		long long size = [download[@"size"] longLongValue];
		NSString *state = [download[@"done"] boolValue] ? @"done"
				: ([download[@"paused"] boolValue] ? @"paused" : @"downloading");
		[rows addObject:TGTapRow(download[@"name"],
				[NSString stringWithFormat:@"%@ - %@", TGBytes(size), state], ^{
			[weakSelf runDownloadActionFor:download];
		})];
	}

	NSMutableArray *sections = [NSMutableArray array];
	[sections addObject:TGSection(self.downloads.count ? @"Files" : nil,
			self.downloads.count
					? @"Tap one to pause it, take it out of the list, or free "
					  @"the disk it is using."
					: @"Nothing has been downloaded yet. A picture or a file "
					  @"opened in a chat appears here.",
			rows)];

	if (self.downloads.count)
		[sections addObject:TGSection(nil, nil, @[
			TGActionRow(self.activeDownloads > 0 ? @"Pause All" : @"Resume All", ^{
				[[TGClient shared] setAllDownloadsPaused:
						weakSelf.activeDownloads > 0];
				[weakSelf loadForPage];
			}),
			TGRedRow(@"Clear List and Free Disk", ^{
				[TGAlertSheet showConfirm:@"Every downloaded file is removed "
										  @"from this device. They can be "
										  @"fetched again from the chat."
									title:@"Clear Downloads"
								   action:@"Clear"
							  destructive:YES
								   inView:weakSelf.view
								onConfirm:^{
					[[TGClient shared] clearDownloadsDeletingFromCache:YES];
					[weakSelf loadForPage];
				}];
			}),
		])];

	return sections;
}

- (void)runDownloadActionFor:(NSDictionary *)download {
	NSInteger fileId = [download[@"fileId"] integerValue];
	BOOL done = [download[@"done"] boolValue];
	BOOL paused = [download[@"paused"] boolValue];
	__weak typeof(self) weakSelf = self;

	NSMutableArray *choices = [NSMutableArray array];
	if (!done)
		[choices addObject:paused ? @"Resume" : @"Pause"];
	[choices addObject:@"Take Out of the List"];
	[choices addObject:@"Delete the File"];

	[TGAlertSheet showChoices:choices
						title:download[@"name"]
			 destructiveIndex:(NSInteger)choices.count - 1
					   inView:self.view
					 onChoice:^(NSInteger index){
		NSString *choice = choices[(NSUInteger)index];
		if ([choice isEqualToString:@"Pause"] || [choice isEqualToString:@"Resume"])
			[[TGClient shared] setDownloadOfFile:fileId
										  paused:[choice isEqualToString:@"Pause"]];
		else if ([choice isEqualToString:@"Take Out of the List"])
			[[TGClient shared] removeFileFromDownloads:fileId deleteFromCache:NO];
		else
			[[TGClient shared] removeFileFromDownloads:fileId deleteFromCache:YES];
		[weakSelf loadForPage];
	}];
}

- (NSArray *)proxySections {
	__weak typeof(self) weakSelf = self;
	BOOL anyEnabled = NO;
	for (NSDictionary *proxy in self.proxies)
		anyEnabled = anyEnabled || [proxy[@"enabled"] boolValue];

	NSMutableArray *rows = [NSMutableArray array];
	[rows addObject:TGCheckRow(@"No proxy", nil, !anyEnabled, ^{
		[[TGClient shared] disableProxy];
		[weakSelf loadForPage];
	})];
	for (NSDictionary *proxy in self.proxies){
		NSString *name = [NSString stringWithFormat:@"%@:%@",
				proxy[@"server"] ?: @"?", proxy[@"port"] ?: @0];
		[rows addObject:TGCheckRow(name, proxy[@"kind"],
				[proxy[@"enabled"] boolValue], ^{
			[weakSelf runProxyActionFor:proxy];
		})];
	}

	return @[
		TGSection(@"Connection",
				  @"A proxy is TDLib's own, not the system's: it applies to "
				  @"this app and to nothing else on the phone.", rows),
		TGSection(nil, nil, @[
			TGActionRow(@"Add Proxy", ^{ [weakSelf addProxyByAsking]; }),
		]),
	];
}

- (void)addProxyByAsking {
	__weak typeof(self) weakSelf = self;
	[TGAlertSheet showInput:@"Add Proxy"
					message:@"A t.me/proxy or tg://proxy link, or host:port "
							@"for a SOCKS5 server."
				placeholder:@"t.me/proxy?... or 1.2.3.4:1080"
					   text:nil
					 action:@"Add"
					 inView:self.view
				   onSubmit:^(NSString *text){
		TGSettingsViewController *me = weakSelf;
		void (^added)(NSInteger) = ^(NSInteger proxyId){
			if (!proxyId){
				[me toast:@"Telegram could not read that as a proxy."];
				return;
			}
			[me loadForPage];
		};

		if ([text rangeOfString:@"proxy"].location != NSNotFound &&
			[text rangeOfString:@"?"].location != NSNotFound){
			if (![[TGClient shared] addProxyFromLink:text completion:added])
				[me toast:@"That link carries no server and port."];
			return;
		}

		NSArray *parts = [text componentsSeparatedByString:@":"];
		NSInteger port = parts.count > 1 ? [parts[1] integerValue] : 0;
		if (parts.count < 2 || port <= 0){
			[me toast:@"A proxy needs a host and a port."];
			return;
		}
		[[TGClient shared] addProxyAtServer:parts[0] port:port kind:@"socks5"
								   username:nil password:nil secret:nil
									 enable:YES completion:added];
	}];
}

- (void)runProxyActionFor:(NSDictionary *)proxy {
	NSInteger proxyId = [proxy[@"id"] integerValue];
	NSString *name = [NSString stringWithFormat:@"%@:%@",
			proxy[@"server"] ?: @"?", proxy[@"port"] ?: @0];
	__weak typeof(self) weakSelf = self;

	[TGAlertSheet showChoices:@[@"Use This Proxy", @"Check It Works",
								@"Change Address", @"Remove"]
						title:name
			 destructiveIndex:3
					   inView:self.view
					 onChoice:^(NSInteger index){
		TGSettingsViewController *me = weakSelf;
		if (index == 0){
			[[TGClient shared] enableProxy:proxyId];
			[me loadForPage];
		} else if (index == 1){
			[me checkProxy:proxy named:name];
		} else if (index == 2){
			[me editProxyAddress:proxy named:name];
		} else {
			[[TGClient shared] removeProxy:proxyId];
			[me loadForPage];
		}
	}];
}

- (void)checkProxy:(NSDictionary *)proxy named:(NSString *)name {
	__weak typeof(self) weakSelf = self;
	NSString *server = proxy[@"server"];
	NSInteger port = [proxy[@"port"] integerValue];
	NSString *kind = proxy[@"kind"];

	[[TGClient shared] testProxyAtServer:server port:port kind:kind
								username:nil password:nil secret:nil
							  completion:^(BOOL works){
		TGSettingsViewController *me = weakSelf;
		if (!works){
			[me toast:[NSString stringWithFormat:
					@"%@ will not carry Telegram.", name]];
			return;
		}
		[[TGClient shared] pingProxyAtServer:server port:port kind:kind
									username:nil password:nil secret:nil
								  completion:^(double seconds){
			[me toast:seconds >= 0
					? [NSString stringWithFormat:@"%@ works - %.0f ms",
							name, seconds * 1000.0]
					: [NSString stringWithFormat:@"%@ works", name]];
		}];
	}];
}

- (void)editProxyAddress:(NSDictionary *)proxy named:(NSString *)name {
	NSInteger proxyId = [proxy[@"id"] integerValue];
	BOOL wasEnabled = [proxy[@"enabled"] boolValue];
	NSString *kind = proxy[@"kind"];
	__weak typeof(self) weakSelf = self;

	[TGAlertSheet showInput:@"Change Address"
					message:@"host:port. The kind of proxy stays as it is."
				placeholder:@"1.2.3.4:1080"
					   text:name
					 action:@"Save"
					 inView:self.view
				   onSubmit:^(NSString *text){
		TGSettingsViewController *me = weakSelf;
		NSArray *parts = [text componentsSeparatedByString:@":"];
		NSInteger port = parts.count > 1 ? [parts[1] integerValue] : 0;
		if (parts.count < 2 || port <= 0){
			[me toast:@"A proxy needs a host and a port."];
			return;
		}
		[[TGClient shared] editProxy:proxyId
							  server:parts[0]
								port:port
								kind:kind
							username:nil password:nil secret:nil
							  enable:wasEnabled
						  completion:^(BOOL ok){
			if (!ok){
				[me toast:@"Telegram refused that address."];
				return;
			}
			[me loadForPage];
		}];
	}];
}

- (void)clearTemporaryFiles {
	NSFileManager *files = [NSFileManager defaultManager];
	NSString *tmp = NSTemporaryDirectory();
	long long freed = 0;
	for (NSString *entry in [files contentsOfDirectoryAtPath:tmp error:nil]){
		NSString *path = [tmp stringByAppendingPathComponent:entry];
		freed += [[files attributesOfItemAtPath:path error:nil] fileSize];
		[files removeItemAtPath:path error:nil];
	}
	[self toast:[NSString stringWithFormat:@"Freed %@", TGBytes(freed)]];
}

@end
