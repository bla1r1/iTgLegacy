//
// TGJson.m - High-performance JSON parser & serializer powered by yyjson.
//
#import "TGJson.h"
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

static yyjson_mut_val *TGBuildMutVal(yyjson_mut_doc *doc, id obj) {
	if (!obj || [obj isKindOfClass:NSNull.class])
		return yyjson_mut_null(doc);

	if ([obj isKindOfClass:NSString.class]){
		NSString *s = (NSString *)obj;
		return yyjson_mut_strn(doc, s.UTF8String, [s lengthOfBytesUsingEncoding:NSUTF8StringEncoding]);
	}

	if ([obj isKindOfClass:NSNumber.class]){
		NSNumber *n = (NSNumber *)obj;
		if (CFGetTypeID((__bridge CFTypeRef)n) == CFBooleanGetTypeID()){
			return yyjson_mut_bool(doc, n.boolValue);
		}
		const char *type = n.objCType;
		if (type[0] == 'f' || type[0] == 'd'){
			return yyjson_mut_real(doc, n.doubleValue);
		}
		return yyjson_mut_sint(doc, n.longLongValue);
	}

	if ([obj isKindOfClass:NSDictionary.class]){
		NSDictionary *d = (NSDictionary *)obj;
		yyjson_mut_val *m = yyjson_mut_obj(doc);
		for (id k in d){
			if ([k isKindOfClass:NSString.class]){
				NSString *ks = (NSString *)k;
				yyjson_mut_val *kVal = yyjson_mut_strn(doc, ks.UTF8String,
						[ks lengthOfBytesUsingEncoding:NSUTF8StringEncoding]);
				yyjson_mut_val *vVal = TGBuildMutVal(doc, d[k]);
				yyjson_mut_obj_add(m, kVal, vVal);
			}
		}
		return m;
	}

	if ([obj isKindOfClass:NSArray.class]){
		NSArray *a = (NSArray *)obj;
		yyjson_mut_val *arr = yyjson_mut_arr(doc);
		for (id item in a){
			yyjson_mut_arr_append(arr, TGBuildMutVal(doc, item));
		}
		return arr;
	}

	return yyjson_mut_null(doc);
}

NSData *TGJsonSerialize(id obj, NSError **error) {
	if (!obj)
		return nil;

	yyjson_mut_doc *doc = yyjson_mut_doc_new(NULL);
	yyjson_mut_val *root = TGBuildMutVal(doc, obj);
	yyjson_mut_doc_set_root(doc, root);

	size_t len = 0;
	char *json = yyjson_mut_write(doc, 0, &len);
	yyjson_mut_doc_free(doc);

	if (!json){
		if (error)
			*error = [NSError errorWithDomain:@"TGJsonErrorDomain" code:-3
									 userInfo:@{NSLocalizedDescriptionKey : @"Serialization failed"}];
		return nil;
	}

	NSData *data = [NSData dataWithBytes:json length:len];
	free(json);
	return data;
}

NSMutableData *TGJsonSerializeForSend(id obj) {
	if (!obj)
		return nil;

	yyjson_mut_doc *doc = yyjson_mut_doc_new(NULL);
	yyjson_mut_val *root = TGBuildMutVal(doc, obj);
	yyjson_mut_doc_set_root(doc, root);

	size_t len = 0;
	char *json = yyjson_mut_write(doc, 0, &len);
	yyjson_mut_doc_free(doc);

	if (!json)
		return nil;

	// Includes the trailing '\0' byte in length for direct td_json_client_send compatibility
	NSMutableData *data = [NSMutableData dataWithCapacity:len + 1];
	[data appendBytes:json length:len];
	[data appendBytes:"\0" length:1];
	free(json);
	return data;
}
