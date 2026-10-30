# Design Spec — iOS 6 Reimagined

**Project:** LegacyTG · **Branch:** `redesign/ios6-reimagined`  
**Target:** iOS 6.0–12.5.7, armv7 & arm64

---

## Concept

Not a retro skin. A synthesis of authentic iOS 6 skeuomorphism (satin headers, linen canvas, recessed inputs, gloss buttons) with clean typographic hierarchy and accessible contrast (WCAG 2.1 AA). All rendering is procedural CoreGraphics — no offscreen GPU blurs, `@1x`/`@2x` cached — targeting 60 FPS on A5/A6.

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
| Appearance | `TGSettingsViewController+Pages` | Theme switcher, auto-night, font size, wallpaper |
| Profile | `TGProfileViewController` | Avatar, shared media tabs, block/leave |
| Music player (modal) | `TGPlayerView` | iPod-style deck, vinyl art, scrubber, queue |
| Mini-player (docked) | `TGPlayerView` | Persistent bar above tab bar |
| VoIP call | `TGCallViewController` | E2EE audio/video, embossed action buttons |
| Media viewer | `TGMediaViewer` | Fullscreen photo/video, pinch-to-zoom |
| Auth flow | `TGLoginViewController` | Phone → code → 2FA → QR |
| Sheets & alerts | `TGAlertSheet`, `TGSheet` | Frosted slate card, embossed title |
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

| Token | Light | Dark |
|---|---|---|
| `TGColorBackground` | `#EFEFF4` | `#1C1C1E` |
| `TGColorSurface` | `#FFFFFF` | `#2C2C2E` |
| `TGColorPrimary` | `#0A84FF` | `#0A84FF` |
| `TGColorDestructive` | `#FF3B30` | `#FF453A` |
| `TGColorTextPrimary` | `#000000` | `#FFFFFF` |
| `TGColorTextSecondary` | `#6C6C70` | `#8E8E93` |
| `TGColorSeparator` | `#C6C6C8` | `#38383A` |
| `TGColorOutgoingBubble` | `#DCF8C6` | `#1E3A2F` |
| `TGColorIncomingBubble` | `#FFFFFF` | `#2C2C2E` |

### Metrics

| Token | Value |
|---|---|
| `TGMetricListAvatar` | 46 pt |
| `TGMetricListRowHeight` | 64 pt |
| `TGMetricBubbleCornerRadius` | 16 pt |
| `TGMetricNavBarHeight` | 44 pt |
| `TGMetricTabBarHeight` | 49 pt |
| `TGMetricInputBarHeight` | 52 pt |
| `TGMetricInputBarCornerRadius` | 20 pt |

---

## TGUI component framework (`src/UI/`)

| Component | Class | Variants / notes |
|---|---|---|
| Button | `TGButton` | Primary / Secondary / Destructive / Success / Ghost × Small / Medium / Large. Physical press depression, busy state. |
| Switch | `TGSwitch` | Recessed track, embossed ON/OFF glyphs, knurled thumb with pan-to-drag |
| Slider | `TGSlider` | Recessed groove, glossy blue fill, min/max icons |
| Input | `TGTextField` | Recessed well, clear button, leading icon, error outline |
| Segmented | `TGSegmentedControl` | Satin container, sliding pill indicator |
| Card | `TGCardView` | Specular highlight, ambient shadow, header |
| Badge | `TGBadge` | Dome specular, 1 px rim — Notification / Accent / Muted / Success |
| Avatar | `TGAvatarView` | Auto-initials, async cache, specular rim, online indicator |
| Search bar | `TGSearchBar` | Linen, recessed well, animated Cancel |
| Reaction bar | `TGReactionPicker` | Spring pop, selection glow |
| Popup menu | `TGPopupMenu` | Directional arrow, emoji dock, etched rows |
| Design lab | `TGGalleryViewController` | Settings → Appearance → UI Component Gallery |

---

## Music player

Full-screen modal with vinyl album art (drop shadow + gloss overlay), scrubber, transport controls, repeat/shuffle, queue sheet. Global mini-player docked above the tab bar with thumbnail, track title, play/pause, close.

---

## Messages & feedback

| Component | Behaviour |
|---|---|
| `TGSnackbar` | Satin bar above chrome, 10 s countdown ring, Undo |
| `TGAlertSheet` | Frosted slate card, embossed OK, auto-dismiss keyboard |
| `TGAlertSheet` (destructive) | Red glossy confirm button, silver Cancel |
| `TGAlertSheet` (input) | Recessed text field, secure entry |
| `TGConnectionBanner` | Pinned under nav bar — Connecting / Updating + radio pulse |
| `TGEmptyView` | Centered illustration, embossed headline, action button |
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
