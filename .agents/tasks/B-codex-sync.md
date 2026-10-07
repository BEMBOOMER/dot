# Task B (Codex): real LAN sync engine — you own lib/sync/ and test/sync/

Read AGENTS.md, docs/ARCHITECTURE.md (Pairing & trust, Wire protocol, Sync rules) and lib/core/*.dart.
Implement `LanSyncEngine implements SyncEngine` in lib/sync/ (split into files: identity.dart, tls_cert.dart, discovery.dart, protocol.dart, host_server.dart, client_connection.dart, file_transfer.dart, lan_sync_engine.dart).

Requirements
- Identity: Ed25519 keypair + deviceId (uuid) created on first run, stored via flutter_secure_storage with a file fallback (app support dir, chmod 600) when the keychain throws (unsigned macOS builds).
- macOS = host: self-signed EC P-256 TLS cert (basic_utils), `HttpServer.bindSecure` on a fixed preferred port 48620 (fallback to any free port), WebSocket upgrade, Bonjour advertise `_dotlink._tcp` via `nsd` with TXT id=deviceId. Pick a LAN IPv4 (en0/wlan, skip loopback/link-local) for the QR.
- Android = client: discover via nsd, else last known host/port, connect with `HttpClient` + badCertificateCallback that ONLY accepts the pinned SHA-256 fingerprint; `WebSocket.fromUpgradedSocket` or `WebSocket.connect(customClient:)`.
- Pairing exactly as ARCHITECTURE.md: one-time token (5 min, single use), QR `dot://pair?...`, manual input "192.168.1.20:48620 ABC123". Host emits PairRequestEvent and waits for respondToPairRequest. Store PairedDevice in DeviceStore on both sides.
- Every later connection: TLS pin + Ed25519 challenge/response; unknown/revoked → close with reason. unpair sends `unpair` and deletes locally; receiving `unpair` deletes the device.
- Sync: on connect hello → flush ItemRepository.pending(); peer applies via applyRemote and acks; markSynced on ack. Idempotent. Set SyncState sending/received/waiting/failed appropriately; when no peer reachable set dirty items to waiting.
- Files: file_offer/file_resume/binary chunks (256 KiB)/file_done/file_ack per protocol. Receiver writes to `<downloadDir or ~/Downloads/DOT>` on macOS and app documents/received on Android, as `.part` then renamed after sha256 verify. Progress via `transfers` ValueNotifier (throttle ~10/s). cancelTransfer sends file_cancel; retry resumes from the receiver's offset. Item becomes Ontvangen only after file_ack ok.
- Status machine: unpaired / searching / pairing / connected / syncing / offline (no network) / failed (with Dutch lastError + reconnect). Auto reconnect with backoff (1s→30s) when settings.autoReconnect; pause when app inactive (onAppLifecycle).
- Ping every 15s, drop after 40s silence. Logs never include item content.
- Register it: in lib/main.dart replace the FakeSyncEngine default factory with LanSyncEngine (keep FakeSyncEngine for demo mode). Only touch main.dart/bootstrap.dart for that wiring.
- Tests (test/sync/): protocol encode/decode, token expiry/single-use, fingerprint pinning reject, and an in-process loopback test: host + client engines on 127.0.0.1 with in-memory dbs, pair, send text item both ways, offline queue flush without duplicates, note conflict, file transfer of a 1 MB file with sha check, revoked device rejected. Inject nsd/secure storage behind small interfaces so tests run with `flutter test`.
- `flutter analyze` clean, `flutter test` green. Report what is verified vs. untested.
