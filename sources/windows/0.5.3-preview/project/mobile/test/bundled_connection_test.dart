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

  final currentDefault = DeviceProfileScope(
    server: '64.176.235.139:24443',
    relayServer: '64.176.235.139:21117',
    publicKey: 'xeGt6mV0n19F0pGH81NoSJNOUKRWqmXmmwObSEzENEg=',
  );
  final oldDefault = previousBundledPortScope(currentDefault)!;
  final oldOptions = <String, dynamic>{
    'custom-rendezvous-server': oldDefault.server,
    'relay-server': oldDefault.relayServer,
    'key': oldDefault.publicKey,
    'api-server': '',
  };
  bool migrateDefault(Map<String, dynamic> options) =>
      shouldUseBundledConnection(jsonEncode(options), previous,
          currentDefault: currentDefault);

  test(
      'exact previous bundled 443 migrates but current native port stays saved',
      () {
    expect(migrateDefault(oldOptions), isTrue);
    expect(migrateDefault({}), isTrue);
    expect(
        migrateDefault({
          ...oldOptions,
          'custom-rendezvous-server': currentDefault.server,
        }),
        isFalse);
    expect(
        migrateDefault({
          ...oldOptions,
          'password': 'unchanged-device-credential',
        }),
        isTrue);
    expect(
        shouldUseBundledConnection('{bad json', previous,
            currentDefault: currentDefault),
        isFalse);
  });

  test('custom and partial public service profiles never migrate', () {
    for (final changes in [
      {'custom-rendezvous-server': '64.176.235.138:443'},
      {'custom-rendezvous-server': '64.176.235.139:444'},
      {'relay-server': ''},
      {'relay-server': '64.176.235.138:21117'},
      {'key': ''},
      {'key': base64.encode(List.filled(32, 2))},
      {'api-server': 'https://account.example'},
      {'custom-rendezvous-server': 42},
      {'relay-server': false},
      {'key': 42},
    ]) {
      expect(migrateDefault({...oldOptions, ...changes}), isFalse);
    }
    expect(migrateDefault({'custom-rendezvous-server': oldDefault.server}),
        isFalse);
    expect(
        previousBundledPortScope(DeviceProfileScope(
          server: '64.176.235.138:21116',
          relayServer: currentDefault.relayServer,
          publicKey: currentDefault.publicKey,
        )),
        isNull);
  });

  test('first launch and known previous LAN migrate without device credentials',
      () {
    expect(migrate({}), isTrue);
    expect(
        migrate({
          'custom-rendezvous-server': '192.168.2.102',
          'relay-server': previous.relayServer,
          'key': previous.publicKey,
          'unrelated-option': 'preserved by native setOption',
        }),
        isTrue);
    expect(migrate({'custom-rendezvous-server': previous.server}), isTrue);
  });

  test(
      'custom, partial, different-key and account service choices are preserved',
      () {
    for (final options in [
      {'custom-rendezvous-server': 'another.example'},
      {'relay-server': previous.relayServer},
      {
        'custom-rendezvous-server': previous.server,
        'key': base64.encode(List.filled(32, 2))
      },
      {
        'custom-rendezvous-server': previous.server,
        'relay-server': 'another.example'
      },
      {'api-server': 'https://account.example'},
      {'custom-rendezvous-server': 42},
    ]) {
      expect(migrate(options), isFalse);
    }
  });
}
