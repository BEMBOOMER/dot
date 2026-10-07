import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:cryptography/cryptography.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:path/path.dart' as p;
import 'package:uuid/uuid.dart';

abstract interface class SecretStore {
  Future<String?> read(String key);
  Future<void> write(String key, String value);
}

class SecureSecretStore implements SecretStore {
  final FlutterSecureStorage storage;
  final Directory directory;
  bool _fallback = false;
  SecureSecretStore(
    this.directory, {
    this.storage = const FlutterSecureStorage(),
  });

  File _file(String key) =>
      File(p.join(directory.path, 'secrets', '$key.json'));
  @override
  Future<String?> read(String key) async {
    // Once fallback exists it is authoritative, even if the keychain recovers.
    final file = _file(key);
    if (await file.exists()) return file.readAsString();
    if (!_fallback) {
      try {
        return await storage
            .read(key: 'dot.$key')
            .timeout(const Duration(seconds: 3));
      } catch (_) {
        _fallback = true;
      }
    }
    return null;
  }

  @override
  Future<void> write(String key, String value) async {
    if (!_fallback && !await _file(key).exists()) {
      try {
        await storage
            .write(key: 'dot.$key', value: value)
            .timeout(const Duration(seconds: 3));
        return;
      } catch (_) {
        _fallback = true;
      }
    }
    final file = _file(key);
    await file.parent.create(recursive: true);
    if (!Platform.isWindows) {
      final result = await Process.run('chmod', ['700', file.parent.path]);
      if (result.exitCode != 0) {
        throw const FileSystemException('Secret directory permissions');
      }
    }
    final temporary = File('${file.path}.tmp');
    // Create without secret contents, restrict permissions, then write.
    await temporary.writeAsString('');
    if (!Platform.isWindows) {
      final result = await Process.run('chmod', ['600', temporary.path]);
      if (result.exitCode != 0) {
        throw const FileSystemException('Secret file permissions');
      }
    }
    await temporary.writeAsString(value, flush: true);
    await temporary.rename(file.path);
  }
}

class MemorySecretStore implements SecretStore {
  final Map<String, String> values = {};
  @override
  Future<String?> read(String key) async => values[key];
  @override
  Future<void> write(String key, String value) async {
    values[key] = value;
  }
}

String randomNonce([int length = 32]) => base64UrlEncode(
  List<int>.generate(length, (_) => Random.secure().nextInt(256)),
);

class DeviceIdentity {
  final String deviceId;
  final SimpleKeyPair keyPair;
  final String publicKey;
  DeviceIdentity(this.deviceId, this.keyPair, this.publicKey);

  static Future<DeviceIdentity> load(
    SecretStore store, {
    String? initialDeviceId,
  }) async {
    final saved = await store.read('identity');
    final algorithm = Ed25519();
    if (saved != null) {
      final data = jsonDecode(saved) as Map<String, dynamic>;
      final pair = await algorithm.newKeyPairFromSeed(
        base64Decode(data['seed'] as String),
      );
      return DeviceIdentity(
        data['id'] as String,
        pair,
        base64Encode((await pair.extractPublicKey()).bytes),
      );
    }
    final seed = List<int>.generate(32, (_) => Random.secure().nextInt(256));
    final pair = await algorithm.newKeyPairFromSeed(seed);
    final id = initialDeviceId ?? const Uuid().v4();
    await store.write(
      'identity',
      jsonEncode({'id': id, 'seed': base64Encode(seed)}),
    );
    return DeviceIdentity(
      id,
      pair,
      base64Encode((await pair.extractPublicKey()).bytes),
    );
  }

  Future<String> sign(String nonce) async => base64Encode(
    (await Ed25519().sign(utf8.encode(nonce), keyPair: keyPair)).bytes,
  );

  static Future<bool> verify(
    String publicKey,
    String nonce,
    String signature,
  ) async {
    try {
      return await Ed25519().verify(
        utf8.encode(nonce),
        signature: Signature(
          base64Decode(signature),
          publicKey: SimplePublicKey(
            base64Decode(publicKey),
            type: KeyPairType.ed25519,
          ),
        ),
      );
    } catch (_) {
      return false;
    }
  }
}
