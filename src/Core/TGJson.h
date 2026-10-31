//
// TGJson.h - High-performance JSON parser & serializer powered by yyjson.
//
#import <Foundation/Foundation.h>
#include "TGUpdateType.h"

#ifdef __cplusplus
extern "C" {
#endif

/// Parses a null-terminated or length-bounded UTF-8 C string into NSDictionary / NSArray.
/// Zero-copy string access during parsing; avoids allocating intermediate NSData buffers.
id TGJsonParse(const char *utf8, size_t len, NSError **error);

/// Parses one object straight off td_json_client_receive, and drops the
/// updates nothing in the client reads before any Foundation object is built
/// for them - updateActiveEmojiReactions alone is a couple of thousand
/// strings the app has no use for. nil both for a dropped update and for
/// malformed input; only the latter sets `error`.
id TGJsonParseUpdate(const char *utf8, size_t len, NSError **error);

/// Parses an NSData object containing UTF-8 JSON.
id TGJsonParseData(NSData *data, NSError **error);

/// Serializes NSDictionary / NSArray into a UTF-8 JSON NSData object.
NSData *TGJsonSerialize(id obj, NSError **error);

/// Serializes NSDictionary / NSArray into a null-terminated UTF-8 NSMutableData (ready for td_send).
NSMutableData *TGJsonSerializeForSend(id obj);

#ifdef __cplusplus
}
#endif
