# Feature Backlog

What the app can't do, derived from TDLib — not from manually walking the official client.

`tdlib/td/td/generate/scheme/td_api.tl` declares every function the protocol offers. The ones this app never names are exactly what it can't do:

```sh
sh scripts/tdlib_coverage.sh            # counts and gap by area
sh scripts/tdlib_coverage.sh --relevant # missing and worth having
sh scripts/tdlib_coverage.sh --skipped  # missing on purpose
```

As of 2026-10-26: **1076 functions declared, 197 called (18%).** 501 of the 879 never-called are out of scope; 378 are wanted.

The counter reads string literals in `src/` and intersects with `td_api` names — every number here is a floor. Where this file and ROADMAP.md disagree, the roadmap wins — it knows the device.

---

## Tier 0 — visibly broken without it

| Area | What was missing | Functions | Status |
|---|---|---|---|
| Typing | App showed "typing…" but never sent it | `sendChatAction` | **done** — one report per 4 s while composing |
| Drafts | Draft from another device shown; local draft never saved | `setChatDraftMessage` | **done** — saved on leave, restored on open, cleared on send |
| Reactions | Reaction could be put on but never removed | `removeMessageReaction` | **done** — held-message menu offers remove |
| Read state | Voice/video notes never marked opened | `openMessageContent` | **done** — sent on playback start |
| Failed sends | No retry on a failed message | `resendMessages` | **done** — Retry row on failed message |
| Pinning | Could read pinned; couldn't pin | `pinChatMessage`, `unpinChatMessage` | **done** — Pin/Unpin in message menu |
| Mentions | Mention/reaction badges never cleared | `readAllChatMentions`, `readAllChatReactions` | **done** — both sent on chat open |
| Chat list | Chat couldn't be marked unread | `toggleChatIsMarkedAsUnread` | **done** — Mark as Unread/Read on held row |
| Links | No way to copy a link to a message | `getMessageLink` | **done** — Copy Link in message menu |
| Contacts | Read-only; couldn't add | `addContact` | **done** — new contact form from contacts (+) and action bar |
| Replies | Reply quote couldn't be jumped to | `getRepliedMessage`, `getMessages`, `getMessageProperties` | **done** — tap quote → jump + fetch if needed |
| Editing | Only text editable; captions and media weren't | `editMessageCaption`, `editMessageMedia` | **done** — Edit row for media with caption |
| Sending | Multiple photos sent as separate messages | `sendMessageAlbum` | **done** — hold tile → multi-select → send as album |
| Search | Only searched what was already loaded | `searchChats`, `searchChatsOnServer`, `searchPublicChats`, `searchContacts` | **done** — local-first, deduplicated, with Contacts section |
| Formatting | Bold/italic rendered on receive; couldn't send | `parseTextEntities` | **done** — `*bold*`, `_italic_`, `` `code` `` parsed through TDLib; `getMarkdownText` fills the composer on Edit |
| Link previews | Pasted link got no preview; t.me links read manually | `getLinkPreview`, `getInternalLinkType` | **done** — composer shows preview on settle; t.me asks Telegram |
| Downloads | No cancel, no delete | `cancelDownloadFile`, `deleteFile`, `getFile` | **done** — Settings → Downloads with pause/cancel/remove |
| Push | App asked iOS for nothing, handed Telegram nothing | `registerDevice`, `processPushNotification` | **done** — token registered on sign-in; live notifications go to TDLib. Needs cert from `docs/howto_push_cert.md` to actually deliver |
| Sign-up | New number stuck on code screen forever | `registerUser`, `getCountries`, `getCountryCode` | **done** — `authorizationStateWaitRegistration` now has a Your Name step |
| Calls | Call stack is over libtgvoip | `createCall`, `acceptCall`, `discardCall`, `sendCallSignalingData`, `sendCallRating` | **done** — TDLib used for signalling, libtgvoip for media |

---

## Tier 1 — reached for weekly, absence reads as unfinished

- **Creating a chat** — **done**: Compose → New Message / New Group, contacts picker, name → `createNewBasicGroupChat` or `createNewSupergroupChat`. Open: join by link (`joinChat`)
- **Group administration** — **done**: member sheet promotes, demotes or removes; batch-add via `addChatMembers`; More menu has photo, description, permissions presets, owner handover
- **Invite links** — **done**: profile menu lists links; primary copyable; create/revoke extras; check-then-join flow; join requests list
- **Chat folders, write side** — **done**: create, rename, delete, add/remove chats, adopt suggestions, reorder by drag; `readChatList` on "Mark Read"; Archive settings in Data & Storage
- **Forum topics, write side** — **done**: create (name + colour), rename, pin/unpin, close/reopen, delete; toggle topics/flow view. Open: custom emoji topic icons
- **Secret chats** — done: start from profile, state in header (waiting / keys exchanged / closed), close with warning, in-chat search uses `searchSecretMessages`
- **Stickers, the rest** — **done**: search installed + public sets, trending, save/remove GIFs, favourite/unfavourite stickers, install/archive/restore sets, drag-reorder strip
- **Scheduled messages** — **done**: hold Send → pick date or "when online"; queue in `TGScheduledViewController`; send-now / reschedule / delete on a row
- **Polls, write side** — **done**: vote, stop poll, view voters, add/remove option, clear vote badge, poll statistics chart
- **Live location** — **done**: fixed or live pin (15 min / 1 h / 8 h); updates via `editMessageLiveLocation`; map thumbnail from `getMapThumbnailFile`
- **Profile and account** — **done**: photo history with delete; privacy & security; 2FA setup/change/disable; delete account; terminate all other sessions; groups in common; recovery email confirmation flow
- **Proxies** — **done**: Settings → Proxy; switch, test, add via link or host:port; edit in place
- **Download manager** — **done**: Settings → Downloads; pause, cancel, remove, sweep
- **Reporting** — **done**: profile More menu; `reportChat` two-step; Report Spam in groups; Report Reaction
- **Recents** — **done**: search opens on Top Chats + Recently Opened, deduplicated; `addRecentlyFoundChat` on open

---

## Tier 2 — wanted, nobody blocked

~300 functions: message statistics, chat event logs, message calendars, per-chat themes, notification exceptions, hashtags, autosave, custom language packs, custom emoji, sticker authoring, `toggleSupergroup*` switches. Run `--relevant` and pick from it when Tier 0 and 1 are closed.

## Tier 3 — out of scope

501 functions skipped by pattern in `scripts/tdlib_coverage.sh`: bots / web apps, gifts, stories, TON wallet, business accounts, group/video calls, Stars / paid media, Premium, boosts, ads, Passport, payments, games, speech recognition, affiliate programs, `test*` and `log*` plumbing.

Reasons: needs a browser this OS can't run, needs a payment stack, or is a server feature designed after these devices shipped. To reconsider one, remove it from `SKIP` — that's the whole edit.

---

## How to work this list

1. Pick from Tier 0 first — usually one request and one button, removes a daily pain.
2. Use the app. Tier 0 and 1 say what's *absent*; only using it says what *hurts*. Log what you reach for and don't find in [bug_registry.md](bug_registry.md).
3. Re-run `scripts/tdlib_coverage.sh` after each feature — the percentage is the progress bar.
