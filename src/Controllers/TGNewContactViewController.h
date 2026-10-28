//
// TGNewContactViewController - a new contact: first name, last name, phone.
//
#import <UIKit/UIKit.h>

@interface TGNewContactViewController : UITableViewController

/// Where the fields start, when the chat adds a name it already knows.
/// Set before the view loads.
@property (nonatomic, copy) NSString *first;
@property (nonatomic, copy) NSString *last;
@property (nonatomic, copy) NSString *phone;

@end
