//
// TGClient+Calls.m - sending a call's log and its debug record.
//
#import "TGClient+Calls.h"
#import "TGClientInternal.h"

static NSString *TGCallRequestError(NSDictionary *result) {
	NSString *message = result[@"message"];
	return [message isKindOfClass:NSString.class] ? message : @"Telegram refused that.";
}

@implementation TGClient (Calls)

- (void)sendCallLog:(NSString *)log
		 forMessage:(int64_t)messageId
			 inChat:(int64_t)chatId
		 completion:(void (^)(BOOL, NSString *))completion {
	if (!chatId || !messageId){
		if (completion) completion(NO, @"Name the call's chat and message.");
		return;
	}
	if (!log.length){
		if (completion) completion(NO, @"The call log is empty.");
		return;
	}

	// TDLib takes inputFileLocal or inputFileGenerated here, so the record
	// has to exist on disk before the request goes out. One name per call
	// keeps two logs sent in the same second apart.
	NSString *name = [NSString stringWithFormat:@"call-%lld-%lld-%lld.log",
			(long long)chatId, (long long)messageId,
			(long long)([[NSDate date] timeIntervalSince1970] * 1000)];
	NSString *path = [NSTemporaryDirectory() stringByAppendingPathComponent:name];
	if (![[log dataUsingEncoding:NSUTF8StringEncoding] writeToFile:path atomically:YES]){
		if (completion) completion(NO, @"The call log could not be written to disk.");
		return;
	}

	void (^done)(BOOL, NSString *) = ^(BOOL ok, NSString *error){
		// The server has read the file by the time it answers; a second
		// copy in the temporary directory is litter.
		[[NSFileManager defaultManager] removeItemAtPath:path error:NULL];
		if (completion) completion(ok, error);
	};

	[self request:@{
		@"@type"    : @"sendCallLog",
		@"call_id"  : @{@"@type" : @"inputCallFromMessage",
						@"chat_id" : @(chatId),
						@"message_id" : @(messageId)},
		@"log_file" : @{@"@type" : @"inputFileLocal", @"path" : path},
	} completion:^(NSDictionary *result){
		BOOL failed = [result[@"@type"] isEqualToString:@"error"];
		done(!failed, failed ? TGCallRequestError(result) : nil);
	}];
}

- (void)sendCallDebugInformation:(NSString *)information
					  forMessage:(int64_t)messageId
						  inChat:(int64_t)chatId
					  completion:(void (^)(BOOL, NSString *))completion {
	if (!chatId || !messageId){
		if (completion) completion(NO, @"Name the call's chat and message.");
		return;
	}
	information = [information stringByTrimmingCharactersInSet:
			[NSCharacterSet whitespaceAndNewlineCharacterSet]];
	if (!information.length){
		if (completion) completion(NO, @"There is no debug information to send.");
		return;
	}
	[self request:@{
		@"@type"               : @"sendCallDebugInformation",
		@"call_id"             : @{@"@type" : @"inputCallFromMessage",
								   @"chat_id" : @(chatId),
								   @"message_id" : @(messageId)},
		@"debug_information"   : information,
	} completion:^(NSDictionary *result){
		BOOL failed = [result[@"@type"] isEqualToString:@"error"];
		if (completion)
			completion(!failed, failed ? TGCallRequestError(result) : nil);
	}];
}

@end

// vim:ft=objc
