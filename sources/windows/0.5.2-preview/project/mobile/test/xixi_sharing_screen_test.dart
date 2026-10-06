import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../lib/xixi_sharing_screen.dart';

void main() {
  testWidgets('sharing uses real snapshot and permission callbacks',
      (tester) async {
    var serviceTaps = 0;
    var inputTaps = 0;
    await tester.pumpWidget(MaterialApp(
        home: Scaffold(
            body: XixiSharingScreen(
      snapshot: const XixiSharingSnapshot(
          localId: '123 456 789',
          oneTimePassword: 'abcdef',
          connectionState: XixiSharingConnectionState.connecting),
      onToggleService: () => serviceTaps++,
      onToggleCapture: () {},
      onToggleInput: () => inputTaps++,
      onToggleFile: () {},
      onToggleClipboard: () {},
    ))));
    expect(find.text('123 456 789'), findsOneWidget);
    expect(find.text('abcdef'), findsOneWidget);
    expect(find.text('正在连接服务'), findsOneWidget);
    expect(find.text('连接服务已就绪'), findsNothing);
    await tester.ensureVisible(find.byKey(const Key('sharing-service-button')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('sharing-service-button')));
    await tester.ensureVisible(find.byKey(const ValueKey('sharing-input')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('sharing-input')));
    expect(serviceTaps, 1);
    expect(inputTaps, 1);
  });

  testWidgets(
      'active permission restrictions and hidden password are respected',
      (tester) async {
    await tester.pumpWidget(MaterialApp(
        home: Scaffold(
            body: XixiSharingScreen(
      snapshot: const XixiSharingSnapshot(
          serviceStarted: true,
          captureEnabled: true,
          hideStopService: true,
          permissionsLocked: true,
          showOneTimePassword: false,
          oneTimePassword: 'should-not-display'),
      onToggleService: () {},
      onToggleCapture: () {},
      onToggleInput: () {},
      onToggleFile: () {},
      onToggleClipboard: () {},
    ))));
    expect(find.text('should-not-display'), findsNothing);
    expect(find.byKey(const Key('sharing-service-button')), findsNothing);
    expect(find.byKey(const ValueKey('sharing-capture')), findsNothing);
    await tester.ensureVisible(find.byKey(const ValueKey('sharing-file')));
    final file = tester
        .widget<SwitchListTile>(find.byKey(const ValueKey('sharing-file')));
    expect(file.onChanged, isNull);
    final clipboard = tester.widget<SwitchListTile>(
        find.byKey(const ValueKey('sharing-clipboard')));
    expect(clipboard.onChanged, isNull);
  });

  testWidgets('incoming request only allows explicit permitted actions',
      (tester) async {
    var accepts = 0;
    await tester.pumpWidget(MaterialApp(
        home: Scaffold(
            body: XixiSharingScreen(
      snapshot: XixiSharingSnapshot(peers: [
        XixiSharingPeer(
            connectionId: 7,
            name: '自定义设备',
            deviceId: '987654321',
            authorized: false,
            onReject: () {},
            onAccept: () => accepts++),
        XixiSharingPeer(
            connectionId: 8,
            name: '密码验证设备',
            deviceId: '112233445',
            authorized: false,
            onReject: () {}),
      ]),
      onToggleService: () {},
      onToggleCapture: () {},
      onToggleInput: () {},
      onToggleFile: () {},
      onToggleClipboard: () {},
    ))));
    await tester.scrollUntilVisible(
        find.byKey(const ValueKey('sharing-accept-7')), 300,
        scrollable: find.byType(Scrollable).first);
    await tester.tap(find.byKey(const ValueKey('sharing-accept-7')));
    expect(accepts, 1);
    expect(find.byKey(const ValueKey('sharing-accept-8')), findsNothing);
  });
}
