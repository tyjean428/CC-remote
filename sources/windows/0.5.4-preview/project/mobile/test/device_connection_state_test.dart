import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';

import '../lib/device_connection_state.dart';
import '../lib/device_scope.dart';
import '../lib/saved_devices.dart';

class _MemoryStorage implements DeviceStorage {
  String value = '';
  bool failReads = false;
  int reads = 0;

  @override
  String read() {
    reads++;
    if (failReads) throw StateError('private-storage-path');
    return value;
  }

  @override
  Future<void> write(String value) async => this.value = value;
}

DeviceProfileScope _scope(String server) => DeviceProfileScope(
    server: server,
    relayServer: '',
    publicKey: base64.encode(List.filled(32, 1)));

void main() {
  test('valid profile can connect with an empty list or unavailable storage',
      () {
    final state = DeviceConnectionState();
    final profile = _scope('server.example');
    state.refresh(
        readScope: () => profile,
        openRepository: (_) => DeviceRepository(_MemoryStorage()));
    expect(state.canConnect, isTrue);
    expect(state.repository!.devices, isEmpty);
    expect(state.profileError, isNull);
    expect(state.storageError, isNull);

    state.refresh(
        readScope: () => profile,
        openRepository: (_) => throw StateError('private-directory-path'),
        forceReload: true);
    expect(state.canConnect, isTrue);
    expect(state.scope!.fingerprint, profile.fingerprint);
    expect(state.repository, isNull);
    expect(state.profileError, isNull);
    expect(state.storageError, '设备列表暂时无法读取，原记录已保留');
    expect(state.storageError, isNot(contains('private-directory-path')));
  });

  test('storage recovery restores the list and force reload observes edits',
      () async {
    final state = DeviceConnectionState();
    final profile = _scope('server.example');
    final storage = _MemoryStorage()..failReads = true;
    void refresh({bool forceReload = false}) => state.refresh(
        readScope: () => profile,
        openRepository: (_) => DeviceRepository(storage),
        forceReload: forceReload);
    refresh();
    expect(state.canConnect, isTrue);
    expect(state.repository, isNull);
    expect(state.storageError, isNotNull);
    storage.failReads = false;
    final fixture = DeviceRepository(storage)..load();
    await fixture.add(SavedDevice(id: 'first-device', name: '已保存设备'));
    refresh();
    expect(state.repository!.devices.single.name, '已保存设备');
    expect(state.storageError, isNull);
    final readsAfterRecovery = storage.reads;
    refresh();
    expect(storage.reads, readsAfterRecovery);
    await fixture.add(SavedDevice(id: 'second-device', name: '后来添加设备'));
    refresh(forceReload: true);
    expect(state.repository!.devices.length, 2);
  });

  test('a changed service never retains the previous service list', () async {
    final a = _scope('a.example');
    final b = _scope('b.example');
    final aStorage = _MemoryStorage();
    final bStorage = _MemoryStorage();
    await (DeviceRepository(aStorage)..load())
        .add(SavedDevice(id: 'same-id', name: 'A 服务设备'));
    await (DeviceRepository(bStorage)..load())
        .add(SavedDevice(id: 'same-id', name: 'B 服务设备'));
    var current = a;
    final state = DeviceConnectionState();
    void refresh() => state.refresh(
        readScope: () => current,
        openRepository: (scope) => DeviceRepository(
            scope.fingerprint == a.fingerprint ? aStorage : bStorage));
    refresh();
    expect(state.repository!.devices.single.name, 'A 服务设备');
    current = b;
    bStorage.failReads = true;
    refresh();
    expect(state.canConnect, isTrue);
    expect(state.scope!.fingerprint, b.fingerprint);
    expect(state.repository, isNull);
    bStorage.failReads = false;
    refresh();
    expect(state.repository!.devices.single.name, 'B 服务设备');
  });

  test('fresh invalid profiles block connection and clear a previous list', () {
    final state = DeviceConnectionState();
    final storage = _MemoryStorage();
    state.refresh(
        readScope: () => _scope('server.example'),
        openRepository: (_) => DeviceRepository(storage));
    expect(state.canConnect, isTrue);
    var repositoryOpened = false;
    state.refresh(
        readScope: () => DeviceProfileScope.fromOptionsJson('{}'),
        openRepository: (_) {
          repositoryOpened = true;
          return DeviceRepository(storage);
        });
    expect(state.canConnect, isFalse);
    expect(state.scope, isNull);
    expect(state.repository, isNull);
    expect(state.profileError, '尚未填写 ID 服务器，请配置连接服务');
    expect(state.storageError, isNull);
    expect(repositoryOpened, isFalse);
  });

  test('unexpected native read failures return a safe message', () {
    final state = DeviceConnectionState();
    state.refresh(
        readScope: () => _scope('server.example'),
        openRepository: (_) => DeviceRepository(_MemoryStorage()));
    state.refresh(
        readScope: () => throw StateError('private-native-details'),
        openRepository: (_) => DeviceRepository(_MemoryStorage()));
    expect(state.canConnect, isFalse);
    expect(state.repository, isNull);
    expect(state.profileError, '连接服务配置暂时无法读取');
    expect(state.profileError, isNot(contains('private-native-details')));
  });
}
