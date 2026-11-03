//
// TGPlaybackQueue.h - what plays after the voice or round note that just ended.
//
#import <Foundation/Foundation.h>

/// The row of the next voice or round note after the message `currentId`, in
/// chat order, or NSNotFound. A note whose file id is missing cannot be played.
FOUNDATION_EXPORT NSInteger TGNextPlayableRow(NSArray *messages, int64_t currentId);

/// The file to fetch ahead of time so Next starts at once. Nil on shuffle, at the
/// end of the list, or for a file over 32 MB nobody asked for yet.
FOUNDATION_EXPORT NSNumber *TGTrackToPrefetch(NSArray *tracks, NSInteger index, BOOL shuffle,
		BOOL repeatAll);

/// Whether a voice or round note carries the dot that says nobody has heard it.
/// It is on your own notes as well: its going away is the only way a sender learns
/// the note was opened. In Saved Messages and on a channel post nobody reports
/// back, so the dot would never go.
FOUNDATION_EXPORT BOOL TGShowsUnplayedMark(NSDictionary *message, BOOL inSavedMessages);
