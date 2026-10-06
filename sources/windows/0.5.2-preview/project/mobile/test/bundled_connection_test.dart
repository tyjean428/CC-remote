import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import '../lib/device_scope.dart';

void main() {
  final previous = DeviceProfileScope(
    server: '192.168.2.102:21116',
    relayServer: '192.168.2.102:21117',
    publicKey: base64.encode(List.filled(32, 1)),
  );
  bool migrate(Map<String, dynamic> options) =>
      shouldUseBundledConnection(jsonEncode(options), previous);

  test('first launch and known previous LAN migrate without device credentials', () {
    expect(migrate({}), isTrue);
    expect(migrate({
      'custom-rendezvous-server': '192.168.2.102',
      'relay-server': previous.relayServer,
      'key': previous.publicKey,
      'unrelated-option': 'preserved by native setOption',
    }), isTrue);
    expect(migrate({'custom-rendezvous-server': previous.server}), isTrue);
  });

  test('custom, partial, different-key and account service choices are preserved', () {
    for (final options in [
      {'custom-rendezvous-server': 'another.example'},
      {'relay-server': previous.relayServer},
      {'custom-rendezvous-server': previous.server, 'key': base64.encode(List.filled(32, 2))},
      {'custom-rendezvous-server': previous.server, 'relay-server': 'another.example'},
      {'api-server': 'https://account.example'},
      {'custom-rendezvous-server': 42},
    ]) {
      expect(migrate(options), isFalse);
    }
  });
}
