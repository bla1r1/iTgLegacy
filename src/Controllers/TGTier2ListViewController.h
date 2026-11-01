//
// TGTier2ListViewController.h - the row model three Tier 2 screens share.
//
// Communities, quick replies and the message tools are all settings-shaped
// lists: a title, a value on the right, and a tap. Their rows are dictionaries
// rather than eight hand-written table views, the way Settings does it.
//
#import <UIKit/UIKit.h>

extern NSString *const TGTier2RowTitle;
extern NSString *const TGTier2RowDetail;
extern NSString *const TGTier2RowKind;
extern NSString *const TGTier2RowTap;
extern NSString *const TGTier2RowChecked;
extern NSString *const TGTier2RowSubtitle;
extern NSString *const TGTier2RowDestructive;

extern NSString *const TGTier2KindPlain;
extern NSString *const TGTier2KindDisclosure;
extern NSString *const TGTier2KindCheck;
extern NSString *const TGTier2KindAction;
extern NSString *const TGTier2KindDestructive;

NSMutableDictionary *TGTier2Row(NSString *title, NSString *detail, void (^tap)(void));
NSMutableDictionary *TGTier2Action(NSString *title, void (^tap)(void));
NSMutableDictionary *TGTier2Check(NSString *title, NSString *detail, BOOL checked,
								  void (^tap)(void));
NSDictionary *TGTier2Section(NSString *header, NSString *footer, NSArray *rows);

@interface TGTier2ListViewController : UITableViewController

/// Each section is "header", "footer" and "rows". Subclasses replace this
/// and call -reloadRows.
@property (nonatomic, strong) NSArray *sections;

- (void)reloadRows;
- (void)applyTheme;
- (void)toast:(NSString *)text;

@end

/// A read-only text screen with Copy, and Send when the caller has a chat to
/// put the text in.
@interface TGTier2ResultViewController : UIViewController

@property (nonatomic, copy) NSString *body;
@property (nonatomic, copy) void (^onSend)(NSString *text);

- (instancetype)initWithTitle:(NSString *)title body:(NSString *)body;

@end
