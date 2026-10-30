//
// TGImageLruCache.h - Objective-C bounded LRU cache adapter over C++ TGLruCache.
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
