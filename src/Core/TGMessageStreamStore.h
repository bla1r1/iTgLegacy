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

@end
