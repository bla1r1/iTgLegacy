# Design Spec — iOS 6 Reimagined

**Project:** LegacyTG · **Branch:** `redesign/ios6-reimagined`  
**Target:** iOS 6.0–12.5.7, armv7 & arm64

---

## Concept

A Telegram client that looks like the iOS it runs on. Since the November 2026
pass (`996512d`, `8e0d1b4`, `8e86854`) the chrome — bars, grouped tables,
settings cells, switches, search, alerts — is the system's own UIKit drawing
on every supported version. The app draws only what the system has no analogue
for: the chat canvas, custom sheets, snackbars, the media viewer, the player,
the call screen and the procedural icon engine. Light only: a theme file
recolours the chat, never the chrome.

Drawing that the app still does is CoreGraphics, `@1x`/`@2x` cached, targeting
60 FPS on A5/A6.

No neon gradients, no card-in-card layouts, no emoji as UI icons.

---

## Route inventory

| Screen | Controller | Notes |
|---|---|---|
| Chats list | `TGChatListViewController` | Search, folder filter, swipe actions (Mute, Archive, Delete) |
| Chat conversation | `TGChatViewController` | History, input bar, voice lock, audio playback dock |
| Contacts | `TGContactsViewController` | Alphabetical with A–Z index, search, add contact |
| New contact | `TGNewContactViewController` | Phone + name, recessed inputs |
| Settings | `TGSettingsViewController` | Profile card, sub-pages for Appearance / Notifications / Privacy / Folders / Devices |
| Appearance | `TGSettingsViewController+AppearancePages` | Light only: font size, wallpaper on/off, chat theme-file import |
| Profile | `TGProfileViewController` | Avatar, shared media tabs, block/leave |
| Music player (modal) | `TGPlayerView` | iPod-style deck, vinyl art, scrubber, queue |
| Mini-player (docked) | `TGPlayerView` | Persistent bar above tab bar |
| VoIP call | `TGCallViewController` | E2EE audio/video, embossed action buttons |
| Media viewer | `TGMediaViewer` | Fullscreen photo/video, pinch-to-zoom |
| Auth flow | `TGLoginViewController` | Phone → code → 2FA → QR |
| Sheets & alerts | `TGAlertSheet`, `TGSheet` | Alerts are the system's (UIAlertView/UIActionSheet ≤ iOS 7, UIAlertController ≥ 8); `TGSheet` hosts the app's bottom sheets (attach, gifts, date pickers) |
| Toasts | `TGSnackbar` | Floating bar, countdown ring, Undo |

---

## Token system

All colours from `TGTheme+Colours`. All sizes and metrics from `src/Core/TGStyle.h`. Screens ask for a role, never a number. `scripts/lint_tokens.sh` enforces this.

### Type scale

| Role | Size | Weight | Usage |
|---|---|---|---|
| `TGFontTitle` | 17pt | Semibold | Navigation titles |
| `TGFontRow` | 16pt | Regular | List rows |
| `TGFontCaption` | 13pt | Regular | Subtitles, timestamps |
| `TGFontFootnote` | 11pt | Regular | Badges, labels |
| `TGFontMono` | 13pt | Regular | Code spans |

### Colour roles

Light only: Night and Auto-Night were removed in `8e86854`, and a chat theme
file that declares a dark palette is refused. Roles live in `TGTheme+Colours`;
the app draws no hue the running OS does not also know:

| Token | Role |
|---|---|
| `groupedBackgroundColour` / `listBackgroundColour` | screen and list plates |
| `cardBackgroundColour` | cards over a grouped screen |
| `primaryTextColour` / `secondaryTextColour` | text |
| `accentColour` / `onAccentColour` | buttons, links, unread badges; content over them |
| `destructiveColour` | delete actions |
| `separatorColour` | hairlines, bubble borders |
| `bubbleMineColour` / `bubbleTheirsColour` | the chat — the only surface a theme file recolours |
| `barTitleColour` / `barSubtitleColour` / `barButtonColour` | content the system bar draws |

### Metrics

| Token | Value |
|---|---|
| `TGMetricListAvatar` | 40 pt |
| `TGMetricTabBarH` | 49 pt (the system tab bar's own height) |
| `TGMetricInputBarHeight` | 48 pt |
| `TGMetricCallButtonSide` | 60 pt |
| `TGMetricCornerControl` | 8 pt |

The navigation bar has no metric of ours — the system draws it.

---

## TGUI component framework (`src/UI/`)

Mostly retired: `996512d` deleted `TGSwitch` and `TGSearchBar` in favour of the
system's own, and the bars and lists stopped being drawn at all. What is left
and what it does:

| Component | Class | Where it lives |
|---|---|---|
| Button | `TGButton` | production: login step buttons, chat edit-mode toolbar |
| Gallery-only kit | `TGTextField`, `TGSlider`, `TGSegmentedControl`, `TGCardView`, `TGBadge`, `TGAvatarView` | showcase only; no production call sites |
| Reaction bar | `TGReactionPicker` | the message context menu |
| Recording strip | `TGRecordBar` | the voice note and the round video: one strip, so they cannot drift apart |
| Popup menu | `TGPopupMenu` | plain lists route to a system action sheet; drawn variants remain for the reactions bar and the sticker-set header |
| Design lab | `TGGalleryViewController` | Settings → Appearance → UI Component Gallery |

---

## Music player

Full-screen modal with vinyl album art (drop shadow + gloss overlay), scrubber, transport controls, repeat/shuffle, queue sheet. Global mini-player docked above the tab bar with thumbnail, track title, play/pause, close.

---

## Messages & feedback

| Component | Behaviour |
|---|---|
| `TGSnackbar` | Bar above the chrome, countdown ring, Undo |
| `TGAlertSheet` | The system alert under iOS 7, `UIAlertController` from iOS 8, behind one block API: message, confirm, choices, input (incl. secure entry) |
| `TGAlertSheet` (destructive) | Destructive confirms are asked from an action sheet with a red button |
| `TGStatusBanner` | Pinned under nav bar — Connecting / Updating + native spinner |
| `TGEmptyView` | Centered illustration, headline, action button |
| Form errors | Red input border, red caption + warning glyph |

---

## Implementation progress

- [x] Worktree (`redesign/ios6-reimagined`)
- [x] Codebase & UX audit
- [x] Design spec
- [x] Procedural drawing engine (`TGTheme+Drawing.m`, `TGStyle.h/m`)
- [x] Vector icon extensions (`TGIcons.h/m`)
- [x] Music player (`TGMusicPlayer`, `TGPlayerView` mini & modal)
- [x] Root VC mini-player integration
- [x] In-chat audio bar (`TGChatViewController+Audio.m`)
- [x] Empty states & connection banner
- [x] TGUI framework (`src/UI/`)
- [x] Design lab (`TGGalleryViewController`)
- [x] Token lint (`scripts/lint_tokens.sh`)
- [x] Full test suite (`make -f tests/Makefile test`)
- [x] System chrome on every iOS version (`996512d`)
- [x] System alerts and action sheets under `TGAlertSheet` (`8e0d1b4`)
- [x] Light only: no Night/Auto-Night, theme files recolour the chat (`8e86854`)
