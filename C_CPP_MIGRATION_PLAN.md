# C/C++ Architecture Migration Plan: LegacyTG

## 1. Executive Summary & Hardware Target Constraints

### 1.1 Target Devices
This migration plan is strictly tailored for legacy Apple silicon and iOS versions:
- **Primary Tier**: iPhone 4, iPhone 4S, iPod Touch 4th Gen, iPad 2 / 3.
- **Operating Systems**: iOS 6.0 – iOS 7.1.2 (32-bit `armv7`), up to iOS 12.5.7 (`arm64`).
- **Critical Resource Constraints**:
  - **iPod Touch 4th Gen**: Apple A4 (Cortex-A8 @ 800 MHz, single-core, in-order execution), **256 MB total RAM** (~35–45 MB usable memory before iOS jetsam OOM termination).
  - **iPhone 4**: Apple A4 @ 800 MHz, 512 MB total RAM.
  - **iPhone 4S**: Apple A5 (dual-core Cortex-A9 @ 800 MHz), 512 MB RAM.
  - **Storage & Bus**: Slow LPDDR/LPDDR2 bandwidth and slow NAND flash write cycles.

### 1.2 Core Architectural Principle
- **UIKit remains strictly in Objective-C**: ViewControllers, TableViews, navigation controllers, and gesture handling remain in Cocoa Touch. Wrapping UIKit in C++ creates unnecessary boilerplate with zero performance gain.
- **Heavy lifting moves to C and Modern C++ (C++14/17)**: High-frequency data manipulation, serialization/deserialization, background sync batching, in-memory caches, audio stream decoding, and vector math move to C/C++.
- **Bridge Layer**: Use Objective-C++ (`.mm`) files as thin, zero-cost adapter layers between UIKit and C++ subsystems.

---

## 2. Migration Guidelines & Transition Rules

1. **Clean Public Objective-C Headers**:
   - Public `.h` headers consumed by ViewControllers must remain pure Objective-C without exposing C++ types to prevent compiler contamination across the codebase.
   - Internal headers (`*Internal.h`) may use C++ types guarded by `#ifdef __cplusplus`.
2. **Zero Dynamic Allocation in Hot Loops**:
   - Never allocate `NSNumber`, `NSString`, or `NSDictionary` inside loops processing TDLib updates, cell layouts, or animation frames.
   - Use stack allocations, flat contiguous buffers (`std::vector`), or static lookup tables.
3. **Decouple Main Thread from Ingestion**:
   - The TDLib receive loop must never directly invoke `dispatch_async(dispatch_get_main_queue(), ...)` for individual raw events.
   - Events are buffered, digested, and stored in C++ background memory, then delivered to UIKit in coalesced batches.
4. **Zero-Copy Streaming Audio**:
   - No audio stream shall ever decompress an entire file into RAM before playing. All audio must be decoded in streaming chunks (20–40 ms).
5. **Memory Safety & OOM Hard Limits**:
   - Absolute memory ceiling for internal caches on 32-bit devices is **16 MB**.
   - Strict LRU policies with deterministic eviction for all image, layout, and entity caches.

---

## 3. Comprehensive Phased Migration Roadmap

```
┌─────────────────────────────────────────────────────────────────────────────┐
│ PHASE 1: Sync Buffer, Batching & Thread Decoupling                          │
│ Goal: Eliminate main-thread saturation on launch and unfreeze Profile/Chats  │
└─────────────────────────────────────────────────────────────────────────────┘
                                       │
                                       ▼
┌─────────────────────────────────────────────────────────────────────────────┐
│ PHASE 2: High-Performance JSON Ingestion & C++ In-Memory Store              │
│ Goal: Cut RAM footprint by 70%, eliminate heap fragmentation & OOM on 256MB │
└─────────────────────────────────────────────────────────────────────────────┘
                                       │
                                       ▼
┌─────────────────────────────────────────────────────────────────────────────┐
│ PHASE 3: Low-Footprint Streaming Audio Engine (Voice & Music)                │
│ Goal: Replace full-file WAV decompression with 64KB AudioQueue streaming    │
└─────────────────────────────────────────────────────────────────────────────┘
                                       │
                                       ▼
┌─────────────────────────────────────────────────────────────────────────────┐
│ PHASE 4: Text Engine, Timestamp Formatting & Cell Layout Caching            │
│ Goal: Guarantee 60 FPS scrolling on iPhone 4/4S by eliminating formatters   │
└─────────────────────────────────────────────────────────────────────────────┘
                                       │
                                       ▼
┌─────────────────────────────────────────────────────────────────────────────┐
│ PHASE 5: Custom Emoji Subsystem & Optimized Vector Graphics (TGS / Lottie)  │
│ Goal: Hardware-feasible custom emojis and smooth vector sticker rendering   │
└─────────────────────────────────────────────────────────────────────────────┘
```

---

## Phase 1: Sync Buffer, Batching & Thread Decoupling

### 1.1 Problem Statement
- In `src/Core/TGClient.m`, `receiveLoop` forwards every single incoming TDLib update to the main queue via `dispatch_async(dispatch_get_main_queue(), ^{ [self handleUpdate:obj]; })`.
- On launch, TDLib sends hundreds of simultaneous updates (`updateNewChat`, `updateChatPosition`, `updateChatTitle`, `updateChatLastMessage`, `updateUser`).
- In `src/Core/TGClient+Chats.m`, `applyChatUpdate:` calls `[self rebuildChats]` on every update, performing full array iterations and `sortedArrayUsingComparator:` $O(N \log N)$ sorts on the main thread, accompanied by `reloadData` calls.
- **Result**: Main runloop hangs for 3–8 seconds. Opening Profile during this period deadlocks or freezes UI.

### 1.2 Target Architecture
- **`TGUpdateBatcher` (C++)**:
  - Ingests incoming events on the background TDLib thread.
  - Updates the in-memory C++ state representation immediately.
  - Uses an adaptive coalescing timer (100–150 ms) to emit a single consolidated UI update notification containing dirty IDs.
- **Fast Chat Sorter (C++)**:
  - Replace `sortedArrayUsingComparator:` with `std::sort` on flat array of `int64_t` chat IDs and 64-bit integer orders.

### 1.3 Step-by-Step Implementation
1. **Rename** `src/Core/TGClient.m` and `src/Core/TGClient+Chats.m` to `.mm` (Objective-C++).
2. **Implement `TGUpdateBatcher.hpp/.cpp`**:
   - Manage pending dirty flags: `dirty_chat_list`, `dirty_user_ids`, `dirty_message_chat_ids`.
   - Dispatch coalesced updates to main thread using `dispatch_after` or high-resolution mach timers.
3. **Refactor `rebuildChats`**:
   - Maintain contiguous vector of `struct ChatOrderEntry { int64_t chat_id; int64_t order; bool is_pinned; };`.
   - Sort using C++ lambda comparator (50x faster than `NSComparator` block invocation).
4. **Profile View Instant Access**:
   - `userInfo:` and `chatProfile:` read synchronously from in-memory C++ structures instead of dispatching roundtrip TDLib calls when already cached.

### 1.4 Test Coverage Plan
- **Unit Tests (`tests/TGClientBatcherTests.mm`)**:
  - Simulate flood of 1,000 `updateChatPosition` events in 50 ms.
  - Assert that main queue receives no more than 2 batch callbacks.
  - Verify exact sorting order matches baseline `NSComparator` sort.
- **Integration Benchmark**:
  - Measure time from authorization to first interactive table scroll. Target: $\le 1.2$ s on iPhone 4S.

---

## Phase 2: High-Performance JSON Ingestion & C++ In-Memory Store

### 2.1 Problem Statement
- `NSJSONSerialization` parses every JSON string into deep Objective-C object trees (`NSDictionary`, `NSArray`, `NSString`, `NSNumber`).
- For large chat histories and sync payloads, millions of short-lived objects pollute the autorelease pool, causing heavy memory fragmentation and OOM crashes on the 256 MB iPod Touch 4G.

### 2.2 Target Architecture
- **JSON Engine**: Vendored [yyjson](https://github.com/ibireme/yyjson) (high-performance C library, zero copy, minimal heap allocations).
- **Domain Store**:
  - `TGStateStore` in C++:
    ```cpp
    struct ChatRecord {
        int64_t id;
        std::string title;
        int64_t order;
        int64_t archive_order;
        int32_t unread_count;
        int32_t last_message_date;
        int32_t photo_file_id;
        bool is_pinned;
        bool is_muted;
        bool is_saved;
    };
    std::unordered_map<int64_t, ChatRecord> chats;
    std::unordered_map<int64_t, UserRecord> users;
    ```

### 2.3 Step-by-Step Implementation
1. Add `third_party/yyjson/yyjson.h` and `yyjson.c` to build pipeline.
2. Build `TGJsonReader` helper to pull raw primitive fields (`int64`, `bool`, `const char*`) directly from `yyjson_val` without boxing.
3. Replace `TGFlattenMessage` logic with C++ parser filling a stack-allocated or pooled `TGFlatMessage` struct.
4. Replace `chatsById` and `usersById` in `TGClientInternal.h` with wrappers around `TGStateStore`.

### 2.4 Test Coverage Plan
- **Fuzzing & Parity Tests (`tests/TGJsonParityTests.mm`)**:
  - Feed 500 sample TDLib JSON messages into both `NSJSONSerialization` and `yyjson` extractor.
  - Assert 100% field equivalence across message types, sender types, and media descriptors.
- **Memory Allocation Benchmark**:
  - Parse 10,000 synthetic messages; assert peak RSS memory reduction $\ge 60\%$.

---

## Phase 3: Low-Footprint Streaming Audio Engine (Voice & Music)

### 3.1 Problem Statement
- In `src/Audio/TGVoiceDecoder.m`, `wavFromOpusFile:` reads the entire Ogg Opus file, decodes all frames into an in-memory `NSMutableData` buffer of uncompressed 16-bit 48 kHz stereo PCM, and writes it to a temporary `.wav` file on flash storage.
- **Math**: 48,000 samples/sec $\times$ 2 channels $\times$ 2 bytes = 192,000 bytes/sec (~11.5 MB per minute).
- A 3-minute voice note consumes **~35 MB RAM** + 35 MB disk write. On iPod Touch 4G with ~35 MB free memory, this triggers an immediate **Jetsam OOM kill**.

### 3.2 Target Architecture
- **`TGStreamingAudioPlayer` (C++ / AudioToolbox C API)**:
  - Direct connection: `OggOpusFile` $\rightarrow$ CoreAudio `AudioQueue` (or `AudioUnit`).
  - Ring buffer of 3 buffers $\times$ 40 ms audio (~3.8 KB each).
  - Total memory footprint: **$\le 64$ KB** regardless of whether the voice note is 10 seconds or 2 hours long.
  - Start latency: $< 10$ ms (playback begins on first decoded frame, no disk write).

### 3.3 Step-by-Step Implementation
1. Create `src/Audio/TGStreamAudioPlayer.h` and `.mm`.
2. Implement C callback for `AudioQueueOutputCallback`:
   - Calls `op_read_stereo` for the next 40 ms buffer.
   - Enqueues buffer back into `AudioQueue`.
3. Support seeking by wrapping `op_pcm_seek` for scrubbing slider.
4. Deprecate and remove `TGVoiceDecoder.m` disk-based WAV creation.

### 3.4 Test Coverage Plan
- **Streaming Verification Tests (`tests/TGAudioStreamingTests.mm`)**:
  - Feed truncated, corrupted, and 30-minute Opus files.
  - Verify steady-state RAM consumption stays below 256 KB.
  - Verify precise seek timing and EOF detection.
- **Interruption Tests**:
  - Test audio route changes (headphones plugged/unplugged, lock screen).

---

## Phase 4: Text Engine, Timestamp Formatting & Cell Layout Caching

### 4.1 Problem Statement
- In `src/Controllers/TGChatViewController+Layout.m`, `stampFor:` and `timeWidthFor:` invoke `[NSDateFormatter stringFromDate:]` and `[NSString stringWithFormat:]` for every message during scroll.
- In `src/Views/TGMessageLayout.m`, emoji scanning uses `enumerateSubstringsInRange:`, cache keys are generated with `[NSString stringWithFormat:@"%.0f|%@", ...]`, and the 300-item cache is dumped completely with `removeAllObjects`, producing noticeable frame drops.

### 4.2 Target Architecture
- **C Time Formatter**:
  - `localtime_r` + `snprintf` format time strings directly into `char[16]` buffer without creating `NSDate` or `NSDateFormatter`.
- **C Emoji Scanner**:
  - Direct UTF-8 / UTF-16 pointer iteration to detect surrogate pairs and Unicode pictograph codepoint ranges.
- **C++ LRU Layout Cache**:
  - Key: 64-bit integer `uint64_t key = (hash64(text) ^ ((uint64_t)fontSize << 32));`.
  - Storage: `std::unordered_map` with doubly-linked list for genuine $O(1)$ LRU eviction (max 500 items, evicts oldest item 1-by-1 instead of flushing entire cache).

### 4.3 Step-by-Step Implementation
1. Convert `TGMessageLayout.m` to `TGMessageLayout.mm`.
2. Replace `[NSDateFormatter stringFromDate:]` with `TGFormatTimestampC(int64_t timestamp, bool edited, char *out, size_t maxLen)`.
3. Implement `TGEmojiScannerC` operating over raw UTF-16 character arrays.
4. Replace `NSMutableDictionary *cache` with `TGLruCache<uint64_t, TGLayoutMetrics>`.

### 4.4 Test Coverage Plan
- **Layout Parity Tests (`tests/TGMessageLayoutTests.m`)**:
  - Validate that bubble width, height, and timestamp positions match existing output to within $\pm 0.5$ pt.
- **Scroll Benchmark**:
  - Measure frame duration distribution during automated table scroll in chat with 500 messages on iPhone 4.
  - Requirement: 0 dropped frames below 45 FPS on iPhone 4; solid 60 FPS on iPhone 4S.

---

## Phase 5: Custom Emoji Subsystem & Optimized Vector Graphics (TGS / Lottie)

### 5.1 Feasibility & Hardware Constraints
- **Challenge**: An iPhone 4 single-core Cortex-A8 cannot evaluate 30 active vector Lottie paths concurrently at 60 FPS.
- **Solution**:
  - **Inline Text Emojis**: Render strictly as **static 40x40 Retina bitmaps** (frame 0) cached in a centralized C++ Glyph Atlas. Memory cost: **6.4 KB per unique custom emoji**.
  - **CoreText Integration**: Embed using `CTRunDelegate` (CoreText C API), drawing directly via `CGContextDrawImage`. Zero `UIView` overhead.
  - **Animated Emojis (Reactions / Focus Tap)**: Pre-bake vector frames on C++ into a lightweight 12-frame sprite sheet. Run all animated visible cells off a **single centralized display link timer** (Global Clock).

### 5.2 Optimizing `TGLottieView.m` (C++ Vector Math)
- In `src/Views/TGLottieView.m`:
  - Eliminate `prop[@"k"]` dictionary lookups during frame interpolation.
  - Parse JSON once into flat C++ structs:
    ```cpp
    struct Keyframe { float frame; float value[4]; };
    struct BezierCurve { std::vector<CGPoint> in_tangents, out_tangents, points; };
    ```
  - Compute Bezier cubic interpolation and affine transforms using standard float math (with optional ARM NEON SIMD intrinsics for `armv7`).

### 5.3 Step-by-Step Implementation
1. Implement `TGCustomEmojiStore.hpp/.mm`:
   - Downloads `.tgs` / `.webm` through TDLib file API.
   - Decompresses and extracts first frame into a 32-bit RGBA bitmap.
   - Caches bitmaps in an LRU bitmap atlas.
2. In `TGMessageLayout.mm`, intercept `textEntityTypeCustomEmoji` entities:
   - Insert `CTRunDelegate` with fixed size $18 \times 18$ pt.
   - Attach custom emoji ID as attribute.
3. Refactor `TGLottieView.m` to `.mm`:
   - Separate AST (Abstract Syntax Tree) parsing from per-frame evaluation.
   - Evaluate curves entirely in C++ before handing `CGPathRef` to `CoreGraphics`.

### 5.4 Test Coverage Plan
- **Emoji Rendering Tests (`tests/TGCustomEmojiTests.mm`)**:
  - Verify layout sizing and baseline alignment within message bubbles.
  - Test memory stress with 150 custom emojis on a single screen (assert RAM $\le 2$ MB).
- **Lottie Benchmark**:
  - Measure CPU usage during sticker playback: target $\le 25\%$ CPU load on Apple A4.

---

## 4. Test Infrastructure & CI Integration

### 4.1 Test Harness Location
All tests will be integrated directly into the standalone test runner:
- Test runner: `tests/main.m`, `tests/main_client.m`, `tests/TGTestRunner.h`.
- Build recipe: `tests/Makefile` (`make -C tests test`).

### 4.2 Quality Gate Checklist for Each Phase
Before merging any phase into `main`:
1. **Compilation**: Clean build on both `armv7` (iOS 6 SDK) and `arm64` (iOS 7+ SDK).
2. **Unit Test Pass Rate**: 100% pass on `tests/Makefile`.
3. **Instruments Leaks & Allocations**:
   - Zero unmanaged C++ or CoreFoundation memory leaks.
   - Steady-state RAM on iPod Touch 4G must remain under **40 MB**.
4. **Binary Footprint Impact**:
   - Total `.ipa` size increase must be $\le 400$ KB across both architectures.
