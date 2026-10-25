#import <Foundation/Foundation.h>

/// The subtitle every line about a user carries. One phrasing core, so the
/// same set of words reaches the chat header, the profile status and any
/// other user row (B4: the formatter here used to know only "today"; anyone
/// seen yesterday or earlier rendered as "last seen a long time ago", and
/// the network state never reached the line at all).
///
/// `status` is the TDLib `user`'s `status` dictionary as it arrives; nil and
/// quiet on a shape it does not know, leaving the caller whatever it had.
/// Returns nil when the receiver's text should keep whatever it has.
FOUNDATION_EXPORT NSString *TGStatusTextFromTDStatus(NSDictionary *status);

/// The phrase to show over a line while the connection is not `ready`, or
/// nil when they are - the list of network states matches what TGClient
/// maps from updateConnectionState.
FOUNDATION_EXPORT NSString *TGNetworkSubtitleForState(NSInteger state,
													  NSString *text);
