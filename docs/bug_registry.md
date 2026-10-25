# Bug Registry

The open bug queue for LegacyTG. Symptoms are reported in the owner's own
words, "Where to look" is what the audit found in the code. The quality bar
for closing any of these lives in
[acceptance_checklist.md](acceptance_checklist.md); the process rules
live in [CONTRIBUTING.md](../CONTRIBUTING.md).

Status vocabulary: **open** · *confirmed* (repro on another device) ·
*fix in progress* · **fixed** (with the regressing test named)

| # | Symptom (owner's own words) | Where to look | Status |
|---|---|---|---|
| B1 | The media grid became the stories grid — "they simply swapped" | `src/Controllers/TGProfileViewController+Media.m` — `selectedTabIsGrid`, `storyGridCellCache` | fixed (4797b90 queue side, 31d403f UI side; f0ddf51 crashed-device recursion fixed) — verify on device |
| B2 | Avatars/round thumbnails take longer than 30 s to load | `src/Core/TGClient+Files.m:24` `downloadFile:` — no `updateFile` handling | fixed (4797b90) — verify on device |
| B3 | Folders crash the app | `TGClient.m` updateChatFolders parser handed a formattedText dictionary as the title; UIKit's addButtonWithTitle: counted its length (crash named: `-[__NSCFDictionary length]`) | fixed (25c97cf parser, b3dcc8d popup UI) — verify on device |
| B4 | Instead of a real network status it says "long time ago" | chat header never reads `connectionState`; formatter at `src/Core/TGClient+Account.m:287` has no "yesterday" case | fixed (e940635) — verify on device |
| B5 | Gifts are not drawn like media/stories, and they have no icons | `src/Controllers/TGProfileViewController.m:407`, `:461` — text-only rows, no `downloadFile`, no glyph | fixed (c4fbf05 flatten `TGFlattenGift` + emoji glyph `TGGiftGlyph` in both render sites) — verify on device |
| B6 | Opening a chat from contacts: no avatar, and the title is out of place | `src/Controllers/TGContactsViewController.m:173` passes only `chatId`/`chatTitle`; the avatar waits for a photo from the chat cache | fixed (082cc56 — `privateChatWithUser` feeds the returned chat object into `mergeChat`) — verify on device |

---

## Facts observed during the first audit (findings, not fixes)

- **B1.** The media section reuses the story-grid component; `selectedTabIsGrid`
  matches only `kind == "stories"`. The single `storyGridCellCache` is shared by
  every tab and is not invalidated when `stories.count` changes.
- **B2.** `downloadFile:` sends one request and waits for a single response;
  TDLib reports progress through `updateFile`, which the client ignores. The
  45 s watchdog (`src/Core/TGClient+Files.m:67`) clears the waiter record, so a
  file that finishes after the timeout never notifies anyone — and the
  "requested" bookkeeping in the callers is filled forever, so no retry.
  `priority: 1` (lowest) means avatars sit behind grid media.
- **B3.** No unambiguous nil-deref found statically. Leading suspect: the
  `updateChatFolders` parser (`src/Core/TGClient.m:379-387`) subscripting
  `[@"text"]` — older tdjson builds used `title:string`, newer ones send
  `name:chatFolderName{formattedText}`; subscripting an `NSString` raises
  `unrecognized selector`. A device crash log from the actual tap is required
  to confirm. Defensive replacements (type-safe parsing, UIActionSheet →
  `TGPopupMenu`) can land without it.
- **B4.** The network status lands only in the chat-list title
  (`src/Controllers/TGChatListViewController.m:62` — which also overwrites a
  chosen folder's title). The chat and profile subtitles are built only from
  `userStatus` and never from `connectionState`/`updateUserStatus`. The last
  seen formatter also only knows "today": any older date (including yesterday)
  renders as "a long time ago", and `was_online == 0` falls into 1970.
- **B5.** `giftsForUser` (`src/Core/TGClient+Account.m:160-177`) keeps only
  `star_count` and a title that does not exist in the TDLib gift schema — every
  gift renders identically. The render branches never set `imageView.image`,
  never download the sticker file, and the `gift` glyph is a placeholder in
  `src/Views/TGIcons+Menu.m:421-424`.
- **B6.** `privateChatWithUser` returns a chat with no `chat_photo` yet; the
  chat controller opens with bare `chatId`/`chatTitle` while
  `buildAvatarButton` expects a photo from the chat cache, leaving an empty
  avatar slot and a title that visually misaligns.

## Cross-links

Donated by the audit; shared root causes define the fix order:

| Pair | Shared machinery | Strength |
|---|---|---|
| B1 + B2 | One download queue: everything goes `priority: 1`, the story grid fires ~20 downloads into it at once, and avatars starve behind the 45 s watchdog | **high** — fixing `TGClient+Files.m` (priority + timeout + `updateFile`) removes ~80% of both |
| B1 + B5 | One profile media pipeline (`currentMediaTabs` / grid / flatten): gifts never entered it, stories and media share one cache | medium — refactor in one pass |
| B4 | Same layer ("TDLib events never reach the UI"), but independent of the loader work | low |
| B3 | Own cause family (TDLib schema drift / deprecated UIActionSheet); shares nothing with the others | none |

Suggested fix order: `TGClient+Files.m` first (B1+B2 together), then the
status formatter (B4), the tab-kind fix (B1 UI side), gifts flatten (B5),
contacts `getChat` on open (B6), and B3 either after its crash log or as the
defensive variant immediately.
