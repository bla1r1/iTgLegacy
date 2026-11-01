//
// TGChecklistViewController.h - checklist composer and editor.
//
// A message id of 0 is a new checklist: the tasks stay local and
// Send Checklist posts them. A real id reads the message, and every tap
// writes through addChecklistTasks, markChecklistTasksAsDone or
// editMessageChecklist.
//
#import "TGTier2ListViewController.h"

@interface TGChecklistViewController : TGTier2ListViewController

- (instancetype)initWithChatId:(int64_t)chatId
                     messageId:(int64_t)messageId
                         title:(NSString *)title;

@property (nonatomic, copy) void (^onSent)(void);

@end
