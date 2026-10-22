#import "TGLoginViewControllerInternal.h"

@implementation TGLoginViewController (Phone)

- (void)inputFieldChanged:(UITextField *)sender {
    if (self.currentStep != TGLoginStepPhone) return;
    NSString *text = sender.text;
    if ([text rangeOfString:@"+"].location != NSNotFound || (text.length >= 4 && [self containsKnownCountryPrefix:text])) {
        [self processPastedPhoneNumber:text];
    }
}

- (void)prefixFieldChanged:(UITextField *)sender {
    if (self.currentStep != TGLoginStepPhone) return;
    NSString *text = sender.text;
    if (![text hasPrefix:@"+"]) {
        text = [@"+" stringByAppendingString:[text stringByReplacingOccurrencesOfString:@"+" withString:@""]];
    }
    NSMutableString *clean = [NSMutableString string];
    for (NSUInteger i = 0; i < text.length; i++) {
        unichar c = [text characterAtIndex:i];
        if (c == '+' && clean.length == 0) {
            [clean appendString:@"+"];
        } else if (c >= '0' && c <= '9') {
            [clean appendFormat:@"%C", c];
        }
    }
    sender.text = clean;
}

- (BOOL)containsKnownCountryPrefix:(NSString *)digits {
    static NSSet *knownPrefixes = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        knownPrefixes = [NSSet setWithObjects:
            @"380", @"375", @"370", @"371", @"372", @"373", @"374", @"376", @"377", @"378",
            @"381", @"382", @"385", @"386", @"387", @"389", @"420", @"421", @"423", @"992",
            @"993", @"994", @"995", @"996", @"998", @"351", @"352", @"353", @"354", @"355",
            @"356", @"357", @"358", @"359", @"852", @"853", @"855", @"856", @"880", @"886",
            @"960", @"961", @"962", @"963", @"964", @"965", @"966", @"967", @"968", @"971",
            @"972", @"973", @"974", @"975", @"976", @"977",
            @"20", @"27", @"30", @"31", @"32", @"33", @"34", @"36", @"39", @"40",
            @"41", @"43", @"44", @"45", @"46", @"47", @"48", @"49", @"51", @"52",
            @"53", @"54", @"55", @"56", @"57", @"58", @"60", @"61", @"62", @"63",
            @"64", @"65", @"66", @"81", @"82", @"84", @"86", @"90", @"91", @"92",
            @"93", @"94", @"95", @"98", @"1", @"7", nil];
    });

    NSString *clean = [digits stringByReplacingOccurrencesOfString:@"\\D" withString:@"" options:NSRegularExpressionSearch range:NSMakeRange(0, digits.length)];
    if (clean.length >= 3 && [knownPrefixes containsObject:[clean substringToIndex:3]]) return YES;
    if (clean.length >= 2 && [knownPrefixes containsObject:[clean substringToIndex:2]]) return YES;
    if (clean.length >= 1 && [knownPrefixes containsObject:[clean substringToIndex:1]]) return YES;
    return NO;
}

- (void)processPastedPhoneNumber:(NSString *)raw {
    if (!raw.length) return;

    NSMutableString *cleaned = [NSMutableString string];
    for (NSUInteger i = 0; i < raw.length; i++) {
        unichar c = [raw characterAtIndex:i];
        if (c == '+' && cleaned.length == 0) {
            [cleaned appendString:@"+"];
        } else if (c >= '0' && c <= '9') {
            [cleaned appendFormat:@"%C", c];
        }
    }

    if ([cleaned hasPrefix:@"00"]) {
        [cleaned replaceCharactersInRange:NSMakeRange(0, 2) withString:@"+"];
    }

    if ([cleaned hasPrefix:@"0"] && ![cleaned hasPrefix:@"00"] && cleaned.length == 10) {
        self.inputField.text = [cleaned substringFromIndex:1];
        [self.inputField becomeFirstResponder];
        return;
    }

    NSString *digits = cleaned;
    BOOL hadPlus = [digits hasPrefix:@"+"];
    if (hadPlus) {
        digits = [digits substringFromIndex:1];
    }
    if (!digits.length) return;

    static NSSet *threeDigitCodes = nil;
    static NSSet *twoDigitCodes = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        threeDigitCodes = [NSSet setWithObjects:
            @"380", @"375", @"370", @"371", @"372", @"373", @"374", @"376", @"377", @"378",
            @"381", @"382", @"385", @"386", @"387", @"389", @"420", @"421", @"423", @"992",
            @"993", @"994", @"995", @"996", @"998", @"351", @"352", @"353", @"354", @"355",
            @"356", @"357", @"358", @"359", @"852", @"853", @"855", @"856", @"880", @"886",
            @"960", @"961", @"962", @"963", @"964", @"965", @"966", @"967", @"968", @"971",
            @"972", @"973", @"974", @"975", @"976", @"977", nil];

        twoDigitCodes = [NSSet setWithObjects:
            @"20", @"27", @"30", @"31", @"32", @"33", @"34", @"36", @"39", @"40",
            @"41", @"43", @"44", @"45", @"46", @"47", @"48", @"49", @"51", @"52",
            @"53", @"54", @"55", @"56", @"57", @"58", @"60", @"61", @"62", @"63",
            @"64", @"65", @"66", @"81", @"82", @"84", @"86", @"90", @"91", @"92",
            @"93", @"94", @"95", @"98", nil];
    });

    NSString *prefix = nil;
    NSString *rest = nil;

    if (digits.length >= 3 && [threeDigitCodes containsObject:[digits substringToIndex:3]]) {
        prefix = [digits substringToIndex:3];
        rest = [digits substringFromIndex:3];
    } else if (digits.length >= 2 && [twoDigitCodes containsObject:[digits substringToIndex:2]]) {
        prefix = [digits substringToIndex:2];
        rest = [digits substringFromIndex:2];
    } else if ([digits hasPrefix:@"1"] || [digits hasPrefix:@"7"]) {
        prefix = [digits substringToIndex:1];
        rest = [digits substringFromIndex:1];
    } else if (hadPlus) {
        NSUInteger pLen = MIN((NSUInteger)3, digits.length);
        prefix = [digits substringToIndex:pLen];
        rest = [digits substringFromIndex:pLen];
    } else {
        self.inputField.text = digits;
        return;
    }

    self.phonePrefixField.text = [NSString stringWithFormat:@"+%@", prefix];
    self.inputField.text = rest;
    [self.inputField becomeFirstResponder];
}

- (BOOL)textField:(UITextField *)textField shouldChangeCharactersInRange:(NSRange)range replacementString:(NSString *)string {
    if (self.currentStep == TGLoginStepPhone && string.length > 1) {
        NSString *existing = textField.text ?: @"";
        NSString *newText = [existing stringByReplacingCharactersInRange:range withString:string];
        [self processPastedPhoneNumber:newText];
        return NO;
    }
    return YES;
}

- (BOOL)textFieldShouldReturn:(UITextField *)textField {
    if (textField == self.phonePrefixField) {
        [self.inputField becomeFirstResponder];
        return YES;
    }
    [self actionButtonTapped];
    return YES;
}

@end
