# Feature Backlog

What the app can't do, derived from TDLib — not from manually walking the official client.

`tdlib/td/td/generate/scheme/td_api.tl` declares every function and every update the protocol offers. The functions this app never names are what it can't do; the updates it never reads are what goes stale while it runs.

```sh
sh scripts/tdlib_coverage.sh            # counts and gap by area
sh scripts/tdlib_coverage.sh --relevant # missing functions worth having
sh scripts/tdlib_coverage.sh --skipped  # missing functions, on purpose
sh scripts/tdlib_coverage.sh --updates  # dropped updates worth reading
```

As of 2026-10-31:

| | declared | covered | gap | of it wanted | out of scope |
|---|---|---|---|---|---|
| functions | 1076 | 232 (21%) | 844 | 344 | 500 |
| updates | 197 | 66 (33%) | 131 | 56 | 75 |

Functions are counted from string literals in `src/`, updates from the one list in `src/Core/TGUpdateType.h` — anything outside it is thrown away in the receive loop before a Foundation tree is built, so a dropped update leaves no trace in the log either. Both numbers are floors. Where this file and ROADMAP.md disagree, the roadmap wins — it knows the device.

The two halves are not comparable: 1076 functions include every bot, Stars, business and TON call, while the 197 updates are the live state of a client that is running. Updates are the weaker number of the two and the cheaper one to move — Tier 0 below is closed but for the global unread total.

---

# Functions

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

~344 functions: message statistics, chat event logs, message calendars, per-chat themes, notification exceptions, hashtags, autosave, custom language packs, custom emoji, sticker authoring, `toggleSupergroup*` switches. Run `--relevant` and pick from it when Tier 0 and 1 are closed.

## Tier 3 — out of scope

500 functions skipped by pattern in `scripts/tdlib_coverage.sh`: bots / web apps, gifts, stories, TON wallet, business accounts, group/video calls, Stars / paid media, Premium, boosts, ads, Passport, payments, games, speech recognition, affiliate programs, `test*` and `log*` plumbing.

Reasons: needs a browser this OS can't run, needs a payment stack, or is a server feature designed after these devices shipped. To reconsider one, remove it from `SKIP` — that's the whole edit.

---

# Updates

A missing function is a button that isn't there. A dropped update is a screen that lies: the data was correct when the screen was built and the server has since said otherwise. The same tiers, ranked by how fast the lie shows.

## Tier 0 — the screen lies within a minute

| Update(s) | What goes stale | Status |
|---|---|---|
| `updateMessageSendSucceeded`, `updateMessageSendFailed` | Sent bubble keeps its clock and its temporary id forever; a failed send looks like a slow one | **done** — swapped in `handleUpdate`, tested in `TGClientComposeTests` |
| `updateChatDraftMessage` | Draft typed on another device never appeared | **done** — merged in `applyChatUpdate`, list and composer read it |
| `updateChatPhoto` | Avatar stayed the old one after it was changed | **done** — new small file id, and a removed photo clears it |
| `updateChatUnreadMentionCount`, `updateChatUnreadReactionCount`, `updateMessageMentionRead`, `updateMessageUnreadReactions` | The @ badge never moved — there was none to move | **done** — counted apart from unread, row shows "@" and outranks the count |
| `updateMessageEdited` | No "edited" mark until the history was re-read | **done** — re-reads the open chat |
| `updateMessageIsPinned` | Pinned banner showed what was pinned when the chat opened | **done** — re-reads the open chat |
| `updateMessageContentOpened` | Voice note kept its unplayed dot after the other side played it | **done** — re-reads the open chat |
| `updateChatIsMarkedAsUnread` | Mark-as-unread from another device never arrived | **done**. `updateUnreadMessageCount` (the global total) — open, nothing draws it yet |
| `updateFileAddedToDownloads`, `updateFileDownload`, `updateFileDownloads`, `updateFileRemovedFromDownloads` | Settings → Downloads was built from one `searchFileDownloads` answer and never moved | **done** — `TGDownloadsChangedNotification`, list re-read 0.3 s after the burst |
| `updateOption` | Limits and the clock were read once at sign-in and never corrected | **done** — `TGOptionStore` (C++); `unix_time` now grades chat-list dates |

## Tier 1 — stale within a day

Full info for every sender type: `updateUserFullInfo`, `updateBasicGroup`, `updateBasicGroupFullInfo`, `updateSupergroupFullInfo` — **done**. They post `TGFullInfoChangedNotification` with the peer's kind and id, and an open profile re-reads its details instead of needing a reopen. A group profile holds the chat id rather than the supergroup id, so any group's full info re-reads a group profile: one request, against caching a mapping for no gain.

Counters and reactions on a message: `updateMessageInteractionInfo` — **done**, through the batcher: a dirty message marks its chat, and the 100 ms window delivers one nudge per chat however many messages in it moved, so a crowd reacting to a channel post costs one history re-read rather than twenty. `updateMessageReaction` and `updateMessageReactions` (who reacted, not how many) are still open and only matter once the app shows a reactor list.

Group administration — **done**. `updateChatMember`, `updateChatPendingJoinRequests` and `updateNewChatJoinRequest` post `TGChatMembersChangedNotification` with the chat id; `updateChatPermissions`, `updateChatMessageAutoDeleteTime` and `updateChatOnlineMemberCount` are chat fields, merged in `applyChatUpdate` and announced as a full record of kind "chat". An open group profile re-reads either way.

Chat list placement: `updateChatAddedToList`, `updateChatRemovedFromList` — **done**. Removal clears the order for that list only, so a chat taken out of the archive stops sitting on the archive strip; an addition carries no order and waits for the position that follows.

Stickers and GIFs: `updateInstalledStickerSets`, `updateRecentStickers`, `updateFavoriteStickers`, `updateSavedAnimations`, `updateTrendingStickerSets`, `updateStickerSet` — **done**. Six lists, one notification, because the panel asks for whichever tab it is showing; installing a set fires several at once so the re-read waits out the burst.

Notifications: `updateScopeNotificationSettings` and `updateChatDefaultDisableNotification` — **done**, one notification, the settings page re-reads all three scopes. Still open, and only needed once notifications are drawn locally rather than by APNs: `updateNotification`, `updateNotificationGroup`, `updateActiveNotifications`, `updateHavePendingNotifications`.

Forum topics — **done**: `updateForumTopic`, `updateForumTopicInfo` (whose chat id is nested in the info) and `updateTopicMessageCount` all name their chat, and an open topics list re-reads itself.

Polls: `updateChatUnreadPollVoteCount` and `updateMessageContainsUnreadPollVotes` — **done**, the chat keeps the count and the message goes through the coalescer. `updatePoll` and `updatePollAnswer` turned out to be marked "for bots only" in td_api and are now counted out of scope — a poll a user can see changes through `updateMessageContent`.

Service traffic an official client is expected to show: `updateServiceNotification`, `updateTermsOfService`, `updateUnconfirmedSession`, `updateUserPrivacySettingRules`, `updateFreezeState`.

Also here: `updateActiveLiveLocationMessages` (live location is shipped), `updateChatAvailableReactions`, `updateDefaultReactionType`, `updateChatBlockList`, `updateChatHasScheduledMessages`, `updateChatViewAsTopics`, `updateLanguagePackStrings`, `updateMessageReaction` and `updateMessageReactions` (who reacted, not how many — wanted once there is a reactor list to show).

## Tier 2 — wanted, nobody blocked

Accent colours, chat themes and backgrounds, saved-messages topics and tags, welcome messages, message sender switching, close birthdays, notification sounds, autosave settings, translation flags, `updateChatReplyMarkup`, `updateSpeedLimitNotification`. Run `--updates` and pick from it when Tier 0 and 1 are closed.

## Tier 3 — out of scope

73 dropped updates match the `SKIP` pattern in `scripts/tdlib_coverage.sh`: stories, group and video calls, business accounts, TON wallet, Stars and paid reactions, gifts and auctions, boosts, quick replies, mini-app and web-browser plumbing, plus every `updateNew*Query` — those only ever reach a bot account, never this one.

Two more are dropped deliberately rather than by pattern: `updateFileGenerationStart` / `updateFileGenerationStop` (the app never asks TDLib to generate a file) and `updateMessageSendAcknowledged` (a flattened message has no state between pending and sent, so there is nothing to draw).

## Pick these first

Tier 0 is closed except the global unread total. Next, in this order:

Tier 1 is down to what has no screen to land on. In order:

1. `updateChatBlockList` + `updateChatHasScheduledMessages` + `updateChatViewAsTopics` + `updateChatAvailableReactions` — four more chat fields through `applyChatUpdate`, the same shape as the last batch.
2. `updateActiveLiveLocationMessages` — live location is shipped and its list is fetched once.
3. `updateUserPrivacySettingRules` + `updateUnconfirmedSession` + `updateFreezeState` — settings screens read them per open.
4. `updateServiceNotification` + `updateTermsOfService` — nothing draws them yet, which is the work, not the update.
5. `updateUnreadMessageCount` — needs the app-icon badge drawn first, same.
6. `updateLanguagePackStrings` — only matters once the app ships more than one language.

Not an update, but the largest single feature hole left: bot keyboards. `replyMarkupInlineKeyboard`, `replyMarkupShowKeyboard` and `getCallbackQueryAnswer` are unimplemented, so buttons under a bot's message are not drawn and cannot be pressed. Inline mode (`getInlineQueryResults`, `sendInlineQueryResultMessage`) already works.

---

## How to work this list

1. Pick from Tier 0 first — usually one request and one button, removes a daily pain.
2. Use the app. Tier 0 and 1 say what's *absent*; only using it says what *hurts*. Log what you reach for and don't find in [bug_registry.md](bug_registry.md).
3. Re-run `scripts/tdlib_coverage.sh` after each feature — the percentage is the progress bar. A new update needs a row in `TG_HANDLED_UPDATES`, a `case` in `handleUpdate` and the test that failed before it; `TGUpdateFilterTests` fails if the list and the dispatch drift apart.
