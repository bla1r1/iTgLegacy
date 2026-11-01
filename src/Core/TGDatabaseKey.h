//
// TGDatabaseKey.h - where the TDLib database key survives a relaunch.
//
// setTdlibParameters takes the key as bytes, so the key has to be readable
// before the client starts. On a device it belongs in the keychain, not in
// NSUserDefaults: a key in the app container is a key the app container
// leaks. The host test build has no keychain entitlement and uses defaults
// instead, because what the tests pin down is the wire shape and the
// "stored before sent, restored on refusal" order, not the storage itself.
//
#import <Foundation/Foundation.h>

@interface TGDatabaseKey : NSObject

/// The key this app last saved. An empty answer means the database is
/// unencrypted, which is how every install starts.
+ (NSData *)currentKey;

/// Whether reading the key's storage worked at all. A keychain that answers
/// an error other than "not found" means the current key is unknown; changing
/// it then could lock the database for good, so the caller refuses.
+ (BOOL)keyStateKnown;

/// Saves a new key. Nil or empty removes the key. Returns NO and fills
/// `error` when the storage refused; the caller must not send a key it could
/// not save.
+ (BOOL)storeKey:(NSData *)key error:(NSString **)error;

@end
