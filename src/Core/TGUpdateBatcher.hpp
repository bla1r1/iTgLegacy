//
// TGUpdateBatcher.hpp - High-performance C++ update coalescing & batching for TDLib events.
//
#ifndef TGUPDATEBATCHER_HPP
#define TGUPDATEBATCHER_HPP

#import <Foundation/Foundation.h>

#ifdef __cplusplus
#include <unordered_set>
#include <unordered_map>
#include <mutex>
#include <memory>
#include <cstdint>

typedef void (^TGUpdateBatchFlushBlock)(NSSet *dirtyChatIds, NSSet *dirtyUserIds, BOOL orderChanged);
/// Dirty message ids grouped by chat: @{chatId: NSSet of message ids}.
typedef void (^TGUpdateBatchMessagesBlock)(NSDictionary *messageIdsByChat);

class TGUpdateBatcher {
private:
	std::mutex _mutex;
	std::unordered_set<int64_t> _dirtyChats;
	std::unordered_set<int64_t> _dirtyUsers;
	// Reactions and view counts on one message arrive one update per tick, so
	// these are the updates that most need coalescing: a popular channel post
	// being read by a crowd would otherwise re-read the history per reaction.
	std::unordered_map<int64_t, std::unordered_set<int64_t> > _dirtyMessages;
	bool _orderDirty;
	bool _flushScheduled;
	uint32_t _coalesceIntervalMs;
	std::shared_ptr<bool> _alive;
	__strong TGUpdateBatchFlushBlock _flushHandler;
	__strong TGUpdateBatchMessagesBlock _messagesHandler;

public:
	explicit TGUpdateBatcher(uint32_t coalesceIntervalMs = 100);
	~TGUpdateBatcher();

	void setFlushHandler(TGUpdateBatchFlushBlock handler);
	void setMessagesHandler(TGUpdateBatchMessagesBlock handler);

	void markChatDirty(int64_t chatId);
	void markMessageDirty(int64_t chatId, int64_t messageId);
	void markUserDirty(int64_t userId);
	void markOrderDirty();

	void flushNow();
	void reset();

	size_t pendingCount();

private:
	void scheduleFlushIfNeeded();
};
#else
typedef void (^TGUpdateBatchFlushBlock)(NSSet *dirtyChatIds, NSSet *dirtyUserIds, BOOL orderChanged);
typedef void (^TGUpdateBatchMessagesBlock)(NSDictionary *messageIdsByChat);
#endif

// Objective-C wrapper for seamless integration into ObjC controllers & client categories
@interface TGUpdateCoalescer : NSObject

- (instancetype)initWithIntervalMs:(uint32_t)intervalMs;
- (void)markChatDirty:(int64_t)chatId;
- (void)markMessageDirty:(int64_t)messageId inChat:(int64_t)chatId;
- (void)markUserDirty:(int64_t)userId;
- (void)markOrderDirty;
- (void)flushNow;
- (void)reset;
- (void)setFlushHandler:(TGUpdateBatchFlushBlock)handler;
- (void)setMessagesHandler:(TGUpdateBatchMessagesBlock)handler;
- (NSUInteger)pendingCount;

@end

#endif // TGUPDATEBATCHER_HPP
