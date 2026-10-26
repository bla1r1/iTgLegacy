//
// TGClient+Proxy.m - the proxy list, which matters most where Telegram is
// blocked and this is the only client old enough to run on the phone.
//
// TDLib keeps the list itself and persists it in the database, so there is
// nothing to store here: this is the list, the four kinds of proxy it
// accepts, and which one is on.
//
#import "TGClientInternal.h"

/// A proxy's type as TDLib wants it, from the kind name this app uses and
/// the three strings a proxy can carry. Unknown kinds become SOCKS5, which
/// is what a pasted server and port usually is.
static NSDictionary *TGProxyType(NSString *kind, NSString *username,
								 NSString *password, NSString *secret) {
	if ([kind isEqualToString:@"mtproto"])
		return @{@"@type" : @"proxyTypeMtproto", @"secret" : secret ?: @""};
	if ([kind isEqualToString:@"http"])
		return @{@"@type"     : @"proxyTypeHttp",
				 @"username"  : username ?: @"",
				 @"password"  : password ?: @"",
				 // An HTTP proxy that only speaks CONNECT cannot carry
				 // Telegram's own traffic, and TDLib needs telling which.
				 @"http_only" : @NO};
	return @{@"@type"    : @"proxyTypeSocks5",
			 @"username" : username ?: @"",
			 @"password" : password ?: @""};
}

/// The kind name back out of a type, for a list that has to say what each
/// row is.
static NSString *TGProxyKind(NSDictionary *type) {
	NSString *name = type[@"@type"] ?: @"";
	if ([name isEqualToString:@"proxyTypeMtproto"]) return @"mtproto";
	if ([name isEqualToString:@"proxyTypeHttp"])    return @"http";
	if ([name isEqualToString:@"proxyTypeWeb"])     return @"web";
	return @"socks5";
}

static NSDictionary *TGProxyObject(NSString *server, NSInteger port, NSString *kind,
								   NSString *username, NSString *password,
								   NSString *secret) {
	return @{@"@type"  : @"proxy",
			 @"server" : server ?: @"",
			 @"port"   : @(port),
			 @"type"   : TGProxyType(kind, username, password, secret)};
}

@implementation TGClient (Proxy)

- (void)proxiesWithCompletion:(void (^)(NSArray *proxies))completion {
	[self request:@{@"@type" : @"getProxies"} completion:^(NSDictionary *result){
		NSMutableArray *out = [NSMutableArray array];
		for (NSDictionary *added in result[@"proxies"]){
			if (![added isKindOfClass:NSDictionary.class])
				continue;
			NSDictionary *proxy = added[@"proxy"];
			[out addObject:@{
				@"id"        : added[@"id"] ?: @(0),
				@"server"    : proxy[@"server"] ?: @"",
				@"port"      : proxy[@"port"] ?: @(0),
				@"kind"      : TGProxyKind(proxy[@"type"]),
				@"enabled"   : added[@"is_enabled"] ?: @NO,
				@"lastUsed"  : added[@"last_used_date"] ?: @(0),
			}];
		}
		if (completion)
			completion(out);
	}];
}

- (void)addProxyAtServer:(NSString *)server
					port:(NSInteger)port
					kind:(NSString *)kind
				username:(NSString *)username
				password:(NSString *)password
				  secret:(NSString *)secret
				  enable:(BOOL)enable
			  completion:(void (^)(NSInteger proxyId))completion {
	if (!server.length || port <= 0 || port > 65535){
		if (completion) completion(0);
		return;
	}
	[self request:@{
		@"@type"   : @"addProxy",
		@"proxy"   : TGProxyObject(server, port, kind, username, password, secret),
		@"enable"  : @(enable),
		@"comment" : @"",
	} completion:^(NSDictionary *result){
		if (completion)
			completion([result[@"id"] integerValue]);
	}];
}

/// Changes a proxy in place rather than removing and re-adding it, which is
/// what the page used to do - and which lost its position in the list and
/// whether it was the one in use.
- (void)editProxy:(NSInteger)proxyId
		   server:(NSString *)server
			 port:(NSInteger)port
			 kind:(NSString *)kind
		 username:(NSString *)username
		 password:(NSString *)password
		   secret:(NSString *)secret
		   enable:(BOOL)enable
	   completion:(void (^)(BOOL ok))completion {
	if (!proxyId || !server.length || port <= 0 || port > 65535){
		if (completion) completion(NO);
		return;
	}
	[self request:@{
		@"@type"    : @"editProxy",
		@"proxy_id" : @(proxyId),
		@"proxy"    : TGProxyObject(server, port, kind, username, password, secret),
		@"enable"   : @(enable),
		@"comment"  : @"",
	} completion:^(NSDictionary *result){
		if (completion)
			completion([result[@"@type"] isEqualToString:@"addedProxy"]);
	}];
}

/// Whether a proxy can actually carry Telegram, which a ping does not say: a
/// handshake can answer while the proxy refuses to pass the data centre.
- (void)testProxyAtServer:(NSString *)server
					 port:(NSInteger)port
					 kind:(NSString *)kind
				 username:(NSString *)username
				 password:(NSString *)password
				   secret:(NSString *)secret
			   completion:(void (^)(BOOL works))completion {
	[self request:@{
		@"@type"   : @"testProxy",
		@"proxy"   : TGProxyObject(server, port, kind, username, password, secret),
		// Any data centre will do for a reachability answer; 1 always exists.
		@"dc_id"   : @(1),
		@"timeout" : @(10.0),
	} completion:^(NSDictionary *result){
		if (completion)
			completion([result[@"@type"] isEqualToString:@"ok"]);
	}];
}

- (void)enableProxy:(NSInteger)proxyId {
	[self send:@{@"@type" : @"enableProxy", @"proxy_id" : @(proxyId)}];
}

/// Off means direct, and there is no proxy id in it: TDLib disables whichever
/// one is on.
- (void)disableProxy {
	[self send:@{@"@type" : @"disableProxy"}];
}

- (void)removeProxy:(NSInteger)proxyId {
	[self send:@{@"@type" : @"removeProxy", @"proxy_id" : @(proxyId)}];
}

/// How long the handshake took, in seconds, or a negative number when it did
/// not answer. The one number worth showing beside a proxy row.
- (void)pingProxyAtServer:(NSString *)server
					 port:(NSInteger)port
					 kind:(NSString *)kind
				 username:(NSString *)username
				 password:(NSString *)password
				   secret:(NSString *)secret
			   completion:(void (^)(double seconds))completion {
	[self request:@{
		@"@type" : @"pingProxy",
		@"proxy" : TGProxyObject(server, port, kind, username, password, secret),
	} completion:^(NSDictionary *result){
		if (!completion)
			return;
		NSNumber *seconds = result[@"seconds"];
		completion([seconds isKindOfClass:NSNumber.class] ? seconds.doubleValue : -1.0);
	}];
}

/// A t.me/proxy or tg://proxy link, which is how a proxy is nearly always
/// passed around. Returns NO when the link carries no server and port.
- (BOOL)addProxyFromLink:(NSString *)link
			  completion:(void (^)(NSInteger proxyId))completion {
	NSURL *url = [NSURL URLWithString:[link stringByTrimmingCharactersInSet:
			[NSCharacterSet whitespaceAndNewlineCharacterSet]] ?: @""];
	NSString *query = url.query;
	if (!query.length){
		if (completion) completion(0);
		return NO;
	}

	NSMutableDictionary *fields = [NSMutableDictionary dictionary];
	for (NSString *pair in [query componentsSeparatedByString:@"&"]){
		NSRange eq = [pair rangeOfString:@"="];
		if (eq.location == NSNotFound)
			continue;
		NSString *key = [pair substringToIndex:eq.location];
		NSString *value = [[pair substringFromIndex:eq.location + 1]
				stringByReplacingPercentEscapesUsingEncoding:NSUTF8StringEncoding];
		if (key.length && value)
			fields[key] = value;
	}

	NSString *server = fields[@"server"];
	NSInteger port = [fields[@"port"] integerValue];
	if (!server.length || port <= 0){
		if (completion) completion(0);
		return NO;
	}

	// A secret means MTProto; a user name means SOCKS5. Their own links carry
	// exactly one of the two.
	NSString *secret = fields[@"secret"];
	NSString *kind = secret.length ? @"mtproto" : @"socks5";
	[self addProxyAtServer:server port:port kind:kind
				  username:fields[@"user"] password:fields[@"pass"]
					secret:secret enable:YES completion:completion];
	return YES;
}

@end

// vim:ft=objc
