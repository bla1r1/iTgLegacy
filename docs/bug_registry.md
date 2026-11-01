# Bug Registry

Open bug queue for LegacyTG. Symptoms in the reporter's own words; "Where to look" is what the audit found. Quality bar for closing: [acceptance_checklist.md](acceptance_checklist.md). Process: [CONTRIBUTING.md](../CONTRIBUTING.md).

Status: **open** · *confirmed* (reproduced on another device) · *fix in progress* · **fixed** (regression test named)

| # | Symptom | Where to look | Status |
|---|---|---|---|
| B1 | The media grid became the stories grid — "they simply swapped" | `src/Controllers/TGProfileViewController+Media.m` — `selectedTabIsGrid`, `storyGridCellCache` | **fixed** (4797b90 queue, 31d403f UI, f0ddf51 recursion crash) — verify on device |
| B2 | Avatars/thumbnails take >30 s to load | `src/Core/TGClient+Files.m:24` `downloadFile:` — no `updateFile` handling | **fixed** (4797b90) — verify on device |
| B3 | Folders crash the app | `TGClient.m` `updateChatFolders` parser hands a `formattedText` dict as the title; `addButtonWithTitle:` calls `-length` on it → `-[__NSCFDictionary length]` | **fixed** (25c97cf parser, b3dcc8d popup UI) — verify on device |
| B4 | Network status shows "long time ago" instead of real state | `src/Core/TGClient+Account.m:287` has no "yesterday" case; header never reads `connectionState` | **fixed** (e940635) — verify on device |
| B5 | Gifts not drawn as media/stories, no icons | `src/Controllers/TGProfileViewController.m:407`, `:461` — text-only rows, no `downloadFile`, no glyph | **fixed** (c4fbf05 `TGFlattenGift` + `TGGiftGlyph`) — verify on device |
| B7 | Crash while scrolling the showcase chat on iOS 6.1.6 (iPod touch 4) | NSString's attribute-taking drawing and measuring (`drawInRect:withAttributes:`, `sizeWithAttributes:`, `boundingRectWithSize:options:attributes:context:`) answer `respondsToSelector:` with YES on 6.1.6 and then die inside `objc_msgSend` resolving the selector (EXC_BAD_ACCESS at 0x7761726c — the fault address is the selector slot, not the string) | **fixed** (`src/Core/TGTextDraw.m`, gated on `NSFoundationVersionNumber`) — device log says `text drawing: pre-7 (Foundation 993.00)`, scrolling to the audio cell still to confirm |
| B6 | Opening a chat from contacts: no avatar, title misaligned | `src/Controllers/TGContactsViewController.m:173` passes only `chatId`/`chatTitle`; avatar waits for photo from chat cache | **fixed** (082cc56 — `privateChatWithUser` feeds returned chat into `mergeChat`) — verify on device |
| B8 | A number Telegram wants an email for stays on the phone step for good | `src/Core/TGClient.m` `handleAuthState` returned early on `authorizationStateWaitEmailAddress` / `WaitEmailCode` | **fixed** (email steps; `TGClientAccountTests.testAuth_EmailStatesReachTheScreen`) — no account on the bench device to sign in with |
| B9 | "Unpin", "Unmute" and "Unarchive" in the chat list's hold menu open the delete confirmation | `src/Controllers/TGChatListViewController+Actions.m` `runChatAction:` matched `hasSuffix:@"Pin"` case-sensitively; "Unpin" ends in "pin" and fell through to delete | **fixed** (case-blind match) — UIKit menu, not host-testable; the showcase list has no pinned chat, so unconfirmed on device |
| B10 | Photos in a long chat stay blank after scrolling away and back | `src/Controllers/TGChatViewController+Media.m` kept a loaded id in `imagesRequested`, so an LRU-evicted photo was never fetched again | **fixed** (rows re-fetch; id cleared on load) — needs a signed-in chat with >12 photos |
| B11 | iOS 6: the app aborts on any undo snackbar, any hold menu, opening a profile, an empty list | `-[UIImageView setTintColor:]` is iOS 7; `TGSnackbar`, `TGPopupMenu`, the profile tiles and `TGEmptyView` set it unguarded (`unrecognized selector`, SIGABRT on the iPod touch 4) | **fixed** (`+[TGIcons tintImageView:colour:]` fills the glyph on 6) — snackbar, hold menu and profile checked on 6.1.6 |
| B12 | Log in with QR Code crashes the app on iOS 6 | `generateQRCodeForString:` set `inputCorrectionLevel` on `CIQRCodeGenerator`; iOS 6 has the filter without that key (`NSUnknownKeyException`) | **fixed** (only listed input keys are set) — QR drawn on 6.1.6 |
| B13 | Leaving the app on the iPod touch 4 kills it; the next open is a cold launch | Crash report `0xdead10cc`: "suspended with locked system files: td.binlog". Installed by SSH into `/Applications` (mobile_installation is broken on that device), its data is in `/var/mobile/Documents`, and TDLib holds the binlog lock while suspended | **fixed** — `TGClient -pauseForBackground:` sends `close` under a background task and frees the client; `-resumeFromBackground` starts a new one. On the iPod: closed in 2 s, no crash report after 20 s in the background, back on the same screen. Test: `testBackground_ClosesTDLibWithoutSigningOutTheScreens` |

---

## Audit findings (root causes, not yet closed)

**B1.** Media reuses the story-grid component; `selectedTabIsGrid` matches only `kind == "stories"`. One `storyGridCellCache` shared by all tabs, not invalidated when `stories.count` changes.

**B2.** `downloadFile:` sends one request and waits for a single response; TDLib reports progress through `updateFile`, which the client ignores. The 45 s watchdog (`src/Core/TGClient+Files.m:67`) clears the waiter record — a file that finishes after the timeout never notifies anyone. `priority: 1` (lowest) means avatars sit behind grid media.

**B3.** Leading suspect: `updateChatFolders` parser (`src/Core/TGClient.m:379–387`) subscripts `[@"text"]` on a `formattedText` dict. Older tdjson used `title:string`; newer sends `name:chatFolderName{formattedText}`. Subscripting an `NSString` raises unrecognized selector. Device crash log required to confirm. Defensive type-safe parsing and `UIActionSheet` → `TGPopupMenu` can land without it.

**B4.** Network status only in chat-list title (`src/Controllers/TGChatListViewController.m:62` — also overwrites a folder's title). Chat and profile subtitles built only from `userStatus`, never from `connectionState`. Last-seen formatter only knows "today" — any older date renders as "a long time ago"; `was_online == 0` falls into 1970.

**B5.** `giftsForUser` (`src/Core/TGClient+Account.m:160–177`) keeps only `star_count` and a title that doesn't exist in TDLib's gift schema. Render branches never set `imageView.image`, never download the sticker file; `gift` glyph is a placeholder in `src/Views/TGIcons+Menu.m:421–424`.

**B6.** `privateChatWithUser` returns a chat with no `chat_photo` yet; controller opens with bare `chatId`/`chatTitle` while `buildAvatarButton` expects a photo from the chat cache.

**B7.** Seven call sites used the iOS 7 attribute-taking NSString APIs. Three
had no gate at all (`TGIcons+Avatars.m` — the crash, every audio cell with
artwork; `TGTheme+Drawing.m` — the ON/OFF tag on every skeuomorphic switch,
so Settings was next; `TGChatViewController+Chrome.m`). The other four
(`TGGiftViewer.m`, `TGChatCell.m`, `TGAlertSheet.m`,
`TGLoginViewController+Steps.m`) gated on `respondsToSelector:` — and that
gate is worthless here: on 6.1.6 NSString answers YES and the send then
faults inside `objc_msgSend` while resolving the selector. The fault address
(0x7761726c) is the selector slot, not the receiver: the receiver answers
`length` two instructions earlier in the same frame. So the method is
declared in that UIKit without being usable, there is no exception to catch,
and the crash report names the call site and nothing else.

All seven now go through `TGLineTextSize` / `TGTextHeight` / `TGDrawText` in
`src/Core/TGTextDraw.m`, which ask `NSFoundationVersionNumber` once and log
which path they took. `TGMessageLayout.mm:388` stays as it is: that is
NSAttributedString's `boundingRectWithSize:options:context:`, which is iOS
6.0 and demonstrably works on the device.

**B15.** The decode burst class, second act. Two crashes, both
`SIGSEGV 0x0` on a background decode through `+[TGIcons decodedImage...]`:
(1) chat-list avatars during a real-account load — 20 instant `downloadFile`
requests decoded pool-free on one GCD thread until the process died
mid-list; (2) entering a profile — the profile photo decodes through
`decodedImageAtPath`'s `CGImageSourceCreateWithURL` branch
(`CopyPropertiesAtIndex`/`CreateThumbnailByIdx`) and died there on a real
photo. **fixed** — every decode goes through one gated, pooled entry
(`TGChatListViewController`'s 2-slot semaphore and the shared
`TGIconsDecodeGate` exported from `TGIcons.h`), `loadImageAtPath` and the
chat-canvas avatar path are both pooled, and `decodedImageAtPath` no longer
runs ImageIO-from-URL at all: it reads the file's bytes and decodes through
the data-provider path that survived 117 chats, with the decode page capped
at TGDECODE_MAX_PIXEL (1024) on a 256MB device. On the 4S: profile of a real
chat loads — history 59/59, `getChatPostedToChatPageStories` acknowledged, no
new crash report.

**B14.** Entering a real chat killed the app on the iPod touch 4 (6.1.6):
`TGFlattenMessage`'s voice-note branch called
`[[NSData alloc] initWithBase64EncodedString:options:]`, an iOS 7 selector the
6.1.6 runtime does not answer - `NSConcreteData` threw
"unrecognized selector" on the receive thread and the exception was fatal
(TGCall.mm's `base64EncodedStringWithOptions:` and key/tag decoders were
three more copies of the same). **fixed** — `src/Core/TGBase64.{h,m}`
gate both spellings on `instancesRespondToSelector:` and fall through to
the iOS 4-era `initWithBase64Encoding:`/`base64Encoding:`
(`TGBase64Decode`/`TGBase64Encode`). Every callsite uses them now:
waveform, call keys, peer tags, signalling. Test:
`testBase64Decode_RoundTripsBothPaths` (33-byte round trip, empty and nil
decode as empty answers, and the encoder round-trips). On the device the
message list of a voice-note-heavy chat loads clean — 59 messages,
no exception.

## Shared root causes

| Pair | Root | Fix order |
|---|---|---|
| B1 + B2 | One download queue, `priority: 1`, 45 s watchdog starves avatars | **High** — fix `TGClient+Files.m` (priority + timeout + `updateFile`) removes ~80 % of both |
| B1 + B5 | Same profile media pipeline (`currentMediaTabs` / grid / flatten) | Medium — refactor in one pass |
| B4 | Independent — "TDLib events never reach the UI" | Low |
| B3 | Independent — TDLib schema drift / deprecated UIActionSheet | None |

Suggested order: `TGClient+Files.m` (B1+B2), status formatter (B4), tab-kind fix (B1 UI), gifts flatten (B5), contacts `getChat` on open (B6), then B3 (after crash log or as defensive cleanup immediately).
