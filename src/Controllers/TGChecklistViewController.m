//
// TGChecklistViewController.m
//
#import "TGChecklistViewController.h"
#import "TGClient.h"
#import "TGAlertSheet.h"

@interface TGChecklistViewController ()
@property (nonatomic, assign) int64_t chatId;
@property (nonatomic, assign) int64_t messageId;
@property (nonatomic, copy) NSString *checklistTitle;
@property (nonatomic, strong) NSMutableArray *tasks;
@property (nonatomic, assign) BOOL canAddTasks;
@property (nonatomic, assign) BOOL canMarkTasks;
@property (nonatomic, assign) BOOL othersCanAddTasks;
@property (nonatomic, assign) BOOL othersCanMarkTasks;
@property (nonatomic, assign) BOOL loaded;
@property (nonatomic, copy) NSString *loadError;
@end

@implementation TGChecklistViewController

- (instancetype)initWithChatId:(int64_t)chatId
                     messageId:(int64_t)messageId
                         title:(NSString *)title {
	self = [super init];
	if (!self)
		return nil;
	_chatId = chatId;
	_messageId = messageId;
	_checklistTitle = [title copy] ?: @"Checklist";
	_tasks = [NSMutableArray array];
	_canAddTasks = YES;
	_canMarkTasks = YES;
	_othersCanAddTasks = YES;
	_othersCanMarkTasks = YES;
	_loaded = (messageId == 0);
	return self;
}

- (void)viewDidLoad {
	self.title = self.messageId ? @"Checklist" : @"New Checklist";
	[super viewDidLoad];
	if (self.messageId)
		[self loadChecklist];
	else
		[self rebuild];
}

- (void)viewWillAppear:(BOOL)animated {
	[super viewWillAppear:animated];
	if (self.loaded)
		[self rebuild];
}

- (void)loadChecklist {
	__weak typeof(self) weakSelf = self;
	[[TGClient shared] checklistForMessage:self.messageId inChat:self.chatId
								completion:^(NSDictionary *checklist, NSString *error){
		TGChecklistViewController *me = weakSelf;
		if (!me)
			return;
		if (!checklist){
			me.loadError = error ?: @"That message has no checklist.";
			me.loaded = YES;
			[me rebuild];
			return;
		}
		me.checklistTitle = checklist[@"title"] ?: @"Checklist";
		me.tasks = [checklist[@"tasks"] mutableCopy] ?: [NSMutableArray array];
		me.canAddTasks = [checklist[@"canAddTasks"] boolValue];
		me.canMarkTasks = [checklist[@"canMarkTasks"] boolValue];
		me.othersCanAddTasks = [checklist[@"othersCanAddTasks"] boolValue];
		me.othersCanMarkTasks = [checklist[@"othersCanMarkTasks"] boolValue];
		me.loaded = YES;
		[me rebuild];
	}];
}

- (void)rebuild {
	__weak typeof(self) weakSelf = self;
	NSInteger done = 0;
	for (NSDictionary *task in self.tasks)
		if ([task[@"done"] boolValue])
			done++;

	NSMutableArray *headRows = [NSMutableArray array];
	[headRows addObject:TGTier2Row(@"Title", self.checklistTitle, ^{
		[weakSelf editTitle];
	})];
	[headRows addObject:TGTier2Row(@"Progress",
			[NSString stringWithFormat:@"%ld of %lu done", (long)done,
					(unsigned long)self.tasks.count], nil)];

	NSMutableArray *taskRows = [NSMutableArray array];
	for (NSDictionary *task in self.tasks){
		NSString *text = task[@"text"] ?: @"Task";
		BOOL isDone = [task[@"done"] boolValue];
		[taskRows addObject:TGTier2Check(text, isDone ? @"Done" : nil, isDone, ^{
			[weakSelf runTask:task];
		})];
	}
	if (!taskRows.count){
		NSMutableDictionary *empty = TGTier2Row(@"No tasks yet", nil, nil);
		empty[TGTier2RowKind] = TGTier2KindPlain;
		[taskRows addObject:empty];
	}

	NSMutableArray *actions = [NSMutableArray array];
	[actions addObject:TGTier2Action(@"Add Task", ^{ [weakSelf addTask]; })];
	if (self.messageId){
		[actions addObject:TGTier2Action(@"Save Title and Tasks", ^{
			[weakSelf saveWholeChecklist];
		})];
	} else {
		[actions addObject:TGTier2Action(@"Send Checklist", ^{
			[weakSelf sendNewChecklist];
		})];
	}

	NSMutableArray *sections = [NSMutableArray array];
	[sections addObject:TGTier2Section(nil, nil, headRows)];
	[sections addObject:TGTier2Section(@"Tasks", nil, taskRows)];
	[sections addObject:TGTier2Section(nil,
			self.loadError ?: (self.messageId
					? @"Tapping a task marks it done or not done. Its menu can rename it."
					: @"A checklist can be added to a group or channel; Telegram refuses secret chats."),
			actions)];
	self.sections = sections;
	[self reloadRows];
}

#pragma mark - writes

- (void)editTitle {
	__weak typeof(self) weakSelf = self;
	[TGAlertSheet showInput:@"Checklist Title"
					message:nil
				placeholder:@"Title"
					   text:self.checklistTitle
					 action:@"Save"
					 inView:self.view
				   onSubmit:^(NSString *title){
		weakSelf.checklistTitle = title;
		if (weakSelf.messageId)
			[weakSelf saveWholeChecklist];
		else
			[weakSelf rebuild];
	}];
}

- (void)addTask {
	__weak typeof(self) weakSelf = self;
	[TGAlertSheet showInput:@"Add Task"
					message:nil
				placeholder:@"Task"
					   text:nil
					 action:@"Add"
					 inView:self.view
				   onSubmit:^(NSString *text){
		NSMutableDictionary *task = [@{@"id"   : @(0),
									   @"text" : text,
									   @"done" : @NO} mutableCopy];
		[weakSelf.tasks addObject:task];
		if (!weakSelf.messageId){
			[weakSelf rebuild];
			return;
		}
		[[TGClient shared] addChecklistTasks:@[task]
								   toMessage:weakSelf.messageId
									  inChat:weakSelf.chatId
								  completion:^(BOOL ok, NSString *error){
			if (!ok){
				[weakSelf toast:error ?: @"Telegram refused that task."];
				return;
			}
			[weakSelf loadChecklist];
		}];
	}];
}

- (void)runTask:(NSDictionary *)task {
	__weak typeof(self) weakSelf = self;
	BOOL isDone = [task[@"done"] boolValue];
	NSString *title = isDone ? @"Mark as Not Done" : @"Mark as Done";
	[TGAlertSheet showChoices:@[title, @"Rename Task"]
						title:task[@"text"] ?: @"Task"
			 destructiveIndex:-1
					   inView:self.view
					 onChoice:^(NSInteger index){
		if (index == 0){
			[weakSelf toggleTask:task];
			return;
		}
		[TGAlertSheet showInput:@"Rename Task"
						message:nil
					placeholder:@"Task"
						   text:task[@"text"]
						 action:@"Save"
						 inView:weakSelf.view
					   onSubmit:^(NSString *text){
			NSMutableDictionary *changed = [task mutableCopy];
			changed[@"text"] = text;
			NSUInteger index = [weakSelf.tasks indexOfObjectIdenticalTo:task];
			if (index != NSNotFound)
				weakSelf.tasks[index] = changed;
			if (weakSelf.messageId)
				[weakSelf saveWholeChecklist];
			else
				[weakSelf rebuild];
		}];
	}];
}

- (void)toggleTask:(NSDictionary *)task {
	BOOL isDone = [task[@"done"] boolValue];
	NSNumber *ident = task[@"id"];
	if (!self.messageId){
		NSMutableDictionary *changed = [task mutableCopy];
		changed[@"done"] = @(!isDone);
		NSUInteger index = [self.tasks indexOfObjectIdenticalTo:task];
		if (index != NSNotFound)
			self.tasks[index] = changed;
		[self rebuild];
		return;
	}
	if (!self.canMarkTasks){
		[self toast:@"Telegram does not let this account mark these tasks."];
		return;
	}
	__weak typeof(self) weakSelf = self;
	NSArray *done = isDone ? @[] : @[ident];
	NSArray *notDone = isDone ? @[ident] : @[];
	[[TGClient shared] markChecklistTasksAsDone:done
								  notDoneTaskIds:notDone
									   onMessage:self.messageId
										  inChat:self.chatId
									  completion:^(BOOL ok, NSString *error){
		if (!ok){
			[weakSelf toast:error ?: @"Telegram refused that."];
			return;
		}
		NSMutableDictionary *changed = [task mutableCopy];
		changed[@"done"] = @(!isDone);
		NSUInteger index = [weakSelf.tasks indexOfObjectIdenticalTo:task];
		if (index != NSNotFound)
			weakSelf.tasks[index] = changed;
		[weakSelf rebuild];
	}];
}

- (void)saveWholeChecklist {
	__weak typeof(self) weakSelf = self;
	[[TGClient shared] editMessageChecklist:self.messageId
									 inChat:self.chatId
									  title:self.checklistTitle
									  tasks:self.tasks
							   othersCanAdd:self.othersCanAddTasks
							 othersCanMark:self.othersCanMarkTasks
								 completion:^(BOOL ok, NSString *error){
		if (!ok){
			[weakSelf toast:error ?: @"Telegram refused that checklist."];
			return;
		}
		[weakSelf loadChecklist];
	}];
}

- (void)sendNewChecklist {
	__weak typeof(self) weakSelf = self;
	[[TGClient shared] sendChecklist:self.checklistTitle
							   tasks:self.tasks
							  toChat:self.chatId
						  completion:^(BOOL ok, NSString *error){
		if (!ok){
			[weakSelf toast:error ?: @"Telegram refused that checklist."];
			return;
		}
		if (weakSelf.onSent)
			weakSelf.onSent();
		[weakSelf.navigationController popViewControllerAnimated:YES];
	}];
}

@end
