#import "TGChatListRowGeometry.h"

NSString *TGChatListArchiveSubtitle(NSUInteger count) {
	return [NSString stringWithFormat:@"%lu %@", (unsigned long)count,
			count == 1 ? @"chat" : @"chats"];
}

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
                              CGFloat *previewRight) {
	CGFloat x = rightEdge;

	if (hasBadge){
		if (badgeFrame)
			*badgeFrame = CGRectMake(x - badgeWidth, top, badgeWidth, badgeHeight);
		x -= badgeWidth + gap;
	} else if (badgeFrame){
		*badgeFrame = CGRectZero;
	}

	if (hasPin){
		if (pinFrame)
			*pinFrame = CGRectMake(x - pinSide,
					top + (badgeHeight - pinSide) * 0.5f, pinSide, pinSide);
		x -= pinSide + gap;
	} else if (pinFrame){
		*pinFrame = CGRectZero;
	}

	if (previewRight)
		*previewRight = x;
}
