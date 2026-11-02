//
// TGChatListRowGeometry.h - the trailing accessories of a chat list row.
//
// The unread count and the pin marker are two objects on the same line, and
// Telegram draws both: a pinned chat that also has unread messages used to
// lose its pin because the count was placed where the pin went. Keeping the
// arithmetic here lets the host suite prove the two never overlap; TGChatCell
// has no honest way to be measured without a live UIKit hierarchy.
//
#ifndef TGCHATLISTROWGEOMETRY_H
#define TGCHATLISTROWGEOMETRY_H

#import <Foundation/Foundation.h>
#import <CoreGraphics/CoreGraphics.h>

#ifdef __cplusplus
extern "C" {
#endif

/// The archive row's second line: "1 chat" never reads "1 chats". Singular
/// plural is the one bit of Telegram's wording this row has to get right, and
/// the archive is the only row whose count can be one.
NSString *TGChatListArchiveSubtitle(NSUInteger count);

/// Frames for the badge and the pin at the trailing edge of the row's second
/// line, and where the preview has to stop.
///
/// The badge keeps the corner; the pin sits to its left, which is the order
/// Telegram uses (count at the edge, pin beside it). Both frames are
/// CGRectZero when their flag is NO. `previewRight` is the left edge of the
/// first accessory minus `gap`, so a preview is never drawn underneath one.
void TGChatListRowAccessories(CGFloat rightEdge,
                              CGFloat top,
                              BOOL hasBadge,
                              CGFloat badgeWidth,
                              CGFloat badgeHeight,
                              BOOL hasPin,
                              CGFloat pinSide,
                              CGFloat gap,
                              CGRect *badgeFrame,
                              CGRect *pinFrame,
                              CGFloat *previewRight);

/// The chats a stopped scroll needs pictures for: one row behind it, for the
/// archive row that shifts the list by one, and `rows` from there on.
NSRange TGAvatarWindow(NSInteger firstVisible, NSUInteger rows, NSUInteger total);

#ifdef __cplusplus
}
#endif

#endif // TGCHATLISTROWGEOMETRY_H
