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

id TGJsonParse(const char *utf8, size_t len, NSError **error) {
	if (!utf8 || len == 0){
		if (error)
			*error = [NSError errorWithDomain:@"TGJsonErrorDomain" code:-1
									 userInfo:@{NSLocalizedDescriptionKey : @"Empty JSON payload"}];
		return nil;
	}

	yyjson_read_err err;
	yyjson_doc *doc = yyjson_read_opts((char *)utf8, len, YYJSON_READ_NOFLAG, NULL, &err);
	if (!doc){
		if (error){
			NSString *msg = [NSString stringWithFormat:@"JSON parse error at pos %zu: %s",
					err.pos, err.msg ? err.msg : "unknown"];
			*error = [NSError errorWithDomain:@"TGJsonErrorDomain" code:-2
									 userInfo:@{NSLocalizedDescriptionKey : msg}];
		}
		return nil;
	}

	yyjson_val *root = yyjson_doc_get_root(doc);
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
