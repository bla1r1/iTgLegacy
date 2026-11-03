//
// TGJson.mm - JSON in through yyjson, out through TGJsonWriter.
//
// Reading stays on yyjson: it is the fast part, and the app genuinely needs
// the NSDictionary tree TDLib's answers become. Writing does not - an
// outgoing request is built once and sent once, so the yyjson_mut_doc that
// used to sit between the dictionary and the text was a second tree of
// allocations for nothing. TGJsonWriter formats straight into one buffer.
//
#import "TGJson.h"
#import "TGJsonWriter.hpp"
#include "yyjson/yyjson.h"

/// TDLib writes an absent object as null, which arrives here as NSNull, and
/// reading a number out of it took the app down in the middle of a scroll. Code
/// that asks the wrong type of a field is everywhere and only meets a null on
/// the odd message, so NSNull answers like nil does: zero, nil, NO. A selector is
/// logged once with its caller, so the field can still be found and fixed.
@implementation NSNull (TGAnswersLikeNil)

- (NSMethodSignature *)methodSignatureForSelector:(SEL)selector {
	for (Class type in @[NSNumber.class, NSString.class, NSDictionary.class, NSArray.class]){
		NSMethodSignature *signature = [type instanceMethodSignatureForSelector:selector];
		if (signature)
			return signature;
	}
	return [NSObject instanceMethodSignatureForSelector:selector];
}

- (void)forwardInvocation:(NSInvocation *)invocation {
	static NSMutableSet *logged;
	@synchronized(self.class){
		if (!logged)
			logged = [NSMutableSet set];
		NSString *name = NSStringFromSelector(invocation.selector);
		if (![logged containsObject:name]){
			[logged addObject:name];
			NSArray *stack = [NSThread callStackSymbols];
			NSLog(@"TGJson: -[NSNull %@] from %@", name,
					[stack subarrayWithRange:NSMakeRange(0, MIN((NSUInteger)8, stack.count))]);
		}
	}
	[invocation invokeWithTarget:nil];
}

@end

static id TGConvertVal(yyjson_val *val) {
	if (!val)
		return nil;

	switch (yyjson_get_type(val)){
		case YYJSON_TYPE_NULL:
			return [NSNull null];

		case YYJSON_TYPE_BOOL:
			return yyjson_get_bool(val) ? (id)kCFBooleanTrue : (id)kCFBooleanFalse;

		case YYJSON_TYPE_NUM: {
			uint8_t subtype = yyjson_get_subtype(val);
			if (subtype == YYJSON_SUBTYPE_UINT){
				return @(yyjson_get_uint(val));
			} else if (subtype == YYJSON_SUBTYPE_SINT){
				return @(yyjson_get_sint(val));
			} else {
				return @(yyjson_get_real(val));
			}
		}

		case YYJSON_TYPE_STR: {
			const char *str = yyjson_get_str(val);
			size_t len = yyjson_get_len(val);
			return [[NSString alloc] initWithBytes:str length:len encoding:NSUTF8StringEncoding];
		}

		case YYJSON_TYPE_ARR: {
			size_t size = yyjson_arr_size(val);
			NSMutableArray *arr = [NSMutableArray arrayWithCapacity:size];
			size_t idx, max;
			yyjson_val *item;
			yyjson_arr_foreach(val, idx, max, item){
				id converted = TGConvertVal(item);
				[arr addObject:converted ?: [NSNull null]];
			}
			return arr;
		}

		case YYJSON_TYPE_OBJ: {
			size_t size = yyjson_obj_size(val);
			NSMutableDictionary *dict = [NSMutableDictionary dictionaryWithCapacity:size];
			size_t idx, max;
			yyjson_val *key, *item;
			yyjson_obj_foreach(val, idx, max, key, item){
				const char *kstr = yyjson_get_str(key);
				size_t klen = yyjson_get_len(key);
				NSString *k = [[NSString alloc] initWithBytes:kstr length:klen encoding:NSUTF8StringEncoding];
				id converted = TGConvertVal(item);
				if (k && converted){
					dict[k] = converted;
				}
			}
			return dict;
		}

		default:
			return nil;
	}
}

static yyjson_doc *TGReadDoc(const char *utf8, size_t len, NSError **error) {
	if (!utf8 || len == 0){
		if (error)
			*error = [NSError errorWithDomain:@"TGJsonErrorDomain" code:-1
									 userInfo:@{NSLocalizedDescriptionKey : @"Empty JSON payload"}];
		return NULL;
	}

	yyjson_read_err err;
	yyjson_doc *doc = yyjson_read_opts((char *)utf8, len, YYJSON_READ_NOFLAG, NULL, &err);
	if (!doc && error){
		NSString *msg = [NSString stringWithFormat:@"JSON parse error at pos %zu: %s",
				err.pos, err.msg ? err.msg : "unknown"];
		*error = [NSError errorWithDomain:@"TGJsonErrorDomain" code:-2
								 userInfo:@{NSLocalizedDescriptionKey : msg}];
	}
	return doc;
}

id TGJsonParse(const char *utf8, size_t len, NSError **error) {
	yyjson_doc *doc = TGReadDoc(utf8, len, error);
	if (!doc)
		return nil;

	id result = TGConvertVal(yyjson_doc_get_root(doc));
	yyjson_doc_free(doc);
	return result;
}

/// One syslog line per update type thrown away, so a feature that looks dead
/// says why. Deduplicated without touching Foundation: this runs on the
/// receive thread for every dropped update, which is the allocation the
/// filter exists to avoid in the first place.
///
/// ponytail: 64 names and a linear scan. td_api has about a hundred update
/// types in all, so a full table would only trade memory for nothing; past
/// the ceiling the log goes quiet and the drop still happens.
static void TGLogDroppedUpdate(const char *name, size_t len) {
	enum { kCap = 64, kNameMax = 63 };
	static char seen[kCap][kNameMax + 1];
	static size_t seenCount = 0;

	if (len > kNameMax)
		return;

	for (size_t i = 0; i < seenCount; i++){
		if (std::strncmp(seen[i], name, len) == 0 && seen[i][len] == 0)
			return;
	}
	if (seenCount == kCap)
		return;

	std::memcpy(seen[seenCount], name, len);
	seen[seenCount][len] = 0;
	seenCount++;
	NSLog(@"TGClient: dropped %s - nothing reads it", seen[seenCount - 1]);
}

id TGJsonParseUpdate(const char *utf8, size_t len, NSError **error) {
	yyjson_doc *doc = TGReadDoc(utf8, len, error);
	if (!doc)
		return nil;

	yyjson_val *root = yyjson_doc_get_root(doc);
	yyjson_val *type = yyjson_is_obj(root) ? yyjson_obj_get(root, "@type") : NULL;
	const char *name = yyjson_get_str(type);
	size_t nameLen = name ? yyjson_get_len(type) : 0;

	// An answer carrying @extra is owed to a waiting completion block whatever
	// its type, so only unclaimed updates are candidates for the bin.
	if (TGUpdateTypeIsUpdateName(name, nameLen) &&
		TGUpdateTypeFor(name, nameLen) == TGUpdateUnknown &&
		!yyjson_obj_get(root, "@extra")){
		TGLogDroppedUpdate(name, nameLen);
		yyjson_doc_free(doc);
		return nil;
	}

	id result = TGConvertVal(root);
	yyjson_doc_free(doc);
	return result;
}

id TGJsonParseData(NSData *data, NSError **error) {
	if (!data.length)
		return nil;
	return TGJsonParse((const char *)data.bytes, data.length, error);
}

/// Writes one Foundation object as JSON. Recursion depth is TDLib's own
/// nesting - three or four levels - so this needs no guard.
static void TGWriteValue(TGJsonWriter &w, id obj) {
	if (!obj || [obj isKindOfClass:NSNull.class]){
		w.null_value();
		return;
	}

	if ([obj isKindOfClass:NSString.class]){
		NSString *s = (NSString *)obj;
		const char *utf8 = s.UTF8String;
		w.str(utf8, utf8 ? std::strlen(utf8) : 0);
		return;
	}

	if ([obj isKindOfClass:NSNumber.class]){
		NSNumber *n = (NSNumber *)obj;
		if (CFGetTypeID((__bridge CFTypeRef)n) == CFBooleanGetTypeID()){
			w.boolean(n.boolValue);
			return;
		}
		const char *type = n.objCType;
		if (type[0] == 'f' || type[0] == 'd')
			w.real(n.doubleValue);
		else
			w.num((int64_t)n.longLongValue);
		return;
	}

	if ([obj isKindOfClass:NSDictionary.class]){
		NSDictionary *d = (NSDictionary *)obj;
		w.begin_object();
		for (id k in d){
			if (![k isKindOfClass:NSString.class])
				continue;
			const char *ks = [(NSString *)k UTF8String];
			w.key(ks ?: "");
			TGWriteValue(w, d[k]);
		}
		w.end_object();
		return;
	}

	if ([obj isKindOfClass:NSArray.class]){
		w.begin_array();
		for (id item in (NSArray *)obj)
			TGWriteValue(w, item);
		w.end_array();
		return;
	}

	w.null_value();
}

NSData *TGJsonSerialize(id obj, NSError **error) {
	if (!obj)
		return nil;

	TGJsonWriter w;
	TGWriteValue(w, obj);
	if (!w.size()){
		if (error)
			*error = [NSError errorWithDomain:@"TGJsonErrorDomain" code:-3
									 userInfo:@{NSLocalizedDescriptionKey : @"Serialization failed"}];
		return nil;
	}
	return [NSData dataWithBytes:w.c_str() length:w.size()];
}

NSMutableData *TGJsonSerializeForSend(id obj) {
	if (!obj)
		return nil;

	TGJsonWriter w;
	TGWriteValue(w, obj);
	if (!w.size())
		return nil;

	// The trailing '\0' is part of the length: td_json_client_send takes a C
	// string, and the outbox hands it these bytes as they are.
	return [NSMutableData dataWithBytes:w.c_str() length:w.size() + 1];
}
