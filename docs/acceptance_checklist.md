# Acceptance Checklist

A feature is **done** when its behaviour matches the official Telegram clients — not just because the button exists. Every item here says: what to tap, what should be on screen, how long to wait, what to find in the log.

Cross-links: [CONTRIBUTING.md](../CONTRIBUTING.md) · [bug_registry.md](bug_registry.md) · [feature_backlog.md](feature_backlog.md)

Token correctness (point sizes and colours) is checked by `scripts/lint_tokens.sh`, not by a row here.

---

## Hot zones

Zones that were fixed more than once. Column format: check — why it broke before (commit) — on-device test — host test.

### Chat rendering

| Check | Broke in | Device | Host |
|---|---|---|---|
| Long word (URL, hashtag) wraps instead of overflowing the bubble on 320 pt | f3c93c6 | Chat with 40+ char URL: wraps, background within screen, not clipped | Geometry test in `TGMessageLayout.m`: 60-char URL in 280 pt bubble ≠ one line |
| Cell height matches text height, including caption under album | 23cf757 | Album with long caption: not cut, gap ≤ 4 pt | `TGMessageLayout.m` fixture: measured height = computed height ± 1 pt |
| Typing indicator touches only header subtitle, never the feed | df4cc0e | Second account types: scroll position doesn't jump, last cell stays | Idempotence: same layout twice → same height |
| Reply strip stays visible; tap scrolls to quote and flashes it | eb30047 | Tap reply strip: feed scrolls, flashes, no artefacts on neighbours | Snapshot reply-strip attrs after `updateNewMessage`: attrs survive |
| Sender name colour is pinned to the sender, not random | f3c93c6 | 3+ member group, two senders in a row: second name doesn't stick to first bubble; colours repeat between runs | senderId → colour mapping in `TGIcons+Avatars.m`: stable across runs |
| Edited/ticks never overlap last text line | 8e4bed9 | 4S photo proof: Edited/timestamp never overlaps at any message length | Layout: text width + label width ≤ bubble width |

### Stickers and GIF panel

| Check | Broke in | Device | Host |
|---|---|---|---|
| Panel opens without freeze on A5; switching tabs ≤ 1 s | 9844356 | Tap panel: first stickers ≤ 1 s, tabs respond immediately | Rebuild test in `TGEmojiPanel.m`: 50-sticker fixture fits budget |
| Emoji and stickers are separate feeds | 9844356 | Tap each tab: content switches wholesale; mixed feed = fail | Fixture data → 3 sections; no item in two sections |
| Sticker sends on first tap; long press → favourites | 9844356 + eb30047 | Tap: sends; long press: favourite appears; survives restart | `getSavedAnimations` round-trip: write/read, order stable |
| GIF badge visible before and during playback | eb30047 | Open GIF: muted loop plays, badge visible | State test: playing/paused doesn't affect badge |
| WebP sticker decodes (not black square) | — | Install a sticker with real WebP: pixels visible | Decode fixture WebP through `UIImage+WebP.m`: non-zero pixels |
| Panel holds on 3.5" and 4" | f8344fe | 5s and 4S: grid holds, tabs not buried under keyboard | Panel metrics vs. two screen widths |
| No installed sticker sets doesn't crash the panel | — | Offline: recents strip shown, no crash | Fixture: no installed sets → recents shown |

### Chat list

| Check | Broke in | Device | Host |
|---|---|---|---|
| `getChats` doesn't block UI; list never left empty | 09c3880 | Cold start: first row ≤ 1 s, first screen ≤ 3 s on 4S | Model test: 200-chat fixture fits budget |
| `updateNewMessage` inserts at top; rest not resorted | — | Receive on second device with list open: row appears on top, no scroll jump | Insertion test: chat becomes first, all other positions unchanged |
| Unread badge matches server; reading clears exactly what was read | — | Read a chat on second account: badge clears identically on both, never over-clears | Counter model: mark-read decrements by amount read, not to zero |
| Paging down twice never returns a duplicate chat id | 09c3880 | Scroll to bottom twice: second page has no already-visible chat id | Dedupe test: same fixture page added twice → no duplicate |
| `updateNewChat`/`updateChatOrder` don't duplicate or drop rows | c64d473 | Second account creates group: one row, correct position | Merge test: repeat event for same chat_id → no second row |
| Preview shows draft, not last message | — | Leave draft, return to list: preview = draft; clear draft → last message | Preview model: draft overrides and lifts |
| Avatars don't reload on every list open | B2 | Open → leave → return: same chat avatars don't blink | Cache: pending/done bookkeeping reduces repeat downloads |

### Calls connectivity

| Check | Broke in | Device | Host |
|---|---|---|---|
| ICE completes on host/srflx candidates, not only relay | 4a5faed | Call over 3G: ICE → connected ≤ 15 s in devrun.sh log | `tests/TGCallIceTests.m` — two-component fixture |
| Reflector binding survives call-to-call | 43c88b6 | Two calls in a row: second keeps the binding | `tests/TGCallReflectorTests.m` |
| Incoming call doesn't crash | 1fd791c | Accept from another account: screen opens, holds ≥ 30 s | `tests/TGCallIntegrationTests.m` |
| `library_versions` reflects real compatibility | — | LegacyTG ↔ LegacyTG works; modern client refusal logged as known boundary | `tests/TGLibTgvoipHooksTests.m` |
| Audio session recovers after a call | a94da4a | Hang up after 30 s, play voice note: sound works | `tests/TGAudioSessionShim.m`: session deactivates on hangup |
| E2EE keys match on both devices | a94da4a | Compare fingerprints in both device logs: equal | `tests/TGCallCryptoTests.m` |
| No iOS 9+ API called in call path on iOS 6/7 | — | Cold call on 4S iOS 7.1.2: no unresolved selector crash | Host: iOS 9+ selectors only after class-availability check |

### Capability gating

| Check | Broke in | Device | Host |
|---|---|---|---|
| Every gate = device tier (Vintage/Legacy/Modern/Full), not iOS version | f822211, f8344fe | 3GS and 5s: Settings > This device lists match reality | `TGCapabilities.m` fixture: model id + RAM → expected gate values |
| `canAnimateInline` — 64-bit only | f822211, f8344fe | 5s: custom emoji animates; 4S: static glyph, no crash | Unit: model id → `canAnimateInline` |
| `canRunWebApps` — iOS 9+ | f822211 | iPhone 5 iOS 9: mini-app button shows; 4S iOS 7: hidden with reason | Unit: (iOS version, class) → gate |
| `canHoldMultipleAccounts` — ≥ 1 GB RAM | f822211 | 3GS: no account switcher; This device explains | Unit: RAM < 1 GB → off |
| Emoji glyph guard: missing glyph draws neither box nor hole | f8344fe | 4S iOS 6/7 emoji-heavy chat: no tofu | Font coverage table fixture |
| Gated-off UI has no empty areas | f8344fe | 4S where 5s would show GIF badge: text-only bubble, no gap | Fixture cell both states: height correct |
| This device reasons match features actually hidden | — | Every hidden feature has a matching reason in This device | Same reason string used in This device and at the hide site |

### Memory and sockets

| Check | Broke in | Device | Host |
|---|---|---|---|
| TDLib scheduler doesn't accumulate expired tasks | 2ab4bf6 | 4S background 5 min, return: answers; no request pile-up in log | Scheduler test with fake executor: queue doesn't grow |
| Lifetime timer releases wedged request | c64d473 | Offline 5 min, restore: requests resume, no stuck locks | Unit: fake timeout releases lock, next request executes |
| Memory doesn't grow scrolling media on Vintage | — | 3GS scroll 200 photos: never hits jetsam limit | Image cache: max retained size; far-away pages evict |
| Wi-Fi ↔ 3G handover loses nothing | — | Toggle Wi-Fi off/on with chat open: feed catches up ≤ 10 s | `updateConnectionState(reconnecting)` handler: auth survives, requests re-queue |
| No socket / request drumbeat in background | — | Background 1 min, return: updates arrive, no repeated requests in log | Fake network: backgrounding closes socket, return restores it |
| Large file doesn't block small downloads | — | Request voice note + video: voice note lands first | Download queue priority test in `TGClient+Files.m` |

---

## Testing: feature × device matrix

Run `scripts/devrun.sh` for device-side checks. Host suite: `make -f tests/Makefile test`.
