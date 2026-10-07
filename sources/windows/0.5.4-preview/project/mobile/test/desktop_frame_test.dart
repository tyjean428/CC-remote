import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import '../../desktop/lib/xixi_desktop_frame.dart';
import '../lib/xixi_device_screen.dart'
    show XixiRuntimeSnapshot, XixiConnectionStatus;
import '../../desktop/lib/xixi_desktop_device_screen.dart';
import '../lib/saved_devices.dart';
import '../../desktop/lib/xixi_desktop_sections.dart';

class _Storage implements DeviceStorage {
  String value = '';
  @override
  String read() => value;
  @override
  Future<void> write(String next) async {
    value = next;
  }
}

void main() {
  testWidgets('desktop workbench uses width, search and keyboard connection',
      (tester) async {
    tester.view.physicalSize = const Size(1100, 760);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final repository = DeviceRepository(_Storage())..load();
    await repository.add(SavedDevice(name: '测试设备 Alpha', id: '987654321'));
    await repository.add(SavedDevice(name: '测试设备 Beta', id: '876543210'));
    String? connected;
    bool? relay;
    await tester.pumpWidget(MaterialApp(
        theme: xixiSilverTheme(ThemeData()),
        home: XixiDesktopFrame(
            selected: 0,
            onSelected: (_) {},
            body: XixiDesktopDeviceScreen(
                repository: repository,
                runtime: const XixiRuntimeSnapshot(localId: '123456789'),
                onConnect: (id, forceRelay) async {
                  connected = id;
                  relay = forceRelay;
                }))));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    final connection = tester.getRect(find.text('连接远程设备'));
    final local = tester.getRect(find.text('允许连接此电脑'));
    expect(local.left, greaterThan(connection.right));
    expect((local.top - connection.top).abs(), lessThan(10));
    expect(tester.getRect(find.byKey(const Key('search-devices'))).top,
        greaterThan(local.bottom));
    await tester.enterText(find.byKey(const Key('search-devices')), 'Beta');
    await tester.pumpAndSettle();
    expect(find.text('测试设备 Alpha'), findsNothing);
    expect(find.text('测试设备 Beta'), findsOneWidget);
    await tester.tap(find.text('连接').last);
    await tester.pumpAndSettle();
    expect(connected, '876543210');
    expect(relay, false);
    await tester.enterText(
        find.byKey(const Key('connect-id')), '765 432 109/r');
    await tester.testTextInput.receiveAction(TextInputAction.go);
    await tester.pumpAndSettle();
    expect(connected, '765432109');
    expect(relay, true);
    expect(repository.devices.last.id, '765432109');
    expect(repository.devices.length, 3);
    expect(tester.takeException(), isNull);
  });
  for (final size in [
    const Size(1100, 760),
    const Size(720, 550),
    const Size(520, 550)
  ]) {
    for (final scale in [1.0, 1.5]) {
      testWidgets('desktop navigation and device editor fit $size at $scale',
          (tester) async {
        tester.view.physicalSize = size;
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        final repository = DeviceRepository(_Storage())..load();
        var selected = 0;
        await tester.pumpWidget(MaterialApp(
            theme: xixiSilverTheme(ThemeData()),
            builder: (context, child) => MediaQuery(
                data: MediaQuery.of(context)
                    .copyWith(textScaler: TextScaler.linear(scale)),
                child: child!),
            home: StatefulBuilder(
                builder: (context, setState) => XixiDesktopFrame(
                    selected: selected,
                    onSelected: (value) => setState(() => selected = value),
                    body: XixiDesktopDeviceScreen(
                        repository: repository,
                        onConnect: (_, __) async {},
                        runtime:
                            const XixiRuntimeSnapshot(localId: '123456789'),
                        onShowSharing: () => setState(() => selected = 1),
                        onOpenSettings: () => setState(() => selected = 2))))));
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        expect(find.byType(NavigationBar), findsNothing);
        await tester.tap(find.byKey(const Key('desktop-nav-2')));
        await tester.pumpAndSettle();
        expect(selected, 2);
        expect(tester.takeException(), isNull);
        await tester.scrollUntilVisible(
            find.byKey(const Key('add-device')), 300,
            scrollable: find.byType(Scrollable).first);
        await tester.tap(find.byKey(const Key('add-device')));
        await tester.pumpAndSettle();
        expect(find.byKey(const Key('device-name')), findsOneWidget);
        expect(tester.takeException(), isNull);
        final dialogRect = tester.getRect(find.byType(AlertDialog));
        expect(dialogRect.left, greaterThanOrEqualTo(0));
        expect(dialogRect.right, lessThanOrEqualTo(size.width));
        expect(dialogRect.top, greaterThanOrEqualTo(0));
        expect(dialogRect.bottom, lessThanOrEqualTo(size.height));
        await tester.enterText(find.byKey(const Key('device-name')), '自定义设备');
        await tester.enterText(find.byKey(const Key('device-id')), '987654321');
        await tester.ensureVisible(find.byKey(const Key('save-device')));
        await tester.tap(find.byKey(const Key('save-device')));
        await tester.pumpAndSettle();
        expect(repository.devices.single.id, '987654321');
        expect(tester.takeException(), isNull);
      });
    }
  }
  for (final size in [const Size(1100, 760), const Size(520, 550)]) {
    for (final scale in [1.0, 1.5]) {
      testWidgets('share/settings rows align and actions work $size $scale', (tester) async {
        tester.view.physicalSize = size;
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        var actions = 0;
        await tester.pumpWidget(MaterialApp(theme: xixiSilverTheme(ThemeData()),
          builder: (context, child) => MediaQuery(data: MediaQuery.of(context).copyWith(
            textScaler: TextScaler.linear(scale)), child: child!),
          home: XixiDesktopFrame(selected: 1, onSelected: (_) {},
            body: XixiDesktopSectionPage(title: '本机共享', description: '共享与授权', sections: [
              XixiDesktopSection(title: '设备与接入', rows: [
                XixiDesktopSettingRow(label: '本机 ID', value: '123456789', prominent: true,
                  action: XixiDesktopAction(key: const Key('action-a'), label: '复制本机 ID',
                    icon: Icons.copy_outlined, onPressed: () => actions++)),
                XixiDesktopSettingRow(label: '固定密码', value: '由你设置并保存在本机',
                  hint: '只向你信任的控制端提供密码。',
                  action: XixiDesktopAction(key: const Key('action-b'), label: '设置固定密码',
                    icon: Icons.lock_outline, onPressed: () => actions++)),
              ]),
            ]))));
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        final first = tester.getRect(find.byKey(const Key('action-a')));
        final second = tester.getRect(find.byKey(const Key('action-b')));
        expect(first.width, second.width);
        expect(first.height, second.height);
        expect(first.left, second.left);
        for (final key in ['action-a', 'action-b']) {
          await tester.ensureVisible(find.byKey(Key(key)));
          await tester.tap(find.byKey(Key(key)));
          await tester.pumpAndSettle();
        }
        expect(actions, 2);
        expect(tester.takeException(), isNull);
      });
    }
  }
  testWidgets('render desktop selected silver theme from real widgets',
      (tester) async {
    tester.view.physicalSize = const Size(1100, 760);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final key = GlobalKey();
    final repository = DeviceRepository(_Storage())..load();
    await tester.runAsync(() async {
      final textFont = FontLoader('XiXiPreview')
        ..addFont(Future.value(ByteData.sublistView(
            await File('C:/Windows/Fonts/msyh.ttc').readAsBytes())));
      final icons = FontLoader('MaterialIcons')
        ..addFont(Future.value(ByteData.sublistView(await File(
                '../tools/flutter-sdk/bin/cache/artifacts/material_fonts/MaterialIcons-Regular.otf')
            .readAsBytes())));
      await textFont.load();
      await icons.load();
    });
    await tester.pumpWidget(MaterialApp(
        theme: xixiSilverTheme(ThemeData(fontFamily: 'XiXiPreview')),
        home: RepaintBoundary(
            key: key,
            child: XixiDesktopFrame(
                selected: 0,
                onSelected: (_) {},
                body: XixiDesktopDeviceScreen(
                    repository: repository,
                    runtime: const XixiRuntimeSnapshot(
                        localId: '123456789',
                        connectionStatus: XixiConnectionStatus.ready),
                    onConnect: (_, __) async {},
                    onShowSharing: () {},
                    onOpenSettings: () {})))));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    await tester.runAsync(() async {
      final boundary =
          key.currentContext!.findRenderObject() as RenderRepaintBoundary;
      final image = await boundary.toImage();
      final png = await image.toByteData(format: ui.ImageByteFormat.png);
      final file =
          File('../tools/desktop-build/previews/desktop-silver-widgets.png');
      await file.parent.create(recursive: true);
      await file.writeAsBytes(png!.buffer.asUint8List());
      image.dispose();
    });
  });
}
