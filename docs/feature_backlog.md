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

As of 2026-10-26: **1076 functions declared, 197 called (18%)**. Of the 879
never called, the script counts 501 out of scope and 378 wanted.

The counter reads every string literal in src and intersects it with the
td_api names, so both branches of a ternary'd request count, not just
the first spelling the regex used to see.

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
| Editing | Only text could be edited — a caption or a picture could not | `editMessageCaption`, `editMessageMedia` | **done** — media with a caption now gets an Edit row, and the composer knows a caption is a different request from text |
| Sending | Several pictures went as several messages, not an album | `sendMessageAlbum` | **done** — holding a tile in the attach strip starts a selection, numbered in the order ticked, and Send sends them as one album with the composer's text as its caption |
| Search | Matching titles found only what was already loaded | `searchChats`, `searchChatsOnServer`, `searchPublicChats`, `searchContacts` | **done** — all three places a chat can be, deduplicated local-first, plus a Contacts section; `searchStickers` landed with the sticker search |
| Formatting | Bold and italic were rendered on receipt and could not be sent | `parseTextEntities` | **done** — the markup is read out of what was typed (`*bold*`, `_italic_`, `` `code` ``) through TDLib's synchronous half, and falls back to the text as written when that is unavailable. `getMarkdownText` fills the composer with the markdown out of it when Edit is tapped |
| Link previews | A pasted link got no preview; a t.me link was read by hand | `getLinkPreview`, `getInternalLinkType` | **done** — the composer shows what Telegram found once the typing settles, and a t.me link asks Telegram what it means rather than reading its path, which used to make t.me/addstickers/foo a chat called "addstickers". The hand-matched paths stay as the fallback, and a link with no schema at all is given meaning through `getDeepLinkInfo` |
| Downloads | A download cannot be cancelled and a file cannot be deleted | `cancelDownloadFile`, `deleteFile`, `getFile` | **done** — Settings → Downloads lists what this account pulled, and a held row pauses, cancels or removes it; a sweep clears the list and frees the disk with it |
| Push | The app asked iOS for nothing and handed Telegram nothing | `registerDevice`, `processPushNotification` | **done** — the token is asked for once an account is signed in, handed over as hex with the sandbox flag following the build, and a notification arriving while the app runs goes to TDLib so the list moves at once. Needs the certificate from docs/howto_push_cert.md to actually deliver; the blob under "p" is what hands over, and `getPushReceiverId` names its chat and message even while it is undeliverable |
| Sign-up | A new number entered its code and then sat on the code screen forever | `registerUser`, `getCountries`, `getCountryCode` | **done** at the step: authorizationStateWaitRegistration had no case in the switch at all, so there was nowhere to go. A Your Name step makes the account and shows the terms Telegram sent with the state. `getCountries`/`getCountryCode` are in the client; the phone step still has a typed prefix rather than a picker |
| Calls | Verify: the call stack is hand-written over libtgvoip, so these may be covered outside TDLib | `createCall`, `acceptCall`, `discardCall`, `sendCallSignalingData`, `sendCallRating` | to verify |

The nine marked **done** are covered by `tests/TGClientDraftsTests.m`, which
holds the shape of each request: a draft that clears by omitting
`draft_message` rather than sending an empty one, `notify:NO` that actually
disables the notification, a reaction that is only removable when it is yours.
The tier-1 work has `tests/TGClientFoldersTests.m`, where the shapes are
easier to get wrong: `editChatFolder` replaces a folder rather than patching
it, so a rename has to carry back the chats and flags it was not asked
about, and `reportChat` answers with a question before it accepts anything.

## Tier 1 — reached for weekly, and its absence reads as unfinished

Groups, folders and the write half of screens the app already shows read-only.

- **Creating a chat** — **done** for the way layers get made: Compose asks
  New Message or New Group, the picker ticks people, and the name goes to
  `createNewBasicGroupChat` or `createNewSupergroupChat`, with
  `upgradeBasicGroupChatToSupergroupChat` in the client. Open:
  `createBasicGroupChat`, `createSupergroupChat`, `joinChat` (a link the app
  receives can be checked but not joined)
- **Group administration** — **done** at the profile for one member at a
  time: the member list is tappable, a member's sheet promotes to
  administrator, demotes or removes, and removing is what banning is, warned
  as such (`addChatMember`, `searchChatMembers`, `setChatMemberStatus`,
  `banChatMember`, `getChatAdministrators`, `setChatTitle`). The batch the
  contacts picker owed is one `addChatMembers` now, and a single member's
  record reads through `getChatMember`. The More menu groups the rest:
  photo (`setChatPhoto`), description (`setChatDescription`) and the
  members' permissions as three spoken presets over `setChatPermissions`.
  `transferChatOwnership` is wired to its handover: the member sheet of the
  owner offers Hand Over Ownership, warned as final, and it asks for the
  2FA password first - which, once two-step verification is on, is the
  only way Telegram answers the request at all.
- **Invite links** — **done**. The profile's menu lists the chat's links:
  the primary copyable, an extra made on the spot
  (`createChatInviteLink`), the whole set on one sheet where an extra is
  revoked and the primary replaced after a confirm
  (`revokeChatInviteLink`, `replacePrimaryChatInviteLink`). A t.me link is
  joined from compose: `checkChatInviteLink` answers its title and size
  first, and the confirm opens or joins
  (`joinChatByInviteLink`). The requests a links-with-approval chat
  collects are listed at the profile, each accepted or declined
  (`getChatJoinRequests`, `processChatJoinRequest`)
- **Chat folders, write side** — **done** except the order. Settings → Chat
  Folders makes, renames and deletes them, adds and removes a chat at a time
  through the forward picker, and adopts Telegram's own suggestions:
  `createChatFolder`, `editChatFolder`, `deleteChatFolder`, `getChatFolder`,
  `getRecommendedChatFolders`, `reorderChatFolders`. Also wired:
  `readChatList` - the folder menu's trailing "Mark Read" row reads the
  list that is open, main included, the archive screen naming
  `chatListArchive` - and the Archive screen's three settings live in
  Settings, Data and Storage: one `archiveChatListSettings` object, three
  switches, the local copy moving before `setArchiveChatListSettings`.
  The pill strip itself is drag-ordered now: holding a folder pill picks
  it up, it follows the finger, and a drop writes the order locally
  before asking TDLib, so the strip holds while the wire is still in flight
- **Forum topics, write side** — **done**. The topics list has a plus that
  makes a topic, name and one of the seven forum hues
  (`createForumTopic`), and holding a topic renames it
  (`editForumTopic`), pins or unpins it (`toggleForumTopicIsPinned`),
  closes or reopens it (`toggleForumTopicIsClosed`) and deletes it with
  the warn that everyone loses it (`deleteForumTopic`). A channel can be
  shown as topics or as one flow from the profile's menu
  (`toggleChatViewAsTopics`, read through
  `getChat`). Open: topic icons as custom emoji, and the general topic's
  own edit
- **Secret chats** — started from a user's profile actions
  (`createNewSecretChat`); the name walks into the list marked
  "(secret)". The header carries the state - waiting on either side,
  keys exchanged, closed - live in updates
  (`getSecretChat` through `updateSecretChat`), "pending" and "closed"
  hide the composer, and holding the header offers the end of it
  (`closeSecretChat`, warned to be final). Search wired too:
  `searchInChat` asks `searchSecretMessages` inside a secret chat and
  `searchChatMessages` elsewhere, so the in-chat search bar reaches the
  self-destructing history without a second screen
- **Stickers, the rest of them** — **done** for the panel's own needs: the
  sticker search reads the installed sets first and then every public one
  (`getStickers`, `searchStickers`), sets are found by name
  (`searchStickerSetsNamed` is on `searchStickerSets`) and by title among
  the installed (`searchInstalledStickerSets`), trending answered
  (`getTrendingStickerSets`), holding a GIF saves or drops it
  (`addSavedAnimation`, `removeSavedAnimation`), holding a sticker
  favourites or unfavourites it (`addFavoriteSticker`,
  `removeFavoriteSticker`), and a held set uninstalls, archives and
  restores (`changeStickerSet` both ways), with the archived shelf behind
  `getArchivedStickerSets` — and the strip is drag-ordered now: holding a
  set's pill picks it up, it follows the finger along the strip, and a
  drop rebuilds the local `stickerSets` before
  `reorderInstalledStickerSets` carries the dragged order, with the lit
  pill staying lit across its own tag shuffle. `getAttachedStickerSets`
  is in the client; the media composer that would show the sets is still
  to come.
- **Scheduled messages** — **done**. Holding Send offers a date, "when
  online" for private chats, and the queue:
  `editMessageSchedulingState` with the state spelled (an absent one is
  TDLib's own "send now"), `getChatScheduledMessages` listed
  (`TGScheduledViewController`) with send-now / move / delete on a row
- **Polls, write side** — **done**. Voting works (`setPollAnswer`, through
  the option buttons inside the bubble) and Stop Poll is in the message
  menu for a poll you sent (`stopPoll`). The menu now also looks at the
  crowd: who voted one answer lists through `getPollVoters`, an answer is
  added after the fact by `addPollOption` when the poll allows it, and one
  is taken out by `deletePollOption` after a confirm. The fresh-vote badge
  clears when the chat is opened (`readAllChatPollVotes`). Statistics
  wired too: `getPollVoteStatistics` behind the message menu's "Poll
  Statistics" - the vote graph TDLib hands over as a JSON chart read into
  the sheet, falling back to the options' own share when the chart is not
  a spelling this file reads
- **Live location** — **done**. The attach sheet's Location row now asks
  what kind of pin: a fixed one, or a live one for 15 minutes, an hour,
  or eight. The live share is one `sendMessage` answered with the
  message, whose id later fixes move through `editMessageLiveLocation`
  while the GPS keeps talking; the message menu takes a live pin of your
  own off the map with the same request whose period says zero. Walking
  away from the chat stops watching the GPS.
  A location bubble now shows Telegram's own picture of the place
  (`getMapThumbnailFile`): the drawn card goes up first so the bubble has
  something at once, and the real thumbnail replaces it when it lands - on
  a device with no connection the card is the whole answer, which is why
  it stays rather than becoming a placeholder. Open:
  `searchChatRecentLocationMessages`
- **Profile and account** — **done**. Tapping an avatar opens the photo
  history, where a swipe takes one off the account
  (`getUserProfilePhotos`, `deleteProfilePhoto`); Privacy and Security
  carries My Link (`getUserLink`) and a Two-Step Verification flow that
  sets, changes and turns off a password, with the hint asked for
  separately and the recovery address read back and changed behind it
  (`setPassword`, `getRecoveryEmailAddress`, `setRecoveryEmailAddress`);
  Delete Account Now asks why and then for the password
  (`deleteAccount`); Active Sessions grew a red row that signs out every
  other device (`terminateAllOtherSessions`). `getGroupsInCommon` is at
  the profile. A new recovery address is confirmed in the app rather than
  in a browser: the code Telegram emails is asked for, refused codes can
  be sent again, and until one goes through the flow says the old address
  still stands (`checkRecoveryEmailAddressCode`,
  `resendRecoveryEmailAddressCode`)
- **Saved Messages** — not worth building, and here is why: Saved Messages
  is a chat, so the chat search already searches it through
  `searchChatMessages`. What `searchSavedMessages` adds over that is
  filtering by tag and by topic, and tags are a Premium feature while
  topics sort saved messages by who they came from - neither is reached for
  weekly on a phone this size. Moved to tier 2 in spirit:
  `searchSavedMessages`, `getSavedMessagesTags`, `loadSavedMessagesTopics`,
  `toggleSavedMessagesTopicIsPinned`
- **Proxies** — **done**. Settings → Proxy lists them, switches between them
  and direct, checks one answers, and takes a t.me/proxy or tg://proxy link
  or a bare host:port: `getProxies`, `addProxy`, `enableProxy`,
  `disableProxy`, `removeProxy`, `pingProxy`. A proxy's address is changed
  in place rather than by removing and re-adding it, which lost its place
  in the list and whether it was in use (`editProxy`), and Check It Works
  asks both questions - whether it answers at all, and whether it will
  carry Telegram, which is the failure a ping alone calls success
  (`testProxy`, then `pingProxy` for the number)
- **Download manager** — **done**. Settings → Downloads is the list Telegram
  keeps, with the running count on the root page: a held row pauses or
  cancels the pending half and removes an entry (its file with it, if
  asked), a sweep pauses or resumes or clears everything
  (`addFileToDownloads`, `searchFileDownloads`, `toggleDownloadIsPaused`,
  `toggleAllDownloadsArePaused`, `removeFileFromDownloads`,
  `removeAllFilesFromDownloads`)
- **Reporting** — **done**. The profile's More menu asks Telegram for the
  reasons and sends back the one picked, which is the two-step `reportChat`
  conversation. Holding someone else's message in a group offers Report
  Spam, on its own or with the sender blocked from replying and their
  messages removed (`reportSupergroupSpam`, which reads the supergroup's
  own id off the chat because a chat id is not it, and
  (`blockMessageSenderFromReplies`). `removeChatActionBar` is in the
  client, with no action bar on screen to dismiss yet. Reactions report
  too: a message whose reaction names a reactor offers "Report Reaction"
  (`reportMessageReactions`), the MessageSender of the latest named
  reactor carried up through the flattening, one confirm behind the menu
- **Recents** — **done**. Search opens on two sections rather than on a
  blank table: the people this account talks to most (`getTopChats`) and
  where it was last (`getRecentlyOpenedChats`), the second with anything
  already in the first left out of it. Opening a chat from search puts it in
  the recently-found list (`addRecentlyFoundChat`). `removeTopChat` is in
  the client, with no "remove from this list" gesture on the row yet.
  `searchRecentlyFoundChats` searches only that list, which the chat search
  above it already covers - not worth its own path

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
