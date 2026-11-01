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

#import "TGJsonTests.m"
#import "TGUpdateFilterTests.m"
#import "TGClientChatsTests.m"
#import "TGClientFilesTests.m"
#import "TGStatusTextTests.m"
#import "TGClientDraftsTests.m"
#import "TGClientFoldersTests.m"
#import "TGClientGroupsTests.m"
#import "TGMessageParserTests.m"
#import "TGClientAccountTests.m"
#import "TGClientProfileTests.m"
#import "TGClientComposeTests.m"
#import "TGClientBareTests.m"
#import "TGClientAuthFunctionsTests.m"
#import "TGClientStickerAuthoringTests.m"
#import "TGClientFileToolsTests.m"
#import "TGClientAutosaveContactsTests.m"
#import "TGClientThreadsTests.m"
#import "TGClientChatToolsTests.m"
#import "TGClientSearchLanguageTests.m"
#import "TGClientUsernamesTests.m"
#import "TGClientEmojiReactionsTests.m"
#import "TGClientAppearanceDiagnosticsTests.m"
#import "TGClientMiscTests.m"
#import "TGClientNotificationsForumTests.m"
#import "TGMessageStreamStoreTests.m"
#import "TGThemeFileTests.m"
#import "TGSVGPathTests.m"
#import "TGUpdatesTests.mm"
#import "TGP0MigrationTests.mm"
#import "TGP1MigrationTests.mm"
#import "TGStickerBudgetTests.m"
#import "TGStickerImageTests.m"
#import "TGClientMessagesFunctionsTests.m"

int main(int argc, char *argv[]) {
	@autoreleasepool {
		TGTestRunnerRun();
		return _tg_failed > 0 ? 1 : 0;
	}
}
