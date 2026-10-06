import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../lib/device_scope.dart';
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
  testWidgets(
      'switching service blocks old request, clears input and restores original list on return',
      (tester) async {
    final key = base64.encode(List.filled(32, 1));
    final a = DeviceProfileScope(
        server: 'server-a.example', relayServer: '', publicKey: key);
    final b = DeviceProfileScope(
        server: 'server-b.example', relayServer: '', publicKey: key);
    final store = ScopedDeviceStore(
        storage: _MemoryStorage(), legacyStorage: _MemoryStorage());
    await (store.repository(a)..load())
        .add(SavedDevice(id: 'old-device', name: '服务 A 的设备'));
    var current = a;
    var connectionCalls = 0;

    Widget screen(DeviceProfileScope displayed) => MaterialApp(
            home: Scaffold(
                body: XixiDeviceScreen(
          key: ValueKey(displayed.fingerprint),
          repository: store.repository(displayed),
          onConnect: (_, __) async {
            requireCurrentDeviceScope(displayed, current);
            connectionCalls++;
          },
        )));

    await tester.pumpWidget(screen(a));
    await tester.enterText(find.byKey(const Key('connect-id')), 'old-device');
    current = b;
    await tester.tap(find.byKey(const Key('connect-button')));
    await tester.pump();
    expect(connectionCalls, 0);
    expect(find.text('连接服务已改变，请从当前列表重新选择设备'), findsOneWidget);
    await tester.pumpWidget(screen(b));
    await tester.pumpAndSettle();
    expect(find.text('服务 A 的设备'), findsNothing);
    expect(find.text('还没有添加设备'), findsOneWidget);
    expect(
        tester
            .widget<TextFormField>(find.byKey(const Key('connect-id')))
            .controller!
            .text,
        isEmpty);
    current = a;
    await tester.pumpWidget(screen(a));
    await tester.pumpAndSettle();
    expect(find.text('服务 A 的设备'), findsOneWidget);
    expect(connectionCalls, 0);
  });
}
