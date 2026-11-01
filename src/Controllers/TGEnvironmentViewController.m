//
// TGEnvironmentViewController.m - the environment calls a normal client
// still uses: JSON conversion for the debug surfaces, the time-zone list a
// schedule picker needs, weather for a location, exchange rates, and TDLib's
// own log controls.
//
// Everything here is a request or a synchronous td_api call with a real
// answer. A build whose dylib has no execute symbol says so instead of
// pretending the JSON parsed.
//
#import "TGEnvironmentViewController.h"
#import "TGClient.h"
#import "TGAlertSheet.h"
#import "TGStyle.h"

@interface TGEnvironmentViewController ()
@property (nonatomic, copy) NSString *jsonText;
@property (nonatomic, copy) NSString *lastJson;
@property (nonatomic, copy) NSString *tag;
@property (nonatomic, assign) int32_t tagLevel;
@property (nonatomic, copy) NSString *logText;
@property (nonatomic, assign) double latitude;
@property (nonatomic, assign) double longitude;
@property (nonatomic, strong) NSArray *answerLines;
@end

@implementation TGEnvironmentViewController

- (instancetype)init {
	if ((self = [super init])){
		_jsonText = @"{\"hello\":\"world\"}";
		_tag = @"tdlib";
		_tagLevel = 1;
		_logText = @"LegacyTG environment check";
		_latitude = 50.4501;
		_longitude = 30.5234;
		_answerLines = @[@"Nothing read yet."];
	}
	return self;
}

- (void)viewDidLoad {
	[super viewDidLoad];
	self.title = @"TDLib Environment";
	[self rebuildSections];
}

- (void)rebuildSections {
	NSMutableArray *jsonRows = [NSMutableArray array];
	[jsonRows addObject:TGBAction(@"JSON Text",
			self.jsonText.length > 40
			? [[self.jsonText substringToIndex:37] stringByAppendingString:@"..."]
			: (self.jsonText.length ? self.jsonText : @"Set"), @"jsonText")];
	[jsonRows addObject:TGBAction(@"Parse JSON", nil, @"parseJson")];
	[jsonRows addObject:TGBAction(@"Serialise Last Value", nil, @"serialiseJson")];
	[jsonRows addObject:TGBAction(@"Theme Parameters JSON", nil, @"themeJson")];

	NSMutableArray *spaceRows = [NSMutableArray array];
	[spaceRows addObject:TGBAction(@"Load Time Zones", nil, @"timeZones")];
	[spaceRows addObject:TGBAction(@"Currency Exchange Rates", nil, @"currency")];

	NSMutableArray *weatherRows = [NSMutableArray array];
	[weatherRows addObject:TGBAction(@"Latitude",
			[NSString stringWithFormat:@"%.4f", self.latitude], @"latitude")];
	[weatherRows addObject:TGBAction(@"Longitude",
			[NSString stringWithFormat:@"%.4f", self.longitude], @"longitude")];
	[weatherRows addObject:TGBAction(@"Get Current Weather", nil, @"weather")];

	NSMutableArray *logRows = [NSMutableArray array];
	[logRows addObject:TGBAction(@"Log Verbosity", nil, @"logLevel")];
	[logRows addObject:TGBAction(@"Log Tags", nil, @"logTags")];
	[logRows addObject:TGBAction(@"Tag", self.tag.length ? self.tag : @"Set", @"tag")];
	[logRows addObject:TGBAction(@"Tag Verbosity",
			[NSString stringWithFormat:@"%d", (int)self.tagLevel], @"tagLevel")];
	[logRows addObject:TGBAction(@"Read Tag Verbosity", nil, @"readTagLevel")];
	[logRows addObject:TGBAction(@"Set Tag Verbosity", nil, @"writeTagLevel")];
	[logRows addObject:TGBAction(@"Log Stream", nil, @"logStream")];
	[logRows addObject:TGBAction(@"Use Default Stream", nil, @"defaultStream")];
	[logRows addObject:TGBAction(@"Write To File", @"tmp/legacytg.log", @"fileStream")];
	[logRows addObject:TGBAction(@"Log Text",
			self.logText.length > 36
			? [[self.logText substringToIndex:33] stringByAppendingString:@"..."]
			: self.logText, @"logText")];
	[logRows addObject:TGBAction(@"Add Log Message", nil, @"addLog")];

	NSMutableArray *diagRows = [NSMutableArray array];
	[diagRows addObject:TGBAction(@"Save Application Log Event", nil, @"saveEvent")];
	[diagRows addObject:TGBAction(@"Wait Three Seconds", nil, @"alarm")];

	NSMutableArray *answers = [NSMutableArray array];
	for (NSString *line in self.answerLines)
		[answers addObject:TGBInfo(line, nil)];

	self.sections = @[
		TGBSection(@"JSON", @"getJsonValue and getJsonString are TDLib's own "
				@"parser and writer; both can be called synchronously. The theme "
				@"string is the colour shape its payment and Web App pages use.",
				jsonRows),
		TGBSection(@"SPACE AND MONEY", @"Time zones for any schedule picker, and "
				@"the rates Telegram returns for USD.", spaceRows),
		TGBSection(@"WEATHER", @"Telegram's weather source for a point. Negative "
				@"latitudes and longitudes are the southern and western halves.",
				weatherRows),
		TGBSection(@"TDLIB LOG", @"Verbosity 1 is errors; 1024 is everything. A "
				@"device log that names the tag and level is easier to match "
				@"against the app's own lines.", logRows),
		TGBSection(@"DIAGNOSTICS", @"The two calls that can run before sign-in "
				@"and do not need a chat to exist.", diagRows),
		TGBSection(@"ANSWER", nil, answers),
	];
	[self rebuild];
}

- (void)finish:(BOOL)ok error:(NSString *)error title:(NSString *)title {
	self.answerLines = @[ok ? @"TDLib accepted the request."
						   : (error.length ? error : @"TDLib refused that.")];
	[self rebuildSections];
	if (!ok)
		[self showMessage:self.answerLines.firstObject title:title];
}

- (void)didChooseAction:(NSString *)action row:(NSDictionary *)row {
	__weak typeof(self) weakSelf = self;
	if ([action isEqualToString:@"jsonText"]){
		[self askText:@"JSON Text" message:nil placeholder:@"{\"a\":1}"
				 text:self.jsonText action:@"Save" completion:^(NSString *text){
			weakSelf.jsonText = text;
			[weakSelf rebuildSections];
		}];
	} else if ([action isEqualToString:@"parseJson"]){
		[[TGClient shared] jsonValueForText:self.jsonText
								 completion:^(NSDictionary *value, NSString *error){
			if (!value){
				[weakSelf finish:NO error:error title:@"JSON"];
				return;
			}
			weakSelf.lastJson = value[@"@type"] ?: @"jsonValue";
			weakSelf.answerLines = @[[NSString stringWithFormat:@"Parsed as %@.",
					weakSelf.lastJson]];
			[weakSelf rebuildSections];
			[weakSelf showMessage:[NSString stringWithFormat:@"TDLib parsed it as %@.",
					weakSelf.lastJson] title:@"JSON"];
		}];
	} else if ([action isEqualToString:@"serialiseJson"]){
		if (!self.lastJson.length){
			[self showMessage:@"Parse a value first; there is nothing to write."
						title:@"JSON"];
			return;
		}
		[[TGClient shared] jsonTextForValue:@{@"@type" : @"jsonValueString",
											 @"value" : self.jsonText}
								 completion:^(NSString *text, NSString *error){
			if (!text){
				[weakSelf finish:NO error:error title:@"JSON"];
				return;
			}
			weakSelf.answerLines = @[text];
			[weakSelf rebuildSections];
			[weakSelf showMessage:text title:@"JSON String"];
		}];
	} else if ([action isEqualToString:@"themeJson"]){
		NSDictionary *colours = @{
			@"backgroundColor" : @((int32_t)0xff000000),
			@"secondaryBackgroundColor" : @((int32_t)0xff1c1c1c),
			@"headerBackgroundColor" : @((int32_t)0xff000000),
			@"bottomBarBackgroundColor" : @((int32_t)0xff000000),
			@"sectionBackgroundColor" : @((int32_t)0xffffffff),
			@"sectionSeparatorColor" : @((int32_t)0xffe1e4e9),
			@"textColor" : @((int32_t)0xff222222),
			@"accentTextColor" : @((int32_t)0xff3d95d4),
			@"sectionHeaderTextColor" : @((int32_t)0xff696a6f),
			@"subtitleTextColor" : @((int32_t)0xff8d8e90),
			@"destructiveTextColor" : @((int32_t)0xffe53935),
			@"hintColor" : @((int32_t)0xff95999a),
			@"linkColor" : @((int32_t)0xff4cb3f5),
			@"buttonColor" : @((int32_t)0xff3d95d4),
			@"buttonTextColor" : @((int32_t)0xffffffff),
		};
		[[TGClient shared] themeParametersJSONString:colours
										  completion:^(NSString *text, NSString *error){
			if (!text){
				[weakSelf finish:NO error:error title:@"Theme JSON"];
				return;
			}
			weakSelf.answerLines = @[text];
			[weakSelf rebuildSections];
			[weakSelf showMessage:text title:@"Theme Parameters"];
		}];
	} else if ([action isEqualToString:@"timeZones"]){
		[[TGClient shared] timeZonesWithCompletion:^(NSArray *zones, NSString *error){
			if (error){
				[weakSelf finish:NO error:error title:@"Time Zones"];
				return;
			}
			NSMutableArray *lines = [NSMutableArray array];
			NSUInteger shown = MIN(zones.count, (NSUInteger)25);
			for (NSUInteger i = 0; i < shown; i++){
				NSDictionary *zone = zones[i];
				[lines addObject:[NSString stringWithFormat:@"%@  %@ (%@ s)",
						zone[@"id"], zone[@"name"], zone[@"offset"]]];
			}
			if (zones.count > shown)
				[lines addObject:[NSString stringWithFormat:@"... and %lu more",
						(unsigned long)(zones.count - shown)]];
			weakSelf.answerLines = lines.count ? lines : @[@"TDLib returned no zones."];
			[weakSelf rebuildSections];
			[weakSelf showMessage:[lines componentsJoinedByString:@"\n"]
							title:@"Time Zones"];
		}];
	} else if ([action isEqualToString:@"currency"]){
		[[TGClient shared] currencyExchangeRatesWithCompletion:^(NSArray *rates,
																 NSString *error){
			if (error){
				[weakSelf finish:NO error:error title:@"Exchange Rates"];
				return;
			}
			NSMutableArray *lines = [NSMutableArray array];
			NSUInteger shown = MIN(rates.count, (NSUInteger)25);
			for (NSUInteger i = 0; i < shown; i++){
				NSDictionary *rate = rates[i];
				[lines addObject:[NSString stringWithFormat:@"%@  %.4f",
						rate[@"currency"], [rate[@"rate"] doubleValue]]];
			}
			if (rates.count > shown)
				[lines addObject:[NSString stringWithFormat:@"... and %lu more",
						(unsigned long)(rates.count - shown)]];
			weakSelf.answerLines = lines.count ? lines : @[@"TDLib returned no rates."];
			[weakSelf rebuildSections];
			[weakSelf showMessage:[lines componentsJoinedByString:@"\n"]
							title:@"Exchange Rates"];
		}];
	} else if ([action isEqualToString:@"latitude"] || [action isEqualToString:@"longitude"]){
		BOOL latitude = [action isEqualToString:@"latitude"];
		[self askText:(latitude ? @"Latitude" : @"Longitude") message:nil
		  placeholder:(latitude ? @"50.4501" : @"30.5234")
				 text:[NSString stringWithFormat:@"%.4f",
					   latitude ? self.latitude : self.longitude]
			   action:@"Save" completion:^(NSString *text){
			double value = text.doubleValue;
			if (latitude)
				weakSelf.latitude = value;
			else
				weakSelf.longitude = value;
			[weakSelf rebuildSections];
		}];
	} else if ([action isEqualToString:@"weather"]){
		[[TGClient shared] currentWeatherAtLatitude:self.latitude
										  longitude:self.longitude
										 completion:^(NSDictionary *weather, NSString *error){
			if (error){
				[weakSelf finish:NO error:error title:@"Weather"];
				return;
			}
			NSString *line = [NSString stringWithFormat:@"%@  %.1f°",
					weather[@"emoji"] ?: @"", [weather[@"temperature"] doubleValue]];
			weakSelf.answerLines = @[line];
			[weakSelf rebuildSections];
			[weakSelf showMessage:line title:@"Current Weather"];
		}];
	} else if ([action isEqualToString:@"logLevel"]){
		[[TGClient shared] logVerbosityLevelWithCompletion:^(int32_t level, NSString *error){
			if (error){
				[weakSelf finish:NO error:error title:@"Log Verbosity"];
				return;
			}
			NSString *line = [NSString stringWithFormat:@"TDLib logs at %d.", (int)level];
			weakSelf.answerLines = @[line];
			[weakSelf rebuildSections];
			[weakSelf showMessage:line title:@"Log Verbosity"];
		}];
	} else if ([action isEqualToString:@"logTags"]){
		[[TGClient shared] logTagsWithCompletion:^(NSArray *tags, NSString *error){
			if (error){
				[weakSelf finish:NO error:error title:@"Log Tags"];
				return;
			}
			NSString *line = [tags componentsJoinedByString:@", "];
			if (!line.length)
				line = @"TDLib returned no tags.";
			weakSelf.answerLines = @[line];
			[weakSelf rebuildSections];
			[weakSelf showMessage:line title:@"Log Tags"];
		}];
	} else if ([action isEqualToString:@"tag"]){
		[self askText:@"Log Tag" message:nil placeholder:@"tdlib" text:self.tag
			   action:@"Save" completion:^(NSString *text){
			weakSelf.tag = text;
			[weakSelf rebuildSections];
		}];
	} else if ([action isEqualToString:@"tagLevel"]){
		[self askText:@"Tag Verbosity" message:@"1 to 1024"
		  placeholder:@"1" text:[NSString stringWithFormat:@"%d", (int)self.tagLevel]
			   action:@"Save" completion:^(NSString *text){
			weakSelf.tagLevel = (int32_t)MAX(1, MIN(text.intValue, 1024));
			[weakSelf rebuildSections];
		}];
	} else if ([action isEqualToString:@"readTagLevel"]){
		[[TGClient shared] logVerbosityForTag:self.tag
								   completion:^(int32_t level, NSString *error){
			if (error){
				[weakSelf finish:NO error:error title:@"Tag Verbosity"];
				return;
			}
			NSString *line = [NSString stringWithFormat:@"%@ logs at %d.",
					weakSelf.tag, (int)level];
			weakSelf.answerLines = @[line];
			[weakSelf rebuildSections];
			[weakSelf showMessage:line title:@"Tag Verbosity"];
		}];
	} else if ([action isEqualToString:@"writeTagLevel"]){
		[[TGClient shared] setLogVerbosityForTag:self.tag level:self.tagLevel
									  completion:^(BOOL ok, NSString *error){
			[weakSelf finish:ok error:error title:@"Tag Verbosity"];
		}];
	} else if ([action isEqualToString:@"logStream"]){
		[[TGClient shared] logStreamWithCompletion:^(NSDictionary *stream, NSString *error){
			if (error){
				[weakSelf finish:NO error:error title:@"Log Stream"];
				return;
			}
			NSString *line = stream[@"@type"] ?: @"unknown";
			if (stream[@"path"])
				line = [line stringByAppendingFormat:@"  %@", stream[@"path"]];
			weakSelf.answerLines = @[line];
			[weakSelf rebuildSections];
			[weakSelf showMessage:line title:@"Log Stream"];
		}];
	} else if ([action isEqualToString:@"defaultStream"]){
		[[TGClient shared] setLogStreamKind:@"default" path:nil
								 completion:^(BOOL ok, NSString *error){
			[weakSelf finish:ok error:error title:@"Log Stream"];
		}];
	} else if ([action isEqualToString:@"fileStream"]){
		[weakSelf askText:@"Log File" message:@"A path inside the app container."
			   placeholder:@"Documents/legacytg.log" text:nil action:@"Use"
			   completion:^(NSString *path){
			[[TGClient shared] setLogStreamKind:@"file" path:path
									 completion:^(BOOL ok, NSString *error){
				[weakSelf finish:ok error:error title:@"Log Stream"];
			}];
		}];
	} else if ([action isEqualToString:@"logText"]){
		[self askText:@"Log Text" message:nil placeholder:@"A line"
				 text:self.logText action:@"Save" completion:^(NSString *text){
			weakSelf.logText = text;
			[weakSelf rebuildSections];
		}];
	} else if ([action isEqualToString:@"addLog"]){
		[[TGClient shared] addLogMessage:self.logText level:1
							  completion:^(BOOL ok, NSString *error){
			[weakSelf finish:ok error:error title:@"Log Message"];
		}];
	} else if ([action isEqualToString:@"saveEvent"]){
		[[TGClient shared] saveApplicationLogEvent:@"legacytg_environment"
											chatId:0 data:self.jsonText
										completion:^(BOOL ok, NSString *error){
			[weakSelf finish:ok error:error title:@"Application Log Event"];
		}];
	} else if ([action isEqualToString:@"alarm"]){
		[[TGClient shared] alarmAfterSeconds:3.0 completion:^(BOOL ok, NSString *error){
			[weakSelf finish:ok error:error title:@"Alarm"];
		}];
	}
}

@end

// vim:ft=objc
