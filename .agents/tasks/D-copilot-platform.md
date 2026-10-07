# Task D (Copilot): platform integration, native config, CI/release — you own lib/platform/, android/, macos/, .github/, scripts/

Read AGENTS.md, docs/CONCEPT.md (macOS-/Android-specifieke mogelijkheden, GitHub en installatie), docs/ARCHITECTURE.md.

1. Native config
   - Android: INTERNET, ACCESS_NETWORK_STATE, ACCESS_WIFI_STATE, CHANGE_WIFI_MULTICAST_STATE, CAMERA, POST_NOTIFICATIONS; share intent filters (text/plain, image/*, */*, SEND + SEND_MULTIPLE) for receive_sharing_intent; usesCleartextTraffic false; app label "DOT"; release signing from android/key.properties (gitignored) with fallback to debug signing when absent.
   - macOS: entitlements (Debug + Release) network.server, network.client, files.user-selected.read-write, files.downloads.read-write, keychain access; Info.plist NSLocalNetworkUsageDescription (Dutch), NSBonjourServices `_dotlink._tcp`, NSCameraUsageDescription not needed; min macOS 11; app name "DOT".
2. lib/platform/:
   - share_intake.dart: Android share menu → AppState.addText/addLink/addFile (initial + streaming intents).
   - desktop_shell.dart (macOS only, no-op elsewhere): window_manager (min size 420x560, title DOT), tray_manager menubar icon showing status text + "Open DOT", "Snel delen" (compact window mode 380x520 always-on-top), "Afsluiten"; close button hides window when menubar is enabled (visible in tray), otherwise quits; launch_at_startup bound to settings.launchAtLogin; desktop_drop wired to WorkspaceScreen `onFilesDropped` / AppState.addFile.
   - notifier.dart: flutter_local_notifications on ItemReceivedEvent when settings.notifications (Android 13 runtime permission request).
   - file_actions.dart: open file (open_filex), reveal in Finder (`open -R` via Process on macOS), share (share_plus).
   - update_checker.dart: query GitHub Releases latest (`https://api.github.com/repos/BEMBOOMER/dot/releases/latest`), compare with package version, return {version, url, notes}; never auto-install.
   - Wire them in lib/main.dart/app.dart with minimal edits (init calls only).
   - Generate tray/app icons: a coral dot on paper (draw with a small Dart or Python script into assets/icons/, then use flutter_launcher_icons config for android+macos). No logos.
3. CI/release in .github/workflows/:
   - ci.yml: on push/PR: flutter analyze + flutter test (ubuntu), build apk debug (ubuntu), build macos (macos-latest).
   - release.yml: on tag v*: build release APK signed with secrets (ANDROID_KEYSTORE_BASE64, ANDROID_KEYSTORE_PASSWORD, ANDROID_KEY_ALIAS, ANDROID_KEY_PASSWORD), build macOS release .app → DMG (hdiutil, ad-hoc codesign; optional notarization step guarded by secrets APPLE_*), sha256 checksums file, GitHub Release with notes from CHANGELOG.md section.
   - scripts/make_keystore.sh (creates release keystore outside the repo + prints the secrets to set), scripts/build_dmg.sh (local DMG build).
4. `flutter analyze` clean; `flutter build apk --debug` and `flutter build macos --debug` succeed locally (JAVA_HOME=/opt/homebrew/opt/openjdk@17). Report.
