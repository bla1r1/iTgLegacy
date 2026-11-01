//
// TGStoriesCell - the horizontal strip at the top of the chat list.
//
// The cell owns only its drawing: the controller hands it rows that already
// carry a decoded avatar, because a view that reached for TGClient would be a
// second place that knows how avatars are fetched.
//
#import <UIKit/UIKit.h>

@interface TGStoriesCell : UITableViewCell

/// Rows from -activeStoryRowsForList:. Each may carry "avatarImage"; without
/// one the bubble falls back to the chat's initial.
@property (nonatomic, strong) NSArray *stories;

@property (nonatomic, copy) void (^onAddStory)(void);
@property (nonatomic, copy) void (^onMore)(void);
@property (nonatomic, copy) void (^onStoryTapped)(NSDictionary *row);
@property (nonatomic, copy) void (^onStoryHeld)(NSDictionary *row);

@end
