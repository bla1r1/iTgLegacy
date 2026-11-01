//
// TGGroupSettingsViewController.m - one screen for everything a group is.
//
// The group profile's More menu used to grow one row per setting: Photo,
// Name, Description, Invite Link, Permissions, Sign Messages, Join to Send,
// All History, Welcome Messages, Direct Messages, Import, Send as, Clear by
// Date, Chat Tools. Each row asked the server what it sat on and answered
// with a sheet. A settings screen can show the value, group the rows by what
// they change, and leave the profile menu for the things a profile does.
//
// The chat id is the only thing the caller passes. Every action here names
// that id directly, so nothing is routed through the profile controller
// behind this screen.
//
#import "TGGroupSettingsViewController.h"
#import "TGClient.h"
#import "TGTheme.h"
#import "TGStyle.h"
#import "TGAlertSheet.h"
#import "TGSnackbar.h"
#import "TGContactsViewController.h"
#import "TGChatToolsViewController.h"
#import "TGGroupMemberActions.h"
#import "TGMemberCell.h"
#import "TGProfileViewController.h"
#import "TGIcons.h"
#import "TGGroupCallViewController.h"
#import "TGVideoChatSetupViewController.h"
#import "TGAntiSpamViewController.h"

/// The rows a section can hold. A switch draws a UISwitch, a member row a
/// face, and everything else a value with a chevron.
typedef NS_ENUM(NSInteger, TGGroupRowKind) {
	TGGroupRowInfo = 0,
	TGGroupRowAction,
	TGGroupRowSwitch,
	TGGroupRowUsername,
	TGGroupRowMember,
};

/// A switch that names the setting it changes, so a reload can rebuild rows
/// without an index pointing at the wrong one.
@interface TGGroupSwitch : UISwitch
@property (nonatomic, copy) NSString *key;
@end

@implementation TGGroupSwitch
@end

static NSMutableDictionary *TGRow(NSString *title, NSString *detail,
								  NSString *action, TGGroupRowKind kind) {
	NSMutableDictionary *row = [@{@"kind" : @(kind), @"title" : title ?: @""}
			mutableCopy];
	if (detail)
		row[@"detail"] = detail;
	if (action)
		row[@"action"] = action;
	return row;
}

static NSMutableDictionary *TGInfoRow(NSString *title, NSString *detail,
									  NSString *action) {
	return TGRow(title, detail, action, TGGroupRowInfo);
}

static NSMutableDictionary *TGActionRow(NSString *title, NSString *detail,
										NSString *action, BOOL destructive) {
	NSMutableDictionary *row = TGRow(title, detail, action, TGGroupRowAction);
	if (destructive)
		row[@"destructive"] = @YES;
	return row;
}

/// The same row when the account has no right for it: the title and the
/// reason stay on screen, the chevron and the tap do not. That is what
/// Telegram does for a switch an administrator may see but not move.
static NSMutableDictionary *TGDisabledRow(NSString *title, NSString *reason,
										  NSString *action) {
	NSMutableDictionary *row = TGActionRow(title, reason, nil, NO);
	if (action)
		row[@"refusedAction"] = action;
	row[@"disabled"] = @YES;
	return row;
}

static NSMutableDictionary *TGSwitchRow(NSString *title, NSString *detail,
										NSString *key, BOOL on, BOOL enabled) {
	NSMutableDictionary *row = TGRow(title, detail, nil, TGGroupRowSwitch);
	row[@"switch"] = key;
	row[@"on"] = @(on);
	row[@"enabled"] = @(enabled);
	return row;
}

static NSMutableDictionary *TGUsernameRow(NSString *username, BOOL active) {
	NSMutableDictionary *row = TGRow([@"@" stringByAppendingString:username],
									 active ? @"Active" : @"Disabled",
									 nil, TGGroupRowUsername);
	row[@"switch"] = [@"@" stringByAppendingString:username];
	row[@"username"] = username;
	row[@"active"] = @(active);
	row[@"on"] = @(active);
	row[@"enabled"] = @YES;
	return row;
}

static NSDictionary *TGSection(NSString *header, NSString *footer, NSArray *rows) {
	NSMutableDictionary *section = [NSMutableDictionary dictionary];
	if (header) section[@"header"] = header;
	if (footer) section[@"footer"] = footer;
	section[@"rows"] = rows ?: @[];
	return section;
}

@interface TGGroupSettingsViewController () <UIImagePickerControllerDelegate,
		UINavigationControllerDelegate>
/// The chat record: its type says which rows this chat supports.
@property (nonatomic, strong) NSDictionary *chat;
/// chatProfile: description, member count, the primary invite link.
@property (nonatomic, copy) NSString *descriptionText;
/// supergroupSettingsForChat: usernames and the mode switches; nil for a
/// basic group, which has none of them.
@property (nonatomic, strong) NSDictionary *settings;
/// supergroupFullInfo: slow mode lives here and nowhere else.
@property (nonatomic, strong) NSDictionary *groupInfo;
@property (nonatomic, strong) NSArray *members;
/// Built fresh after every read; cellForRow reads a descriptor rather than
/// counting sections by hand.
@property (nonatomic, strong) NSArray *sections;
@property (nonatomic, copy) NSString *editable;
@property (nonatomic, strong) NSMutableArray *active;
@property (nonatomic, strong) NSMutableArray *disabled;
@property (nonatomic, copy) NSString *inviteLink;
@property (nonatomic, assign) NSInteger memberCount;
@property (nonatomic, assign) BOOL signMessages;
@property (nonatomic, assign) BOOL joinToSend;
@property (nonatomic, assign) BOOL allHistory;
/// Aggressive anti-spam is a supergroup-only switch; `canToggleAntiSpam`
/// comes from the same full record and keeps the switch disabled where
/// Telegram does not allow it.
@property (nonatomic, assign) BOOL aggressiveAntiSpam;
@property (nonatomic, assign) BOOL canToggleAntiSpam;
@property (nonatomic, assign) BOOL hasPhoto;
/// This account's own role in the chat. A plain member sees the group's
/// identity and people; the management rows belong to the owner and the
/// administrators, and Telegram would refuse every one of them to anybody
/// else. `myStatus` is "owner", "admin", "member" or nil until it arrives.
@property (nonatomic, copy) NSString *myStatus;
@property (nonatomic, strong) NSDictionary *myRights;
@property (nonatomic, assign) BOOL canManage;
/// The owner has every right; an administrator has only the boxes Telegram
/// ticked. A row whose right is missing is drawn disabled instead of
/// pretending the tap will work.
@property (nonatomic, assign) BOOL isOwner;
@property (nonatomic, assign) BOOL canChangeInfo;
@property (nonatomic, assign) BOOL canInvite;
@property (nonatomic, assign) BOOL canRestrict;
@property (nonatomic, assign) BOOL canDeleteMessages;
/// Kept because a switch's answer is not a full re-read: the local value
/// flips only after Telegram accepted it.
@property (nonatomic, assign) BOOL loaded;
@property (nonatomic, assign) BOOL busy;
@property (nonatomic, assign) BOOL pickingPhoto;
@property (nonatomic, assign) BOOL editingNames;
@end

@implementation TGGroupSettingsViewController

- (instancetype)init {
	return [super initWithStyle:UITableViewStyleGrouped];
}

- (void)viewDidLoad {
	[super viewDidLoad];
	NSLog(@"TGGroupSettings: opened for chat %lld", self.chatId);
	self.title = self.chatTitle.length ? self.chatTitle : @"Group Settings";
	self.active = [NSMutableArray array];
	self.disabled = [NSMutableArray array];
	// The screen is real before the first answer: a pushed blank table and a
	// nav bar still saying the group's name read as "the tap did nothing".
	self.sections = @[TGSection(@"Group Settings",
			@"Reading the group from Telegram.", @[TGInfoRow(@"Loading",
					@"Waiting for the group record", nil)])];
	self.loaded = YES;
	if ([self respondsToSelector:@selector(setEdgesForExtendedLayout:)])
		self.edgesForExtendedLayout = UIRectEdgeNone;
	[self applyTheme];
	[self load];

	// A tap opens the person's profile; a hold keeps the member sheet, the
	// same split the group profile uses.
	UILongPressGestureRecognizer *memberHold = [[UILongPressGestureRecognizer alloc]
			initWithTarget:self action:@selector(memberRowHeld:)];
	memberHold.minimumPressDuration = 0.5;
	memberHold.cancelsTouchesInView = YES;
	[self.tableView addGestureRecognizer:memberHold];

	__weak typeof(self) weakSelf = self;
	[[NSNotificationCenter defaultCenter] addObserverForName:TGThemeChangedNotification
			object:nil queue:[NSOperationQueue mainQueue]
		 usingBlock:^(NSNotification *note) {
		[weakSelf applyTheme];
		[weakSelf.tableView reloadData];
	}];
	// A switch moved on another device is a full-info update here. The screen
	// re-reads rather than showing the value it opened with.
	[[NSNotificationCenter defaultCenter] addObserverForName:TGFullInfoChangedNotification
			object:nil queue:[NSOperationQueue mainQueue]
		 usingBlock:^(NSNotification *note) {
		NSNumber *chatId = note.userInfo[@"id"];
		if (chatId && [chatId longLongValue] == weakSelf.chatId)
			[weakSelf load];
	}];
	[[NSNotificationCenter defaultCenter] addObserverForName:TGChatMembersChangedNotification
			object:nil queue:[NSOperationQueue mainQueue]
		 usingBlock:^(NSNotification *note) {
		NSNumber *chatId = note.userInfo[@"chatId"];
		if (chatId && [chatId longLongValue] == weakSelf.chatId)
			[weakSelf load];
	}];
}

- (void)dealloc {
	[[NSNotificationCenter defaultCenter] removeObserver:self];
}

- (void)viewWillAppear:(BOOL)animated {
	[super viewWillAppear:animated];
	[self applyTheme];
	[self load];
}

- (void)applyTheme {
	[[TGTheme shared] styleGroupedTable:self.tableView];
	[[TGTheme shared] styleNavigationBar:self.navigationController.navigationBar];
}

#pragma mark - the chat behind the screen

- (BOOL)isSupergroupChat {
	return [self.chat[@"type"][@"@type"] isEqualToString:@"chatTypeSupergroup"];
}

- (BOOL)isChannelChat {
	return [self isSupergroupChat] &&
		   [self.chat[@"type"][@"is_channel"] boolValue];
}

- (BOOL)isBasicGroupChat {
	return [self.chat[@"type"][@"@type"] isEqualToString:@"chatTypeBasicGroup"];
}

- (void)load {
	__weak typeof(self) weakSelf = self;
	[[TGClient shared] chatRecordForChat:self.chatId completion:^(NSDictionary *chat){
		TGGroupSettingsViewController *me = weakSelf;
		if (!me)
			return;
		if (!chat){
			// No record means no type, and every row below is decided by the
			// type. A blank screen would leave the user guessing why.
			me.loaded = YES;
			me.sections = @[TGSection(@"Group Settings",
					@"Telegram did not return this chat. Reopen the profile to try again.",
					@[TGInfoRow(@"Unavailable", @"No answer from Telegram", nil)])];
			[me reloadTableDebounced];
			return;
		}
		me.chat = chat;
		NSString *title = chat[@"title"];
		if (title.length){
			me.chatTitle = title;
			me.title = title;
		}
		me.hasPhoto = [[TGClient shared] photoFileIdForChat:me.chatId] != nil;
		me.loaded = YES;
		[me rebuild];
		[me loadOwnRole];
	}];
	[[TGClient shared] chatProfile:self.chatId completion:^(NSDictionary *info){
		TGGroupSettingsViewController *me = weakSelf;
		if (!me)
			return;
		me.descriptionText = info[@"description"] ?: @"";
		me.memberCount = [info[@"members"] integerValue];
		me.inviteLink = info[@"inviteLink"] ?: @"";
		[me rebuild];
	}];
	[[TGClient shared] supergroupSettingsForChat:self.chatId completion:^(NSDictionary *settings){
		TGGroupSettingsViewController *me = weakSelf;
		if (!me)
			return;
		me.settings = settings;
		me.active = [settings[@"active"] isKindOfClass:NSArray.class]
				? [settings[@"active"] mutableCopy] : [NSMutableArray array];
		me.disabled = [settings[@"disabled"] isKindOfClass:NSArray.class]
				? [settings[@"disabled"] mutableCopy] : [NSMutableArray array];
		me.editable = settings[@"editable"] ?: @"";
		[me rebuild];
	}];
	[[TGClient shared] groupFullInfoForChat:self.chatId completion:^(NSDictionary *info){
		TGGroupSettingsViewController *me = weakSelf;
		if (!me)
			return;
		me.groupInfo = info;
		me.aggressiveAntiSpam = [info[@"has_aggressive_anti_spam_enabled"] boolValue];
		me.canToggleAntiSpam = [info[@"can_toggle_aggressive_anti_spam"] boolValue];
		[me rebuild];
	}];
	[[TGClient shared] supergroupFlagsForChat:self.chatId
			completion:^(BOOL signMessages, BOOL joinToSend, BOOL allHistory, BOOL ok){
		TGGroupSettingsViewController *me = weakSelf;
		if (!me || !ok)
			return;
		me.signMessages = signMessages;
		me.joinToSend = joinToSend;
		me.allHistory = allHistory;
		[me rebuild];
	}];
	[[TGClient shared] membersOfChat:self.chatId completion:^(NSArray *members){
		TGGroupSettingsViewController *me = weakSelf;
		if (!me)
			return;
		me.members = members ?: @[];
		[me rebuild];
	}];
}

- (void)loadOwnRole {
	// The member list is the aggregate; this is the one record that says
	// what this account may actually change. Without it the screen would
	// offer a plain member every switch and then show Telegram's refusal.
	int64_t meId = [[TGClient shared].me[@"id"] longLongValue];
	if (!meId || !self.chatId){
		self.canManage = NO;
		return;
	}
	__weak typeof(self) weakSelf = self;
	[[TGClient shared] chatMember:meId inChat:self.chatId
						completion:^(NSDictionary *member){
		TGGroupSettingsViewController *me = weakSelf;
		if (!me)
			return;
		NSDictionary *status = [member[@"status"] isKindOfClass:NSDictionary.class]
				? member[@"status"] : @{};
		NSString *kind = status[@"@type"];
		me.myStatus = [kind isEqualToString:@"chatMemberStatusCreator"] ? @"owner"
				: ([kind isEqualToString:@"chatMemberStatusAdministrator"]
						? @"admin" : @"member");
		me.myRights = [status[@"rights"] isKindOfClass:NSDictionary.class]
				? status[@"rights"] : @{};
		BOOL owner = [me.myStatus isEqualToString:@"owner"];
		me.isOwner = owner;
		me.canManage = owner || [me.myStatus isEqualToString:@"admin"];
		me.canChangeInfo = owner || [me.myRights[@"can_change_info"] boolValue];
		me.canInvite = owner || [me.myRights[@"can_invite_users"] boolValue];
		me.canRestrict = owner || [me.myRights[@"can_restrict_members"] boolValue];
		me.canDeleteMessages = owner ||
				[me.myRights[@"can_delete_messages"] boolValue];
		// A basic group's administrators have no rights object in this
		// TDLib, and any unrestricted member may invite. The chat's own
		// permissions are the source for both.
		if ([me isBasicGroupChat]){
			if (!owner){
				id canInvite = me.chat[@"permissions"][@"can_invite_users"];
				me.canInvite = canInvite ? [canInvite boolValue] : YES;
			}
			if (me.canManage && !owner){
				me.canChangeInfo = YES;
				me.canDeleteMessages = YES;
			}
		}
		[me rebuild];
	}];
}

- (void)reloadTableDebounced {
	[NSObject cancelPreviousPerformRequestsWithTarget:self selector:@selector(doReloadTable) object:nil];
	[self performSelector:@selector(doReloadTable) withObject:nil afterDelay:0.05];
}

- (void)doReloadTable {
	[self.tableView reloadData];
}

- (void)showRefusal:(NSString *)error title:(NSString *)title {
	[TGAlertSheet showMessage:(error.length ? error : @"Telegram refused that.")
						title:title inView:self.view];
}

#pragma mark - the section model

- (NSString *)permissionsDetail {
	NSDictionary *p = self.chat[@"permissions"];
	if (![p isKindOfClass:NSDictionary.class])
		return @"Change";
	BOOL send = [p[@"can_send_basic_messages"] boolValue] ||
				[p[@"can_send_messages"] boolValue];
	BOOL media = [p[@"can_send_photos"] boolValue] ||
				 [p[@"can_send_videos"] boolValue] ||
				 [p[@"can_send_documents"] boolValue];
	if (!send)
		return @"Read only";
	return media ? @"Everything allowed" : @"Messages only";
}

- (NSString *)slowModeDetail {
	NSInteger seconds = [self.groupInfo[@"slow_mode_delay"] integerValue];
	if (seconds <= 0)
		return @"Off";
	if (seconds < 60)
		return [NSString stringWithFormat:@"%ld s", (long)seconds];
	if (seconds < 3600)
		return [NSString stringWithFormat:@"%ld min", (long)(seconds / 60)];
	return [NSString stringWithFormat:@"%ld h", (long)(seconds / 3600)];
}

- (NSString *)labelForTab:(NSString *)tab {
	if ([tab isEqualToString:@"media"]) return @"Media";
	if ([tab isEqualToString:@"files"]) return @"Files";
	if ([tab isEqualToString:@"links"]) return @"Links";
	if ([tab isEqualToString:@"music"]) return @"Music";
	if ([tab isEqualToString:@"voice"]) return @"Voice";
	if ([tab isEqualToString:@"gifs"])  return @"GIFs";
	return @"Posts";
}

- (void)updateEditButton {
	BOOL canOrder = self.canManage && self.canChangeInfo &&
			self.active.count > 1 && self.settings != nil;
	if (!canOrder){
		self.navigationItem.rightBarButtonItem = nil;
		return;
	}
	self.navigationItem.rightBarButtonItem =
			[[UIBarButtonItem alloc] initWithTitle:(self.editingNames ? @"Done" : @"Edit")
											  style:UIBarButtonItemStylePlain
											 target:self action:@selector(toggleEditing)];
}

- (void)toggleEditing {
	self.editingNames = !self.editingNames;
	[self.tableView setEditing:self.editingNames animated:YES];
	[self updateEditButton];
}

- (void)rebuild {
	if (!self.loaded || !self.chat)
		return;
	BOOL supergroup = [self isSupergroupChat];
	BOOL channel = [self isChannelChat];
	BOOL basic = [self isBasicGroupChat];
	BOOL manager = self.canManage;
	NSMutableArray *sections = [NSMutableArray array];

	// ── identity ────────────────────────────────────────────────────────
	NSMutableArray *info = [NSMutableArray array];
	BOOL editInfo = manager && self.canChangeInfo;
	NSString *photoDetail = self.hasPhoto ? @"Change" : @"Set";
	NSString *nameDetail = self.chatTitle ?: @"";
	NSString *noInfoRight = @"An administrator with the change-info right does this";
	if (manager && !self.canChangeInfo){
		[info addObject:TGDisabledRow(@"Group Photo", noInfoRight, @"photo")];
		[info addObject:TGDisabledRow(@"Group Name", nameDetail, @"name")];
	} else {
		[info addObject:TGInfoRow(@"Group Photo",
				manager ? photoDetail : (self.hasPhoto ? @"Set" : @"None"),
				manager ? @"photo" : nil)];
		[info addObject:TGInfoRow(@"Group Name", nameDetail, manager ? @"name" : nil)];
	}
	if (supergroup){
		if (manager && !self.canChangeInfo){
			[info addObject:TGDisabledRow(@"Description",
					self.descriptionText.length ? self.descriptionText
							: @"No description", @"description")];
		} else {
			[info addObject:TGInfoRow(@"Description",
					self.descriptionText.length ? self.descriptionText
							: (manager ? @"Add a description" : @"None"),
					manager ? @"description" : nil)];
		}
		if (manager && !self.canInvite){
			[info addObject:TGDisabledRow(@"Invite Link",
					self.inviteLink.length ? self.inviteLink
							: @"An administrator with the invite right manages links",
					@"invite")];
		} else if (manager || self.inviteLink.length){
			[info addObject:TGInfoRow(@"Invite Link",
					self.inviteLink.length ? self.inviteLink
							: (manager ? @"Manage" : @"None"),
					manager ? @"invite" : nil)];
		}
		// Telegram names this row Group Type / Channel Type and sits it
		// above the link. Private here means no active username.
		BOOL isPublic = self.editable.length > 0 || self.active.count > 0;
		NSString *typeTitle = channel ? @"Channel Type" : @"Group Type";
		NSString *typeDetail = isPublic
				? (self.editable.length
						? [@"@" stringByAppendingString:self.editable] : @"Public")
				: @"Private";
		if (editInfo)
			[info addObject:TGInfoRow(typeTitle, typeDetail, @"groupType")];
		else if (manager)
			[info addObject:TGDisabledRow(typeTitle, typeDetail, @"groupType")];
		else
			[info addObject:TGInfoRow(typeTitle, typeDetail, nil)];
		[info addObject:TGInfoRow(@"Main Profile Tab",
				[self labelForTab:self.settings[@"mainTab"]],
				editInfo ? @"tab" : nil)];
	}
	if (basic)
		[info addObject:TGInfoRow(@"Group Type", @"Private", nil)];
	if (self.memberCount > 0)
		[info addObject:TGInfoRow(channel ? @"Subscribers" : @"Members",
				[NSString stringWithFormat:@"%ld", (long)self.memberCount], nil)];
	if (basic && manager)
		[info addObject:TGActionRow(@"Upgrade to Supergroup",
				@"Basic groups stop at 200 members", @"upgrade", NO)];
	[sections addObject:TGSection(@"Group Info",
			manager ? (basic ? @"A basic group has no username, invite link or supergroup "
					@"permissions. Upgrading gives it those and a new chat id."
				  : @"The public identity of this group. Telegram applies each "
					@"change or says why not.")
					: @"Anyone in the group can read this. Changing it needs an "
					  @"administrator.",
			info)];

	// ── people ──────────────────────────────────────────────────────────
	if (!channel){
		NSMutableArray *people = [NSMutableArray array];
		if (manager && !self.canInvite)
			[people addObject:TGDisabledRow(@"Add Members",
					@"An administrator with the invite right adds people",
					@"addMembers")];
		else if (self.canInvite)
			[people addObject:TGActionRow(@"Add Members", nil, @"addMembers", NO)];
		[people addObject:TGActionRow(@"Find Member", @"Search by name or @username",
									  @"findMember", NO)];
		for (NSDictionary *member in self.members)
			[people addObject:@{@"kind" : @(TGGroupRowMember), @"member" : member}];
		NSString *header = self.memberCount > 0
				? [NSString stringWithFormat:@"%ld members", (long)self.memberCount]
				: @"Members";
		[sections addObject:TGSection(header,
				@"Tap a member for their profile; hold for their actions. The "
				@"list shows the members Telegram returned first.", people)];
	}

	// ── calls ───────────────────────────────────────────────────────────
	NSMutableArray *calls = [NSMutableArray array];
	[calls addObject:TGActionRow(@"Group Call",
			@"Join, leave or manage the active call", @"groupCall", NO)];
	[calls addObject:TGActionRow(@"Video Chat",
			@"Create, schedule and record", @"videoChat", NO)];
	[sections addObject:TGSection(@"Calls",
			@"A video chat is a group call bound to this chat. The call screen "
			@"shows Telegram's participant list, messages and stream metadata; "
			@"this client has no group-call audio engine.", calls)];

	// ── what the group does ─────────────────────────────────────────────
	if (supergroup && manager){
		BOOL canBehaviour = self.canChangeInfo;
		NSMutableArray *behaviour = [NSMutableArray array];
		if (self.canRestrict)
			[behaviour addObject:TGActionRow(@"Permissions",
					[self permissionsDetail], @"permissions", NO)];
		else
			[behaviour addObject:TGDisabledRow(@"Permissions",
					[self permissionsDetail], @"permissions")];
		if (canBehaviour)
			[behaviour addObject:TGActionRow(@"Slow Mode", [self slowModeDetail],
											 @"slow", NO)];
		else
			[behaviour addObject:TGDisabledRow(@"Slow Mode", [self slowModeDetail],
											   @"slow")];
		[behaviour addObject:TGSwitchRow(@"Sign Messages", nil, @"sign",
										 self.signMessages, canBehaviour)];
		[behaviour addObject:TGSwitchRow(@"Join to Send", nil, @"join",
										 self.joinToSend, canBehaviour)];
		[behaviour addObject:TGSwitchRow(@"All History", nil, @"history",
										 self.allHistory, canBehaviour)];
		[behaviour addObject:TGSwitchRow(@"Aggressive Anti-Spam",
				self.canToggleAntiSpam
						? (self.aggressiveAntiSpam
								? @"Deletes suspicious messages automatically"
								: @"Off")
						: @"Telegram does not allow this group to turn it on",
				@"antispam", self.aggressiveAntiSpam, self.canToggleAntiSpam)];
		[behaviour addObject:TGActionRow(@"Anti-Spam False Positives",
				@"Report a message deleted by mistake", @"antispamFalsePositive",
				NO)];
		[behaviour addObject:TGSwitchRow(@"Join by Request",
				[self.settings[@"joinByRequest"] boolValue]
						? @"Administrators approve each join"
						: @"Anyone with the link joins",
				@"joinRequests",
				[self.settings[@"joinByRequest"] boolValue], canBehaviour)];
		BOOL canHide = [self.settings[@"canHideMembers"] boolValue];
		[behaviour addObject:TGSwitchRow(@"Hidden Members",
				canHide ? (self.settings[@"hiddenMembers"]
						? @"Members are hidden" : @"Members are listed")
						: @"Telegram does not allow this group to hide members",
				@"hidden", [self.settings[@"hiddenMembers"] boolValue],
				canBehaviour && canHide)];
		if (!channel){
			[behaviour addObject:TGSwitchRow(@"Forum Mode",
					self.settings[@"isForum"] ? @"Topics are on" : @"One message stream",
					@"forum", [self.settings[@"isForum"] boolValue], canBehaviour)];
			BOOL broadcast = [self.settings[@"isBroadcast"] boolValue];
			if (canBehaviour)
				[behaviour addObject:TGActionRow(@"Broadcast Group",
						broadcast ? @"On" : @"Convert",
						broadcast ? nil : @"broadcast", NO)];
			else
				[behaviour addObject:TGDisabledRow(@"Broadcast Group",
						broadcast ? @"On" : @"Convert", @"broadcast")];
			if (canBehaviour)
				[behaviour addObject:TGActionRow(@"Welcome Messages",
						@"Greet someone when they join", @"welcome", NO)];
			else
				[behaviour addObject:TGDisabledRow(@"Welcome Messages",
						@"Greet someone when they join", @"welcome")];
		}
		[behaviour addObject:TGSwitchRow(@"Automatic Translation",
				self.settings[@"automaticTranslation"]
						? @"The chat suggests a translation"
						: @"No automatic translation",
				@"translation",
				[self.settings[@"automaticTranslation"] boolValue], canBehaviour)];
		if (self.canInvite)
			[behaviour addObject:TGActionRow(@"Join Requests", nil,
											 @"joinRequests", NO)];
		else
			[behaviour addObject:TGDisabledRow(@"Join Requests",
					@"An administrator with the invite right answers requests",
					@"joinRequests")];
		[sections addObject:TGSection(@"Permissions and Behaviour",
				@"Telegram applies the switch that moved or refuses it with a "
				@"reason. A row this account cannot change says who can.",
				behaviour)];
	}

	// ── tools ───────────────────────────────────────────────────────────
	// ── usernames ───────────────────────────────────────────────────────
	if (supergroup && self.settings && manager){
		NSMutableArray *names = [NSMutableArray array];
		if (self.canChangeInfo){
			[names addObject:TGInfoRow(@"Editable Username",
					self.editable.length ? [@"@" stringByAppendingString:self.editable]
										 : @"None", @"username")];
			if (self.editable.length)
				[names addObject:TGActionRow(@"Remove Username",
						@"Keeps every active name below", @"removeUsername", YES)];
			if (self.active.count > 1)
				[names addObject:TGActionRow(@"Disable All Usernames",
						@"Every name except the editable one",
						@"disableUsernames", YES)];
		} else {
			[names addObject:TGDisabledRow(@"Editable Username",
					self.editable.length ? [@"@" stringByAppendingString:self.editable]
										 : @"None", @"username")];
		}
		[sections addObject:TGSection(@"Usernames",
				@"The public names in front of this group's links. The editable "
				@"name is the one Telegram shows first.", names)];

		if (self.active.count){
			NSMutableArray *rows = [NSMutableArray array];
			for (NSString *name in self.active){
				NSMutableDictionary *row = TGUsernameRow(name, YES);
				row[@"enabled"] = @(self.canChangeInfo);
				[rows addObject:row];
			}
			[sections addObject:TGSection(@"Active usernames",
					self.active.count > 1
							? @"Tap Edit and drag a row to change the order of the names "
							  @"on the group's profile."
							: nil, rows)];
		}
		if (self.disabled.count){
			NSMutableArray *rows = [NSMutableArray array];
			for (NSString *name in self.disabled){
				NSMutableDictionary *row = TGUsernameRow(name, NO);
				row[@"enabled"] = @(self.canChangeInfo);
				[rows addObject:row];
			}
			[sections addObject:TGSection(@"Disabled usernames",
					@"Every name here can be switched back on. Telegram keeps "
					@"them on the group while they are off.", rows)];
		}
	}

	// ── tools ───────────────────────────────────────────────────────────
	if (manager){
		NSMutableArray *tools = [NSMutableArray array];
		[tools addObject:TGActionRow(@"Chat Tools", @"Log, statistics, theme",
									 @"chatTools", NO)];
		if (channel)
			[tools addObject:TGActionRow(@"Direct Messages", @"Reader replies",
										 @"directMessages", NO)];
		[tools addObject:TGActionRow(@"Import Messages", @"From an export file",
									 @"import", NO)];
		if (supergroup)
			[tools addObject:TGActionRow(@"Send as", @"Who a post is from",
										 @"sendAs", NO)];
		if (self.canDeleteMessages)
			[tools addObject:TGActionRow(@"Clear by Date", @"Delete older messages",
										 @"clearByDate", YES)];
		else
			[tools addObject:TGDisabledRow(@"Clear by Date",
					@"An administrator with the delete-messages right clears",
					@"clearByDate")];
		if (supergroup){
			if (self.canChangeInfo){
				[tools addObject:TGActionRow(@"Group Stickers", nil,
											 @"groupStickers", NO)];
				[tools addObject:TGActionRow(@"Custom Emoji Stickers", nil,
											 @"customEmojiStickers", NO)];
			} else {
				[tools addObject:TGDisabledRow(@"Group Stickers",
						@"An administrator with the change-info right sets it",
						@"groupStickers")];
				[tools addObject:TGDisabledRow(@"Custom Emoji Stickers",
						@"An administrator with the change-info right sets it",
						@"customEmojiStickers")];
			}
		}
		[sections addObject:TGSection(@"Tools", nil, tools)];
	}

	// ── leaving and deleting ────────────────────────────────────────────
	if (self.myStatus.length){
		NSMutableArray *danger = [NSMutableArray array];
		NSString *what = channel ? @"Channel" : @"Group";
		NSMutableDictionary *dangerRow = self.isOwner
				? TGActionRow([NSString stringWithFormat:@"Delete %@", what],
							  nil, @"deleteChat", YES)
				: TGActionRow([NSString stringWithFormat:@"Leave %@", what],
							  nil, @"leave", YES);
		dangerRow[@"centered"] = @YES;
		[danger addObject:dangerRow];
		[sections addObject:TGSection(nil,
				(self.isOwner
						? @"Deleting removes this chat and every message in it for all members."
						: @"Leaving removes this chat from your list. The group stays for everyone else."),
				danger)];
	}

	self.sections = sections;
	[self updateEditButton];
	[self reloadTableDebounced];
}

#pragma mark - table

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView {
	return self.loaded ? (NSInteger)self.sections.count : 0;
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
	if (section < 0 || section >= (NSInteger)self.sections.count)
		return 0;
	return [self.sections[(NSUInteger)section][@"rows"] count];
}

- (NSString *)tableView:(UITableView *)tableView titleForHeaderInSection:(NSInteger)section {
	if (section < 0 || section >= (NSInteger)self.sections.count)
		return nil;
	return self.sections[(NSUInteger)section][@"header"];
}

- (NSString *)tableView:(UITableView *)tableView titleForFooterInSection:(NSInteger)section {
	if (section < 0 || section >= (NSInteger)self.sections.count)
		return nil;
	return self.sections[(NSUInteger)section][@"footer"];
}

- (void)tableView:(UITableView *)tableView willDisplayHeaderView:(UIView *)view
	   forSection:(NSInteger)section {
	if (![view isKindOfClass:UITableViewHeaderFooterView.class])
		return;
	UITableViewHeaderFooterView *footer = (UITableViewHeaderFooterView *)view;
	footer.textLabel.textColor = [[TGTheme shared] sectionHeaderColour];
}

- (CGFloat)tableView:(UITableView *)tableView heightForRowAtIndexPath:(NSIndexPath *)path {
	NSDictionary *row = [self rowAtPath:path];
	return [row[@"kind"] integerValue] == TGGroupRowMember
			? TGMetricPersonRow : TGMetricRow;
}

- (NSDictionary *)rowAtPath:(NSIndexPath *)path {
	if (path.section < 0 || path.section >= (NSInteger)self.sections.count)
		return nil;
	NSArray *rows = self.sections[(NSUInteger)path.section][@"rows"];
	if (path.row < 0 || path.row >= (NSInteger)rows.count)
		return nil;
	return rows[(NSUInteger)path.row];
}

- (UITableViewCell *)valueCellForRow:(NSDictionary *)row
							 inTable:(UITableView *)tableView {
	static NSString *reuse = @"value";
	UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:reuse];
	if (!cell)
		cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleValue1
									  reuseIdentifier:reuse];
	TGTheme *theme = [TGTheme shared];
	[theme styleCell:cell];
	cell.textLabel.font = TGFontRow();
	cell.textLabel.text = row[@"title"];
	cell.textLabel.textAlignment = NSTextAlignmentLeft;
	cell.detailTextLabel.font = TGFontBody();
	cell.detailTextLabel.text = row[@"detail"] ?: @"";
	BOOL disabled = [row[@"disabled"] boolValue];
	BOOL tappable = row[@"action"] != nil && !disabled;
	// The value on the right is blue only when tapping it changes something.
	// A read-only group leaves its name and photo black, the way Telegram's
	// member view does; blue there sells a tap that does not exist.
	cell.detailTextLabel.textColor = tappable ? [theme cellDetailColour]
											  : [theme secondaryTextColour];
	cell.accessoryType = tappable ? UITableViewCellAccessoryDisclosureIndicator
								  : UITableViewCellAccessoryNone;
	cell.selectionStyle = tappable ? UITableViewCellSelectionStyleDefault
								   : UITableViewCellSelectionStyleNone;
	if (disabled)
		cell.textLabel.textColor = [theme secondaryTextColour];
	else
		cell.textLabel.textColor = [row[@"destructive"] boolValue]
				? [theme destructiveColour] : [theme primaryTextColour];
	// Leave/Delete is the one row Telegram centres and leaves undecorated.
	if ([row[@"centered"] boolValue]){
		cell.textLabel.textAlignment = NSTextAlignmentCenter;
		cell.detailTextLabel.text = nil;
		cell.accessoryType = UITableViewCellAccessoryNone;
	}
	return cell;
}

- (UITableViewCell *)switchCellForRow:(NSDictionary *)row
							  inTable:(UITableView *)tableView {
	static NSString *reuse = @"switch";
	UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:reuse];
	if (!cell)
		cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleSubtitle
									  reuseIdentifier:reuse];
	TGTheme *theme = [TGTheme shared];
	[theme styleCell:cell];
	cell.textLabel.font = TGFontRow();
	cell.textLabel.textColor = [theme primaryTextColour];
	cell.detailTextLabel.font = TGFontCaption();
	cell.detailTextLabel.textColor = [theme secondaryTextColour];
	cell.textLabel.text = row[@"title"];
	cell.detailTextLabel.text = row[@"detail"] ?: @"";
	cell.selectionStyle = UITableViewCellSelectionStyleNone;

	TGGroupSwitch *toggle = [[TGGroupSwitch alloc] init];
	toggle.key = row[@"switch"];
	toggle.on = [row[@"on"] boolValue];
	toggle.enabled = [row[@"enabled"] boolValue] && !self.busy;
	[toggle addTarget:self action:@selector(switchChanged:)
	 forControlEvents:UIControlEventValueChanged];
	cell.accessoryView = toggle;
	cell.showsReorderControl = [row[@"kind"] integerValue] == TGGroupRowUsername &&
			[row[@"active"] boolValue] && self.active.count > 1;
	return cell;
}

- (UITableViewCell *)memberCellForRow:(NSDictionary *)row
							  inTable:(UITableView *)tableView {
	static NSString *reuse = @"member";
	TGMemberCell *cell = [tableView dequeueReusableCellWithIdentifier:reuse];
	if (!cell)
		cell = [[TGMemberCell alloc] initWithStyle:UITableViewCellStyleDefault
								  reuseIdentifier:reuse];
	TGTheme *theme = [TGTheme shared];
	[theme styleCell:cell];
	cell.textLabel.font = TGFontBody();
	cell.textLabel.textColor = [theme primaryTextColour];
	cell.selectionStyle = UITableViewCellSelectionStyleDefault;
	cell.accessoryType = UITableViewCellAccessoryDisclosureIndicator;

	NSDictionary *member = row[@"member"];
	int64_t userId = [member[@"id"] longLongValue];
	NSString *name = [member[@"name"] length]
			? member[@"name"] : [[TGClient shared] nameForUserId:userId];
	[cell setName:name userId:userId status:member[@"status"]
				tag:member[@"tag"] inTable:tableView];
	return cell;
}

/// The old tap on a member: their action sheet. Kept on a hold now that a
/// tap belongs to the person's profile.
- (void)memberRowHeld:(UILongPressGestureRecognizer *)hold {
	if (hold.state != UIGestureRecognizerStateBegan)
		return;
	NSIndexPath *path = [self.tableView indexPathForRowAtPoint:
			[hold locationInView:self.tableView]];
	NSDictionary *row = path ? [self rowAtPath:path] : nil;
	if (!row || [row[@"kind"] integerValue] != TGGroupRowMember)
		return;
	__weak typeof(self) weakSelf = self;
	[TGGroupMemberActions showForMember:row[@"member"]
								 inChat:self.chatId
								   from:self
							  onChanged:^{
		[weakSelf load];
	}];
}

- (UITableViewCell *)tableView:(UITableView *)tableView
		 cellForRowAtIndexPath:(NSIndexPath *)path {
	NSDictionary *row = [self rowAtPath:path];
	if (!row)
		return [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleDefault
									  reuseIdentifier:nil];
	TGGroupRowKind kind = (TGGroupRowKind)[row[@"kind"] integerValue];
	if (kind == TGGroupRowMember)
		return [self memberCellForRow:row inTable:tableView];
	if (kind == TGGroupRowSwitch || kind == TGGroupRowUsername)
		return [self switchCellForRow:row inTable:tableView];
	return [self valueCellForRow:row inTable:tableView];
}

- (BOOL)tableView:(UITableView *)tableView canMoveRowAtIndexPath:(NSIndexPath *)path {
	NSDictionary *row = [self rowAtPath:path];
	return [row[@"kind"] integerValue] == TGGroupRowUsername &&
		   [row[@"active"] boolValue] && self.active.count > 1;
}

- (NSIndexPath *)tableView:(UITableView *)tableView
targetIndexPathForMoveFromRowAtIndexPath:(NSIndexPath *)source
	   toProposedIndexPath:(NSIndexPath *)proposed {
	return source.section == proposed.section ? proposed : source;
}

- (void)tableView:(UITableView *)tableView
		moveRowAtIndexPath:(NSIndexPath *)from
			  toIndexPath:(NSIndexPath *)to {
	NSUInteger fromRow = (NSUInteger)from.row;
	NSUInteger toRow = (NSUInteger)to.row;
	if (fromRow >= self.active.count || toRow >= self.active.count)
		return;
	NSArray *before = [self.active copy];
	NSString *name = self.active[fromRow];
	[self.active removeObjectAtIndex:fromRow];
	[self.active insertObject:name atIndex:toRow];
	self.busy = YES;
	__weak typeof(self) weakSelf = self;
	[[TGClient shared] reorderSupergroupActiveUsernames:self.active inChat:self.chatId
			completion:^(BOOL ok, NSString *error){
		TGGroupSettingsViewController *me = weakSelf;
		if (!me)
			return;
		me.busy = NO;
		if (!ok){
			me.active = [before mutableCopy];
			[me showRefusal:error title:@"Username Order"];
			[me rebuild];
			return;
		}
		[me rebuild];
	}];
}

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)path {
	[tableView deselectRowAtIndexPath:path animated:YES];
	NSDictionary *row = [self rowAtPath:path];
	if (!row)
		return;
	if ([row[@"kind"] integerValue] == TGGroupRowMember){
		// The row is a person: open their profile, never a chat. Send
		// Message and the administrator actions live on the hold.
		[TGGroupMemberActions openProfileForMember:row[@"member"] from:self];
		return;
	}
	NSString *action = row[@"action"];
	if (action.length)
		[self runAction:action];
}

#pragma mark - switches

- (void)switchChanged:(TGGroupSwitch *)sender {
	if (self.busy){
		sender.on = !sender.on;
		return;
	}
	NSString *key = sender.key;
	BOOL on = sender.on;
	if ([key hasPrefix:@"@"])
		[self setUsername:key active:on sender:sender];
	else
		[self setBehaviour:key on:on sender:sender];
}

- (void)setUsername:(NSString *)key active:(BOOL)on sender:(TGGroupSwitch *)sender {
	NSString *username = [key substringFromIndex:1];
	self.busy = YES;
	sender.enabled = NO;
	__weak typeof(self) weakSelf = self;
	[[TGClient shared] toggleSupergroupUsernameIsActive:username
												 inChat:self.chatId
											   isActive:on
											 completion:^(BOOL ok, NSString *error){
		TGGroupSettingsViewController *me = weakSelf;
		if (!me)
			return;
		me.busy = NO;
		if (!ok){
			sender.on = !on;
			sender.enabled = YES;
			[me showRefusal:error title:@"Username"];
			return;
		}
		[me load];
	}];
}

- (void)setBehaviour:(NSString *)key on:(BOOL)on sender:(TGGroupSwitch *)sender {
	self.busy = YES;
	sender.enabled = NO;
	__weak typeof(self) weakSelf = self;
	void (^done)(BOOL, NSString *) = ^(BOOL ok, NSString *error){
		TGGroupSettingsViewController *me = weakSelf;
		if (!me)
			return;
		me.busy = NO;
		if (!ok){
			sender.on = !on;
			sender.enabled = YES;
			[me showRefusal:error title:@"Group Settings"];
			return;
		}
		if ([key isEqualToString:@"sign"])
			me.signMessages = on;
		else if ([key isEqualToString:@"join"])
			me.joinToSend = on;
		else if ([key isEqualToString:@"history"])
			me.allHistory = on;
		else if ([key isEqualToString:@"antispam"])
			me.aggressiveAntiSpam = on;
		else if ([key isEqualToString:@"hidden"] || [key isEqualToString:@"forum"] ||
				 [key isEqualToString:@"joinRequests"] ||
				 [key isEqualToString:@"translation"]){
			NSMutableDictionary *changed = [me.settings mutableCopy];
			if ([key isEqualToString:@"hidden"])
				changed[@"hiddenMembers"] = @(on);
			else if ([key isEqualToString:@"forum"])
				changed[@"isForum"] = @(on);
			else if ([key isEqualToString:@"joinRequests"])
				changed[@"joinByRequest"] = @(on);
			else
				changed[@"automaticTranslation"] = @(on);
			me.settings = changed;
		}
		[me rebuild];
	};

	if ([key isEqualToString:@"sign"]){
		[[TGClient shared] setChatSignMessages:self.chatId on:on completion:^(BOOL ok){
			done(ok, ok ? nil : @"Only an administrator of a supergroup or a "
								@"channel carries this switch.");
		}];
	} else if ([key isEqualToString:@"join"]){
		[[TGClient shared] setChatJoinToSendMessages:self.chatId on:on
										  completion:^(BOOL ok){
			done(ok, ok ? nil : @"Only an administrator of a supergroup or a "
								@"channel carries this switch.");
		}];
	} else if ([key isEqualToString:@"history"]){
		[[TGClient shared] setSupergroupAllHistoryAvailable:self.chatId on:on
												completion:^(BOOL ok){
			done(ok, ok ? nil : @"Only an administrator of a supergroup or a "
								@"channel carries this switch.");
		}];
	} else if ([key isEqualToString:@"antispam"]){
		[[TGClient shared] setChat:self.chatId aggressiveAntiSpam:on
						completion:done];
	} else if ([key isEqualToString:@"hidden"]){
		[[TGClient shared] setSupergroupHiddenMembersInChat:self.chatId on:on
												completion:done];
	} else if ([key isEqualToString:@"forum"]){
		[[TGClient shared] setSupergroupForumInChat:self.chatId on:on
										 completion:done];
	} else if ([key isEqualToString:@"joinRequests"]){
		[[TGClient shared] setSupergroupJoinByRequestInChat:self.chatId on:on
											 guardBotUserId:[self.settings[@"guardBotUserId"] longLongValue]
												 completion:done];
	} else {
		[[TGClient shared] setSupergroupAutomaticTranslationInChat:self.chatId on:on
														completion:done];
	}
}

/// Group Type / Channel Type. Telegram treats "private" and "public" as the
/// presence of a username, so the row edits that one name rather than
/// inventing a second switch that could disagree with the Usernames section.
- (void)chooseGroupType {
	BOOL isPublic = self.editable.length > 0 || self.active.count > 0;
	NSString *what = [self isChannelChat] ? @"Channel" : @"Group";
	if (!isPublic){
		[self editUsername];
		return;
	}
	__weak typeof(self) weakSelf = self;
	[TGAlertSheet showChoices:@[@"Edit Username", @"Make Private"]
						title:[NSString stringWithFormat:@"%@ Type", what]
						message:@"A public group is reachable by its @name; a "
								@"private one only by its invite link."
			 destructiveIndex:1
						 inView:self.view
					   onChoice:^(NSInteger index){
		if (index == 0){
			[weakSelf editUsername];
			return;
		}
		[weakSelf removeUsername];
	}];
}

/// Leaving is the member's row; the owner gets Delete instead because a
/// group cannot be left without an owner to hand it to.
- (void)leaveChat {
	NSString *what = [self isChannelChat] ? @"channel" : @"group";
	__weak typeof(self) weakSelf = self;
	[TGAlertSheet showConfirm:[NSString stringWithFormat:
					@"You will stop receiving messages from this %@.", what]
							title:([self isChannelChat] ? @"Leave Channel"
														: @"Leave Group")
						   action:@"Leave"
					  destructive:YES
						   inView:self.view
						onConfirm:^{
		TGGroupSettingsViewController *me = weakSelf;
		if (!me)
			return;
		// deleteChat removes the row and leaves in the same request pair.
		[[TGClient shared] deleteChat:me.chatId];
		[me.navigationController popToRootViewControllerAnimated:YES];
	}];
}

- (void)deleteChatForEveryone {
	NSString *what = [self isChannelChat] ? @"Channel" : @"Group";
	__weak typeof(self) weakSelf = self;
	[TGAlertSheet showConfirm:[NSString stringWithFormat:
					@"%@ and every message in it are deleted for all members. "
					@"This cannot be undone.", what]
							title:[NSString stringWithFormat:@"Delete %@", what]
						   action:@"Delete"
					  destructive:YES
						   inView:self.view
						onConfirm:^{
		TGGroupSettingsViewController *me = weakSelf;
		if (!me)
			return;
		[[TGClient shared] deleteChatForEveryone:me.chatId completion:^(NSString *error){
			TGGroupSettingsViewController *again = weakSelf;
			if (!again)
				return;
			if (error.length){
				[TGAlertSheet showMessage:error
									title:[NSString stringWithFormat:@"Delete %@", what]
								   inView:again.view];
				return;
			}
			[again.navigationController popToRootViewControllerAnimated:YES];
		}];
	}];
}

#pragma mark - actions

- (void)runAction:(NSString *)action {
	if ([action isEqualToString:@"photo"])        { [self editPhoto]; return; }
	if ([action isEqualToString:@"name"])         { [self editName]; return; }
	if ([action isEqualToString:@"description"])  { [self editDescription]; return; }
	if ([action isEqualToString:@"invite"])       { [self showInviteLink]; return; }
	if ([action isEqualToString:@"tab"])          { [self chooseMainTab]; return; }
	if ([action isEqualToString:@"upgrade"])      { [self confirmUpgrade]; return; }
	if ([action isEqualToString:@"addMembers"])   { [self addMembers]; return; }
	if ([action isEqualToString:@"findMember"])   { [self findMember]; return; }
	if ([action isEqualToString:@"permissions"])  { [self choosePermissions]; return; }
	if ([action isEqualToString:@"slow"])         { [self chooseSlowMode]; return; }
	if ([action isEqualToString:@"broadcast"])    { [self confirmBroadcast]; return; }
	if ([action isEqualToString:@"welcome"])      { [self showWelcomeMessages]; return; }
	if ([action isEqualToString:@"joinRequests"]) { [self showJoinRequests]; return; }
	if ([action isEqualToString:@"chatTools"])    { [self openChatTools]; return; }
	if ([action isEqualToString:@"groupCall"])    { [self openGroupCall]; return; }
	if ([action isEqualToString:@"videoChat"])    { [self openVideoChatSetup]; return; }
	if ([action isEqualToString:@"directMessages"]){ [self chooseDirectMessages]; return; }
	if ([action isEqualToString:@"import"])       { [self importMessages]; return; }
	if ([action isEqualToString:@"sendAs"])       { [self showSendAs]; return; }
	if ([action isEqualToString:@"clearByDate"])  { [self clearByDate]; return; }
	if ([action isEqualToString:@"groupStickers"]){ [self chooseStickerSet:NO]; return; }
	if ([action isEqualToString:@"customEmojiStickers"]){ [self chooseStickerSet:YES]; return; }
	if ([action isEqualToString:@"groupType"])    { [self chooseGroupType]; return; }
	if ([action isEqualToString:@"antispamFalsePositive"]){
		TGAntiSpamViewController *antiSpam = [[TGAntiSpamViewController alloc] init];
		antiSpam.chatId = self.chatId;
		antiSpam.chatTitle = self.chatTitle;
		antiSpam.hidesBottomBarWhenPushed = YES;
		[self.navigationController pushViewController:antiSpam animated:YES];
		return;
	}
	if ([action isEqualToString:@"username"])     { [self editUsername]; return; }
	if ([action isEqualToString:@"removeUsername"]){ [self removeUsername]; return; }
	if ([action isEqualToString:@"disableUsernames"]){ [self disableAllUsernames]; return; }
	if ([action isEqualToString:@"leave"])        { [self leaveChat]; return; }
	if ([action isEqualToString:@"deleteChat"])   { [self deleteChatForEveryone]; return; }
}

#pragma mark - identity

- (void)openGroupCall {
	__weak typeof(self) weakSelf = self;
	[[TGClient shared] chatRecordForChat:self.chatId completion:^(NSDictionary *chat){
		TGGroupSettingsViewController *me = weakSelf;
		if (!me)
			return;
		int32_t callId = [chat[@"video_chat"][@"group_call_id"] intValue];
		TGGroupCallViewController *screen = [[TGGroupCallViewController alloc]
				initWithChatId:me.chatId groupCallId:callId];
		screen.hidesBottomBarWhenPushed = YES;
		[me.navigationController pushViewController:screen animated:YES];
	}];
}

- (void)openVideoChatSetup {
	__weak typeof(self) weakSelf = self;
	[[TGClient shared] chatRecordForChat:self.chatId completion:^(NSDictionary *chat){
		TGGroupSettingsViewController *me = weakSelf;
		if (!me)
			return;
		int32_t callId = [chat[@"video_chat"][@"group_call_id"] intValue];
		TGVideoChatSetupViewController *screen = [[TGVideoChatSetupViewController alloc]
				initWithChatId:me.chatId groupCallId:callId];
		screen.hidesBottomBarWhenPushed = YES;
		[me.navigationController pushViewController:screen animated:YES];
	}];
}

- (void)editName {
	__weak typeof(self) weakSelf = self;
	[TGAlertSheet showInput:@"Group Name" message:nil placeholder:@"Name"
					   text:self.chatTitle action:@"Save" inView:self.view
				 onSubmit:^(NSString *name){
		[[TGClient shared] setChat:weakSelf.chatId title:name completion:^(BOOL ok){
			TGGroupSettingsViewController *me = weakSelf;
			if (!ok){
				[TGAlertSheet showMessage:@"Only an administrator can rename this group."
									title:@"Group Name" inView:me.view];
				return;
			}
			me.chatTitle = name;
			me.title = name;
			[me rebuild];
			[TGSnackbar showInView:me.view text:@"Group name updated"
						   seconds:2 onCommit:nil];
		}];
	}];
}

- (void)editDescription {
	__weak typeof(self) weakSelf = self;
	[TGAlertSheet showInput:@"Group Description"
					message:nil
				placeholder:@"What this group is about"
					   text:self.descriptionText
					 action:@"Save"
					 inView:self.view
				 onSubmit:^(NSString *text){
		[[TGClient shared] setChat:weakSelf.chatId description:text
						completion:^(BOOL ok){
			TGGroupSettingsViewController *me = weakSelf;
			if (!ok){
				[TGAlertSheet showMessage:@"Only an administrator of a supergroup "
										  @"or a channel writes a description."
									title:@"Group Description" inView:me.view];
				return;
			}
			me.descriptionText = text;
			[me rebuild];
			[TGSnackbar showInView:me.view text:@"Description updated"
						   seconds:2 onCommit:nil];
		}];
	}];
}

- (void)editPhoto {
	if (![UIImagePickerController isSourceTypeAvailable:
			UIImagePickerControllerSourceTypePhotoLibrary]){
		[TGAlertSheet showMessage:@"The photo library is not on this device."
							title:@"Group Photo" inView:self.view];
		return;
	}
	self.pickingPhoto = YES;
	UIImagePickerController *picker = [[UIImagePickerController alloc] init];
	picker.sourceType = UIImagePickerControllerSourceTypePhotoLibrary;
	picker.delegate = self;
	[self presentViewController:picker animated:YES completion:nil];
}

- (void)imagePickerController:(UIImagePickerController *)picker
		didFinishPickingMediaWithInfo:(NSDictionary *)info {
	[picker dismissViewControllerAnimated:YES completion:nil];
	if (!self.pickingPhoto)
		return;
	self.pickingPhoto = NO;
	UIImage *image = info[UIImagePickerControllerOriginalImage];
	if (!image)
		return;
	UIImage *scaled = [TGIcons decodedImage:image
								fittingSize:CGSizeMake(TGMetricUploadPhotoSide, TGMetricUploadPhotoSide)
									   fill:NO scale:TGMetricScaleFull];
	NSString *path = [NSTemporaryDirectory()
			stringByAppendingPathComponent:@"group-photo.jpg"];
	if (![UIImageJPEGRepresentation(scaled, TGCompressionQualityStandard) writeToFile:path atomically:YES]){
		[TGAlertSheet showMessage:@"Could not prepare the picture."
							title:@"Group Photo" inView:self.view];
		return;
	}
	__weak typeof(self) weakSelf = self;
	[[TGClient shared] setChat:self.chatId photoAtPath:path completion:^(BOOL ok){
		TGGroupSettingsViewController *me = weakSelf;
		if (!ok){
			[TGAlertSheet showMessage:@"Only an administrator can change this group's photo."
								title:@"Group Photo" inView:me.view];
			return;
		}
		me.hasPhoto = YES;
		[me rebuild];
		[TGSnackbar showInView:me.view text:@"Group photo updated"
					   seconds:2 onCommit:nil];
	}];
}

- (void)imagePickerControllerDidCancel:(UIImagePickerController *)picker {
	self.pickingPhoto = NO;
	[picker dismissViewControllerAnimated:YES completion:nil];
}

- (void)chooseMainTab {
	NSArray *names = @[@"posts", @"media", @"files", @"links", @"music",
					   @"voice", @"gifs"];
	NSArray *titles = @[@"Posts", @"Media", @"Files", @"Links", @"Music",
						@"Voice", @"GIFs"];
	__weak typeof(self) weakSelf = self;
	[TGAlertSheet showChoices:titles title:@"Main Profile Tab" destructiveIndex:-1
					   inView:self.view onChoice:^(NSInteger index){
		NSString *tab = names[(NSUInteger)index];
		[[TGClient shared] setSupergroupMainProfileTab:tab inChat:weakSelf.chatId
				completion:^(BOOL ok, NSString *error){
			TGGroupSettingsViewController *me = weakSelf;
			if (!ok){
				[me showRefusal:error title:@"Main Profile Tab"];
				return;
			}
			NSMutableDictionary *changed = [me.settings mutableCopy];
			changed[@"mainTab"] = tab;
			me.settings = changed;
			[me rebuild];
		}];
	}];
}

- (void)confirmUpgrade {
	__weak typeof(self) weakSelf = self;
	[TGAlertSheet showConfirm:@"A basic group becomes a supergroup: it gets a "
			@"link of its own, room past two hundred members, and a new chat "
			@"id. This screen closes with the old one."
						 title:@"Upgrade"
						action:@"Upgrade"
				   destructive:NO
						inView:self.view
					 onConfirm:^{
		[[TGClient shared] upgradeGroupToSupergroup:weakSelf.chatId
										 completion:^(int64_t newChatId){
			TGGroupSettingsViewController *me = weakSelf;
			if (!newChatId){
				[TGAlertSheet showMessage:@"Telegram refused the upgrade - a "
						@"supergroup or a channel is already one."
										  title:@"Upgrade" inView:me.view];
				return;
			}
			UINavigationController *nav = me.navigationController;
			[nav popToRootViewControllerAnimated:YES];
			[TGAlertSheet showMessage:@"The group is now a supergroup."
								  title:@"Upgraded"
								 inView:(nav.view ?: me.view)];
		}];
	}];
}

#pragma mark - members

- (void)addMembers {
	TGContactsViewController *contacts = [[TGContactsViewController alloc] init];
	contacts.addingToChatId = self.chatId;
	contacts.hidesBottomBarWhenPushed = YES;
	[self.navigationController pushViewController:contacts animated:YES];
}

/// getChatMembers is a page, not a search; searchChatMembers answers the
/// query server-side, which is the only way a group of a few thousand is
/// usable from a phone at all.
- (void)findMember {
	__weak typeof(self) weakSelf = self;
	[TGAlertSheet showInput:@"Find Member" message:nil
				placeholder:@"Name or @username" text:nil action:@"Find"
					 inView:self.view onSubmit:^(NSString *query){
		[[TGClient shared] searchMembersInChat:weakSelf.chatId query:query
									completion:^(NSArray *members){
			TGGroupSettingsViewController *me = weakSelf;
			if (!members.count){
				[TGAlertSheet showMessage:@"Nobody here answers to that."
									  title:@"Find Member" inView:me.view];
				return;
			}
			NSMutableArray *names = [NSMutableArray array];
			for (NSDictionary *member in members)
				[names addObject:[member[@"name"] length]
						? member[@"name"] : @"Member"];
			[TGAlertSheet showChoices:names title:@"Find Member"
					 destructiveIndex:-1 inView:me.view
							 onChoice:^(NSInteger index){
				NSDictionary *member = members[(NSUInteger)index];
				int64_t userId = [member[@"id"] longLongValue];
				if (!userId)
					return;
				TGProfileViewController *profile = [[TGProfileViewController alloc]
						initWithChatId:userId
								userId:userId
								 title:[member[@"name"] length] ? member[@"name"] : @""];
				profile.hidesBottomBarWhenPushed = YES;
				[me.navigationController pushViewController:profile animated:YES];
			}];
		}];
	}];
}

#pragma mark - permissions and behaviour

- (void)choosePermissions {
	__weak typeof(self) weakSelf = self;
	[TGAlertSheet showChoices:@[@"Everything allowed", @"Messages only (no media)", @"Read only"]
						title:@"What members may do"
			 destructiveIndex:-1
					   inView:self.view
					 onChoice:^(NSInteger index){
		NSString *preset = index == 0 ? @"all" : (index == 1 ? @"text" : @"read");
		[[TGClient shared] setChatPermissionsFromPreset:preset
												 inChat:weakSelf.chatId
											  completion:^(BOOL ok){
			TGGroupSettingsViewController *me = weakSelf;
			if (!ok){
				[TGAlertSheet showMessage:@"Only an administrator can change what "
										  @"members may do."
									title:@"Permissions" inView:me.view];
				return;
			}
			[me load];
		}];
	}];
}

- (void)chooseSlowMode {
	NSArray *titles = @[@"Off", @"5 seconds", @"10 seconds", @"30 seconds",
						@"1 minute", @"5 minutes", @"15 minutes", @"1 hour"];
	static const NSInteger seconds[] = {0, 5, 10, 30, 60, 300, 900, 3600};
	__weak typeof(self) weakSelf = self;
	[TGAlertSheet showChoices:titles title:@"Slow Mode" destructiveIndex:-1
					   inView:self.view onChoice:^(NSInteger index){
		[[TGClient shared] setSlowModeDelayForChat:weakSelf.chatId
										   seconds:seconds[index]
										completion:^(BOOL ok){
			TGGroupSettingsViewController *me = weakSelf;
			if (!ok){
				[TGAlertSheet showMessage:@"Telegram refused that delay."
									title:@"Slow Mode" inView:me.view];
				return;
			}
			NSMutableDictionary *changed = [me.groupInfo mutableCopy];
			changed[@"slow_mode_delay"] = @(seconds[index]);
			me.groupInfo = changed;
			[me rebuild];
		}];
	}];
}

- (void)confirmBroadcast {
	__weak typeof(self) weakSelf = self;
	[TGAlertSheet showConfirm:@"A broadcast group is read by its members and "
							  @"posted to by administrators only. Telegram has "
							  @"no way back from this."
						title:@"Convert to Broadcast Group"
					   action:@"Convert"
				  destructive:YES
					   inView:self.view
					onConfirm:^{
		[[TGClient shared] convertSupergroupToBroadcastInChat:weakSelf.chatId
				completion:^(BOOL ok, NSString *error){
			TGGroupSettingsViewController *me = weakSelf;
			if (!ok){
				[me showRefusal:error title:@"Broadcast Group"];
				return;
			}
			NSMutableDictionary *changed = [me.settings mutableCopy];
			changed[@"isBroadcast"] = @YES;
			me.settings = changed;
			[me rebuild];
		}];
	}];
}

- (void)showJoinRequests {
	__weak typeof(self) weakSelf = self;
	[[TGClient shared] joinRequestsForChat:self.chatId completion:^(NSArray *requests){
		TGGroupSettingsViewController *me = weakSelf;
		if (!requests.count){
			[TGAlertSheet showMessage:@"Nobody is waiting at the links."
								title:@"Join Requests" inView:me.view];
			return;
		}
		NSMutableArray *rows = [NSMutableArray array];
		for (NSDictionary *request in requests)
			[rows addObject:request[@"name"] ?: @"?"];
		[rows addObject:@"Approve All Requests"];
		[rows addObject:@"Decline All Requests"];

		[TGAlertSheet showChoices:rows title:@"Join Requests"
				 destructiveIndex:(NSInteger)rows.count - 1 inView:me.view
						 onChoice:^(NSInteger index){
			if (index == (NSInteger)requests.count ||
				index == (NSInteger)requests.count + 1){
				BOOL approve = index == (NSInteger)requests.count;
				[[TGClient shared] processAllJoinRequests:me.chatId link:@""
						approve:approve completion:^(BOOL ok){
					[TGAlertSheet showMessage:(ok ? @"Every request was answered."
												   : @"Telegram refused the batch.")
										title:@"Join Requests" inView:me.view];
					[me showJoinRequests];
				}];
				return;
			}
			int64_t userId = [requests[index][@"id"] longLongValue];
			NSString *name = requests[index][@"name"] ?: @"them";
			[TGAlertSheet showChoices:@[@"Accept", @"Decline"] title:name
					 destructiveIndex:1 inView:me.view
							 onChoice:^(NSInteger pick){
				[[TGClient shared] processJoinRequest:userId inChat:me.chatId
											   approve:(pick == 0)];
				dispatch_after(dispatch_time(DISPATCH_TIME_NOW,
						(int64_t)(0.5 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
					[me showJoinRequests];
				});
			}];
		}];
	}];
}

/// One sheet, everything a welcome-message family does: add, edit, delete
/// one or all. Text is what this client composes; media stays TDLib-side.
- (void)showWelcomeMessages {
	__weak typeof(self) weakSelf = self;
	int64_t chatId = self.chatId;
	NSString *groupTitle = self.chatTitle ?: @"Welcome Messages";
	[[TGClient shared] welcomeMessagesOfChat:chatId completion:^(NSArray *welcomes){
		TGGroupSettingsViewController *me = weakSelf;
		if (!me)
			return;

		NSMutableArray *rows = [NSMutableArray array];
		NSMutableArray *ids = [NSMutableArray array];
		for (NSDictionary *welcome in welcomes){
			NSString *text = welcome[@"text"];
			NSString *preview = text.length
					? [text substringToIndex:MIN((NSUInteger)30, text.length)]
					: @"(not text)";
			[rows addObject:[NSString stringWithFormat:@"Edit — %@", preview]];
			[ids addObject:welcome[@"id"]];
		}
		[rows addObject:@"Add"];
		if (welcomes.count)
			[rows addObject:@"Delete One..."];
		[rows addObject:@"Delete All"];

		NSInteger destructive = (NSInteger)[rows indexOfObject:@"Delete All"];
		[TGAlertSheet showChoices:rows title:groupTitle
							message:(welcomes.count
									? @"The first one a joiner sees."
									: @"None yet. A new joiner sees the highest one first.")
				 destructiveIndex:destructive inView:me.view
						 onChoice:^(NSInteger index){
			NSString *what = rows[(NSUInteger)index];
			if ([what isEqualToString:@"Delete All"]){
				[TGAlertSheet showConfirm:@"Every welcome message this group has is removed."
									title:@"Welcome Messages"
								   action:@"Delete All"
							  destructive:YES
								   inView:me.view
								onConfirm:^{
					[[TGClient shared] clearAllWelcomeMessagesInChat:chatId];
					[me showWelcomeMessages];
				}];
				return;
			}
			if ([what isEqualToString:@"Delete One..."]){
				NSMutableArray *previews = [NSMutableArray array];
				for (NSUInteger i = 0; i < welcomes.count; i++){
					NSString *text = welcomes[i][@"text"];
					NSString *preview = text.length
							? [text substringToIndex:MIN((NSUInteger)30, text.length)]
							: @"(not text)";
					[previews addObject:[NSString stringWithFormat:@"%lu. %@",
										 (unsigned long)(i + 1), preview]];
				}
				[TGAlertSheet showChoices:previews title:@"Welcome Messages"
								   message:@"Which welcome goes?"
						 destructiveIndex:0 inView:me.view
								 onChoice:^(NSInteger which){
					NSString *wid = [ids[(NSUInteger)which] isKindOfClass:NSString.class]
							? ids[(NSUInteger)which]
							: [ids[(NSUInteger)which] stringValue];
					[[TGClient shared] deleteWelcomeMessage:[wid longLongValue]
													 inChat:chatId];
					[me showWelcomeMessages];
				}];
				return;
			}
			if ([what isEqualToString:@"Add"]){
				[TGAlertSheet showInput:@"Add Welcome" message:nil
							placeholder:@"A word to the joiner" text:nil
								 action:@"Add" inView:me.view
							 onSubmit:^(NSString *typed){
					[[TGClient shared] addWelcomeMessageToChat:chatId text:typed
													completion:^(BOOL ok){
						if (!ok)
							[TGAlertSheet showMessage:@"Telegram refused that. Only "
													  @"an administrator adds one."
												title:@"Welcome" inView:me.view];
					}];
				}];
				return;
			}
			if (index >= (NSInteger)ids.count)
				return;
			NSString *old = welcomes[index][@"text"];
			NSString *welcomeId = [ids[index] isKindOfClass:NSString.class]
					? ids[index] : [ids[index] stringValue];
			[TGAlertSheet showInput:@"Edit Welcome" message:nil
						placeholder:old ?: @"A word to the joiner" text:old
							 action:@"Save" inView:me.view
						 onSubmit:^(NSString *typed){
				[[TGClient shared] setWelcomeMessage:[welcomeId longLongValue]
											  inChat:chatId text:typed
										  completion:^(BOOL ok){
					if (!ok)
						[TGAlertSheet showMessage:@"Telegram refused that."
											title:@"Welcome" inView:me.view];
				}];
			}];
		}];
	}];
}

#pragma mark - tools

- (void)openChatTools {
	TGChatToolsViewController *tools = [[TGChatToolsViewController alloc] init];
	tools.chatId = self.chatId;
	tools.chatTitle = self.chatTitle;
	tools.isGroup = YES;
	tools.hidesBottomBarWhenPushed = YES;
	[self.navigationController pushViewController:tools animated:YES];
}

/// The switch Telegram offers channel owners: post under yourself, or as one
/// of the other accounts you own.
- (void)showSendAs {
	__weak typeof(self) weakSelf = self;
	[[TGClient shared] availableMessageSendersInChat:self.chatId completion:^(NSArray *senders){
		TGGroupSettingsViewController *me = weakSelf;
		if (!senders.count){
			[TGAlertSheet showMessage:@"Only a chat you may post in carries a "
									  @"Send-as switch."
								title:@"Send as" inView:me.view];
			return;
		}
		NSMutableArray *rows = [NSMutableArray array];
		for (NSDictionary *sender in senders){
			NSString *who = nil;
			NSString *userId = sender[@"user_id"];
			if (userId)
				who = [[TGClient shared] nameForUserId:[userId longLongValue]];
			if (!who.length && sender[@"chat_id"])
				who = [[TGClient shared] titleForChat:
						[sender[@"chat_id"] longLongValue]];
			NSString *line = who.length ? who : @"chat";
			NSString *current = [sender[@"is_current"] boolValue] ? @" — now" : @"";
			[rows addObject:[line stringByAppendingString:current]];
		}
		[TGAlertSheet showChoices:rows title:@"Send as"
							message:@"What you post here posts under that name."
				 destructiveIndex:-1 inView:me.view
						 onChoice:^(NSInteger index){
			NSDictionary *sender = senders[(NSUInteger)index];
			[[TGClient shared] setMessageSender:sender inChat:me.chatId
									 completion:^(BOOL ok){
				if (!ok)
					[TGAlertSheet showMessage:@"Telegram refused that."
										title:@"Send as" inView:me.view];
			}];
		}];
	}];
}

- (void)chooseDirectMessages {
	__weak typeof(self) weakSelf = self;
	[TGAlertSheet showChoices:@[@"Off", @"On, free", @"On, 1 star per message"]
						title:@"Channel Direct Messages"
			  destructiveIndex:-1
					   inView:self.view
					 onChoice:^(NSInteger index){
		BOOL enabled = index > 0;
		NSInteger stars = index > 1 ? 1 : 0;
		[[TGClient shared] setDirectMessagesEnabled:enabled paidStars:stars
											 inChat:weakSelf.chatId
										 completion:^(BOOL ok){
			TGGroupSettingsViewController *me = weakSelf;
			[TGSnackbar showInView:me.view
							  text:(ok ? @"Direct messages updated"
									   : @"Only the channel's owner changes this")
						   seconds:2 onCommit:nil];
		}];
	}];
}

- (void)clearByDate {
	__weak typeof(self) weakSelf = self;
	[TGAlertSheet showChoices:@[@"Older than a week", @"Older than a month",
								@"Everything older than today"]
						title:@"Clear by Date"
			 destructiveIndex:-1
					   inView:self.view
					 onChoice:^(NSInteger index){
		NSTimeInterval now = [[NSDate date] timeIntervalSince1970];
		NSInteger days = index == 0 ? 7 : (index == 1 ? 30 : 1);
		[TGAlertSheet showConfirm:@"Everything sent before that is deleted for "
								  @"everyone, if this account may delete it here."
							title:@"Clear by Date"
						   action:@"Clear"
					  destructive:YES
						   inView:weakSelf.view
						onConfirm:^{
			[[TGClient shared] deleteChatMessagesByDate:weakSelf.chatId
												 minDate:0
												 maxDate:(NSInteger)(now - days * 86400)
												  revoke:YES];
		}];
	}];
}

/// A group's sticker shelf and its custom emoji shelf are two settings on the
/// supergroup, chosen from the packs this account owns.
- (void)chooseStickerSet:(BOOL)customEmoji {
	__weak typeof(self) weakSelf = self;
	[[TGClient shared] ownedStickerSetsWithCompletion:^(NSArray *sets){
		TGGroupSettingsViewController *me = weakSelf;
		NSMutableArray *titles = [NSMutableArray arrayWithObject:@"None"];
		NSMutableArray *ids = [NSMutableArray arrayWithObject:@(0)];
		for (NSDictionary *set in sets){
			NSString *type = set[@"stickerType"] ?: @"";
			BOOL isCustom = [type isEqualToString:@"stickerTypeCustomEmoji"];
			if (customEmoji != isCustom)
				continue;
			int64_t setId = [set[@"id"] longLongValue];
			if (!setId)
				continue;
			[titles addObject:[NSString stringWithFormat:@"%@  ·  %lu stickers",
					set[@"title"] ?: @"Pack",
					(unsigned long)[set[@"count"] unsignedIntegerValue]]];
			[ids addObject:@(setId)];
		}
		NSString *title = customEmoji ? @"Custom Emoji Stickers" : @"Group Stickers";
		if (titles.count == 1){
			[TGAlertSheet showMessage:(customEmoji
					? @"This account owns no custom emoji packs."
					: @"This account owns no sticker packs.")
								  title:title inView:me.view];
			return;
		}
		[TGAlertSheet showChoices:titles title:title
							message:(customEmoji
									? @"Used for the group's emoji status and reactions."
									: @"Shown above the composer for everyone here.")
				 destructiveIndex:-1 inView:me.view
						 onChoice:^(NSInteger index){
			int64_t setId = [ids[(NSUInteger)index] longLongValue];
			void (^done)(BOOL) = ^(BOOL ok){
				[TGAlertSheet showMessage:(ok ? @"The group's shelf is updated."
											  : @"Telegram refused the shelf; only "
												@"an administrator can change it.")
								  title:title inView:me.view];
			};
			if (customEmoji)
				[[TGClient shared] setSupergroupCustomEmojiStickerSet:setId
						inChat:me.chatId completion:done];
			else
				[[TGClient shared] setSupergroupStickerSet:setId
						inChat:me.chatId completion:done];
		}];
	}];
}

/// Reads an export file's opening lines so Telegram can name it, asks the
/// chat's own confirmation sentence, then imports it. Paths are relative to
/// Documents, which is the folder iTunes file sharing exposes.
- (void)importMessages {
	int64_t chatId = self.chatId;
	__weak typeof(self) weakSelf = self;
	[TGAlertSheet showInput:@"Import Messages"
					message:@"Name a history file in this app's Documents "
							@"folder. Its media files go in the same folder."
				placeholder:@"export.json"
					   text:nil
					 action:@"Next"
					 inView:self.view
				   onSubmit:^(NSString *name){
		[weakSelf beginImportFromPath:name inChat:chatId];
	}];
}

- (void)beginImportFromPath:(NSString *)name inChat:(int64_t)chatId {
	NSString *trimmed = [name stringByTrimmingCharactersInSet:
			[NSCharacterSet whitespaceAndNewlineCharacterSet]];
	if (!trimmed.length)
		return;
	NSString *path = trimmed;
	if (!path.isAbsolutePath){
		NSString *documents = [NSSearchPathForDirectoriesInDomains(
				NSDocumentDirectory, NSUserDomainMask, YES) firstObject];
		path = [documents stringByAppendingPathComponent:trimmed];
	}
	if (![[NSFileManager defaultManager] fileExistsAtPath:path]){
		[TGAlertSheet showMessage:[NSString stringWithFormat:
				@"No file at %@. Put the export in the app's Documents folder "
				@"first; iTunes file sharing shows it.", path]
							title:@"Import Messages" inView:self.view];
		return;
	}
	NSStringEncoding encoding = NSUTF8StringEncoding;
	NSError *error = nil;
	NSString *contents = [NSString stringWithContentsOfFile:path
			usedEncoding:&encoding error:&error];
	if (!contents)
		contents = [NSString stringWithContentsOfFile:path
				encoding:NSUTF8StringEncoding error:nil];
	if (!contents.length){
		[TGAlertSheet showMessage:@"The file is not text this app can read."
							title:@"Import Messages" inView:self.view];
		return;
	}
	NSArray *lines = [contents componentsSeparatedByString:@"\n"];
	NSUInteger headCount = MIN((NSUInteger)100, lines.count);
	NSString *head = [[lines subarrayWithRange:NSMakeRange(0, headCount)]
			componentsJoinedByString:@"\n"];

	__weak typeof(self) weakSelf = self;
	[[TGClient shared] messageFileTypeForHead:head completion:^(NSDictionary *fileType){
		TGGroupSettingsViewController *me = weakSelf;
		NSString *kind = fileType[@"kind"] ?: @"unknown";
		NSString *who = fileType[@"title"];
		[[TGClient shared] importConfirmationTextForChat:chatId
											  completion:^(NSString *text){
			TGGroupSettingsViewController *again = weakSelf;
			NSString *title = [kind isEqualToString:@"private"]
					? [NSString stringWithFormat:@"Import chat with %@",
							who.length ? who : @"them"]
					: ([kind isEqualToString:@"group"]
							? [NSString stringWithFormat:@"Import group %@",
									who.length ? who : @""]
							: @"Import messages");
			NSString *body = text.length ? text
					: @"This file looks like a history export. Importing adds "
					  @"its messages to this chat.";
			[TGAlertSheet showConfirm:body title:title action:@"Import"
						  destructive:YES inView:again.view
							onConfirm:^{
				[[TGClient shared] importMessagesFromFile:path
											attachedFiles:@[]
												 intoChat:chatId
											   completion:^(BOOL ok){
					[TGSnackbar showInView:again.view
									  text:(ok ? @"Import started"
											   : @"Telegram refused the import")
								   seconds:2 onCommit:nil];
				}];
			}];
			(void)me;
		}];
	}];
}

#pragma mark - invite links

- (void)showInviteLink {
	int64_t chatId = self.chatId;
	__weak typeof(self) weakSelf = self;
	[[TGClient shared] inviteLinksForChat:chatId completion:^(NSArray *links){
		TGGroupSettingsViewController *me = weakSelf;
		NSString *primary = nil;
		for (NSDictionary *link in links)
			if ([link[@"primary"] boolValue] && ![link[@"revoked"] boolValue]){
				primary = link[@"link"];
				break;
			}
		if (!primary.length && links.count)
			primary = links[0][@"link"];
		if (!primary.length){
			[TGAlertSheet showMessage:@"This chat has no invite link, and only "
									  @"an administrator can make one."
								title:@"Invite Link" inView:me.view];
			return;
		}
		[TGAlertSheet showChoices:@[@"Copy Link", @"Create Extra Link",
									@"Create Subscription Link",
									@"Manage Links", @"Link Counts"]
							title:primary
				 destructiveIndex:-1 inView:me.view
						 onChoice:^(NSInteger index){
			if (index == 0){
				[UIPasteboard generalPasteboard].string = primary;
				[TGAlertSheet showMessage:@"Copied." title:nil inView:me.view];
				return;
			}
			if (index == 1){
				[[TGClient shared] createInviteLinkForChat:chatId name:nil
											   memberLimit:0
												completion:^(NSString *link){
					[TGAlertSheet showMessage:(link.length ? link
							: @"Telegram refused to create a link - only an "
							  @"administrator of a group with a primary link "
							  @"makes extras.")
										title:@"New Invite Link" inView:me.view];
				}];
				return;
			}
			if (index == 2){
				[me createSubscriptionLink];
				return;
			}
			if (index == 3){
				[me showAllInviteLinks];
				return;
			}
			[me showInviteLinkCounts];
		}];
	}];
}

- (void)showAllInviteLinks {
	int64_t chatId = self.chatId;
	__weak typeof(self) weakSelf = self;
	[[TGClient shared] inviteLinksForChat:chatId completion:^(NSArray *links){
		TGGroupSettingsViewController *me = weakSelf;
		if (!links.count){
			[TGAlertSheet showMessage:@"This chat has no invite links."
								title:@"All Links" inView:me.view];
			return;
		}
		NSMutableArray *rows = [NSMutableArray array];
		for (NSDictionary *link in links)
			[rows addObject:[NSString stringWithFormat:@"%@%@  ·  %@ joined",
					[link[@"revoked"] boolValue] ? @"(revoked) " : @"",
					link[@"link"], link[@"members"] ?: @(0)]];
		[rows addObject:@"Link Counts"];
		[rows addObject:@"Delete All Revoked Links"];

		[TGAlertSheet showChoices:rows title:@"All Links"
				 destructiveIndex:(NSInteger)rows.count - 1 inView:me.view
						 onChoice:^(NSInteger index){
			if (index == (NSInteger)links.count){
				[me showInviteLinkCounts];
				return;
			}
			if (index == (NSInteger)links.count + 1){
				[me deleteAllRevokedLinks];
				return;
			}
			[me showActionsForInviteLink:links[(NSUInteger)index] inChat:chatId];
		}];
	}];
}

- (void)showActionsForInviteLink:(NSDictionary *)link inChat:(int64_t)chatId {
	NSString *url = link[@"link"];
	if (!url.length)
		return;
	__weak typeof(self) weakSelf = self;
	[[TGClient shared] inviteLink:url inChat:chatId completion:^(NSDictionary *info){
		TGGroupSettingsViewController *me = weakSelf;
		NSDictionary *fresh = info ?: link;
		BOOL primary = [fresh[@"primary"] boolValue];
		BOOL revoked = [fresh[@"revoked"] boolValue];
		id subscriptionValue = fresh[@"subscription"];
		BOOL subscription = subscriptionValue &&
				subscriptionValue != [NSNull null];
		NSMutableArray *choices = [NSMutableArray arrayWithObject:@"Copy Link"];
		[choices addObject:@"Members"];
		if (!revoked)
			[choices addObject:subscription ? @"Rename Link"
											: @"Edit Name & Limit"];
		[choices addObject:(revoked ? @"Delete Link"
									: (primary ? @"Replace" : @"Revoke"))];
		[TGAlertSheet showChoices:choices title:url destructiveIndex:-1
						   inView:me.view onChoice:^(NSInteger index){
			NSString *action = choices[(NSUInteger)index];
			if ([action isEqualToString:@"Copy Link"]){
				[UIPasteboard generalPasteboard].string = url;
				[TGAlertSheet showMessage:@"Copied." title:nil inView:me.view];
				return;
			}
			if ([action isEqualToString:@"Members"]){
				[me showMembersOfInviteLink:url inChat:chatId];
				return;
			}
			if ([action isEqualToString:@"Rename Link"]){
				[TGAlertSheet showInput:@"Rename Link" message:nil
							placeholder:@"Name" text:fresh[@"name"] ?: @""
								 action:@"Save" inView:me.view
							 onSubmit:^(NSString *name){
					[[TGClient shared] editSubscriptionInviteLink:url inChat:chatId
							name:name completion:^(BOOL ok){
						[TGAlertSheet showMessage:(ok ? @"Link renamed."
											   : @"Telegram refused the edit.")
											title:@"Invite Link" inView:me.view];
					}];
				}];
				return;
			}
			if ([action isEqualToString:@"Edit Name & Limit"]){
				[TGAlertSheet showInput:@"Edit Link"
								message:@"Leave the limit empty for no limit."
							placeholder:@"Name" text:fresh[@"name"] ?: @""
								 action:@"Next" inView:me.view
							 onSubmit:^(NSString *name){
					[TGAlertSheet showConfirm:@"Set a member limit?"
										title:@"Member Limit"
									   action:@"Set Limit"
								  destructive:NO
									   inView:me.view
									onConfirm:^{
						[TGAlertSheet showInput:@"Member Limit" message:nil
									placeholder:@"0 for no limit" text:@"0"
										 action:@"Save" inView:me.view
									 onSubmit:^(NSString *limitText){
							[[TGClient shared] editInviteLink:url inChat:chatId
									name:name expiration:0
									memberLimit:limitText.integerValue
									joinRequest:NO completion:^(BOOL ok){
								[TGAlertSheet showMessage:(ok ? @"Link updated."
															   : @"Telegram refused the edit.")
														title:@"Invite Link" inView:me.view];
							}];
						}];
					}];
				}];
				return;
			}
			if ([action isEqualToString:@"Delete Link"]){
				[[TGClient shared] deleteRevokedInviteLink:url inChat:chatId
											 completion:^(BOOL ok){
					[TGAlertSheet showMessage:(ok ? @"The revoked link is gone."
												   : @"Telegram refused the delete.")
											title:@"Invite Link" inView:me.view];
					[me showAllInviteLinks];
				}];
				return;
			}
			NSString *warn = primary
					? @"The common link stops working and a new one takes its place."
					: @"The link above stops working at once, and it does not come back.";
			[TGAlertSheet showConfirm:warn title:url
							   action:(primary ? @"Replace" : @"Revoke")
						  destructive:YES inView:me.view onConfirm:^{
				if (primary){
					[[TGClient shared] replacePrimaryInviteLinkForChat:chatId
														 completion:^(NSString *made){
						[TGAlertSheet showMessage:(made.length ? made
								: @"Telegram refused to replace the link.")
												title:@"Invite Link" inView:me.view];
					}];
					return;
				}
				[[TGClient shared] revokeInviteLink:url inChat:chatId
										 completion:^(BOOL ok){
					if (!ok)
						[TGAlertSheet showMessage:@"Telegram refused to revoke that link."
											title:@"Revoke" inView:me.view];
					else
						[me showAllInviteLinks];
				}];
			}];
		}];
	}];
}

- (void)showMembersOfInviteLink:(NSString *)url inChat:(int64_t)chatId {
	__weak typeof(self) weakSelf = self;
	[[TGClient shared] membersOfInviteLink:url inChat:chatId
								completion:^(NSArray *members){
		TGGroupSettingsViewController *me = weakSelf;
		if (!members.count){
			[TGAlertSheet showMessage:@"Nobody has joined through this link yet."
								title:@"Link Members" inView:me.view];
			return;
		}
		NSMutableArray *rows = [NSMutableArray array];
		for (NSDictionary *member in members){
			NSDate *date = [NSDate dateWithTimeIntervalSince1970:
					[member[@"date"] doubleValue]];
			NSString *when = [NSDateFormatter localizedStringFromDate:date
					dateStyle:NSDateFormatterMediumStyle
					timeStyle:NSDateFormatterNoStyle];
			[rows addObject:[NSString stringWithFormat:@"%@ · joined %@",
					member[@"name"] ?: @"Member", when]];
		}
		[TGAlertSheet showChoices:rows title:@"Link Members"
				 destructiveIndex:-1 inView:me.view onChoice:^(NSInteger index){
			(void)index;
		}];
	}];
}

- (void)showInviteLinkCounts {
	__weak typeof(self) weakSelf = self;
	[[TGClient shared] inviteLinkCountsForChat:self.chatId completion:^(NSArray *counts){
		TGGroupSettingsViewController *me = weakSelf;
		if (!counts.count){
			[TGAlertSheet showMessage:@"Telegram returned no link counts."
								title:@"Link Counts" inView:me.view];
			return;
		}
		NSMutableArray *rows = [NSMutableArray array];
		for (NSDictionary *count in counts)
			[rows addObject:[NSString stringWithFormat:@"%@: %@ active, %@ revoked",
					count[@"name"] ?: @"Administrator",
					count[@"active"] ?: @(0), count[@"revoked"] ?: @(0)]];
		[TGAlertSheet showChoices:rows title:@"Link Counts"
				 destructiveIndex:-1 inView:me.view onChoice:^(NSInteger index){
			(void)index;
		}];
	}];
}

/// A monthly Star subscription in a channel, which is the one invite link
/// shape that carries a price rather than a member limit.
- (void)createSubscriptionLink {
	int64_t chatId = self.chatId;
	__weak typeof(self) weakSelf = self;
	[TGAlertSheet showInput:@"Subscription Link"
					message:@"A monthly Star subscription in this channel."
				placeholder:@"Name (optional)" text:nil action:@"Create"
					 inView:self.view onSubmit:^(NSString *name){
		[TGAlertSheet showInput:@"Stars Per Month" message:nil
					placeholder:@"1" text:@"1" action:@"Create"
					 inView:weakSelf.view onSubmit:^(NSString *stars){
			[[TGClient shared] createSubscriptionInviteLink:chatId name:name
					stars:MAX(stars.integerValue, 1) period:2592000
					completion:^(NSString *link){
				[TGAlertSheet showMessage:(link.length ? link
						: @"Telegram refused a subscription link - the chat must be "
						  @"a channel and this account its admin.")
									title:@"Subscription Link" inView:weakSelf.view];
			}];
		}];
	}];
}

- (void)deleteAllRevokedLinks {
	int64_t myId = [[TGClient shared].me[@"id"] longLongValue];
	__weak typeof(self) weakSelf = self;
	[TGAlertSheet showConfirm:@"Every revoked link this account made in this "
							  @"chat is deleted permanently."
						title:@"Delete All Revoked Links"
					   action:@"Delete" destructive:YES inView:self.view
					onConfirm:^{
		[[TGClient shared] deleteAllRevokedInviteLinks:weakSelf.chatId creator:myId
				completion:^(BOOL ok){
			[TGAlertSheet showMessage:(ok ? @"Revoked links deleted."
										   : @"Telegram refused the delete.")
								title:@"Invite Links" inView:weakSelf.view];
		}];
	}];
}

#pragma mark - usernames

- (void)editUsername {
	__weak typeof(self) weakSelf = self;
	[TGAlertSheet showInput:@"Group Username"
					message:@"The public @name for this group or channel. Remove "
							@"it from the row above; active names below stay."
				placeholder:@"username"
					   text:self.editable
					 action:@"Save"
					 inView:self.view
				 onSubmit:^(NSString *text){
		NSString *username = [text stringByReplacingOccurrencesOfString:@"@"
															withString:@""];
		[[TGClient shared] setSupergroupUsername:username inChat:weakSelf.chatId
				completion:^(BOOL ok, NSString *error){
			if (!ok){
				[weakSelf showRefusal:error title:@"Group Username"];
				return;
			}
			[weakSelf load];
			[TGSnackbar showInView:weakSelf.view text:@"Username updated"
						   seconds:2 onCommit:nil];
		}];
	}];
}

- (void)removeUsername {
	__weak typeof(self) weakSelf = self;
	[TGAlertSheet showConfirm:@"Removing the editable username leaves the group "
							  @"reachable only through its invite link or its "
							  @"active names. Names below are not touched."
						title:@"Remove Username"
					   action:@"Remove"
				  destructive:YES
					   inView:self.view
					onConfirm:^{
		[[TGClient shared] setSupergroupUsername:@"" inChat:weakSelf.chatId
				completion:^(BOOL ok, NSString *error){
			if (!ok){
				[weakSelf showRefusal:error title:@"Remove Username"];
				return;
			}
			[weakSelf load];
		}];
	}];
}

- (void)disableAllUsernames {
	__weak typeof(self) weakSelf = self;
	[TGAlertSheet showConfirm:@"Every active name except the editable one is "
							  @"switched off. They stay on the group and can be "
							  @"switched back on here."
						title:@"Disable All Usernames"
					   action:@"Disable"
				  destructive:YES
					   inView:self.view
					onConfirm:^{
		[[TGClient shared] disableAllSupergroupUsernamesInChat:weakSelf.chatId
				completion:^(BOOL ok, NSString *error){
			if (!ok){
				[weakSelf showRefusal:error title:@"Disable Usernames"];
				return;
			}
			[weakSelf load];
		}];
	}];
}

@end
