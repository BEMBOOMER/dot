import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';

import 'identity.dart';

const protocolVersion = 1;
const chunkSize = 256 * 1024;
String encodeMessage(String type, [Map<String, Object?> fields = const {}]) =>
    jsonEncode({...fields, 't': type});
Map<String, dynamic> decodeMessage(String frame) {
  if (frame.length > 2 * 1024 * 1024) {
    throw const FormatException('Bericht te groot.');
  }
  final data = jsonDecode(frame);
  if (data is! Map<String, dynamic> || data['t'] is! String) {
    throw const FormatException('Ongeldig bericht.');
  }
  return data;
}

class FileChunk {
  final String id;
  final int offset;
  final Uint8List bytes;
  FileChunk(this.id, this.offset, this.bytes);
  Uint8List encode() {
    if (!RegExp(r'^[a-fA-F0-9-]{36}$').hasMatch(id) ||
        offset < 0 ||
        bytes.length > chunkSize) {
      throw const FormatException('Ongeldig bestandsblok.');
    }
    final result = Uint8List(44 + bytes.length);
    result.setRange(0, 36, ascii.encode(id));
    ByteData.sublistView(result).setUint64(36, offset, Endian.big);
    result.setRange(44, result.length, bytes);
    return result;
  }

  static FileChunk decode(List<int> frame) {
    if (frame.length < 44 || frame.length > 44 + chunkSize) {
      throw const FormatException('Ongeldig bestandsblok.');
    }
    final data = Uint8List.fromList(frame);
    final id = ascii.decode(data.sublist(0, 36));
    if (!RegExp(r'^[a-fA-F0-9-]{36}$').hasMatch(id)) {
      throw const FormatException('Ongeldig bestands-ID.');
    }
    return FileChunk(
      id,
      ByteData.sublistView(data).getUint64(36, Endian.big),
      Uint8List.sublistView(data, 44),
    );
  }
}

class PairingTokens {
  final DateTime Function() now;
  String? token;
  String? code;
  DateTime? expiresAt;
  PairingTokens({DateTime Function()? clock}) : now = clock ?? DateTime.now;
  void issue() {
    token = randomNonce();
    const alphabet = 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789';
    code = List.generate(
      6,
      (_) => alphabet[Random.secure().nextInt(alphabet.length)],
    ).join();
    expiresAt = now().add(const Duration(minutes: 5));
  }

  bool get valid =>
      token != null && expiresAt != null && now().isBefore(expiresAt!);
  bool matches(String value) => valid && (value == token || value == code);
  bool consume(String value) {
    if (!matches(value)) return false;
    cancel();
    return true;
  }

  void cancel() {
    token = null;
    code = null;
    expiresAt = null;
  }
}

String manualProof(
  String code,
  String nonce,
  String fingerprint,
  String deviceId,
  String name,
) => Hmac(
  sha256,
  utf8.encode(code),
).convert(utf8.encode('$nonce:$fingerprint:$deviceId:$name')).toString();
