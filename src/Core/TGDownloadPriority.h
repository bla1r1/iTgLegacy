//
// TGDownloadPriority - download-queue priorities, shared by the client and
// the domain stores. Kept out of TGClient.h so a view can name a priority
// without importing the whole client header.
//
typedef NS_ENUM(NSInteger, TGDownloadPriority) {
	TGDownloadPriorityBackground = 1,   // media a scroll may never reach
	TGDownloadPriorityOnScreen   = 16,  // tiles the user is looking at right now
	TGDownloadPriorityAvatar     = 32,  // avatars: small files, always wanted
};
