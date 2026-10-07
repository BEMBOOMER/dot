import 'dart:async';
import 'dart:io';

import 'tls_cert.dart';

class HostServer {
  HttpServer? _server;
  int get port => _server!.port;
  Future<void> start(
    TlsCertificate certificate,
    void Function(WebSocket) onConnection, {
    String bindAddress = '0.0.0.0',
    int preferredPort = 48620,
  }) async {
    try {
      _server = await HttpServer.bindSecure(
        bindAddress,
        preferredPort,
        certificate.context,
      );
    } on SocketException {
      _server = await HttpServer.bindSecure(
        bindAddress,
        0,
        certificate.context,
      );
    }
    _server!.listen((request) async {
      if (request.uri.path != '/sync' ||
          !WebSocketTransformer.isUpgradeRequest(request)) {
        request.response.statusCode = HttpStatus.notFound;
        await request.response.close();
        return;
      }
      try {
        onConnection(await WebSocketTransformer.upgrade(request));
      } catch (_) {
        await request.response.close();
      }
    });
  }

  Future<void> stop() async {
    await _server?.close(force: true);
    _server = null;
  }
}
