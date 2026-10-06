import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_hbb/common.dart';
import 'package:flutter_hbb/desktop/pages/desktop_home_page.dart'
    show setPasswordDialog;
import 'package:flutter_hbb/models/platform_model.dart';
import '../xixi/xixi_connection_page.dart';
import '../xixi/saved_devices.dart';
import '../xixi/device_scope.dart';
import 'xixi_desktop_frame.dart';
import 'xixi_desktop_sections.dart';

class XixiDesktopHome extends StatefulWidget {
  const XixiDesktopHome({super.key});
  @override
  State<XixiDesktopHome> createState() => _XixiDesktopHomeState();
}

class _XixiDesktopHomeState extends State<XixiDesktopHome> {
  int _page = 0;
  Timer? _timer;
  bool _restoring = false;
  bool _sharingPaused = false;
  bool _changingSharing = false;
  @override
  void initState() {
    super.initState();
    _refresh();
    _initializeSharing();
    _timer = Timer.periodic(const Duration(seconds: 3), (_) => _refresh());
  }

  Future<void> _initializeSharing() async {
    // Running this product starts sharing. Old upstream stop-service settings
    // must not leave the independently installed product permanently offline.
    for (var attempt = 0; attempt < 20; attempt++) {
      if (!mounted) return;
      if (await bind.optionSynced()) {
        await _setSharingPaused(false, announce: false);
        return;
      }
      await Future<void>.delayed(const Duration(milliseconds: 500));
    }
  }

  Future<void> _setSharingPaused(bool paused, {bool announce = true}) async {
    if (_changingSharing) return;
    setState(() => _changingSharing = true);
    try {
      await bind.mainSetOption(key: 'stop-service', value: paused ? 'Y' : '');
      await _refresh();
      if (announce && mounted) _message(paused ? '已暂停本机共享' : '已开始本机共享');
    } catch (_) {
      if (mounted) _message('共享状态未保存，请重试');
    } finally {
      if (mounted) setState(() => _changingSharing = false);
    }
  }

  Future<void> _refresh() async {
    try {
      await gFFI.serverModel.fetchID();
      await gFFI.serverModel.updatePasswordModel();
      final options = jsonDecode(bind.mainGetOptionsSync()) as Map;
      if (mounted && _sharingPaused != (options['stop-service'] == 'Y')) {
        setState(() => _sharingPaused = options['stop-service'] == 'Y');
      }
      final appData = Platform.environment['LOCALAPPDATA'];
      if (appData != null && appData.isNotEmpty) {
        final folder = Directory('$appData${Platform.pathSeparator}XiXiRemote');
        await folder.create(recursive: true);
        var id = '';
        try {
          id = normalizeDeviceId(gFFI.serverModel.serverId.text);
        } catch (_) {}
        // Diagnostics intentionally contain only public connection facts.
        await File(
                '${folder.path}${Platform.pathSeparator}standalone-status.json')
            .writeAsString(
                jsonEncode({
                  'product': 'XiXiRemote',
                  'version': '0.5.2-preview',
                  'checkedAtUtc': DateTime.now().toUtc().toIso8601String(),
                  'executable': Platform.resolvedExecutable,
                  'nativeBridgeActive': true,
                  'localId': id,
                  'connectStatus': gFFI.serverModel.connectStatus,
                  'idServer': options['custom-rendezvous-server'],
                  'relayServer': options['relay-server'],
                  'publicKey': options['key'],
                  'sharingPaused': options['stop-service'] == 'Y',
                }),
                flush: true);
      }
    } catch (_) {
      /* Keep the actual last native state; do not invent readiness. */
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  void _select(int page) => setState(() => _page = page);
  void _message(String text) =>
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));
  Future<void> _restoreDefaults() async {
    if (_restoring) return;
    setState(() => _restoring = true);
    try {
      // The public asset uses the product schema, not the engine import schema.
      final json =
          await rootBundle.loadString('assets/XIXI-DEFAULT-CONNECTION.json');
      final scope = DeviceProfileScope.fromPublicProfileJson(json);
      if (!await setServerConfig(
          null,
          null,
          ServerConfig(
              idServer: scope.server,
              relayServer: scope.relayServer,
              apiServer: '',
              key: scope.publicKey))) {
        throw StateError('Configuration was rejected');
      }
      requireCurrentDeviceScope(
          scope, DeviceProfileScope.fromOptionsJson(bind.mainGetOptionsSync()));
      _message('已恢复西西默认连接服务');
    } catch (_) {
      _message('连接服务未保存，请重试');
    } finally {
      if (mounted) setState(() => _restoring = false);
    }
  }

  Widget _sharing() => AnimatedBuilder(
      animation: gFFI.serverModel,
      builder: (context, _) {
        final model = gFFI.serverModel;
        final id = model.serverId.text;
        return XixiDesktopSectionPage(
            title: '本机共享',
            description: '让其他设备通过 ID 和授权连接这台电脑。',
            sections: [
              XixiDesktopSection(title: '设备与接入', rows: [
                XixiDesktopSettingRow(
                    label: '本机 ID',
                    value: id.isEmpty ? '正在读取' : id,
                    prominent: true,
                    hint: '对方输入此 ID 即可发起连接。',
                    action: XixiDesktopAction(
                        label: '复制本机 ID',
                        icon: Icons.copy_outlined,
                        onPressed: () async {
                          try {
                            await Clipboard.setData(
                                ClipboardData(text: normalizeDeviceId(id)));
                            _message('本机 ID 已复制');
                          } catch (_) {
                            _message('本机 ID 暂未读取');
                          }
                        })),
                XixiDesktopSettingRow(
                    label: '一次性密码',
                    value: model.verificationMethod == 'use-permanent-password'
                        ? '已选择固定密码验证'
                        : model.serverPasswd.text,
                    prominent:
                        model.verificationMethod != 'use-permanent-password',
                    hint: '临时接入可用一次性密码；无人值守请设置固定密码。',
                    action: XixiDesktopAction(
                        label: '刷新一次性密码',
                        icon: Icons.refresh_rounded,
                        onPressed:
                            model.verificationMethod == 'use-permanent-password'
                                ? null
                                : () {
                                    bind.mainUpdateTemporaryPassword();
                                    model.updatePasswordModel();
                                  })),
                XixiDesktopSettingRow(
                    label: '固定密码',
                    value: '由你设置并保存在本机',
                    hint: '只向你信任的控制端提供密码。',
                    action: XixiDesktopAction(
                        label: '设置固定密码',
                        icon: Icons.lock_outline,
                        onPressed: () => setPasswordDialog())),
              ]),
              XixiDesktopSection(title: '运行状态', rows: [
                XixiDesktopSettingRow(
                    label: '本机共享',
                    value: _sharingPaused
                        ? '已暂停'
                        : model.connectStatus > 0
                            ? '连接服务就绪'
                            : model.connectStatus == 0
                                ? '正在连接服务'
                                : '连接服务未就绪',
                    hint: '此预览版需保持程序运行；重启恢复和系统登录屏幕仍待验收。',
                    action: XixiDesktopAction(
                        primary: true,
                        label: _changingSharing
                            ? '正在保存…'
                            : _sharingPaused
                                ? '开始本机共享'
                                : '暂停本机共享',
                        icon: _sharingPaused
                            ? Icons.play_arrow_rounded
                            : Icons.pause_rounded,
                        onPressed: _changingSharing
                            ? null
                            : () => _setSharingPaused(!_sharingPaused))),
              ]),
            ]);
      });
  Widget _settings() => XixiDesktopSectionPage(
          title: '设置',
          description: '连接服务已内置，安装后可直接输入设备 ID。',
          sections: [
            XixiDesktopSection(title: '连接与安全', rows: [
              XixiDesktopSettingRow(
                  label: '连接服务',
                  value: '西西默认连接服务',
                  hint: '日常连接无需手动填写服务器。',
                  action: XixiDesktopAction(
                      primary: true,
                      label: _restoring ? '正在恢复…' : '恢复默认连接服务',
                      icon: Icons.refresh_rounded,
                      onPressed: _restoring ? null : _restoreDefaults)),
              XixiDesktopSettingRow(
                  label: '接入密码',
                  value: '软件不预设远控密码',
                  hint: '每次接入按本机选择的授权方式验证。',
                  action: XixiDesktopAction(
                      label: '设置固定密码',
                      icon: Icons.lock_outline,
                      onPressed: () => setPasswordDialog())),
            ]),
            const XixiDesktopSection(title: '关于', rows: [
              XixiDesktopSettingRow(
                  label: '西西远程',
                  value: '独立桌面客户端 · 0.5.2-preview',
                  hint: '远控引擎随软件提供，无需另外安装程序。'),
              XixiDesktopSettingRow(
                  label: '开源组件',
                  value: 'RustDesk（AGPL-3.0）与 Flutter',
                  hint: '完整许可、来源和对应修改源码随安装包提供。'),
            ]),
          ]);
  @override
  Widget build(BuildContext context) => XixiDesktopFrame(
      selected: _page,
      onSelected: _select,
      body: IndexedStack(index: _page, children: [
        XixiConnectionPage(
            appBarActions: const [],
            onOpenSettings: () => _select(2),
            onShowSharing: () => _select(1)),
        _sharing(),
        _settings(),
      ]));
}
