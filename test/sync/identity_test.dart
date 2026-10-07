import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:dot/sync/identity.dart';
import 'package:dot/sync/tls_cert.dart';
import 'package:flutter/services.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test('hung keychain read falls back within five seconds', () async {
    final directory = await Directory.systemTemp.createTemp('dot-identity-');
    try {
      final store = SecureSecretStore(directory, storage: _HungReadStorage());
      final identity = await DeviceIdentity.load(store)
          .timeout(const Duration(seconds: 5));
      final file = File('${directory.path}/secrets/identity.json');
      final saved =
          jsonDecode(await file.readAsString()) as Map<String, dynamic>;
      expect(saved['id'], identity.deviceId);

      // An existing fallback must bypass the keychain on restart.
      final restored = await DeviceIdentity.load(
        SecureSecretStore(directory, storage: _HungReadStorage()),
      ).timeout(const Duration(seconds: 1));
      expect(restored.deviceId, identity.deviceId);
      expect(restored.publicKey, identity.publicKey);
    } finally {
      await directory.delete(recursive: true);
    }
  });
  test(
    'unavailable keychain falls back to private files and survives restart',
    () async {
      const channel = MethodChannel(
        'plugins.it_nomads.com/flutter_secure_storage',
      );
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (_) async {
            throw PlatformException(code: 'keychain_unavailable');
          });
      final directory = await Directory.systemTemp.createTemp('dot-identity-');
      try {
        final firstStore = SecureSecretStore(directory);
        final first = await DeviceIdentity.load(firstStore);
        final tls = await TlsCertificate.load(firstStore);
        final restartedStore = SecureSecretStore(directory);
        final second = await DeviceIdentity.load(restartedStore);
        final restoredTls = await TlsCertificate.load(restartedStore);
        expect(second.deviceId, first.deviceId);
        expect(second.publicKey, first.publicKey);
        expect(restoredTls.fingerprint, tls.fingerprint);
        final file = File('${directory.path}/secrets/identity.json');
        expect((await file.stat()).mode & 0x1ff, 0x180); // 0600
        expect((await file.parent.stat()).mode & 0x1ff, 0x1c0); // 0700
      } finally {
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(channel, null);
        await directory.delete(recursive: true);
      }
    },
  );
}

class _HungReadStorage extends FlutterSecureStorage {
  @override
  Future<String?> read({
    required String key,
    AppleOptions? iOptions,
    AndroidOptions? aOptions,
    LinuxOptions? lOptions,
    WebOptions? webOptions,
    AppleOptions? mOptions,
    WindowsOptions? wOptions,
  }) => Completer<String?>().future;
}
