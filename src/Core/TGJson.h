//
// TGJson.h - High-performance JSON parser & serializer powered by yyjson.
//
#import <Foundation/Foundation.h>

#ifdef __cplusplus
extern "C" {
#endif

/// Parses a null-terminated or length-bounded UTF-8 C string into NSDictionary / NSArray.
/// Zero-copy string access during parsing; avoids allocating intermediate NSData buffers.
id TGJsonParse(const char *utf8, size_t len, NSError **error);

/// Parses an NSData object containing UTF-8 JSON.
id TGJsonParseData(NSData *data, NSError **error);

/// Serializes NSDictionary / NSArray into a UTF-8 JSON NSData object.
NSData *TGJsonSerialize(id obj, NSError **error);

/// Serializes NSDictionary / NSArray into a null-terminated UTF-8 NSMutableData (ready for td_send).
NSMutableData *TGJsonSerializeForSend(id obj);

#ifdef __cplusplus
}
#endif
