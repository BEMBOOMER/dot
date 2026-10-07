import 'dart:async';
import 'dart:io';

import 'tls_cert.dart';

class ClientConnection {
  final WebSocket socket;
  final HttpClient client;
  ClientConnection(this.socket, this.client);
  static Future<ClientConnection> connect(
    String host,
    int port,
    String fingerprint,
  ) async {
    // No system roots: even a publicly trusted certificate must match the pin.
    final client = HttpClient(
      context: SecurityContext(withTrustedRoots: false),
    );
    client.connectionTimeout = const Duration(seconds: 10);
    client.badCertificateCallback = (certificate, _, _) =>
        acceptsFingerprint(certificate, fingerprint);
    try {
      final socket = await WebSocket.connect(
        Uri(scheme: 'wss', host: host, port: port, path: '/sync').toString(),
        customClient: client,
      ).timeout(const Duration(seconds: 10));
      return ClientConnection(socket, client);
    } catch (_) {
      client.close(force: true);
      rethrow;
    }
  }

  Future<void> close() async {
    await socket.close();
    client.close(force: true);
  }

  /// Manual pairing has no QR pin. Probe only to obtain a candidate, then
  /// authenticate it using a fresh challenge and the one-time manual secret.
  /// This socket is never used to send pairing credentials or item data.
  static Future<String> probeFingerprint(String host, int port) async {
    final socket = await SecureSocket.connect(
      host,
      port,
      context: SecurityContext(withTrustedRoots: false),
      onBadCertificate: (_) => true,
      timeout: const Duration(seconds: 10),
    );
    try {
      return certificateFingerprint(socket.peerCertificate!);
    } finally {
      socket.destroy();
    }
  }
}
