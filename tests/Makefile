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
    -I$(SRC)/UI \
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
    $(SRC)/Views/TGMessageLayout.mm \
    $(SRC)/Core/TGStyle.m

# Real TGClient sources, compiled only into the second binary: the main
# binary links a test stub of TGClient instead, which the call tests need.
CLIENT_OBJC_SRCS := \
    $(ROOT)/third_party/yyjson/yyjson.c \
    $(SRC)/Core/TGJson.m \
    $(SRC)/Core/TGClient.m \
    $(SRC)/Core/TGClient+Chats.mm \
    $(SRC)/Core/TGMessageStreamStore.mm \
    $(SRC)/Core/TGClient+Messages.m \
    $(SRC)/Core/TGClient+Stickers.m \
    $(SRC)/Core/TGClient+Files.m \
    $(SRC)/Core/TGStatusText.m \
    $(SRC)/Core/TGClient+Proxy.m \
    $(SRC)/Core/TGClient+Groups.m \
    $(SRC)/Core/TGClient+Downloads.m \
    $(SRC)/Core/TGClient+Secret.m \
    $(SRC)/Core/TGClient+Account.m \
    $(SRC)/Core/TGClient+Auth.m

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
    $(TESTS)/TGJsonTests.m \
    $(TESTS)/TGClientChatsTests.m \
    $(TESTS)/TGClientFilesTests.m \
    $(TESTS)/TGStatusTextTests.m \
    $(TESTS)/TGClientDraftsTests.m \
    $(TESTS)/TGClientFoldersTests.m \
    $(TESTS)/TGClientGroupsTests.m \
    $(TESTS)/TGMessageParserTests.m \
    $(TESTS)/TGClientAccountTests.m \
    $(TESTS)/TGClientComposeTests.m

TEST_BINARY := $(BUILD)/TGCallTests
CLIENT_BINARY := $(BUILD)/TGClientTests
SIM_BINARY := $(BUILD)/call_sim
OFFICIAL_SIM_BINARY := $(BUILD)/official_tgvoip_sim

OPUS := $(shell pkg-config --variable=prefix opus 2>/dev/null || echo /opt/homebrew/opt/opus)

LIBTGVOIP_SRCS := \
    $(ROOT)/third_party/libtgvoip/BlockingQueue.cpp \
    $(ROOT)/third_party/libtgvoip/Buffers.cpp \
    $(ROOT)/third_party/libtgvoip/CongestionControl.cpp \
    $(ROOT)/third_party/libtgvoip/EchoCanceller.cpp \
    $(ROOT)/third_party/libtgvoip/JitterBuffer.cpp \
    $(ROOT)/third_party/libtgvoip/MediaStreamItf.cpp \
    $(ROOT)/third_party/libtgvoip/MessageThread.cpp \
    $(ROOT)/third_party/libtgvoip/NetworkSocket.cpp \
    $(ROOT)/third_party/libtgvoip/OpusDecoder.cpp \
    $(ROOT)/third_party/libtgvoip/OpusEncoder.cpp \
    $(ROOT)/third_party/libtgvoip/PacketReassembler.cpp \
    $(ROOT)/third_party/libtgvoip/VoIPController.cpp \
    $(ROOT)/third_party/libtgvoip/VoIPServerConfig.cpp \
    $(ROOT)/third_party/libtgvoip/json11.cpp \
    $(ROOT)/third_party/libtgvoip/logging.cpp \
    $(ROOT)/third_party/libtgvoip/audio/AudioIO.cpp \
    $(ROOT)/third_party/libtgvoip/audio/AudioInput.cpp \
    $(ROOT)/third_party/libtgvoip/audio/AudioOutput.cpp \
    $(ROOT)/third_party/libtgvoip/audio/AudioIOCallback.cpp \
    $(ROOT)/third_party/libtgvoip/audio/Resampler.cpp \
    $(ROOT)/third_party/libtgvoip/os/posix/NetworkSocketPosix.cpp \
    $(ROOT)/third_party/libtgvoip/os/darwin/DarwinSpecific.mm \
    $(ROOT)/third_party/libtgvoip/video/ScreamCongestionController.cpp \
    $(ROOT)/third_party/libtgvoip/tests/MockReflector.cpp

# ─── targets ──────────────────────────────────────────────────────────────────

.PHONY: test build clean tokens sim official_sim

# The design-token lint. Cheap, so it runs first: a literal size or colour
# fails the suite the same way a broken assertion does.
tokens:
	@echo "\n════════ Design token lint ════════"
	@sh $(ROOT)/scripts/lint_tokens.sh

TEST_BINARY_DEPS := $(TESTS)/main.m $(C_SRCS) $(OBJC_SRCS) $(TEST_HELPER_SRCS) $(TEST_SRCS) \
                $(TESTS)/TGTestRunner.h $(TESTS)/TGCallTestHelpers.h
CLIENT_BINARY_DEPS := $(TESTS)/main_client.m $(CLIENT_OBJC_SRCS) $(CLIENT_HELPER_SRCS) \
                $(CLIENT_TEST_SRCS) $(TESTS)/TGTestRunner.h
SIM_BINARY_DEPS := $(TESTS)/call_sim.mm $(C_SRCS) $(OBJC_SRCS) $(TEST_HELPER_SRCS) \
                $(TESTS)/TGCallTestHelpers.h
OFFICIAL_SIM_DEPS := $(TESTS)/official_tgvoip_sim.mm $(LIBTGVOIP_SRCS)

test: tokens $(TEST_BINARY) $(CLIENT_BINARY)
	@echo "\n════════ Running call stack tests ════════"
	$(TEST_BINARY)
	@echo "\n════════ Running TGClient regression tests ════════"
	$(CLIENT_BINARY)

sim: $(SIM_BINARY)
	@echo "\n════════ Running VoIP call simulation (LegacyTG stack) ════════"
	$(SIM_BINARY)

official_sim: $(OFFICIAL_SIM_BINARY)
	@echo "\n════════ Running VoIP call simulation (Official libtgvoip) ════════"
	$(OFFICIAL_SIM_BINARY)

build: $(TEST_BINARY) $(CLIENT_BINARY) $(SIM_BINARY) $(OFFICIAL_SIM_BINARY)

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

$(SIM_BINARY): $(SIM_BINARY_DEPS)
	@mkdir -p $(BUILD)
	$(CLANG) $(CFLAGS) \
	    $(C_SRCS) \
	    $(OBJC_SRCS) \
	    $(TEST_HELPER_SRCS) \
	    $(TESTS)/call_sim.mm \
	    $(LDFLAGS) \
	    -o $@
	@echo "  Built $(notdir $@)"

$(OFFICIAL_SIM_BINARY): $(OFFICIAL_SIM_DEPS)
	@mkdir -p $(BUILD)
	$(CLANG) -std=c++14 \
	    -arch $(ARCH) \
	    $(if $(SDK),-isysroot $(SDK),) \
	    -DTGVOIP_USE_CALLBACK_AUDIO_IO \
	    -DTGVOIP_NO_DSP \
	    -DTGVOIP_NO_AEC \
	    -DWEBRTC_POSIX \
	    -I$(ROOT)/third_party/libtgvoip \
	    -I$(OPENSSL)/include \
	    -I$(OPUS)/include \
	    -I$(OPUS)/include/opus \
	    -L$(OPENSSL)/lib \
	    -L$(OPUS)/lib \
	    -lcrypto -lssl -lopus \
	    -lc++ \
	    -framework Foundation \
	    -framework CoreAudio \
	    -framework AudioToolbox \
	    $(LIBTGVOIP_SRCS) \
	    $(TESTS)/official_tgvoip_sim.mm \
	    -o $@
	@echo "  Built $(notdir $@)"

clean:
	@rm -rf $(BUILD)
	@echo "  Cleaned $(BUILD)"
