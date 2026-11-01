#import "TGVideoChatStreamViewController.h"
#import "TGClient.h"
#import "TGTheme.h"
#import "TGStyle.h"
#import "TGAlertSheet.h"

@interface TGVideoChatStreamViewController ()
@property (nonatomic, strong) NSArray *streams;
@property (nonatomic, copy) NSString *statusText;
@property (nonatomic, strong) NSData *lastEncrypted;
@property (nonatomic, strong) NSData *sample;
@property (nonatomic, assign) BOOL busy;
@end

@implementation TGVideoChatStreamViewController

- (instancetype)initWithChatId:(int64_t)chatId groupCallId:(int32_t)groupCallId {
	self = [super init];
	if (self){
		_chatId = chatId;
		_groupCallId = groupCallId;
		self.listTitle = @"Streams and Data";
		self.emptyText = @"No stream channels loaded yet.";
		_sample = [@"LegacyTG group-call data channel sample" dataUsingEncoding:NSUTF8StringEncoding];
		_statusText = @"Load the call's stream channels, or run the data-channel check.";
	}
	return self;
}

- (void)viewDidLoad {
	[super viewDidLoad];
	[self rebuildRows];
}

- (void)setStatus:(NSString *)status {
	self.statusText = status ?: @"";
	[self rebuildRows];
}

- (NSDictionary *)rowWithTitle:(NSString *)title detail:(NSString *)detail tap:(void (^)(void))tap {
	NSMutableDictionary *row = [NSMutableDictionary dictionary];
	row[@"title"] = title ?: @"";
	if (detail.length)
		row[@"detail"] = detail;
	if (tap)
		row[@"tap"] = tap;
	return row;
}

- (void)rebuildRows {
	__weak typeof(self) weakSelf = self;
	NSMutableArray *rows = [NSMutableArray array];
	[rows addObject:[self rowWithTitle:@"Load Streams"
			detail:@"getGroupCallStreams"
			tap:^{ [weakSelf loadStreams]; }]];
	for (NSDictionary *stream in self.streams){
		NSString *title = [NSString stringWithFormat:@"Channel %ld · scale %ld",
				(long)[stream[@"channelId"] integerValue],
				(long)[stream[@"scale"] integerValue]];
		NSString *detail = [NSString stringWithFormat:@"time offset %lld ms · tap for a segment",
				(long long)[stream[@"timeOffset"] longLongValue]];
		[rows addObject:[self rowWithTitle:title detail:detail tap:^{
			[weakSelf chooseQualityForStream:stream];
		}]];
	}
	[rows addObject:[self rowWithTitle:@"Mark Myself Speaking"
			detail:@"setGroupCallParticipantIsSpeaking, audio source of this account"
			tap:^{ [weakSelf setSpeaking:YES]; }]];
	[rows addObject:[self rowWithTitle:@"Stop Speaking Indicator"
			detail:@"Sends the same flag as false"
			tap:^{ [weakSelf setSpeaking:NO]; }]];
	[rows addObject:[self rowWithTitle:@"Encrypt Sample Payload"
			detail:@"encryptGroupCallData on the main channel"
			tap:^{ [weakSelf encryptSample]; }]];
	[rows addObject:[self rowWithTitle:@"Decrypt Last Payload"
			detail:self.lastEncrypted.length ? @"decryptGroupCallData as this account"
					: @"Encrypt a sample first"
			tap:^{ [weakSelf decryptLast]; }]];
	self.rows = rows;
	self.listFooter = self.statusText;
	[self.tableView reloadData];
}

#pragma mark - streams

- (void)loadStreams {
	if (!self.groupCallId){
		[self setStatus:@"Open this screen from a call."];
		return;
	}
	__weak typeof(self) weakSelf = self;
	[[TGClient shared] groupCallStreams:self.groupCallId
							 completion:^(NSArray *streams, NSString *error){
		TGVideoChatStreamViewController *me = weakSelf;
		if (!me)
			return;
		if (!streams){
			[me setStatus:error ?: @"Telegram refused that."];
			return;
		}
		me.streams = streams;
		[me setStatus:streams.count
				? [NSString stringWithFormat:@"%ld stream channel%@ returned.",
						(long)streams.count, streams.count == 1 ? @"" : @"s"]
				: @"Telegram returned no stream channels for this call."];
	}];
}

- (void)chooseQualityForStream:(NSDictionary *)stream {
	NSArray *titles = @[@"Thumbnail quality", @"Medium quality", @"Full quality"];
	NSArray *keys = @[@"thumbnail", @"medium", @"full"];
	__weak typeof(self) weakSelf = self;
	[TGAlertSheet showChoices:titles title:@"Stream Segment"
			destructiveIndex:-1 inView:self.view onChoice:^(NSInteger index){
		TGVideoChatStreamViewController *me = weakSelf;
		if (!me || index < 0 || index >= (NSInteger)keys.count)
			return;
		[me loadSegmentForStream:stream quality:keys[(NSUInteger)index]];
	}];
}

- (void)loadSegmentForStream:(NSDictionary *)stream quality:(NSString *)quality {
	if (self.busy)
		return;
	self.busy = YES;
	__weak typeof(self) weakSelf = self;
	[[TGClient shared] groupCallStreamSegment:self.groupCallId
			timeOffset:[stream[@"timeOffset"] longLongValue]
				 scale:[stream[@"scale"] integerValue]
			 channelId:[stream[@"channelId"] integerValue]
			   quality:quality
			completion:^(NSData *data, NSString *error){
		TGVideoChatStreamViewController *me = weakSelf;
		if (!me)
			return;
		me.busy = NO;
		if (!data){
			[me setStatus:error ?: @"Telegram refused that segment."];
			return;
		}
		NSString *name = [NSString stringWithFormat:@"group-call-%d-%ld-%lld.ogg",
				me.groupCallId, (long)[stream[@"channelId"] integerValue],
				(long long)[stream[@"timeOffset"] longLongValue]];
		NSString *path = [NSTemporaryDirectory() stringByAppendingPathComponent:name];
		BOOL written = [data writeToFile:path atomically:YES];
		[me setStatus:[NSString stringWithFormat:
				@"Segment: %lu bytes, %@ quality, %@. %@",
				(unsigned long)data.length, quality,
				written ? path : @"could not be written to disk",
				@"It is the modified OGG/MP4 Telegram generated; this client "
				@"has no group-call media engine to decode it in-app."]];
	}];
}

#pragma mark - speaking

- (void)setSpeaking:(BOOL)speaking {
	NSDictionary *participant = [[TGClient shared] currentGroupCallParticipant:self.groupCallId];
	NSNumber *source = participant[@"audioSourceId"];
	if (!source)
		source = @(0);
	__weak typeof(self) weakSelf = self;
	[[TGClient shared] setGroupCallParticipantSpeaking:[source intValue]
												inCall:self.groupCallId
											 isSpeaking:speaking
											 completion:^(NSDictionary *sender, NSString *error){
		TGVideoChatStreamViewController *me = weakSelf;
		if (!me)
			return;
		if (error.length){
			[me setStatus:error];
			return;
		}
		[me setStatus:sender
				? [NSString stringWithFormat:@"Telegram matched the speaking flag to user %@.",
						sender[@"user_id"] ?: sender[@"chat_id"]]
				: @"Telegram accepted the speaking flag but named no participant."];
	}];
}

#pragma mark - data channel

- (void)encryptSample {
	if (self.busy || !self.sample.length)
		return;
	if (!self.groupCallId){
		[self setStatus:@"Open this screen from a call."];
		return;
	}
	self.busy = YES;
	__weak typeof(self) weakSelf = self;
	[[TGClient shared] encryptGroupCallData:self.sample inCall:self.groupCallId
									channel:@"main" unencryptedPrefixSize:0
								 completion:^(NSData *encrypted, NSString *error){
		TGVideoChatStreamViewController *me = weakSelf;
		if (!me)
			return;
		me.busy = NO;
		if (!encrypted){
			[me setStatus:error ?: @"Telegram refused to encrypt the sample."];
			return;
		}
		me.lastEncrypted = encrypted;
		[me setStatus:[NSString stringWithFormat:
				@"Encrypted %lu bytes to %lu bytes on the main channel. "
				@"Decrypt Last Payload sends them back through TDLib.",
				(unsigned long)me.sample.length, (unsigned long)encrypted.length]];
	}];
}

- (void)decryptLast {
	if (self.busy || !self.lastEncrypted.length)
		return;
	NSDictionary *participant = [[TGClient shared] currentGroupCallParticipant:self.groupCallId];
	NSDictionary *sender = participant[@"sender"];
	if (!sender){
		int64_t meId = [[TGClient shared].me[@"id"] longLongValue];
		sender = @{@"@type" : @"messageSenderUser", @"user_id" : @(meId)};
	}
	self.busy = YES;
	__weak typeof(self) weakSelf = self;
	[[TGClient shared] decryptGroupCallData:self.lastEncrypted fromParticipant:sender
									 inCall:self.groupCallId channel:@"main"
								 completion:^(NSData *decrypted, NSString *error){
		TGVideoChatStreamViewController *me = weakSelf;
		if (!me)
			return;
		me.busy = NO;
		if (!decrypted){
			[me setStatus:error ?: @"Telegram refused to decrypt the payload."];
			return;
		}
		BOOL roundTrip = [decrypted isEqualToData:me.sample];
		[me setStatus:[NSString stringWithFormat:
				@"Decrypted %lu bytes. %@",
				(unsigned long)decrypted.length,
				roundTrip ? @"The bytes match the sample: the data channel round-trips."
						  : @"The bytes differ from the sample; Telegram's keys are "
							@"per call and this is the answer it gave."]];
	}];
}

@end

// vim:ft=objc
