//
// TGBusinessMessagesViewController.h - the business-bot connection and the
// message calls TDLib declares on its behalf.
//
#import "TGBusinessViewController.h"

/// getBusinessConnection plus the id the message screen sends with.
@interface TGBusinessConnectionViewController : TGBusinessBaseViewController
@end

/// Send, edit, read, pin and delete business messages. Every request names
/// the connection id; without one Telegram's refusal is the answer shown.
@interface TGBusinessMessagesViewController : TGBusinessBaseViewController
@end

// vim:ft=objc
