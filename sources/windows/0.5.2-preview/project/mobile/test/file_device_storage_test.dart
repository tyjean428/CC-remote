import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import '../lib/file_device_storage.dart';
import '../lib/saved_devices.dart';

void main() {
  late Directory fixture;

  setUp(() async {
    final root = Directory('test').absolute;
    fixture = Directory(
        '${root.path}${Platform.pathSeparator}.device-store-${DateTime.now().microsecondsSinceEpoch}');
    expect(fixture.absolute.parent.path, root.path);
    await fixture.create();
  });

  tearDown(() async {
    final root = Directory('test').absolute;
    expect(fixture.absolute.parent.path, root.path);
    if (fixture.existsSync()) await fixture.delete(recursive: true);
  });

  test('actual disk roundtrip persists edits and removal', () async {
    final file = File('${fixture.path}${Platform.pathSeparator}devices.json');
    final repository = DeviceRepository(FileDeviceStorage(file))..load();
    await repository.add(SavedDevice(id: 'device-abc', name: '第一台'));
    await repository.update('device-abc', SavedDevice(id: '我的设备', name: '新名称'));
    final reloaded = DeviceRepository(FileDeviceStorage(file))..load();
    expect(reloaded.devices.single.id, '我的设备');
    expect(reloaded.devices.single.name, '新名称');
    await reloaded.remove('我的设备');
    expect(
        (DeviceRepository(FileDeviceStorage(file))..load()).devices, isEmpty);
  });

  test('rename failure propagates without replacing existing contents',
      () async {
    final destination =
        Directory('${fixture.path}${Platform.pathSeparator}devices.json');
    await destination.create();
    final existing =
        File('${destination.path}${Platform.pathSeparator}keep.txt');
    await existing.writeAsString('original contents', flush: true);
    final storage = FileDeviceStorage(File(destination.path));
    expect(() => storage.read(), throwsA(isA<FileSystemException>()));
    await expectLater(
        storage.write('replacement'), throwsA(isA<FileSystemException>()));
    expect(await existing.readAsString(), 'original contents');
    expect(destination.existsSync(), isTrue);
  });
}
