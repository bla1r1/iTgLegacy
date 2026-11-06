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
| **done** | Video stickers (`.webm`) | VP9 with alpha via `TGWebMDecoder` & streaming player |
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

---

## 7 · Audit: Stubbed & Semi-functional Surfaces (Real Closure Backlog)

An audit of `src/Controllers/` reveals that while core messaging, 1:1 voice calls (`tgcalls 9.0.0`), standard stories, stickers, and profile workflows are fully functional, several screens and entry points were added to satisfy TDLib coverage metrics (`scripts/tdlib_wired.py`) or wire protocol stubs. They have dedicated UI controllers but lack underlying media engines, expose bot-only methods to user accounts, or act as raw debug harnesses.

### 1. Group Calls & Video Streaming (Signaling wired, media engine missing)
- **`TGGroupCallViewController` («Group Call»)**:
  - *Current state*: Joins call signaling in TDLib, updates participant states and mute flags. However, audio and video pipelines do not exist. Code explicitly states: `self.noteLabel.text = @"Joined. This client has no group-call audio engine."` and `@"TDLib records the flag; there is no frame to pause"`.
  - *Closure requirement*: Implement WebRTC/RTP multi-peer audio mixing and AudioUnit playback/recording pipeline; wire video decode for active speaker.
- **`TGVideoChatSetupViewController` & `TGVideoChatStreamViewController`**:
  - *Current state*: Administrative/debug tables. Screen sharing (`startScreenSharing`) opens a text alert asking the user to manually type the raw join payload string. Stream segment fetcher saves raw OGG/MP4 chunks to `/tmp` with status note: `@"client has no group-call media engine to decode it in-app"`. Cryptographic test buttons run sample AES checks.
  - *Closure requirement*: Replace manual payload text prompts with internal tgcalls pipeline; integrate stream receiver with a hardware/software player rather than file dump.
- **`TGLiveStoryViewController` («Live Story»)**:
  - *Current state*: Opens from `TGStoryViewerViewController` ("Open Live Story"). Inherits from `TGListViewController` and merely lists RTMP address, streamer ID, and reaction buttons. Joining copies the tgcalls payload to `UIPasteboard`. No video player pipeline exists.
  - *Closure requirement*: AVPlayer / RTMP streaming player overlay inside `TGStoryViewerViewController` for live broadcast playback.

### 2. Bot-Only & Staff Functions Exposed in User UI (Always Refused by Server)
- **`TGEphemeralViewController` («Ephemeral»)**:
  - *Current state*: Linked in chat attach menu (+) > More > «Ephemeral». Calls `sendEphemeralMessage`. Explicit comment: `@"sendEphemeralMessage is for bots. A user account sees Telegram's refusal sentence"`.
  - *Closure requirement*: Remove from user chat attach sheet; gate behind bot session mode or map to self-destructing media.
- **Settings > «Bot Tools»**:
  - *Current state*: 7 rows (Prepared Keyboard Button, Close Web App, Bot Name/Description, Bot Menu Button, etc.) prompting user for numeric Bot IDs via `TGAlertSheet` and failing with server refusal.
  - *Closure requirement*: Hide from user settings; move into a bot management section accessible only when managing a bot token.
- **`TGAdminRightsViewController` («Default Admin Rights»)**:
  - *Current state*: Settings > Privacy & Security > Default Admin Rights. Calls `setDefaultGroupAdministratorRights` which is bot-only. Code notes: `@"Both requests are bot-only: a user account is expected to see the refusal"`.
  - *Closure requirement*: Restrict to bot administration views.
- **`TGBusinessProfileViewController` (under Telegram Business)**:
  - *Current state*: Name/Bio/Photo fields call `setBusinessAccount*` with `connectionId`. Without an active bot business connection, Telegram always returns refusal.
  - *Closure requirement*: Separate user subscriber settings (hours, location, away messages — which work) from bot business connection fields.
- **`TGBusinessConnectionViewController` & `TGBusinessMessagesViewController`**:
  - *Current state*: Manual test harness where user must paste a bot connection ID, chat ID, and message ID to trigger bot calls (`sendBusinessMessage`, etc.).
  - *Closure requirement*: Relocate to developer options or remove.

### 3. Non-Interactive Stubs & Raw Diagnostic Harnesses
- **`TGDiceViewController` («Stake Dice»)**:
  - *Current state*: Linked in attach sheet (+) and profile More. Calls TON staking gambling API `getStakeDiceState`. Has **no `didSelectRowAtIndexPath`** (completely read-only, non-interactive dump of state hashes and amounts).
  - *Closure requirement*: Replace with official Telegram animated dice picker (`🎲`, `🎯`, `🏀`, `⚽`, `🎰`, `🎳`) to send dice emoji messages.
- **`TGGameScoresViewController` («Game Scores»)**:
  - *Current state*: Opened from game message context menu. Form asking for manual text input of Chat ID, Message ID, User ID, and Score to call bot-only `setGameScore`.
  - *Closure requirement*: Convert to a native high scores leaderboard displaying `getGameHighScores`.
- **`TGStarsGiftsViewController` («Premium, Stars and Gifts»)**:
  - *Current state*: Linked under Tier 3 Audit as "Read-only". 30 action buttons dumping raw strings into an `answerLines` label. No StoreKit or payment provider.
  - *Closure requirement*: Build a true visual gifts catalogue and stars balance card, or move raw dumps to debug.
- **`TGTestHarnessViewController`, `TGSupportInfoViewController`, `TGWebProxyCarrierViewController`, `TGEnvironmentViewController`**:
  - *Current state*: Settings > Tier 3 Audit. Diagnostic screens directly calling TDLib internal `test*` methods, staff support notes, or manual postMessage carriers.
  - *Closure requirement*: Move behind `TG_DEV` debug menu, out of release Settings.
- **`TGChatToolsViewController` Manual ID Prompts**:
  - *Current state*: "Answer Protected-Content Request" and "Answer Join Request Query" ask user to manually type numeric Message ID / Query ID.
  - *Closure requirement*: Present structured selection lists for pending requests.
- **Settings Payment Dev Flows**:
  - *Current state*: Order validation (`validateOrderFlow`) triggers a sequence of 8 successive text input alerts.
  - *Closure requirement*: Replace with a single structured checkout form or gate behind developer menu.
