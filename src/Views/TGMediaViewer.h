//
// TGMediaViewer - the in-app viewer for pictures and video, the way the
// current clients do it.
//
// What this replaces was a black view with one UIImageView on it: it showed
// whatever bitmap the bubble happened to be holding - which is a thumbnail
// scaled to 200pt - and there was no way to reach the next picture without
// closing it and finding the message.
//
// This one pages sideways through every picture and video in the chat, fetches
// the original file for whichever page you are on, zooms, and plays video
// inside the app rather than handing it to the system player - which on iOS 7
// takes over the screen with its own chrome and its own idea of a back button.
//
#import <UIKit/UIKit.h>

@interface TGMediaViewer : NSObject

/// `items` are flattened messages, oldest first, each carrying "photoId" or
/// "docId", "kind", "text" (the caption), "date" and "senderId". Anything that
/// is not a picture or a video is skipped.
///
/// Nothing is retained by the caller: the viewer holds itself up while it is
/// on screen and lets go when it is dismissed.
+ (void)presentItems:(NSArray *)items
			 startAt:(NSInteger)index
			 inChat:(int64_t)chatId;

@end
