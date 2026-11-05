# tgcalls 9.0.0 wire protocol

Scope: everything `src/Calls/TGCall.mm` must do to talk to a real tgcalls 9.0.0
peer through a Telegram reflector, audio only. 9.0.0 maps to
`SignalingProtocolVersion::V2` (`v2/InstanceV2Impl.cpp:78-92`). Our existing
`TGCallCrypto.c` already speaks the V2 signalling envelope; the media path is
new (DTLS/SRTP).

Sources: `v2/` and WebRTC file:line, plus `sample:N` for the 9.0.0 pair log.

## 1. Signalling transport

V2 has **no gzip on send** (`signalingProtocolSupportsCompression` is false for
V2, `v2/InstanceV2Impl.cpp:96-103`). It **accepts gzip on receive**: if the
decrypted payload starts with the gzip magic it is inflated, limit 2 MB
(`v2/InstanceV2Impl.cpp:1682-1690`). Send plain JSON.

The envelope is tgcalls `EncryptedConnection`, identical to what
`TGCallCrypto.c` already implements. Per packet:

```
[16-byte msgKey][AES-256-CTR ciphertext]
plaintext = [seq:4 BE][message] ( [seq:4 BE][message] )*
```

`msgKey` is `SHA256(key + 88 + x, plaintext)[8..24]`, the AES key/IV come from
`CryptoHelper::PrepareAesKeyIv`, and `x` is `(outgoing?0:8) + (signaling?128:0)`
for writing, the opposite halves for reading
(`EncryptedConnection.cpp:430-460`, `:120-150`; our `TGCallCrypto.c:12-18`
matches). A call key is 256 bytes; V2 uses only the signalling half, key+128.
The old media half (key+0/+8) is dead for 9.0.0.

`seq` bits: bit 31 = single-message packet, bit 30 = requires ack, low 30 bits
= counter (`EncryptedConnection.cpp:15-22`). Our `+markSeq:requiresAck:`
already sets exactly one of the two bits.

One message is a raw message, id `kCustomId = 127`
(`EncryptedConnection.cpp:44`, `:82-88`):

```
7F | len:4 BE | JSON bytes
```

Acks and resent messages are packed into the same plaintext. Each additional
element is preceded by its own 4-byte seq. An ack is
`[acked_seq:4 BE][FF]`; an ack-only packet starts with `[seq:4][FE]`
(`EncryptedConnection.cpp:336-343`, `:873-880`; constants at `:41-43`).
`acked_seq` is the full seq including bit 30.

Retries (`EncryptedConnection.cpp:797-805`): signalling messages are resent
after at least 3 s and at most 5 s; acks are flushed immediately for a new
ack-required message, otherwise after 5 s. A receiver must dedupe by counter
(window 64, `:474-505`) and must re-ack a duplicate. Our current
`TGCallParsePacketSlices` returns only the first slice
(`src/Calls/TGCallMessages.m:35-56`) and takes the body of a 127 message as
"rest of packet" (`:46-47`); for V2 it must use the 4-byte length and loop over
all seq-delimited elements, or an ack appended to a data message will corrupt
the JSON.

Order (sample): the caller sends `NegotiateChannels` and `InitialSetup` first,
in either order (the offer is synchronous, `sendInitialSetup` hops to the media
thread, `v2/InstanceV2Impl.cpp:1311-1345`; sample:52 at 313 ms, sample:106 at
315 ms). The callee sends nothing at start (`beginSignaling` only sends when
outgoing, `:1341`). On the caller's `InitialSetup` the callee replies with its
own (`:1704-1726`; sample:317). On the caller's `NegotiateChannels` the callee
sends an answer and then its own offer (`:1728-1747` plus `getPendingOffer`,
sample:135 and sample:142). Then the caller answers the callee's offer
(sample:264). Candidates go out when the reflector port is ready (sample:426,
sample:428).

Ack every 9.0.0 message: all four types are sent with `requiresAck = true`
(`v2/InstanceV2Impl.cpp:1282-1288`).

## 2. JSON messages

All messages are one JSON object with `@type`. Unknown fields are ignored;
an unknown `@type` is logged and dropped (`v2/Signaling.cpp:766-800`). json11
writes `", "`/`": "` separators; any valid JSON is accepted, so
`NSJSONSerialization` compact output is fine.

### InitialSetup

Serialized keys in order `@type, fingerprints, pwd, renomination, ufrag`
(`v2/Signaling.cpp:368-390`). `ufrag` and `pwd` are mandatory strings, `pwd`
24 chars, `ufrag` 4 (`p2p/base/p2p_constants.cc:23-26`). `renomination` is
optional and defaults false (`v2/Signaling.cpp:402-406`); 9.0.0 always sends
true (`v2/NativeNetworkingImpl.cpp:507`). `fingerprints` must be an array; each
item needs `hash`, `setup`, `fingerprint` (`:424-443`).

```json
{"@type": "InitialSetup", "fingerprints": [{"fingerprint": "8D:F5:D2:CF:EA:FE:9C:C7:49:E9:AD:44:C5:71:45:46:E4:6B:B6:89:6C:65:12:B1:5A:98:F1:7B:5C:62:74:C3", "hash": "sha-256", "setup": "actpass"}], "pwd": "Ab3dEf6hIj9lMn2pQr5sTu7v", "renomination": true, "ufrag": "UX7o"}
```

Caller sends `setup: "actpass"`, callee `setup: "passive"`
(`v2/InstanceV2Impl.cpp:1586-1594`). Real ufrags in the sample: `UX7o`
(caller, sample:192) and `Au56` (callee, sample:381); real fingerprint prefix
in sample:106.

### NegotiateChannels

Keys `@type, contents, exchangeId` (`v2/Signaling.cpp:451-468`).
`exchangeId` is a **string** on the wire (`uint32ToString`, `:456`) but the
parser also takes a number (`:469-489`); it is a non-zero random uint32
(`rtc_base/unique_id_generator.cc:29-37`). `contents` may be absent or empty
(`:487-500`), but for audio it must not be: see §3.

`MediaContent` keys, alphabetically as json11 emits them:
`payloadTypes?, rtpExtensions, ssrc, ssrcGroups?, type`
(`v2/Signaling.cpp:227-272`). `type` is `"audio"` or `"video"`. `ssrc` is
mandatory and serialized as a decimal string, though a number parses
(`:274-310`). `payloadTypes` items: `id` (number), `name` (string),
`clockrate` (number), `channels` (number), `feedbackTypes` (array of
`{type, subtype}`), `parameters` (object of string→string)
(`:156-225`). `rtpExtensions` items: `{id: number, uri: string}`
(`:117-130`).

Real 9.0.0 offer, one audio content (the tail after `payloadTypes` is not
visible in the truncated sample; `parameters` and `rtpExtensions` come from
`v2/ContentNegotiation.cpp:57-66`, `:106-110`, sample:233 — UNCONFIRMED against
the sample text):

```json
{"@type": "NegotiateChannels", "contents": [{"payloadTypes": [{"channels": 2, "clockrate": 48000, "feedbackTypes": [{"subtype": "", "type": "transport-cc"}], "id": 111, "name": "opus", "parameters": {"minptime": "10", "useinbandfec": "1"}}], "rtpExtensions": [{"id": 2, "uri": "http://www.webrtc.org/experiments/rtp-hdrext/abs-send-time"}, {"id": 3, "uri": "http://www.ietf.org/id/draft-holmer-rmcat-transport-wide-cc-extensions-01"}], "ssrc": "120974494", "type": "audio"}], "exchangeId": "246813579"}
```

### Candidates

Keys `@type, candidates`; each item is `{"sdpString": "..."}`
(`v2/Signaling.cpp:537-586`). The old 5.0.0 top-level `ufrag`/`pwd` and the
binary candidate body are gone; the ufrag lives in the candidate string.

```json
{"@type": "Candidates", "candidates": [{"sdpString": "candidate:3376150301 1 udp 41877760 reflector-1-231911121.reflector 598 typ relay generation 0 ufrag UX7o network-id 1 network-cost 10"}]}
```

(`network-cost` value is truncated in the sample; the rest is sample:426/428.)

### MediaState

Keys `@type, lowBattery, muted, screencastState, videoRotation, videoState`
(`v2/Signaling.cpp:589-665`). `lowBattery` and `muted` are bools,
`screencastState`/`videoState` strings, `videoRotation` a number. Every field
is optional on parse (`:668-745`); `videoState`/`screencastState` are
`"inactive" | "suspended" | "active"`, `videoRotation` is `0|90|180|270`.

```json
{"@type": "MediaState", "lowBattery": false, "muted": false, "screencastState": "inactive", "videoRotation": 0, "videoState": "inactive"}
```

Audio-only omissions: no video or screencast content anywhere; no
`ssrcGroups`; `rtpExtensions` may be omitted entirely. `MediaState` may be
omitted (the library only sends it on the data channel, §7). `InitialSetup`
cannot omit `ufrag`, `pwd` or `fingerprints`.

## 3. Audio negotiation

Each side offers **its own** send-only audio and answers the other's offer;
there are two independent exchanges with different `exchangeId`s. Offers
contain only send-only contents (`v2/ContentNegotiation.cpp:352-360`); answers
contain only the peer's content, with the peer's ssrc copied into it
(`:549-571`). `setAnswer` accepts the peer's answer only if a content's `ssrc`
equals the ssrc this side offered (`:576-595`), and the outgoing audio channel
is built from that content (`v2/InstanceV2Impl.cpp:1355-1385`). Consequences:

- Our offer must carry a non-zero ssrc and an opus payload type, otherwise the
  peer creates no incoming channel for us and discards our RTP.
- Our answer must echo the peer's `ssrc` and an opus payload type, otherwise
  the peer creates no outgoing channel and stays silent.
- The answer's `exchangeId` must be the peer's offer `exchangeId`.

The audio codec list is filtered to opus only
(`v2/ContentNegotiation.cpp:57-66`): id 111, name `opus`, clockrate 48000,
channels 2, feedback `transport-cc`, fmtp-equivalent parameters
`minptime=10;useinbandfec=1` (`media/engine/webrtc_voice_engine_unittest.cc:3792-3793`,
`modules/audio_coding/codecs/opus/audio_encoder_opus.cc:213`). RTP extensions
offered for audio: abs-send-time id 2, transport-cc id 3
(`v2/ContentNegotiation.cpp:106-110`; URIs at `api/rtp_parameters.h:307-308`,
`:342-346`). The sample confirms the peer's sender used both (sample:233).

Real ssrcs from the sample: 120974494 (sample:227) and 318510 (sample:354).

Smallest offer the library accepts for audio:

```json
{"@type":"NegotiateChannels","exchangeId":"123456789","contents":[{"type":"audio","ssrc":"305419896","payloadTypes":[{"id":111,"name":"opus","clockrate":48000,"channels":2}]}]}
```

Smallest answer to the peer's offer (copy the peer's ssrc and exchangeId):

```json
{"@type":"NegotiateChannels","exchangeId":"<peer exchangeId>","contents":[{"type":"audio","ssrc":"<peer ssrc>","payloadTypes":[{"id":111,"name":"opus","clockrate":48000,"channels":2}]}]}
```

Omitting `rtpExtensions` is deliberate: the peer then sends bare RTP and
expects no transport-cc feedback from us. Omitting `feedbackTypes`/`parameters`
is legal (`v2/Signaling.cpp:186-225`). If you prefer to mirror 9.0.0, echo the
peer's whole content object verbatim.

The library forces `ptime=60` and `useinbandfec=1` on its sender regardless of
what we send (`v2/InstanceV2Impl.cpp:160-166`), and caps audio at 32 kbit/s
(`:2147`).

## 4. ICE over the reflector

The reflector envelope is unchanged from 5.0.0 and `TGCallReflector.m:134-157`
already matches `ReflectorPort`:

```
[16-byte peer tag, last 4 = destination tag][4-byte sender tag][4-byte BE payload length][payload][pad to 4]
```

(`v2/ReflectorPort.cpp:625-660`, receive `:733-790`). The 16-byte tag is
TDLib's `peer_tag`; the 4-byte sender tag is our own random tag. The hello/ping
is 16-byte tag + 12×FF + FE + 3×FF + uint64 123, padded to 4
(`v2/ReflectorPort.cpp:337-352`; `TGCallReflector.m:117-132`). The port becomes
ready, and only then emits its candidate, when a packet arrives back from the
reflector (sample:414, sample:418). Our code emits the candidate earlier; that
is harmless because the peer buffers candidates until the handshake completes
(`v2/InstanceV2Impl.cpp:1756-1760`).

Candidate differences from 5.0.0:

- component is **1**, not 0. 9.0.0 patches every gathered candidate to
  component 1 before serializing (`v2/InstanceV2Impl.cpp:1926-1928`).
- priority is relay type preference 2, local preference 127, component 1 =
  **41877760** (sample:426). 5.0.0 used 41878272/component 0.
- hostname is `reflector-<serverId>-<our 4-byte tag>.reflector`; the peer
  parses it as `reflector-<serverId>-<tag>.reflector` and refuses anything
  else (`v2/ReflectorPort.cpp:536-543`). `serverId` is the 1-based index into
  TDLib's server list.
- port must equal the reflector port (598 in the sample), same check at
  `v2/ReflectorPort.cpp:540-543`.
- `ufrag <ours>` must equal the ufrag in our `InitialSetup`; otherwise the peer
  logs "unknown ufrag" and leaves the candidate without a password
  (`p2p/base/p2p_transport_channel.cc:1222-1240`).
- `network-id`/`network-cost` are optional and skipped if unknown
  (`pc/webrtc_sdp.cc:1188-1213`).

ufrag is 4 random chars, pwd 24 (`v2/NativeNetworkingImpl.cpp:507`;
`p2p/base/p2p_constants.cc:23-26`). Our current 4/24 choice is right. The STUN
USERNAME is `remoteUfrag:localUfrag` (`p2p/base/port.cc:721-723`), which is what
`TGCallStun.m:104-106` already builds; no change.

Roles: caller is `ICEROLE_CONTROLLING`, callee `ICEROLE_CONTROLLED`
(`v2/NativeNetworkingImpl.cpp:651`). The controlled side sends
`ICE-CONTROLLED` and **never** `USE-CANDIDATE`; only the controlling side may
(`p2p/base/connection.cc:1045-1060`). Our current `TGCallStun.m:126-133` sends
`ICE-CONTROLLING` + `USE-CANDIDATE` from both roles; for 9.0.0 that must be
role-dependent or the peer sees a role conflict. Tie-breaker is a random
uint64, any value.

`v2/NativeNetworkingImpl.cpp:315` is **not** the media path. That
`EncryptedConnection(Type::Transport, ...)` belongs to `MtProtoPacketTransport`,
which is constructed only when the custom parameter `network_use_mtproto` is
set (`:661-679`). `enableStunMarking` only installs `TurnCustomizerImpl`, which
adds a STUN `SOFTWARE` attribute with the literal `"Telegram "`
(`v2/NativeNetworkingImpl.cpp:559-561`, `TurnCustomizerImpl.cpp:13-15`). The
sample has no MtProto transport logs, so 9.0.0 media is plain DTLS/SRTP over
the reflector. The `SOFTWARE` attribute is optional for us; the reflector is a
dumb relay and our 5.0.0 STUN already works without it.

XOR-MAPPED-ADDRESS: the peer answers with its remote-candidate address, not
the packet source (`p2p/base/connection.cc:716`), and for `.reflector`
candidates it ignores the mapped address when deciding on a prflx candidate
(`:1657-1670`). Our source-address answer is therefore tolerable; the attribute
must be present. Real checks in the sample produced prflx candidates
(sample:468-471), which is expected.

## 5. DTLS

Roles: caller is the DTLS **client**, callee the **server**. Caller announces
`setup: "actpass"`, callee `"passive"` (`v2/InstanceV2Impl.cpp:1586-1594`);
the peer maps `"passive"` to client and `"active"` to server, and falls back to
`isOutgoing ? client : server` for anything else
(`v2/NativeNetworkingImpl.cpp:784-793`). Sample confirms one side runs
`connect_loop TLS client` (sample:613) and the other `accept_loop TLS server`
(sample:573).

- Version: DTLS 1.2 only, min and max are both `DTLS1_2_VERSION`
  (`rtc_base/openssl_stream_adapter.cc:1017-1020`).
- Certificate: ECDSA P-256 (`rtc::KT_ECDSA`,
  `v2/NativeNetworkingImpl.cpp:509`; curve
  `NID_X9_62_prime256v1`, `rtc_base/openssl_key_pair.cc:58-60`). Self-signed is
  fine; the peer ignores chain and validity and checks only the digest
  (`rtc_base/openssl_stream_adapter.cc:1079-1112`).
- Fingerprint: `sha-256` over the DER certificate, colon-separated uppercase
  hex, in `InitialSetup.fingerprints[0]` (`rtc_base/ssl_fingerprint.cc:82-94`,
  `:108-113`; sample:106). `hash` is the algorithm string, `fingerprint` the
  hex, `setup` as above.
- Mutual auth: the server requires a client certificate
  (`SSL_VERIFY_FAIL_IF_NO_PEER_CERT`, `rtc_base/openssl_stream_adapter.cc:1035-1038`;
  default `client_auth_enabled_ = true`, `rtc_base/ssl_stream_adapter.h:276`).
- Cipher suites: OpenSSL cipher string
  `DEFAULT:!NULL:!aNULL:!SHA256:!SHA384:!aECDH:!AESGCM+AES256:!aPSK:!3DES`
  (`rtc_base/openssl_stream_adapter.cc:1060-1062`). With an ECDSA certificate
  the usable entries are the ECDHE-ECDSA ones in the map at
  `rtc_base/openssl_stream_adapter.cc:104-150`: AES-128-GCM-SHA256,
  AES-128-CBC-SHA, AES-256-CBC-SHA (AES-256-GCM is removed by
  `!AESGCM+AES256`, the CBC-SHA256/384 ones by `!SHA256`/`!SHA384`). The exact
  suite chosen is not printed in the sample (UNCONFIRMED).
- SRTP profiles offered, in order: `SRTP_AES128_CM_SHA1_80`, then
  `SRTP_AEAD_AES_256_GCM`, then `SRTP_AEAD_AES_128_GCM`
  (`api/crypto/crypto_options.cc:40-54`, enabled at
  `v2/NativeNetworkingImpl.cpp:482-487`). 9.0.0 selects the first common one;
  the sample shows `send crypto_suite 1 recv crypto_suite 1` (sample:597),
  and 1 is `SRTP_AES128_CM_SHA1_80` (`rtc_base/ssl_stream_adapter.h:36`).
- Keys: RFC 5705 exporter, label `EXTRACTOR-dtls_srtp`, no context, output
  `2*(16+14) = 60` bytes = `client_write_key||salt` then
  `server_write_key||salt`; the client uses the first half to send, the server
  the second (`pc/dtls_srtp_transport.cc:25`, `:225-250`;
  `rtc_base/ssl_stream_adapter.cc:55-77`).

Rejected by the library: a non-DTLS-1.2 handshake, a certificate whose
SHA-256 does not match the announced fingerprint, no client certificate, a
cipher suite outside the string above, and no common SRTP profile (then
`SetDtlsSrtpCryptoSuites` fails, `p2p/base/dtls_transport.cc:384-392`, and key
extraction never happens, `pc/dtls_srtp_transport.cc:212-217`).

OpenSSL 1.1.1 can do all of it. This repo ships 1.1.1d headers
(`include/openssl/opensslv.h:42-43`) with `DTLS_method()`
(`include/openssl/ssl.h:1907`), `SSL_CTX_set_min/max_proto_version`
(`:1440`), `SSL_CTX_set_tlsext_use_srtp` and `SSL_get_selected_srtp_profile`
(`include/openssl/srtp.h:38-42`), and `SSL_export_keying_material`
(`include/openssl/tls1.h:225`). The library must be linked with DTLS enabled —
UNCONFIRMED from the tree, check the link line. Use memory BIOs (the transport
is the reflector, not a socket), drive `DTLSv1_handle_timeout`, and keep
records under ~1200 bytes because the reflector adds 24 bytes plus padding.

## 6. SRTP and RTCP

Profile `SRTP_AES128_CM_SHA1_80`: AES-128 counter mode, 112-bit salt, 10-byte
HMAC-SHA1 tag (the `80` in the profile name; key/salt lengths
`rtc_base/ssl_stream_adapter.cc:55-77`; WebRTC calls libsrtp for
protect/unprotect, `pc/srtp_session.cc:33-34`, `:186`, `:232`). The libsrtp
source is not in the greppable tree, so the exact byte layout is UNCONFIRMED
there; it is RFC 3711.

Audio packet: normal RTP v2, PT 111, SSRC = the ssrc we offered, 48 kHz
timestamp, no header extensions if we omit them from the offer. On the wire it
is RTP header + encrypted payload + 10-byte tag. The library's sender uses
60 ms frames (`v2/InstanceV2Impl.cpp:163`); our existing engine uses 20 ms
(`src/Calls/TGCallAudioEngine.mm:10`), which the peer's NetEq accepts
(min delay 50 ms, `v2/InstanceV2Impl.cpp:329`).

RTCP is muxed on the same tag and port (`set_rtcp_mux(true)`,
`v2/InstanceV2Impl.cpp:179`, `:355`) and must be SRTCP-protected with the RTCP
half of the same keys. The library needs **nothing** from us to keep the call
alive: liveness is ICE/STUN, and its audio sender is pinned at 32 kbit/s
(min 32000 in sample:232, max set at `v2/InstanceV2Impl.cpp:2147`), so missing
receiver reports do not lower the bitrate. Its sender is configured with
`rtcp_report_interval_ms: 5000` (sample:232) and uses RR for RTT/loss stats.
If we advertise transport-cc (id 3) we must return transport-cc feedback at
most every 250 ms (sample:35); the simplest correct choice is not to advertise
it. Our existing 32-byte RR (`src/Calls/TGCallMessages.m:260-296`) is fine to
keep, now SRTCP-wrapped, but it is optional for audio.

## 7. SCTP data channel

Not required, either to establish or to carry audio.

Code path: `NativeNetworkingImpl::start` always creates
`SctpDataChannelProviderInterfaceImpl` over the DTLS transport
(`v2/NativeNetworkingImpl.cpp:697-717`). When ICE+DTLS become writable,
`updateIsConnected` starts SCTP with T1-init 5000 ms, T1-cookie 5000 ms, max
backoff 262144 ms (`SctpDataChannelProviderInterfaceImpl.cpp:101-110`). It
opens one reliable ordered channel labelled `"data"`, id 0, caller = opener,
callee = acker (`:28-46`). When it opens, `onDataChannelStateUpdated` calls
`sendMediaState` (`v2/InstanceV2Impl.cpp:1865-1872`), and `sendMediaState`
returns immediately while the channel is closed (`:1894-1897`). `MediaState`
is the only thing ever sent on it: `sendDataChannelMessage` has exactly one
call site, `:1923`.

Established state is `ICE connected && DTLS-SRTP writable`
(`v2/NativeNetworkingImpl.cpp:1009-1030`, `:1052-1055`); SCTP is not in that
test. With no data channel the peer's channel never opens, it keeps
retransmitting SCTP INIT with backoff, and nothing else changes: no
`MediaState` is sent or received, no timeout, no call failure. The
`onTerminated` callback is wired to a commented-out restart
(`v2/NativeNetworkingImpl.cpp:710-714`). So skip SCTP for the first port.

We must still consume DTLS application-data records (or at least not let them
break the record layer); read and discard.

If the remote mute indicator is wanted later, `MediaState` can also be sent as
a normal V2 signalling message: both paths call `processSignalingData`
(`v2/InstanceV2Impl.cpp:1647-1693`, `:1879-1884`) and the MediaState branch
runs for either (`:1760-1836`). 9.0.0 itself never does this.

## 8. Timeouts and failure

- 20 s: `NativeNetworkingImpl::checkConnectionTimeout` marks the call failed
  when `_isConnected` has been false for 20 s; it runs every 1 s
  (`v2/NativeNetworkingImpl.cpp:831-849`). This is the state that reaches the
  UI as `State::Failed`.
- `_isConnected` = ICE connected/completed **and** DTLS-SRTP writable
  (`:1009-1030`). So a missing or failed DTLS handshake ends the call in 20 s
  even when ICE is fine.
- No `InitialSetup` from us: the peer never sets remote ICE parameters and
  never commits our candidates (`v2/InstanceV2Impl.cpp:1704-1726`,
  `:1756-1760`) → ICE never leaves `kNew` → 20 s → failed.
- No `Candidates` from us: no remote candidate, same outcome.
- 15 s: a connection with no successful response for
  `CONNECTION_WRITE_TIMEOUT` becomes not writable
  (`p2p/base/p2p_constants.cc:70`,
  `p2p/base/ice_transport_internal.cc:123`), which starts the 20 s clock. So
  the peer drops a dead path about 35 s after the last STUN answer. Answer
  every check and keep sending checks (our 0.3 s cadence is fine).
- 5 s / `CONNECTION_WRITE_CONNECT_TIMEOUT` + minimum checks: unwritable
  detection before the 15 s path (`p2p/base/p2p_constants.cc:62-63`).
- DTLS handshake retransmission: initial RTO = `clamp(2*RTT, 50, 3000)` ms
  (`p2p/base/dtls_transport.cc:50-51`, `:862-872`), then normal exponential
  backoff. Total attempts are inside BoringSSL and not visible here
  (UNCONFIRMED).
- 44750 ms: unused-port cleanup, not a call timer
  (`p2p/base/port.cc:66-70`, `p2p/base/stun_request.h:36`).
- No negotiation timeout at all: if we never answer the peer's
  `NegotiateChannels`, the peer reaches Established and stays silent forever.
  "Connected but no audio" is the signature of a missing answer, not a
  timeout.

Bench reading: if the peer logs `DTLS handshake complete` and
`SRTP activated`, ICE and DTLS are done; silence then means the NegotiateChannels
answer or the RTP SSRC/PT is wrong. If it logs `NativeNetworkingImpl timeout`,
it never got our candidates or our STUN answers.

## 9. Order of work

1. **Framing and JSON** (≈250 lines, `TGCallMessages.m` mostly). Parse every
   seq-delimited element, use the 127 length, ack each message, retransmit
   unacked ones, replace the binary bodies with the four JSON shapes. Proof:
   the peer logs `processSignalingData: {"@type": "InitialSetup"...}` and
   `sendSignalingMessage` for its answer/offer; no `could not parse`.
2. **Candidates and roles** (≈60 lines, `TGCallIce.m`/`TGCallStun.m`). Component
   1, priority 41877760, `reflector-<serverId>-<tag>.reflector`, ufrag matching
   InitialSetup, controlled role and no USE-CANDIDATE for the callee. Proof:
   peer logs `Received remote ICE parameters: ufrag=...`, `Transport channel
   state changed from 0 to 2`, `Selecting connection for triggered check`
   (sample:192, sample:446, sample:468).
3. **DTLS** (≈450 lines, new). ECDSA P-256 cert, SHA-256 fingerprint, memory
   BIO pump over the reflector, DTLS 1.2, client/server by role, the cipher
   string, SRTP profile list, timers. Proof: peer logs
   `DtlsTransport: Started DTLS handshake` then `DTLS handshake complete`, and
   no `mismatched digest` (sample:529, sample:583).
4. **SRTP/SRTCP keys and packets** (≈350 lines). Exporter, key split, AES-CM,
   HMAC-SHA1-80, ROC/seq, SRTCP. Proof: peer logs
   `SRTP activated with negotiated parameters: send crypto_suite 1 recv
   crypto_suite 1` (sample:597); our packets decrypt at the peer and its
   packets decrypt at ours.
5. **Audio wiring** (≈120 lines). Send with the offered ssrc and PT 111; feed
   decrypted RTP to `TGCallAudioEngine`; start only after SRTP keys exist.
   Proof: the peer's `AudioSendStream::ConfigureStream` appears (sample:233)
   and its render shows our tone; our speaker plays its tone.
6. **RTCP RR** (≈40 lines). Wrap the existing RR in SRTCP; skip if time is
   short. Proof: peer RTCP stats show reports; audio already works without it.
7. **Optional**: `MediaState` over signalling (≈30 lines), or SCTP (≈500
   lines, skip). Proof for the cheap version: peer's remote media state changes.

A4 cost: AES-128-CTR + HMAC-SHA1 per packet is small at 50 packets/s, but
allocate nothing per packet — reuse the existing `_decryptScratch` pattern.
ECDSA keygen/sign is a few milliseconds once per call; keep the whole DTLS
handshake off the main thread. The 60-byte key export and SRTP contexts are
one-time. Do not add SCTP: it costs the peer retransmissions, not us.

## Assumptions

- 9.0.0 is `SignalingProtocolVersion::V2`; 12.0.0/13.0.0 are V3, which moves
  signalling itself onto SCTP (`v2/InstanceV2Impl.cpp:983-1000`). This document
  is V2 only.
- The peer runs the normal reflector path: no `network_use_mtproto`, no
  `network_standalone_reflectors`. The sample shows neither (no MtProto logs,
  hostnames are `reflector-1-<tag>.reflector`). UNCONFIRMED for other server
  configurations.
- TDLib supplies the 16-byte `peer_tag`, reflector host and port in
  `callStateReady`, as `TGCall.mm` already assumes.
- The offer's opus `parameters` and `rtpExtensions` are derived from tgcalls
  and WebRTC source; the sample line is truncated before them. UNCONFIRMED
  against the sample text.
- The negotiated DTLS cipher suite is not printed by the sample. UNCONFIRMED.
- The OpenSSL 1.1.1d library in this repo is built with DTLS. Headers are
  present; the link line is UNCONFIRMED.

## Check on the device, not here

- DTLS handshake wall time and CPU on the A4; whether the 1 s network-thread
  work causes audio dropouts.
- Actual audio quality/latency with 20 ms Opus frames against the peer's 60 ms
  sender, and whether the A4 keeps up with AES+HMAC per packet.
- iOS 6 UDP behaviour through the reflector (NAT rebinding, 100 ms recv
  timeout) under a real call.
- The real TDLib-selected 9.0.0 peer (the bench uses `tgcalls_cli --mode
  bridge`), including whether the server picks 9.0.0 at all.
- Whether the shipped OpenSSL links DTLS and the SRTP extension on armv7.
