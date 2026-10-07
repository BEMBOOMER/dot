import 'dart:typed_data';

import 'package:dot/sync/identity.dart';
import 'package:dot/sync/protocol.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test(
    'text frames round-trip and unknown messages remain forward compatible',
    () {
      expect(decodeMessage(encodeMessage('hello', {'proto': 1})), {
        't': 'hello',
        'proto': 1,
      });
      expect(
        decodeMessage(encodeMessage('future_feature'))['t'],
        'future_feature',
      );
      expect(() => decodeMessage('[]'), throwsFormatException);
      expect(() => decodeMessage('{"t":42}'), throwsFormatException);
    },
  );
  test('binary frame uses UUID and big-endian 64-bit offset', () {
    const id = '12345678-1234-4234-8234-123456789abc';
    final encoded = FileChunk(
      id,
      0x123456789,
      Uint8List.fromList([1, 2, 3]),
    ).encode();
    expect(encoded.length, 47);
    expect(
      ByteData.sublistView(encoded).getUint64(36, Endian.big),
      0x123456789,
    );
    final decoded = FileChunk.decode(encoded);
    expect(decoded.id, id);
    expect(decoded.offset, 0x123456789);
    expect(decoded.bytes, [1, 2, 3]);
    expect(() => FileChunk.decode([1]), throwsFormatException);
    expect(
      () => FileChunk(id, 0, Uint8List(chunkSize + 1)).encode(),
      throwsFormatException,
    );
  });
  test('tokens expire after five minutes and short code is single-use', () {
    var now = DateTime(2026);
    final tokens = PairingTokens(clock: () => now)..issue();
    final token = tokens.token!;
    final code = tokens.code!;
    expect(code.length, 6);
    expect(tokens.matches('wrong'), isFalse);
    now = now.add(const Duration(minutes: 5));
    expect(tokens.consume(token), isFalse);
    tokens.issue();
    final nextToken = tokens.token!;
    expect(tokens.consume(tokens.code!), isTrue);
    expect(tokens.consume(nextToken), isFalse);
    tokens.issue();
    tokens.cancel();
    expect(tokens.valid, isFalse);
  });
  test('identity persists and verifies only the correct fresh nonce', () async {
    final store = MemorySecretStore();
    final first = await DeviceIdentity.load(store);
    final second = await DeviceIdentity.load(store);
    expect(second.deviceId, first.deviceId);
    expect(second.publicKey, first.publicKey);
    final signature = await first.sign('fresh');
    expect(
      await DeviceIdentity.verify(second.publicKey, 'fresh', signature),
      isTrue,
    );
    expect(
      await DeviceIdentity.verify(second.publicKey, 'replay', signature),
      isFalse,
    );
  });
}
