//
// TGClientTypes - the plain types the client's API speaks.
//
#import <Foundation/Foundation.h>

typedef NS_ENUM(NSInteger, TGAuthState) {
    TGAuthStateUnknown = 0,
    TGAuthStateWaitPhoneNumber,
    TGAuthStateWaitCode,
    TGAuthStateWaitPassword,
    TGAuthStateWaitRegistration,
    TGAuthStateWaitOtherDeviceConfirmation,
    TGAuthStateReady,
    TGAuthStateLoggingOut,
    TGAuthStateClosed,
    /// Telegram wants an email address on the account before it sends a code.
    TGAuthStateWaitEmailAddress,
    /// A code went to that address (`emailCodeInfo` says where).
    TGAuthStateWaitEmailCode
};

/// Connection state to Telegram as reported by TDLib.
typedef NS_ENUM(NSInteger, TGConnectionState) {
    TGConnectionStateUnknown = 0,
    TGConnectionStateWaitingForNetwork,
    TGConnectionStateConnecting,
    TGConnectionStateUpdating,
    TGConnectionStateReady
};
