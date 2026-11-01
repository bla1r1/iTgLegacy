# Feature Backlog

What the app can't do, derived from TDLib — not from manually walking the official client.

`tdlib/td/td/generate/scheme/td_api.tl` declares every function and every update the protocol offers. The functions this app never names are what it can't do; the updates it never reads are what goes stale while it runs.

```sh
sh scripts/tdlib_coverage.sh            # counts and gap by area
sh scripts/tdlib_coverage.sh --relevant # missing functions worth having
sh scripts/tdlib_coverage.sh --skipped  # missing functions, on purpose
sh scripts/tdlib_coverage.sh --wired    # called names a screen can reach
sh scripts/tdlib_coverage.sh --bare     # called names with no caller
sh scripts/tdlib_coverage.sh --updates  # dropped updates worth reading
sh scripts/tdlib_coverage.sh --ignored  # let through, but no branch acts on them
```

As of 2026-11-01:

| | declared | covered | gap | of it wanted | out of scope |
|---|---|---|---|---|---|
| functions | 1076 | 497 (46%) | 579 | 84 | 495 |
| updates | 197 | 101 (51%) | 96 | 0 | 78 |

Of the 497 functions the app names, all 497 are reachable from a screen and none are bare: every request has a caller in `src/`, not only a method. A test driving a method does not make it wired — that is the point of the split. `scripts/tdlib_wired.py` does the walk; a new `@type` with no caller shows up under `--bare` and is expected to get a UI path, not only a test.

Functions are counted from string literals in `src/`, updates from the one list in `src/Core/TGUpdateType.h` — anything outside it is thrown away in the receive loop before a Foundation tree is built, so a dropped update leaves no trace in the log either. Both numbers are floors. Where this file and ROADMAP.md disagree, the roadmap wins — it knows the device.

Of the 119 updates let through the filter, 101 have a branch that acts on them; the other 18 are the scaffold in `TG_IGNORED_UPDATES` — names kept in the filter and the dispatch so the screen can be filled in later without hunting for the string, and reported by `--ignored` rather than counted as handled. The 78 dropped updates are out of scope and match the script's `SKIP` pattern.

The two halves are not comparable: 1076 functions include every bot, Stars, business and TON call, while the 197 updates are the live state of a client that is running. Updates are the weaker number of the two and the cheaper one to move — Tier 0 below is closed, the global unread total drives the app-icon badge now.

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
| Downloads | No cancel, no delete | `cancelDownloadFile`, `deleteFile` | **done** — Settings → Downloads with pause/cancel/remove; the chat's progress plate cancels on a tap, and a held picture's sheet adds it to Downloads or deletes the local copy |
| Push | App asked iOS for nothing, handed Telegram nothing | `registerDevice`, `processPushNotification` | **done** — token registered on sign-in; live notifications go to TDLib, and `getPushReceiverId` opens the chat and message the payload names. Needs cert from `docs/howto_push_cert.md` to actually deliver |
| Sign-up | New number stuck on code screen forever | `registerUser`, `getCountries`, `getCountryCode` | **done** — `authorizationStateWaitRegistration` now has a Your Name step; the phone step pre-fills the prefix from `getCountryCode` and the Choose a Country link searches `getCountries` |
| Calls | Call stack is over libtgvoip | `createCall`, `acceptCall`, `discardCall`, `sendCallSignalingData`, `sendCallRating` | **done** — TDLib used for signalling, libtgvoip for media; a call over ten seconds asks for a star rating after it ends, and the call id survives teardown for it |

---

## Tier 1 — reached for weekly, absence reads as unfinished

- **Creating a chat** — **done**: Compose → New Message / New Group, contacts picker, name → `createNewBasicGroupChat` or `createNewSupergroupChat`; a join link joins through `joinChatByInviteLink`, and `joinChat` backs the join switch on a public chat
- **Group administration** — **done**: member sheet promotes, demotes or removes; batch-add via `addChatMembers`; More menu has photo, description, permissions presets, owner handover
- **Invite links** — **done**: profile menu lists links; primary copyable; create/revoke extras; check-then-join flow; join requests list
- **Chat folders, write side** — **done**: create, rename, delete, add/remove chats, adopt suggestions, reorder by drag; `readChatList` on "Mark Read"; Archive settings in Data & Storage
- **Forum topics, write side** — **done**: create (name + colour + an emoji from `getForumTopicDefaultIcons`), rename, change or remove the topic icon, pin/unpin, close/reopen, delete; toggle topics/flow view
- **Secret chats** — done: start from profile, state in header (waiting / keys exchanged / closed), close with warning, in-chat search uses `searchSecretMessages`
- **Stickers, the rest** — **done**: search installed + public sets, trending, save/remove GIFs, favourite/unfavourite stickers, install/archive/restore sets, drag-reorder strip; authoring lives under Settings → Stickers (see Tier 2)
- **Scheduled messages** — **done**: hold Send → pick date or "when online"; queue in `TGScheduledViewController`; send-now / reschedule / delete on a row
- **Polls, write side** — **done**: vote, stop poll, view voters, add/remove option, clear vote badge, poll statistics chart
- **Live location** — **done**: fixed or live pin (15 min / 1 h / 8 h); updates via `editMessageLiveLocation`; map thumbnail from `getMapThumbnailFile`
- **Profile and account** — **done**: photo history with delete; privacy & security; 2FA setup/change/disable; delete account; terminate all other sessions; groups in common; recovery email confirmation flow
- **Proxies** — **done**: Settings → Proxy; switch, test, add via link or host:port; edit in place
- **Download manager** — **done**: Settings → Downloads; pause, cancel, remove, sweep
- **Reporting** — **done**: profile More menu; `reportChat` two-step; Report Spam in groups; Report Reaction
- **Recents** — **done**: search opens on Top Chats + Recently Opened, deduplicated; `addRecentlyFoundChat` on open
- **Sign-in recovery** — **done**: forgotten cloud password (`requestAuthenticationPasswordRecovery` → `checkAuthenticationPasswordRecoveryCode` → `recoverAuthenticationPassword`), password hint shown, email address and email code steps, "Can't access this email?" (`resetAuthenticationEmailAddress`), "Didn't get the code?" (`reportAuthenticationCodeMissing`)
- **Channel comments** — **done**: "N Comments" bar under a channel post with a discussion group; `getMessageThread` opens the thread as a chat
- **Everyday actions** — **done**: Delete Contact (`removeContacts`), Delete for Everyone (`deleteChat`), hold the pinned strip to Unpin All (`unpinAllChatMessages` / `unpinAllForumTopicMessages`), Move Up/Down for pinned chats (`setPinnedChats`), Jump to Date from the profile menu (`getChatMessageByDate`)
- **Bot buttons** — **done**: inline keyboards under bot messages (callback via `getCallbackQueryAnswer`, URL, login via `getLoginUrlInfo` / `getLoginUrl` with a confirm, switch-inline into the composer, copy text, user); reply keyboards in a panel behind a key in the composer, kept live by `updateChatReplyMarkup`. Web apps, payments, games and password callbacks show greyed out
- **Message batch one** — **done**: `getMessageLinkInfo` answers the "message" kind a t.me link to one post carries (the link opened a guessed chat before); the chat opens to that message through `initialMessageId`, and the jump machinery the pinned banner already has does the fetching around. `canSendMessageToUser` gates "Send Message" before a doomed composer sells itself ("ok", "paidMessages", "userDeleted", "userRestrictsNewChats"); `clearAllDraftMessages` is Data & Storage's red row; `getDefaultMessageAutoDeleteTime` / `setDefaultMessageAutoDeleteTime` are Privacy's "Delete Messages By Default" picker; `toggleSupergroupSignMessages` + `toggleSupergroupJoinToSendMessages` are in the group menu, flags read per open off `getSupergroupFullInfo`.
- **Message batches two to six** — **done**: the message record sheets (menu rows on a held message) for `getMessageViewers` + `getMessageReadDate` (who read, and why not — the privacy words TDLib sends), `getMessageAuthor`, `getMessageEmbeddingCode` (Copy Embed Code), `getMessagePublicForwards`; reaction record sheets from `getMessageAddedReactions` where an admin clears `deleteMessageReactionsFromSender` per sender and `deleteAllRecentMessageReactionsFromSender` chat-wide (through the member sheet's Clear Their Reactions); `searchPublicMessagesByTag` rides the in-chat search bar (#-typed, tagged answers in Saved via `searchSavedMessages`); `searchChatRecentLocationMessages` is the locations sheet that jumps to a pin; `translateMessageText` is the Translate row; `getChatMessageCount` fills the jump sheet's subtitle and takes over the count row in the profile; `getChatMessageCalendar` is what Jump-to-Date answers through (one round trip instead of two). Moderation: `deleteChatMessagesByDate/bySender` in the group menu; `deleteAllCallMessages` and `searchOutgoingDocumentMessages` ("My Sent Files") in Data & Storage; welcome messages (`loadChatWelcomeMessages`, `addChatWelcomeMessage`, `editChatWelcomeMessage`, `deleteChatWelcomeMessage`, `deleteAllChatWelcomeMessages`) as one sheet off the group menu; send-as (`getChatAvailableMessageSenders`, `setChatMessageSender`) off the channel profile; the whole Saved-messages topics screen (`loadSavedMessagesTopics`, `getSavedMessagesTags`, `setSavedMessagesTagLabel`, `toggleSavedMessagesTopicIsPinned`, `setPinnedSavedMessagesTopics`, `getSavedMessagesTopicMessageByDate`, `deleteSavedMessagesTopicMessagesByDate`), topics riding `updateSavedMessagesTopic` as real state. Everything the row used to defer now has a path. Bot/inline plumbing (`editMessageReplyMarkup`, `getCallbackQueryMessage`, `getPreparedInlineMessage`, `savePreparedInlineMessage`, `sendTextMessageDraft`, `stopPendingMessage`, `getPersonalChatHistory`, and the five `editInlineMessage*` edits) sits in Settings → Debug Menu → Bot Tools, where the bot-account request and the server's refusal have a real surface; the import trio (`importMessages`, `getMessageFileType`, `getMessageImportConfirmationText`) is the chat profile's Import Messages flow, which reads the export head, shows Telegram's confirmation sentence and imports from Documents; `setChatDirectMessagesGroup` is the channel profile's Direct Messages row. The held-message menu and its Message Info sheet now reach `addLocalMessage` (Add Local Note), `clickAnimatedEmojiMessage`, `getChatMessagePosition`, `getChatSparseMessagePositions`, `getMessageEffect`, `getMessageLocally`, `getMessageStatistics` and `sendMessageViewMetrics`; `setMessageReactions` sits in Bot Tools with the other bot-side requests. `toggleSupergroupIsAllHistoryAvailable` surfaced when the old `[Ss]tory` pattern stopped matching "History" and is now the third switch in the group flags sheet; the History-by-topic calls are no longer skipped either — a topic's history tries `getForumTopicHistory` and falls back to `getMessageThreadHistory`, Saved topics use `getSavedMessagesTopicHistory`, and Clear Everything is `deleteSavedMessagesTopicHistory`.

---

## Tier 2 — wanted, nobody blocked

84 functions in a long tail: usernames/supergroup admin (15), profile/privacy/notes/support (13), emoji/reactions (11), backgrounds/themes (9), diagnostics/network/config (8), notifications/sounds (7), forum topics (6), payments/orders (5), calls/sessions (4), connected websites (3), bot keyboards (2) and poll option properties (1). Run `--relevant` for the exact names and pick with the app in hand.

**Search, links, web, language and formatting — done as a wave.** Thirty functions, every one on a screen:

- **Search** — the search box now offers prefix suggestions from `searchStringsByPrefix` over the chat titles and recent tags it already has; hashtag suggestions from `searchHashtags`; the recent tag log from `getSearchedForTags`, with separate `removeRecentHashtag` and `removeSearchedForTag` actions on a held tag and `clearSearchedForTags` at the end of the list; public posts from `searchPublicPosts`, gated by `getPublicPostSearchLimits` so a spent allowance says when the next free query is; and the t.me links a new account visited from `getRecentlyVisitedTMeUrls`. A held message adds Find Quote, which is `searchQuote` on that message's text.
- **Links** — every external link gets a sheet before it leaves the app: `getLinkWebBrowserType` names the browser Telegram wants, `getExternalLinkInfo` names a sign-in domain and write-access request, and Open goes through `getExternalLink` with that permission. The sheet also reads `getWebPageInstantView` and pushes a native reader (`TGInstantViewController`). Internal t.me/tg:// links are canonicalised through `getInternalLink` before the public-chat, message, invite, sticker-set and phone handlers run, with the old path matcher as the fallback.
- **Language** — Settings → Language reads `getLanguagePackInfo`, `getLanguagePackStrings` and `getLanguagePackString` for the current pack; installs server packs (`addCustomServerLanguagePack`), creates and edits local ones (`setCustomLanguagePack`, `setCustomLanguagePackString`, `editCustomLanguagePackInfo`), synchronises (`synchronizeLanguagePack`) and deletes (`deleteLanguagePack`). The same page shows `getCountry`, `getPreferredCountryLanguage` and `getCountryFlagEmoji` for the device's country, with a code prompt that re-reads all three. The message Translate row uses `translateText` and falls back to `translateMessageText` when a message has no flattened text.
- **Formatting** — holding Send while composing adds Preview Formatting, which asks `parseMarkdown` and `getTextEntities` and lists the parsed entities and detected mentions, tags and links before the message is sent.

**Chat wave — done.** 68 chat functions, all reachable from a screen, none skipped:

- **Invite links** — the profile's link sheet now edits a link's name and limit, reads one link fresh, lists who joined through it, shows per-admin counts, creates subscription links, refuses an approval link with a member limit, and deletes one revoked link or all of them.
- **Folders** — the folder menu gained invite links (create/edit/delete, with the chats Telegram says are suitable), suggested new chats from a shared folder, the default icon name, the approximate chat count, and a delete that offers to leave the suggested chats. Folder links from `t.me/addlist/…` are checked and adopted from the chat list's join sheet; folder tags have a switch.
- **Join requests** — approve or decline every pending request at once; a guard bot's query id can be answered, and a spent one-time keyboard is dropped from the chat.
- **Per-chat tools** — a new Chat Tools screen from a profile's More menu: event log, statistics, similar and recommended chats, slow mode, available reactions, protected content, translatability, default silence, accent and profile-accent colours, emoji chat themes, per-chat background and reset, discussion group, location, a local note kept in `client_data`, the owner after leaving, media positions, emoji photos from Telegram's default sticker set, photo reporting, and adding the chat to any of its chat lists.
- **Account** — new-chat privacy, the personal chat, inactive groups, own public chats with a username check and the public-chat limit, per-chat notification exceptions, and the per-session "accept secret chats" switch.
- **Compatibility** — `createBasicGroupChat`, `createSupergroupChat` and `createSecretChat` turn an inner group/secret-chat id back into a chat, exposed on the Debug Menu's Chat Resolvers; `createNewSecretChat` remains the creation path.

**Auth, email, phone and password — done as a wave.** 30 functions, every one reachable from a screen:

- **Login** — the phone step resolves a typed prefix through `getPhoneNumberInfo` and shows the country and Telegram's formatting under the instructions. A web login can be finished with `checkAuthenticationWebToken` or dropped with `dismissWebToken`, a scanned QR link is confirmed with `confirmQrCodeAuthentication`, and a Firebase-delivered code is handed to the server with `sendAuthenticationFirebaseSms`. A user link with no username is resolved by `searchUserByToken` when the chat's link handler opens it.
- **Changing the number** — Settings → Privacy & Security → Phone Number runs the whole request pair: `sendPhoneNumberCode` with `phoneNumberCodeTypeChange`, `checkPhoneNumberCode`, `resendPhoneNumberCode`, `reportPhoneNumberCodeMissing` and `sendPhoneNumberFirebaseSms`; `getPhoneNumberInfoSync` fills the confirmation sheet before it is shown.
- **Two-step verification** — "Forgot Password?" now offers `requestPasswordRecovery`, `checkPasswordRecoveryCode` and `recoverPassword`, or the slow `resetPassword` road whose pending state can be called off with `cancelPasswordReset`; the temporary password is read with `getTemporaryPasswordState` and made with `createTemporaryPassword`.
- **Settings → Privacy & Security** — the login email is checked with `isLoginEmailAddressRequired`, changed with `setLoginEmailAddress`, and confirmed through `checkLoginEmailAddressCode` / `resendLoginEmailAddressCode`. Passport's address half is `sendEmailAddressVerificationCode`, `resendEmailAddressVerificationCode` and `checkEmailAddressVerificationCode`; a recovery-address change can be abandoned with `cancelRecoveryEmailAddressVerification`; forgotten payment credentials go with `deleteSavedCredentials`.
- **Ownership** — the group profile's Hand Over Ownership asks `canTransferOwnership` first and shows the server's answer (allowed, password needed, or how long the session is too new).
- **Application verification** — `updateApplicationVerificationRequired` now keeps its request id on the client and the Settings row sends the verification service's token through `setApplicationVerificationToken`, showing the server's answer.

**Stickers, authoring and emoji metadata — done as a wave.** Settings → Stickers opens `TGStickerPacksViewController`: New Sticker Pack (title, checked short name, Telegram's suggestion when it is taken, `createNewStickerSet`), My Packs from `getOwnedStickerSets`, search by short name (`searchStickerSet` + `getStickerSetName`), the trending shelf (`viewTrendingStickerSets` as it is drawn), `clearRecentStickers`, the three default custom emoji shelves, a `getCustomEmojiStickers` id lookup and `getGreetingStickers`. A pack opens `TGStickerEditorViewController`: upload (`uploadStickerFile`), add, replace, remove, reorder (`setStickerPositionInSet`), emoji tags (`setStickerEmojis`), keywords (`setStickerKeywords`), mask position — set or removed through a null — (`setStickerMaskPosition`), title (`setStickerSetTitle`), thumbnail (`setStickerSetThumbnail`, or `setCustomEmojiStickerSetThumbnail` for a custom emoji pack) and `deleteStickerSet`. A picked still is aspect-fitted on a transparent 512×512 square and encoded as WebP before either upload, because Telegram checks the bytes against the declared format. The panel's hold card shows `getStickerEmojis` + `getAllStickerEmojis` and the outline (`getStickerOutline`, `getStickerOutlineSvgPath`, copyable). A group profile's More menu sets `setSupergroupStickerSet` and `setSupergroupCustomEmojiStickerSet`. Why each has a screen is the rule the backlog runs on: a name with a method and no caller is bare, not done.

**Files, autosave and contacts — done as a wave.** A media viewer's hold menu and a Downloads row open `TGFileInfoViewController`: `getFile` reads the record, `getRemoteFile` re-resolves its remote copy, `getFileDownloadedPrefixSize` shows what is on disk, and `getSuggestedFileName`, `getFileMimeType`, `getFileExtension` and `cleanFileName` fill the name, type and safe-name rows; Copy puts the whole sheet on the clipboard. Data & Storage → File Tools runs TDLib's generation contract end to end: `preliminaryUploadFile` asks TDLib to generate an `inputFileGenerated`, `updateFileGenerationStart` drives `setFileGenerationProgress` + `writeGeneratedFilePart` for every part, `finishFileGeneration` closes it, upload progress rides `updateFile`, and `cancelPreliminaryUploadFile` stops it; `readFilePart` reads the first bytes back. The same page shows `getAutoDownloadSettingsPresets` and applies Low/Medium/High with `setAutoDownloadSettings`. Autosave is a Settings page built from `getAutosaveSettings`, with the private/group/channel photo and video switches writing through `setAutosaveSettings` and `clearAutosaveSettingsExceptions` for the per-chat list. Contacts grows an Import button: a bundled vCard is parsed into `importedContact` rows, uploaded with `changeImportedContacts`, and the account total from `getImportedContactCount` is kept on the list footer. Settings' "Get the App" row opens `getApplicationDownloadLink`.

## Tier 3 — out of scope

495 functions skipped by pattern in `scripts/tdlib_coverage.sh`: bots / web apps, gifts, stories, TON wallet, business accounts, group/video calls, Stars / paid media, Premium, boosts, ads, Passport, payments, games, speech recognition, affiliate programs, `test*` and `log*` plumbing.

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
| `updateChatIsMarkedAsUnread` | Mark-as-unread from another device never arrived | **done**. `updateUnreadMessageCount` (the global total) — **done**: the unmuted main-list total drives the app-icon badge from `TGUnreadTotalChangedNotification`; a folder's slice does not shrink the badge |
| `updateFileAddedToDownloads`, `updateFileDownload`, `updateFileDownloads`, `updateFileRemovedFromDownloads` | Settings → Downloads was built from one `searchFileDownloads` answer and never moved | **done** — `TGDownloadsChangedNotification`, list re-read 0.3 s after the burst |
| `updateOption` | Limits and the clock were read once at sign-in and never corrected | **done** — `TGOptionStore` (C++); `unix_time` now grades chat-list dates |

## Tier 1 — stale within a day

Full info for every sender type: `updateUserFullInfo`, `updateBasicGroup`, `updateBasicGroupFullInfo`, `updateSupergroupFullInfo` — **done**. They post `TGFullInfoChangedNotification` with the peer's kind and id, and an open profile re-reads its details instead of needing a reopen. A group profile holds the chat id rather than the supergroup id, so any group's full info re-reads a group profile: one request, against caching a mapping for no gain.

Counters and reactions on a message: `updateMessageInteractionInfo` — **done**, through the batcher: a dirty message marks its chat, and the 100 ms window delivers one nudge per chat however many messages in it moved, so a crowd reacting to a channel post costs one history re-read rather than twenty. `updateMessageReaction` and `updateMessageReactions` (who reacted, not how many) ride the same coalescer now, so the open chat sees a reaction land and unfresh itself without a re-open; the reactor list screen is separate and still missing.

Group administration — **done**. `updateChatMember`, `updateChatPendingJoinRequests` and `updateNewChatJoinRequest` post `TGChatMembersChangedNotification` with the chat id; `updateChatPermissions`, `updateChatMessageAutoDeleteTime` and `updateChatOnlineMemberCount` are chat fields, merged in `applyChatUpdate` and announced as a full record of kind "chat". An open group profile re-reads either way.

Chat list placement: `updateChatAddedToList`, `updateChatRemovedFromList` — **done**. Removal clears the order for that list only, so a chat taken out of the archive stops sitting on the archive strip; an addition carries no order and waits for the position that follows.

Stickers and GIFs: `updateInstalledStickerSets`, `updateRecentStickers`, `updateFavoriteStickers`, `updateSavedAnimations`, `updateTrendingStickerSets`, `updateStickerSet` — **done**. Six lists, one notification, because the panel asks for whichever tab it is showing; installing a set fires several at once so the re-read waits out the burst.

Notifications: `updateScopeNotificationSettings` and `updateChatDefaultDisableNotification` — **done**, one notification, the settings page re-reads all three scopes. `updateReactionNotificationSettings` and `updateSavedNotificationSounds` ride the same announcement. `updateNotification`, `updateNotificationGroup`, `updateActiveNotifications` and `updateHavePendingNotifications` are out of scope: APNs draws notifications, so TDLib's local notification list has no screen to land on and the filter drops them.

Forum topics — **done**: `updateForumTopic`, `updateForumTopicInfo` (whose chat id is nested in the info) and `updateTopicMessageCount` all name their chat, and an open topics list re-reads itself.

Polls: `updateChatUnreadPollVoteCount` and `updateMessageContainsUnreadPollVotes` — **done**, the chat keeps the count and the message goes through the coalescer. `updatePoll` and `updatePollAnswer` turned out to be marked "for bots only" in td_api and are now counted out of scope — a poll a user can see changes through `updateMessageContent`.

Service traffic an official client is expected to show: `updateServiceNotification` — **done**, shown as the popup the protocol asks for, through `TGServiceNotificationReceivedNotification` and the app window, since the post belongs to no chat. `updateTermsOfService` — **done**, a terms screen shows the text and Accept sends `acceptTermsOfService`; a terms object that does not ask for a popup is accepted silently. `updateUnconfirmedSession` — **done**, Devices re-reads and the row offers Confirm (`confirmSession`) beside Sign Out. `updateUserPrivacySettingRules` — **done**, an open privacy page re-reads its switches. `updateFreezeState` is dropped with the verification updates: the app draws no freeze or verification banner, and a restriction that matters arrives as a service notification.

Also here, **done** since the second wave: `updateActiveLiveLocationMessages` (every running live location nudges its chat), `updateChatAvailableReactions`, `updateChatBlockList`, `updateChatHasScheduledMessages`, `updateChatViewAsTopics`, `updateChatIsTranslatable`, `updateChatHasProtectedContent` and the rest of the chat-field wave — merged into the row through `applyChatUpdate` and announced as a full record of kind "chat", so an open profile re-reads; `updateSpeedLimitNotification` posts the downloads-round announcement; `updateChatJoinResult` lands next to the other membership updates. `updateDefaultReactionType` now leads the reaction bar with the server's choice, and `updateAnimationSearchParameters` names the GIF search provider and the emoji it suggests — both were no-op markers. `updateLanguagePackStrings` is out of scope: one language ships.

## Tier 2 — wanted, nobody blocked

Saved-messages topics and tags, welcome messages, message sender switching, notification sounds, translation flags, `updateChatReplyMarkup`, `updateSpeedLimitNotification`, the default reaction and the GIF search parameters — **done as a wave**: every update with a reader is in the filter, merged or nudged. `updateApplicationVerificationRequired` also acts now: it keeps the request id on the client and posts the notification the Settings row reads. Eighteen names remain in `TG_IGNORED_UPDATES` as the scaffold for screens not drawn yet; `sh scripts/tdlib_coverage.sh --ignored` lists them, and filling one in is a case and a screen.

## Tier 3 — out of scope

78 dropped updates match the `SKIP` pattern in `scripts/tdlib_coverage.sh`: stories, group and video calls, business accounts, TON wallet, Stars and paid reactions, gifts and auctions, boosts, quick replies, mini-app and web-browser plumbing, plus every `updateNew*Query` — those only ever reach a bot account, never this one.

Three more joined the pattern deliberately rather than through a screen: `updateMessageSendAcknowledged` (a flattened message has no state between pending and sent, so there is nothing to draw), `updateActiveEmojiReactions` (the reaction picker's list — no picker) and `updatePendingMessage` (a bot's streaming draft — no bot surface). `updateFileGenerationStart` / `updateFileGenerationStop` used to be here for the same reason; File Tools now asks TDLib to generate a file, so both are handled and announce progress to `TGFileToolsViewController`.

## Pick these first

The update half is in two states. 99 updates act; 18 are scaffold markers in `TG_IGNORED_UPDATES`, each waiting for one screen. The markers worth giving a screen to, in order:

1. Local notification drawing (`updateNotification`, `updateNotificationGroup`, `updateActiveNotifications`, `updateHavePendingNotifications`) — the only way to replace APNs as the delivery path.
2. `updateAutosaveSettings` (gallery autosave), `updateAccentColors` / `updateProfileAccentColors` / `updateDefaultBackground` / `updateEmojiChatThemes` (theme and background pickers), `updateLanguagePackStrings` (a language pack this OS can carry).
3. `updateAvailableMessageEffects`, `updateContactCloseBirthdays`, `updateStopMessageDraft`, `updateVideoPublished`, `updateUserSubscription`, `updateFreezeState`, the age-verification pair and `updateApplicationRecaptchaVerificationRequired` — each needs its renderer or account surface first.
4. The functions half below, still 84 wide — pick from `--relevant` with the app in hand.

---

## How to work this list

1. Pick from Tier 0 first — usually one request and one button, removes a daily pain.
2. Use the app. Tier 0 and 1 say what's *absent*; only using it says what *hurts*. Log what you reach for and don't find in [bug_registry.md](bug_registry.md).
3. Re-run `scripts/tdlib_coverage.sh` after each feature — the percentage is the progress bar. A new update needs a row in `TG_HANDLED_UPDATES`, a `case` in `handleUpdate` and the test that failed before it; `TGUpdateFilterTests` fails if the list and the dispatch drift apart.
