//
// TGMessageStreamStore.mm - C++ backed high-performance message stream manager.
//
#import "TGMessageStreamStore.h"
#include <vector>
#include <unordered_set>

@interface TGMessageStreamStore () {
	std::vector<id> _messagesVector;
	std::unordered_set<int64_t> _messageIds;
}
@end

@implementation TGMessageStreamStore

- (instancetype)init {
	self = [super init];
	if (self) {
		_messagesVector.reserve(128);
	}
	return self;
}

- (void)clear {
	_messagesVector.clear();
	_messageIds.clear();
}

- (NSUInteger)count {
	return _messagesVector.size();
}

- (int64_t)oldestMessageId {
	for (id msg : _messagesVector) {
		if ([msg isKindOfClass:[NSDictionary class]]) {
			int64_t mid = [msg[@"id"] longLongValue];
			if (mid > 0) return mid;
		}
	}
	return 0;
}

- (int64_t)newestMessageId {
	for (auto it = _messagesVector.rbegin(); it != _messagesVector.rend(); ++it) {
		id msg = *it;
		if ([msg isKindOfClass:[NSDictionary class]]) {
			int64_t mid = [msg[@"id"] longLongValue];
			if (mid > 0) return mid;
		}
	}
	return 0;
}

- (BOOL)containsMessageId:(int64_t)msgId {
	if (msgId <= 0) return NO;
	return _messageIds.find(msgId) != _messageIds.end();
}

- (void)resetWithMessages:(NSArray *)messages {
	[self clear];
	if (!messages.count) return;

	_messagesVector.reserve(messages.count);
	for (id item in messages) {
		if ([item isKindOfClass:[NSDictionary class]]) {
			int64_t mid = [item[@"id"] longLongValue];
			if (mid > 0) {
				if (_messageIds.find(mid) != _messageIds.end()) {
					continue; // skip duplicate
				}
				_messageIds.insert(mid);
			}
			_messagesVector.push_back(item);
		}
	}
}

- (NSUInteger)prependOlderMessages:(NSArray *)older {
	if (!older.count) return 0;

	std::vector<id> toPrepend;
	toPrepend.reserve(older.count);

	for (id item in older) {
		if ([item isKindOfClass:[NSDictionary class]]) {
			int64_t mid = [item[@"id"] longLongValue];
			if (mid > 0) {
				if (_messageIds.find(mid) != _messageIds.end()) {
					continue; // skip duplicate
				}
				_messageIds.insert(mid);
			}
			toPrepend.push_back(item);
		}
	}

	if (toPrepend.empty()) return 0;

	size_t addedCount = toPrepend.size();
	toPrepend.insert(toPrepend.end(), _messagesVector.begin(), _messagesVector.end());
	_messagesVector = std::move(toPrepend);

	return addedCount;
}

- (NSUInteger)appendNewerMessages:(NSArray *)newer {
	if (!newer.count) return 0;

	NSUInteger addedCount = 0;
	for (id item in newer) {
		if ([item isKindOfClass:[NSDictionary class]]) {
			int64_t mid = [item[@"id"] longLongValue];
			if (mid > 0) {
				if (_messageIds.find(mid) != _messageIds.end()) {
					continue; // skip duplicate
				}
				_messageIds.insert(mid);
			}
			_messagesVector.push_back(item);
			addedCount++;
		}
	}

	return addedCount;
}

- (BOOL)removeMessageId:(int64_t)msgId {
	if (msgId <= 0) return NO;
	auto idIt = _messageIds.find(msgId);
	if (idIt == _messageIds.end()) return NO;
	_messageIds.erase(idIt);

	for (auto it = _messagesVector.begin(); it != _messagesVector.end(); ++it) {
		id item = *it;
		if ([item isKindOfClass:[NSDictionary class]] && [item[@"id"] longLongValue] == msgId) {
			_messagesVector.erase(it);
			return YES;
		}
	}
	return NO;
}

- (NSArray *)messages {
	if (_messagesVector.empty()) return @[];
	NSMutableArray *out = [NSMutableArray arrayWithCapacity:_messagesVector.size()];
	for (id item : _messagesVector) {
		[out addObject:item];
	}
	return out;
}

@end
