import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import '../lib/saved_devices.dart';
import '../lib/xixi_device_screen.dart';

class _MemoryStorage implements DeviceStorage {
  String value = '';
  @override
  String read() => value;
  @override
  Future<void> write(String next) async => value = next;
}

void main() {
  testWidgets('successful submission automatically saves while rejected submission does not', (tester) async {
    final storage = _MemoryStorage();
    final repository = DeviceRepository(storage)..load();
    var reject = false;
    await tester.pumpWidget(MaterialApp(home: Scaffold(body: XixiDeviceScreen(
      repository: repository, onConnect: (_, __) async {
        if (reject) throw const DeviceValidationException('连接服务不匹配');
      }))));
    await tester.enterText(find.byKey(const Key('connect-id')), '123 456 789/r');
    await tester.testTextInput.receiveAction(TextInputAction.go);
    await tester.pumpAndSettle();
    expect(repository.devices.single.id, '123456789');
    expect((DeviceRepository(storage)..load()).devices.single.id, '123456789');
    reject = true;
    await tester.enterText(find.byKey(const Key('connect-id')), '987654321');
    await tester.testTextInput.receiveAction(TextInputAction.go);
    await tester.pumpAndSettle();
    expect(repository.devices.length, 1);
  });

  testWidgets('native grouped local ID displays and copies canonical digits',
      (tester) async {
    String? copied;
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform, (call) async {
      if (call.method == 'Clipboard.setData') {
        copied = (call.arguments as Map)['text'] as String;
      }
      return null;
    });
    addTearDown(() => tester.binding.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, null));
    await tester.pumpWidget(MaterialApp(
        home: Scaffold(body: XixiDeviceScreen(
      repository: DeviceRepository(_MemoryStorage())..load(),
      runtime: const XixiRuntimeSnapshot(localId: '6 024 681 301'),
      onConnect: (_, __) async {},
    ))));
    expect(find.text('6 024 681 301'), findsOneWidget);
    expect(find.text('正在读取…'), findsNothing);
    await tester.tap(find.byTooltip('复制本机 ID'));
    await tester.pump();
    expect(copied, '6024681301');
  });

  testWidgets(
      'unconfigured connection accepts an ID but blocks connection and device writes',
      (tester) async {
    final storage = _MemoryStorage();
    var configureOpened = false;
    var connected = false;
    await tester.pumpWidget(MaterialApp(
        home: Scaffold(
            body: XixiDeviceScreen(
      repository: DeviceRepository(storage),
      connectionConfigured: false,
      connectionMessage: '请先配置连接服务',
      onConfigureConnection: () => configureOpened = true,
      onConnect: (_, __) async => connected = true,
    ))));
    expect(find.text('连接设备'), findsOneWidget);
    expect(find.text('配置连接服务'), findsOneWidget);
    expect(
        tester
            .widget<TextFormField>(find.byKey(const Key('connect-id')))
            .enabled,
        isTrue);
    await tester.enterText(find.byKey(const Key('connect-id')), '123456789');
    expect(find.text('123456789'), findsOneWidget);
    await tester.testTextInput.receiveAction(TextInputAction.go);
    await tester.pump();
    expect(connected, isFalse);
    expect(configureOpened, isFalse);
    await tester.tap(find.byKey(const Key('connect-button')));
    await tester.pump();
    expect(configureOpened, isTrue);
    expect(connected, isFalse);
    await tester.ensureVisible(find.byKey(const Key('add-device')));
    expect(
        tester
            .widget<TextButton>(find.byKey(const Key('add-device')))
            .onPressed,
        isNull);
    expect(storage.value, isEmpty);
  });

  testWidgets(
      'valid connection remains usable when device storage is unavailable',
      (tester) async {
    final storage = _MemoryStorage();
    final connections = <(String, bool)>[];
    var retries = 0;
    const storageMessage = '设备列表暂时无法打开，仍可输入 ID 连接';
    await tester.pumpWidget(MaterialApp(
        home: Scaffold(
            body: XixiDeviceScreen(
      repository: DeviceRepository(storage),
      connectionConfigured: true,
      savedDevicesAvailable: false,
      savedDevicesMessage: storageMessage,
      onRetryDeviceStorage: () => retries++,
      onConnect: (id, relay) async => connections.add((id, relay)),
    ))));
    expect(
        tester
            .widget<TextFormField>(find.byKey(const Key('connect-id')))
            .enabled,
        isTrue);
    await tester.enterText(
        find.byKey(const Key('connect-id')), '123 456 789/r');
    await tester.testTextInput.receiveAction(TextInputAction.go);
    await tester.pumpAndSettle();
    expect(connections, [('123456789', true)]);
    await tester.enterText(find.byKey(const Key('connect-id')), 'device-abc');
    await tester.tap(find.byKey(const Key('connect-button')));
    await tester.pumpAndSettle();
    expect(connections, [('123456789', true), ('device-abc', false)]);
    await tester.ensureVisible(find.byKey(const Key('add-device')));
    await tester.pumpAndSettle();
    expect(
        tester
            .widget<TextButton>(find.byKey(const Key('add-device')))
            .onPressed,
        isNull);
    expect(find.text(storageMessage), findsOneWidget);
    await tester.ensureVisible(find.text('重新读取'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('重新读取'));
    await tester.pump();
    expect(retries, 1);
    expect(storage.value, isEmpty);
    expect(tester.takeException(), isNull);
  });

  testWidgets('connection shows specific private profile validation error',
      (tester) async {
    await tester.pumpWidget(MaterialApp(
        home: Scaffold(
            body: XixiDeviceScreen(
      repository: DeviceRepository(_MemoryStorage()),
      onConnect: (_, __) async =>
          throw const DeviceValidationException('尚未填写 ID 服务器，请配置连接服务'),
    ))));
    await tester.enterText(find.byKey(const Key('connect-id')), 'device-abc');
    await tester.tap(find.byKey(const Key('connect-button')));
    await tester.pump();
    expect(find.text('尚未填写 ID 服务器，请配置连接服务'), findsOneWidget);
  });
  testWidgets('input dispatches normalized real ID with relay intent',
      (tester) async {
    String? connected;
    bool? relay;
    await tester.pumpWidget(MaterialApp(
        home: Scaffold(
            body: XixiDeviceScreen(
      repository: DeviceRepository(_MemoryStorage()),
      onConnect: (id, forceRelay) async {
        connected = id;
        relay = forceRelay;
      },
    ))));
    expect(find.text('还没有添加设备'), findsOneWidget);
    expect(find.text('在线'), findsNothing);
    await tester.enterText(
        find.byKey(const Key('connect-id')), '123 456 789/r');
    await tester.tap(find.byKey(const Key('connect-button')));
    await tester.pumpAndSettle();
    expect(connected, '123456789');
    expect(relay, isTrue);
    await tester.enterText(find.byKey(const Key('connect-id')), '我的设备');
    await tester.tap(find.byKey(const Key('connect-button')));
    await tester.pumpAndSettle();
    expect(connected, '我的设备');
    expect(relay, isFalse);
  });

  testWidgets('add custom device then connect it from the list',
      (tester) async {
    String? connected;
    final storage = _MemoryStorage();
    await tester.pumpWidget(MaterialApp(
        home: Scaffold(
            body: XixiDeviceScreen(
      repository: DeviceRepository(storage),
      onConnect: (id, _) async => connected = id,
    ))));
    await tester.ensureVisible(find.byKey(const Key('add-device')));
    await tester.tap(find.byKey(const Key('add-device')));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('device-name')), '我的平板');
    await tester.enterText(find.byKey(const Key('device-id')), '123456789');
    await tester.tap(find.byKey(const Key('save-device')));
    await tester.pumpAndSettle();
    expect(find.text('我的平板'), findsOneWidget);
    expect((DeviceRepository(storage)..load()).devices.single.name, '我的平板');
    await tester.ensureVisible(find.byTooltip('连接 我的平板'));
    await tester.tap(find.byTooltip('连接 我的平板'));
    await tester.pumpAndSettle();
    expect(connected, '123456789');
    await tester.tap(find.byKey(const ValueKey('menu-123456789')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('编辑名称和 ID'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('device-name')), '自定义名称');
    await tester.enterText(find.byKey(const Key('device-id')), 'device-abc');
    await tester.tap(find.byKey(const Key('save-device')));
    await tester.pumpAndSettle();
    expect(find.text('自定义名称'), findsOneWidget);
    expect(find.text('我的平板'), findsNothing);
    expect((DeviceRepository(storage)..load()).devices.single.id, 'device-abc');
    await tester.ensureVisible(find.byKey(const ValueKey('menu-device-abc')));
    await tester.tap(find.byKey(const ValueKey('menu-device-abc')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('移除设备'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('移除'));
    await tester.pumpAndSettle();
    expect(find.text('还没有添加设备'), findsOneWidget);
    expect((DeviceRepository(storage)..load()).devices, isEmpty);
  });

  for (final scale in [2.0, 3.0]) {
    testWidgets(
        '320px layout supports ${scale}x text with saved device and editor',
        (tester) async {
      tester.view.physicalSize = const Size(320, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final repository = DeviceRepository(_MemoryStorage())..load();
      await repository
          .add(SavedDevice(id: 'device-abc', name: '这是我自己添加并且可以随时编辑名称的设备'));
      await tester.pumpWidget(MaterialApp(
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context)
              .copyWith(textScaler: TextScaler.linear(scale)),
          child: child!,
        ),
        home: Scaffold(
            body: XixiDeviceScreen(
          repository: repository,
          runtime: const XixiRuntimeSnapshot(
              localId: '123456789',
              connectionStatus: XixiConnectionStatus.unavailable,
              sharingStarted: false),
          onConnect: (_, __) async {},
          onShowSharing: () {},
          onOpenSettings: () {},
        )),
      ));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      await tester.scrollUntilVisible(
          find.byKey(const ValueKey('menu-device-abc')), 300,
          scrollable: find.byType(Scrollable).first);
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.byKey(const ValueKey('menu-device-abc')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('menu-device-abc')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('编辑名称和 ID'));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('device-name')), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  }
}
