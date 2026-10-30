//
// TGImageLruCache.mm - Objective-C bounded LRU cache adapter over C++ TGLruCache.
//
#import "TGImageLruCache.h"
#import "TGLruCache.hpp"

static inline int64_t TGKeyToInt64(id key) {
	if (!key) return 0;
	if ([key isKindOfClass:[NSNumber class]]) {
		return [(NSNumber *)key longLongValue];
	}
	if ([key respondsToSelector:@selector(longLongValue)]) {
		return [key longLongValue];
	}
	return (int64_t)[key hash];
}

@interface TGImageLruCache () {
	TGLruCache<int64_t, UIImage *> _cache;
}
@end

@implementation TGImageLruCache

- (instancetype)initWithCapacity:(NSUInteger)capacity {
	if ((self = [super init])) {
		_cache.set_capacity(capacity ? capacity : 50);
	}
	return self;
}

- (instancetype)init {
	return [self initWithCapacity:50];
}

- (UIImage *)objectForKeyedSubscript:(id)key {
	if (!key) return nil;
	UIImage *val = nil;
	if (_cache.get(TGKeyToInt64(key), val)) {
		return val;
	}
	return nil;
}

- (void)setObject:(UIImage *)image forKeyedSubscript:(id)key {
	if (!key) return;
	int64_t k = TGKeyToInt64(key);
	if (image) {
		_cache.put(k, image);
	} else {
		_cache.remove(k);
	}
}

- (UIImage *)objectForKey:(id)key {
	return [self objectForKeyedSubscript:key];
}

- (void)setObject:(UIImage *)image forKey:(id)key {
	[self setObject:image forKeyedSubscript:key];
}

- (void)removeObjectForKey:(id)key {
	if (key) {
		_cache.remove(TGKeyToInt64(key));
	}
}

- (void)removeAllObjects {
	_cache.clear();
}

- (NSUInteger)count {
	return _cache.size();
}

- (NSUInteger)capacity {
	return _cache.capacity();
}

@end
