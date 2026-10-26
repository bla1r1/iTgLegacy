//
// TGAlertSheet - the app's own answer to UIAlertView and UIActionSheet.
//
// Those two drew themselves in the system's colours, which on a themed app
// means a white box in the middle of a dark screen, and they answered through
// a delegate keyed by a tag - which is how one screen ended up with a switch
// over five integers to remember what it had asked. This rises from the bottom
// edge like every other sheet here, takes the theme, and answers with a block.
//
// Four shapes, which is every shape the app was using:
//
//   showMessage   something to read, one OK
//   showConfirm   a question, Cancel and one action
//   showChoices   a list to pick from, Cancel under it
//   showInput     one text field, Cancel and one action
//
#import "TGSheet.h"

@interface TGAlertSheet : TGSheet

/// Something to read and nothing to decide. `title` may be nil.
+ (void)showMessage:(NSString *)message
			  title:(NSString *)title
			 inView:(UIView *)host;

/// A question. `onConfirm` runs only when the action is tapped; a tap on
/// Cancel or on the backdrop runs nothing. `destructive` draws the action red.
+ (void)showConfirm:(NSString *)message
			  title:(NSString *)title
			 action:(NSString *)actionTitle
		destructive:(BOOL)destructive
			 inView:(UIView *)host
		  onConfirm:(void (^)(void))onConfirm;

/// A list to pick from. `onChoice` gets the index into `titles`, and is not
/// called at all if the sheet is cancelled - so there is no cancel index to
/// compare against. `destructiveIndex` is -1 for none.
+ (void)showChoices:(NSArray *)titles
			  title:(NSString *)title
   destructiveIndex:(NSInteger)destructiveIndex
			 inView:(UIView *)host
		   onChoice:(void (^)(NSInteger index))onChoice;

/// One text field. `onSubmit` gets what was typed, trimmed, and runs only on
/// the action - never on Cancel, and never with an empty string.
+ (void)showInput:(NSString *)title
		  message:(NSString *)message
	  placeholder:(NSString *)placeholder
			 text:(NSString *)text
		   action:(NSString *)actionTitle
		   inView:(UIView *)host
		 onSubmit:(void (^)(NSString *text))onSubmit;

@end

// vim:ft=objc
