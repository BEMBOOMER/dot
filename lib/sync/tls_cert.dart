import 'dart:convert';
import 'dart:io';

import 'package:basic_utils/basic_utils.dart';
import 'package:crypto/crypto.dart';

import 'identity.dart';

String certificateFingerprint(X509Certificate certificate) =>
    sha256.convert(certificate.der).toString();
bool acceptsFingerprint(X509Certificate certificate, String pin) =>
    pin.length == 64 &&
    certificateFingerprint(certificate) == pin.toLowerCase();

class TlsCertificate {
  final String certificatePem;
  final String keyPem;
  TlsCertificate(this.certificatePem, this.keyPem);
  String get fingerprint {
    final body = certificatePem.replaceAll(RegExp(r'-----[^-]+-----|\s'), '');
    return sha256.convert(base64Decode(body)).toString();
  }

  SecurityContext get context => SecurityContext()
    ..useCertificateChainBytes(utf8.encode(certificatePem))
    ..usePrivateKeyBytes(utf8.encode(keyPem));

  static Future<TlsCertificate> load(SecretStore store) async {
    final saved = await store.read('tls');
    if (saved != null) {
      final data = jsonDecode(saved) as Map<String, dynamic>;
      return TlsCertificate(data['cert'] as String, data['key'] as String);
    }
    final pair = CryptoUtils.generateEcKeyPair();
    final privateKey = pair.privateKey as ECPrivateKey;
    final publicKey = pair.publicKey as ECPublicKey;
    final csr = X509Utils.generateEccCsrPem(
      {'CN': 'DOT'},
      privateKey,
      publicKey,
    );
    final cert = X509Utils.generateSelfSignedCertificate(privateKey, csr, 3650);
    final key = CryptoUtils.encodeEcPrivateKeyToPem(privateKey);
    await store.write('tls', jsonEncode({'cert': cert, 'key': key}));
    return TlsCertificate(cert, key);
  }
}
