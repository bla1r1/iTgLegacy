//
// TGClient+Diagnostics.m - TDLib's own state, configuration and counters.
//
// A screen here is looking at the machinery rather than at Telegram's
// content, so the failure mode is different: every request can be refused
// for a reason the server spells out, and a silent boolean would hide it.
// Each method therefore carries the server's sentence to its completion.
//
#import "TGClient+Diagnostics.h"
#import "TGClientInternal.h"
#import "TGDatabaseKey.h"
#import "TGBase64.h"

@interface TGClient (TGDiagnosticsPrivate)
- (void)tg_graphForChat:(int64_t)chatId
				  token:(NSString *)token
					  x:(NSInteger)x
				attempt:(NSInteger)attempt
			 completion:(void (^)(NSDictionary *graph, NSString *error))completion;
@end

static NSString *TGDiagnosticsError(NSDictionary *result) {
	NSString *message = result[@"message"];
	return [message isKindOfClass:NSString.class] ? message : @"Telegram refused that.";
}

static NSDictionary *TGNetworkTypeObject(NSString *name) {
	if ([name isEqualToString:@"none"])
		return @{@"@type" : @"networkTypeNone"};
	if ([name isEqualToString:@"mobile"])
		return @{@"@type" : @"networkTypeMobile"};
	if ([name isEqualToString:@"roaming"] || [name isEqualToString:@"mobileRoaming"])
		return @{@"@type" : @"networkTypeMobileRoaming"};
	if ([name isEqualToString:@"wifi"] || [name isEqualToString:@"wiFi"])
		return @{@"@type" : @"networkTypeWiFi"};
	if ([name isEqualToString:@"other"])
		return @{@"@type" : @"networkTypeOther"};
	return nil;
}

/// A scalar JsonValue as a string, or nil for an object or array. Used by the
/// update summary, where one option's value is worth a line and a nested tree
/// is not.
static NSString *TGJsonValueSimple(id value) {
	if (![value isKindOfClass:NSDictionary.class])
		return nil;
	NSString *type = value[@"@type"];
	if ([type isEqualToString:@"jsonValueBoolean"] ||
		[type isEqualToString:@"jsonValueNumber"] ||
		[type isEqualToString:@"jsonValueString"]){
		id scalar = value[@"value"];
		if ([scalar isKindOfClass:NSString.class])
			return scalar;
		if ([scalar isKindOfClass:NSNumber.class])
			return [scalar stringValue];
	}
	return nil;
}

/// Peels the jsonValue wrappers off getApplicationConfig. Null becomes NSNull
/// because a dictionary cannot carry nil, and a caller showing the tree wants
/// to see that a field was there and empty.
static id TGFoundationFromJsonValue(id value) {
	if (![value isKindOfClass:NSDictionary.class])
		return [NSNull null];
	NSString *type = value[@"@type"];
	if ([type isEqualToString:@"jsonValueNull"])
		return [NSNull null];
	if ([type isEqualToString:@"jsonValueBoolean"] ||
		[type isEqualToString:@"jsonValueNumber"] ||
		[type isEqualToString:@"jsonValueString"])
		return value[@"value"] ?: [NSNull null];
	if ([type isEqualToString:@"jsonValueArray"]){
		NSArray *values = value[@"values"];
		if (![values isKindOfClass:NSArray.class])
			return @[];
		NSMutableArray *out = [NSMutableArray arrayWithCapacity:values.count];
		for (id item in values)
			[out addObject:TGFoundationFromJsonValue(item)];
		return out;
	}
	if ([type isEqualToString:@"jsonValueObject"]){
		NSArray *members = value[@"members"];
		if (![members isKindOfClass:NSArray.class])
			return @{};
		NSMutableDictionary *out = [NSMutableDictionary dictionaryWithCapacity:members.count];
		for (NSDictionary *member in members){
			NSString *name = member[@"name"];
			if (![name isKindOfClass:NSString.class] || !name.length)
				continue;
			out[name] = TGFoundationFromJsonValue(member[@"value"]);
		}
		return out;
	}
	return value;
}

static NSString *TGUpdateSummary(NSDictionary *update) {
	NSString *type = update[@"@type"];
	if (![type isKindOfClass:NSString.class])
		return @"";

	if ([type hasPrefix:@"authorizationState"])
		return [type substringFromIndex:@"authorizationState".length];
	if ([type hasPrefix:@"connectionState"])
		return [type substringFromIndex:@"connectionState".length];
	if ([type isEqualToString:@"updateOption"]){
		NSString *name = update[@"name"];
		NSString *value = TGJsonValueSimple(update[@"value"]);
		if (name.length && value.length)
			return [NSString stringWithFormat:@"%@ = %@", name, value];
		return name ?: @"";
	}
	if ([type isEqualToString:@"updateDefaultBackground"]){
		NSDictionary *background = update[@"background"];
		NSString *name = background[@"name"];
		if (name.length)
			return name;
		return background ? @"Changed" : @"Removed";
	}

	// Every other state update still has a few integers and words worth
	// seeing in a support session. The id and the type are already known.
	NSMutableArray *parts = [NSMutableArray array];
	NSArray *keys = [[update allKeys] sortedArrayUsingSelector:@selector(compare:)];
	for (NSString *key in keys){
		if ([key isEqualToString:@"@type"] || [key isEqualToString:@"@extra"] ||
			[key isEqualToString:@"id"])
			continue;
		id value = update[key];
		if ([value isKindOfClass:NSString.class] ||
			[value isKindOfClass:NSNumber.class])
			[parts addObject:[NSString stringWithFormat:@"%@ = %@", key, value]];
		if (parts.count == 3)
			break;
	}
	return [parts componentsJoinedByString:@", "];
}

/// A printable list for statisticalGraphData. TDLib sends public statistics
/// as JSON with a "points" array, and older endpoints as a named tree; both
/// end up as rows the list screen can draw without a chart engine.
static NSArray *TGStatisticalGraphLines(id json, NSString *raw) {
	NSMutableArray *lines = [NSMutableArray array];
	if ([json isKindOfClass:NSDictionary.class]){
		NSArray *points = json[@"points"];
		if ([points isKindOfClass:NSArray.class] && points.count){
			double maxY = 0;
			for (NSDictionary *point in points){
				NSNumber *y = point[@"y"];
				if ([y isKindOfClass:NSNumber.class] && fabs(y.doubleValue) > maxY)
					maxY = fabs(y.doubleValue);
			}
			[lines addObject:[NSString stringWithFormat:@"%lu points, peak %g",
					(unsigned long)points.count, maxY]];
			NSUInteger shown = MIN(points.count, (NSUInteger)60);
			for (NSUInteger i = 0; i < shown; i++){
				NSDictionary *point = points[i];
				NSNumber *x = point[@"x"];
				NSNumber *y = point[@"y"];
				if (![x isKindOfClass:NSNumber.class] ||
					![y isKindOfClass:NSNumber.class])
					continue;
				// Twenty cells is what fits beside a date on a 3.5-inch
				// screen; the number after it is the value itself.
				NSUInteger bars = maxY > 0
						? (NSUInteger)lround((fabs(y.doubleValue) / maxY) * 20.0) : 0;
				NSMutableString *bar = [NSMutableString string];
				for (NSUInteger b = 0; b < bars; b++)
					[bar appendString:@"#"];
				[lines addObject:[NSString stringWithFormat:@"%lld %@ %g",
						x.longLongValue, bar, y.doubleValue]];
			}
			if (points.count > shown)
				[lines addObject:[NSString stringWithFormat:@"... and %lu more",
						(unsigned long)(points.count - shown)]];
			return lines;
		}

		NSArray *keys = [[json allKeys] sortedArrayUsingSelector:@selector(compare:)];
		for (NSString *key in keys){
			id value = json[key];
			if ([value isKindOfClass:NSString.class] ||
				[value isKindOfClass:NSNumber.class])
				[lines addObject:[NSString stringWithFormat:@"%@: %@", key, value]];
			else if ([value isKindOfClass:NSArray.class])
				[lines addObject:[NSString stringWithFormat:@"%@: %lu entries", key,
						(unsigned long)[value count]]];
			else if ([value isKindOfClass:NSDictionary.class])
				[lines addObject:[NSString stringWithFormat:@"%@: an object", key]];
			if (lines.count == 30)
				break;
		}
	} else if ([json isKindOfClass:NSArray.class]){
		[lines addObject:[NSString stringWithFormat:@"%lu values", (unsigned long)[json count]]];
		NSUInteger shown = MIN([json count], (NSUInteger)30);
		for (NSUInteger i = 0; i < shown; i++)
			[lines addObject:[NSString stringWithFormat:@"%@", json[i]]];
	}

	if (!lines.count){
		NSString *trimmed = [raw stringByTrimmingCharactersInSet:
				[NSCharacterSet whitespaceAndNewlineCharacterSet]];
		[lines addObject:trimmed.length ? trimmed : @"Telegram sent an empty graph."];
	}
	return lines;
}

@implementation TGClient (Diagnostics)

#pragma mark - state and configuration

- (void)currentStateWithCompletion:(void (^)(NSArray *updates,
											 NSString *error))completion {
	[self request:@{@"@type" : @"getCurrentState"} completion:^(NSDictionary *result){
		if ([result[@"@type"] isEqualToString:@"error"]){
			if (completion)
				completion(@[], TGDiagnosticsError(result));
			return;
		}
		NSArray *records = result[@"updates"];
		if (![records isKindOfClass:NSArray.class])
			records = @[];
		NSMutableArray *rows = [NSMutableArray arrayWithCapacity:records.count];
		for (NSDictionary *update in records){
			if (![update isKindOfClass:NSDictionary.class])
				continue;
			NSString *type = update[@"@type"];
			if (![type isKindOfClass:NSString.class] || !type.length)
				continue;
			[rows addObject:@{
				@"type"    : type,
				@"summary" : TGUpdateSummary(update),
			}];
		}
		if (completion)
			completion(rows, nil);
	}];
}

- (void)applicationConfigWithCompletion:(void (^)(NSDictionary *config,
												  NSString *error))completion {
	[self request:@{@"@type" : @"getApplicationConfig"} completion:^(NSDictionary *result){
		if ([result[@"@type"] isEqualToString:@"error"]){
			if (completion)
				completion(nil, TGDiagnosticsError(result));
			return;
		}
		NSString *type = result[@"@type"];
		if (![type isKindOfClass:NSString.class] || ![type hasPrefix:@"jsonValue"]){
			if (completion)
				completion(nil, @"Telegram answered with something that is not configuration.");
			return;
		}
		id converted = TGFoundationFromJsonValue(result);
		NSDictionary *config = nil;
		if ([converted isKindOfClass:NSDictionary.class])
			config = converted;
		else if ([converted isKindOfClass:NSNull.class])
			config = @{};
		else
			config = @{@"value" : converted};
		if (completion)
			completion(config, nil);
	}];
}

- (void)databaseStatisticsWithCompletion:(void (^)(NSString *statistics,
												   NSString *error))completion {
	[self request:@{@"@type" : @"getDatabaseStatistics"}
	   completion:^(NSDictionary *result){
		if ([result[@"@type"] isEqualToString:@"error"]){
			if (completion)
				completion(nil, TGDiagnosticsError(result));
			return;
		}
		NSString *statistics = result[@"statistics"];
		if (![statistics isKindOfClass:NSString.class]){
			if (completion)
				completion(nil, @"Telegram answered without database statistics.");
			return;
		}
		if (completion)
			completion(statistics, nil);
	}];
}

#pragma mark - network

- (void)setNetworkType:(NSString *)networkType
			completion:(void (^)(BOOL ok, NSString *error))completion {
	NSDictionary *type = TGNetworkTypeObject(networkType);
	if (!type){
		if (completion)
			completion(NO, @"Unknown network type.");
		return;
	}
	[self request:@{@"@type" : @"setNetworkType", @"type" : type}
	   completion:^(NSDictionary *result){
		BOOL failed = [result[@"@type"] isEqualToString:@"error"];
		if (completion)
			completion(!failed, failed ? TGDiagnosticsError(result) : nil);
	}];
}

- (void)addNetworkStatisticsForNetworkType:(NSString *)networkType
								sentBytes:(long long)sent
							receivedBytes:(long long)received
								 duration:(double)duration
							   completion:(void (^)(BOOL ok,
													NSString *error))completion {
	NSDictionary *type = TGNetworkTypeObject(networkType);
	if (!type){
		if (completion)
			completion(NO, @"Unknown network type.");
		return;
	}
	NSDictionary *entry = @{
		@"@type"         : @"networkStatisticsEntryCall",
		@"network_type"  : type,
		@"sent_bytes"    : @(MAX((long long)0, sent)),
		@"received_bytes": @(MAX((long long)0, received)),
		@"duration"      : @(MAX(0.0, duration)),
	};
	[self request:@{@"@type" : @"addNetworkStatistics", @"entry" : entry}
	   completion:^(NSDictionary *result){
		BOOL failed = [result[@"@type"] isEqualToString:@"error"];
		if (completion)
			completion(!failed, failed ? TGDiagnosticsError(result) : nil);
	}];
}

#pragma mark - charts

- (void)statisticalGraphForChat:(int64_t)chatId
						  token:(NSString *)token
							  x:(NSInteger)x
					 completion:(void (^)(NSDictionary *graph,
										  NSString *error))completion {
	if (!token.length){
		if (completion)
			completion(nil, @"No statistics token was given.");
		return;
	}
	[self tg_graphForChat:chatId token:token x:x attempt:0 completion:completion];
}

- (void)tg_graphForChat:(int64_t)chatId
				  token:(NSString *)token
					  x:(NSInteger)x
				attempt:(NSInteger)attempt
			 completion:(void (^)(NSDictionary *graph,
								  NSString *error))completion {
	[self request:@{@"@type" : @"getStatisticalGraph",
					@"chat_id" : @(chatId),
					@"token" : token,
					@"x" : @(x)}
	   completion:^(NSDictionary *result){
		NSString *type = result[@"@type"];
		if ([type isEqualToString:@"statisticalGraphData"]){
			NSString *raw = result[@"json_data"];
			if (![raw isKindOfClass:NSString.class])
				raw = @"";
			id json = nil;
			NSData *data = [raw dataUsingEncoding:NSUTF8StringEncoding];
			if (data.length){
				json = [NSJSONSerialization JSONObjectWithData:data options:0 error:nil];
			}
			NSDictionary *graph = @{
				@"kind"      : @"data",
				@"json"      : json ?: [NSNull null],
				@"raw"       : raw,
				@"zoomToken" : result[@"zoom_token"] ?: @"",
				@"lines"     : TGStatisticalGraphLines(json, raw),
			};
			if (completion)
				completion(graph, nil);
			return;
		}
		if ([type isEqualToString:@"statisticalGraphAsync"]){
			NSString *next = result[@"token"];
			// TDLib answers a heavy graph with a token and prepares it in the
			// background. Three follow-ups covers the longest wait this screen
			// can hold; after that the token is shown and the page can retry.
			if (next.length && attempt < 3){
				[self tg_graphForChat:chatId token:next x:0 attempt:attempt + 1
						  completion:completion];
				return;
			}
			NSDictionary *graph = @{
				@"kind"  : @"async",
				@"token" : next ?: token,
				@"lines" : @[@"Telegram is still preparing this graph.",
							 [NSString stringWithFormat:@"Token: %@", next ?: token]],
			};
			if (completion)
				completion(graph, nil);
			return;
		}
		if ([type isEqualToString:@"statisticalGraphError"]){
			NSString *message = result[@"error_message"];
			if (completion)
				completion(nil, [message isKindOfClass:NSString.class]
						? message : @"Telegram refused that graph.");
			return;
		}
		if ([type isEqualToString:@"error"]){
			if (completion)
				completion(nil, TGDiagnosticsError(result));
			return;
		}
		if (completion)
			completion(nil, @"Telegram answered with something that is not a graph.");
	}];
}

#pragma mark - raw request and database key

- (void)sendCustomRequestMethod:(NSString *)method
					 parameters:(NSString *)parameters
					 completion:(void (^)(NSString *result,
										  NSString *error))completion {
	if (!method.length){
		if (completion)
			completion(nil, @"No method name was given.");
		return;
	}
	[self request:@{@"@type" : @"sendCustomRequest",
					@"method" : method,
					@"parameters" : parameters.length ? parameters : @"{}"}
	   completion:^(NSDictionary *result){
		if ([result[@"@type"] isEqualToString:@"error"]){
			if (completion)
				completion(nil, TGDiagnosticsError(result));
			return;
		}
		NSString *answer = result[@"result"];
		if (![answer isKindOfClass:NSString.class]){
			if (completion)
				completion(nil, @"Telegram answered without a result string.");
			return;
		}
		if (completion)
			completion(answer, nil);
	}];
}

- (BOOL)databaseEncryptionKeyIsKnown {
	return [TGDatabaseKey keyStateKnown];
}

- (BOOL)databaseEncryptionKeyIsSet {
	return [TGDatabaseKey currentKey].length > 0;
}

- (void)setDatabaseEncryptionKey:(NSData *)newKey
					  completion:(void (^)(BOOL ok, NSString *error))completion {
	if (!newKey.length){
		if (completion)
			completion(NO, @"An empty key cannot be set.");
		return;
	}
	if (![self databaseEncryptionKeyIsKnown]){
		if (completion)
			completion(NO, @"The current database key could not be read, so "
						   @"changing it could lock the database.");
		return;
	}

	NSData *previous = [TGDatabaseKey currentKey];
	NSString *storeError = nil;
	// Save first: a key Telegram accepts but this app cannot remember would
	// leave the next launch unable to open the database it just encrypted.
	if (![TGDatabaseKey storeKey:newKey error:&storeError]){
		if (completion)
			completion(NO, storeError ?: @"The new key could not be saved.");
		return;
	}

	[self request:@{@"@type" : @"setDatabaseEncryptionKey",
					@"new_encryption_key" : TGBase64Encode(newKey)}
	   completion:^(NSDictionary *result){
		if (![result[@"@type"] isEqualToString:@"error"]){
			if (completion)
				completion(YES, nil);
			return;
		}
		NSString *restoreError = nil;
		[TGDatabaseKey storeKey:previous error:&restoreError];
		NSString *message = TGDiagnosticsError(result);
		if (restoreError)
			message = [message stringByAppendingFormat:
					@" The old key could not be restored: %@", restoreError];
		if (completion)
			completion(NO, message);
	}];
}

@end
