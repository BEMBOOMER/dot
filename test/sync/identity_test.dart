import 'dart:io';

import 'package:dot/sync/identity.dart';
import 'package:dot/sync/tls_cert.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
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
