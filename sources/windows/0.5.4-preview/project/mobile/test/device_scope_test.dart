import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';

import '../lib/device_scope.dart';
import '../lib/saved_devices.dart';

class _MemoryStorage implements DeviceStorage {
  String value = '';
  bool failWrites = false;
  @override
  String read() => value;
  @override
  Future<void> write(String next) async {
    if (failWrites) throw const DeviceStorageException('write failed');
    value = next;
  }
}

DeviceProfileScope _scope(String server,
        {int keyByte = 1, String relay = ''}) =>
    DeviceProfileScope(
      server: server,
      relayServer: relay,
      publicKey: base64.encode(List.filled(32, keyByte)),
    );

void main() {
  final bundledCurrent = DeviceProfileScope(
    server: '64.176.235.139:24443',
    relayServer: '64.176.235.139:21117',
    publicKey: 'xeGt6mV0n19F0pGH81NoSJNOUKRWqmXmmwObSEzENEg=',
  );
  final bundledPrevious = previousBundledPortScope(bundledCurrent)!;
  final bundledDomain = DeviceProfileScope(
    server: 'videopmt.com:24443',
    relayServer: 'videopmt.com:21117',
    publicKey: bundledCurrent.publicKey,
  );
  test(
      'domain migration combines independent old scopes and preserves target names',
      () async {
    final storage = _MemoryStorage();
    final store =
        ScopedDeviceStore(storage: storage, legacyStorage: _MemoryStorage());
    for (final previous in previousBundledServiceScopes(bundledDomain)) {
      final repository = store.repository(previous)..load();
      await repository.add(SavedDevice(id: 'same-id', name: '旧名称'));
      await repository.add(SavedDevice(
          id: previous.server.endsWith(':443') ? 'from-443' : 'from-ip',
          name: '旧服务设备'));
    }
    await (store.repository(bundledDomain)..load())
        .add(SavedDevice(id: 'same-id', name: '目标现名'));
    final before = storage.value;
    storage.failWrites = true;
    await expectLater(store.migrateBundledPortDevices(bundledDomain),
        throwsA(isA<DeviceStorageException>()));
    expect(storage.value, before);
    storage.failWrites = false;
    expect((await store.migrateBundledPortDevices(bundledDomain)).imported, 2);
    final target = store.repository(bundledDomain)..load();
    expect(target.devices.first.name, '目标现名');
    expect(target.devices.map((device) => device.id),
        ['same-id', 'from-ip', 'from-443']);
    for (final device in target.devices) {
      await target.remove(device.id);
    }
    expect((await store.migrateBundledPortDevices(bundledDomain)).imported, 0);
    expect((store.repository(bundledDomain)..load()).devices, isEmpty);
    for (final previous in previousBundledServiceScopes(bundledDomain)) {
      expect((store.repository(previous)..load()).devices.length, 2);
    }
  });

  test('domain upgrade respects deletes after the earlier 443 port migration',
      () async {
    final storage = _MemoryStorage();
    final store =
        ScopedDeviceStore(storage: storage, legacyStorage: _MemoryStorage());
    final oldest = store.repository(bundledPrevious)..load();
    await oldest.add(SavedDevice(id: 'deleted-id', name: '已删除的旧设备'));
    await oldest.add(SavedDevice(id: 'kept-id', name: '保留的设备'));
    await store.migrateBundledPortDevices(bundledCurrent);
    await (store.repository(bundledCurrent)..load()).remove('deleted-id');
    expect((await store.migrateBundledPortDevices(bundledDomain)).imported, 1);
    final target = store.repository(bundledDomain)..load();
    expect(target.devices.single.id, 'kept-id');
    await target.remove('kept-id');
    final reopened =
        ScopedDeviceStore(storage: storage, legacyStorage: _MemoryStorage());
    expect(
        (await reopened.migrateBundledPortDevices(bundledDomain)).imported, 0);
    expect((reopened.repository(bundledDomain)..load()).devices, isEmpty);
    expect((reopened.repository(bundledPrevious)..load()).devices.length, 2);
  });
  test('bundled port list migration preserves both lists and only runs once',
      () async {
    final storage = _MemoryStorage();
    final store =
        ScopedDeviceStore(storage: storage, legacyStorage: _MemoryStorage());
    final old = store.repository(bundledPrevious)..load();
    await old.add(SavedDevice(id: 'same-id', name: '旧名称'));
    await old.add(SavedDevice(id: 'second-id', name: '保留的旧设备'));
    final current = store.repository(bundledCurrent)..load();
    await current.add(SavedDevice(id: 'same-id', name: '已有新名称'));
    final result = await store.migrateBundledPortDevices(bundledCurrent);
    expect(result.imported, 1);
    expect(result.retained, 1);
    final reloaded = store.repository(bundledCurrent)..load();
    expect(reloaded.devices.map((device) => device.name), ['已有新名称', '保留的旧设备']);
    expect((store.repository(bundledPrevious)..load()).devices.length, 2);
    await reloaded.remove('second-id');
    await reloaded.remove('same-id');
    final reopened =
        ScopedDeviceStore(storage: storage, legacyStorage: _MemoryStorage());
    expect(
        (await reopened.migrateBundledPortDevices(bundledCurrent)).imported, 0);
    expect((reopened.repository(bundledCurrent)..load()).devices, isEmpty);
    expect((reopened.repository(bundledPrevious)..load()).devices.length, 2);
  });

  test('failed bundled list migration preserves source and is retryable',
      () async {
    final storage = _MemoryStorage();
    final store =
        ScopedDeviceStore(storage: storage, legacyStorage: _MemoryStorage());
    await (store.repository(bundledPrevious)..load())
        .add(SavedDevice(id: 'old-id', name: '旧设备'));
    final original = storage.value;
    storage.failWrites = true;
    await expectLater(store.migrateBundledPortDevices(bundledCurrent),
        throwsA(isA<DeviceStorageException>()));
    expect(storage.value, original);
    expect((store.repository(bundledCurrent)..load()).devices, isEmpty);
    storage.failWrites = false;
    expect((await store.migrateBundledPortDevices(bundledCurrent)).imported, 1);
    expect(
        (store.repository(bundledCurrent)..load()).devices.single.id, 'old-id');
  });

  test('custom and LAN lists are outside bundled port migration', () async {
    final storage = _MemoryStorage();
    final store =
        ScopedDeviceStore(storage: storage, legacyStorage: _MemoryStorage());
    final custom = _scope('custom.example:21116');
    await (store.repository(custom)..load())
        .add(SavedDevice(id: 'custom-id', name: '自定义设备'));
    final original = storage.value;
    expect((await store.migrateBundledPortDevices(custom)).imported, 0);
    expect((await store.migrateBundledPortDevices(bundledCurrent)).imported, 0);
    expect(storage.value, original);
  });

  test('public profile accepts only the complete public connection schema', () {
    final expected =
        _scope('192.168.2.102:21116', relay: '192.168.2.102:21117');
    final profile = {
      'schemaVersion': 1,
      'idServer': expected.server,
      'relayServer': expected.relayServer,
      'publicKey': expected.publicKey,
    };
    final actual =
        DeviceProfileScope.fromPublicProfileJson(jsonEncode(profile));
    expect(actual.server, expected.server);
    expect(actual.relayServer, expected.relayServer);
    expect(actual.publicKey, expected.publicKey);
    expect(actual.fingerprint, expected.fingerprint);

    expect(
        () => DeviceProfileScope.fromPublicProfileJson(
            jsonEncode({...profile, 'password': 'not-a-public-field'})),
        throwsA(isA<DeviceValidationException>()));
    for (final field in profile.keys) {
      final incomplete = Map<String, Object>.of(profile)..remove(field);
      expect(
          () =>
              DeviceProfileScope.fromPublicProfileJson(jsonEncode(incomplete)),
          throwsA(isA<DeviceValidationException>()),
          reason: 'Missing public field $field must be rejected');
    }
    for (final field in ['idServer', 'relayServer', 'publicKey']) {
      for (final invalidType in [
        null,
        42,
        true,
        ['unexpected']
      ]) {
        expect(
            () => DeviceProfileScope.fromPublicProfileJson(
                jsonEncode({...profile, field: invalidType})),
            throwsA(isA<DeviceValidationException>()),
            reason: '$field must be a string');
      }
    }
    for (final invalidVersion in [null, '1', true, 1.0, 2]) {
      expect(
          () => DeviceProfileScope.fromPublicProfileJson(
              jsonEncode({...profile, 'schemaVersion': invalidVersion})),
          throwsA(isA<DeviceValidationException>()),
          reason: 'schemaVersion must be integer 1');
    }
    for (final malformed in ['{broken', '[]', 'null']) {
      expect(() => DeviceProfileScope.fromPublicProfileJson(malformed),
          throwsA(isA<DeviceValidationException>()));
    }
  });

  test('public profile rejects invalid keys without exposing their value', () {
    for (final invalidKey in [
      'bad-key-content!',
      base64.encode([0])
    ]) {
      expect(
          () => DeviceProfileScope.fromPublicProfileJson(jsonEncode({
                'schemaVersion': 1,
                'idServer': '192.168.2.102:21116',
                'relayServer': '192.168.2.102:21117',
                'publicKey': invalidKey,
              })),
          throwsA(isA<DeviceValidationException>()
              .having((error) => error.message, 'specific key error',
                  '服务器公钥（Key）不完整或格式不正确，请粘贴完整公钥')
              .having((error) => error.message, 'no submitted key value',
                  isNot(contains(invalidKey)))));
    }
  });

  test('scope binds normalized public addresses and decoded public key', () {
    final first = _scope(' Server-A.example ', relay: 'Relay.example');
    final same = DeviceProfileScope(
        server: 'server-a.example',
        relayServer: 'relay.example',
        publicKey: base64Url.encode(List.filled(32, 1)).replaceAll('=', ''));
    expect(same.fingerprint, first.fingerprint);
    final fromOptions = DeviceProfileScope.fromOptionsJson(jsonEncode({
      'custom-rendezvous-server': 'SERVER-A.example',
      'relay-server': 'relay.example',
      'key': first.publicKey,
      'password': 'never-store-this-secret',
    }));
    expect(fromOptions.fingerprint, first.fingerprint);
    expect(
        utf8.decode(
            base64Url.decode(base64Url.normalize(fromOptions.fingerprint))),
        isNot(contains('never-store-this-secret')));
    expect(() => DeviceProfileScope.fromOptionsJson('{}'),
        throwsA(isA<DeviceValidationException>()));
    expect(() => DeviceProfileScope.fromOptionsJson('{broken'),
        throwsA(isA<DeviceValidationException>()));
    for (final other in [
      _scope('server-b.example', relay: 'relay.example'),
      _scope('server-a.example', keyByte: 2, relay: 'relay.example'),
      _scope('server-a.example', relay: 'other.example')
    ]) {
      expect(other.fingerprint, isNot(first.fingerprint));
      expect(() => requireCurrentDeviceScope(first, other),
          throwsA(isA<DeviceValidationException>()));
    }
    expect(() => requireCurrentDeviceScope(first, same), returnsNormally);
  });

  test('same device ID stays isolated across servers, key rotation, and reload',
      () async {
    final storage = _MemoryStorage();
    final legacy = _MemoryStorage();
    final store = ScopedDeviceStore(storage: storage, legacyStorage: legacy);
    final a = _scope('server-a.example');
    final b = _scope('server-b.example');
    final rotated = _scope('server-a.example', keyByte: 2);
    final aRepository = store.repository(a)..load();
    await aRepository.add(SavedDevice(id: 'same-id', name: '服务 A 设备'));
    final bRepository = store.repository(b)..load();
    expect(bRepository.devices, isEmpty);
    await bRepository.add(SavedDevice(id: 'same-id', name: '服务 B 设备'));
    expect((store.repository(rotated)..load()).devices, isEmpty);
    await aRepository.update(
        'same-id', SavedDevice(id: 'same-id', name: 'A 修改后的名称'));
    final reloaded = ScopedDeviceStore(storage: storage, legacyStorage: legacy);
    expect((reloaded.repository(a)..load()).devices.single.name, 'A 修改后的名称');
    expect((reloaded.repository(b)..load()).devices.single.name, '服务 B 设备');
    expect((reloaded.repository(rotated)..load()).devices, isEmpty);
  });

  test(
      'old schema stays untouched until explicit one-time import into chosen scope',
      () async {
    final legacy = _MemoryStorage();
    final old = DeviceRepository(legacy)..load();
    await old.add(SavedDevice(id: 'old-device', name: '旧名称'));
    await old.add(SavedDevice(id: 'second-old', name: '另一台'));
    final original = legacy.value;
    final storage = _MemoryStorage();
    final store = ScopedDeviceStore(storage: storage, legacyStorage: legacy);
    final a = _scope('server-a.example');
    final b = _scope('server-b.example');
    final aRepository = store.repository(a)..load();
    expect(aRepository.devices, isEmpty);
    expect(store.pendingLegacyDevices().length, 2);
    expect(storage.value, isEmpty);
    expect(legacy.value, original);
    await aRepository.add(SavedDevice(id: 'old-device', name: '已经编辑的新名称'));
    final result = await store.importLegacy(a);
    expect(result.imported, 1);
    expect(result.retained, 1);
    expect((store.repository(a)..load()).devices.first.name, '已经编辑的新名称');
    expect((store.repository(b)..load()).devices, isEmpty);
    expect(store.pendingLegacyDevices(), isEmpty);
    await expectLater(
        store.importLegacy(b), throwsA(isA<DeviceValidationException>()));
    expect(legacy.value, original);
    expect((DeviceRepository(legacy)..load()).devices.first.name, '旧名称');
  });

  test(
      'failed import keeps old file and migration pending without partial changes',
      () async {
    final legacy = _MemoryStorage();
    await (DeviceRepository(legacy)..load())
        .add(SavedDevice(id: 'old-device', name: '旧设备'));
    final original = legacy.value;
    final storage = _MemoryStorage()..failWrites = true;
    final store = ScopedDeviceStore(storage: storage, legacyStorage: legacy);
    final a = _scope('server-a.example');
    await expectLater(
        store.importLegacy(a), throwsA(isA<DeviceStorageException>()));
    expect(storage.value, isEmpty);
    expect(legacy.value, original);
    expect(store.pendingLegacyDevices().single.id, 'old-device');
    expect((store.repository(a)..load()).devices, isEmpty);
  });

  test('corrupt scope records cannot be silently replaced by an empty list',
      () async {
    final a = _scope('server-a.example');
    final storage = _MemoryStorage();
    final store =
        ScopedDeviceStore(storage: storage, legacyStorage: _MemoryStorage());
    final repository = store.repository(a)..load();
    await repository.add(SavedDevice(id: 'one-device', name: '已保存设备'));
    storage.value = jsonEncode({
      'schema_version': 2,
      'scopes': {a.fingerprint: null}
    });
    final original = storage.value;
    expect(() => store.repository(a).load(),
        throwsA(isA<DeviceStorageException>()));
    await expectLater(repository.remove('one-device'),
        throwsA(isA<DeviceStorageException>()));
    expect(repository.devices.single.id, 'one-device');
    expect(storage.value, original);
  });
}
