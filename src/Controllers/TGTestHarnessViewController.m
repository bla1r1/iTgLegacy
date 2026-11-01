//
// TGTestHarnessViewController.m
//
// A diagnostic, not a feature. Each row sends one test* request with the
// value typed above it and puts Telegram's answer in the ANSWER section.
// testReturnError is the one call whose success is an error object; it is
// printed as code + message, not as a failure of the request.
//
#import "TGTestHarnessViewController.h"
#import "TGClient.h"

@interface TGTestHarnessViewController ()
@property (nonatomic, copy) NSString *text;
@property (nonatomic, copy) NSString *number;
@property (nonatomic, copy) NSString *intVector;
@property (nonatomic, copy) NSString *stringVector;
@property (nonatomic, copy) NSString *bytes;
@property (nonatomic, copy) NSString *errorCode;
@property (nonatomic, copy) NSString *errorMessage;
@property (nonatomic, strong) NSArray *answerLines;
@end

@implementation TGTestHarnessViewController

- (instancetype)init {
	if ((self = [super init])){
		_text = @"hello";
		_number = @"12";
		_intVector = @"1,2,3";
		_stringVector = @"a,b";
		_bytes = @"AQID";
		_errorCode = @"400";
		_errorMessage = @"Test error";
		_answerLines = @[@"Pick a test method. The request goes to Telegram."];
	}
	return self;
}

- (void)viewDidLoad {
	[super viewDidLoad];
	self.title = @"TDLib Test Harness";
	[self rebuildSections];
}

- (NSArray *)numbersFrom:(NSString *)text {
	NSMutableArray *values = [NSMutableArray array];
	for (NSString *part in [text componentsSeparatedByString:@","]){
		NSString *trimmed = [part stringByTrimmingCharactersInSet:
				[NSCharacterSet whitespaceAndNewlineCharacterSet]];
		if (trimmed.length)
			[values addObject:@(trimmed.intValue)];
	}
	return values;
}

- (NSArray *)stringsFrom:(NSString *)text {
	NSMutableArray *values = [NSMutableArray array];
	for (NSString *part in [text componentsSeparatedByString:@","]){
		NSString *trimmed = [part stringByTrimmingCharactersInSet:
				[NSCharacterSet whitespaceAndNewlineCharacterSet]];
		if (trimmed.length)
			[values addObject:trimmed];
	}
	return values;
}

- (void)rebuildSections {
	NSMutableArray *inputRows = [NSMutableArray array];
	[inputRows addObject:TGBAction(@"String", self.text, @"text")];
	[inputRows addObject:TGBAction(@"Integer", self.number, @"number")];
	[inputRows addObject:TGBAction(@"Integer Vector", self.intVector, @"intVector")];
	[inputRows addObject:TGBAction(@"String Vector", self.stringVector, @"stringVector")];
	[inputRows addObject:TGBAction(@"Bytes (base64)", self.bytes, @"bytes")];
	[inputRows addObject:TGBAction(@"Error Code", self.errorCode, @"errorCode")];
	[inputRows addObject:TGBAction(@"Error Message", self.errorMessage, @"errorMessage")];

	NSMutableArray *scalarRows = [NSMutableArray array];
	[scalarRows addObject:TGBAction(@"testCallEmpty", nil, @"callEmpty")];
	[scalarRows addObject:TGBAction(@"testCallString", nil, @"callString")];
	[scalarRows addObject:TGBAction(@"testCallBytes", nil, @"callBytes")];
	[scalarRows addObject:TGBAction(@"testSquareInt", nil, @"squareInt")];
	[scalarRows addObject:TGBAction(@"testReturnError", nil, @"returnError")];
	[scalarRows addObject:TGBAction(@"testUseUpdate", nil, @"useUpdate")];

	NSMutableArray *vectorRows = [NSMutableArray array];
	[vectorRows addObject:TGBAction(@"testCallVectorInt", nil, @"vectorInt")];
	[vectorRows addObject:TGBAction(@"testCallVectorIntObject", nil, @"vectorIntObject")];
	[vectorRows addObject:TGBAction(@"testCallVectorString", nil, @"vectorString")];
	[vectorRows addObject:TGBAction(@"testCallVectorStringObject", nil, @"vectorStringObject")];

	NSMutableArray *plumbingRows = [NSMutableArray array];
	[plumbingRows addObject:TGBAction(@"testGetDifference", nil, @"getDifference")];
	[plumbingRows addObject:TGBAction(@"testNetwork", nil, @"network")];

	NSMutableArray *answers = [NSMutableArray array];
	for (NSString *line in self.answerLines)
		[answers addObject:TGBInfo(line, nil)];

	self.sections = @[
		TGBSection(@"INPUTS", @"Comma-separated values become the vectors; "
				@"bytes are base64 because that is how TDLib's JSON carries them.",
				inputRows),
		TGBSection(@"SCALAR", nil, scalarRows),
		TGBSection(@"VECTORS", nil, vectorRows),
		TGBSection(@"PLUMBING", nil, plumbingRows),
		TGBSection(@"ANSWER", nil, answers),
	];
	[self rebuild];
}

- (void)showAnswer:(NSString *)text title:(NSString *)title {
	self.answerLines = text.length ? @[text] : @[@"Telegram answered with an empty value."];
	[self rebuildSections];
	[self showMessage:self.answerLines.firstObject title:title];
}

- (void)finish:(BOOL)ok error:(NSString *)error title:(NSString *)title {
	self.answerLines = @[ok ? @"Telegram accepted the request."
			: (error.length ? error : @"Telegram refused that.")];
	[self rebuildSections];
	if (!ok)
		[self showMessage:self.answerLines.firstObject title:title];
}

- (void)didChooseAction:(NSString *)action row:(NSDictionary *)row {
	__weak typeof(self) weakSelf = self;
	if ([action isEqualToString:@"text"] || [action isEqualToString:@"number"] ||
			[action isEqualToString:@"intVector"] ||
			[action isEqualToString:@"stringVector"] ||
			[action isEqualToString:@"bytes"] ||
			[action isEqualToString:@"errorCode"] ||
			[action isEqualToString:@"errorMessage"]){
		NSString *current = nil;
		NSString *label = @"Value";
		if ([action isEqualToString:@"text"]){ current = self.text; label = @"String"; }
		if ([action isEqualToString:@"number"]){ current = self.number; label = @"Integer"; }
		if ([action isEqualToString:@"intVector"]){ current = self.intVector; label = @"Integer Vector"; }
		if ([action isEqualToString:@"stringVector"]){ current = self.stringVector; label = @"String Vector"; }
		if ([action isEqualToString:@"bytes"]){ current = self.bytes; label = @"Bytes"; }
		if ([action isEqualToString:@"errorCode"]){ current = self.errorCode; label = @"Error Code"; }
		if ([action isEqualToString:@"errorMessage"]){ current = self.errorMessage; label = @"Error Message"; }
		[self askText:label message:nil placeholder:current text:current
			   action:@"Save" completion:^(NSString *text){
			if ([action isEqualToString:@"text"]) weakSelf.text = text;
			if ([action isEqualToString:@"number"]) weakSelf.number = text;
			if ([action isEqualToString:@"intVector"]) weakSelf.intVector = text;
			if ([action isEqualToString:@"stringVector"]) weakSelf.stringVector = text;
			if ([action isEqualToString:@"bytes"]) weakSelf.bytes = text;
			if ([action isEqualToString:@"errorCode"]) weakSelf.errorCode = text;
			if ([action isEqualToString:@"errorMessage"]) weakSelf.errorMessage = text;
			[weakSelf rebuildSections];
		}];
		return;
	}

	if ([action isEqualToString:@"callEmpty"]){
		[[TGClient shared] testCallEmptyWithCompletion:^(BOOL ok, NSString *error){
			[weakSelf finish:ok error:error title:@"testCallEmpty"];
		}];
	} else if ([action isEqualToString:@"callString"]){
		[[TGClient shared] testCallString:self.text
							   completion:^(NSString *value, NSString *error){
			if (error) [weakSelf finish:NO error:error title:@"testCallString"];
			else [weakSelf showAnswer:value title:@"testCallString"];
		}];
	} else if ([action isEqualToString:@"callBytes"]){
		if (!self.bytes.length){
			[self showMessage:@"A base64 byte string is needed." title:@"testCallBytes"];
			return;
		}
		[[TGClient shared] testCallBytes:self.bytes
							  completion:^(NSString *value, NSString *error){
			if (error) [weakSelf finish:NO error:error title:@"testCallBytes"];
			else [weakSelf showAnswer:value title:@"testCallBytes"];
		}];
	} else if ([action isEqualToString:@"vectorInt"]){
		[[TGClient shared] testCallVectorInt:[self numbersFrom:self.intVector]
								  completion:^(NSArray *result, NSString *error){
			if (error){
				[weakSelf finish:NO error:error title:@"testCallVectorInt"];
				return;
			}
			NSMutableArray *lines = [NSMutableArray array];
			for (id value in result)
				[lines addObject:[value description]];
			[weakSelf showAnswer:[lines componentsJoinedByString:@", "]
						   title:@"testCallVectorInt"];
		}];
	} else if ([action isEqualToString:@"vectorIntObject"]){
		[[TGClient shared] testCallVectorIntObject:[self numbersFrom:self.intVector]
										completion:^(NSArray *result, NSString *error){
			if (error){
				[weakSelf finish:NO error:error title:@"testCallVectorIntObject"];
				return;
			}
			NSMutableArray *lines = [NSMutableArray array];
			for (id value in result)
				[lines addObject:[value description]];
			[weakSelf showAnswer:[lines componentsJoinedByString:@", "]
						   title:@"testCallVectorIntObject"];
		}];
	} else if ([action isEqualToString:@"vectorString"]){
		[[TGClient shared] testCallVectorString:[self stringsFrom:self.stringVector]
									 completion:^(NSArray *result, NSString *error){
			if (error){
				[weakSelf finish:NO error:error title:@"testCallVectorString"];
				return;
			}
			[weakSelf showAnswer:[result componentsJoinedByString:@", "]
						   title:@"testCallVectorString"];
		}];
	} else if ([action isEqualToString:@"vectorStringObject"]){
		[[TGClient shared] testCallVectorStringObject:[self stringsFrom:self.stringVector]
										   completion:^(NSArray *result, NSString *error){
			if (error){
				[weakSelf finish:NO error:error title:@"testCallVectorStringObject"];
				return;
			}
			[weakSelf showAnswer:[result componentsJoinedByString:@", "]
						   title:@"testCallVectorStringObject"];
		}];
	} else if ([action isEqualToString:@"squareInt"]){
		[[TGClient shared] testSquareInt:self.number.intValue
							  completion:^(int32_t result, NSString *error){
			if (error){
				[weakSelf finish:NO error:error title:@"testSquareInt"];
				return;
			}
			[weakSelf showAnswer:[NSString stringWithFormat:@"%d", (int)result]
						   title:@"testSquareInt"];
		}];
	} else if ([action isEqualToString:@"returnError"]){
		[[TGClient shared] testReturnErrorCode:self.errorCode.intValue
									  message:self.errorMessage
								   completion:^(int32_t code, NSString *message,
												NSString *error){
			if (error){
				[weakSelf finish:NO error:error title:@"testReturnError"];
				return;
			}
			[weakSelf showAnswer:[NSString stringWithFormat:@"Error %d: %@",
					(int)code, message ?: @""] title:@"testReturnError"];
		}];
	} else if ([action isEqualToString:@"getDifference"]){
		[[TGClient shared] testGetDifferenceWithCompletion:^(BOOL ok, NSString *error){
			[weakSelf finish:ok error:error title:@"testGetDifference"];
		}];
	} else if ([action isEqualToString:@"network"]){
		[[TGClient shared] testNetworkWithCompletion:^(BOOL ok, NSString *error){
			[weakSelf finish:ok error:error title:@"testNetwork"];
		}];
	} else if ([action isEqualToString:@"useUpdate"]){
		[[TGClient shared] testUseUpdateWithCompletion:^(NSDictionary *update,
														 NSString *error){
			if (error){
				[weakSelf finish:NO error:error title:@"testUseUpdate"];
				return;
			}
			[weakSelf showAnswer:[NSString stringWithFormat:@"Update: %@",
					update[@"@type"] ?: @"?"] title:@"testUseUpdate"];
		}];
	}
}

@end

// vim:ft=objc
