# DOT — architecture contract

This document is the contract between the people/agents building DOT. Read `docs/CONCEPT.md` for the product spec (Dutch). UI copy is Dutch, code/comments/commits are English.

## Stack
- Flutter (stable), Dart 3, targets: `android`, `macos`. Bundle/app id: `com.bemooks.dot`.
- State: `provider` + `ChangeNotifier`. No other state library.
- Local data: `sqflite` (works on Android and macOS). Preferences: `shared_preferences`.
- Secrets (identity keys, TLS key): `flutter_secure_storage`, with a file fallback in the app support dir if the keychain is unavailable (unsigned macOS dev builds).
- Discovery: `nsd` (Bonjour on macOS, NSD on Android), service type `_dotlink._tcp`.
- Transport: WebSocket over TLS (`dart:io` `HttpServer.bindSecure` on macOS, `WebSocket.connect` / `HttpClient` with pinned cert on Android).
- Crypto: `cryptography` (Ed25519 identity + HMAC), `basic_utils` (self-signed EC cert generation), `crypto` (sha256).
- UI packages: `qr_flutter` (mac shows QR), `mobile_scanner` (android scans), `file_picker`, `url_launcher`, `share_plus`, `open_filex`, `flutter_local_notifications`.
- macOS packages: `window_manager`, `tray_manager`, `launch_at_startup`, `desktop_drop`.
- Android: `receive_sharing_intent` (share menu target).

## Folder ownership (do not edit folders you don't own without a note in your report)
```
lib/
  main.dart              # bootstrap (integrator)
  app.dart               # MaterialApp, routing, theme switching (integrator)
  core/                  # models, repository, settings, AppState, SyncEngine interface (integrator) — FROZEN API
  sync/                  # pairing, identity, TLS, server/client, discovery, protocol, file transfer (sync agent)
  ui/theme/              # tokens, ThemeData, noise (ui agent)
  ui/dots/               # 3D dot painter + status animations (ui agent)
  ui/screens/            # welcome, pair, workspace, item detail, devices, settings (ui agent)
  ui/widgets/            # shared widgets: brutal cards/buttons, status bar (ui agent)
  platform/              # share intent, tray, window, launch-at-login, drop, notifications (platform agent)
test/                    # each agent adds tests for its own folder
android/ macos/          # native config (platform agent)
.github/workflows/       # CI + release (platform agent)
```

## Core API (lib/core) — summary
- `models.dart`: `ItemType {text, link, file, note}`, `SyncState {local, waiting, sending, received, failed}`, `DotItem`, `PairedDevice`, `ConnectionStatus {unpaired, searching, pairing, connected, syncing, offline, failed}` with Dutch labels via `statusLabel(status, peerName)`.
- `item_repository.dart`: `ItemRepository extends ChangeNotifier` over sqflite. `all({query, type})`, `get(id)`, `upsertLocal(item)` (bumps etag, marks dirty), `applyRemote(item)` (conflict rules below), `markSynced(id, etag)`, `setSyncState`, `setProgress`, `pending()`, `delete(id)` (tombstone), `clearHistory()`.
- `device_store.dart`: `DeviceStore extends ChangeNotifier` — paired devices (persisted in sqflite), `add/update/remove/get`.
- `settings_store.dart`: `SettingsStore extends ChangeNotifier` — themeMode, reducedMotion, notifications, autoReconnect, launchAtLogin, downloadDir, menuBarIcon, deviceName.
- `sync_engine.dart`: abstract `SyncEngine extends ChangeNotifier`:
  - `ConnectionStatus get status`, `String? get peerName`, `String? get lastError`
  - `Stream<SyncEvent> get events` (`sent(itemId)`, `received(itemId)`, `pairRequest(PairingRequest)`, `paired(device)`)
  - `Future<void> start()` / `stop()` — start discovery/server, auto reconnect
  - Host (mac): `Future<PairingOffer> createPairingOffer()` → `qrPayload` + `manualCode` + host/port, valid 5 min, one-time
  - Client (android): `Future<PairingPreview> previewPairing(String qrPayloadOrManual)`, `Future<PairedDevice> confirmPairing(PairingPreview)`
  - Host confirm: `Future<void> respondToPairRequest(String requestId, bool accept)`
  - `Future<void> reconnect()`, `Future<void> unpair(String deviceId)`, `Future<void> syncNow()`
  - `Future<void> cancelTransfer(String itemId)`, `Future<void> retry(String itemId)`
- `FakeSyncEngine` (core/fake_sync_engine.dart): in-memory demo engine used for "Eerst bekijken" and for UI development.
- `AppState` (core/app_state.dart): wires repository + devices + settings + engine; exposes helper actions the UI calls (`addText`, `addLink`, `addFile(path)`, `addNote`, `updateNote`, `pasteAndSend`, `togglePin`, `deleteItem`).

## Sync rules
- Every item: `id` (uuid v4), `etag` (uuid per content version), `parentEtag` (etag it was edited from), `dirty` (needs sending), `deleted` (tombstone, never resurrected).
- Outbox = items with `dirty == true`. Sending is idempotent by `(id, etag)`. Receiver replies `ack {id, etag}`; sender then `markSynced` → `SyncState.received`.
- Receiver `applyRemote(incoming)`:
  1. local missing → insert (unless a tombstone for id exists).
  2. local.deleted → ignore incoming (ack anyway). incoming.deleted → tombstone locally.
  3. local.etag == incoming.etag → duplicate, ack.
  4. local.etag == incoming.parentEtag or !local.dirty → fast-forward, replace.
  5. else conflict: for notes keep local and insert incoming as a new note with `conflictOf = id` and title suffix " (andere versie)"; for other types last-writer-wins by `updatedAt`.
- On connect both sides send `hello {deviceId, protocolVersion, appVersion}` then flush their outbox. Unknown message types are ignored (forward compat). `protocolVersion` mismatch with major difference → status failed with clear message.

## Wire protocol (JSON text frames, binary frames for file chunks)
```
{ "t": "hello", "deviceId", "name", "platform", "proto": 1, "app": "1.0.0" }
{ "t": "auth", "deviceId", "nonce", "sig" }           # client proves identity (Ed25519 over server nonce)
{ "t": "challenge", "nonce" }
{ "t": "pair", "requestId", "token", "deviceId", "name", "platform", "pubKey" }
{ "t": "pair_result", "requestId", "accepted", "deviceId", "name", "pubKey" }
{ "t": "item", "item": {...DotItem.toWire()} }
{ "t": "ack", "id", "etag" }
{ "t": "file_offer", "id", "etag", "name", "size", "sha256", "offset" }
{ "t": "file_resume", "id", "offset" }                 # receiver says where to continue
binary: [36 bytes item id ascii][8 bytes big-endian offset][chunk ≤ 256 KiB]
{ "t": "file_done", "id", "sha256" }  → receiver verifies, then { "t": "file_ack", "id", "ok" }
{ "t": "file_cancel", "id" }
{ "t": "unpair", "deviceId" }
{ "t": "ping" } / { "t": "pong" }
```

## Pairing & trust
- macOS is the host (TLS server, advertises `_dotlink._tcp` with TXT `id=<deviceId>`). Android is the client.
- First run each device creates an Ed25519 identity keypair and (mac) a self-signed EC TLS cert. Stored in secure storage.
- QR payload: `dot://pair?h=<ip>&p=<port>&t=<one-time token>&f=<sha256 cert fingerprint hex>&n=<name>&id=<deviceId>`. Token valid 5 minutes, single use. No long-lived secret in the QR.
- Manual route: user types IP, port and 6-char code shown on the Mac (code = token short form).
- Client pins the TLS cert fingerprint from the QR. Host shows an incoming pair request (name + platform) and the user confirms on the Mac; client also confirms on Android before sending.
- After pairing: host stores client pubKey; client stores host cert fingerprint + pubKey. Every later connection: TLS pin check + Ed25519 challenge/response. Unknown or revoked devices are disconnected immediately.
- Logs never contain item content.

## Visual tokens
paper `#F5F0E8`, ink `#1A1A1A`, coral `#FF4F81` (primary), lime `#CCFF00` (connected), plus sparing blue `#2979FF`, amber `#FFA41F`. Dark theme: background `#121212`, surface `#1E1E1E`, text paper. Headings Archivo Black, body Space Grotesk (bundled in `assets/fonts`). Cards/buttons: radius 18, 2px ink border, hard offset shadow (4,4) in ink, subtle noise overlay. Animations 200–500 ms, ambient loops pause when app is inactive; reduced motion → fades only.
