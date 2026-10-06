import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'saved_devices.dart';

enum XixiConnectionStatus { unknown, connecting, ready, unavailable }

class XixiRuntimeSnapshot {
  final String localId;
  final XixiConnectionStatus connectionStatus;
  final bool? sharingStarted;

  const XixiRuntimeSnapshot({
    this.localId = '',
    this.connectionStatus = XixiConnectionStatus.unknown,
    this.sharingStarted,
  });
}

typedef XixiConnect = Future<void> Function(String id, bool forceRelay);

class XixiDeviceScreen extends StatefulWidget {
  final DeviceRepository repository;
  final XixiRuntimeSnapshot runtime;
  final XixiConnect onConnect;
  final VoidCallback? onShowSharing;
  final VoidCallback? onOpenSettings;
  final bool connectionConfigured;
  final String? connectionMessage;
  final VoidCallback? onConfigureConnection;
  final bool savedDevicesAvailable;
  final String? savedDevicesMessage;
  final VoidCallback? onRetryDeviceStorage;

  const XixiDeviceScreen({
    super.key,
    required this.repository,
    required this.onConnect,
    this.runtime = const XixiRuntimeSnapshot(),
    this.onShowSharing,
    this.onOpenSettings,
    this.connectionConfigured = true,
    this.connectionMessage,
    this.onConfigureConnection,
    this.savedDevicesAvailable = true,
    this.savedDevicesMessage,
    this.onRetryDeviceStorage,
  });

  @override
  State<XixiDeviceScreen> createState() => _XixiDeviceScreenState();
}

class _XixiDeviceScreenState extends State<XixiDeviceScreen> {
  final _idController = TextEditingController();
  final _connectForm = GlobalKey<FormState>();
  bool _busy = false;
  String? _loadError;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void didUpdateWidget(covariant XixiDeviceScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.repository != widget.repository) _load();
  }

  void _load() {
    try {
      widget.repository.load();
      _loadError = null;
    } catch (_) {
      _loadError = '设备列表暂时无法读取，原记录已保留';
    }
  }

  @override
  void dispose() {
    _idController.dispose();
    super.dispose();
  }

  void _message(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _connect(String value) async {
    if (_busy) return;
    if (!widget.connectionConfigured) {
      _message(widget.connectionMessage ?? '请先配置连接服务');
      return;
    }
    DeviceConnectionRequest request;
    try {
      request = DeviceConnectionRequest.parse(value);
    } on DeviceValidationException catch (error) {
      _message(error.message);
      return;
    }
    FocusScope.of(context).unfocus();
    setState(() => _busy = true);
    try {
      await widget.onConnect(request.id, request.forceRelay);
      try {
        if (!widget.savedDevicesAvailable || _loadError != null) {
          throw const DeviceStorageException('设备列表不可用');
        }
        await widget.repository.rememberConnection(request.id);
        if (mounted) setState(() {});
      } catch (_) {
        _message('连接已发起，但设备记录未保存，请检查设备列表');
      }
    } on DeviceValidationException catch (error) {
      _message(error.message);
    } catch (_) {
      _message('连接暂时无法发起，请稍后重试');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _editDevice([SavedDevice? device]) async {
    if (_busy || _loadError != null || !widget.savedDevicesAvailable) return;
    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (_) => _DeviceEditorDialog(
        device: device,
        repository: widget.repository,
      ),
    );
    if (mounted) setState(() {});
  }

  Future<void> _removeDevice(SavedDevice device) async {
    if (_busy || _loadError != null || !widget.savedDevicesAvailable) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('移除设备？'),
        content: Text('将“${device.name}”从本机列表移除。'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('取消')),
          TextButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('移除')),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    setState(() => _busy = true);
    try {
      await widget.repository.remove(device.id);
    } catch (_) {
      _message('移除失败，请重试；设备列表未更改');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  String? _validateId(String value) {
    try {
      DeviceConnectionRequest.parse(value);
      return null;
    } on DeviceValidationException catch (error) {
      return error.message;
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = _SilverColors(Theme.of(context).brightness);
    final devices = widget.repository.devices;
    final storageError =
        !widget.savedDevicesAvailable && widget.connectionConfigured
            ? widget.savedDevicesMessage ?? '设备列表暂时无法打开，仍可输入 ID 连接'
            : _loadError;
    return ColoredBox(
      color: colors.background,
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 640),
          child: ListView(
            key: const Key('device-screen'),
            padding: const EdgeInsets.fromLTRB(20, 24, 20, 32),
            children: [
              Row(children: [
                _BrandMark(colors: colors),
                const SizedBox(width: 12),
                Expanded(
                    child: Text('设备',
                        style: TextStyle(
                            fontSize: 27,
                            fontWeight: FontWeight.w600,
                            color: colors.ink))),
                if (widget.onOpenSettings != null)
                  IconButton(
                      tooltip: '设置',
                      onPressed: widget.onOpenSettings,
                      icon: Icon(Icons.tune_rounded, color: colors.muted)),
              ]),
              const SizedBox(height: 24),
              _surface(
                  colors,
                  Padding(
                    padding: const EdgeInsets.all(20),
                    child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('连接设备',
                              style: TextStyle(
                                  fontSize: 20,
                                  fontWeight: FontWeight.w600,
                                  color: colors.ink)),
                          const SizedBox(height: 7),
                          Text(
                              widget.connectionConfigured
                                  ? '输入对方 ID，打开远程画面'
                                  : widget.connectionMessage ??
                                      '先配置连接服务，再连接你的设备',
                              style: TextStyle(color: colors.muted)),
                          const SizedBox(height: 24),
                          Form(
                            key: _connectForm,
                            child: TextFormField(
                              key: const Key('connect-id'),
                              controller: _idController,
                              enabled: !_busy,
                              keyboardType: TextInputType.text,
                              textInputAction: TextInputAction.go,
                              maxLength: 255,
                              style: TextStyle(
                                  fontSize: 21,
                                  letterSpacing: 1,
                                  color: colors.ink),
                              decoration: InputDecoration(
                                labelText: '设备 ID',
                                hintText: '输入对方设备 ID',
                                counterText: '',
                                prefixIcon: Icon(Icons.devices_rounded,
                                    color: colors.muted),
                                filled: true,
                                fillColor: colors.background,
                                border: OutlineInputBorder(
                                    borderRadius: BorderRadius.circular(10)),
                                enabledBorder: OutlineInputBorder(
                                    borderSide: BorderSide(color: colors.line),
                                    borderRadius: BorderRadius.circular(10)),
                              ),
                              validator: (value) => _validateId(value ?? ''),
                              onFieldSubmitted: (_) {
                                if (_connectForm.currentState!.validate()) {
                                  _connect(_idController.text);
                                }
                              },
                            ),
                          ),
                          const SizedBox(height: 16),
                          XixiPrimaryButton(
                            key: const Key('connect-button'),
                            label: _busy
                                ? '处理中…'
                                : widget.connectionConfigured
                                    ? '连接'
                                    : '配置连接服务',
                            icon: widget.connectionConfigured
                                ? Icons.arrow_forward_rounded
                                : Icons.tune_rounded,
                            onPressed: _busy
                                ? null
                                : !widget.connectionConfigured
                                    ? widget.onConfigureConnection
                                    : () {
                                        if (_connectForm.currentState!
                                            .validate()) {
                                          _connect(_idController.text);
                                        }
                                      },
                          ),
                        ]),
                  )),
              const SizedBox(height: 20),
              _localDevice(colors),
              const SizedBox(height: 26),
              Row(children: [
                Expanded(
                    child: Text('我的设备',
                        style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.w600,
                            color: colors.ink))),
                TextButton.icon(
                  key: const Key('add-device'),
                  onPressed: _busy ||
                          _loadError != null ||
                          !widget.savedDevicesAvailable ||
                          !widget.connectionConfigured
                      ? null
                      : () => _editDevice(),
                  icon: const Icon(Icons.add_rounded, size: 20),
                  label: const Text('添加'),
                ),
              ]),
              const SizedBox(height: 8),
              if (storageError != null)
                _surface(
                    colors,
                    Padding(
                      padding: const EdgeInsets.all(20),
                      child: Column(children: [
                        Text(storageError,
                            style: TextStyle(color: colors.muted)),
                        TextButton(
                            onPressed: widget.onRetryDeviceStorage ??
                                () => setState(_load),
                            child: const Text('重新读取')),
                      ]),
                    ))
              else if (devices.isEmpty)
                _surface(
                    colors,
                    Padding(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 20, vertical: 28),
                      child: Column(children: [
                        Icon(Icons.add_to_photos_outlined,
                            size: 32, color: colors.muted),
                        const SizedBox(height: 14),
                        Text('还没有添加设备',
                            style: TextStyle(
                                fontWeight: FontWeight.w500,
                                color: colors.ink)),
                        const SizedBox(height: 7),
                        Text(
                            widget.connectionConfigured
                                ? '给常用设备起个名称，下次直接连接'
                                : '配置连接服务后，可以添加设备并自由命名',
                            textAlign: TextAlign.center,
                            style: TextStyle(color: colors.muted)),
                      ]),
                    ))
              else
                for (final device in devices) ...[
                  _deviceCard(device, colors),
                  const SizedBox(height: 10),
                ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _localDevice(_SilverColors colors) {
    final runtime = widget.runtime;
    var canCopy = false;
    var localId = '';
    try {
      localId = normalizeDeviceId(runtime.localId);
      canCopy = widget.connectionConfigured;
    } on DeviceValidationException {
      canCopy = false;
    }
    final status = !widget.connectionConfigured
        ? '连接服务未配置'
        : switch (runtime.connectionStatus) {
            XixiConnectionStatus.ready => '连接服务就绪',
            XixiConnectionStatus.connecting => '正在连接服务',
            XixiConnectionStatus.unavailable => '连接服务未就绪',
            XixiConnectionStatus.unknown => '正在读取服务状态',
          };
    return _surface(
        colors,
        Padding(
          padding: const EdgeInsets.all(18),
          child:
              Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Wrap(
                spacing: 12,
                runSpacing: 8,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  Row(mainAxisSize: MainAxisSize.min, children: [
                    Icon(Icons.phonelink_outlined,
                        color: colors.muted, size: 21),
                    const SizedBox(width: 9),
                    Text('本机 ID', style: TextStyle(color: colors.muted)),
                  ]),
                  Text(status,
                      style: TextStyle(fontSize: 12, color: colors.muted)),
                ]),
            const SizedBox(height: 9),
            Row(children: [
              Expanded(
                  child: SelectableText(
                      canCopy
                          ? formatDeviceId(localId)
                          : widget.connectionConfigured
                              ? '正在读取…'
                              : '配置后获取 ID',
                      style: TextStyle(
                          fontSize: 22,
                          fontWeight: FontWeight.w600,
                          color: colors.ink))),
              IconButton(
                tooltip: '复制本机 ID',
                onPressed: canCopy
                    ? () async {
                        try {
                          await Clipboard.setData(ClipboardData(text: localId));
                          _message('本机 ID 已复制');
                        } catch (_) {
                          _message('复制失败，请手动选择 ID');
                        }
                      }
                    : null,
                icon: const Icon(Icons.copy_outlined, size: 20),
              ),
            ]),
            if (widget.onShowSharing != null) ...[
              const SizedBox(height: 5),
              const Divider(height: 20),
              Wrap(
                  spacing: 12,
                  runSpacing: 4,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    Text(
                      runtime.sharingStarted == null
                          ? '查看共享屏幕状态'
                          : runtime.sharingStarted!
                              ? '共享服务运行中'
                              : '共享服务未启动',
                      style: TextStyle(fontSize: 13, color: colors.muted),
                    ),
                    TextButton(
                        onPressed: widget.onShowSharing,
                        child: const Text('共享屏幕')),
                  ]),
            ],
          ]),
        ));
  }

  Widget _deviceCard(SavedDevice device, _SilverColors colors) {
    return _surface(
        colors,
        Padding(
          key: ValueKey('saved-${device.id}'),
          padding: const EdgeInsets.fromLTRB(14, 10, 6, 10),
          child: Row(children: [
            Container(
              width: 42,
              height: 42,
              decoration: BoxDecoration(
                  border: Border.all(color: colors.line),
                  borderRadius: BorderRadius.circular(12)),
              child: Icon(Icons.devices_rounded, color: colors.muted, size: 23),
            ),
            const SizedBox(width: 12),
            Expanded(
                child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                  Text(device.name,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w600,
                          color: colors.ink)),
                  const SizedBox(height: 4),
                  Text('ID ${formatDeviceId(device.id)}',
                      style: TextStyle(fontSize: 12, color: colors.muted)),
                ])),
            IconButton(
              tooltip: '连接 ${device.name}',
              onPressed: _busy ? null : () => _connect(device.id),
              icon: Icon(Icons.arrow_forward_rounded,
                  color: _busy ? colors.muted : colors.accent),
            ),
            PopupMenuButton<String>(
              key: ValueKey('menu-${device.id}'),
              tooltip: '管理 ${device.name}',
              enabled: !_busy,
              icon: Icon(Icons.more_vert_rounded, color: colors.muted),
              itemBuilder: (_) => const [
                PopupMenuItem(value: 'edit', child: Text('编辑名称和 ID')),
                PopupMenuItem(value: 'remove', child: Text('移除设备')),
              ],
              onSelected: (action) {
                if (action == 'edit') _editDevice(device);
                if (action == 'remove') _removeDevice(device);
              },
            ),
          ]),
        ));
  }

  Widget _surface(_SilverColors colors, Widget child) => Container(
        decoration: BoxDecoration(
          color: colors.surface,
          borderRadius: BorderRadius.circular(15),
          border: Border.all(color: colors.line),
          boxShadow: [
            BoxShadow(
                color: colors.shadow,
                blurRadius: 17,
                offset: const Offset(0, 6))
          ],
        ),
        child: child,
      );
}

class _DeviceEditorDialog extends StatefulWidget {
  final SavedDevice? device;
  final DeviceRepository repository;
  const _DeviceEditorDialog({required this.device, required this.repository});
  @override
  State<_DeviceEditorDialog> createState() => _DeviceEditorDialogState();
}

class _DeviceEditorDialogState extends State<_DeviceEditorDialog> {
  final _form = GlobalKey<FormState>();
  late final TextEditingController _id;
  late final TextEditingController _name;
  bool _saving = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _id = TextEditingController(text: widget.device?.id ?? '');
    _name = TextEditingController(text: widget.device?.name ?? '');
  }

  @override
  void dispose() {
    _id.dispose();
    _name.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (_saving || !_form.currentState!.validate()) return;
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      final next = SavedDevice(id: _id.text, name: _name.text);
      final device = widget.device;
      if (device == null) {
        await widget.repository.add(next);
      } else {
        await widget.repository.update(device.id, next);
      }
      if (mounted) {
        setState(() => _saving = false);
        Navigator.pop(context);
      }
    } catch (error) {
      if (mounted) {
        setState(() {
          _saving = false;
          _error = error is DeviceValidationException
              ? error.message
              : '保存失败，请重试；设备列表未更改';
        });
      }
    }
  }

  String? _validate(String value, String Function(String) normalize) {
    try {
      normalize(value);
      return null;
    } on DeviceValidationException catch (error) {
      return error.message;
    }
  }

  @override
  Widget build(BuildContext context) => PopScope(
        canPop: !_saving,
        child: AlertDialog(
          title: Text(widget.device == null ? '添加设备' : '编辑设备'),
          content: SingleChildScrollView(
            child: Form(
              key: _form,
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                TextFormField(
                  key: const Key('device-name'),
                  controller: _name,
                  enabled: !_saving,
                  autofocus: true,
                  maxLength: 50,
                  textInputAction: TextInputAction.next,
                  decoration: const InputDecoration(labelText: '设备名称'),
                  validator: (value) =>
                      _validate(value ?? '', normalizeDeviceName),
                ),
                const SizedBox(height: 12),
                TextFormField(
                  key: const Key('device-id'),
                  controller: _id,
                  enabled: !_saving,
                  keyboardType: TextInputType.text,
                  textInputAction: TextInputAction.done,
                  maxLength: 253,
                  decoration: const InputDecoration(labelText: '设备 ID'),
                  validator: (value) =>
                      _validate(value ?? '', normalizeDeviceId),
                  onFieldSubmitted: (_) => _save(),
                ),
                if (_error != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 12),
                    child: Text(_error!,
                        style: TextStyle(
                            color: Theme.of(context).colorScheme.error)),
                  ),
              ]),
            ),
          ),
          actions: [
            TextButton(
                onPressed: _saving ? null : () => Navigator.pop(context),
                child: const Text('取消')),
            FilledButton(
                key: const Key('save-device'),
                onPressed: _saving ? null : _save,
                child: Text(_saving ? '保存中…' : '保存')),
          ],
        ),
      );
}

class _BrandMark extends StatelessWidget {
  final _SilverColors colors;
  const _BrandMark({required this.colors});
  @override
  Widget build(BuildContext context) => Container(
        width: 35,
        height: 35,
        decoration: BoxDecoration(
          gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [colors.buttonTop, colors.buttonBottom]),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Icon(Icons.sync_alt_rounded, color: colors.buttonInk, size: 23),
      );
}

class XixiPrimaryButton extends StatefulWidget {
  final String label;
  final IconData icon;
  final VoidCallback? onPressed;
  const XixiPrimaryButton(
      {super.key, required this.label, required this.icon, this.onPressed});
  @override
  State<XixiPrimaryButton> createState() => _XixiPrimaryButtonState();
}

class _XixiPrimaryButtonState extends State<XixiPrimaryButton> {
  bool _pressed = false;
  @override
  Widget build(BuildContext context) {
    final colors = _SilverColors(Theme.of(context).brightness);
    final enabled = widget.onPressed != null;
    return Semantics(
      button: true,
      enabled: enabled,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 110),
        transform: Matrix4.translationValues(0, _pressed ? 1 : 0, 0),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(11),
          boxShadow: enabled
              ? [
                  BoxShadow(
                      color: colors.shadow,
                      blurRadius: _pressed ? 2 : 9,
                      offset: Offset(0, _pressed ? 1 : 4))
                ]
              : [],
        ),
        child: Material(
          color: Colors.transparent,
          borderRadius: BorderRadius.circular(11),
          clipBehavior: Clip.antiAlias,
          child: Ink(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: enabled
                      ? [colors.buttonTop, colors.buttonBottom]
                      : [colors.line, colors.line]),
              border:
                  Border.all(color: enabled ? colors.buttonEdge : colors.line),
              borderRadius: BorderRadius.circular(11),
            ),
            child: InkWell(
              onTap: widget.onPressed,
              onHighlightChanged: (value) => setState(() => _pressed = value),
              splashColor: Colors.white.withOpacity(0.15),
              highlightColor: Colors.black.withOpacity(0.10),
              child: Container(
                constraints: const BoxConstraints(minHeight: 52),
                padding:
                    const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                child:
                    Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                  Flexible(
                      child: Text(widget.label,
                          style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w600,
                              color:
                                  enabled ? colors.buttonInk : colors.muted))),
                  const SizedBox(width: 12),
                  Icon(widget.icon,
                      size: 21,
                      color: enabled ? colors.buttonInk : colors.muted),
                ]),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _SilverColors {
  final bool dark;
  _SilverColors(Brightness brightness) : dark = brightness == Brightness.dark;
  Color get background => Color(dark ? 0xff141822 : 0xfff6f7fa);
  Color get surface => Color(dark ? 0xff202632 : 0xffffffff);
  Color get ink => Color(dark ? 0xfff2f5fc : 0xff222c40);
  Color get muted => Color(dark ? 0xffadb8cf : 0xff647085);
  Color get line => Color(dark ? 0xff3a4455 : 0xffdde2eb);
  Color get accent => Color(dark ? 0xffaec7ff : 0xff245bea);
  Color get buttonTop => Color(dark ? 0xffc4d7ff : 0xff3874ff);
  Color get buttonBottom => Color(dark ? 0xff9eb8ef : 0xff174bd2);
  Color get buttonEdge => Color(dark ? 0xffcbdcff : 0xff174aca);
  Color get buttonInk => Color(dark ? 0xff172b50 : 0xffffffff);
  Color get shadow => Color(dark ? 0x55000000 : 0x1834466b);
}
