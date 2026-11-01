//
// TGClient - TDLib client wrapper.
// Dynamically loads libtdjson.dylib; background receive loop dispatches to main queue.
//
// The surface lives in one header per duty - messages, stickers, downloads
// and the rest. This file imports them all, so a screen still does
// #import "TGClient.h" once and sees the whole client.
//
#import "TGClientTypes.h"
#import "TGClientNotifications.h"
#import "TGDownloadPriority.h"
#import "TGClient+Base.h"
#import "TGClient+Account.h"
#import "TGClient+Appearance.h"
#import "TGClient+Auth.h"
#import "TGClient+BotTools.h"
#import "TGClient+Calls.h"
#import "TGClient+Diagnostics.h"
#import "TGClient+Chats.h"
#import "TGClient+ChatTools.h"
#import "TGClient+Downloads.h"
#import "TGClient+Files.h"
#import "TGClient+Groups.h"
#import "TGClient+Language.h"
#import "TGClient+MessageMeta.h"
#import "TGClient+Messages.h"
#import "TGClient+Notifications.h"
#import "TGClient+Payments.h"
#import "TGClient+Profile.h"
#import "TGClient+Proxy.h"
#import "TGClient+SavedMessages.h"
#import "TGClient+Search.h"
#import "TGClient+Secret.h"
#import "TGClient+Stickers.h"
#import "TGClient+Stories.h"
#import "TGClient+Usernames.h"
#import "TGClient+Websites.h"
