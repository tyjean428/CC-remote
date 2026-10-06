import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_hbb/common.dart';
import 'package:flutter_hbb/consts.dart';
import 'package:flutter_hbb/desktop/pages/desktop_home_page.dart';
import 'package:flutter_hbb/mobile/pages/home_page.dart';
import 'package:flutter_hbb/mobile/pages/server_page.dart';
import 'package:flutter_hbb/mobile/widgets/dialog.dart';
import 'package:flutter_hbb/models/platform_model.dart';
import 'package:flutter_hbb/models/server_model.dart';

import 'xixi_sharing_screen.dart';

class XixiSharingPage extends StatefulWidget implements PageShape {
  @override
  final String title = '共享';
  @override
  final Widget icon = const Icon(Icons.mobile_screen_share_rounded);
  @override
  final List<Widget> appBarActions;
  final VoidCallback? onOpenSettings;

  const XixiSharingPage({
    super.key,
    this.appBarActions = const [],
    this.onOpenSettings,
  });

  @override
  State<XixiSharingPage> createState() => _XixiSharingPageState();
}

class _XixiSharingPageState extends State<XixiSharingPage> {
  Timer? _timer;
  Map<dynamic, dynamic> _unattended = const {};
  bool _settingUp = false;

  @override
  void initState() {
    super.initState();
    _refresh();
    gFFI.serverModel.checkAndroidPermission();
    _timer = Timer.periodic(const Duration(seconds: 3), (_) => _refresh());
  }

  Future<void> _refresh() async {
    checkService();
    await gFFI.serverModel.fetchID();
    try {
      final state = await gFFI.invokeMethodWithResult<Map<dynamic, dynamic>>(
          'xixi_unattended_state');
      if (mounted && state != null) setState(() => _unattended = state);
    } catch (_) {/* Desktop and older hosts do not expose this Android API. */}
  }

  void _message(String text) {
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));
    }
  }

  Future<void> _enableUnattended() async {
    if (_settingUp) return;
    if (_unattended['supported'] != true) {
      _message('免录屏确认模式需要 Android 11 或更新版本');
      return;
    }
    if (_unattended['capable'] != true) {
      _message('请先启用“西西远程输入”无障碍服务；升级后可能需要关闭再开启一次');
      if (_unattended['accessibility'] != true) gFFI.serverModel.toggleInput();
      return;
    }
    if (await bind.mainGetCommon(key: 'permanent-password-set') != 'true') {
      setPasswordDialog(notEmptyCallback: () => _enableUnattended());
      return;
    }
    if (!mounted) return;
    setState(() => _settingUp = true);
    try {
      await gFFI.serverModel.setApproveMode('password');
      await bind.mainSetOption(
          key: kOptionVerificationMethod, value: kUsePermanentPassword);
      gFFI.serverModel.updatePasswordModel();
      if (!await gFFI.invokeMethod('xixi_enable_unattended', true)) {
        throw StateError('Host did not start');
      }
      await gFFI.serverModel.startService();
      await _refresh();
      _message('已开启无人值守。请用固定密码从另一台设备连接验证');
    } catch (_) {
      _message('无人值守未能开启，请检查无障碍服务后重试');
    } finally {
      if (mounted) setState(() => _settingUp = false);
    }
  }

  String get _unattendedStatus {
    if (_unattended.isEmpty) return '正在读取手机能力';
    if (_unattended['supported'] != true) {
      return '此系统需要录屏确认；免确认模式需要 Android 11 起';
    }
    if (_unattended['enabled'] != true) return '首次设置固定密码和无障碍权限，然后开启后台接入';
    if (_unattended['capable'] != true) return '无障碍服务已失效，请在本机重新启用';
    if (_unattended['running'] != true) return '后台接入未运行，请点恢复后台接入';
    final error = _unattended['error'];
    if (error is String && error.isNotEmpty) return error;
    if (_unattended['batteryExempt'] != true) {
      return '后台接入已启动；请允许不受电池优化限制，并在小米设置中允许自启动';
    }
    return '后台接入已启动 · 固定密码验证 · 无障碍截屏；实际连接待验证';
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  void _toggleService({bool fromCapture = false}) {
    final model = gFFI.serverModel;
    final starting = fromCapture ? !model.mediaOk : !model.isStart;
    if (starting &&
        gFFI.userModel.userName.value.isEmpty &&
        bind.mainGetLocalOption(key: 'show-scam-warning') != 'N') {
      showScamWarning(context, model);
    } else {
      model.toggleService();
    }
  }

  Future<void> _chooseVerification(String value) async {
    void apply() {
      bind.mainSetOption(key: kOptionVerificationMethod, value: value);
      gFFI.serverModel.updatePasswordModel();
    }

    if (value == kUsePermanentPassword &&
        await bind.mainGetCommon(key: 'permanent-password-set') != 'true' &&
        !isChangePermanentPasswordDisabled()) {
      setPasswordDialog(notEmptyCallback: apply);
    } else {
      apply();
    }
  }

  void _showSecuritySettings() {
    final model = gFFI.serverModel;
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (context) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            const ListTile(
                contentPadding: EdgeInsets.zero,
                title: Text('密码与连接授权',
                    style:
                        TextStyle(fontSize: 20, fontWeight: FontWeight.w600))),
            DropdownButtonFormField<String>(
              value: ['password', 'click'].contains(model.approveMode)
                  ? model.approveMode
                  : defaultOptionApproveMode,
              decoration: const InputDecoration(labelText: '连接授权方式'),
              items: [
                const DropdownMenuItem(
                    value: 'password', child: Text('使用密码授权')),
                const DropdownMenuItem(value: 'click', child: Text('每次手动确认')),
                DropdownMenuItem(
                    value: defaultOptionApproveMode,
                    child: const Text('密码或手动确认')),
              ],
              onChanged: isOptionFixed(kOptionApproveMode)
                  ? null
                  : (value) {
                      if (value == null) return;
                      model.setApproveMode(value);
                      Navigator.pop(context);
                    },
            ),
            const SizedBox(height: 20),
            if (model.approveMode != 'click') ...[
              DropdownButtonFormField<String>(
                value: model.verificationMethod,
                decoration: const InputDecoration(labelText: '可使用的密码'),
                items: const [
                  DropdownMenuItem(
                      value: kUseTemporaryPassword, child: Text('一次性密码')),
                  DropdownMenuItem(
                      value: kUsePermanentPassword, child: Text('固定密码')),
                  DropdownMenuItem(
                      value: kUseBothPasswords, child: Text('两种密码均可')),
                ],
                onChanged: isOptionFixed(kOptionVerificationMethod)
                    ? null
                    : (value) {
                        if (value == null) return;
                        Navigator.pop(context);
                        _chooseVerification(value);
                      },
              ),
              const SizedBox(height: 12),
              if (!isChangePermanentPasswordDisabled())
                ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: const Icon(Icons.key_rounded),
                    title: const Text('设置固定密码'),
                    trailing: const Icon(Icons.chevron_right_rounded),
                    onTap: () {
                      Navigator.pop(context);
                      setPasswordDialog();
                    }),
              if (model.verificationMethod != kUsePermanentPassword)
                ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: const Icon(Icons.password_rounded),
                    title: const Text('一次性密码长度'),
                    trailing: const Icon(Icons.chevron_right_rounded),
                    onTap: () {
                      Navigator.pop(context);
                      setTemporaryPasswordLengthDialog(gFFI.dialogManager);
                    }),
            ],
          ]),
        ),
      ),
    );
  }

  XixiSharingPeer _peer(Client client, ServerModel model) => XixiSharingPeer(
        connectionId: client.id,
        name: client.name,
        deviceId: client.peerId,
        authorized: client.authorized,
        disconnected: client.disconnected,
        fileTransfer: client.isFileTransfer,
        onAccept: !client.authorized && model.approveMode != 'password'
            ? () => model.sendLoginResponse(client, true)
            : null,
        onReject: !client.authorized
            ? () => model.sendLoginResponse(client, false)
            : null,
        onDisconnect: client.authorized
            ? () {
                bind.cmCloseConnection(connId: client.id);
                gFFI.invokeMethod('cancel_notification', client.id);
              }
            : null,
        onAcceptVoice: client.incomingVoiceCall &&
                !client.inVoiceCall &&
                model.approveMode != 'password'
            ? () => model.handleVoiceCall(client, true)
            : null,
        onRejectVoice: client.incomingVoiceCall && !client.inVoiceCall
            ? () => model.handleVoiceCall(client, false)
            : null,
        onStopVoice: client.inVoiceCall
            ? () {
                bind.cmCloseVoiceCall(id: client.id);
                gFFI.invokeMethod('cancel_notification', client.id);
              }
            : null,
      );

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
        animation: gFFI.serverModel,
        builder: (context, _) {
          final model = gFFI.serverModel;
          final allowPermissionChange = option2bool(
              kOptionEnablePermChangeInAcceptWindow,
              bind.mainGetBuildinOption(
                  key: kOptionEnablePermChangeInAcceptWindow));
          final securityEnabled = !bind.isDisableSettings() &&
              bind.mainGetBuildinOption(key: kOptionHideSecuritySetting) != 'Y';
          return XixiSharingScreen(
            unattendedStatus: _unattendedStatus,
            unattendedEnabled: _unattended['enabled'] == true,
            unattendedBusy: _settingUp,
            onEnableUnattended: _enableUnattended,
            onBatterySettings: () => gFFI.invokeMethod('xixi_battery_settings'),
            snapshot: XixiSharingSnapshot(
              localId: model.serverId.text,
              oneTimePassword: model.serverPasswd.text,
              connectionState: model.connectStatus > 0
                  ? XixiSharingConnectionState.ready
                  : model.connectStatus == 0
                      ? XixiSharingConnectionState.connecting
                      : XixiSharingConnectionState.unavailable,
              serviceStarted: model.isStart,
              captureEnabled: model.mediaOk,
              inputEnabled: model.inputOk,
              fileEnabled: model.fileOk,
              clipboardEnabled: model.clipboardOk,
              audioEnabled: model.audioOk,
              audioSupported: androidVersion >= 30,
              permissionsLocked: model.clients.any((c) => !c.disconnected) &&
                  !allowPermissionChange,
              hideStopService:
                  bind.mainGetBuildinOption(key: kOptionHideStopService) == 'Y',
              showOneTimePassword: model.approveMode != 'click' &&
                  model.verificationMethod != kUsePermanentPassword,
              peers: model.clients.map((c) => _peer(c, model)).toList(),
            ),
            onToggleService: _toggleService,
            onToggleCapture: () => _toggleService(fromCapture: true),
            onToggleInput: model.toggleInput,
            onToggleFile: model.toggleFile,
            onToggleClipboard: model.toggleClipboard,
            onToggleAudio: model.toggleAudio,
            onRefreshPassword: () => bind.mainUpdateTemporaryPassword(),
            onSecuritySettings: securityEnabled ? _showSecuritySettings : null,
            onOpenSettings:
                bind.isDisableSettings() ? null : widget.onOpenSettings,
            passwordWarning: buildPresetPasswordWarningMobile(),
          );
        },
      );
}
