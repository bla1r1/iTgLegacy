# C/C++ Architecture Migration

## Target hardware

| Device | CPU | RAM |
|---|---|---|
| iPod Touch 4 | A4 Cortex-A8 @ 800 MHz, single-core, in-order | 256 MB (~35–45 MB usable before jetsam) |
| iPhone 4 | A4 @ 800 MHz | 512 MB |
| iPhone 4S | A5 dual-core Cortex-A9 @ 800 MHz | 512 MB |
| iPhone 5s+ | A7+ | 1 GB+ |

OS range: iOS 6.0–7.1.2 (armv7), up to iOS 12.5.7 (arm64). Slow LPDDR/LPDDR2 and slow NAND.

## Architecture split

- **UIKit stays in Objective-C.** ViewControllers, TableViews, navigation, gestures. Wrapping UIKit in C++ adds boilerplate with no performance gain.
- **Heavy lifting moves to C/C++14/17.** High-frequency data processing, serialization, background sync batching, in-memory caches, audio decoding, vector math.
- **`.mm` bridge files** are thin, zero-cost adapters between UIKit and C++ subsystems.

## Rules

1. **Clean public headers.** `.h` consumed by ViewControllers stays pure Objective-C. Internal headers (`*Internal.h`) may use C++ types under `#ifdef __cplusplus`.
2. **No dynamic allocation in hot loops.** No `NSNumber`/`NSString`/`NSDictionary` inside TDLib update loops, cell layout, or animation frames. Use stack allocation, `std::vector`, or static lookup tables.
3. **Decouple TDLib receive loop from main thread.** No `dispatch_async(main_queue)` per raw event. Buffer, digest, deliver in coalesced batches.
4. **Zero-copy streaming audio.** Never decompress an entire audio file to RAM before playback. Stream in 20–40 ms chunks via AudioQueue.
5. **OOM ceiling.** Internal cache max on 32-bit: **16 MB**. Strict LRU with deterministic eviction for image, layout, and entity caches.

## Migration phases

**Phase 1 — Sync buffer, batching, thread decoupling**  
Eliminate main-thread saturation on launch; unfreeze Profile and Chats.

**Phase 2 — C++ in-memory store, fast JSON ingestion**  
Cut RAM footprint by ~70%, eliminate heap fragmentation and OOM on 256 MB.

**Phase 3 — Streaming audio engine**  
Replace full-file WAV decompression with 64 KB AudioQueue streaming.

**Phase 4 — Text engine, timestamp formatting, cell layout cache**  
60 FPS scrolling on iPhone 4/4S by eliminating per-cell formatters.

**Phase 5 — Custom emoji, TGS/Lottie optimisation**  
Hardware-feasible custom emoji and smooth vector sticker rendering.

**Phase 6 — Remaining hot-path switchover**  
Remove the last `NSDictionary` boxing layer and per-reuse drawing cost.
