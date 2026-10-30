//
// TGMessageStreamStore.mm - C++ backed high-performance message stream manager.
//
#import "TGMessageStreamStore.h"
#import "TGFlattenedMessage.hpp"
#include <vector>
#include <unordered_set>

/// The flat scalar index that runs beside the dictionaries: one 88-byte POD
/// per message, in the same order. Bounds, de-duplication, removal and the
/// scalar accessors read this and never touch an NSDictionary - walking fifty
/// of those, unboxing an NSNumber each time, was the store's whole cost.
///
/// ponytail: the dictionaries stay, because every cell and layout still reads
/// m[@"text"] and friends; replacing those is the rest of the migration, and
/// it is a change to every view in the app rather than to this file.
static TGFlattenedMessage TGIndexFromDictionary(NSDictionary *m) {
	TGFlattenedMessage out;
	TGFlattenedMessageClear(out);
	out.messageId = [m[@"id"] longLongValue];
	out.chatId    = [m[@"chatId"] longLongValue];
	out.senderId  = [m[@"senderId"] longLongValue];
	out.date      = (int32_t)[m[@"date"] longLongValue];
	out.duration  = (int32_t)[m[@"duration"] intValue];
	out.set(TGMessageFlagOutgoing, [m[@"outgoing"] boolValue]);
	out.set(TGMessageFlagEdited,   [m[@"edited"] boolValue]);
	out.set(TGMessageFlagService,  [m[@"service"] boolValue]);
	out.set(TGMessageFlagFailed,   [m[@"failed"] boolValue]);
	out.set(TGMessageFlagUnplayed, [m[@"unplayed"] boolValue]);
	NSString *kind = m[@"kind"];
	out.kind = TGMessageKindFromTypeName(kind.length ? kind.UTF8String : "");
	return out;
}

@interface TGMessageStreamStore () {
	std::vector<id> _messagesVector;
	std::vector<TGFlattenedMessage> _index;
	std::unordered_set<int64_t> _messageIds;
}
@end

@implementation TGMessageStreamStore

- (instancetype)init {
	self = [super init];
	if (self) {
		_messagesVector.reserve(128);
		_index.reserve(128);
	}
	return self;
}

- (void)clear {
	_messagesVector.clear();
	_index.clear();
	_messageIds.clear();
}

- (NSUInteger)count {
	return _messagesVector.size();
}

- (int64_t)oldestMessageId {
	for (const TGFlattenedMessage &entry : _index) {
		if (entry.messageId > 0) return entry.messageId;
	}
	return 0;
}

- (int64_t)newestMessageId {
	for (auto it = _index.rbegin(); it != _index.rend(); ++it) {
		if (it->messageId > 0) return it->messageId;
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
	_index.reserve(messages.count);
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
			_index.push_back(TGIndexFromDictionary(item));
		}
	}
}

- (NSUInteger)prependOlderMessages:(NSArray *)older {
	if (!older.count) return 0;

	std::vector<id> toPrepend;
	std::vector<TGFlattenedMessage> indexToPrepend;
	toPrepend.reserve(older.count);
	indexToPrepend.reserve(older.count);

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
			indexToPrepend.push_back(TGIndexFromDictionary(item));
		}
	}

	if (toPrepend.empty()) return 0;

	size_t addedCount = toPrepend.size();
	toPrepend.insert(toPrepend.end(), _messagesVector.begin(), _messagesVector.end());
	_messagesVector = std::move(toPrepend);
	indexToPrepend.insert(indexToPrepend.end(), _index.begin(), _index.end());
	_index = std::move(indexToPrepend);

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
			_index.push_back(TGIndexFromDictionary(item));
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

	for (size_t i = 0; i < _index.size(); i++) {
		if (_index[i].messageId != msgId)
			continue;
		_messagesVector.erase(_messagesVector.begin() + (long)i);
		_index.erase(_index.begin() + (long)i);
		return YES;
	}
	return NO;
}

#pragma mark - flat index

- (int64_t)messageIdAtIndex:(NSUInteger)index {
	return (index < _index.size()) ? _index[index].messageId : 0;
}

- (int32_t)dateAtIndex:(NSUInteger)index {
	return (index < _index.size()) ? _index[index].date : 0;
}

- (BOOL)isOutgoingAtIndex:(NSUInteger)index {
	return (index < _index.size()) &&
			_index[index].has(TGMessageFlagOutgoing);
}

- (NSUInteger)indexOfMessageId:(int64_t)msgId {
	if (msgId > 0) {
		for (size_t i = 0; i < _index.size(); i++) {
			if (_index[i].messageId == msgId)
				return i;
		}
	}
	return NSNotFound;
}

- (NSUInteger)indexByteSize {
	return _index.size() * sizeof(TGFlattenedMessage);
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
