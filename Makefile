# ==============================================================================
# iTgLegacy - Makefile
# Clean, architecture-separated build pipeline for iOS (armv7 32-bit + arm64 64-bit)
#
# Directory Structure:
#   build/
#     ├── ipa/
#     │   ├── iTgLegacy-armv7.ipa   (32-bit for iPhone 4S / 5)
#     │   ├── iTgLegacy-arm64.ipa   (64-bit for iPhone 5s+)
#     │   └── iTgLegacy.ipa         (Universal fat package)
#     ├── armv7/
#     │   ├── libs/                 (32-bit OpenSSL, cURL, Opus static libs)
#     │   ├── tdlib/                (32-bit TDLib static libs & headers)
#     │   ├── obj/                  (32-bit object files)
#     │   └── app/                  (32-bit iTgLegacy.app bundle)
#     └── arm64/
#         ├── libs/                 (64-bit OpenSSL, cURL, Opus static libs)
#         ├── tdlib/                (64-bit TDLib static libs & headers)
#         ├── obj/                  (64-bit object files)
#         └── app/                  (64-bit iTgLegacy.app bundle)
# ==============================================================================

ROOT_DIR   := $(shell pwd)
BUILD_DIR  := $(ROOT_DIR)/build
MACHOFIX   := $(BUILD_DIR)/tools/machofix
IPA_DIR    := $(BUILD_DIR)/ipa

IPA_FILE   := $(IPA_DIR)/iTgLegacy.ipa
IPA_ARMV7  := $(IPA_DIR)/iTgLegacy-armv7.ipa
IPA_ARM64  := $(IPA_DIR)/iTgLegacy-arm64.ipa

# Compiler & Toolchain
XCODE_DEV   := /Applications/Xcode-beta.app/Contents/Developer
ifneq ($(wildcard $(XCODE_DEV)),)
  XCODE_CLANG := $(XCODE_DEV)/Toolchains/XcodeDefault.xctoolchain/usr/bin/clang
  XCODE_CXX   := $(XCODE_DEV)/Toolchains/XcodeDefault.xctoolchain/usr/bin/clang++
  XCODE_SDK   := $(XCODE_DEV)/Platforms/iPhoneOS.platform/Developer/SDKs/iPhoneOS.sdk
else
  XCODE_CLANG := $(shell which clang)
  XCODE_CXX   := $(shell which clang++)
  XCODE_SDK   :=
endif

SDK_PATH    := $(BUILD_DIR)/sdks/iPhoneOS15.6.sdk
ifeq ($(wildcard $(SDK_PATH)),)
  SDK_PATH  := $(BUILD_DIR)/sdks/iPhoneOS12.4.sdk
endif
ifeq ($(wildcard $(SDK_PATH)),)
  SDK_PATH  := $(BUILD_DIR)/sdks/iPhoneOS9.3.sdk
endif
ifeq ($(wildcard $(SDK_PATH)),)
  SDK_PATH  := $(XCODE_SDK)
endif

# C++ stdlib include path
ifneq ($(wildcard $(SDK_PATH)/usr/include/c++/v1),)
  CXX_STDLIB_INC := -stdlib=libc++
else ifneq ($(wildcard $(XCODE_SDK)/usr/include/c++/v1),)
  CXX_STDLIB_INC := -isystem $(XCODE_SDK)/usr/include/c++/v1
else
  CXX_STDLIB_INC := -stdlib=libc++
endif

CC  := $(shell command -v ccache 2>/dev/null) $(XCODE_CLANG)
CXX := $(shell command -v ccache 2>/dev/null) $(XCODE_CXX)

MIN_IOS   := -miphoneos-version-min=6.0

# Include Flags
INCLUDES  := -I$(ROOT_DIR)/include \
             -I$(ROOT_DIR)/src \
             -I$(ROOT_DIR)/src/ogg \
             -I$(ROOT_DIR)/src/ogg/ogg \
             -I$(ROOT_DIR)/src/opus/include \
             -I$(ROOT_DIR)/src/opus/include/opus \
             -I$(ROOT_DIR)/src/opusenc \
             -I$(ROOT_DIR)/src/opusfile \
             -I$(ROOT_DIR)/tdlib/td \
             -I$(ROOT_DIR)/tdlib/include \
             -I$(BUILD_DIR)/armv7/tdlib/include \
             -I$(BUILD_DIR)/arm64/tdlib/include

DEFINES   :=

WEBP_ARMV7 := -F$(ROOT_DIR)/src -framework WebP
WEBP_ARM64 := -lwebp

FRAMEWORKS := -framework UIKit -framework Foundation -framework QuickLook \
              -framework SystemConfiguration -framework CoreGraphics \
              -framework QuartzCore -framework MediaPlayer \
              -framework AVFoundation -framework AudioToolbox \
              -framework CoreMedia -framework AddressBook \
              -framework AddressBookUI -framework MobileCoreServices \
              -framework CoreLocation -framework MapKit \
              -framework CoreTelephony -framework CoreImage \


# TDLib is loaded at runtime from libtdjson.dylib, never linked.
# armv7 loads TDLib from a dylib and links none of it: static, its __TEXT goes
# past 19MB and a Thumb BL only reaches 16, which this linker cannot bridge.
# arm64 has no such limit, and no arm64 dylib was ever built - so it links the
# static libraries it already has. That is why this is per-architecture.
TDLIB_LIBS :=
# -u forces each entry point in even though nothing references it at link
# time: the app reaches TDLib through dlsym, so -dead_strip would otherwise
# throw the whole library away and leave a binary that links but cannot talk.
TDLIB_KEEP_ARM64 := -Wl,-u,_td_json_client_create -Wl,-u,_td_json_client_send \
                    -Wl,-u,_td_json_client_receive -Wl,-u,_td_json_client_execute \
                    -Wl,-u,_td_json_client_destroy
TDLIB_LIBS_ARM64 := $(TDLIB_KEEP_ARM64) \
                    -ltdjson_static -ltdjson_private -ltdclient -ltdcore \
                    -ltdapi -ltddb -ltdactor -ltdnet -ltdmtproto -ltdsqlite \
                    -ltde2e -ltdutils -ltdtl -lssl
# libcrypto: TDLib brings its own copy inside the dylib, but libtgvoip is
# linked into the app and needs AES and SHA here.
DEPS_LIBS  := -lopus -lstdc++ -lz -lcrypto

# ------------------------------------------------------------------------------
# Source Files
# ------------------------------------------------------------------------------
# libtgvoip - voice calls. Public domain (UNLICENSE), vendored because there is
# no armv7 iOS build of it anywhere. The WebRTC DSP is left out: TGVOIP_NO_DSP
# drops echo cancellation and noise suppression, which an A5 cannot afford and
# whose sources this fork does not fully carry anyway.
VOIP_SRC_CXX := \
	src/libtgvoip/VoIPController.cpp \
	src/libtgvoip/VoIPServerConfig.cpp \
	src/libtgvoip/logging.cpp \
	src/libtgvoip/json11.cpp \
	src/libtgvoip/video/ScreamCongestionController.cpp \
	src/libtgvoip/JitterBuffer.cpp \
	src/libtgvoip/OpusEncoder.cpp \
	src/libtgvoip/OpusDecoder.cpp \
	src/libtgvoip/NetworkSocket.cpp \
	src/libtgvoip/CongestionControl.cpp \
	src/libtgvoip/EchoCanceller.cpp \
	src/libtgvoip/MessageThread.cpp \
	src/libtgvoip/Buffers.cpp \
	src/libtgvoip/BlockingQueue.cpp \
	src/libtgvoip/MediaStreamItf.cpp \
	src/libtgvoip/PacketReassembler.cpp \
	src/libtgvoip/audio/AudioIO.cpp \
	src/libtgvoip/audio/AudioInput.cpp \
	src/libtgvoip/audio/AudioOutput.cpp \
	src/libtgvoip/audio/Resampler.cpp \
	src/libtgvoip/os/darwin/AudioUnitIO.cpp \
	src/libtgvoip/os/darwin/AudioInputAudioUnit.cpp \
	src/libtgvoip/os/darwin/AudioOutputAudioUnit.cpp \
	src/libtgvoip/os/posix/NetworkSocketPosix.cpp

VOIP_SRC_MM := \
	src/libtgvoip/os/darwin/DarwinSpecific.mm \
	src/TGCall.mm

VOIP_FLAGS := -DTGVOIP_NO_DSP -DWEBRTC_POSIX -DTGVOIP_USE_CUSTOM_CRYPTO \
              -I$(ROOT_DIR)/src/libtgvoip -Wno-everything

LIBTG_SRC_C :=

LIBTG_SRC_CXX :=

APP_SRC_M := \
	src/AppDelegate.m \
	src/RootViewController.m \
	src/main.m \
	src/TGClient.m \
	src/TGDevice.m \
	src/TGCapabilities.m \
	src/TGTheme.m \
	src/TGThemeFile.m \
	src/TGIcons.m \
	src/TGPopupMenu.m \
	src/TGSnackbar.m \
	src/TGSearchViewController.m \
	src/TGPlaceholderViewController.m \
	src/TGQRViewController.m \
	src/TGLoginViewController.m \
	src/TGChatListViewController.m \
	src/TGMessageLayout.m \
	src/TGBubbleCell.m \
	src/TGChatViewController.m \
	src/TGContactsViewController.m \
	src/TGTopicsViewController.m \
	src/TGForwardPicker.m \
	src/TGCallViewController.m \
	src/TGProfileViewController.m \
	src/TGEditProfileViewController.m \
	src/TGDeviceViewController.m \
	src/TGStorageViewController.m \
	src/TGSessionsViewController.m \
	src/TGSettingsViewController.m \
	src/TGVoiceDecoder.m \
	src/TGCallIce.m \
	src/TGCallStun.m \
	src/TGCallMessages.m \
	src/TGCallReflector.m \
	src/TGVoiceRecorder.m \
	src/opusenc/opusenc.m \
	src/UIImage+WebP.m \
	src/TGLottieView.m \
	src/TGMediaViewer.m \
	src/TGMusicPlayer.m \
	src/TGCallAudioEngine.m


APP_SRC_C := \
	src/tlv_polyfill.c \
	src/TGCallCrypto.c \
	src/opusfile/internal.c \
	src/opusfile/opusfile.c \
	src/opusfile/info.c \
	src/opusfile/stream.c \
	src/ogg/ogg/framing.c \
	src/ogg/ogg/bitwise.c \
	src/opusenc/opus_header.c \
	src/opusenc/picture.c \
	src/opusenc/diag_range.c

# Object mapping for armv7
ARMV7_OBJ_DIR := $(BUILD_DIR)/armv7/obj
ARMV7_LIBTG_OBJS := $(patsubst %.c,$(ARMV7_OBJ_DIR)/%.o,$(LIBTG_SRC_C)) \
                    $(patsubst %.cpp,$(ARMV7_OBJ_DIR)/%.o,$(LIBTG_SRC_CXX))
ARMV7_VOIP_OBJS  := $(patsubst %.cpp,$(ARMV7_OBJ_DIR)/%.o,$(VOIP_SRC_CXX)) \
                    $(patsubst %.mm,$(ARMV7_OBJ_DIR)/%.o,$(VOIP_SRC_MM))
ARMV7_APP_OBJS   := $(patsubst %.m,$(ARMV7_OBJ_DIR)/%.o,$(APP_SRC_M)) \
                    $(patsubst %.c,$(ARMV7_OBJ_DIR)/%.o,$(APP_SRC_C)) \
                    $(ARMV7_VOIP_OBJS)
ARMV7_ALL_OBJS   := $(ARMV7_LIBTG_OBJS) $(ARMV7_APP_OBJS)

# Object mapping for arm64
ARM64_OBJ_DIR := $(BUILD_DIR)/arm64/obj
ARM64_LIBTG_OBJS := $(patsubst %.c,$(ARM64_OBJ_DIR)/%.o,$(LIBTG_SRC_C)) \
                    $(patsubst %.cpp,$(ARM64_OBJ_DIR)/%.o,$(LIBTG_SRC_CXX))
ARM64_VOIP_OBJS  := $(patsubst %.cpp,$(ARM64_OBJ_DIR)/%.o,$(VOIP_SRC_CXX)) \
                    $(patsubst %.mm,$(ARM64_OBJ_DIR)/%.o,$(VOIP_SRC_MM))
ARM64_APP_OBJS   := $(patsubst %.m,$(ARM64_OBJ_DIR)/%.o,$(APP_SRC_M)) \
                    $(patsubst %.c,$(ARM64_OBJ_DIR)/%.o,$(APP_SRC_C)) \
                    $(ARM64_VOIP_OBJS)
ARM64_ALL_OBJS   := $(ARM64_LIBTG_OBJS) $(ARM64_APP_OBJS)

# Compiler Flags per Architecture
CFLAGS_ARMV7    := -arch armv7 -mthumb -O2 -isysroot $(SDK_PATH) $(MIN_IOS) $(INCLUDES) $(DEFINES) -fPIC \
                   -Wno-macro-redefined -Wno-implicit-function-declaration -Wno-incompatible-pointer-types -Wno-deprecated-declarations
OBJCFLAGS_ARMV7 := $(CFLAGS_ARMV7) -fobjc-arc
CXXFLAGS_ARMV7  := $(CFLAGS_ARMV7) $(CXX_STDLIB_INC) -std=c++11 -fno-use-cxa-atexit -fno-threadsafe-statics -Wno-error

CFLAGS_ARM64    := -arch arm64 -O2 -isysroot $(SDK_PATH) $(MIN_IOS) $(INCLUDES) $(DEFINES) -fPIC \
                   -Wno-macro-redefined -Wno-implicit-function-declaration -Wno-incompatible-pointer-types -Wno-deprecated-declarations
OBJCFLAGS_ARM64 := $(CFLAGS_ARM64) -fobjc-arc
CXXFLAGS_ARM64  := $(CFLAGS_ARM64) $(CXX_STDLIB_INC) -std=c++11 -fno-use-cxa-atexit -fno-threadsafe-statics -Wno-error

# ------------------------------------------------------------------------------
# Main Targets
# ------------------------------------------------------------------------------
.PHONY: all ipa ipa-armv7 ipa-arm64 clean help

all: ipa

deploy:
	@chmod +x scripts/deploy.sh
	@./scripts/deploy.sh

deploy-sync:
	@chmod +x scripts/deploy.sh
	@./scripts/deploy.sh --sync

deploy-full:
	@chmod +x scripts/deploy.sh
	@./scripts/deploy.sh --full

ipa: ipa-armv7 ipa-arm64
	@echo "[+] Packaging universal fat IPA $(IPA_FILE)..."
	@mkdir -p "$(IPA_DIR)" "$(BUILD_DIR)/fat_app/iTgLegacy.app"
	@cp -rf "$(BUILD_DIR)/arm64/app/iTgLegacy.app/"* "$(BUILD_DIR)/fat_app/iTgLegacy.app/"
	@lipo -create "$(BUILD_DIR)/armv7/app/iTgLegacy.app/iTgLegacy" "$(BUILD_DIR)/arm64/app/iTgLegacy.app/iTgLegacy" -output "$(BUILD_DIR)/fat_app/iTgLegacy.app/iTgLegacy"
	# The armv7 slice dlopens this; the arm64 slice has TDLib linked in and
	# ignores it. Packaging from the arm64 bundle alone left it out, and the
	# universal build installed on a 4S with no TDLib at all.
	@cp -f "$(BUILD_DIR)/armv7/app/iTgLegacy.app/libtdjson.dylib" "$(BUILD_DIR)/fat_app/iTgLegacy.app/" 2>/dev/null || echo "[!] no armv7 libtdjson.dylib to package"
	@codesign -s - --force "$(BUILD_DIR)/fat_app/iTgLegacy.app" 2>/dev/null || true
	@rm -rf "$(BUILD_DIR)/Payload"
	@mkdir -p "$(BUILD_DIR)/Payload"
	@cp -rf "$(BUILD_DIR)/fat_app/iTgLegacy.app" "$(BUILD_DIR)/Payload/"
	@cd "$(BUILD_DIR)" && zip -qr "$(IPA_FILE)" Payload
	@rm -rf "$(BUILD_DIR)/Payload" "$(BUILD_DIR)/fat_app"
	@echo ""
	@echo "================================================================="
	@echo "  [SUCCESS] All IPA packages built successfully!"
	@echo "  Universal : $(IPA_FILE)"
	@echo "  32-bit    : $(IPA_ARMV7)"
	@echo "  64-bit    : $(IPA_ARM64)"
	@echo "================================================================="

$(MACHOFIX): tools/machofix.c
	@mkdir -p "$(BUILD_DIR)/tools"
	cc -O2 -Wall -o $@ $<

ipa-armv7: $(MACHOFIX) $(ARMV7_ALL_OBJS)
	@echo "[+] Building 32-bit armv7 app bundle..."
	@mkdir -p "$(IPA_DIR)" "$(BUILD_DIR)/armv7/app/iTgLegacy.app"
	$(CC) -arch armv7 -isysroot $(SDK_PATH) $(MIN_IOS) -Wl,-dead_strip -ObjC -Wl,-pagezero_size,0x1000 \
		-L$(BUILD_DIR)/armv7/libs -L$(BUILD_DIR)/armv7/tdlib/lib -L$(ROOT_DIR)/src/opus/lib \
		$(ARMV7_ALL_OBJS) $(FRAMEWORKS) $(WEBP_ARMV7) $(TDLIB_LIBS) $(DEPS_LIBS) -o "$(BUILD_DIR)/armv7/app/iTgLegacy.app/iTgLegacy"
	@cp -f "$(ROOT_DIR)/src/Info.plist" "$(BUILD_DIR)/armv7/app/iTgLegacy.app/Info.plist" 2>/dev/null || true
	@cp -f "$(ROOT_DIR)/src/"*.ttf "$(BUILD_DIR)/armv7/app/iTgLegacy.app/" 2>/dev/null || true
	@cp -rf "$(ROOT_DIR)/images/"* "$(BUILD_DIR)/armv7/app/iTgLegacy.app/" 2>/dev/null || true
	@# TDLib rides along as its own image: statically linked it pushes __TEXT
	@# past the 16MB armv7 thumb branch limit. Built by scripts/build_tdlib_dylib.sh.
	@cp -f "$(BUILD_DIR)/armv7/tdlib/lib/libtdjson.dylib" "$(BUILD_DIR)/armv7/app/iTgLegacy.app/" 2>/dev/null || echo "[!] no libtdjson.dylib - run scripts/build_tdlib_dylib.sh"
	@echo "[+] Repairing armv7 Mach-O (__PAGEZERO, LC_MAIN, Thumb bits)..."
	$(MACHOFIX) "$(BUILD_DIR)/armv7/app/iTgLegacy.app/iTgLegacy"
	@ldid -S "$(BUILD_DIR)/armv7/app/iTgLegacy.app/iTgLegacy" 2>/dev/null || true
	@rm -rf "$(BUILD_DIR)/Payload" "$(IPA_ARMV7)"
	@mkdir -p "$(BUILD_DIR)/Payload"
	@cp -rf "$(BUILD_DIR)/armv7/app/iTgLegacy.app" "$(BUILD_DIR)/Payload/"
	@cd "$(BUILD_DIR)" && zip -qr "$(IPA_ARMV7)" Payload
	@rm -rf "$(BUILD_DIR)/Payload"

ipa-arm64: $(ARM64_ALL_OBJS)
	@echo "[+] Building 64-bit arm64 app bundle..."
	@mkdir -p "$(IPA_DIR)" "$(BUILD_DIR)/arm64/app/iTgLegacy.app"
	$(CC) -arch arm64 -isysroot $(SDK_PATH) $(MIN_IOS) -Wl,-dead_strip \
		-L$(BUILD_DIR)/arm64/libs -L$(BUILD_DIR)/arm64/tdlib/lib -L$(ROOT_DIR)/src/opus/lib \
		$(ARM64_ALL_OBJS) $(FRAMEWORKS) $(WEBP_ARM64) $(TDLIB_LIBS_ARM64) $(DEPS_LIBS) -o "$(BUILD_DIR)/arm64/app/iTgLegacy.app/iTgLegacy"
	@cp -f "$(ROOT_DIR)/src/Info.plist" "$(BUILD_DIR)/arm64/app/iTgLegacy.app/Info.plist" 2>/dev/null || true
	@cp -f "$(ROOT_DIR)/src/"*.ttf "$(BUILD_DIR)/arm64/app/iTgLegacy.app/" 2>/dev/null || true
	@cp -rf "$(ROOT_DIR)/images/"* "$(BUILD_DIR)/arm64/app/iTgLegacy.app/" 2>/dev/null || true
	@codesign -s - --force "$(BUILD_DIR)/arm64/app/iTgLegacy.app" 2>/dev/null || true
	@rm -rf "$(BUILD_DIR)/Payload" "$(IPA_ARM64)"
	@mkdir -p "$(BUILD_DIR)/Payload"
	@cp -rf "$(BUILD_DIR)/arm64/app/iTgLegacy.app" "$(BUILD_DIR)/Payload/"
	@cd "$(BUILD_DIR)" && zip -qr "$(IPA_ARM64)" Payload
	@rm -rf "$(BUILD_DIR)/Payload"

# ------------------------------------------------------------------------------
# Object Compilation Rules (32-bit armv7)
# ------------------------------------------------------------------------------
$(ARMV7_OBJ_DIR)/%.o: %.c
	@mkdir -p $(dir $@)
	$(CC) $(CFLAGS_ARMV7) -c $< -o $@

$(ARMV7_OBJ_DIR)/%.o: %.m
	@mkdir -p $(dir $@)
	$(CC) $(OBJCFLAGS_ARMV7) -c $< -o $@

$(ARMV7_OBJ_DIR)/src/libtgvoip/%.o: src/libtgvoip/%.cpp
	@mkdir -p $(dir $@)
	$(CXX) $(subst -std=c++11,-std=c++14,$(CXXFLAGS_ARMV7)) $(VOIP_FLAGS) -c $< -o $@

$(ARMV7_OBJ_DIR)/%.o: %.mm
	@mkdir -p $(dir $@)
	$(CXX) $(subst -std=c++11,-std=c++14,$(CXXFLAGS_ARMV7)) $(VOIP_FLAGS) -fobjc-arc -c $< -o $@

$(ARMV7_OBJ_DIR)/%.o: %.cpp
	@mkdir -p $(dir $@)
	$(CXX) $(CXXFLAGS_ARMV7) -c $< -o $@

# ------------------------------------------------------------------------------
# Object Compilation Rules (64-bit arm64)
# ------------------------------------------------------------------------------
$(ARM64_OBJ_DIR)/%.o: %.c
	@mkdir -p $(dir $@)
	$(CC) $(CFLAGS_ARM64) -c $< -o $@

$(ARM64_OBJ_DIR)/%.o: %.m
	@mkdir -p $(dir $@)
	$(CC) $(OBJCFLAGS_ARM64) -c $< -o $@

$(ARM64_OBJ_DIR)/src/libtgvoip/%.o: src/libtgvoip/%.cpp
	@mkdir -p $(dir $@)
	$(CXX) $(subst -std=c++11,-std=c++14,$(CXXFLAGS_ARM64)) $(VOIP_FLAGS) -c $< -o $@

$(ARM64_OBJ_DIR)/%.o: %.mm
	@mkdir -p $(dir $@)
	$(CXX) $(subst -std=c++11,-std=c++14,$(CXXFLAGS_ARM64)) $(VOIP_FLAGS) -fobjc-arc -c $< -o $@

$(ARM64_OBJ_DIR)/%.o: %.cpp
	@mkdir -p $(dir $@)
	$(CXX) $(CXXFLAGS_ARM64) -c $< -o $@

clean:
	@rm -rf "$(BUILD_DIR)/armv7" "$(BUILD_DIR)/arm64" "$(BUILD_DIR)/fat_app" "$(BUILD_DIR)/ipa" "$(BUILD_DIR)/Payload" "$(BUILD_DIR)/tools"

help:
	@echo "Available targets:"
	@echo "  make ipa         - Build universal fat IPA (armv7 + arm64)"
	@echo "  make ipa-armv7   - Build 32-bit armv7 IPA (for iPhone 4S / 5)"
	@echo "  make ipa-arm64   - Build 64-bit arm64 IPA (for iPhone 5s+)"
	@echo "  make clean       - Clean all build outputs"
