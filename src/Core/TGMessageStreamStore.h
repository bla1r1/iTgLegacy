//
// TGMessageStreamStore.h - C++ backed high-performance message stream manager.
//
// Maintains bidirectional chronological message stream with O(1) duplicate
// detection and boundary tracking for chat pagination.
//
#import <Foundation/Foundation.h>

@interface TGMessageStreamStore : NSObject

@property (nonatomic, readonly) NSArray *messages;
@property (nonatomic, readonly) NSUInteger count;
@property (nonatomic, readonly) int64_t oldestMessageId;
@property (nonatomic, readonly) int64_t newestMessageId;

/// Replace all messages with a new initial set (ordered oldest to newest).
- (void)resetWithMessages:(NSArray *)messages;

/// Prepend older messages to the beginning of the stream.
/// Filters out duplicates. Returns number of newly prepended messages.
- (NSUInteger)prependOlderMessages:(NSArray *)older;

/// Append newer messages to the end of the stream.
/// Filters out duplicates. Returns number of newly appended messages.
- (NSUInteger)appendNewerMessages:(NSArray *)newer;

/// Check if a message ID is already present in the stream.
- (BOOL)containsMessageId:(int64_t)msgId;

/// Remove a message by ID.
- (BOOL)removeMessageId:(int64_t)msgId;

/// Clear the entire stream.
- (void)clear;

// ─── the flat scalar index ───────────────────────────────────────────────────
// Answered from a contiguous buffer of 88-byte PODs rather than from the
// message dictionaries: no NSNumber unboxing, no objc_msgSend per field.

/// The message id at a position in the stream, or 0 past the end.
- (int64_t)messageIdAtIndex:(NSUInteger)index;

/// Its unix timestamp, or 0 past the end.
- (int32_t)dateAtIndex:(NSUInteger)index;

/// Whether it is ours, false past the end.
- (BOOL)isOutgoingAtIndex:(NSUInteger)index;

/// Where a message id sits in the stream, or NSNotFound.
- (NSUInteger)indexOfMessageId:(int64_t)msgId;

/// Bytes the flat index occupies - what the saving is measured against.
- (NSUInteger)indexByteSize;

@end
