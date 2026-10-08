/// System permission and a live accessibility connection are separate facts.
/// A missing native response never counts as permission being denied or granted.
enum XixiInputPermissionState {
  unknown,
  notGranted,
  connecting,
  recoveryRequired,
  connected,
}

enum XixiInputPermissionAction {
  checkAgain,
  openSystemSettings,
  waitForConnection,
  confirmDisable,
}

class XixiUnattendedState {
  final bool? supported;
  final bool enabled;
  final bool? accessibilityEnabled;
  final bool accessibilityConnected;
  final bool capable;
  final bool running;
  final bool recovering;
  final bool recoveryTimedOut;
  final bool batteryExempt;
  final String error;

  const XixiUnattendedState({
    this.supported,
    this.enabled = false,
    this.accessibilityEnabled,
    this.accessibilityConnected = false,
    this.capable = false,
    this.running = false,
    this.recovering = false,
    this.recoveryTimedOut = false,
    this.batteryExempt = false,
    this.error = '',
  });

  factory XixiUnattendedState.fromNative(Map<dynamic, dynamic> value) =>
      XixiUnattendedState(
        supported:
            value['supported'] is bool ? value['supported'] as bool : null,
        enabled: value['enabled'] == true,
        accessibilityEnabled: value['accessibilityStatusKnown'] != false &&
                value['accessibilityEnabled'] is bool
            ? value['accessibilityEnabled'] as bool
            : null,
        accessibilityConnected: value['accessibilityConnected'] == true,
        capable: value['capable'] == true,
        running: value['running'] == true,
        recovering: value['recovering'] == true,
        recoveryTimedOut: value['recoveryTimedOut'] == true,
        batteryExempt: value['batteryExempt'] == true,
        error: value['error'] is String ? value['error'] as String : '',
      );

  XixiInputPermissionState get inputPermissionState {
    if (accessibilityEnabled == null) return XixiInputPermissionState.unknown;
    if (accessibilityEnabled == false) {
      return XixiInputPermissionState.notGranted;
    }
    if (accessibilityConnected) return XixiInputPermissionState.connected;
    return recoveryTimedOut
        ? XixiInputPermissionState.recoveryRequired
        : XixiInputPermissionState.connecting;
  }

  XixiInputPermissionAction inputActionFor({required bool enable}) {
    if (accessibilityEnabled == null) {
      return XixiInputPermissionAction.checkAgain;
    }
    if (!enable) {
      return accessibilityEnabled == true
          ? XixiInputPermissionAction.confirmDisable
          : XixiInputPermissionAction.checkAgain;
    }
    if (accessibilityEnabled == false) {
      return XixiInputPermissionAction.openSystemSettings;
    }
    return XixiInputPermissionAction.waitForConnection;
  }
}

String xixiInputPermissionDescription(XixiInputPermissionState state) =>
    switch (state) {
      XixiInputPermissionState.unknown => '正在读取系统输入权限',
      XixiInputPermissionState.notGranted => '首次使用时启用西西远程输入服务',
      XixiInputPermissionState.connecting => '系统授权已保留，正在恢复输入服务',
      XixiInputPermissionState.recoveryRequired =>
        '系统授权已保留，输入服务尚未连接；请查看后台与电池设置',
      XixiInputPermissionState.connected => '输入服务已连接，系统授权已保留',
    };
