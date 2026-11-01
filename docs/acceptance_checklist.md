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

### Emoji, reactions and topic badges

| Check | Broke in | Device | Host |
|---|---|---|---|
| Emoji strip is Telegram's categories, with the built-in set as the offline fallback | — | Open Emoji: strip names and icons match Telegram; cut the network and reopen: built-in strip still draws, no empty tabs | `TGClientEmojiReactionsTests.testEmojiCategories_AsksForTheDefaultsAndReadsTheSource`; premium rows carry no list and are dropped |
| The magnifier searches and suggests in two sections | — | Emoji → magnifier → "cat": Results fills within 1 s and Suggested sits above it; a repeated glyph appears once; log shows one `searchEmojis` and one `getKeywordEmojis` | `testSearchEmojis_…DropsDuplicateGlyphs`, `testKeywordEmojis_IsTheSuggestedRow` |
| Held emoji card plays the animation and shows the reaction title | — | Hold 😀 → Animated Preview: plays or says there is none; Reaction Info: title and Available/Not available appear in ≤ 1 s | `testAnimatedEmoji_ReadsTheStickerAndSound`, `testEmojiReaction_ReadsTheTitleAndTheAnimation` |
| Custom reaction animation and the suggestion link are reachable from the same card | — | Hold an emoji → Custom Reaction Animation plays a TGS; Suggest Replacement Link offers Copy/Open and the copied URL opens the translation platform | `testCustomEmojiReactionAnimations_FlattensTheStickerList`, `testEmojiSuggestionsUrl_IsTheLinksText` |
| Holding a reaction makes it lead the bar, now and after reopening | — | Hold a message → hold 🔥 in the bar: it jumps to the front, the ring moves with it; reopen the menu: 🔥 still leads; log shows `setDefaultReactionType` | `testSetDefaultReaction_SendsTheEmojiAndLeadsTheBarAtOnce` |
| Notifications page owns reaction settings and the recent list | — | Settings → Notifications and Sounds → Reactions: the switch flips and survives reopening; Clear Recently Used Reactions empties the bar's recent order after a confirm | `testReactionNotificationSettings_OffKeepsTheSourcesThisScreenDoesNotShow`, `testClearRecentReactions_IsAnswered` |
| A forum topic's unread reactions show, then clear on open | — | Topics list shows "3 reactions" under the row; open the topic: the badge is gone on return, and the log names `readAllForumTopicReactions` | `testForumTopics_CarryTheUnreadReactionCount`, `testReadAllForumTopicReactions_SendsTheChatAndTopic` |
| A hold lifts the bubble, dims the chat and opens the short menu under it; administrative rows sit under More | — | Hold any message: the bubble leaves the list and settles at the top of the screen, the chat behind it is dimmed and blurred, the reaction bar floats over the bubble and the card opens below it; Reply, Copy, Edit, Pin, Copy Link, Forward, Delete, Select and the reaction bar are there (the card scrolls when the screen is short); a tap outside puts the bubble back, removes the backdrop and dismisses the menu; More opens Translate, Message Info, Reactions, Report Spam and the rest in a second card | No host test: UIKit lifecycle and CoreImage. Lift/blur in `TGChatViewController+Actions`; anchored card in `TGPopupMenu`; menu rows in `TGChatViewController+Actions`; flatten fields they read are covered below |
| One reactor shows their face; more show emoji and count | — | In a group, react with one account: the chip under the bubble is that account's round picture plus the emoji. Add a second account's reaction: the chip becomes emoji + 2 | `TGMessageParserTests.testFlatten_ReactionGroupsCarryTheSoleReactorAndTheViewCount`, `testFlatten_CustomReactionKeepsItsIdAndFallsBackToAStar` |
| Tapping a reaction chip opens its reactor list directly | — | Tap a chip: a pushed screen titled "👍 Reactions" lists picture, name, reaction date/time and the emoji; Back returns to the chat. A custom emoji opens the same list by `custom_emoji_id` | `TGClientMessagesFunctionsTests.testAddedReactions_CarriesTheDateAndMineAndAcceptsACustomType`; list layout is device-only |
| An own post shows "Viewed by N"; opening it lists readers | — | As a channel/group admin, hold your own post: "Viewed by 3" sits in the first card. Tap it: readers with avatars and dates appear. In a private chat with viewers refused, the same row shows the read date or Telegram's reason | `testViewersAndReadDate_NamesWhoAndWhyNot`, `testViewers_AnErrorAnswerIsNilNotAnEmptyList` |

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

### Stories

| Check | Broke in | Device | Host |
|---|---|---|---|
| The chat list opens on a stories strip with a ring per unread story | — | Cold start on a 4S: the strip appears above the first chat in ≤ 3 s; an account with active stories shows its avatar inside an accent ring, a read one shows the separator ring; a chat's photo matches the chat list | `testActiveStoryRow_ReadsTheListAndMarksUnread`, `testActiveStoryRows_SendsLoadThenReadsEachChat` |
| A held story bubble hides or restores that chat's stories | — | Hold a friend's story bubble: "Hide from Stories Row" moves the chat off the strip in ≤ 2 s; reopen the archive and hold it there: "Move to Main Stories" puts it back | `testSetActiveStoriesList_SendsTheChatAndTheList` |
| Tapping a story opens the viewer and marks it read | — | Tap the strip: full-screen picture or video, one progress segment per story, tap right moves on, tap left goes back, a hold pauses and release resumes, the close cross returns to the list; log shows `openStory` on entry and `closeStory` on every move | `testOpenStory_SendsBothIds`, `testCloseStory_SendsBothIds` |
| The reaction rail sends and clears the chosen emoji | — | Open a story: the rail fills from `getStoryAvailableReactions`; tap ❤️ and reopen: it is marked chosen; tap it again: the reaction is removed; a live story puts 1★ pending and commits after two seconds | `testAvailableStoryReactions_SendsTheRowSizeAndReadsTheEmojis`, `testSetStoryReaction_SendsTheEmoji`, `testSetStoryReaction_NilRemovesItWithANull` |
| Add Story posts a photo or video with caption, privacy and period | — | Strip → Add Story: pick a picture, type a caption, choose Close Friends and 48 hours, Post: the row rejoins the strip in ≤ 30 s and the story shows the caption; log names `canPostStory` then `postStory` with `active_period` 172800 | `testCanPostStory_ReadsTheOkAndTheRefusal`, `testPostStory_SendsTheContentPrivacyAndPeriod`, `testPostStory_AnEmptyPathSendsNothing` |
| The own-story menu edits, covers, deletes, keeps on the profile and sets privacy | — | Open your story → More: Edit Caption changes the line on screen; Change Cover Frame reports Telegram's answer; Remove from Profile makes it private; Story Privacy sends the chosen users; Delete removes the story and the viewer moves on | `testEditStory_KeepsContentWhenOnlyTheCaptionChanges`, `testEditStoryCover_SendsTheTimestamp`, `testToggleStoryPostedToChatPage_SendsTheFlag`, `testSetStoryPrivacySettings_SendsTheSelectedUsers`, `testDeleteStory_SendsBothIds` |
| The album manager creates, renames, orders, fills and empties an album | — | Stories → Story Albums: + creates "Trip"; drag the second above the first and reopen: order holds; open Trip → Add puts an archived story in it; swipe removes it; More → Rename and Delete report Telegram's answers | `testCreateStoryAlbum_SendsTheNameAndStories`, `testSetStoryAlbumName_ReadsTheChangedAlbum`, `testReorderStoryAlbums_SendsTheWholeOrder`, `testStoriesInAlbum_FlattensTheStories`, `testAddStoriesToAlbum_SendsTheIds`, `testRemoveStoriesFromAlbum_SendsTheIds`, `testReorderStoriesInAlbum_SendsTheOrder`, `testDeleteStoryAlbum_SendsTheAlbumAndChat` |
| Story Info lists interactions, forwards and both graphs, and reports | — | Own story → More → Story Info: Load Interactions names viewers and reactions, Load Public Forwards names reposts, Load Statistics draws the points as bars; Report asks Telegram's options, then the note, and shows the result | `testStoryInteractions_SendsTheFiltersAndRows`, `testChatStoryInteractions_SendsANullReactionForAll`, `testStoryPublicForwards_ReadsMessagesAndReposts`, `testStoryStatistics_FlattensTheGraphPoints`, `testReportStory_FirstAnswerIsTheOptionList`, `testReportStory_ChosenOptionAndTextReachTheServer` |
| Settings → Stories lists the chats with their own story notifications | — | Settings → Stories: each row matches the official client's story switch and mute time; Refresh re-reads in ≤ 2 s; a row opens that chat | `testStoryNotificationExceptions_ReadsEachChat` |
| The archive lists every posted story and pages | — | Stories → Story Archive: the newest stories appear with thumbnails and view counts; Load More extends the list; a row opens the viewer | `testArchivedStoryIds_SendsThePagingAndReturnsIds` |
| Stealth mode sends the request and shows the server's answer | — | Stories → Activate Stealth Mode → Activate: a Premium account reports active; a free account shows Telegram's refusal sentence, not a generic failure | `testActivateStealthMode_SendsAndKeepsTheServerWord` |
| Public discovery searches by tag, location and venue and opens the result | — | Search "#kyiv" → Public Stories → Search Public Stories: results list; the location sheet takes city or country/city and shows found stories; a venue provider and id do the same; a result opens the viewer | `testSearchPublicStoriesByTag_SendsTheTagOffsetAndLimit`, `testSearchPublicStoriesByLocation_SendsTheAddressFields`, `testSearchPublicStoriesByVenue_SendsProviderAndId` |
| A live story starts, shows its RTMP address, streamer, senders, donors and reactions | — | Stories → Start Live Story → RTMP stream: the story id and group call appear, Get RTMP URL fills the address and key and copies them, Replace asks first, Join returns the payload; Streamer, Message Senders and Top Donors fill in place; Add 1★ then Commit/Cancel report Telegram's answer | `testStartLiveStory_SendsTheShapeAndReadsTheGroupCall`, `testJoinLiveStory_SendsTheCallAndReturnsThePayload`, `testLiveStoryRtmpUrl_ReadsUrlAndKey`, `testReplaceLiveStoryRtmpUrl_IsItsOwnRequest`, `testLiveStoryStreamer_FlattensTheParticipant`, `testLiveStoryMessageSenders_FlattenPremiumAndSender`, `testSetLiveStoryMessageSender_BuildsTheSenderObject`, `testLiveStoryTopDonors_ReadsTheTotalAndRows`, `testPendingLiveStoryReactions_SendAddCommitAndRemove` |
| Business story actions show a user account Telegram's refusal | — | Own story → More → Edit as Business Story / Delete as Business Story on a user account: the sheet says Telegram refuses it; the same rows on a business-capable account send the business request | `testDeleteBusinessStory_IsTheBusinessRequest`, `testEditBusinessStory_SendsTheBusinessRequest` |

### Account and sign-in

| Check | Broke in | Device | Host |
|---|---|---|---|
| Typed phone prefix shows its country and Telegram's formatting | — | Login phone step, type `38044…`: the line under the instructions names Ukraine and the formatted number; log shows one `getPhoneNumberInfo` per change | `TGClientAuthFunctionsTests.m`: info flattened from a `phoneNumberInfo` answer; errors answer nil |
| Web login token signs in or is dismissed, with the server's answer | — | Login → Web Login Token: a valid token opens the account; an expired one shows Telegram's message; Dismiss says the web login stops waiting | Requests measured: token and dc_id, `dismissWebToken` |
| A QR link is confirmed by the server | — | Login → Log in with QR Code → Enter a QR Link: a fresh link signs in, a stale one shows the refusal | `session` is success, anything else is an error |
| A Firebase code path asks for the push secret and reports the answer | — | Code step when Telegram sent a Firebase code: link appears; a wrong secret shows the server's refusal | Request measured: `sendAuthenticationFirebaseSms` |
| Changing the number sends, resends and reports a missing code | — | Settings → Privacy & Security → Phone Number: confirmation names the country, a wrong code is refused on screen, Send It Again and It Never Arrived both answer | `sendPhoneNumberCode` type `phoneNumberCodeTypeChange`, null settings; `resendPhoneNumberCode` reason |
| Lost-password recovery and the slow reset both show the server's stage | — | Two-Step Verification → Forgot Password?: wrong code refused; reset answers ok/pending/declined with the date, and a pending reset can be cancelled | `requestPasswordRecovery`, `checkPasswordRecoveryCode`, `recoverPassword`, the three reset results, `cancelPasswordReset` |
| Login email pre-check, change and resend are visible | — | Privacy & Security → Login Email Address: the pre-check answer is shown, the code sheet masks the address, Send It Again refreshes it | `isLoginEmailAddressRequired` maps ok to required; code wrapped as `emailAddressAuthentication` |
| Temporary password reads state and is created with the 2FA password | — | Privacy & Security → Temporary Password: says active/none and how long; Create asks the password and reports the new lifetime | State and create both flatten has/valid_for; a wrong password is an error |
| Ownership handover pre-check is shown before the password | — | Group member → Hand Over Ownership: too-new session names the wait and stops; allowed goes on to the password | Four `canTransferOwnership` results and their retry times |
| Application verification row sends the token for the pending id | — | Settings → Privacy & Security → Application Verification after the update: row says Required and shows the nonce; sending reports accepted/refused | Update keeps id/nonce; `setApplicationVerificationToken` sends both and clears it on ok |

### Usernames and group settings

| Check | Broke in | Device | Host |
|---|---|---|---|
| Account names match `getMe`, and one switch moves a name between Active and Disabled | — | Settings → Edit Profile → Username: each `@name` matches the account; switch a disabled name on, reopen: it is under Active; switch it off: back under Disabled ≤ 2 s | `TGClientUsernamesTests`: `accountUsernamesWithCompletion`, `toggleUsernameIsActive` shape and refusal |
| Edit → drag changes the order Telegram shows | — | Username screen with two active names → Edit → drag the second above the first → Done, reopen: order holds | `TGClientUsernamesTests`: `reorderActiveUsernames` carries the whole list in order |
| Group Settings shows the group's real mode switches | — | Group profile → More → Group Settings: Forum/Join by Request/Hidden/Translation match the official client; toggling one and reopening shows the new state ≤ 2 s | `TGClientUsernamesTests`: one read of `getSupergroup` + full info, and each toggle's request |
| Group username change or refusal is the server's sentence | — | Group Settings → Editable Username: a free name becomes the group's `@name`; a taken one shows Telegram's message and the old name stays | `TGClientUsernamesTests`: `setSupergroupUsername` names the supergroup id; error text survives |
| Disable All keeps the editable name and can be undone | — | Group Settings → Disable All Usernames: other names move to Disabled, the primary stays active; switch one back on | `TGClientUsernamesTests`: `disableAllSupergroupUsernames`, `toggleSupergroupUsernameIsActive` |
| Default admin rights say what the server did | — | Privacy & Security → Default Admin Rights: choosing Standard sends the rights object; a user account shows Telegram's bot-only refusal and the row keeps "Not set" | `TGClientUsernamesTests`: both presets' full `chatAdministratorRights` object and the refusal path |
| Basic-group resolver shows the record before opening | — | Debug Menu → Open Basic Group by ID → a valid id: dialog names the group, member count, status and upgrade state; Open Chat then opens it | `TGClientUsernamesTests`: `getBasicGroup` → `createBasicGroupChat`, title and member count flattened |
| Group Settings carries identity, members, behaviour and tools; the profile More menu has one row for it | — | Group profile → More → Group Settings: the screen pushes at once with a Loading row, then those four sections and the current values ≤ 2 s; a profile with no navigation stack gets the same screen presented with Done | `TGGroupSettingsViewController.rebuild`; the push/present fallback is `TGPresentControllerFrom` |
| A basic group shows only the rows it supports | — | Basic group → Group Settings: Photo, Name, Members, Add/Find, Chat Tools, Import, Clear by Date, Upgrade; no username, invite link, permissions or supergroup switches | `rebuild` reads `chatTypeBasicGroup`; the server refusal path is unchanged |
| Member avatars appear in both member lists | — | Group profile and Group Settings: a member with a profile photo shows it within 2 s; one without keeps initials immediately and the row never blanks; scrolling does not reload the table wholesale | `TGClientAccountTests.testProfilePhoto_*` pins the file-id lookup; `TGMemberAvatarStore` cache/download is UIKit-bound |
| Member rows open the person, and a hold keeps the member actions | — | Group profile and Group Settings → tap a member: their profile opens with the name; hold the same row: Member Info, Member Details, Send Message and the admin rows appear; neither tap opens a private chat | `TGClientGroupsTests.testMembersOfChat_*` pins the row the sheet and the screen read |
| Owner and administrator badges replace the administrator count | — | Group profile → member rows: the owner carries an Owner pill and administrators an Admin pill; the details card lists Members and Invite Link but never "N admins" | `TGClientGroupsTests.testMemberRow_EveryStatusWordAndTheOwnerFlag` |
| Telegram's refusal is shown where rights are missing | — | Non-admin taps Permissions or a mode switch: the sheet names why Telegram refused; the row keeps its old value | The same `BOOL ok, NSString *error` completions the supergroup tests cover |

### Backgrounds and diagnostics

| Check | Broke in | Device | Host |
|---|---|---|---|
| Installed backgrounds match the account, in the light and dark lists | — | Settings → Appearance → Chat Backgrounds: every background on the official client is listed; flipping Dark Theme Backgrounds swaps the list and its default ≤ 2 s | `TGClientAppearanceDiagnosticsTests`: `getInstalledBackgrounds` sends the theme flag, flattens id/name/default/type/file |
| A catalogue search shows a result or Telegram's miss | — | Chat Backgrounds → Search Telegram's Backgrounds → `cat`: the result appears with its thumbnail; a nonsense name shows the server's sentence in the page | `searchBackground` names the query, error text survives |
| Installing a found background makes it the default | — | Tap a search result → Install as Default: the result joins Installed with "Default" under it, and a reopened chat uses it | `setDefaultBackground` sends `inputBackgroundRemote` and keeps the pattern type |
| A background's remote address is readable and copyable | — | Installed → a background → Show Remote URL: the alert names the HTTPS address; Copy Address puts it on the clipboard | `getBackgroundUrl` sends name and type; a chat theme and a nameless background refuse without a request |
| Remove, reset and delete-default each show their answer | — | Remove drops one row ≤ 2 s; Reset restores Telegram's set; Delete Default puts chats back and leaves the installed list | `removeInstalledBackground`, `resetInstalledBackgrounds` and `deleteDefaultBackground` shapes, including refusals |
| Network page reads state, config, database and totals | — | Settings → Data and Storage → Network: TDLib State names the authorization and connection words, Application Config lists key/value rows, Database Statistics shows the report, Data Usage matches the official client's figure | `getCurrentState` flattening, `getApplicationConfig` nested JsonValue, `getDatabaseStatistics` string |
| Network type and added usage entries reach TDLib | — | Network Type → Wi-Fi: the row says Wi-Fi and the server's answer; Add Usage Entry → 100/200 bytes, 3.5 s: the totals grow by the entry | `setNetworkType` object and refusal; `addNetworkStatistics` call entry fields |
| A statistical graph renders its points | — | Network → Statistical Graph → chat id, token: the list names the point count and draws one bar per point; an async token is followed; an expired token shows Telegram's message | `getStatisticalGraph` data/async/error paths and line rendering |
| A custom request shows its own result | — | Debug Menu → Send Custom Request → `getOption`, `{"name":"version"}`: the viewer pretty-prints the result and Copy keeps it | `sendCustomRequest` method and parameters, result string |
| Changing the database key warns, saves and survives a refusal | — | Debug Menu → Database Encryption Key: the warning names the risk; a set key survives a relaunch (TDLib opens the database); a refused change keeps the old key | `setDatabaseEncryptionKey` base64 bytes, key saved on ok, old key restored on error, empty key refused |

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

### File tools, autosave and contact import

| Check | Broke in | Device | Host |
|---|---|---|---|
| File Info lists the record, downloads prefix and resolved remote id | — | Hold a photo → File Info: name, type, size, downloaded, path and remote id fill ≤ 2 s; Copy puts all of them on the clipboard | `TGClientFileToolsTests`: getFile → getRemoteFile → flattened fields |
| File Tools writes a generated file and uploads it | — | Data & Storage → File Tools → Generate: progress passes "generating" and "uploading", path appears; read-back shows the same text | `TGClientFileToolsTests`: preliminaryUploadFile → updateFileGenerationStart → progress/write/finish |
| Cancel stops a generation before it finishes | — | Generate, tap Cancel while "Preparing": no result row, no late "Uploading" stage | `TGClientFileToolsTests`: cancelPreliminaryUploadFile carries the file id |
| Autosave switches write the scope and survive reopening the page | — | Toggle Photos for Groups: reopen Autosave: switch stays as set; clearing exceptions empties the list | `TGClientAutosaveContactsTests`: get/set/clear shapes |
| Imported contact count follows an import | — | Contacts → Import → Import: alert names the accepted count; footer shows the account total | `TGClientAutosaveContactsTests`: changeImportedContacts + getImportedContactCount |
| Auto-download presets come from Telegram, not a constant | — | Data & Storage → Presets shows Medium sizes; choose High: Wi-Fi switch follows and the toast names the preset | `TGClientFileToolsTests`: getAutoDownloadSettingsPresets flat shape |
| Autosave follows a change made on another client | — | With Autosave open, change a scope on a second device: the switch and exception count move ≤ 2 s without reopening | `TGUpdatesTests`: `updateAutosaveSettings` keeps the scope and posts `TGAutosaveSettingsChangedNotification` |
| Active notifications draw, change and remove | — | Settings → Notifications and Sounds → Active: groups name their chat and count; a new background message adds a row; remove drops it; Clear All empties the list; the spinner shows while TDLib reports pending | `TGUpdatesTests`: the four `updateNotification*` shapes; `TGClientAccountTests`: `removeNotification` / `removeNotificationGroup` ids and cache |
| A language pack change reaches the page | — | With Language open and Strings read once, change a string on another client: the Strings detail and the sheet follow ≤ 2 s | `TGUpdatesTests`: `updateLanguagePackStrings` names the pack and keeps the change |

### Orders, call diagnostics, websites, bot buttons and poll answers

The screens are UIKit and checked on device; every request shape behind them is in `TGClientMiscTests`. A user account may see Telegram's refusal on the bot-only rows; the refusal itself is the expected screen.

| Check | Broke in | Device | Host |
|---|---|---|---|
| Saved order reads, then deletes after a confirm | — | Privacy and Security → Orders and Payment Data: the row names the saved name ≤ 2 s; Delete → confirm: the row says "None saved" and reopening the page keeps it gone | `testSavedOrderInfo_ReadsTheOrderTelegramKept`, `testDeleteSavedOrderInfo_SendsTheRequestAndKeepsTheRefusal` |
| Card lookup shows the provider's title and links | — | Type a full card number: the sheet names the card ≤ 3 s and offers the provider's action titles; a short number never sends and says why | `testBankCardInfo_StripsSpacesBeforeTheLookup`, `testBankCardInfo_AShortNumberNeverLeavesTheDevice` |
| An offer names the message and a Stars price | — | Add an Offer → chat id, message id, 250: either "Offer sent" with the message id or Telegram's refusal, never a silent sheet | `testAddOffer_BuildsEverySendOptionAndTheStarPrice`, `testAddOffer_NoPriceSendsNothing` |
| Order validation reads the order-info id and shipping | — | Validate an Order → invoice + seven fields: the sheet names `order_info_id` and each shipping option, or Telegram's sentence | `testValidateOrderInfo_BuildsEveryRequiredOrderField`, `testValidateOrderInfo_NoInvoiceNameSendsNothing` |
| A finished call sends its log file | — | Recent Calls → a call → Send Call Log: "Telegram accepted the call log"; the row then reads "log sent", survives a reopen, and the log shows one `sendCallLog` with a local path that no longer exists | `testSendCallLog_WritesALocalFileForTheCallMessage`, `testSendCallLog_RefusalCarriesTheServersSentence` |
| A finished call sends its debug record | — | Same card → Send Debug Information: accepted or refused with the server's words; on success the row reads "debug sent" and the request carries the JSON | `testSendCallDebugInformation_NamesTheCallAndCarriesTheJSON`, `testSendCallDebugInformation_EmptyTextNeverLeavesTheDevice` |
| A session's calls switch and the idle timeout are real | — | Devices → tap a session → Stop Accepting Calls: reopening the row shows the new state; Inactive Session Timeout → 90 days: the row says 90 and survives reopening | `testSessions_CarryTheIdleTimeoutAndCallsSwitch`, `testToggleSessionCanAcceptCalls_SendsTheBooleanAndTheRefusal`, `testSetInactiveSessionTtl_SendsTheDaysAndRefusesOutOfRange` |
| Connected websites list and sign out one or all | — | Devices → Connected Websites: every site with browser and last use ≤ 3 s; sign one out: the row disappears after the re-read; Disconnect All → confirm: the list empties | `testConnectedWebsites_ReadsEverySite`, `testDisconnectWebsite_NamesTheWebsiteId`, `testDisconnectAllWebsites_SendsTheOneRequest` |
| A prepared keyboard button is saved and read back | — | Debug → Bot Tools → Save Prepared Keyboard Button: the prepared id appears, Fetch It Back shows the same text, or a user account shows the refusal | `testSavePreparedKeyboardButton_BuildsACompleteTextButton`, `testPreparedKeyboardButton_ReadsTheButtonAndTheRefusal` |
| A poll answer's card names what it still allows | — | Tap an answer: the card lists delete/reply/another-chat/link flags ≤ 2 s, then Vote is one tap below; a closed poll shows the flags without Vote | `testPollOptionProperties_ReadsEveryFlag`, `testPollOptionProperties_RefusalIsTheServersSentence` |

---

## Testing: feature × device matrix

Run `scripts/devrun.sh` for device-side checks. Host suite: `make -f tests/Makefile test`.
