//
// TGMediaViewer - fullscreen media viewer for photos and video.
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
			  inChat:(int64_t)chatId
			 isAlbum:(BOOL)isAlbum;

+ (void)presentItems:(NSArray *)items
			 startAt:(NSInteger)index
			  inChat:(int64_t)chatId;

/// As above, but the picture grows out of `sourceView` (the image view that
/// shows it in the chat) and shrinks back into it on dismiss. The viewer holds
/// the view weakly and hides it while the picture is up, so it is not drawn
/// twice. With a nil view, or one with no image yet, this fades like the
/// variants above.
+ (void)presentItems:(NSArray *)items
			 startAt:(NSInteger)index
			  inChat:(int64_t)chatId
			 isAlbum:(BOOL)isAlbum
			fromView:(UIView *)sourceView;

@end
