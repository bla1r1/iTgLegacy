//
// TGUpdateBatcher.mm - High-performance C++ update coalescing & batching for TDLib events.
//
#import "TGUpdateBatcher.hpp"

TGUpdateBatcher::TGUpdateBatcher(uint32_t coalesceIntervalMs)
	: _orderDirty(false),
	  _flushScheduled(false),
	  _coalesceIntervalMs(coalesceIntervalMs ? coalesceIntervalMs : 100),
	  _alive(std::make_shared<bool>(true)),
	  _flushHandler(nil)
{
}

TGUpdateBatcher::~TGUpdateBatcher() {
	if (_alive) {
		*_alive = false;
	}
	_flushHandler = nil;
}

void TGUpdateBatcher::setFlushHandler(TGUpdateBatchFlushBlock handler) {
	std::lock_guard<std::mutex> lock(_mutex);
	_flushHandler = [handler copy];
}

void TGUpdateBatcher::markChatDirty(int64_t chatId) {
	std::lock_guard<std::mutex> lock(_mutex);
	_dirtyChats.insert(chatId);
	scheduleFlushIfNeeded();
}

void TGUpdateBatcher::markUserDirty(int64_t userId) {
	std::lock_guard<std::mutex> lock(_mutex);
	_dirtyUsers.insert(userId);
	scheduleFlushIfNeeded();
}

void TGUpdateBatcher::markOrderDirty() {
	std::lock_guard<std::mutex> lock(_mutex);
	_orderDirty = true;
	scheduleFlushIfNeeded();
}

void TGUpdateBatcher::scheduleFlushIfNeeded() {
	if (_flushScheduled) {
		return;
	}
	_flushScheduled = true;

	std::shared_ptr<bool> alive = _alive;
	uint64_t delayMs = _coalesceIntervalMs;
	dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(delayMs * NSEC_PER_MSEC)),
				   dispatch_get_main_queue(), ^{
		if (alive && *alive) {
			this->flushNow();
		}
	});
}

void TGUpdateBatcher::flushNow() {
	std::unordered_set<int64_t> chats;
	std::unordered_set<int64_t> users;
	bool order = false;
	TGUpdateBatchFlushBlock handler = nil;

	{
		std::lock_guard<std::mutex> lock(_mutex);
		if (!_flushScheduled && _dirtyChats.empty() && _dirtyUsers.empty() && !_orderDirty) {
			return;
		}
		_flushScheduled = false;
		chats.swap(_dirtyChats);
		users.swap(_dirtyUsers);
		order = _orderDirty;
		_orderDirty = false;
		handler = _flushHandler;
	}

	if (!handler || (chats.empty() && users.empty() && !order)) {
		return;
	}

	NSMutableSet *chatSet = [NSMutableSet setWithCapacity:chats.size()];
	for (int64_t cid : chats) {
		[chatSet addObject:@(cid)];
	}

	NSMutableSet *userSet = [NSMutableSet setWithCapacity:users.size()];
	for (int64_t uid : users) {
		[userSet addObject:@(uid)];
	}

	handler(chatSet, userSet, order);
}

void TGUpdateBatcher::reset() {
	std::lock_guard<std::mutex> lock(_mutex);
	_dirtyChats.clear();
	_dirtyUsers.clear();
	_orderDirty = false;
	_flushScheduled = false;
}

size_t TGUpdateBatcher::pendingCount() {
	std::lock_guard<std::mutex> lock(_mutex);
	return _dirtyChats.size() + _dirtyUsers.size() + (_orderDirty ? 1 : 0);
}

@implementation TGUpdateCoalescer {
	TGUpdateBatcher *_batcher;
}

- (instancetype)initWithIntervalMs:(uint32_t)intervalMs {
	self = [super init];
	if (self) {
		_batcher = new TGUpdateBatcher(intervalMs);
	}
	return self;
}

- (void)dealloc {
	delete _batcher;
	_batcher = nullptr;
}

- (void)markChatDirty:(int64_t)chatId {
	if (_batcher) _batcher->markChatDirty(chatId);
}

- (void)markUserDirty:(int64_t)userId {
	if (_batcher) _batcher->markUserDirty(userId);
}

- (void)markOrderDirty {
	if (_batcher) _batcher->markOrderDirty();
}

- (void)flushNow {
	if (_batcher) _batcher->flushNow();
}

- (void)reset {
	if (_batcher) _batcher->reset();
}

- (void)setFlushHandler:(TGUpdateBatchFlushBlock)handler {
	if (_batcher) _batcher->setFlushHandler(handler);
}

- (NSUInteger)pendingCount {
	return _batcher ? _batcher->pendingCount() : 0;
}

@end
