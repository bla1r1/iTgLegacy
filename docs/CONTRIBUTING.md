# Contributing to LegacyTG

LegacyTG is a Telegram client for iOS 6.0–12.5.7, built on TDLib (`libtdjson` loaded at runtime) with an Objective-C UI.

## What "done" means

A feature is **done** when its behaviour matches the official Telegram clients, verified by the checks in [docs/acceptance_checklist.md](docs/acceptance_checklist.md). If a zone has no checklist yet, write it before marking done.

Every check must say: what action is performed, what is on screen afterwards, how long to wait, and what's in the log (`scripts/devrun.sh`). Forbidden: "works", "looks fine", "doesn't crash for me".

Where a check needs a second party — calls, read receipts — it needs a second device or account.

## A fix ships with a failing test

The host suite (`make -f tests/Makefile test`) compiles real `src/` files against stubs in `tests/`. No Xcode needed.

- Every fix ships with the regression test that **failed before the fix**.
- A silent re-fix of something already done requires adding the checklist item that would have caught it.
- Components welded to UIKit lifecycle can't be host-tested — record that next to the zone checklist and use `scripts/devrun.sh` as the fallback. Don't just skip.

## Style tokens

Colours come from `TGTheme+Colours`. Sizes and metrics come from `src/Core/TGStyle.h`. Screens ask for a role (`TGFontRow()`, `TGMetricListAvatar`, etc.) and never write out a number.

`scripts/lint_tokens.sh` runs first in `make -f tests/Makefile test` and fails on any hardcoded point size or colour. New roles go into `TGStyle.h`, new colours into the palette.

The lint also tracks files still using `UIAlertView`/`UIActionSheet` instead of `TGSheet` — lower the ceiling as they migrate, never raise it.

## Bug queue

Every reported bug is a row in [docs/bug_registry.md](docs/bug_registry.md): the symptom verbatim, and where to look in code. It stays there until the closing fix names its regression test. The registry file is the source of truth; mirroring to GitHub Issues is fine.

## Commit style

Use conventional subjects: `fix(chat): …`, `feat(capabilities): …`. Include the bug ID (`B1`–`Bn`) in the message body when a bug closes.

## PR checklist

- [ ] `make -f tests/Makefile test` is green (currently 524 client and 164 call tests, 0 failed — raise the bar, never lower it)
- [ ] `sh scripts/lint_tokens.sh` is clean
- [ ] fix lands with the regression test that failed before it
- [ ] every behaviour claim is backed by a checklist line or a device log
- [ ] changed UI exercised on at least one Vintage/Legacy device if it touches a gated capability
