# LegacyTG Roadmap

A Telegram client for iPhone 3GS/4/4S on iOS 6–7, built on TDLib.

Status legend: **done** · *in progress* · planned · out of scope

---

## Where the project stands

The app was rewritten onto TDLib. libtg — the hand-written MTProto stack it
started with — is gone, along with every screen built on its C structs. What
remains is roughly 2500 lines written for this app plus TDLib itself, loaded at
runtime as `libtdjson.dylib`.

Reference point for "missing": Telegram for iOS, Telegram Desktop and
[Nicegram](https://nicegram.app)-class forks. This list is what those have and
this does not.

---

## 1 · Messaging core

| | Feature | Notes |
|---|---|---|
| **done** | Sign in by phone, code, 2FA password | 1.3 s from launch to authorized on a 4S |
| **done** | Chat list with avatars, previews, unread badges | |
| **done** | Message history, paged | |
| **done** | Send text | |
| **done** | Live updates while a chat is open | `updateNewMessage` |
| **done** | Read receipts sent | `viewMessages` |
| **done** | Reply to a message | quoted message shown above the reply |
| **done** | Forward a message | source is named on the message |
| **done** | Edit a message | marked as edited |
| **done** | Delete a message from the UI | long press |
| **done** | Draft persistence | |
| **done** | Typing indicators | takes over the header subtitle |
| **done** | Search in chat and globally | in-chat search lives in the profile |
| **done** | Pinned message banner | |
| **done** | Reactions | shown on messages; can add a thumbs up |
| | Message selection and multi-actions | one message at a time |
| **done** | Jump to the quoted message | scrolls and flashes it |
| **done** | Unread separator and jump-to-unread | opens at the Unread Messages bar; a jump-down button counts what arrives while reading above |
| | Scheduled and silent sending | |
| **done** | Saved Messages | from the Folders menu |

## 2 · Media

| | Feature | Notes |
|---|---|---|
| **done** | Photos inline, full-screen viewer | hold to save |
| **done** | Video and video notes, played | `MPMoviePlayerViewController` |
| **done** | Voice notes, played | Opus decoded to PCM via libopusfile — iOS 7 cannot decode Opus |
| **done** | WebP stickers | libwebp; the category had to be written, the file in the repo held only a header |
| **done** | Animated `.tgs` stickers | `TGLottieView`, a Lottie subset written for this app |
| **done** | Documents with name and size | |
| **done** | Send a photo from the library | untested — needs a real tap |
| | `.webm` stickers | VP9; no decoder exists on this hardware |
| | Lottie: masks, mattes, trim paths, gradients, repeaters | stickers using them draw approximately |
| **done** | Record and send a voice note | libopusenc; hold the microphone. Verified on a 4S: 4 seconds encodes to 22KB and arrives |
| **done** | Send video, location, contacts | documents still missing - no file browser on iOS 7 |
| **done** | Albums (grouped media) | one block, one timestamp |
| *in progress* | Download progress and cancel | progress shown; no cancel |
| **done** | Save to camera roll | hold the full-screen picture |
| **done** | GIF autoplay | muted loop in the bubble on A5 and up (Power Saving switch); tap still opens the viewer |
| **done** | Send stickers and GIFs | emoji / sticker / GIF panel; GIF search through @gif |
| *in progress* | Sticker sets: install, browse, favourites | browse installed sets and favourites; installing new sets not yet |
| *in progress* | Photo viewer | zooms; no swipe between photos |
| **done** | Polls | question, options and shares; tap to vote |

## 3 · Chats and groups

| | Feature | Notes |
|---|---|---|
| **done** | Basic groups and supergroups | sender names, per-person colours |
| **done** | Service messages | joins, leaves, renames, pins, creation |
| **done** | Forum topics | opens on a topic list |
| **done** | Member count in the header | |
| **done** | Profile screen | avatar, username, phone, members, shared media, gifts, premium |
| **done** | Sender avatars in groups | Telegram's own placeholder palette and mapping |
| **done** | Start a new chat from contacts | |
| *in progress* | Channels | read, join, mute; comments and reactions do not |
| | Secret chats | disabled at TDLib init |
| **done** | Archive | a row above the list |
| **done** | Chat folders | offered from the Folders button |
| **done** | Mute, pin, leave, delete a chat | hold a row in the list |
| *in progress* | Group member list, admin actions | list is in the profile; no admin actions |
| | Invite links | |
| | Create a group or channel | join only |
| | Create and manage forum topics | read only |
| **done** | Block a user | from the profile |
| | Report a user or chat | |
| **done** | Online status and last seen | in the header of a private chat |

## 4 · Presentation

| | Feature | Notes |
|---|---|---|
| **done** | Skeuomorphic and flat themes, switchable | defaults to what the OS shipped with: skeuomorphic below iOS 7, flat from 7 |
| *in progress* | Skeuomorphic icon set and chrome | app icon, tab bar and buttons still the inherited artwork |
| | Dark theme as a built-in | available today only by importing one |
| | Wallpapers from Telegram's own collection | `getBackgrounds` is not called |
| | Font size setting | |
| | Landscape and iPad layouts | portrait iPhone only |
| | 4-inch screen layout check | built for 3.5-inch, never verified on a 5/5c |
| | Localisation | English strings, hardcoded |
| **done** | Themes from the official clients | `.tgios-theme` JSON and `.attheme`; zipped exports rejected |
| **done** | Chat wallpaper | a picture from the library |

## 5 · Platform and delivery

| | Feature | Notes |
|---|---|---|
| **done** | armv7 build that runs on iOS 7.1.2 | `tools/machofix.c` repairs what the linker breaks |
| **done** | TDLib as a dylib | static linking exceeds the 16 MB armv7 branch limit |
| **done** | Unattended device runs | `scripts/devrun.sh`: build, install, launch, log, screenshot |
| *in progress* | iOS 6 support | iOS 7-only calls are guarded; never run on real iOS 6 hardware |
| | Push notifications | needs an `aps-environment` entitlement the build does not have |
| | Background fetch | |
| | arm64 build | Makefile target exists, unexercised since the rewrite |
| | Crash reporting | crash logs are pulled by hand today |

---

## 6 · The rest of Telegram

Everything the official client has that this one does not, with what it would
take. TDLib here is 1.8.66, so the API for nearly all of it is present - the
question is almost always the screen, not the protocol.

### Reachable, not yet written

| Feature | TDLib | Note |
|---|---|---|
| Stories: view a contact's | `getChatActiveStories`, `getStory` | photo and video stories would draw; the ring in the chat list is the bigger job |
| Premium status of the account | `getPremiumState` | what is active and until when |
| Auto-download rules | `setAutoDownloadSettings` | worth having on 3G, which is what this phone has |
| Per-chat notification settings | `setChatNotificationSettings` | mute is all that is wired |
| Privacy settings | `getUserPrivacySettingRules` | last seen, photo, calls, forwards |
| Two-step verification setup | `setPassword`, `getPasswordState` | login already handles an existing password |
| Create a group or channel | `createNewBasicGroupChat` etc. | joining works |
| Invite links | `createChatInviteLink` | |
| Admin actions, member management | `setChatMemberStatus` | the member list is read-only |
| Forum topic creation | `createForumTopic` | topics are read-only |
| Scheduled and silent sending | `messageSendOptions` | |
| Message multi-select | - | one at a time |
| Sticker sets: browse, install | `getInstalledStickerSets` | only the recents strip exists |
| GIF panel and saved GIFs | `getSavedAnimations` | |
| Emoji and reaction pickers | `getAvailableReactions` | one hardcoded thumbs up |
| Chat folder editing | `createChatFolder` | folders are read-only |
| Archive settings, auto-delete timers | `setChatMessageAutoDeleteTime` | |
| Story posting | `sendStory` | |

### Blocked by the machine, not by the API

Every device falls into one of four tiers, and a feature asks for a tier
rather than for a version. `Settings > This device` lists them with what each
one is waiting for, so a missing button is explained rather than mysterious.

| Tier | Devices | What it means |
|---|---|---|
| Vintage | iPhone 3GS, 4, iPod touch 4 | armv7, 256-512MB, never went past iOS 7 |
| Legacy | iPhone 4S, 5, 5c, iPod touch 5 | armv7, up to iOS 10 |
| Modern | iPhone 5s, 6, 6 Plus, iPod touch 6 | the first 64-bit chips, all stopped at 12.5 |
| Full | iPhone 6s and later | 2GB and up |

What each gated feature waits for:

| Feature | Gate | Where it turns on |
|---|---|---|
| Custom emoji, animated emoji status | `canAnimateInline` | any 64-bit device (A7+); one Lottie frame per message is more than an A5 has |
| Mini apps, bot web apps, payment pages | `canRunWebApps` | iOS 9 and up, where WKWebView's JavaScript is usable |
| Multiple accounts | `canHoldMultipleAccounts` | 1GB of RAM or more; each TDLib client costs tens of megabytes |
| Video calls | `canEncodeVideoCall` | not reachable at all today: video rides tgcalls, and TDLib names the field "supported tgcalls versions". tgcalls is WebRTC - C++17, no armv7 build - and iOS 7 has no public VideoToolbox encoder either |
| Voice calls | - | **built, and the other end refuses.** libtgvoip is vendored, compiles for armv7 and rings the callee - a current Telegram for iOS answers with "cannot accept this call with this version". Modern clients speak only tgcalls; advertising `library_versions: ["2.4.4"]` with layers 65-92, which is exactly what the official clients sent while libtgvoip was theirs, is no longer enough. The call path works end to end between two peers that accept 2.4.4 |

The 64-bit build now links (`make ipa-arm64`); what it still lacks is an arm64
`libtdjson.dylib`, which is the same script run for a second architecture. The
WebP framework in the tree carries an arm64 slice, but its archive members were
written by an `ar` that did not align them, so the link is fed a repacked copy.

### Blocked by not being the official app

No iOS version changes these.

| Feature | Why |
|---|---|
| Buying Premium, Stars or gifts | payment goes through StoreKit or Fragment; an app with no App Store receipt can complete neither. Sending a gift from a balance you already have is a plain API call and could be added |
| Push notifications | the push has to be delivered to a bundle id whose APNs certificate Telegram's servers hold, which is the official app's |
| Translation and transcription | server features gated behind Premium |

### Just not written yet

| Feature | Why |
|---|---|
| Secret chats | disabled at TDLib init - one flag - plus the key-verification screens |
| Live locations | a background location task iOS 7 will kill, but iOS 9 and up have the right API |
| Group calls and live streams | the same tgcalls wall as video, plus mixing |
