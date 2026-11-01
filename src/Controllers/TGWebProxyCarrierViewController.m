//
// TGWebProxyCarrierViewController.m - messages and errors for a web proxy
// carrier, the page TDLib asks the client to host for proxyTypeWeb.
//
// TDLib opens a carrier with updateWebProxyCarrierOpened and then waits for
// every postMessage the page made, in order. This screen is that bridge's
// manual half: a carrier id, one message, and the error report that closes
// it. When the id is not an open carrier, TDLib's refusal is the answer.
//
#import "TGWebProxyCarrierViewController.h"
#import "TGClient.h"
#import "TGAlertSheet.h"
#import "TGStyle.h"

@interface TGWebProxyCarrierViewController ()
@property (nonatomic, assign) NSInteger carrierId;
@property (nonatomic, copy) NSString *messageText;
@property (nonatomic, copy) NSString *errorKind;
@property (nonatomic, copy) NSString *errorMessage;
@property (nonatomic, strong) NSArray *answerLines;
@end

@implementation TGWebProxyCarrierViewController

- (void)viewDidLoad {
	[super viewDidLoad];
	self.title = @"Web Proxy Carrier";
	self.errorKind = @"unsupported";
	self.answerLines = @[@"No message passed yet."];
	[self rebuildSections];
}

- (void)rebuildSections {
	NSMutableArray *answers = [NSMutableArray array];
	for (NSString *line in self.answerLines)
		[answers addObject:TGBInfo(line, nil)];

	NSMutableArray *errorRows = [NSMutableArray array];
	[errorRows addObject:TGBAction(@"Error", [self errorKindTitle], @"errorKind")];
	if ([self.errorKind isEqualToString:@"loadFailed"]){
		[errorRows addObject:TGBAction(@"Error Message",
				self.errorMessage.length ? self.errorMessage : @"Set", @"errorMessage")];
	}
	[errorRows addObject:TGBAction(@"Report Error", nil, @"reportError")];

	self.sections = @[
		TGBSection(@"CARRIER",
				@"The id comes from updateWebProxyCarrierOpened. TDLib can be "
				@"told about a carrier before authorization, so this page also "
				@"works on the login screen when a web proxy is in use.",
				@[
			TGBAction(@"Carrier ID", [NSString stringWithFormat:@"%ld",
					(long)self.carrierId], @"carrierId"),
			TGBAction(@"Message Text", self.messageText.length
					? self.messageText : @"Set", @"text"),
			TGBAction(@"Pass Text Message", nil, @"passText"),
			TGBAction(@"Pass Binary Message", @"Text above is base64", @"passBinary"),
		]),
		TGBSection(@"ERROR", @"An error closes the carrier; TDLib decides whether "
				@"and when to request another one.", errorRows),
		TGBSection(@"ANSWER", nil, answers),
	];
	[self rebuild];
}

- (NSString *)errorKindTitle {
	if ([self.errorKind isEqualToString:@"paused"]) return @"Paused";
	if ([self.errorKind isEqualToString:@"loadFailed"]) return @"Load Failed";
	if ([self.errorKind isEqualToString:@"terminated"]) return @"Terminated";
	if ([self.errorKind isEqualToString:@"refused"]) return @"Refused";
	return @"Unsupported";
}

- (void)finish:(BOOL)ok error:(NSString *)error title:(NSString *)title {
	if (ok)
		self.answerLines = @[@"TDLib accepted the carrier message."];
	else
		self.answerLines = @[error.length ? error : @"TDLib refused that carrier message."];
	[self rebuildSections];
	if (!ok)
		[self showResult:NO error:error title:title];
}

- (void)didChooseAction:(NSString *)action row:(NSDictionary *)row {
	__weak typeof(self) weakSelf = self;
	if ([action isEqualToString:@"carrierId"]){
		[self askText:@"Carrier ID" message:@"From updateWebProxyCarrierOpened."
		  placeholder:@"1" text:[NSString stringWithFormat:@"%ld", (long)self.carrierId]
			   action:@"Save" completion:^(NSString *text){
			weakSelf.carrierId = [text integerValue];
			[weakSelf rebuildSections];
		}];
	} else if ([action isEqualToString:@"text"]){
		[self askText:@"Carrier Message" message:nil placeholder:@"postMessage text"
				 text:self.messageText action:@"Save" completion:^(NSString *text){
			weakSelf.messageText = text;
			[weakSelf rebuildSections];
		}];
	} else if ([action isEqualToString:@"passText"]){
		[[TGClient shared] processWebProxyCarrierMessage:self.carrierId
													text:self.messageText
											  completion:^(BOOL ok, NSString *error){
			[weakSelf finish:ok error:error title:@"Carrier Message"];
		}];
	} else if ([action isEqualToString:@"passBinary"]){
		[[TGClient shared] processWebProxyCarrierMessage:self.carrierId
												  base64:self.messageText
											  completion:^(BOOL ok, NSString *error){
			[weakSelf finish:ok error:error title:@"Carrier Message"];
		}];
	} else if ([action isEqualToString:@"errorKind"]){
		[TGAlertSheet showChoices:@[@"Unsupported", @"Paused", @"Load Failed",
									@"Terminated", @"Refused"]
							title:@"Carrier Error"
				 destructiveIndex:-1 inView:self.view
						 onChoice:^(NSInteger index){
			static NSArray *kinds = nil;
			if (!kinds)
				kinds = @[@"unsupported", @"paused", @"loadFailed",
						  @"terminated", @"refused"];
			weakSelf.errorKind = kinds[(NSUInteger)index];
			[weakSelf rebuildSections];
		}];
	} else if ([action isEqualToString:@"errorMessage"]){
		[self askText:@"Error Message" message:nil placeholder:@"The page did not load"
				 text:self.errorMessage action:@"Save" completion:^(NSString *text){
			weakSelf.errorMessage = text;
			[weakSelf rebuildSections];
		}];
	} else if ([action isEqualToString:@"reportError"]){
		[[TGClient shared] reportWebProxyCarrierError:self.carrierId
												 kind:self.errorKind
											  message:self.errorMessage
										   completion:^(BOOL ok, NSString *error){
			[weakSelf finish:ok error:error title:@"Carrier Error"];
		}];
	}
}

@end

// vim:ft=objc
