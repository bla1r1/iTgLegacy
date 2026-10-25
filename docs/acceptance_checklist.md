# Acceptance Checklist

The quality bar: a feature is not **done** because "the button exists" — it is
done when its behaviour matches the official Telegram clients. Every item here
is checkable: what is tapped, what is visible on screen, how long to wait,
what appears in the log. Complements `ROADMAP.md`: the roadmap records what
was attempted; this file records what counts as finished.

Process rules live in [CONTRIBUTING.md](../CONTRIBUTING.md). The open bug
queue lives in [bug_registry.md](bug_registry.md).

---

## Hot zones

Zones that were fixed repeatedly (fix-after-done is visible in git history).
Format: check — why it broke before (commit hint) — device check — host test.

### Chat rendering / wrapping

| Check | Why it broke before | On device | Host test |
|---|---|---|---|
| A long run of characters without spaces (URL, hashtag) wraps instead of overflowing the bubble on a 320 pt (3GS) screen | `Chat: Fix text word wrapping, group sender alignment, and media stamp ticks` (f3c93c6) | Open a chat with a 40+ char URL: the URL wraps, the bubble background stays within the screen, text is not clipped horizontally | Geometry test on `src/Views/TGMessageLayout.m` at boundary widths: a 60-char URL in a 280 pt bubble must not measure as one line |
| Cell height matches rendered text height, including a caption under an album | `feat(chat): add multi-select messages and caption layout fixes` (23cf757) | Open an album with a long caption: the caption is not cut, gap between caption and bubble bottom ≤ 4 pt | Run `src/Views/TGMessageLayout.m` on a fixture message with a caption: measured height matches computed height ± 1 pt |
| Typing indicator appearing/disappearing touches only the header subtitle, never the feed | `segmentation fault on bubbleview typing` (df4cc0e) | A second account types in the open chat: scroll position does not jump, the last cell does not slide off screen | Idempotence check: the same layout twice yields the same height (stable cell caching) |
| The reply strip stays visible; tapping it scrolls to the quoted message and flashes it | `fix(chat): reply strip that stays visible, sticker favourites, GIF badge` (eb30047) | Tap a reply strip: the feed scrolls to the quote and flashes; no leftover strip artefacts on the quote or neighbours afterwards | Snapshot of reply-strip attributes after a reflow from `updateNewMessage`: quote attributes survive |
| Sender name sits above the message and its colour is pinned to the sender — Telegram's palette, not a random one | f3c93c6 (group sender alignment) | In a 3+ member group, two messages from different senders in a row: the second name does not stick to the first bubble; colours repeat between runs | Test the senderId → colour mapping in `src/Views/TGIcons+Avatars.m`: stable across runs |
| Edited marks / ticks are visible and never overlap the last text line | `feat(ui): read ticks and run spacing rhythm` (8e4bed9) | Photo proof from a 4S: the Edited label / timestamp never overlaps the last line at any message length | Layout test: text width + label width never exceed the bubble width |

### Stickers and GIF panel

| Check | Why it broke before | On device | Host test |
|---|---|---|---|
| The panel opens without a freeze on an A5 (4S/5); switching emoji/stickers/GIF takes ≤ 1 s | `fix(stickers): one feed, working favourites, no freeze` (9844356) | Open a chat → tap the panel: first stickers appear ≤ 1 s; header buttons respond right after opening | Test the pure rebuild logic of `src/Views/TGEmojiPanel.m`: the first screen from a 50-sticker fixture fits the budget |
| Emoji and stickers are separate feeds, never blended | 9844356 ("one feed") | Tap through the emoji / stickers / GIF tabs: content switches wholesale; emoji glyphs mixed with stickers in one feed = fail | Structure test: fixture data splits into 3 sections; no item lands in two sections at once |
| A sticker sends on the first tap; long press adds it to favourites | 9844356 + eb30047 (sticker favourites) | Tap a sticker — it sends; long press — the favourite mark appears immediately; favourites survive an app restart | Round-trip favourites through `getSavedAnimations`: write/read a persisted list, order stable |
| The GIF badge (GIF/MOTION) is visible over the preview before and during playback | eb30047 (GIF badge) | Open a GIF: animation plays as a muted loop (`Power Saving` on, A5 and up — ROADMAP §2), badge visible during animation | State-coupling test: playing/paused does not affect badge presence |
| A WebP sticker decodes instead of rendering a black square | ROADMAP §2: the WebP category had to be rewritten, the file in the repo held only a header | Install a sticker with real WebP content: pixels are visible, not an empty rectangle | Decode a fixture WebP through `src/Views/UIImage+WebP.m`, pixels are non-zero |
| The panel layout holds on 3.5" and 4" portrait | the panel shipped before `fix(capabilities)` (f8344fe), which also repaired icon exports | Open the panel on a 5s (4") and a 4S (3.5"): the grid holds, tabs are not buried under the keyboard | Panel metrics against two fixture screen widths |
| No downloaded sticker sets does not break the panel | `Sticker sets: install, browse, favourites` — in progress in ROADMAP §2 | Offline: the panel shows the recents strip, not an empty view and not a crash | Fixture with no installed sets → UI shows recents |

### Dialogs loading / chat list

| Check | Why it broke before | On device | Host test |
|---|---|---|---|
| The first `getChats` does not block the UI; the list is never left empty | chat list migrated from libtg to TDLib (09c3880), then scattered fixes ("some fixes", "1") | Cold start while authorized: first row ≤ 1 s on a 4S, first screen ≤ 3 s | Host test of the list model: building the model from a 200-chat fixture fits the budget |
| A `updateNewMessage` inserts a row at the top; the rest of the order is not resorted | live updates — done in ROADMAP §1, followed by list repairs | Receive a message on a second device with the list open: the row appears on top, the scroll does not jump | Insertion test on the model: the chat becomes first, all other positions unchanged |
| The unread badge matches the server counter; reading clears exactly what was read | read receipts / unread badges were repaired after "done" | Read a chat on the second account: the badge clears identically on both devices, never over-clears | Counter model: mark-read decrements by exactly the amount read, not to zero |
| Paging down twice never returns a duplicate chat id | paging fixes after the 09c3880 migration | Scroll to the bottom twice: the second page does not return an already visible chat id | Dedupe test: the same fixture page added twice does not duplicate chat_id |
| `updateNewChat`/`updateChatOrder` neither duplicate rows nor lose chats | "close mutex fix; add queue lifetime timer" around the list model (c64d473) | On the second account create a group / write first — one row appears, in the right position | Merge test on the model: a repeat event for the same chat_id never creates a second row |
| A chat preview shows the draft, not the last message | draft persistence — done in ROADMAP §1 | Leave a draft in a chat, return to the list: preview = draft; clear the draft — preview returns to the last message | Preview model test: draft overrides the last message and lifts |
| Chat avatars/previews do not reload on every list open | today's avatar bug (B2 in bug_registry.md) | Open the list → leave → return: avatars of the same chats do not blink or clear | Cache layer test: download-task bookkeeping (pending/done) reduces repeat downloads |

### Calls connectivity

| Check | Why it broke before | On device | Host test |
|---|---|---|---|
| ICE checks pass on host/srflx candidates, not only relay | `Fix relay ICE component and add call tests` (4a5faed) | Call over 3G: in the `devrun.sh` log, ICE completes per media component to connected ≤ 15 s | Existing: `tests/TGCallIceTests.m` — fixture candidates with two components |
| The reflector binding survives from call to call | `feat: ICE connectivity checks, reflector binding, and touch injection` (43c88b6) | Call twice in a row between two accounts: the second call keeps the binding | Existing: `tests/TGCallReflectorTests.m` |
| An incoming call does not crash | `test: call integration suite (127/127 pass), incoming crash fix, and protocol compatibility` (1fd791c) | Accept a call from another account: the call screen opens, accept is tappable, the call holds ≥ 30 s | Existing: `tests/TGCallIntegrationTests.m` — incoming scenario |
| The `library_versions` announcement reflects real compatibility | ROADMAP "Blocked by the machine…": `library_versions: ["2.4.4"]` is rejected by modern clients today | LegacyTG ↔ LegacyTG calls work; the refusal of a modern client is logged as a known boundary | Existing: `tests/TGLibTgvoipHooksTests.m` — library_versions announcement hooks |
| The audio session recovers after a call | `feat: voice calls E2EE and connectivity fix, fast deploy, and UI polish` (a94da4a) | Hang up after 30 s and play a voice note without restarting: there is sound | Host test via `tests/TGAudioSessionShim.m`: the session deactivates on hangup |
| E2EE keys match on both devices | a94da4a, `src/Calls/TGCallCrypto.*` | Compare the key fingerprints in both device logs — equal | Existing: `tests/TGCallCryptoTests.m` |
| No iOS 9+ API is called in the call path on iOS 6/7 | ROADMAP §5: iOS 6 support in progress, "iOS 7-only calls are guarded" | Cold call on a 4S iOS 7.1.2: no crash from an unresolved selector/class | Host test: iOS 9+ selectors fire only after a class-availability check |

### Capability gating on old hardware

| Check | Why it broke before | On device | Host test |
|---|---|---|---|
| Every gate = device tier, not an iOS version (Vintage / Legacy / Modern / Full — ROADMAP §6) | `feat(capabilities): add animated sticker, wallpaper, inline, multi-account, and video call gates` (f822211), then `fix(capabilities): add emoji glyph guard, sticker/GIF flag gates, and icon exports` (f8344fe) — boundaries were redefined after "done" | On a 3GS (Vintage) and a 5s (Modern), open `Settings > This device`: the list of enabled gates and their reasons matches reality | Test of `src/Core/TGCapabilities.m`: fixture profiles (model id + RAM) → expected values of every gate |
| `canAnimateInline` — 64-bit only (A7+); 32-bit gets a static fallback, not a crash | f822211, then f8344fe | On a 5s custom emoji animates; on a 4S a static glyph shows and the app lives | Unit: model id → `canAnimateInline` (32-bit → off, 64-bit → on) |
| `canRunWebApps` — iOS 9 and up (WKWebView JavaScript) | f822211 | On a iPhone 5 iOS 9 the mini-app button shows; on a 4S iOS 7.1.2 it is hidden with a reason stated in This device | Unit: (iOS version, class availability) → gate |
| `canHoldMultipleAccounts` — needs 1 GB RAM or more | f822211; each TDLib client costs tens of megabytes | On a 3GS there is no account switcher; This device explains what it waits for | Unit: RAM < 1 GB → off, ≥ 1 GB → on |
| Emoji glyph guard: a glyph missing from this iOS system font draws neither a box nor a hole | f8344fe (emoji glyph guard) | On a 4S iOS 6/7 scroll an emoji-heavy chat: no tofu boxes or dropped glyphs in bubbles | Test the font coverage table: fixture (iOS version, glyph codes) → visibility |
| Turning a gate on changes the UI only where enabled — no empty areas in the gated-off view | fallout of f8344fe icon exports | On a 4S, where a 5s renders a GIF badge, the cell renders as a text-only bubble without gaps | Fixture cell rendered in both states; height correct in each |
| This device reasons never contradict the features actually hidden | ROADMAP §6 principle: "a missing button is explained rather than mysterious" | For every hidden feature a reason exists in This device and matches reality | Test: the same reason string is used in This device and at the UI hide site |

### Memory and sockets

| Check | Why it broke before | On device | Host test |
|---|---|---|---|
| The TDLib single-threaded scheduler does not accumulate expired tasks | `feat: TDLib single-threaded scheduler and remote login authorization` (2ab4bf6) | Park an authorized 4S in background for 5 min, return: the app answers; the log shows no pending-request pile-up | Host run of the scheduler on a fake executor: the queue does not grow with a blocked executor |
| The lifetime timer releases a wedged request (query mutex) | `query mutex fix; add queue lifetime timer` (c64d473) | Leave the app offline 5 min, restore the network: requests resume, no stuck locks in the log | Unit: a fake-timeout event releases the lock, the next request executes |
| Memory on a Vintage device does not grow without bound while scrolling media | "Blocked by the machine": 256–512 MB on Vintage | On a 3GS scroll 200 photo messages and measure footprint (Instruments or the `devrun.sh` log): never reaches the memory limit | Image cache test: a maximum retained size; far-away pages evict |
| Wi-Fi ↔ 3G handover loses neither authorization nor updates | historical tdjson fixes after the migration | Toggle Wi-Fi off/on with a chat open: after reconnect the feed catches up ≤ 10 s | Test of the `updateConnectionState(reconnecting)` handler: requests re-queue, authorization survives |
| The app holds no socket and no request drumbeat in the background | Push/Background fetch — out of scope in ROADMAP §5, so background time is short by design | Background 1 min, return: updates arrive, no accumulation of repeated requests in the log | Unit with a fake network: backgrounding closes the socket, returning restores it |
| A large file never blocks independent small downloads | `Download progress and cancel` — in progress in ROADMAP §2 (progress shown, no cancel) | Request a voice note and a video simultaneously: the voice note lands first; the small download is independent of the large one | Test of the download queue priority in `src/Core/TGClient+Files.m` |

---

## Testing

### On real devices: feature × device matrix

Base — the tier model from ROADMAP §6: a feature asks for its tier, not for an
iOS version. Rows = zones, columns = devices; filled in by actual runs.

| | iPhone 3GS (6/7, Vintage) | iPhone 4 (7, Vintage) | 4S (7, Legacy) | 5 (9, Legacy) | 5s (9/12, Modern) | X (12.5.7, Full) |
|---|---|---|---|---|---|---|
| Chat rendering/wrapping | | | | | | |
| Stickers/GIF panel | | | | | | |
| Dialogs loading | | | | | | |
| Calls connectivity | | | | | | |
| Capability gates | | | | | | |
| Memory/sockets | | | | | | |

What each device is for:

| Device | What it is enough to prove here |
|---|---|
| iPhone 3GS | Everything the gates allow; install via `tools/machofix.c` (armv7 branch); priority = memory and sockets |
| iPhone 4 | 3.5" sizing, Vintage gates; tier-duplicate of the 3GS |
| iPhone 4S | The workhorse: wrapping, calls (ICE over 3G), panel without freeze |
| iPhone 5 | The lower bound of `canRunWebApps` (iOS 9) |
| iPhone 5s | 64-bit arm64 slice, Modern tier gates |
| iPhone X | 64-bit with Premium; zoom behaviour of the latest UI paths |

Debug loop on a device: `scripts/devrun.sh` (build / install / launch / log /
screenshot). Crash logs are pulled by hand (ROADMAP §5) and symbolicated
locally — the symbols are ours because we build them. Syslog: `idevicesyslog`.

### Host tests

`make -f tests/Makefile test` runs the whole suite on the macOS host, no Xcode
required: tests compile the **real** `src/` files against stubs (`tests/shim/`,
`TGClientStub`), not copies. As of this writing: 173 passed, 0 failed
(127 legacy call-suite + 23 layout/entity/emoji + 23 dialogs-loading).

## Rule of process

See [CONTRIBUTING.md](../CONTRIBUTING.md). Summary: a fix without a host test
that failed before the fix is not a fix; a "done" without a reference to the
line of this checklist it was proven by stays *in progress*; every open bug
lives in [bug_registry.md](bug_registry.md) until closed.
