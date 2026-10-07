import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';

import '../lib/private_connection_profile.dart';
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

void main() {
  test(
      'connection history survives reload, deduplicates and preserves custom names',
      () async {
    final storage = _MemoryStorage();
    final repository = DeviceRepository(storage)..load();
    await repository.rememberConnection('123 456 789');
    expect((DeviceRepository(storage)..load()).devices.single.id, '123456789');
    await repository.update(
        '123456789', SavedDevice(id: '123456789', name: '自定义名称'));
    await repository.rememberConnection('123456789');
    expect(repository.devices.single.name, '自定义名称');
    expect(repository.devices.length, 1);
    storage.failWrites = true;
    await expectLater(repository.rememberConnection('987654321'),
        throwsA(isA<DeviceStorageException>()));
    expect(repository.devices.length, 1);
  });
  test('private connection requires a configured server and 32-byte public key',
      () {
    final key = base64.encode(List.filled(32, 0));
    expect(
        () => requirePrivateConnectionService(
            server: 'private.example', publicKey: key),
        returnsNormally);
    for (final profile in [
      ('  ', key, '尚未填写 ID 服务器，请配置连接服务'),
      ('private.example', '  ', '尚未填写服务器公钥（Key），请配置连接服务'),
      ('private.example', 'invalid', '服务器公钥（Key）不完整或格式不正确，请粘贴完整公钥'),
      ('private.example', base64.encode([0]), '服务器公钥（Key）不完整或格式不正确，请粘贴完整公钥')
    ]) {
      expect(
          () => requirePrivateConnectionService(
              server: profile.$1, publicKey: profile.$2),
          throwsA(isA<DeviceValidationException>().having(
              (error) => error.message, 'specific profile error', profile.$3)));
    }
    const submittedBadKey = 'bad-key-content!';
    expect(
        () => requirePrivateConnectionService(
            server: 'private.example', publicKey: submittedBadKey),
        throwsA(isA<DeviceValidationException>().having(
            (error) => error.message,
            'no submitted key value',
            isNot(contains(submittedBadKey)))));
    for (final id in ['123456789', 'device.abc', '我的设备']) {
      expect(() => requirePrivateDeviceTarget(id), returnsNormally);
    }
    for (final address in [
      '192.168.2.102',
      '[::1]',
      '192.168.2.102:21118',
      'device@other-server'
    ]) {
      expect(() => requirePrivateDeviceTarget(address),
          throwsA(isA<DeviceValidationException>()));
    }
  });
  test('empty initial list and named device changes survive reload', () async {
    final storage = _MemoryStorage();
    final repository = DeviceRepository(storage)..load();
    expect(repository.devices, isEmpty);
    await repository.add(SavedDevice(id: '123 456 789', name: '工作设备'));
    expect(repository.devices.single.id, '123456789');
    await repository.update(
        '123456789', SavedDevice(id: '987654321', name: '随身设备'));
    final reloaded = DeviceRepository(storage)..load();
    expect(reloaded.devices.single.name, '随身设备');
    expect(reloaded.devices.single.id, '987654321');
    await reloaded.remove('987654321');
    expect((DeviceRepository(storage)..load()).devices, isEmpty);
  });

  test('duplicate ID and failed save keep the previous records', () async {
    final storage = _MemoryStorage();
    final repository = DeviceRepository(storage)..load();
    await repository.add(SavedDevice(id: '123456789', name: '第一台'));
    await repository.add(SavedDevice(id: '987654321', name: '第二台'));
    final original = storage.value;
    await expectLater(
      repository.update(
          '987654321', SavedDevice(id: '123 456 789', name: '重复设备')),
      throwsA(isA<DeviceValidationException>()),
    );
    storage.failWrites = true;
    await expectLater(
        repository.remove('123456789'), throwsA(isA<DeviceStorageException>()));
    expect(repository.devices.length, 2);
    expect(storage.value, original);
  });

  test('invalid stored records are preserved and connection suffix is separate',
      () {
    final storage = _MemoryStorage()..value = '{bad json';
    expect(() => DeviceRepository(storage).load(),
        throwsA(isA<DeviceStorageException>()));
    expect(storage.value, '{bad json');
    final request = DeviceConnectionRequest.parse('123 456 789/r');
    expect(request.id, '123456789');
    expect(request.forceRelay, isTrue);
    expect(() => SavedDevice(id: '123456789/r', name: '设备'),
        throwsA(isA<DeviceValidationException>()));
    expect(DeviceConnectionRequest.parse('device-abc/r').id, 'device-abc');
    expect(DeviceConnectionRequest.parse('我的设备').id, '我的设备');
    expect(formatDeviceId('device123456'), 'device123456');
    expect(() => normalizeDeviceId('two words'),
        throwsA(isA<DeviceValidationException>()));
    expect(() => normalizeDeviceId(List.filled(85, '中').join()),
        throwsA(isA<DeviceValidationException>()));
  });
}
