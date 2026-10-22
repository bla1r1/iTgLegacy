//
// TGCallStun - STUN binding requests and responses for VoIP ICE checks (RFC 5389 / RFC 8445).
//
#ifndef TG_CALL_STUN_H
#define TG_CALL_STUN_H

#import <Foundation/Foundation.h>

@interface TGCallStun : NSObject

/// A binding request for the peer. `username` is "theirUfrag:ourUfrag" and
/// `password` is theirs - the side being asked signs nothing, the asker does.
+ (NSData *)bindingRequestWithUsername:(NSString *)username
                              password:(NSString *)password
                             tieBreaker:(uint64_t)tieBreaker
                            useCandidate:(BOOL)useCandidate;

/// A success response to `request`, signed with our own password.
+ (NSData *)bindingResponseTo:(NSData *)request
                     password:(NSString *)password
                   fromAddress:(NSData *)address;   ///< sockaddr_in of the sender

/// 0x0001 request, 0x0101 success, 0x0111 error, or -1 when not STUN.
+ (int)messageTypeOf:(NSData *)packet;

/// For holding two packets side by side in the log.
+ (NSString *)hexOf:(NSData *)data;

@end

#endif
