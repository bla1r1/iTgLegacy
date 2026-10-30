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
| B6 | Opening a chat from contacts: no avatar, title misaligned | `src/Controllers/TGContactsViewController.m:173` passes only `chatId`/`chatTitle`; avatar waits for photo from chat cache | **fixed** (082cc56 — `privateChatWithUser` feeds returned chat into `mergeChat`) — verify on device |

---

## Audit findings (root causes, not yet closed)

**B1.** Media reuses the story-grid component; `selectedTabIsGrid` matches only `kind == "stories"`. One `storyGridCellCache` shared by all tabs, not invalidated when `stories.count` changes.

**B2.** `downloadFile:` sends one request and waits for a single response; TDLib reports progress through `updateFile`, which the client ignores. The 45 s watchdog (`src/Core/TGClient+Files.m:67`) clears the waiter record — a file that finishes after the timeout never notifies anyone. `priority: 1` (lowest) means avatars sit behind grid media.

**B3.** Leading suspect: `updateChatFolders` parser (`src/Core/TGClient.m:379–387`) subscripts `[@"text"]` on a `formattedText` dict. Older tdjson used `title:string`; newer sends `name:chatFolderName{formattedText}`. Subscripting an `NSString` raises unrecognized selector. Device crash log required to confirm. Defensive type-safe parsing and `UIActionSheet` → `TGPopupMenu` can land without it.

**B4.** Network status only in chat-list title (`src/Controllers/TGChatListViewController.m:62` — also overwrites a folder's title). Chat and profile subtitles built only from `userStatus`, never from `connectionState`. Last-seen formatter only knows "today" — any older date renders as "a long time ago"; `was_online == 0` falls into 1970.

**B5.** `giftsForUser` (`src/Core/TGClient+Account.m:160–177`) keeps only `star_count` and a title that doesn't exist in TDLib's gift schema. Render branches never set `imageView.image`, never download the sticker file; `gift` glyph is a placeholder in `src/Views/TGIcons+Menu.m:421–424`.

**B6.** `privateChatWithUser` returns a chat with no `chat_photo` yet; controller opens with bare `chatId`/`chatTitle` while `buildAvatarButton` expects a photo from the chat cache.

## Shared root causes

| Pair | Root | Fix order |
|---|---|---|
| B1 + B2 | One download queue, `priority: 1`, 45 s watchdog starves avatars | **High** — fix `TGClient+Files.m` (priority + timeout + `updateFile`) removes ~80 % of both |
| B1 + B5 | Same profile media pipeline (`currentMediaTabs` / grid / flatten) | Medium — refactor in one pass |
| B4 | Independent — "TDLib events never reach the UI" | Low |
| B3 | Independent — TDLib schema drift / deprecated UIActionSheet | None |

Suggested order: `TGClient+Files.m` (B1+B2), status formatter (B4), tab-kind fix (B1 UI), gifts flatten (B5), contacts `getChat` on open (B6), then B3 (after crash log or as defensive cleanup immediately).
