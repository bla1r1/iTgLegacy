# LegacyTG Roadmap

Telegram client for iPhone 3GS/4/4S on iOS 6–7, built on TDLib.

Status: **done** · *in progress* · planned · out of scope

The app was fully rewritten onto TDLib. `libtg` — the hand-written MTProto stack — is gone. What remains is ~2500 lines written for this app plus TDLib itself, loaded at runtime as `libtdjson.dylib`.

---

## 1 · Messaging core

| | Feature | Notes |
|---|---|---|
| **done** | Sign in by phone, code, 2FA | 1.3 s from launch to authorized on a 4S |
| **done** | Chat list with avatars, previews, badges | |
| **done** | Message history, paged | |
| **done** | Send text | |
| **done** | Live updates in an open chat | `updateNewMessage` |
| **done** | Read receipts | `viewMessages` |
| **done** | Reply | quoted message shown above |
| **done** | Forward | source named on the message |
| **done** | Edit | marked as edited |
| **done** | Delete | long press |
| **done** | Draft persistence | |
| **done** | Typing indicators | takes over the header subtitle |
| **done** | Search in chat and globally | in-chat search lives in the profile |
| **done** | Pinned message banner | |
| **done** | Reactions | shown on messages; thumbs up |
| | Message multi-select | one at a time |
| **done** | Jump to quoted message | scrolls and flashes |
| **done** | Unread separator and jump-to-unread | |
| | Scheduled and silent sending | |
| **done** | Saved Messages | from the Folders menu |

## 2 · Media

| | Feature | Notes |
|---|---|---|
| **done** | Photos inline, full-screen viewer | hold to save |
| **done** | Video and video notes | `MPMoviePlayerViewController` |
| **done** | Voice notes, played | Opus → PCM via libopusfile |
| **done** | WebP stickers | libwebp |
| **done** | Animated `.tgs` stickers | `TGLottieView` |
| **done** | Documents with name and size | |
| **done** | Send photo from library | |
| | `.webm` stickers | VP9 — no decoder on this hardware |
| | Lottie: mattes, trim paths, repeaters | gradients done; the rest approximate |
| **done** | Record and send voice note | libopusenc; 4 s → 22 KB on a 4S |
| **done** | Send video, location, contacts | no file browser on iOS 7 |
| **done** | Albums (grouped media) | one block, one timestamp |
| *in progress* | Download progress and cancel | progress shown; no cancel |
| **done** | Save to camera roll | hold the full-screen image |
| **done** | GIF autoplay | muted loop on A5+; Power Saving switch |
| **done** | Send stickers and GIFs | GIF search through @gif |
| *in progress* | Sticker sets: install, browse, favourites | browse and favourites done; install by link in |
| *in progress* | Photo viewer | zooms; no swipe between photos |
| **done** | Polls | tap to vote |

## 3 · Chats and groups

| | Feature | Notes |
|---|---|---|
| **done** | Groups and supergroups | sender names, per-person colours |
| **done** | Service messages | joins, leaves, renames, pins |
| **done** | Forum topics | opens on topic list |
| **done** | Member count in header | |
| **done** | Profile screen | avatar, phone, members, shared media, gifts |
| **done** | Sender avatars in groups | |
| **done** | Start a new chat from contacts | |
| *in progress* | Channels | read, join, mute; no comments/reactions |
| | Secret chats | disabled at TDLib init |
| **done** | Archive | row above the list |
| **done** | Chat folders | |
| **done** | Mute, pin, leave, delete | hold a row |
| *in progress* | Group member list, admin actions | list in profile; no admin actions |
| | Invite links | |
| | Create group or channel | join only |
| | Create/manage forum topics | read only |
| **done** | Block a user | from profile |
| **done** | Online status / last seen | private chat header |

## 4 · Presentation

| | Feature | Notes |
|---|---|---|
| **done** | Chrome is the system's | `996512d` + `8e0d1b4`: bars, grouped tables, cells, switches, search, alerts draw by UIKit on every supported iOS version; the app keeps drawing only the chat, sheets, snackbars, viewer, player, call screen |
| **done** | Procedural icon set | every glyph drawn from published SVG paths (`6861366`); the tab bar carries outline/filled pairs |
| out of scope | Dark theme | light only: Night and Auto-Night removed, dark theme files refused (`8e86854`) |
| | Telegram wallpaper collection | `getBackgrounds` not called |
| **done** | Font size setting | Appearance → Message Text Size |
| | Landscape / iPad layouts | portrait iPhone only |
| | 4-inch screen check | built for 3.5-inch, never tested on a 5/5c |
| | Localisation | English only, hardcoded |
| **done** | Import official client themes | `.tgios-theme` and `.attheme`; zipped exports rejected |
| **done** | Chat wallpaper | photo from library |

## 5 · Platform and delivery

| | Feature | Notes |
|---|---|---|
| **done** | armv7 build on iOS 7.1.2 | `tools/machofix.c` repairs linker breakage |
| **done** | TDLib as a dylib | static linking exceeds the 16 MB armv7 branch limit |
| **done** | Unattended device runs | `scripts/devrun.sh` |
| *in progress* | iOS 6 support | iOS 7-only calls are guarded; never run on real iOS 6 |
| | Push notifications | needs `aps-environment` entitlement |
| | Background fetch | |
| | arm64 build | Makefile target exists, unexercised since rewrite |
| | Crash reporting | pulled by hand today |

---

## 6 · The rest of Telegram

TDLib is 1.8.66 — the API is mostly there. The question is almost always the screen, not the protocol.

### Reachable, not yet written

| Feature | TDLib call | Note |
|---|---|---|
| Stories: view | `getChatActiveStories`, `getStory` | photo/video would draw; the ring in the chat list is the bigger job |
| Premium status | `getPremiumState` | |
| Auto-download rules | `setAutoDownloadSettings` | worth having on 3G |
| Per-chat notification settings | `setChatNotificationSettings` | mute is all that's wired |
| Privacy settings | `getUserPrivacySettingRules` | last seen, photo, calls, forwards |
| 2FA setup | `setPassword`, `getPasswordState` | login already handles an existing password |
| Create group/channel | `createNewBasicGroupChat` etc. | joining works |
| Invite links | `createChatInviteLink` | |
| Admin actions | `setChatMemberStatus` | member list is read-only |
| Forum topic creation | `createForumTopic` | topics are read-only |
| Scheduled/silent sending | `messageSendOptions` | |
| Message multi-select | — | one at a time |
| Sticker set browser | `getInstalledStickerSets` | recents strip only |
| GIF panel / saved GIFs | `getSavedAnimations` | |
| Reaction picker | `getAvailableReactions` | one hardcoded thumbs up |
| Folder editing | `createChatFolder` | folders are read-only |
| Story posting | `sendStory` | |

### Blocked by the machine

Device tiers — a feature asks for a tier, not an iOS version. `Settings > This device` explains what each missing button is waiting for.

| Tier | Devices | RAM |
|---|---|---|
| Vintage | iPhone 3GS/4, iPod touch 4 | 256–512 MB, never past iOS 7 |
| Legacy | iPhone 4S/5/5c, iPod touch 5 | up to iOS 10 |
| Modern | iPhone 5s/6/6+, iPod touch 6 | first 64-bit, stopped at 12.5 |
| Full | iPhone 6s+ | 2 GB+ |

| Feature | Gate |
|---|---|
| Custom emoji in message text | not built on any device; shown as the plain emoji |
| Mini apps, web apps | `canRunWebApps` — iOS 9+, WKWebView JS |
| Multiple accounts | Every device, one active at a time; each has its own TDLib directory |
| Video calls | `canEncodeVideoCall` — blocked: tgcalls is WebRTC/C++17, no armv7 build, iOS 7 has no VideoToolbox encoder |
| Voice calls | **built, but the other end refuses.** libtgvoip compiles and rings — modern Telegram iOS rejects with "cannot accept this call with this version". Works between two peers that still accept 2.4.4 |

The arm64 build links (`make ipa-arm64`); what's missing is an arm64 `libtdjson.dylib` — same build script, second architecture.

### Blocked by not being the official app

| Feature | Why |
|---|---|
| Buying Premium / Stars / gifts | StoreKit / Fragment; no App Store receipt |
| Push notifications | APNs cert is held by Telegram's servers for the official bundle ID |
| Translation / transcription | Premium server features |

### Just not written yet

| Feature | Why |
|---|---|
| Secret chats | disabled at TDLib init — one flag — plus key-verification screens |
| Live locations | background location iOS 7 kills; iOS 9+ has the API |
| Group calls / live streams | same tgcalls wall as video, plus mixing |
