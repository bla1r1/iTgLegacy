//
// TGClient+Proxy.h - the client surface for proxies.
//
#import "TGClient+Base.h"

@interface TGClient (Proxy)

/// Every proxy TDLib has been told about. Entries carry "id", "server",
/// "port", "kind" (socks5/http/mtproto/web), "enabled" and "lastUsed".
- (void)proxiesWithCompletion:(void (^)(NSArray *proxies))completion;

/// Adds one and, with `enable`, switches to it at once. The completion gets
/// its id, or 0 when the server or port made no sense.
- (void)addProxyAtServer:(NSString *)server
					port:(NSInteger)port
					kind:(NSString *)kind
				username:(NSString *)username
				password:(NSString *)password
				  secret:(NSString *)secret
				  enable:(BOOL)enable
			  completion:(void (^)(NSInteger proxyId))completion;

/// Adds a proxy out of a t.me/proxy or tg://proxy link, which is how one is
/// nearly always passed around. NO when the link carries no server and port.
- (BOOL)addProxyFromLink:(NSString *)link
			  completion:(void (^)(NSInteger proxyId))completion;

/// Changes one in place, keeping its position and whether it is in use -
/// which removing and re-adding did not.
- (void)editProxy:(NSInteger)proxyId
		   server:(NSString *)server
			 port:(NSInteger)port
			 kind:(NSString *)kind
		 username:(NSString *)username
		 password:(NSString *)password
		   secret:(NSString *)secret
		   enable:(BOOL)enable
	   completion:(void (^)(BOOL ok))completion;

/// Whether a proxy can carry Telegram, which a ping does not say.
- (void)testProxyAtServer:(NSString *)server
					 port:(NSInteger)port
					 kind:(NSString *)kind
				 username:(NSString *)username
				 password:(NSString *)password
				   secret:(NSString *)secret
			   completion:(void (^)(BOOL works))completion;

- (void)enableProxy:(NSInteger)proxyId;

/// Back to a direct connection; there is no id in this one.
- (void)disableProxy;

- (void)removeProxy:(NSInteger)proxyId;

/// How long the handshake takes, in seconds, or a negative number when the
/// proxy does not answer.
- (void)pingProxyAtServer:(NSString *)server
					 port:(NSInteger)port
					 kind:(NSString *)kind
				 username:(NSString *)username
				 password:(NSString *)password
				   secret:(NSString *)secret
			   completion:(void (^)(double seconds))completion;

#pragma mark - web proxy carrier

/// A text message a web proxy page passed to postMessage of the bridge
/// object. TDLib must see every one, in order, before it can run the page.
/// `carrierId` is the id from updateWebProxyCarrierOpened.
- (void)processWebProxyCarrierMessage:(NSInteger)carrierId
								 text:(NSString *)text
						   completion:(void (^)(BOOL ok, NSString *error))completion;

/// The same for a binary message, base64 as TDLib spells bytes.
- (void)processWebProxyCarrierMessage:(NSInteger)carrierId
							  base64:(NSString *)base64
						  completion:(void (^)(BOOL ok, NSString *error))completion;

/// reportWebProxyCarrierError. `kind` is "unsupported", "paused",
/// "terminated" or "refused"; "loadFailed" also takes a sentence.
- (void)reportWebProxyCarrierError:(NSInteger)carrierId
							  kind:(NSString *)kind
						   message:(NSString *)message
						completion:(void (^)(BOOL ok, NSString *error))completion;

@end
