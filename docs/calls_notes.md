# Calls: phone↔phone silence, phone↔desktop works

Observed: a call between two phones (this legacy client, libtgvoip-based)
carries no sound, while a call from this phone to the desktop client talks
fine. Scratchpad copy of `tgcalls` lives at
`/private/var/folders/25/kh3vn47d1870yk0n0q5j5ljm0000gn/T/opencode/refs/tgcalls-development`
(fetch of `https://github.com/TelegramMessenger/tgcalls/archive/refs/heads/development.tar.gz`
- the old `Telegram/tgcalls` path 404s, the repo was renamed).

## What each side runs

| client | stack | what it negotiates |
|---|---|---|
| this app | `third_party/libtgvoip`, `PROTOCOL_VERSION 9` (`MIN_PROTOCOL_VERSION 3`), `max_layer 92` in TGCall.mm `-protocol` | legacy tgvoip protocol: Endpoint {id, ip, peerTag, UDP/TCP relay} over its own hand-rolled crypto, handshake in VoIPController.cpp |
| modern desktop / iOS | `tgcalls` (WebRTC bundled), versions negotiated by `tgcalls::Instance` | `v2` and `v2_4_0_0` - those are *compatibility shims*, not just new stacks |

## Why desktop works

`tgcalls` deliberately keeps the legacy protocol implementations:

- `tgcalls/v2_4_0_0/` - the tgvoip 2.4-era controller, still built.
- `tgcalls/v2/InstanceV2CompatImpl.cpp` - a WebRTC PeerConnection based
  instance, but authored so it also *interop* paths can fall through.

Our `-protocol` announces `library_versions ["3.0.0", "2.4.4"]`. The modern
desktop matches one of those names and either speaks legacy tgvoip directly
(the `v2_4_0_0` controller) or bridges via the compat layer, so the whole
magazine of endpoints, peer tags and opus packets lines up. That is why
phone→desktop has audio.

## Why phone↔phone may not

Two hypotheses, in order of what the code suggests:

1. **Peer's modern client picks a newer protocol.** Modern clients request
   `InstanceV2Impl` (full WebRTC signaling) first and only drop to the
   compat/tgvoip path when the *other side's* announced versions ask for it.
   Both phones announcing a version the other refuses to serve quietly
   results in established signaling but no media. Worth logging what
   `phoneCallProtocol` swaps in on the answering phone vs. what we accept:
   our `min_layer 65 / max_layer 92` may refuse a layer the modern phone
   actually picked.
2. **Endpoint flavour mismatch.** `tgcalls`' `Endpoint` differs from
   tgvoip's only in shape (int64 endpointId, ipv4+ipv6 pair, peerTag,
   Inet/Lan/UdpRelay/TcpRelay). If the modern peer sends IPv6-only hosts or
   both, and our `VoIPController::SetRemoteEndpoints` path treats the
   `peerTag` differently for the second endpoint, packets may flow but fail
   the crypto check, which reads as silence, not an error.

## Build note (2026-10-28): the archive that broke e2e silently

While wiring this up, `make ipa-arm64` failed on undefined
`tde2e_api::call_create(...)`: TDLib's fat `libtde2e.a` carries two different
sources under **one ar member name** (hand-written `td/e2e/e2e_api.cpp` and
generated `td/generate/auto/td/telegram/e2e_api.cpp`), so a plain extract
overwrites one with the other and the symbol index goes rotten. The repack
recipe (`scripts/repack_arm64_libs.sh`) now extracts occurrence-wise with
`llvm-ar xN` and renames later copies, and the arm64 IPA links clean again.
Keep this in mind for any future thin/fat archive work in the tree.

## What to do next (in our tree)

- Log at connect time, on both ends: negotiated `protocol_version`,
  `connectionMaxLayer`, chosen codec, and whether the first media packet
  decrypts (`VoIPController` logs that in `HandleIncomingPacket`).
- Compare the log phone↔desktop (works) against phone↔phone (silent); the
  divergence point is the answer.
- If the modern peer negotiates a layer above 92 or a protocol above 9,
  raise our `max_layer`/`library_versions` to match what tgvoip 2.4.4+c
  actually supports rather than what TGCall.mm conservatively announces.
