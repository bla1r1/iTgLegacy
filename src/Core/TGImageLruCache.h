//
// TGImageLruCache.h - Objective-C bounded LRU cache adapters over C++
// TGLruCache.
//
// Two of them, because an unbounded NSMutableDictionary is how a cache on a
// 256 MB phone turns into an OOM kill: TGImageLruCache for decoded pictures,
// TGObjectLruCache for anything else held by integer id. Both evict the least
// recently used entry one at a time rather than flushing everything.
//
#import <UIKit/UIKit.h>

@interface TGImageLruCache : NSObject

- (instancetype)initWithCapacity:(NSUInteger)capacity;

- (UIImage *)objectForKeyedSubscript:(id)key;
- (void)setObject:(UIImage *)image forKeyedSubscript:(id)key;

- (UIImage *)objectForKey:(id)key;
- (void)setObject:(UIImage *)image forKey:(id)key;
- (void)removeObjectForKey:(id)key;
- (void)removeAllObjects;

@property (nonatomic, readonly) NSUInteger count;
@property (nonatomic, readonly) NSUInteger capacity;

@end


/// The same bound over arbitrary objects - a raw user record, a parsed
/// entity - keyed by an integer id. The subscript shape is NSMutableDictionary's,
/// so it drops straight into code that held one.
@interface TGObjectLruCache : NSObject

- (instancetype)initWithCapacity:(NSUInteger)capacity;

- (id)objectForKeyedSubscript:(id)key;
- (void)setObject:(id)object forKeyedSubscript:(id)key;

- (id)objectForKey:(id)key;
- (void)setObject:(id)object forKey:(id)key;
- (void)removeObjectForKey:(id)key;
- (void)removeAllObjects;

@property (nonatomic, readonly) NSUInteger count;
@property (nonatomic, readonly) NSUInteger capacity;

@end
