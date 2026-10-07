# Task A (Codex): scaffold + core

Read AGENTS.md, docs/CONCEPT.md, docs/ARCHITECTURE.md.

You run in a sandbox that can only write inside this repo (network allowed). The reviewer already ran
`flutter create` and `flutter pub get`. If a flutter command fails because it needs to write outside the repo
(pub cache, gradle, SDK cache), don't fight it: finish the code and list the exact command(s) in your report so the reviewer runs them.

1. (done by reviewer) flutter create.
2. Replace the generated lib/main.dart and test/widget_test.dart.
3. pubspec.yaml: dependencies are already added by the reviewer (check them; if one is missing, add it to pubspec and report it). Register fonts: family `ArchivoBlack` (assets/fonts/ArchivoBlack-Regular.ttf) and `SpaceGrotesk` (assets/fonts/SpaceGrotesk.ttf, variable font).
   Android minSdk 23+ (whatever mobile_scanner/nsd need), Kotlin/AGP versions that build with JDK 17.
4. Finish lib/core (models.dart, database.dart, item_repository.dart, device_store.dart, settings_store.dart already exist; review & fix them):
   - `sync_engine.dart`: abstract `SyncEngine extends ChangeNotifier` exactly per docs/ARCHITECTURE.md "Core API", plus `localDeviceId`, `localName`, `isHost`, `onAppLifecycle({required bool active})`, `cancelPairingOffer()`, and `ValueListenable<Map<String,double>> get transfers`.
   - `fake_sync_engine.dart`: in-memory demo engine (status cycles searching → connected; sending marks items received after ~800ms; it can simulate an incoming item). Used for "Eerst bekijken" and UI work.
   - `app_state.dart`: `AppState extends ChangeNotifier` wiring ItemRepository, DeviceStore, SettingsStore and a SyncEngine. Helpers: addText, addLink (normalise url, title = host), addFile(path) (copy into app support dir `files/`, compute sha256, size, mime), addNote, updateNote, pasteAndSend (reads clipboard ONLY when called), togglePin, deleteItem, copyItem, clearHistory, enterDemoMode/exitDemoMode. After local writes call engine.syncNow().
   - `bootstrap.dart`: opens db/prefs, builds AppState. Engine factory: a function `SyncEngine Function(ctx)` registered from main.dart so lib/sync can plug in later; default to FakeSyncEngine for now.
5. lib/main.dart + lib/app.dart: MultiProvider, MaterialApp with light/dark from settings, named routes `/welcome`, `/pair`, `/workspace`, `/item`, `/devices`, `/settings` pointing to simple placeholder widgets in `lib/ui/screens/` (one file per screen, class names WelcomeScreen, PairScreen, WorkspaceScreen, ItemDetailScreen, DevicesScreen, SettingsScreen). The UI agent will replace these.
6. Tests in test/core/: repository applyRemote rules (insert, duplicate, tombstone not resurrected, fast-forward, note conflict copy, LWW), markSynced only on matching etag. Use sqflite_common_ffi in-memory.
7. `flutter analyze` clean, `flutter test` green, and `flutter build macos --debug` succeeds.
Report files changed and anything left open.
