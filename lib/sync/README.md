# LAN sync implementation

`createLanEngine` is registered in `lib/main.dart`. Demo mode still uses the
existing `FakeSyncEngine`. No core API changes are required.

## Trust and transport

Identity and EC P-256 TLS material are persistent secure-storage records. When
keychain access fails, records are atomically written beneath the application
support directory with directory mode 0700 and file mode 0600. Tests inject
`SecretStore` and `LanDiscovery` without loading native plugins.

All WebSocket clients use an empty system trust store and accept only the
expected certificate SHA-256 pin. Both peers prove possession of their stored
Ed25519 keys using fresh, role-prefixed challenges (`client:` / `host:`), including
on first pairing. Pair messages include the client's signature and challenge;
`pair_result` includes the host's signature. Host confirmation consumes the
five-minute token and invalidates simultaneous requests.

A manual code has no QR fingerprint. A separate TLS probe obtains a candidate
certificate without transmitting credentials or content. A WebSocket pinned to
that candidate then requests `manual_probe {nonce}`. The host returns
`manual_proof {deviceId,name,proof}`, where proof is HMAC-SHA256 of
`nonce:fingerprint:deviceId:name` keyed by the six-character code. Only after
verification does the client present a pairing preview. The server never accepts
item traffic on that unauthenticated connection.

## Files and outbox

JSON frames follow the architecture contract. Additional challenge/signature
fields, `manual_probe`, `manual_proof` and `file_retry {id}` support mutual
identity proof, the manual route and receiver-initiated retries. Unknown JSON
message types are ignored after authentication. Protocol major 1 is required.

Files send one 256 KiB chunk at a time. The receiver acknowledges every durable
chunk with `file_resume {id,offset}`, providing flow control and a persisted
resume position. Partial names include the content hash, preventing an old
prefix being reused for different content. A checksum failure deletes the
corrupt partial. Final filenames use an item UUID prefix and a sanitized
basename to prevent collisions and path traversal. Only `file_ack ok` clears
the sender's dirty version; stale item acknowledgements cannot clear newer edits.

A single active peer connection synchronizes the shared workspace. Streams are
processed sequentially. Disconnects keep the outbox and partial files. Reconnect
uses Bonjour then the stored address, exponential backoff from 1 to 30 seconds,
and respects `autoReconnect`. Inactive lifecycle state stops transports and
foreground state starts them again. Ping interval is 15 seconds; a 5-second
watchdog disconnects after at least 40 seconds without an incoming frame.

## Verification

Tests in `test/sync` exercise real loopback TLS/WebSockets and in-memory SQLite:
pairing (QR/manual), pin rejection, two-way item delivery, offline replay without
duplicates, note conflicts, 1 MiB file delivery and SHA-256 verification, revoked
identity rejection, cancelled offers, token expiry/single use, frame validation,
keychain fallback/permissions, cancellation/resume and corrupt-file rejection.

Real-device Bonjour discovery, Android secure storage/documents access, signed
macOS keychain access, native lifecycle integration and Wi-Fi changes still need
Android/macOS device testing. Those adapters are implemented, not stubbed.

The standard Flutter shell launcher cannot update its SDK cache in this sandbox.
The cached tool snapshot works without changing the SDK:

```sh
FLUTTER_ALREADY_LOCKED=true XDG_CONFIG_HOME=/private/tmp/dot-flutter-config \
  /opt/homebrew/share/flutter/bin/cache/dart-sdk/bin/dart \
  /opt/homebrew/share/flutter/bin/cache/flutter_tools.snapshot \
  --no-version-check analyze --no-pub lib/sync test/sync lib/main.dart

FLUTTER_ALREADY_LOCKED=true XDG_CONFIG_HOME=/private/tmp/dot-flutter-config \
  /opt/homebrew/share/flutter/bin/cache/dart-sdk/bin/dart \
  /opt/homebrew/share/flutter/bin/cache/flutter_tools.snapshot \
  --no-version-check test --no-pub test/core test/sync
```
