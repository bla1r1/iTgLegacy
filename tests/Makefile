# tests/Makefile — build and run the LegacyTG call-stack test suite.
#
# Works with only macOS Command Line Tools (no full Xcode required).
#
# Targets:
#   make -f tests/Makefile test        build + run unit tests
#   make -f tests/Makefile build       compile only
#   make -f tests/Makefile clean       remove build artefacts
#
# Requirements:
#   • macOS host (arm64 or x86_64)
#   • Xcode Command Line Tools: xcode-select --install
#   • Homebrew OpenSSL 3: brew install openssl@3

ROOT    := $(shell cd "$(dir $(lastword $(MAKEFILE_LIST))).." && pwd)
BUILD   := $(ROOT)/build/tests
SRC     := $(ROOT)/src
TESTS   := $(ROOT)/tests

OPENSSL := /opt/homebrew/opt/openssl@3
CLANG   := $(shell xcrun -f clang 2>/dev/null || echo clang)
SDK     := $(shell xcrun --sdk macosx --show-sdk-path 2>/dev/null)

ARCH    := $(shell uname -m)

CFLAGS  := \
    -arch $(ARCH) \
    $(if $(SDK),-isysroot $(SDK),) \
    -I$(TESTS)/shim \
    -I$(ROOT)/include \
    -I$(ROOT)/compat \
    -I$(SRC) \
    -I$(SRC)/Core \
    -I$(SRC)/Controllers \
    -I$(SRC)/Views \
    -I$(SRC)/Calls \
    -I$(SRC)/Audio \
    -I$(ROOT)/third_party \
    -I$(ROOT)/third_party/libtgvoip \
    -I$(TESTS) \
    -I$(OPENSSL)/include \
    -fobjc-arc \
    -fmodules \
    -O0 -g \
    -DDEBUG=1

LDFLAGS := \
    $(if $(SDK),-isysroot $(SDK),) \
    -L$(OPENSSL)/lib \
    -lcrypto \
    -lz \
    -lc++ \
    -framework Foundation \
    -framework AppKit

# ─── sources ──────────────────────────────────────────────────────────────────

# Pure C (no ARC)
C_SRCS := $(SRC)/Calls/TGCallCrypto.c

# ObjC sources under test
OBJC_SRCS := \
    $(SRC)/Calls/TGCallStun.m \
    $(SRC)/Calls/TGCallMessages.m \
    $(SRC)/Calls/TGCallIce.m \
    $(SRC)/Calls/TGCallReflector.m \
    $(SRC)/Calls/TGCall.mm \
    $(SRC)/Views/TGMessageLayout.m \
    $(SRC)/Core/TGStyle.m

# Real TGClient sources, compiled only into the second binary: the main
# binary links a test stub of TGClient instead, which the call tests need.
CLIENT_OBJC_SRCS := \
    $(SRC)/Core/TGClient.m \
    $(SRC)/Core/TGClient+Chats.m \
    $(SRC)/Core/TGClient+Messages.m \
    $(SRC)/Core/TGClient+Stickers.m \
    $(SRC)/Core/TGClient+Files.m \
    $(SRC)/Core/TGStatusText.m

# Test helper ObjC sources. TGClientStub and TGCallAudioEngineStub stand in
# for the iOS-only production classes that TGCall.mm would otherwise need.
# UIKitShim.m backs tests/shim/UIKit so real src that imports UIKit
# (TGMessageLayout, TGClientInternal) compiles on the host.
TEST_HELPER_SRCS := \
    $(TESTS)/TGCallPeer.m \
    $(TESTS)/TGCallReflectorStub.m \
    $(TESTS)/TGClientStub.m \
    $(TESTS)/TGCallAudioEngineStub.m \
    $(TESTS)/TGAudioSessionShim.m \
    $(TESTS)/TGLibTgvoipBridge.mm \
    $(TESTS)/shim/UIKit/UIKitShim.m

# Stand-ins around the real TGClient for the second binary (see
# TGClientTestSupport.m).
CLIENT_HELPER_SRCS := \
    $(TESTS)/shim/UIKit/UIKitShim.m \
    $(TESTS)/TGClientTestSupport.m

# Test files (included via main.m / main_client.m, not compiled separately)
TEST_SRCS := \
    $(TESTS)/TGCallCryptoTests.m \
    $(TESTS)/TGCallStunTests.m \
    $(TESTS)/TGCallMessagesTests.m \
    $(TESTS)/TGCallIceTests.m \
    $(TESTS)/TGCallReflectorTests.m \
    $(TESTS)/TGCallIntegrationTests.m \
    $(TESTS)/TGLibTgvoipHooksTests.m \
    $(TESTS)/TGMessageLayoutTests.m

CLIENT_TEST_SRCS := \
    $(TESTS)/TGClientChatsTests.m \
    $(TESTS)/TGClientFilesTests.m \
    $(TESTS)/TGStatusTextTests.m \
    $(TESTS)/TGClientDraftsTests.m

TEST_BINARY := $(BUILD)/TGCallTests
CLIENT_BINARY := $(BUILD)/TGClientTests

# ─── targets ──────────────────────────────────────────────────────────────────

.PHONY: test build clean tokens

# The design-token lint. Cheap, so it runs first: a literal size or colour
# fails the suite the same way a broken assertion does.
tokens:
	@echo "\n════════ Design token lint ════════"
	@sh $(ROOT)/scripts/lint_tokens.sh

TEST_BINARY_DEPS := $(TESTS)/main.m $(C_SRCS) $(OBJC_SRCS) $(TEST_HELPER_SRCS) $(TEST_SRCS) \
                $(TESTS)/TGTestRunner.h $(TESTS)/TGCallTestHelpers.h
CLIENT_BINARY_DEPS := $(TESTS)/main_client.m $(CLIENT_OBJC_SRCS) $(CLIENT_HELPER_SRCS) \
                $(CLIENT_TEST_SRCS) $(TESTS)/TGTestRunner.h

test: tokens $(TEST_BINARY) $(CLIENT_BINARY)
	@echo "\n════════ Running call stack tests ════════"
	$(TEST_BINARY)
	@echo "\n════════ Running TGClient regression tests ════════"
	$(CLIENT_BINARY)

build: $(TEST_BINARY) $(CLIENT_BINARY)

$(TEST_BINARY): $(TEST_BINARY_DEPS)
	@mkdir -p $(BUILD)
	$(CLANG) $(CFLAGS) \
	    $(C_SRCS) \
	    $(OBJC_SRCS) \
	    $(TEST_HELPER_SRCS) \
	    $(TESTS)/main.m \
	    $(LDFLAGS) \
	    -o $@
	@echo "  Built $(notdir $@)"

$(CLIENT_BINARY): $(CLIENT_BINARY_DEPS)
	@mkdir -p $(BUILD)
	$(CLANG) $(CFLAGS) \
	    $(CLIENT_OBJC_SRCS) \
	    $(CLIENT_HELPER_SRCS) \
	    $(TESTS)/main_client.m \
	    $(LDFLAGS) \
	    -o $@
	@echo "  Built $(notdir $@)"

clean:
	@rm -rf $(BUILD)
	@echo "  Cleaned $(BUILD)"
