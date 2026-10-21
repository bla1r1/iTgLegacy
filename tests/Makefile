# tests/Makefile — build and run the iTgLegacy call-stack test suite.
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
    -I$(SRC) \
    -I$(SRC)/libtgvoip \
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
    -framework Foundation

# ─── sources ──────────────────────────────────────────────────────────────────

# Pure C (no ARC)
C_SRCS := $(SRC)/TGCallCrypto.c

# ObjC sources under test
OBJC_SRCS := \
    $(SRC)/TGCallStun.m \
    $(SRC)/TGCallMessages.m \
    $(SRC)/TGCallIce.m \
    $(SRC)/TGCallReflector.m \
    $(SRC)/TGCall.mm

# Test helper ObjC sources. TGClientStub and TGCallAudioEngineStub stand in
# for the iOS-only production classes that TGCall.mm would otherwise need.
TEST_HELPER_SRCS := \
    $(TESTS)/TGCallPeer.m \
    $(TESTS)/TGCallReflectorStub.m \
    $(TESTS)/TGClientStub.m \
    $(TESTS)/TGCallAudioEngineStub.m \
    $(TESTS)/TGAudioSessionShim.m \
    $(TESTS)/TGLibTgvoipBridge.mm

# Test files (included via main.m, not compiled separately)
TEST_SRCS := \
    $(TESTS)/TGCallCryptoTests.m \
    $(TESTS)/TGCallStunTests.m \
    $(TESTS)/TGCallMessagesTests.m \
    $(TESTS)/TGCallIceTests.m \
    $(TESTS)/TGCallReflectorTests.m \
    $(TESTS)/TGCallIntegrationTests.m \
    $(TESTS)/TGLibTgvoipHooksTests.m

TEST_BINARY := $(BUILD)/TGCallTests

# ─── targets ──────────────────────────────────────────────────────────────────

.PHONY: test build clean

test: $(TEST_BINARY)
	@echo "\n════════ Running call stack tests ════════"
	$(TEST_BINARY)

build: $(TEST_BINARY)

$(TEST_BINARY): $(TESTS)/main.m $(C_SRCS) $(OBJC_SRCS) $(TEST_HELPER_SRCS) $(TEST_SRCS) \
                $(TESTS)/TGTestRunner.h $(TESTS)/TGCallTestHelpers.h
	@mkdir -p $(BUILD)
	$(CLANG) $(CFLAGS) \
	    $(C_SRCS) \
	    $(OBJC_SRCS) \
	    $(TEST_HELPER_SRCS) \
	    $(TESTS)/main.m \
	    $(LDFLAGS) \
	    -o $@
	@echo "  Built $(notdir $@)"

clean:
	@rm -rf $(BUILD)
	@echo "  Cleaned $(BUILD)"
