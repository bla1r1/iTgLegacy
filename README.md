# iTgLegacy

Read this in other languages: [Русский](README_RU.md)

Telegram client tailored for legacy iOS devices running iOS 6.0 through iOS 12.5.7.

It uses a dual-engine architecture combining a lightweight C MTProto engine (`libtg`) for legacy 32-bit devices and the official Telegram Database Library (`tdlib`) for modern features.

## Supported Devices and Architectures

The project produces lightweight single-architecture IPA packages as well as a universal fat binary:

- **armv7 (32-bit, ~8.8 MB)**: Targeted at iOS 6.0+ (iPhone 3GS, iPhone 4, iPhone 4S, iPhone 5, iPad 2/3/4, iPod Touch 4/5).
- **arm64 (64-bit, ~8.8 MB)**: Targeted at iOS 7.0 - 12.5.7 (iPhone 5s through iPhone X, iPad Air/Pro).
- **Universal (~16 MB)**: Fat binary package containing both architecture slices.

## Telegram API Credentials

Before building for real use, configure your Telegram API credentials:

1. Copy [`include/tg_config.h.example`](include/tg_config.h.example) to `include/tg_config.h`:
   ```bash
   cp include/tg_config.h.example include/tg_config.h
   ```
2. Register your client at https://my.telegram.org (under *API development tools*).
3. Update `TG_API_ID` and `TG_API_HASH` in `include/tg_config.h`:

```c
#define TG_API_ID   YOUR_API_ID
#define TG_API_HASH "YOUR_API_HASH"
```

> Note: `include/tg_config.h` is git-ignored to prevent committing private API credentials.

## Repository Layout

```
iTgLegacy/
├── Makefile       # Master build file
├── README.md      # Documentation (English)
├── README_RU.md   # Documentation (Russian)
├── LICENSE        # GPLv3 License
├── src/           # iOS Objective-C source files
├── libtg/         # Native C MTProto Telegram engine
├── tdlib/         # Telegram Database Library (git submodule)
├── include/       # Third-party C header files and tg_config.h.example
├── images/        # Application assets and icons
├── scripts/       # Build automation scripts
└── build/         # Build outputs (git-ignored)
    ├── iTgLegacy-armv7.ipa # 32-bit IPA for iOS 6.0+ (8.8 MB)
    ├── iTgLegacy-arm64.ipa # 64-bit IPA for iOS 7.0-12.5.7 (8.8 MB)
    └── iTgLegacy.ipa       # Universal Fat IPA package (16 MB)
```

## Prerequisites

To build iTgLegacy on macOS:

1. Xcode installed with iOS SDK support.
2. Build dependencies:
   ```bash
   brew install cmake gperf openssl@1.1 ccache
   ```

## Building

Clone the repository with submodules and run `make`:

```bash
git clone --recursive https://github.com/bla1r1/iTgLegacy.git
cd iTgLegacy
make
```

Or run the wrapper script:

```bash
./scripts/build_ipa.sh
```

### Build Targets

- `make ipa` - Build all packages (`iTgLegacy-armv7.ipa`, `iTgLegacy-arm64.ipa`, and universal `iTgLegacy.ipa`).
- `make ipa-armv7` - Build lightweight 32-bit `.ipa` (8.8 MB for iOS 6.0+).
- `make ipa-arm64` - Build lightweight 64-bit `.ipa` (8.8 MB for iOS 7.0 - 12.5.7).
- `make app` - Build the `.app` bundle.
- `make deps` - Extract static third-party libraries into `build/libs`.
- `make tdlib` - Compile TDLib for iOS.
- `make clean` - Remove all intermediate build artifacts from `build/`.

## Author, History & License

- **Author & Maintainer**: [bla1r1](https://github.com/bla1r1)
- **License**: GNU General Public License v3.0 ([LICENSE](LICENSE))

### Project History & Acknowledgements
The project originally started based on an early prototype by Igor V. Sementsov ([@igkuzm](https://github.com/igkuzm)). During active development, that initial codebase was soon completely rewritten from scratch due to being technically obsolete (replacing the legacy unmaintained `libtg` engine with official `tdlib`, introducing an entirely new UIKit architecture, multimedia pipeline, and E2EE voice calls under GPLv3).

## Disclaimer

This software is provided for legacy hardware preservation and educational purposes. Use at your own risk.
