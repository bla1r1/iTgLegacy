// TGClientFileToolsTests.m - file records, names, reads, and the generation
// contract (updateFileGenerationStart -> writeGeneratedFilePart -> finish).
//
// The client binary never loads tdjson, so every request lands in the outbox
// and every answer is fed back through handleUpdate. A request that leaves
// src without its wire shape pinned here is exactly what this suite catches.
#import "TGTestRunner.h"
#import "TGClient.h"
#import "TGClientInternal.h"
#import "TGBase64.h"

@interface TGClientFileToolsTests : XCTestCase @end

static TGClient *FTClient(void) {
	TGClient *c = TGClient.shared;
	[c.outbox removeAllObjects];
	[c.pendingRequests removeAllObjects];
	c.me = @{@"id" : @(1001)};
	return c;
}

static NSDictionary *FTDecode(NSData *data) {
	NSString *json = [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding];
	NSString *trimmed = [json componentsSeparatedByString:@"\0"][0];
	return [NSJSONSerialization JSONObjectWithData:
			[trimmed dataUsingEncoding:NSUTF8StringEncoding] options:0 error:nil];
}

static NSDictionary *FTLast(TGClient *c, NSString *type) {
	NSDictionary *found = nil;
	for (NSData *data in c.outbox){
		NSDictionary *request = FTDecode(data);
		if ([request[@"@type"] isEqualToString:type])
			found = request;
	}
	return found;
}

static void FTAnswer(TGClient *c, NSDictionary *answer) {
	NSDictionary *sent = nil;
	for (NSData *data in c.outbox){
		NSDictionary *request = FTDecode(data);
		if (request[@"@extra"])
			sent = request;
	}
	if (!sent)
		return;
	NSMutableDictionary *reply = [answer mutableCopy];
	reply[@"@extra"] = sent[@"@extra"];
	[c handleUpdate:reply];
}

/// Literal dictionaries answer nil one level down; a real TDLib answer is
/// parsed, so round-trip the fixture through JSON before feeding it back.
static NSDictionary *FTPlain(NSDictionary *dictionary) {
	return [NSJSONSerialization JSONObjectWithData:
			[NSJSONSerialization dataWithJSONObject:dictionary options:0 error:nil]
			options:0 error:nil];
}

static NSDictionary *FTError(void) {
	return @{@"@type" : @"error", @"code" : @(400), @"message" : @"NO_FILE"};
}

@implementation TGClientFileToolsTests

// ─── file records ────────────────────────────────────────────────────────────

- (void)testFileInfo_ReadsTheRecordThenResolvesItsRemoteCopy {
	TGClient *c = FTClient();
	__block NSDictionary *got = nil;
	[c fileInfo:41 completion:^(NSDictionary *info){ got = info; }];

	NSDictionary *asked = FTLast(c, @"getFile");
	XCTAssertEqualObjects(asked[@"file_id"], @(41));

	FTAnswer(c, FTPlain(@{
		@"@type" : @"file",
		@"id" : @(41),
		@"size" : @(2048),
		@"expected_size" : @(4096),
		@"local" : @{
			@"path" : @"/var/tmp/photo.jpg",
			@"downloaded_size" : @(1024),
			@"is_downloading_active" : @NO,
			@"is_downloading_completed" : @YES,
		},
		@"remote" : @{
			@"id" : @"remote-41",
			@"unique_id" : @"unique-41",
			@"is_uploading_active" : @NO,
			@"uploaded_size" : @(0),
		},
	}));

	NSDictionary *remote = FTLast(c, @"getRemoteFile");
	XCTAssertEqualObjects(remote[@"remote_file_id"], @"remote-41");
	XCTAssertEqualObjects(remote[@"file_type"][@"@type"], @"fileTypeUnknown");

	FTAnswer(c, FTPlain(@{
		@"@type" : @"file",
		@"id" : @(41),
		@"size" : @(2048),
		@"expected_size" : @(4096),
		@"local" : @{@"path" : @""},
		@"remote" : @{@"id" : @"remote-41", @"uploaded_size" : @(2048)},
	}));

	XCTAssertEqualObjects(got[@"fileId"], @(41));
	XCTAssertEqualObjects(got[@"size"], @(2048));
	XCTAssertEqualObjects(got[@"expectedSize"], @(4096));
	XCTAssertEqualObjects(got[@"localPath"], @"/var/tmp/photo.jpg");
	XCTAssertEqualObjects(got[@"remoteId"], @"remote-41");
	XCTAssertEqualObjects(got[@"remoteResolved"], @YES);
	XCTAssertEqualObjects(got[@"remoteUploadedSize"], @(2048));
}

- (void)testFileInfo_AnErrorAnswersNil {
	TGClient *c = FTClient();
	__block NSDictionary *got = @{};
	[c fileInfo:41 completion:^(NSDictionary *info){ got = info; }];
	XCTAssertNotNil(FTLast(c, @"getFile"));
	FTAnswer(c, FTError());
	XCTAssertNil(got);
}

- (void)testDownloadedPrefix_ReturnsTheByteCount {
	TGClient *c = FTClient();
	__block long long bytes = -1;
	[c fileDownloadedPrefixSize:41 offset:100 completion:^(long long n){ bytes = n; }];

	NSDictionary *asked = FTLast(c, @"getFileDownloadedPrefixSize");
	XCTAssertEqualObjects(asked[@"file_id"], @(41));
	XCTAssertEqualObjects(asked[@"offset"], @(100));

	FTAnswer(c, FTPlain(@{@"@type" : @"fileDownloadedPrefixSize", @"size" : @(900)}));
	XCTAssertEqual(bytes, 900LL);
}

// ─── names and bytes ─────────────────────────────────────────────────────────

- (void)testFileNameInfo_ChainsMimeExtensionAndCleanName {
	TGClient *c = FTClient();
	__block NSDictionary *got = nil;
	[c fileNameInfo:@"Photo.JPG" completion:^(NSDictionary *info){ got = info; }];

	XCTAssertEqualObjects(FTLast(c, @"getFileMimeType")[@"file_name"], @"Photo.JPG");
	FTAnswer(c, FTPlain(@{@"@type" : @"text", @"text" : @"image/jpeg"}));

	XCTAssertEqualObjects(FTLast(c, @"getFileExtension")[@"mime_type"], @"image/jpeg");
	FTAnswer(c, FTPlain(@{@"@type" : @"text", @"text" : @"jpg"}));

	XCTAssertEqualObjects(FTLast(c, @"cleanFileName")[@"file_name"], @"Photo.JPG");
	FTAnswer(c, FTPlain(@{@"@type" : @"text", @"text" : @"Photo.JPG"}));

	XCTAssertEqualObjects(got[@"mime"], @"image/jpeg");
	XCTAssertEqualObjects(got[@"extension"], @"jpg");
	XCTAssertEqualObjects(got[@"cleanName"], @"Photo.JPG");
}

- (void)testSuggestedFileName_SendsTheFileAndDirectory {
	TGClient *c = FTClient();
	__block NSString *got = nil;
	[c suggestedFileNameForFile:41 directory:@"/var/tmp" completion:^(NSString *name){ got = name; }];

	NSDictionary *asked = FTLast(c, @"getSuggestedFileName");
	XCTAssertEqualObjects(asked[@"file_id"], @(41));
	XCTAssertEqualObjects(asked[@"directory"], @"/var/tmp");
	FTAnswer(c, FTPlain(@{@"@type" : @"text", @"text" : @"photo.jpg"}));
	XCTAssertEqualObjects(got, @"photo.jpg");
}

- (void)testReadFilePart_DecodesTheBytes {
	TGClient *c = FTClient();
	__block NSData *got = nil;
	[c readFilePartOfFile:41 offset:0 count:3 completion:^(NSData *data){ got = data; }];

	NSDictionary *asked = FTLast(c, @"readFilePart");
	XCTAssertEqualObjects(asked[@"file_id"], @(41));
	XCTAssertEqualObjects(asked[@"offset"], @(0));
	XCTAssertEqualObjects(asked[@"count"], @(3));
	FTAnswer(c, FTPlain(@{@"@type" : @"data",
						  @"data" : TGBase64Encode([@"abc" dataUsingEncoding:NSUTF8StringEncoding])}));
	XCTAssertEqualObjects([[NSString alloc] initWithData:got encoding:NSUTF8StringEncoding], @"abc");
}

// ─── generation ──────────────────────────────────────────────────────────────

- (void)testGenerateTextFile_SendsGeneratedInputThenWritesEveryPart {
	TGClient *c = FTClient();
	NSString *contents = @"hello generated file";
	__block NSInteger doneFile = 0;
	__block NSString *donePath = nil;
	__block NSError *doneError = nil;
	__block NSMutableArray *stages = [NSMutableArray array];

	[c generateTextFileNamed:@"note.txt" contents:contents
			progress:^(NSInteger fileId, float progress, NSString *stage){
		[stages addObject:stage ?: @""];
	} completion:^(NSInteger fileId, NSString *path, NSError *error){
		doneFile = fileId;
		donePath = path;
		doneError = error;
	}];

	NSDictionary *upload = FTLast(c, @"preliminaryUploadFile");
	XCTAssertNotNil(upload);
	XCTAssertEqualObjects(upload[@"file"][@"@type"], @"inputFileGenerated");
	XCTAssertEqualObjects(upload[@"file"][@"conversion"], @"legacy-text");
	XCTAssertEqualObjects(upload[@"file_type"][@"@type"], @"fileTypeDocument");
	XCTAssertEqualObjects(upload[@"priority"], @(1));
	NSString *original = upload[@"file"][@"original_path"];
	XCTAssertEqualObjects(upload[@"file"][@"expected_size"],
						  @([contents lengthOfBytesUsingEncoding:NSUTF8StringEncoding]));

	FTAnswer(c, FTPlain(@{
		@"@type" : @"file",
		@"id" : @(700),
		@"size" : @(0),
		@"expected_size" : @(0),
		@"local" : @{},
		@"remote" : @{},
	}));

	[c handleUpdate:FTPlain(@{
		@"@type" : @"updateFileGenerationStart",
		@"generation_id" : @(9),
		@"original_path" : original,
		@"destination_path" : @"/var/tmp/generated.txt",
		@"conversion" : @"legacy-text",
	})];

	NSDictionary *progress = FTLast(c, @"setFileGenerationProgress");
	XCTAssertEqualObjects(progress[@"generation_id"], @(9));
	XCTAssertEqualObjects(progress[@"expected_size"],
						  @([contents lengthOfBytesUsingEncoding:NSUTF8StringEncoding]));

	NSDictionary *written = FTLast(c, @"writeGeneratedFilePart");
	XCTAssertEqualObjects(written[@"generation_id"], @(9));
	XCTAssertEqualObjects(written[@"offset"], @(0));
	NSString *decoded = [[NSString alloc] initWithData:TGBase64Decode(written[@"data"])
											  encoding:NSUTF8StringEncoding];
	XCTAssertEqualObjects(decoded, contents);

	NSDictionary *finished = FTLast(c, @"finishFileGeneration");
	XCTAssertEqualObjects(finished[@"generation_id"], @(9));
	XCTAssertEqualObjects(finished[@"error"], [NSNull null]);

	XCTAssertEqual(doneFile, 700);
	XCTAssertEqualObjects(donePath, @"/var/tmp/generated.txt");
	XCTAssertNil(doneError);
	XCTAssertTrue([stages containsObject:@"generating"]);
	XCTAssertTrue([stages containsObject:@"generated"]);
}

- (void)testGenerateTextFile_StopAfterWritingDoesNotFailTheUpload {
	TGClient *c = FTClient();
	__block NSError *doneError = nil;
	__block NSString *donePath = nil;
	[c generateTextFileNamed:@"note.txt" contents:@"race" progress:nil
				   completion:^(NSInteger fileId, NSString *path, NSError *error){
		doneError = error;
		donePath = path;
	}];

	NSDictionary *upload = FTLast(c, @"preliminaryUploadFile");
	NSString *original = upload[@"file"][@"original_path"];
	[c handleUpdate:FTPlain(@{
		@"@type" : @"updateFileGenerationStart",
		@"generation_id" : @(11),
		@"original_path" : original,
		@"destination_path" : @"/var/tmp/race.txt",
		@"conversion" : @"legacy-text",
	})];
	// The stop is TDLib acknowledging our finish, before the upload answer
	// names the file. It must not be mistaken for a failed generation.
	[c handleUpdate:FTPlain(@{
		@"@type" : @"updateFileGenerationStop",
		@"generation_id" : @(11),
	})];
	XCTAssertNil(doneError);

	FTAnswer(c, FTPlain(@{
		@"@type" : @"file", @"id" : @(701), @"size" : @(0),
		@"expected_size" : @(0), @"local" : @{}, @"remote" : @{},
	}));
	XCTAssertNil(doneError);
	XCTAssertEqualObjects(donePath, @"/var/tmp/race.txt");
}

- (void)testGenerateTextFile_AnUploadErrorReachesTheCompletion {
	TGClient *c = FTClient();
	__block NSError *doneError = nil;
	[c generateTextFileNamed:@"note.txt" contents:@"x" progress:nil
				   completion:^(NSInteger fileId, NSString *path, NSError *error){
		doneError = error;
	}];
	FTAnswer(c, FTError());
	XCTAssertNotNil(doneError);
	XCTAssertEqualObjects(doneError.localizedDescription, @"NO_FILE");
}

- (void)testCancelPreliminaryUpload_SendsTheFileId {
	TGClient *c = FTClient();
	[c cancelPreliminaryUploadOfFile:700];
	NSDictionary *asked = FTLast(c, @"cancelPreliminaryUploadFile");
	XCTAssertEqualObjects(asked[@"file_id"], @(700));
}

// ─── presets ─────────────────────────────────────────────────────────────────

- (void)testAutoDownloadPresets_FlattensAllThree {
	TGClient *c = FTClient();
	__block NSDictionary *got = nil;
	[c autoDownloadSettingsPresetsWithCompletion:^(NSDictionary *p){ got = p; }];

	XCTAssertNotNil(FTLast(c, @"getAutoDownloadSettingsPresets"));
	NSDictionary *preset = @{
		@"@type" : @"autoDownloadSettings",
		@"is_auto_download_enabled" : @YES,
		@"max_photo_file_size" : @(1024),
		@"max_video_file_size" : @(2048),
		@"max_other_file_size" : @(4096),
		@"preload_large_videos" : @NO,
		@"preload_next_audio" : @YES,
		@"use_less_data_for_calls" : @YES,
	};
	FTAnswer(c, FTPlain(@{
		@"@type" : @"autoDownloadSettingsPresets",
		@"low" : preset,
		@"medium" : preset,
		@"high" : preset,
	}));

	XCTAssertEqualObjects(got[@"medium"][@"enabled"], @YES);
	XCTAssertEqualObjects(got[@"medium"][@"maxPhotoSize"], @(1024));
	XCTAssertEqualObjects(got[@"medium"][@"maxVideoSize"], @(2048));
	XCTAssertEqualObjects(got[@"medium"][@"preloadAudio"], @YES);
}

- (void)testApplyPreset_WritesThePresetForTheNamedNetwork {
	TGClient *c = FTClient();
	__block BOOL ok = NO;
	[c applyAutoDownloadPreset:@{
		@"enabled" : @YES,
		@"maxPhotoSize" : @(1024),
		@"maxVideoSize" : @(2048),
		@"maxOtherSize" : @(4096),
		@"preloadVideos" : @NO,
		@"preloadAudio" : @YES,
		@"lessDataForCalls" : @NO,
	} forNetwork:@"mobile" completion:^(BOOL result){ ok = result; }];

	NSDictionary *asked = FTLast(c, @"setAutoDownloadSettings");
	XCTAssertEqualObjects(asked[@"type"][@"@type"], @"networkTypeMobile");
	XCTAssertEqualObjects(asked[@"settings"][@"max_video_file_size"], @(2048));
	FTAnswer(c, FTPlain(@{@"@type" : @"ok"}));
	XCTAssertTrue(ok);
}

@end
