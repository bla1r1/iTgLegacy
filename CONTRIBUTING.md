# Contributing to LegacyTG

LegacyTG is a Telegram client for legacy iOS 6.0–12.5.7 devices, built on
TDLib (`libtdjson` loaded at runtime) with an Objective-C UI. This file is the
process contract. The quality bar itself lives in
[docs/acceptance_checklist.md](docs/acceptance_checklist.md); the open bug
queue lives in [docs/bug_registry.md](docs/bug_registry.md).

## The rule that produced this file

Roughly half the commits in this repository are fixes. Most of them fixed
something that was already marked done. The cause: "done" meant "the button
exists in the UI". It means something better now.

## 1 · What "done" means

A feature is **done** when its behaviour matches the official Telegram
clients, proven by the checks of its zone in
[docs/acceptance_checklist.md](docs/acceptance_checklist.md) — not merely
because the control exists. If a zone has no checklist yet, the checklist is
written before the feature is marked done.

Every check is a verifiable statement, in one of these forms:

- which action is performed (tap, long press, swipe; where, how many times);
- what is visibly on screen afterwards (a concrete element: a row, an inset,
  an icon, a text — described, never "renders correctly");
- how long to wait, and what must have happened within that time
  (≤ 1 s, ≤ 3 s, 5 min — numbers, not "quickly");
- what must be in the log (`scripts/devrun.sh` captures the device log,
  where TDLib events such as `updateNewMessage`, `updateChatReadOutbox`,
  `updateConnectionState`, `updateFile` are readable).

**Forbidden formulations for done:** "works", "looks fine", "rendering is the
same", "does not crash for me". Only what another person on another device
can reproduce with the same result.

**Independent verification.** Where the behaviour needs a second side —
calls, incoming messages, read receipts — the check needs a second device or
account.

## 2 · A fix is not a fix without a falling test

The host suite (`make -f tests/Makefile test`, macOS, no Xcode needed)
compiles the real `src/` files against the stubs in `tests/`.

- Every fix ships with the regression test that **failed before the fix**
  (for a legacy bug, the test added now must fail on current `src/`).
- A "silent re-fix" of something already done requires adding the checklist
  item that would have caught that regression.
- If a component cannot be host-tested because it is welded to the UIKit
  lifecycle, that fact is recorded next to the zone checklist with the reason
  (see the stickers panel note in the checklist) — the fallback is a device
  run through `scripts/devrun.sh`, not a skipped test.

## 2a · One size, one place

Colour comes from `TGTheme+Palette`; type and metrics come from
`src/Core/TGStyle.h`. A screen asks for the role — `TGFontRow()`,
`TGFontCaption()`, `TGMetricListAvatar` — and never writes the number. That is
why the app drifted in the first place: the palette existed and the type scale
did not, so every screen picked its own size.

`scripts/lint_tokens.sh` runs as the first step of `make -f tests/Makefile
test` and fails the suite on a point size or a colour written out in a screen.
A new role goes into `TGStyle.h`; a new colour goes into the palette. The lint
also holds a ceiling on files still using `UIAlertView`/`UIActionSheet` instead
of `TGSheet` — lower it as they move over, never raise it.

## 3 · Where a bug lives

Every reported bug is a row in
[docs/bug_registry.md](docs/bug_registry.md): the owner's symptom, verbatim,
plus where the audit looks in the code. It stays there until the closing fix
names its regressing test. Mirroring rows into GitHub Issues is welcome; the
registry file is the source of truth.

Crash logs are pulled from the device by hand (ROADMAP §5) and symbolicated
locally — the symbols are ours because we build them.

## 4 · Commit style

History so far uses conventional subjects for later work (`fix(chat): …`,
`feat(capabilities): …`) and deserves it everywhere: zone, "feat", not a bare
"fix"/"some_fixes". The issue or bug ID (`B1`–`Bn`) goes in the message where a
bug closes.

## 5 · PR checklist

Before a PR counts as ready:

- [ ] `make -f tests/Makefile test` is green (currently 207 passed, 0 failed —
      raise the bar, never lower it)
- [ ] `sh scripts/lint_tokens.sh` is clean — no hand-written size or colour
- [ ] a fix lands with the regression test that failed before it
- [ ] every behaviour claim is backed by a checklist line or a device log
- [ ] changed UI is exercised on at least one Vintage/Legacy device if it
      touches a gated capability (tier model — ROADMAP §6)
- [ ] `git log --pretty=%s` would still read as a project, not a diary
