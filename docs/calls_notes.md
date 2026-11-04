# Calls: phone↔phone silent, phone↔desktop works

A call between two phones (this app, libtgvoip-based) carries no audio. A call from this phone to the desktop client works fine.

tgcalls source: `https://github.com/TelegramMessenger/tgcalls/archive/refs/heads/development.tar.gz` (the old `Telegram/tgcalls` path 404s — repo was renamed).

## What each side runs

| Client | Stack | Protocol |
|---|---|---|
| This app | `third_party/libtgvoip`, `PROTOCOL_VERSION 9`, `max_layer 92` | Legacy tgvoip: Endpoint {id, ip, peerTag, UDP/TCP relay}, own crypto, handshake in VoIPController.cpp |
| Modern desktop/iOS | `tgcalls` (WebRTC bundled) | `v2` and `v2_4_0_0` — compatibility shims, not just new stacks |

## Why desktop works

`tgcalls` keeps the legacy protocol:

- `tgcalls/v2_4_0_0/` — tgvoip 2.4-era controller, still built
- `tgcalls/v2/InstanceV2CompatImpl.cpp` — WebRTC-based with interop fallback paths

Our `-protocol` announces `library_versions ["3.0.0", "2.4.4"]`. Modern desktop matches one and either speaks legacy tgvoip directly or bridges via the compat layer. That's why phone→desktop has audio.

## Why phone↔phone may not

1. **Peer picks a newer protocol.** Modern clients request `InstanceV2Impl` first and only fall back to tgvoip when the *other side* asks for it. Both phones announcing a version the other won't serve → signaling established, no media. Worth logging: `phoneCallProtocol` on the answering phone vs. what we accept — our `min_layer 65 / max_layer 92` may refuse the layer the modern phone picked.

2. **Endpoint shape mismatch.** `tgcalls` Endpoint differs from tgvoip's only in shape (int64 id, ipv4+ipv6 pair, peerTag, Inet/Lan/UdpRelay/TcpRelay). If the modern peer sends IPv6-only and `VoIPController::SetRemoteEndpoints` treats peerTag differently for the second endpoint, packets flow but fail the crypto check — reads as silence, not an error.

## Build note (2026-10-28): archive that broke e2e silently

`make ipa-arm64` failed on undefined `tde2e_api::call_create(...)`: TDLib's fat `libtde2e.a` carries two different sources under **one ar member name** (hand-written `td/e2e/e2e_api.cpp` and generated `td/generate/auto/td/telegram/e2e_api.cpp`). Plain extract overwrites one with the other, symbol index goes rotten. `scripts/repack_arm64_libs.sh` now extracts occurrence-wise with `llvm-ar xN` and renames later copies. Keep this in mind for any future thin/fat archive work.

## Next steps

- Log at connect time on both ends: `protocol_version`, `connectionMaxLayer`, chosen codec, and whether the first media packet decrypts (`VoIPController` logs it in `HandleIncomingPacket`).
- Compare phone↔desktop (works) vs. phone↔phone (silent) — the divergence point is the answer.
- If the modern peer negotiates a layer > 92 or protocol > 9, raise `max_layer`/`library_versions` to match what tgvoip 2.4.4 actually supports.

## Bench against the real library (2026-11-04)

`scripts/call_bench.sh` runs our `TGCall` on the Mac against tgcalls itself (`tgcalls_cli --mode bridge`, from Telegram-iOS with `tests/call_bench/tgcalls_cli_bridge.patch`) through a real reflector, no account. `scripts/call_bench_device.sh` does the same from the device with the real audio engine.

Current tgcalls registers 2.7.7, 5.0.0 and 7.0.0 up; 3.0.0 and 2.4.4 are gone, and iOS (`selectVersionOnAccept`) cannot take a call with no version in common. 7.0.0 and up are a different protocol (DTLS, SCTP) and would need a port. 2.7.7 and 5.0.0 are `InstanceImpl`, whose wire format is what `TGCall` already speaks, so they went on the offer list.

Result, Mac and iPod: Established in both roles on both versions. Their 440 Hz tone reaches us at a 0.84-1.00 energy share. Our tone reaches them at 0.10-0.24 against 0.00-0.01 when we send nothing. Their `Render` output is noisy on any input (a real tgcalls pair reads 0.01-0.02 there), so it shows the tone arrives, not how clean it is. Not tried: a call between two accounts through TDLib, where the server picks the version.
