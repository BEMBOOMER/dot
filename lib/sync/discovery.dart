import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:nsd/nsd.dart' as nsd;

class HostAddress {
  final String deviceId;
  final String host;
  final int port;
  HostAddress(this.deviceId, this.host, this.port);
}

abstract interface class LanDiscovery {
  Future<void> advertise(String id, String name, int port);
  Future<void> discover(void Function(HostAddress) onHost);
  Future<void> stop();
}

class BonjourDiscovery implements LanDiscovery {
  nsd.Registration? _registration;
  nsd.Discovery? _discovery;
  @override
  Future<void> advertise(String id, String name, int port) async {
    _registration = await nsd.register(
      nsd.Service(
        name: name,
        type: '_dotlink._tcp',
        port: port,
        txt: {'id': Uint8List.fromList(utf8.encode(id))},
      ),
    );
  }

  @override
  Future<void> discover(void Function(HostAddress) onHost) async {
    final discovery = await nsd.startDiscovery(
      '_dotlink._tcp',
      ipLookupType: nsd.IpLookupType.v4,
    );
    _discovery = discovery;
    void update() {
      for (final service in discovery.services) {
        final bytes = service.txt?['id'];
        final host = service.addresses?.firstOrNull?.address ?? service.host;
        if (bytes != null && host != null && service.port != null) {
          onHost(HostAddress(utf8.decode(bytes), host, service.port!));
        }
      }
    }

    discovery.addListener(update);
    update();
  }

  @override
  Future<void> stop() async {
    final registration = _registration;
    final discovery = _discovery;
    _registration = null;
    _discovery = null;
    if (registration != null) await nsd.unregister(registration);
    if (discovery != null) await nsd.stopDiscovery(discovery);
  }
}

class NoDiscovery implements LanDiscovery {
  @override
  Future<void> advertise(String id, String name, int port) async {}
  @override
  Future<void> discover(void Function(HostAddress) onHost) async {}
  @override
  Future<void> stop() async {}
}

Future<String?> lanIPv4() async {
  final interfaces = await NetworkInterface.list(
    type: InternetAddressType.IPv4,
  );
  interfaces.sort((a, b) {
    bool preferred(String name) => name == 'en0' || name.startsWith('wlan');
    return (preferred(b.name) ? 1 : 0) - (preferred(a.name) ? 1 : 0);
  });
  for (final interface in interfaces) {
    for (final address in interface.addresses) {
      if (!address.isLoopback && !address.address.startsWith('169.254.')) {
        return address.address;
      }
    }
  }
  return null;
}
