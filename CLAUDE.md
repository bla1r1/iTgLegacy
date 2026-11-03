# LegacyTG — instructions for Claude

## Project in one sentence
Telegram client for iOS 6.0–12.5.7 on old hardware. Objective-C UI over TDLib (`libtdjson.dylib`), armv7 and arm64.

## Key files
- `src/Core/TGClient*.m` — TDLib bridge and all request logic
- `src/Core/TGClient.h` — umbrella: imports TGClientTypes.h, TGClientNotifications.h and one header per duty (TGClient+Messages.h, TGClient+Stickers.h, ...)
- `src/Core/TGStyle.h` — all sizes and metrics (no magic numbers anywhere else)
- `TGTheme+Colours` — all colours
- `src/App/` — app entry: main, AppDelegate, URL routing, dev bench
- `src/Media/` — decoders (WebP, WebM sticker video)
- `scripts/lint_tokens.sh` — fails on any hardcoded point size or colour in a screen
- `make -f tests/Makefile test` — host test suite (currently 1190 client and 167 call tests)
- `scripts/devrun.sh` — build, install, launch, log, screenshot on device

## Architecture rules
- UIKit stays in Objective-C. No C++ in `.h` files consumed by ViewControllers.
- Views never import `TGClient.h`. They ask the domain stores in `src/Core`
  (`TGStickerStore`, `TGMediaStore`); a store's header is the list of what
  the view may ask.
- Theme colours come from `TGTheme+Colours`. The exception is
  `TGStylePalette.h`: roles that never change with the theme (link,
  code-block) and the decorative icon-tile hues. They are declared once,
  in `TGStyle.m`, and stay out of the theme on purpose.
- Heavy processing (TDLib events, layout, audio) moves to C/C++. `.mm` files are thin adapters.
- No `NSNumber`/`NSDictionary` allocation inside TDLib update loops or cell layout.
- TDLib receive loop never calls `dispatch_async(main_queue)` per raw event — batch and coalesce.
- Internal cache ceiling on 32-bit: 16 MB. LRU eviction only.

## Testing — mandatory
- **Compile ≠ done.** A feature is done when it works on a real device, matches official Telegram behaviour, and has a passing regression test.
- Every fix ships with the test that **failed before the fix**.
- UI changes must be verified on at least one real device (4S or earlier for armv7, 5s+ for arm64).
- Device checks use `scripts/devrun.sh`. Log lines from TDLib (`updateNewMessage`, `updateFile`, `updateConnectionState`) are the ground truth.
- Components that can't be host-tested (UIKit lifecycle) → note the reason next to the checklist zone, fall back to devrun. Never just skip.

## Writing style — for docs and comments
- Write like a developer, not a product manager. No "comprehensive", "robust", "seamlessly", "cutting-edge", "leverage".
- No bullet-point soups for things that fit in a sentence.
- No "Executive Summary". No meta-sections explaining what the document is about.
- Numbers over vague words: "≤ 1 s", "16 MB", "12 ms" — not "quickly", "lightweight", "extensive".
- Comments explain *why*, not *what* the code does.

## Commit style
`fix(chat): …` / `feat(capabilities): …` — zone first. Bug IDs (`B1`–`Bn`) in the body when a bug closes. No bare "fix" or "some fixes".

## Device tiers (capability gating)
| Tier | Devices |
|---|---|
| Vintage | iPhone 3GS/4, iPod touch 4 — 256–512 MB, armv7, ≤ iOS 7 |
| Legacy | iPhone 4S/5/5c, iPod touch 5 — armv7, ≤ iOS 10 |
| Modern | iPhone 5s/6/6+, iPod touch 6 — first 64-bit, ≤ iOS 12.5 |
| Full | iPhone 6s+ — 2 GB+ |

Features gate by tier, not by iOS version. `Settings > This device` explains every missing button.
