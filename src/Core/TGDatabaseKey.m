//
// TGDatabaseKey.m - keychain on a device, defaults on the host test build.
//
#import "TGDatabaseKey.h"
#import "TGBase64.h"

#if TARGET_OS_IPHONE
#import <Security/Security.h>
#endif

static NSString *const TGDatabaseKeyDefaultsName = @"TGDatabaseEncryptionKey";
static NSString *const TGDatabaseKeyService = @"com.legacytg.database";
static NSString *const TGDatabaseKeyAccount = @"tdlib";

@implementation TGDatabaseKey

#if TARGET_OS_IPHONE

/// The one query every keychain call starts from. The service and account
/// are fixed: one database, one key.
+ (NSMutableDictionary *)keychainQuery {
	return [@{
		(__bridge id)kSecClass       : (__bridge id)kSecClassGenericPassword,
		(__bridge id)kSecAttrService : TGDatabaseKeyService,
		(__bridge id)kSecAttrAccount : TGDatabaseKeyAccount,
	} mutableCopy];
}

+ (NSData *)currentKey {
	NSMutableDictionary *query = [self keychainQuery];
	query[(__bridge id)kSecReturnData] = @YES;
	query[(__bridge id)kSecMatchLimit] = (__bridge id)kSecMatchLimitOne;

	CFTypeRef result = NULL;
	OSStatus status = SecItemCopyMatching((__bridge CFDictionaryRef)query, &result);
	if (status == errSecSuccess && result){
		// The caller wants bytes, not the keychain's wrapper. The bridge
		// transfer releases the CF object when ARC drops the NSData.
		return (__bridge_transfer NSData *)result;
	}
	return nil;
}

+ (BOOL)keyStateKnown {
	NSMutableDictionary *query = [self keychainQuery];
	query[(__bridge id)kSecMatchLimit] = (__bridge id)kSecMatchLimitOne;
	OSStatus status = SecItemCopyMatching((__bridge CFDictionaryRef)query, NULL);
	// "No item" is the unencrypted database every install starts with; it is
	// a known state. Anything else is a keychain this app cannot read.
	return status == errSecSuccess || status == errSecItemNotFound;
}

+ (BOOL)storeKey:(NSData *)key error:(NSString **)error {
	NSMutableDictionary *query = [self keychainQuery];
	if (!key.length){
		OSStatus status = SecItemDelete((__bridge CFDictionaryRef)query);
		if (status == errSecSuccess || status == errSecItemNotFound)
			return YES;
		if (error)
			*error = [NSString stringWithFormat:@"The keychain refused to clear the key (%ld).",
					(long)status];
		return NO;
	}

	NSMutableDictionary *attributes = [@{
		(__bridge id)kSecValueData : key,
		(__bridge id)kSecAttrAccessible : (__bridge id)kSecAttrAccessibleAfterFirstUnlock,
	} mutableCopy];

	OSStatus status;
	if ([self currentKey])
		status = SecItemUpdate((__bridge CFDictionaryRef)query,
				(__bridge CFDictionaryRef)attributes);
	else {
		[query addEntriesFromDictionary:attributes];
		status = SecItemAdd((__bridge CFDictionaryRef)query, NULL);
	}
	if (status == errSecSuccess)
		return YES;
	if (error)
		*error = [NSString stringWithFormat:@"The keychain refused to save the key (%ld).",
				(long)status];
	return NO;
}

#else

+ (NSData *)currentKey {
	NSString *encoded = [NSUserDefaults.standardUserDefaults
			stringForKey:TGDatabaseKeyDefaultsName];
	return encoded.length ? TGBase64Decode(encoded) : nil;
}

+ (BOOL)keyStateKnown {
	return YES;
}

+ (BOOL)storeKey:(NSData *)key error:(NSString **)error {
	if (key.length)
		[NSUserDefaults.standardUserDefaults setObject:TGBase64Encode(key)
											   forKey:TGDatabaseKeyDefaultsName];
	else
		[NSUserDefaults.standardUserDefaults removeObjectForKey:TGDatabaseKeyDefaultsName];
	[NSUserDefaults.standardUserDefaults synchronize];
	return YES;
}

#endif

@end
