import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_hbb/common.dart';
import 'package:flutter_hbb/consts.dart';
import 'package:flutter_hbb/mobile/pages/home_page.dart';
import 'package:flutter_hbb/mobile/pages/settings_page.dart';
import 'package:flutter_hbb/mobile/widgets/dialog.dart';
import 'package:flutter_hbb/models/platform_model.dart';
import 'package:path_provider/path_provider.dart';

import 'file_device_storage.dart';
import 'device_scope.dart';
import 'device_connection_state.dart';
import 'private_connection_profile.dart';
import 'saved_devices.dart';
import 'xixi_device_screen.dart';
import 'xixi_sharing_page.dart';

class XixiConnectionPage extends StatefulWidget implements PageShape {
  @override
  final String title = '设备';
  @override
  final Widget icon = const Icon(Icons.devices_rounded);
  @override
  final List<Widget> appBarActions;
  final VoidCallback? onShowSharing;
  final VoidCallback? onOpenSettings;

  const XixiConnectionPage({
    super.key,
    required this.appBarActions,
    this.onShowSharing,
    this.onOpenSettings,
  });

  @override
  State<XixiConnectionPage> createState() => _XixiConnectionPageState();
}

class _XixiConnectionPageState extends State<XixiConnectionPage> {
  final _unconfiguredRepository =
      DeviceRepository(_UnconfiguredDeviceStorage());
  final _connectionState = DeviceConnectionState();
  ScopedDeviceStore? _scopedStore;
  bool _storageFailed = false;
  bool _preparingRepository = false;
  bool _legacyPromptShown = false;
  Timer? _idTimer;
  StreamSubscription? _links;
  bool _idReadFailed = true;
  bool _startingConnection = true;
  String? _bootstrapError;
  String? _deviceMigrationError;

  @override
  void initState() {
    super.initState();
    _initializeConnection();
    _idTimer = Timer.periodic(const Duration(seconds: 3), (_) => _refreshId());
  }

  Future<void> _applyBundledConnection(DeviceProfileScope preset) async {
    await setServerConfig(
        null,
        null,
        ServerConfig(
          idServer: preset.server,
          relayServer: preset.relayServer,
          apiServer: '',
          key: preset.publicKey,
        ));
    requireCurrentDeviceScope(preset, _readNativeScope());
  }

  Future<void> _initializeConnection() async {
    try {
      final preset = DeviceProfileScope.fromPublicProfileJson(
          await rootBundle.loadString('assets/XIXI-DEFAULT-CONNECTION.json'));
      final previous = DeviceProfileScope.fromPublicProfileJson(
          await rootBundle.loadString('assets/XIXI-PREVIOUS-CONNECTION.json'));
      if (mounted &&
          _canConfigureConnection &&
          shouldUseBundledConnection(bind.mainGetOptionsSync(), previous,
              currentDefault: preset)) {
        await _applyBundledConnection(preset);
      }
    } catch (_) {
      _bootstrapError = '默认连接服务暂未保存，请点连接服务重试';
    }
    if (!mounted) return;
    setState(() => _startingConnection = false);
    _links = listenUniLinks();
    await _prepareRepository();
    await _refreshId();
  }

  Future<void> _prepareRepository() async {
    if (_preparingRepository) return;
    _preparingRepository = true;
    if (mounted && _storageFailed) setState(() => _storageFailed = false);
    try {
      final directory = await getApplicationSupportDirectory();
      await directory.create(recursive: true);
      if (!mounted) return;
      _scopedStore = ScopedDeviceStore(
        storage: FileDeviceStorage(File(
            '${directory.path}${Platform.pathSeparator}${ScopedDeviceStore.storageKey}.json')),
        legacyStorage: FileDeviceStorage(File(
            '${directory.path}${Platform.pathSeparator}${DeviceRepository.storageKey}.json')),
      );
      _deviceMigrationError = null;
      try {
        await _scopedStore!.migrateBundledPortDevices(_readNativeScope());
      } catch (_) {
        _deviceMigrationError = '旧版设备列表暂未合并，原记录已保留，仍可输入 ID 连接';
      }
      await _refreshScope();
    } catch (_) {
      if (mounted) {
        _storageFailed = true;
        await _refreshScope();
      }
    } finally {
      _preparingRepository = false;
    }
  }

  DeviceProfileScope _readNativeScope() =>
      DeviceProfileScope.fromOptionsJson(bind.mainGetOptionsSync());

  Future<void> _refreshScope({bool forceReload = false}) async {
    if (_startingConnection) return;
    final store = _scopedStore;
    if (!mounted) return;
    setState(() {
      _connectionState.refresh(
        readScope: _readNativeScope,
        openRepository: (scope) {
          if (_deviceMigrationError != null &&
              previousBundledPortScope(scope) != null) {
            throw DeviceStorageException(_deviceMigrationError!);
          }
          if (store == null) {
            throw DeviceStorageException(_storageFailed
                ? '设备列表暂时无法打开，仍可输入 ID 连接'
                : '设备列表正在准备，仍可输入 ID 连接');
          }
          return store.repository(scope);
        },
        forceReload: forceReload,
      );
    });
    final scope = _connectionState.scope;
    if (scope != null && _connectionState.repository != null) {
      await _offerLegacyImport(scope);
    }
  }

  Future<void> _offerLegacyImport(DeviceProfileScope scope) async {
    if (_legacyPromptShown || !mounted) return;
    final store = _scopedStore!;
    _legacyPromptShown = true;
    try {
      final legacy = store.pendingLegacyDevices();
      if (legacy.isEmpty) return;
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('确认旧列表归属'),
          content: Text(
              '发现 ${legacy.length} 台旧版设备，旧文件没有记录服务器。\n\n请确认它们属于当前连接服务：\n${scope.server}\n公钥：${scope.publicKey}\n\n确认后复制到此服务的列表；已有同 ID 的记录保留当前名称，原文件完整保留。'),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: const Text('暂不导入')),
            FilledButton(
                onPressed: () => Navigator.pop(context, true),
                child: const Text('确认归属并导入')),
          ],
        ),
      );
      if (confirmed != true || !mounted) return;
      requireCurrentDeviceScope(scope, _readNativeScope());
      final result = await store.importLegacy(scope);
      if (!mounted) return;
      await _refreshScopeAfterImport(scope);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(
              '已导入 ${result.imported} 台设备，保留 ${result.retained} 条现有记录；旧文件仍保留。'),
        ));
      }
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(error is DeviceValidationException
              ? error.message
              : '旧列表未导入，原文件已保留。'),
        ));
      }
    }
  }

  Future<void> _refreshScopeAfterImport(DeviceProfileScope scope) async {
    await _refreshScope(forceReload: true);
  }

  Future<void> _refreshId() async {
    if (_startingConnection) return;
    await _refreshScope();
    try {
      await gFFI.serverModel.fetchID();
      if (mounted && _idReadFailed) setState(() => _idReadFailed = false);
    } catch (_) {
      if (mounted && !_idReadFailed) setState(() => _idReadFailed = true);
    }
  }

  @override
  void dispose() {
    _idTimer?.cancel();
    _links?.cancel();
    super.dispose();
  }

  void _openPage(PageShape page) {
    Navigator.of(context).push(MaterialPageRoute<void>(
        builder: (_) => Scaffold(
              appBar:
                  AppBar(title: Text(page.title), actions: page.appBarActions),
              body: page,
            )));
  }

  bool get _canConfigureConnection =>
      !bind.isDisableSettings() &&
      bind.mainGetBuildinOption(key: kOptionHideNetworkSetting) != 'Y' &&
      bind.mainGetBuildinOption(key: kOptionHideServerSetting) != 'Y';

  void _openConnectionSettings({ServerConfig? initial}) {
    if (!_canConfigureConnection) return;
    void onSaved(VoidCallback _) {
      if (mounted) {
        _bootstrapError = null;
        _refreshScope(forceReload: true);
      }
    }

    if (initial == null) {
      showServerSettings(gFFI.dialogManager, onSaved);
    } else {
      showServerSettingsWithValue(initial, gFFI.dialogManager, onSaved);
    }
  }

  Future<void> _showConnectionSetup() async {
    if (!_canConfigureConnection) return;
    DeviceProfileScope? testScope;
    try {
      testScope = DeviceProfileScope.fromPublicProfileJson(
          await rootBundle.loadString('assets/XIXI-DEFAULT-CONNECTION.json'));
    } catch (_) {
      // A missing preview preset still permits manual server configuration.
    }
    if (!mounted) return;
    if (testScope == null) {
      _openConnectionSettings();
      return;
    }
    final preset = testScope;
    final fillTestServer = await showModalBottomSheet<bool>(
      context: context,
      showDragHandle: true,
      builder: (context) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            const ListTile(
              contentPadding: EdgeInsets.zero,
              title: Text('配置连接服务',
                  style: TextStyle(fontSize: 20, fontWeight: FontWeight.w600)),
              subtitle: Text('安装后自动使用西西连接服务，可跨网络联测'),
            ),
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.router_outlined),
              title: const Text('使用西西默认连接服务'),
              subtitle: const Text('自动恢复，无需填写地址或公钥'),
              trailing: const Icon(Icons.chevron_right_rounded),
              onTap: () => Navigator.pop(context, true),
            ),
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.tune_rounded),
              title: const Text('编辑服务器设置'),
              subtitle: const Text('查看或修改已保存的地址和公钥'),
              trailing: const Icon(Icons.chevron_right_rounded),
              onTap: () => Navigator.pop(context, false),
            ),
          ]),
        ),
      ),
    );
    if (!mounted || fillTestServer == null) return;
    if (!fillTestServer) {
      _openConnectionSettings();
      return;
    }
    setState(() => _startingConnection = true);
    try {
      await _applyBundledConnection(preset);
      _bootstrapError = null;
    } catch (_) {
      _bootstrapError = '默认连接服务暂未保存，请重试';
    } finally {
      if (mounted) {
        setState(() => _startingConnection = false);
        await _refreshScope(forceReload: true);
      }
    }
  }

  Future<void> _retryDeviceStorage() async {
    if (_scopedStore == null || _deviceMigrationError != null) {
      await _prepareRepository();
    } else {
      await _refreshScope(forceReload: true);
    }
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
        animation: gFFI.serverModel,
        builder: (context, _) {
          final repository = _connectionState.repository;
          final scope = _connectionState.scope;
          final configured = !_startingConnection &&
              _bootstrapError == null &&
              _connectionState.canConnect;
          final server = gFFI.serverModel;
          final status = server.connectStatus;
          return XixiDeviceScreen(
            key: ValueKey(scope?.fingerprint ?? 'unconfigured'),
            repository: repository ?? _unconfiguredRepository,
            connectionConfigured: configured,
            connectionMessage: _startingConnection
                ? '正在准备西西连接服务'
                : _bootstrapError ??
                    _connectionState.profileError ??
                    '正在读取连接服务配置',
            onConfigureConnection:
                _canConfigureConnection ? _showConnectionSetup : null,
            savedDevicesAvailable: repository != null,
            savedDevicesMessage: _connectionState.storageError,
            onRetryDeviceStorage: _retryDeviceStorage,
            runtime: _idReadFailed || !configured
                ? const XixiRuntimeSnapshot()
                : XixiRuntimeSnapshot(
                    localId: server.serverId.text,
                    connectionStatus: status > 0
                        ? XixiConnectionStatus.ready
                        : status == 0
                            ? XixiConnectionStatus.connecting
                            : XixiConnectionStatus.unavailable,
                    sharingStarted: isAndroid ? server.isStart : null,
                  ),
            onConnect: (id, forceRelay) async {
              if (scope == null) {
                throw DeviceValidationException(
                    _connectionState.profileError ?? '请先配置连接服务');
              }
              requirePrivateDeviceTarget(id);
              try {
                requireCurrentDeviceScope(scope, _readNativeScope());
              } on DeviceValidationException {
                await _refreshScope();
                rethrow;
              }
              await connect(context, id, forceRelay: forceRelay);
            },
            onShowSharing: isAndroid && !bind.isOutgoingOnly()
                ? widget.onShowSharing ?? () => _openPage(XixiSharingPage())
                : null,
            onOpenSettings: bind.isDisableSettings()
                ? null
                : widget.onOpenSettings ?? () => _openPage(SettingsPage()),
          );
        },
      );
}

class _UnconfiguredDeviceStorage implements DeviceStorage {
  @override
  String read() => '';

  @override
  Future<void> write(String value) async {
    throw const DeviceStorageException('设备列表暂时无法保存，请重试');
  }
}
