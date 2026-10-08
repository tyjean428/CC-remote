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
import 'xixi_unattended_state.dart';

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

class _XixiSharingPageState extends State<XixiSharingPage>
    with WidgetsBindingObserver {
  Timer? _timer;
  XixiUnattendedState _unattended = const XixiUnattendedState();
  Future<XixiUnattendedState>? _refreshing;
  bool _settingUp = false;
  bool _changingInput = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    unawaited(_refresh());
    _timer = Timer.periodic(
        const Duration(seconds: 3), (_) => unawaited(_refresh()));
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) unawaited(_refresh());
  }

  Future<XixiUnattendedState> _refresh() =>
      _refreshing ??= _readState().whenComplete(() => _refreshing = null);

  Future<XixiUnattendedState> _readState() async {
    var state = const XixiUnattendedState();
    try {
      // The native snapshot is authoritative; never treat initial model false
      // or a temporary service disconnect as a request to revoke permission.
      await gFFI.invokeMethod('check_service');
      await gFFI.serverModel.checkAndroidPermission();
      await gFFI.serverModel.fetchID();
      final response = await gFFI.invokeMethodWithResult<Map<dynamic, dynamic>>(
          'xixi_unattended_state');
      if (response != null) state = XixiUnattendedState.fromNative(response);
    } catch (_) {/* Desktop and older hosts do not expose this Android API. */}
    if (mounted) setState(() => _unattended = state);
    return state;
  }

  void _message(String text) {
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));
    }
  }

  Future<void> _enableUnattended() async {
    if (_settingUp) return;
    if (!mounted) return;
    setState(() => _settingUp = true);
    try {
      final state = await _refresh();
      if (state.supported == null || state.accessibilityEnabled == null) {
        _message('正在读取系统权限，请稍后重试');
        return;
      }
      if (state.supported != true) {
        _message('免录屏确认模式需要 Android 11 或更新版本');
        return;
      }
      if (state.accessibilityEnabled == false) {
        showInputWarnAlert(gFFI);
        return;
      }
      if (!state.accessibilityConnected) {
        if (state.enabled) {
          await gFFI.invokeMethod('xixi_retry_unattended');
          await _refresh();
        }
        _message(
            xixiInputPermissionDescription(_unattended.inputPermissionState));
        return;
      }
      if (!state.capable) {
        _message('输入服务已授权，但当前系统未提供无人值守截屏能力');
        return;
      }
      if (await bind.mainGetCommon(key: 'permanent-password-set') != 'true') {
        setPasswordDialog(notEmptyCallback: () => _enableUnattended());
        return;
      }
      await gFFI.serverModel.setApproveMode('password');
      await bind.mainSetOption(
          key: kOptionVerificationMethod, value: kUsePermanentPassword);
      gFFI.serverModel.updatePasswordModel();
      if (!state.enabled &&
          !await gFFI.invokeMethod('xixi_enable_unattended', true)) {
        throw StateError('Host did not start');
      }
      if (!await gFFI.invokeMethod('xixi_retry_unattended')) {
        throw StateError('Host recovery was not accepted');
      }
      final refreshed = await _refresh();
      _message(refreshed.running && refreshed.capable
          ? '后台接入已启动，请用固定密码连接'
          : '无人值守设置已保存，正在恢复后台接入');
    } catch (_) {
      _message('后台接入未能启动，请稍后重试或查看后台与电池设置');
    } finally {
      if (mounted) setState(() => _settingUp = false);
    }
  }

  String get _unattendedStatus {
    if (_unattended.supported == null) return '正在读取手机能力';
    if (_unattended.supported != true) {
      return '此系统需要录屏确认；免确认模式需要 Android 11 起';
    }
    if (_unattended.enabled &&
        _unattended.inputPermissionState !=
            XixiInputPermissionState.connected) {
      return xixiInputPermissionDescription(_unattended.inputPermissionState);
    }
    if (!_unattended.enabled) return '首次设置固定密码和无障碍权限，然后开启后台接入';
    if (!_unattended.capable) return '输入服务已授权，但当前系统未提供无人值守截屏能力';
    if (!_unattended.running) return '后台接入未运行，请点恢复后台接入';
    if (_unattended.error.isNotEmpty) return _unattended.error;
    if (!_unattended.batteryExempt) {
      return '后台接入已启动；请允许不受电池优化限制，并在小米设置中允许自启动';
    }
    return '后台接入已启动 · 固定密码验证 · 无障碍截屏；实际连接待验证';
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _timer?.cancel();
    super.dispose();
  }

  Future<void> _toggleService({bool fromCapture = false}) async {
    final model = gFFI.serverModel;
    final state = await _refresh();
    if (!mounted) return;
    if (state.supported == null || state.accessibilityEnabled == null) {
      _message('正在读取系统权限，请稍后重试');
      return;
    }
    final running =
        state.enabled ? state.running && state.capable : model.isStart;
    final capture =
        state.enabled ? state.running && state.capable : model.mediaOk;
    final starting = fromCapture ? !capture : !running;
    if (starting && state.enabled) {
      // Preserve the saved unattended mode instead of asking for a new
      // MediaProjection session through the ordinary sharing flow.
      if (state.accessibilityEnabled != true) {
        showInputWarnAlert(gFFI);
        return;
      }
      await gFFI.invokeMethod('xixi_retry_unattended');
      await _refresh();
      return;
    }
    if (starting &&
        gFFI.userModel.userName.value.isEmpty &&
        bind.mainGetLocalOption(key: 'show-scam-warning') != 'N') {
      showScamWarning(context, model);
    } else {
      model.toggleService();
    }
  }

  Future<void> _setInputPermission(bool enable) async {
    if (_changingInput) return;
    _changingInput = true;
    try {
      final state = await _refresh();
      if (!mounted) return;
      switch (state.inputActionFor(enable: enable)) {
        case XixiInputPermissionAction.checkAgain:
          _message('正在读取系统输入权限，请稍后重试');
          return;
        case XixiInputPermissionAction.openSystemSettings:
          showInputWarnAlert(gFFI);
          return;
        case XixiInputPermissionAction.waitForConnection:
          _message(xixiInputPermissionDescription(state.inputPermissionState));
          return;
        case XixiInputPermissionAction.confirmDisable:
          final confirmed = await showDialog<bool>(
            context: context,
            builder: (context) => AlertDialog(
              title: const Text('关闭输入权限？'),
              content: const Text('关闭后将无法远程操作这部手机；下次使用需要在本机重新启用。'),
              actions: [
                TextButton(
                    onPressed: () => Navigator.pop(context, false),
                    child: const Text('保留权限')),
                TextButton(
                    onPressed: () => Navigator.pop(context, true),
                    child: const Text('关闭权限')),
              ],
            ),
          );
          if (confirmed != true) return;
          final refreshed = await _refresh();
          if (refreshed.accessibilityEnabled != true) return;
          if (refreshed.accessibilityConnected) {
            await gFFI.invokeMethod('stop_input');
            await bind.mainSetOption(key: kOptionEnableKeyboard, value: 'N');
            await _refresh();
          } else {
            // An enabled but disconnected Android service cannot disable
            // itself; only this explicit management action opens Settings.
            AndroidPermissionManager.startAction(kActionAccessibilitySettings);
          }
      }
    } finally {
      _changingInput = false;
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
            unattendedEnabled: _unattended.enabled,
            unattendedRunning: _unattended.running && _unattended.capable,
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
              serviceStarted: _unattended.enabled
                  ? _unattended.running && _unattended.capable
                  : model.isStart,
              captureEnabled: _unattended.enabled
                  ? _unattended.running && _unattended.capable
                  : model.mediaOk,
              inputEnabled: _unattended.accessibilityConnected &&
                  _unattended.accessibilityEnabled == true,
              inputPermissionState: _unattended.inputPermissionState,
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
            onInputPermissionChanged: _setInputPermission,
            onManageInputPermission: () => AndroidPermissionManager.startAction(
                kActionAccessibilitySettings),
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
