import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'xixi_device_screen.dart' show XixiPrimaryButton;
import 'xixi_unattended_state.dart';

enum XixiSharingConnectionState { unknown, connecting, ready, unavailable }

class XixiSharingPeer {
  final int connectionId;
  final String name;
  final String deviceId;
  final bool authorized;
  final bool disconnected;
  final bool fileTransfer;
  final VoidCallback? onAccept;
  final VoidCallback? onReject;
  final VoidCallback? onDisconnect;
  final VoidCallback? onAcceptVoice;
  final VoidCallback? onRejectVoice;
  final VoidCallback? onStopVoice;

  const XixiSharingPeer({
    required this.connectionId,
    required this.name,
    required this.deviceId,
    required this.authorized,
    this.disconnected = false,
    this.fileTransfer = false,
    this.onAccept,
    this.onReject,
    this.onDisconnect,
    this.onAcceptVoice,
    this.onRejectVoice,
    this.onStopVoice,
  });
}

class XixiSharingSnapshot {
  final String localId;
  final String oneTimePassword;
  final XixiSharingConnectionState connectionState;
  final bool serviceStarted;
  final bool captureEnabled;
  final bool inputEnabled;
  final XixiInputPermissionState inputPermissionState;
  final bool fileEnabled;
  final bool clipboardEnabled;
  final bool audioEnabled;
  final bool audioSupported;
  final bool permissionsLocked;
  final bool hideStopService;
  final bool showOneTimePassword;
  final List<XixiSharingPeer> peers;

  const XixiSharingSnapshot({
    this.localId = '',
    this.oneTimePassword = '',
    this.connectionState = XixiSharingConnectionState.unknown,
    this.serviceStarted = false,
    this.captureEnabled = false,
    this.inputEnabled = false,
    this.inputPermissionState = XixiInputPermissionState.unknown,
    this.fileEnabled = false,
    this.clipboardEnabled = false,
    this.audioEnabled = false,
    this.audioSupported = false,
    this.permissionsLocked = false,
    this.hideStopService = false,
    this.showOneTimePassword = true,
    this.peers = const [],
  });
}

class XixiSharingScreen extends StatelessWidget {
  final XixiSharingSnapshot snapshot;
  final VoidCallback onToggleService;
  final VoidCallback onToggleCapture;
  final ValueChanged<bool> onInputPermissionChanged;
  final VoidCallback onToggleFile;
  final VoidCallback onToggleClipboard;
  final VoidCallback? onToggleAudio;
  final VoidCallback? onRefreshPassword;
  final VoidCallback? onSecuritySettings;
  final VoidCallback? onOpenSettings;
  final Widget? passwordWarning;
  final String? unattendedStatus;
  final bool unattendedEnabled;
  final bool unattendedRunning;
  final bool unattendedBusy;
  final VoidCallback? onEnableUnattended;
  final VoidCallback? onBatterySettings;
  final VoidCallback? onManageInputPermission;

  const XixiSharingScreen({
    super.key,
    required this.snapshot,
    required this.onToggleService,
    required this.onToggleCapture,
    required this.onInputPermissionChanged,
    required this.onToggleFile,
    required this.onToggleClipboard,
    this.onToggleAudio,
    this.onRefreshPassword,
    this.onSecuritySettings,
    this.onOpenSettings,
    this.passwordWarning,
    this.unattendedStatus,
    this.unattendedEnabled = false,
    this.unattendedRunning = false,
    this.unattendedBusy = false,
    this.onEnableUnattended,
    this.onBatterySettings,
    this.onManageInputPermission,
  });

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    final background = Color(dark ? 0xff141822 : 0xfff6f7fa);
    final surface = Color(dark ? 0xff202632 : 0xffffffff);
    final ink = Color(dark ? 0xfff2f5fc : 0xff222c40);
    final muted = Color(dark ? 0xffadb8cf : 0xff647085);
    final line = Color(dark ? 0xff3a4455 : 0xffdde2eb);
    final accent = Color(dark ? 0xffaec7ff : 0xff245bea);

    Widget card(List<Widget> children) => Container(
          margin: const EdgeInsets.only(bottom: 16),
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            color: surface,
            border: Border.all(color: line),
            borderRadius: BorderRadius.circular(16),
          ),
          child: Column(
              crossAxisAlignment: CrossAxisAlignment.start, children: children),
        );

    void copy(String value, String message) {
      Clipboard.setData(ClipboardData(text: value.trim()));
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(message)));
    }

    Widget permission(String key, IconData icon, String title, String subtitle,
            bool value, VoidCallback? callback) =>
        SwitchListTile(
          key: ValueKey(key),
          contentPadding: EdgeInsets.zero,
          secondary: Icon(icon, color: muted),
          title: Text(title, style: TextStyle(color: ink)),
          subtitle:
              Text(subtitle, style: TextStyle(color: muted, fontSize: 12)),
          activeColor: accent,
          value: value,
          onChanged: callback == null ? null : (_) => callback(),
        );

    final status = switch (snapshot.connectionState) {
      XixiSharingConnectionState.ready => '连接服务已就绪',
      XixiSharingConnectionState.connecting => '正在连接服务',
      XixiSharingConnectionState.unavailable => '连接服务暂不可用',
      XixiSharingConnectionState.unknown => '连接状态待确认',
    };
    final permissionCallback = snapshot.permissionsLocked;
    return ColoredBox(
      color: background,
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 640),
          child: ListView(
            key: const Key('xixi-sharing-screen'),
            padding: const EdgeInsets.fromLTRB(20, 24, 20, 32),
            children: [
              Row(children: [
                Container(
                  width: 36,
                  height: 36,
                  decoration: BoxDecoration(
                      color: accent, borderRadius: BorderRadius.circular(9)),
                  child: Icon(Icons.mobile_screen_share_rounded,
                      color: dark ? background : Colors.white, size: 22),
                ),
                const SizedBox(width: 12),
                Expanded(
                    child: Text('共享此设备',
                        style: TextStyle(
                            fontSize: 27,
                            fontWeight: FontWeight.w600,
                            color: ink))),
                if (onOpenSettings != null)
                  IconButton(
                      tooltip: '连接设置',
                      onPressed: onOpenSettings,
                      icon: Icon(Icons.tune_rounded, color: muted)),
              ]),
              const SizedBox(height: 10),
              Text('让其他设备连接并操作这部手机', style: TextStyle(color: muted)),
              const SizedBox(height: 24),
              if (passwordWarning != null) passwordWarning!,
              if (onEnableUnattended != null)
                card([
                  Text('无人值守',
                      style: TextStyle(
                          color: ink,
                          fontSize: 18,
                          fontWeight: FontWeight.w600)),
                  const SizedBox(height: 10),
                  Text(unattendedStatus ?? '',
                      style: TextStyle(color: muted, fontSize: 14)),
                  const SizedBox(height: 16),
                  XixiPrimaryButton(
                      label: unattendedBusy
                          ? '正在设置…'
                          : unattendedRunning
                              ? '后台接入已启动'
                              : unattendedEnabled
                                  ? '恢复后台接入'
                                  : '设置无人值守',
                      icon: Icons.shield_outlined,
                      onPressed: unattendedBusy || unattendedRunning
                          ? null
                          : onEnableUnattended),
                  const SizedBox(height: 12),
                  SizedBox(
                      width: double.infinity,
                      child: OutlinedButton.icon(
                          onPressed: onBatterySettings,
                          icon: const Icon(Icons.battery_charging_full_rounded),
                          label: const Text('后台与电池设置'))),
                  const SizedBox(height: 12),
                  Text('只向你信任的控制端提供固定密码。使用无障碍截屏，刷新较慢；系统强行停止、权限撤销和受保护画面仍需本机处理。',
                      style: TextStyle(color: muted, fontSize: 12)),
                ]),
              card([
                Row(children: [
                  Expanded(
                      child: Text('本机 ID',
                          style: TextStyle(color: muted, fontSize: 13))),
                  Icon(
                      snapshot.connectionState ==
                              XixiSharingConnectionState.ready
                          ? Icons.check_circle_outline_rounded
                          : Icons.info_outline_rounded,
                      size: 16,
                      color: muted),
                  const SizedBox(width: 6),
                  Flexible(
                      child: Text(status,
                          style: TextStyle(color: muted, fontSize: 12))),
                ]),
                const SizedBox(height: 10),
                Row(children: [
                  Expanded(
                      child: SelectableText(
                          snapshot.localId.trim().isEmpty
                              ? '等待设备 ID'
                              : snapshot.localId,
                          key: const Key('sharing-local-id'),
                          style: TextStyle(
                              color: ink,
                              fontSize: 28,
                              fontWeight: FontWeight.w600,
                              letterSpacing: 1))),
                  IconButton(
                      tooltip: '复制本机 ID',
                      onPressed: snapshot.localId.trim().isEmpty
                          ? null
                          : () => copy(snapshot.localId, '本机 ID 已复制'),
                      icon: Icon(Icons.copy_rounded, color: muted)),
                ]),
                const Divider(height: 30),
                Text('一次性密码', style: TextStyle(color: muted, fontSize: 13)),
                const SizedBox(height: 6),
                Row(children: [
                  Expanded(
                      child: SelectableText(
                          !snapshot.showOneTimePassword
                              ? '当前使用其他验证方式'
                              : snapshot.oneTimePassword.isEmpty
                                  ? '等待密码'
                                  : snapshot.oneTimePassword,
                          style: TextStyle(
                              color: ink,
                              fontSize: snapshot.showOneTimePassword ? 22 : 14,
                              fontWeight: FontWeight.w600))),
                  if (snapshot.showOneTimePassword) ...[
                    IconButton(
                        tooltip: '刷新一次性密码',
                        onPressed: onRefreshPassword,
                        icon: Icon(Icons.refresh_rounded, color: muted)),
                    IconButton(
                        tooltip: '复制一次性密码',
                        onPressed: snapshot.oneTimePassword.isEmpty
                            ? null
                            : () => copy(snapshot.oneTimePassword, '密码已复制'),
                        icon: Icon(Icons.copy_rounded, color: muted)),
                  ],
                ]),
                if (onSecuritySettings != null)
                  TextButton.icon(
                      onPressed: onSecuritySettings,
                      icon: Icon(Icons.lock_outline_rounded,
                          size: 18, color: accent),
                      label: Text('密码与连接授权', style: TextStyle(color: accent))),
              ]),
              card([
                Row(children: [
                  Expanded(
                      child: Text('共享服务',
                          style: TextStyle(
                              color: ink,
                              fontSize: 20,
                              fontWeight: FontWeight.w600))),
                  Text(snapshot.serviceStarted ? '服务已启动' : '服务未启动',
                      style: TextStyle(color: muted, fontSize: 12)),
                ]),
                const SizedBox(height: 10),
                Text(
                    snapshot.captureEnabled
                        ? '屏幕采集已获授权，可向已授权的连接提供画面。'
                        : '开启共享后，按照 Android 提示确认屏幕录制权限。',
                    style: TextStyle(color: muted, height: 1.5)),
                if (!snapshot.serviceStarted || !snapshot.hideStopService) ...[
                  const SizedBox(height: 20),
                  SizedBox(
                    width: double.infinity,
                    child: FilledButton.icon(
                        key: const Key('sharing-service-button'),
                        style: FilledButton.styleFrom(
                            backgroundColor:
                                snapshot.serviceStarted ? background : accent,
                            foregroundColor: snapshot.serviceStarted
                                ? ink
                                : dark
                                    ? background
                                    : Colors.white,
                            padding: const EdgeInsets.symmetric(vertical: 14),
                            shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(10),
                                side: BorderSide(
                                    color: snapshot.serviceStarted
                                        ? line
                                        : accent))),
                        onPressed: onToggleService,
                        icon: Icon(snapshot.serviceStarted
                            ? Icons.stop_circle_outlined
                            : Icons.play_arrow_rounded),
                        label:
                            Text(snapshot.serviceStarted ? '停止共享服务' : '开启共享')),
                  ),
                ],
              ]),
              card([
                Text('允许远程使用',
                    style: TextStyle(
                        color: ink, fontSize: 20, fontWeight: FontWeight.w600)),
                const SizedBox(height: 8),
                if (!snapshot.hideStopService || !snapshot.captureEnabled)
                  permission(
                      'sharing-capture',
                      Icons.screenshot_monitor_rounded,
                      unattendedEnabled ? '屏幕画面' : '屏幕录制',
                      unattendedEnabled
                          ? '使用已启用的无障碍截屏服务'
                          : '由 Android 系统确认采集权限',
                      snapshot.captureEnabled,
                      onToggleCapture),
                SwitchListTile(
                  key: const ValueKey('sharing-input'),
                  contentPadding: EdgeInsets.zero,
                  secondary: Icon(Icons.touch_app_outlined, color: muted),
                  title: Text('输入控制', style: TextStyle(color: ink)),
                  subtitle: Text(
                      xixiInputPermissionDescription(
                          snapshot.inputPermissionState),
                      style: TextStyle(color: muted, fontSize: 12)),
                  activeColor: accent,
                  // Waiting for Android to bind is not a live input permission.
                  value: snapshot.inputEnabled &&
                      snapshot.inputPermissionState ==
                          XixiInputPermissionState.connected,
                  onChanged: !permissionCallback &&
                          (snapshot.inputPermissionState ==
                                  XixiInputPermissionState.notGranted ||
                              snapshot.inputPermissionState ==
                                  XixiInputPermissionState.connected)
                      ? onInputPermissionChanged
                      : null,
                ),
                if (onManageInputPermission != null)
                  Align(
                    alignment: Alignment.centerLeft,
                    child: TextButton.icon(
                      key: const Key('sharing-input-settings'),
                      onPressed:
                          permissionCallback ? null : onManageInputPermission,
                      icon: const Icon(Icons.settings_outlined, size: 18),
                      label: const Text('管理系统输入权限'),
                    ),
                  ),
                permission(
                    'sharing-file',
                    Icons.folder_open_rounded,
                    '传输文件',
                    '允许已授权的连接传输文件',
                    snapshot.fileEnabled,
                    permissionCallback ? null : onToggleFile),
                permission(
                    'sharing-clipboard',
                    Icons.content_paste_rounded,
                    '同步剪贴板',
                    '允许已连接设备同步复制的内容',
                    snapshot.clipboardEnabled,
                    permissionCallback ? null : onToggleClipboard),
                if (snapshot.audioSupported)
                  permission(
                      'sharing-audio',
                      Icons.volume_up_outlined,
                      '音频采集',
                      '由系统确认麦克风权限',
                      snapshot.audioEnabled,
                      permissionCallback ? null : onToggleAudio),
                if (snapshot.permissionsLocked)
                  Padding(
                    padding: const EdgeInsets.only(top: 10),
                    child: Text('连接期间部分权限暂不能更改',
                        style: TextStyle(color: muted, fontSize: 12)),
                  ),
              ]),
              ...snapshot.peers.map((peer) => card([
                    Text(peer.fileTransfer ? '文件连接' : '远程连接',
                        style: TextStyle(color: muted, fontSize: 12)),
                    const SizedBox(height: 9),
                    Text(peer.name.isEmpty ? peer.deviceId : peer.name,
                        style: TextStyle(
                            color: ink,
                            fontSize: 18,
                            fontWeight: FontWeight.w600)),
                    const SizedBox(height: 4),
                    Text('ID ${peer.deviceId}',
                        style: TextStyle(color: muted, fontSize: 13)),
                    const SizedBox(height: 12),
                    Text(
                        peer.disconnected
                            ? '连接已断开'
                            : peer.authorized
                                ? '已授权连接'
                                : '有设备请求连接，请确认是否允许',
                        style: TextStyle(color: muted)),
                    if (!peer.disconnected)
                      Wrap(spacing: 10, children: [
                        if (peer.onReject != null)
                          TextButton(
                              onPressed: peer.onReject,
                              child: const Text('拒绝')),
                        if (peer.onAccept != null)
                          FilledButton(
                              key: ValueKey(
                                  'sharing-accept-${peer.connectionId}'),
                              onPressed: peer.onAccept,
                              child: const Text('允许连接')),
                        if (peer.onDisconnect != null)
                          OutlinedButton(
                              onPressed: peer.onDisconnect,
                              child: const Text('断开连接')),
                        if (peer.onRejectVoice != null)
                          TextButton(
                              onPressed: peer.onRejectVoice,
                              child: const Text('拒绝语音')),
                        if (peer.onAcceptVoice != null)
                          FilledButton(
                              onPressed: peer.onAcceptVoice,
                              child: const Text('接听语音')),
                        if (peer.onStopVoice != null)
                          OutlinedButton(
                              onPressed: peer.onStopVoice,
                              child: const Text('结束语音')),
                      ]),
                  ])),
            ],
          ),
        ),
      ),
    );
  }
}
