//
// TGUpdateBatcher.hpp - High-performance C++ update coalescing & batching for TDLib events.
//
#ifndef TGUPDATEBATCHER_HPP
#define TGUPDATEBATCHER_HPP

#import <Foundation/Foundation.h>

#ifdef __cplusplus
#include <unordered_set>
#include <mutex>
#include <memory>
#include <cstdint>

typedef void (^TGUpdateBatchFlushBlock)(NSSet *dirtyChatIds, NSSet *dirtyUserIds, BOOL orderChanged);

class TGUpdateBatcher {
private:
	std::mutex _mutex;
	std::unordered_set<int64_t> _dirtyChats;
	std::unordered_set<int64_t> _dirtyUsers;
	bool _orderDirty;
	bool _flushScheduled;
	uint32_t _coalesceIntervalMs;
	std::shared_ptr<bool> _alive;
	__strong TGUpdateBatchFlushBlock _flushHandler;

public:
	explicit TGUpdateBatcher(uint32_t coalesceIntervalMs = 100);
	~TGUpdateBatcher();

	void setFlushHandler(TGUpdateBatchFlushBlock handler);

	void markChatDirty(int64_t chatId);
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
#endif

// Objective-C wrapper for seamless integration into ObjC controllers & client categories
@interface TGUpdateCoalescer : NSObject

- (instancetype)initWithIntervalMs:(uint32_t)intervalMs;
- (void)markChatDirty:(int64_t)chatId;
- (void)markUserDirty:(int64_t)userId;
- (void)markOrderDirty;
- (void)flushNow;
- (void)reset;
- (void)setFlushHandler:(TGUpdateBatchFlushBlock)handler;
- (NSUInteger)pendingCount;

@end

#endif // TGUPDATEBATCHER_HPP
