// tests/main_client.m — entry point of the TGClientTests regression binary.
//
// A second executable, because the main TGCallTests binary links a test
// stub for TGClient (the call tests record signalling by watching it),
// while these suites compile the real src/Core/TGClient.m. One cannot
// carry both the stub and the real class.
//
//   make -f tests/Makefile test
#import <Foundation/Foundation.h>
#import "TGTestRunner.h"

#import "TGClientChatsTests.m"

int main(int argc, char *argv[]) {
	@autoreleasepool {
		TGTestRunnerRun();
		return _tg_failed > 0 ? 1 : 0;
	}
}
