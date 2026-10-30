# iOS 6 Reimagined — Comprehensive Design System & Product Specification
**Project:** LegacyTG (iTgLegacy)  
**Target Architectures:** iOS 6.0 – 12.5.7 (armv7 32-bit & arm64 64-bit)  
**Authors:** Senior Product Designer, UI/UX Designer, Design Systems Architect, Frontend Engineer  
**Status:** In Progress / Active Worktree (`redesign/ios6-reimagined`)

---

## 1. Executive Summary & Vision

### 1.1 The Concept: "iOS 6 Reimagined"
"iOS 6 Reimagined" is not a simplistic retro skin nor an uncritical replica of legacy software. It is a rigorous synthesis of:
- **Authentic Physical Tactility (Skeuomorphism 2.0):** Rich materials (satin navigation headers, subtle linen/pinstripe canvas, brushed metal sliders, recessed input wells, debossed section captions, and glossy glass buttons with realistic top specular highlights and bottom drop shadows).
- **Modern UX Information Architecture:** Clean typographic hierarchy, accessible contrast ratios (WCAG 2.1 AA compliant), intuitive gesture workflows, contextual sheets, and adaptive layouts (320pt iPhone 4/4S up to 1024pt iPad).
- **High-Performance Engineering on Legacy Hardware:** Zero-overhead procedural CoreGraphics rasterization with `@1x`/`@2x` caching, avoiding expensive offscreen GPU blurs while delivering buttery 60 FPS on 32-bit A5/A6 chips and 64-bit A7+ devices.
- **Strict Ban on Generic AI Tropes:** No neon glow, no purple-cyan gradient smears, no card-in-card clutter, no emojis as UI icons, and no fake demo data.

---

## 2. Information Architecture & Route Inventory

| Route / Screen | Controller | Purpose & Key Scenarios | Key Components & State |
|---|---|---|---|
| **Chats List (Main Tab 0)** | `TGChatListViewController` | Hub for all conversations (direct, group, channel, secret). Fast search, folder filtering, swipe actions (Mute, Archive, Delete). | Skeuomorphic search bar, tactile badge counters, online status pips, swipe action drawers, compose button. |
| **Chat Conversation** | `TGChatViewController` | Message history, input bar, voice recording, reactions, reply chains, audio playback dock. | Skeuomorphic message bubbles, custom iOS 6 input bar, tactile voice lock capsule, in-chat audio bar. |
| **Contacts (Main Tab 1)** | `TGContactsViewController` | Address book sorted alphabetically with section index bar, user status, invite/add contact. | Sectioned table view, A-Z index well, search bar, tactile "Add Contact" navigation item. |
| **New Contact Modal** | `TGNewContactViewController` | Add contact with phone number and name. | Recessed input fields, validation status, tactile Done button. |
| **Settings (Main Tab 2)** | `TGSettingsViewController` | Profile card, preferences, sub-pages (Appearance, Data & Storage, Notifications, Privacy, Folders, Devices). | Skeuomorphic grouped table view, profile avatar hero, icon tiles with physical sheen. |
| **Appearance Settings** | `TGSettingsViewController+Pages` | Theme switcher (Classic Skeuomorphic, Day, Night, Night Blue), Auto-Night scheduler, font size, wallpaper picker. | Real-time preview card, checkmark selection, tactile font slider. |
| **User / Group Profile** | `TGProfileViewController` | Details, shared media tabs (Photos, Videos, Files, Audio, Links), notifications toggle, block/leave actions. | Large avatar hero with gloss bezel, shared media grid, destructive action buttons. |
| **Audio / Music Player Modal** | `TGPlayerView` / Fullscreen | Dedicated iOS 6 iPod-style music deck for songs and podcasts. | Vinyl album art with drop shadow & gloss overlay, scrubber timeline, transport buttons, repeat/shuffle, queue. |
| **Global Mini-Player** | `TGPlayerView` / Docked Mini | Persistent playback bar docked above the tab bar across all main screens. | Album thumbnail, track title & artist, play/pause, close button, tap to expand modal. |
| **VoIP Call Screen** | `TGCallViewController` | End-to-end encrypted voice/video calls with peer avatar, duration clock, cryptographic verification emojis. | Dynamic gradient backdrop, circular embossed action buttons (Mute, Speaker, Video, End/Accept). |
| **Media Viewer** | `TGMediaViewer` | Fullscreen photo/video gallery with swipe-to-dismiss, pinch-to-zoom, and action drawer. | Deep black backdrop, tactile translucent chrome bars, scrub timeline for video. |
| **Authorization Flow** | `TGLoginViewController` | Phone input, SMS/TG code verification, 2FA cloud password, QR code scanner. | Embossed segmented steps, recessed code input fields, tactile action buttons. |
| **Action & Alert Sheets** | `TGAlertSheet`, `TGSheet` | System alerts, confirmation dialogs, contextual action sheets. | Frosted slate-navy card, embossed title, silver/red glossy action rows, tactile Cancel button. |
| **Toasts & Feedback** | `TGSnackbar` | Temporary non-blocking confirmation with countdown ring and Undo. | Floating embossed plate, animated circular countdown, blue Undo button. |

---

## 3. Design Tokens & Visual Architecture

### 3.1 Surface & Lighting Model
- **Light Source:** Consistent overhead illumination at $90^\circ$ (simulating overhead studio/daylight).
- **Top Specular Highlight:** 1pt hairline `rgba(255, 255, 255, 0.25 - 0.45)` along the top edge of raised surfaces.
- **Bottom Bevel / Shade:** 1pt hairline `rgba(0, 0, 0, 0.15 - 0.35)` along the bottom edge of raised surfaces.
- **Recessed Surfaces (Wells, Input fields):** Inverted light model: top inner shadow `rgba(0, 0, 0, 0.18)` and bottom inner highlight `rgba(255, 255, 255, 0.6)`.
- **Text Shadows:**
  - *On dark textured bars:* `0px -1px rgba(0, 0, 0, 0.5)` (embossed/etched feel).
  - *On light metallic surfaces:* `0px 1px rgba(255, 255, 255, 0.7)` (crisp letterpress effect).

### 3.2 Typography Scale (Design Tokens in `TGStyle.h/m`)
- **Hero (28pt):** Call screen peer title, storage total summary.
- **Title (22pt Bold):** Profile header names, modal headings.
- **Header (17pt Bold):** Navigation bar title, primary button labels.
- **Row (16pt Regular/Bold):** List item titles, settings rows.
- **Body (15pt Regular/Bold):** Chat message body, descriptions, sheet items.
- **Subhead (14pt Regular/Bold):** Second line of list items, dates, tabs.
- **Caption (13pt Regular/Bold):** Quotes, settings secondary values, badges.
- **Meta (12pt Regular/Bold):** Bubble timestamps, sender names, section footers.
- **Micro (11pt Regular/Bold):** Compact timestamps, player elapsed clocks.

### 3.3 Color Palette (Primary & Functional)
- **Classic Header Blue (Skeuomorphic):** `rgb(0x51, 0x7D, 0xA2)` to `rgb(0x3B, 0x64, 0x88)` satin gradient.
- **Classic Tab Bar Matte Slate:** `rgb(0x1B, 0x1F, 0x24)` with top bevel line `rgb(0x33, 0x38, 0x40)`.
- **Grouped Background:** Subtle iOS 6 textured pinstripe / linen canvas.
- **Chat Canvas:** Crisp linen/paper grain `rgb(0xDE, 0xE2, 0xE6)` in Light, neutral charcoal in Dark.
- **Incoming Bubble:** Crisp porcelain white (`#FFFFFF`) with tactile outer bevel and specular highlight.
- **Outgoing Bubble:** Authentic Telegram celestial blue `rgb(0xDF, 0xEE, 0xFA)` with glossy skeuomorphic gradient (`#E6F2FD` to `#B4DAF5`) and tactile blue stroke `rgb(0x99, 0xC4, 0xE8)`. In Dark, deep night blue (`#286E9B` to `#14466A`).
- **Accent Blue:** `rgb(0x1A, 0x77, 0xD4)` (links, unread badge, active controls).
- **Destructive Red:** `rgb(0xD3, 0x2F, 0x2F)` with deep crimson bevel.
- **Success / Online Green:** `rgb(0x4C, 0xAF, 0x50)`.

---

## 4. Audio & Media Player Architecture

### 4.1 In-Chat Compact Player Bar
- Positioned directly below the navigation bar in `TGChatViewController`.
- Physical satin gradient background with bottom separator and inner bevel.
- Artwork square with rounded corners and gloss sheen.
- Transport buttons (Previous, Play/Pause, Next) with tactile pressed states.
- Scrubber track with metallic circular thumb (`TGMetricPlayerThumbSide = 12pt`).
- Playback speed button (1x / 1.5x / 2x) in a recessed pill.

### 4.2 Persistent Docked Mini-Player (`TGPlayerView` - Mini Mode)
- Docked directly above `UITabBar` in `RootViewController`.
- When audio is active, table view content insets are adjusted dynamically to prevent obscuring content.
- Shows: Album Art / Disc, Track Title, Artist/Performer, Play/Pause toggle, and Close button.
- Smooth slide-up presentation when playback begins; tap anywhere on the bar opens the Fullscreen Modal Player.

### 4.3 Fullscreen iPod / Music Modal Player (`TGPlayerView` - Fullscreen Mode)
- Dedicated sheet with realistic iOS 6 brushed-metal / satin chassis:
  - **Header:** Tactile chevron dismiss button, "Now Playing" embossed title, queue toggle button.
  - **Vinyl / Album Art Deck:** Large square artwork with subtle drop shadow, realistic gloss overlay, and high-fidelity placeholder if no artwork is embedded.
  - **Timeline Scrubber:** Recessed track well, elapsed & remaining time labels with tabular font numbers, metallic draggable thumb.
  - **Main Transport Controls:** Tactile circular Play/Pause button (64pt) with radial shine and pressed depth, flanked by tactile Previous and Next buttons (44pt).
  - **Secondary Controls:** Repeat button (Off / All / One) with physical active highlight, Shuffle toggle, and Volume slider with min/max speaker glyphs.
  - **Interactive Queue Sheet:** Slide-up tracklist allowing instant jumping between chat audio tracks.

---

## 5. Comprehensive Messages & Feedback System

| Category | Component | Visual Presentation & Behavior |
|---|---|---|
| **Informational Toast** | `TGSnackbar` | Floating satin bar above bottom chrome, 10s countdown ring, blue Undo action. |
| **System Alerts** | `TGAlertSheet` | Slate-blue frosted card, embossed title, silver tactile OK button, automatic keyboard dismissal. |
| **Destructive Confirmation** | `TGAlertSheet` (Confirm) | Highlighted red glossy button for irreversible action, silver Cancel card. |
| **Input Dialogs** | `TGAlertSheet` (Input) | Recessed text field inside alert card, secure entry support for passwords/PINs. |
| **Connecting / Network Banner** | `TGConnectionBanner` | Pinned under navigation bar: "Connecting...", "Updating...", with pulsating radio indicator. |
| **Empty States** | `TGEmptyView` | Centered vector illustration (chats, contacts, search, calls), embossed headline, tactile action button. |
| **Inline Form Errors** | Form Cells | Subtle red tint on input border, red caption with warning glyph. |

---

## 6. Implementation Progress Tracker

- [x] Worktree initialization (`redesign/ios6-reimagined`)
- [x] Codebase & UX audit (Routes, tokens, controllers, assets)
- [x] Design specification (`DESIGN_SPEC.md`)
- [x] Skeuomorphic procedural drawing engine (`TGTheme+Drawing.m`, `TGStyle.h/m`)
- [x] Tactile vector iconography extensions (`TGIcons.h/m`)
- [x] Dedicated Music Player System (`TGMusicPlayer`, `TGPlayerView` Mini & Modal)
- [x] RootViewController global mini-player integration
- [x] In-chat player bar refinement (`TGChatViewController+Audio.m`)
- [x] Empty states & connection status banners
- [x] Unified `TGUI` Component Framework (`src/UI/`): `TGButton`, `TGSwitch`, `TGSlider`, `TGTextField`, `TGSegmentedControl`, `TGCardView`, `TGBadge`
- [x] Interactive Design Lab & Component Showcase (`TGGalleryViewController` in Settings -> Appearance)
- [x] Token lint validation (`scripts/lint_tokens.sh`)
- [x] Full test suite execution (`make -f tests/Makefile test`)

---

## 7. Unified `TGUI` Component Framework (`src/UI/`)

Inspired by modern declarative UI architectures (such as `b1air/src/shell/qml/Ui/`), the application features a unified, modular UI component framework exported via the umbrella header `TGUI.h`:

| Component | Class | Capabilities & Tactile Presentation |
|---|---|---|
| **Buttons** | `TGButton` | 5 variants (`Primary`, `Secondary`, `Destructive`, `Success`, `Ghost`) across 3 sizes (`Small` 28pt, `Medium` 36pt, `Large` 44pt). Physical 1px down-press depression, etched shadows, and built-in activity indicator (`busy`). |
| **Switches** | `TGSwitch` | iOS 6 skeuomorphic toggle with deeply recessed track, white embossed "ON" / "OFF" glyphs, metallic knurled circular thumb with grip ridges, pan-to-drag and tap-to-flip physics. |
| **Sliders** | `TGSlider` | Tactile recessed groove with glossy blue progress fill and silver track well, circular knurled thumb, accessory min/max icon integration. |
| **Input Wells** | `TGTextField` | Procedural recessed well with top inner shadow, padding geometry, clear button, leading search/lock icons, and error outline transition. |
| **Segmented Controls** | `TGSegmentedControl` | Satin silver container, engraved hairline dividers, and sliding tactile action pill indicator with smooth ease-in-out animations. |
| **Containers** | `TGCardView` | Grouped canvas card with 1px top specular highlight, subtle ambient drop shadow, header bar with icon/title/subtitle, and interactive touch handling. |
| **Pill Badges** | `TGBadge` | iOS 6 notification badge with specular dome highlight, 1px white rim, etched tabular typography (`Notification`, `Accent`, `Muted`, `Success`). |
| **Avatars** | `TGAvatarView` | Tactile skeuomorphic avatar with automatic initials, async image caching, 1px specular rim, and online presence badge indicator. |
| **Search Headers** | `TGSearchBar` | Tactile satin linen search bar with recessed well, search glyph, and animated sliding Cancel button. |
| **Reaction Bar** | `TGReactionPicker` | Tactile frosted emoji reaction bar with spring pop animation, selection glow indicator, and one-tap reaction handling (`👍`, `❤️`, `🔥`, `🎉`, `😂`, `😮`, `😢`, `👏`). |
| **Popup Callouts** | `TGPopupMenu` | Classic iOS 6 callout popup card with directional pointer arrow, 1px specular shine, integrated emoji reaction dock, and etched action rows. |
| **Design Lab** | `TGGalleryViewController` | Live interactive showcase screen (accessible in Settings -> Appearance -> UI Component Gallery) allowing real-time interaction with every component, reaction bar, and variant. |

