// tests/main.m — test runner entry point.
//
// Compiles all call-stack unit tests into a single binary and runs them
// using the minimal TGTestRunner shim (no Xcode required).
//
//   make -f tests/Makefile test
//   ./build/tests/TGCallTests
//
#import <Foundation/Foundation.h>
#import "TGTestRunner.h"

// Pull in every test class by importing their implementation files.
// (This is the simplest approach for a single-binary runner without a
//  build system that handles separate translation units per test file.)
#import "TGCallCryptoTests.m"
#import "TGCallStunTests.m"
#import "TGCallMessagesTests.m"
#import "TGCallIceTests.m"
#import "TGCallReflectorTests.m"
#import "TGCallIntegrationTests.m"
#import "TGLibTgvoipHooksTests.m"
#import "TGMessageLayoutTests.m"

int main(int argc, char *argv[]) {
    @autoreleasepool {
        TGTestRunnerRun();
        return _tg_failed > 0 ? 1 : 0;
    }
}
