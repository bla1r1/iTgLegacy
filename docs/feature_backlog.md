# Feature Backlog

What the app cannot do, derived from TDLib rather than from walking the
official client screen by screen.

`tdlib/td/td/generate/scheme/td_api.tl` declares every function the protocol
offers. The ones this app never names are, exactly, what it cannot do — a
complete list, produced in a second, with nothing in it that somebody happened
to notice:

```sh
sh scripts/tdlib_coverage.sh            # the counts, and the gap by area
sh scripts/tdlib_coverage.sh --relevant # what is missing and worth having
sh scripts/tdlib_coverage.sh --skipped  # what is missing on purpose
```

As of 2026-10-26: **1076 functions declared, 104 called (9%)**. Of the 972
never called, the script counts 501 out of scope and 471 wanted.

Two things this is not. It is not a to-do list in priority order below the
tier — within a tier, pick by what the owner reaches for. And it is not a
substitute for [ROADMAP.md](../ROADMAP.md), which says what the project
intends; this says what the protocol allows and the code ignores. Where they
disagree, the roadmap wins — it knows about the device.

Counting caveat: the script reads literal `@"@type" : @"name"` pairs out of
`src`, so a request whose type is assembled at runtime is missed. Every number
here is a floor.

---

## Tier 0 — the app is visibly broken without it

Each of these is a thing the owner does every day in the official client and
cannot do here at all. Short list on purpose: this is the whole of what
"missing half the features" actually costs in daily use.

| Area | What was missing | Functions | Status |
|---|---|---|---|
| Typing | The app showed "typing…" but never sent it | `sendChatAction` | **done** — one report per four seconds while the composer is typed into |
| Drafts | A draft from another device was shown; one typed here was never saved | `setChatDraftMessage` | **done** — saved on leaving the chat, restored on opening it, cleared when the message goes |
| Reactions | A reaction could be put on and never taken off | `removeMessageReaction` | **done** — the held-message menu offers the six and then offers to remove yours |
| Read state | Voice notes and video notes were never marked opened | `openMessageContent` | **done** — sent when playback starts on an incoming one |
| Failed sends | A message that failed had no retry | `resendMessages` | **done** — a Retry row on a failed message |
| Pinning | Pinned messages were read; nothing could be pinned | `pinChatMessage`, `unpinChatMessage` | **done** — Pin/Unpin in the message menu, and the banner follows |
| Mentions | The mention and reaction badges never cleared | `readAllChatMentions`, `readAllChatReactions` | **done** — both sent on opening a chat |
| Chat list | A chat could not be marked unread | `toggleChatIsMarkedAsUnread` | **done** — Mark as Unread/Read on a held row |
| Links | No way to copy a link to a message | `getMessageLink` | **done** — Copy Link in the message menu |
| Contacts | Contacts could be read but not added | `addContact` | **done** at the client; the screen that calls it is still to come |
| Replies | A reply quotes a message that cannot be jumped to | `getRepliedMessage`, `getMessages`, `getMessageProperties` | client done, no UI yet |
| Editing | Only text can be edited — a caption or a picture cannot | `editMessageCaption`, `editMessageMedia` | open |
| Sending | Several pictures go as several messages, not an album | `sendMessageAlbum` | open |
| Search | Only one public chat at a time; no global search over chats, contacts or people | `searchChats`, `searchChatsOnServer`, `searchContacts`, `searchPublicChats`, `searchStickers` | open |
| Formatting | Bold/italic are rendered on receipt but cannot be sent | `parseTextEntities`, `parseMarkdown`, `getTextEntities`, `getMarkdownText` | open |
| Link previews | A pasted link gets no preview; a t.me link does not resolve | `getLinkPreview`, `getInternalLinkType`, `getInternalLink`, `getDeepLinkInfo` | open |
| Downloads | A download cannot be cancelled and a file cannot be deleted | `cancelDownloadFile`, `deleteFile`, `getFile` | open |
| Push | The device is never registered, so there are no notifications when closed | `registerDevice`, `getPushReceiverId`, `processPushNotification` | open |
| Sign-up | A new account cannot be created, only an existing one signed into | `registerUser`, `checkPhoneNumberCode`, `sendPhoneNumberCode`, `getCountries`, `getCountryCode` | open |
| Calls | Verify: the call stack is hand-written over libtgvoip, so these may be covered outside TDLib | `createCall`, `acceptCall`, `discardCall`, `sendCallSignalingData`, `sendCallRating` | to verify |

The nine marked **done** are covered by `tests/TGClientDraftsTests.m`, which
holds the shape of each request: a draft that clears by omitting
`draft_message` rather than sending an empty one, `notify:NO` that actually
disables the notification, a reaction that is only removable when it is yours.

## Tier 1 — reached for weekly, and its absence reads as unfinished

Groups, folders and the write half of screens the app already shows read-only.

- **Creating a chat** — `createNewBasicGroupChat`, `createNewSupergroupChat`,
  `createBasicGroupChat`, `createSupergroupChat`,
  `upgradeBasicGroupChatToSupergroupChat`, `joinChat`
- **Group administration** — `addChatMember`, `addChatMembers`,
  `setChatMemberStatus`, `banChatMember`, `searchChatMembers`, `getChatMember`,
  `getChatAdministrators`, `setChatTitle`, `setChatPhoto`,
  `setChatDescription`, `setChatPermissions`, `transferChatOwnership`
- **Invite links** — `createChatInviteLink`, `getChatInviteLinks`,
  `checkChatInviteLink`, `revokeChatInviteLink`,
  `replacePrimaryChatInviteLink`, `processChatJoinRequest`, `getChatJoinRequests`
- **Chat folders, write side** — the app reads folders and shows them as a pill
  strip; none of them can be made or edited: `createChatFolder`,
  `editChatFolder`, `deleteChatFolder`, `reorderChatFolders`,
  `getRecommendedChatFolders`, `readChatList`, `setArchiveChatListSettings`
- **Forum topics, write side** — `createForumTopic`, `editForumTopic`,
  `deleteForumTopic`, `toggleForumTopicIsClosed`, `toggleForumTopicIsPinned`,
  `getForumTopic`, `toggleChatViewAsTopics`
- **Secret chats** — none at all: `createNewSecretChat`, `createSecretChat`,
  `closeSecretChat`, `getSecretChat`, `searchSecretMessages`
- **Stickers, the rest of them** — `getStickers`, `searchStickerSets`,
  `getTrendingStickerSets`, `searchInstalledStickerSets`, `getArchivedStickerSets`,
  `getAttachedStickerSets`, `addFavoriteSticker`, `removeFavoriteSticker`,
  `addSavedAnimation`, `removeSavedAnimation`, `reorderInstalledStickerSets`
- **Scheduled messages** — `getChatScheduledMessages`, `editMessageSchedulingState`
- **Polls, write side** — `stopPoll`, `getPollVoters`, `addPollOption`,
  `deletePollOption`, `readAllChatPollVotes`
- **Live location** — `editMessageLiveLocation`,
  `searchChatRecentLocationMessages`, `getMapThumbnailFile`
- **Profile and account** — `deleteProfilePhoto`, `getUserProfilePhotos`,
  `getUserLink`, `getGroupsInCommon`, `setPassword`, `getRecoveryEmailAddress`,
  `setRecoveryEmailAddress`, `deleteAccount`, `terminateAllOtherSessions`
- **Saved Messages** — `searchSavedMessages`, `getSavedMessagesTags`,
  `loadSavedMessagesTopics`, `toggleSavedMessagesTopicIsPinned`
- **Proxies** — matters where Telegram is blocked: `addProxy`, `editProxy`,
  `enableProxy`, `disableProxy`, `removeProxy`, `getProxies`, `pingProxy`,
  `testProxy`
- **Download manager** — `addFileToDownloads`, `searchFileDownloads`,
  `toggleDownloadIsPaused`, `toggleAllDownloadsArePaused`,
  `removeFileFromDownloads`, `removeAllFilesFromDownloads`
- **Reporting and blocking** — `reportChat`, `reportMessageReactions`,
  `reportSupergroupSpam`, `blockMessageSenderFromReplies`, `removeChatActionBar`
- **Recents** — the people row in search: `getTopChats`,
  `getRecentlyOpenedChats`, `addRecentlyFoundChat`, `removeTopChat`,
  `searchRecentlyFoundChats`

## Tier 2 — wanted, nobody is blocked

Everything the script counts as wanted and the two tiers above do not name
(roughly 300 functions): message statistics and view counts, chat event logs,
message calendars and sparse positions, per-chat themes and accent colours,
notification exceptions and saved sounds, hashtags and tag search, autosave
settings, custom language packs, backgrounds beyond the wallpaper the app
already has, translation, custom emoji, sticker authoring, and the long tail of
`toggleSupergroup*` switches. `--relevant` lists them all; pick from it when
the first two tiers are closed.

## Tier 3 — out of scope, and will stay there

501 functions, skipped by one pattern in `scripts/tdlib_coverage.sh` so the
wanted count stays a number worth watching rather than a feeling. In order of
size: bots and inline/web apps, gifts and gift auctions, stories, TON wallet
and TON Connect, business accounts, group calls and video chats (RTMP, screen
sharing), Stars and paid media, Premium, boosts and giveaways, sponsored
messages and ads, Passport, payments and invoices, games, quick replies,
channel direct-message topics, speech recognition and AI summaries, affiliate
programs, and TDLib's own `test*` and `log*` plumbing.

Each is out for one of three reasons: it needs a browser engine this OS has no
usable one of, it needs a payment or wallet stack that is a project of its own,
or it is a server feature designed years after the last device this app targets
shipped. If one of them turns out to matter, move it up by taking it out of
`SKIP` — that is the whole edit.

---

## How to work this list

1. Pick from Tier 0 first. They are small — most are one request and one
   button — and each one removes a daily annoyance.
2. Dogfood for priority. Tier 0 and 1 say what is *absent*; only using the app
   says what *hurts*. Write what you reach for and do not find into
   [bug_registry.md](bug_registry.md).
3. Re-run `scripts/tdlib_coverage.sh` after each feature. The percentage is the
   progress bar, and it costs nothing to keep honest.
