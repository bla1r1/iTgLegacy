# LegacyTG

Read this in other languages: [Русский](README_RU.md)

Telegram client for iOS 6.0–12.5.7 on old hardware. Dual-engine: `libtg` (lightweight C MTProto) for 32-bit devices, `tdlib` for everything modern.

## Supported devices

| Build | Size | Target |
|---|---|---|
| armv7 | ~8.8 MB | iOS 6.0+ — iPhone 3GS/4/4S/5, iPad 2/3/4, iPod Touch 4/5 |
| arm64 | ~8.8 MB | iOS 7.0–12.5.7 — iPhone 5s–X, iPad Air/Pro |
| Universal | ~16 MB | Fat binary, both slices |

## Setup

Before building, configure your API credentials:

```bash
cp include/tg_config.h.example include/tg_config.h
```

Register at https://my.telegram.org → API development tools, then fill in `include/tg_config.h`:

```c
#define TG_API_ID   YOUR_API_ID
#define TG_API_HASH "YOUR_API_HASH"
```

`include/tg_config.h` is git-ignored.

## Repository layout

```
LegacyTG/
├── Makefile
├── src/
│   ├── Core/        # client, device logic
│   ├── Controllers/ # ViewControllers
│   ├── Views/       # UI components, cells
│   ├── Calls/       # VoIP & E2EE calls
│   └── Audio/       # voice notes
├── resources/       # Info.plist, fonts, entitlements
├── images/          # icons and assets
├── third_party/     # libtgvoip, opus, ogg, …
├── tdlib/           # TDLib (git submodule)
├── libs/            # prebuilt libs & WebP.framework
├── include/         # C headers, tg_config.h.example
├── compat/          # polyfills (dyld TLV, iOS 7 shims)
├── tools/           # host/device utilities
├── scripts/         # build & deploy scripts
├── tests/           # unit and integration tests
└── build/           # output (git-ignored)
```

## Building

Requirements: Xcode with iOS SDK, then:

```bash
brew install cmake gperf openssl@1.1 ccache
```

Clone and build:

```bash
git clone --recursive https://github.com/bla1r1/iTgLegacy.git
cd iTgLegacy
make
```

### Make targets

| Target | What it does |
|---|---|
| `make ipa` | All three packages (armv7, arm64, universal) |
| `make ipa-armv7` | 32-bit IPA for iOS 6.0+ |
| `make ipa-arm64` | 64-bit IPA for iOS 7.0–12.5.7 |
| `make app` | `.app` bundle only |
| `make deps` | Extract static libs into `build/libs` |
| `make tdlib` | Compile TDLib for iOS |
| `make clean` | Remove `build/` |

## Author & license

- **[bla1r1](https://github.com/bla1r1)** — author and maintainer
- **GPLv3** — see [LICENSE](LICENSE)

The project started from an early prototype by [@igkuzm](https://github.com/igkuzm) and was later rewritten from scratch — new engine (TDLib instead of `libtg`), new UIKit architecture, multimedia pipeline, E2EE calls.

> This software is for legacy hardware preservation and educational use. Use at your own risk.
