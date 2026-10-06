import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../xixi/saved_devices.dart';
import '../xixi/xixi_device_screen.dart'
    show XixiRuntimeSnapshot, XixiConnectionStatus, XixiConnect;

class XixiDesktopDeviceScreen extends StatefulWidget {
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

  const XixiDesktopDeviceScreen({
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
  State<XixiDesktopDeviceScreen> createState() =>
      _XixiDesktopDeviceScreenState();
}

class _XixiDesktopDeviceScreenState extends State<XixiDesktopDeviceScreen> {
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
  void didUpdateWidget(covariant XixiDesktopDeviceScreen oldWidget) {
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
    _search.dispose();
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
    final all = widget.repository.devices;
    final query = _search.text.trim().toLowerCase();
    final devices = all
        .where((d) =>
            d.name.toLowerCase().contains(query) ||
            d.id.toLowerCase().contains(query))
        .toList();
    final storageError =
        !widget.savedDevicesAvailable && widget.connectionConfigured
            ? widget.savedDevicesMessage ?? '设备列表暂时无法打开，仍可输入 ID 连接'
            : _loadError;
    return ColoredBox(
        color: colors.background,
        child: LayoutBuilder(builder: (context, bounds) {
          return SingleChildScrollView(
              key: const Key('device-screen'),
              padding: const EdgeInsets.all(24),
              child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(children: [
                      Expanded(
                          child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                            Text('远程连接',
                                style: TextStyle(
                                    fontSize: 23,
                                    fontWeight: FontWeight.w600,
                                    color: colors.ink)),
                            const SizedBox(height: 4),
                            Text('通过设备 ID 连接电脑或手机',
                                style: TextStyle(
                                    fontSize: 13, color: colors.muted)),
                          ])),
                      if (widget.onOpenSettings != null)
                        IconButton(
                            tooltip: '设置',
                            onPressed: widget.onOpenSettings,
                            icon: Icon(Icons.tune_rounded, color: colors.muted))
                    ]),
                    const SizedBox(height: 20),
                    if (bounds.maxWidth >= 700)
                      Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Expanded(
                                flex: 3,
                                child: ConstrainedBox(
                                    constraints:
                                        const BoxConstraints(minHeight: 232),
                                    child: _connectionPanel(colors))),
                            const SizedBox(width: 18),
                            Expanded(
                                flex: 2,
                                child: ConstrainedBox(
                                    constraints:
                                        const BoxConstraints(minHeight: 232),
                                    child: _localPanel(colors))),
                          ])
                    else ...[
                      _connectionPanel(colors),
                      const SizedBox(height: 16),
                      _localPanel(colors)
                    ],
                    const SizedBox(height: 26),
                    _deviceTable(colors, devices, all.length, storageError,
                        bounds.maxWidth - 48),
                  ]));
        }));
  }

  final _search = TextEditingController();
  Widget _title(String label, _SilverColors colors) => Text(label,
      style: TextStyle(
          fontSize: 16, fontWeight: FontWeight.w600, color: colors.ink));
  Widget _connectionPanel(_SilverColors colors) => _surface(
      colors,
      Padding(
          padding: const EdgeInsets.all(20),
          child:
              Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              Icon(Icons.desktop_windows_outlined,
                  color: colors.accent, size: 20),
              const SizedBox(width: 10),
              Expanded(child: _title('连接远程设备', colors))
            ]),
            const SizedBox(height: 10),
            Text(
                widget.connectionConfigured
                    ? '输入对方 ID，按 Enter 或点击连接'
                    : widget.connectionMessage ?? '正在准备连接服务',
                style: TextStyle(fontSize: 13, color: colors.muted)),
            const SizedBox(height: 20),
            LayoutBuilder(builder: (context, bounds) {
              final input = Form(
                  key: _connectForm,
                  child: TextFormField(
                      key: const Key('connect-id'),
                      controller: _idController,
                      enabled: !_busy,
                      textInputAction: TextInputAction.go,
                      maxLength: 255,
                      style: TextStyle(fontSize: 17, color: colors.ink),
                      decoration: InputDecoration(
                          hintText: '设备 ID',
                          counterText: '',
                          filled: true,
                          fillColor: colors.background,
                          isDense: true,
                          contentPadding: const EdgeInsets.symmetric(
                              horizontal: 14, vertical: 16),
                          border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(8)),
                          enabledBorder: OutlineInputBorder(
                              borderSide: BorderSide(color: colors.line),
                              borderRadius: BorderRadius.circular(8))),
                      validator: (v) => _validateId(v ?? ''),
                      onFieldSubmitted: (_) => _submit()));
              final button = SizedBox(
                  width: widget.connectionConfigured ? 112 : 150,
                  child: XixiDesktopPrimaryButton(
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
                          : widget.connectionConfigured
                              ? _submit
                              : widget.onConfigureConnection));
              if (bounds.maxWidth >= 360) {
                return Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(child: input),
                      const SizedBox(width: 12),
                      button
                    ]);
              }
              return Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [input, const SizedBox(height: 12), button]);
            }),
            const SizedBox(height: 16),
            Text('首次连接需对方接受或验证接入密码',
                style: TextStyle(fontSize: 12, color: colors.muted)),
          ])));
  void _submit() {
    if (_connectForm.currentState?.validate() == true) {
      _connect(_idController.text);
    }
  }

  Widget _localPanel(_SilverColors colors) {
    String? id;
    try {
      id = normalizeDeviceId(widget.runtime.localId);
    } on DeviceValidationException {/* not yet available */}
    final canCopy = id != null && widget.connectionConfigured;
    final status = !widget.connectionConfigured
        ? '连接服务未配置'
        : switch (widget.runtime.connectionStatus) {
            XixiConnectionStatus.ready => '连接服务就绪',
            XixiConnectionStatus.connecting => '正在连接服务',
            XixiConnectionStatus.unavailable => '连接服务未就绪',
            XixiConnectionStatus.unknown => '正在读取服务状态'
          };
    return _surface(
        colors,
        Padding(
            padding: const EdgeInsets.all(20),
            child:
                Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              _title('允许连接此电脑', colors),
              const SizedBox(height: 12),
              Text('本机 ID',
                  style: TextStyle(fontSize: 12, color: colors.muted)),
              const SizedBox(height: 4),
              Row(children: [
                Expanded(
                    child: SelectableText(canCopy ? id : '正在读取…',
                        style: TextStyle(
                            fontSize: 24,
                            fontWeight: FontWeight.w600,
                            color: colors.ink))),
                IconButton(
                    tooltip: '复制本机 ID',
                    onPressed: canCopy
                        ? () async {
                            try {
                              await Clipboard.setData(ClipboardData(text: id!));
                              _message('本机 ID 已复制');
                            } catch (_) {
                              _message('复制失败，请手动选择 ID');
                            }
                          }
                        : null,
                    icon: Icon(Icons.copy_outlined,
                        size: 19, color: colors.muted))
              ]),
              const SizedBox(height: 12),
              Row(children: [
                Container(
                    width: 6,
                    height: 6,
                    decoration: BoxDecoration(
                        color: widget.runtime.connectionStatus ==
                                XixiConnectionStatus.ready
                            ? colors.accent
                            : colors.muted,
                        shape: BoxShape.circle)),
                const SizedBox(width: 8),
                Expanded(
                    child: Text(status,
                        style: TextStyle(fontSize: 12, color: colors.muted)))
              ]),
              if (widget.onShowSharing != null) ...[
                const SizedBox(height: 8),
                TextButton.icon(
                    onPressed: widget.onShowSharing,
                    icon: const Icon(Icons.screen_share_outlined, size: 18),
                    label: const Text('共享与接入设置'))
              ],
            ])));
  }

  Widget _deviceTable(_SilverColors colors, List<SavedDevice> devices,
      int count, String? error, double width) {
    final compact = width < 570;
    final canAdd = !_busy &&
        _loadError == null &&
        widget.savedDevicesAvailable &&
        widget.connectionConfigured;
    return _surface(
        colors,
        Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Padding(
              padding: const EdgeInsets.fromLTRB(18, 14, 18, 14),
              child: Wrap(
                  spacing: 16,
                  runSpacing: 12,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    SizedBox(
                        width: 140,
                        child: Row(children: [
                          _title('我的设备', colors),
                          const SizedBox(width: 8),
                          Text('$count',
                              style:
                                  TextStyle(fontSize: 13, color: colors.muted))
                        ])),
                    SizedBox(
                        width: width < 410 ? width - 36 : 230,
                        child: TextField(
                            key: const Key('search-devices'),
                            controller: _search,
                            onChanged: (_) => setState(() {}),
                            style: TextStyle(fontSize: 13, color: colors.ink),
                            decoration: InputDecoration(
                                hintText: '搜索名称或 ID',
                                isDense: true,
                                prefixIcon: Icon(Icons.search_rounded,
                                    size: 19, color: colors.muted),
                                contentPadding: const EdgeInsets.symmetric(
                                    vertical: 12, horizontal: 12),
                                border: OutlineInputBorder(
                                    borderRadius: BorderRadius.circular(8)),
                                enabledBorder: OutlineInputBorder(
                                    borderSide: BorderSide(color: colors.line),
                                    borderRadius: BorderRadius.circular(8))))),
                    OutlinedButton.icon(
                        key: const Key('add-device'),
                        onPressed: canAdd ? () => _editDevice() : null,
                        icon: const Icon(Icons.add_rounded, size: 18),
                        label: const Text('添加设备')),
                  ])),
          Container(
              color: colors.background,
              padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 11),
              child: Row(children: [
                Expanded(
                    flex: 3,
                    child: Text(compact ? '设备 / ID' : '设备名称',
                        style: TextStyle(fontSize: 12, color: colors.muted))),
                if (!compact)
                  Expanded(
                      flex: 2,
                      child: Text('设备 ID',
                          style: TextStyle(fontSize: 12, color: colors.muted))),
                SizedBox(
                    width: compact ? 98 : 150,
                    child: Text('操作',
                        style: TextStyle(fontSize: 12, color: colors.muted)))
              ])),
          if (error != null)
            Padding(
                padding: const EdgeInsets.all(28),
                child: Column(children: [
                  Text(error, style: TextStyle(color: colors.muted)),
                  TextButton(
                      onPressed:
                          widget.onRetryDeviceStorage ?? () => setState(_load),
                      child: const Text('重新读取'))
                ]))
          else if (devices.isEmpty)
            Padding(
                padding:
                    const EdgeInsets.symmetric(horizontal: 24, vertical: 40),
                child: Column(children: [
                  Icon(Icons.devices_outlined, size: 30, color: colors.muted),
                  const SizedBox(height: 12),
                  Text(_search.text.trim().isEmpty ? '还没有添加设备' : '没有找到匹配的设备',
                      style: TextStyle(
                          color: colors.ink, fontWeight: FontWeight.w500)),
                  const SizedBox(height: 6),
                  Text(
                      _search.text.trim().isEmpty
                          ? '点击“添加设备”，保存常用设备的名称和 ID'
                          : '试试其它名称或 ID',
                      style: TextStyle(fontSize: 12, color: colors.muted)),
                ]))
          else
            for (final device in devices) ...[
              Material(
                  color: colors.surface,
                  child: MouseRegion(
                      cursor: SystemMouseCursors.basic,
                      child: Padding(
                          key: ValueKey('saved-${device.id}'),
                          padding: const EdgeInsets.symmetric(
                              horizontal: 18, vertical: 9),
                          child: Row(children: [
                            Expanded(
                                flex: 3,
                                child: Row(children: [
                                  Icon(Icons.devices_rounded,
                                      size: 20, color: colors.muted),
                                  const SizedBox(width: 10),
                                  Expanded(
                                      child: Column(
                                          crossAxisAlignment:
                                              CrossAxisAlignment.start,
                                          children: [
                                        Text(device.name,
                                            maxLines: 1,
                                            overflow: TextOverflow.ellipsis,
                                            style: TextStyle(
                                                fontSize: 14,
                                                color: colors.ink)),
                                        if (compact) ...[
                                          const SizedBox(height: 4),
                                          Text(device.id,
                                              maxLines: 1,
                                              overflow: TextOverflow.ellipsis,
                                              style: TextStyle(
                                                  fontSize: 12,
                                                  color: colors.muted))
                                        ],
                                      ]))
                                ])),
                            if (!compact)
                              Expanded(
                                  flex: 2,
                                  child: Text(device.id,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: TextStyle(
                                          fontSize: 13, color: colors.muted))),
                            SizedBox(
                                width: compact ? 98 : 150,
                                child: Row(children: [
                                  if (compact)
                                    IconButton(
                                        tooltip: '连接 ${device.name}',
                                        onPressed: _busy
                                            ? null
                                            : () => _connect(device.id),
                                        icon: Icon(Icons.arrow_forward_rounded,
                                            color: colors.accent, size: 20))
                                  else
                                    Expanded(
                                        child: TextButton.icon(
                                            onPressed: _busy
                                                ? null
                                                : () => _connect(device.id),
                                            icon: const Icon(
                                                Icons.arrow_forward_rounded,
                                                size: 16),
                                            label: const Text('连接'))),
                                  PopupMenuButton<String>(
                                      key: ValueKey('menu-${device.id}'),
                                      tooltip: '管理 ${device.name}',
                                      enabled: !_busy,
                                      icon: Icon(Icons.more_horiz_rounded,
                                          color: colors.muted, size: 20),
                                      itemBuilder: (_) => const [
                                            PopupMenuItem(
                                                value: 'edit',
                                                child: Text('编辑名称和 ID')),
                                            PopupMenuItem(
                                                value: 'remove',
                                                child: Text('移除设备'))
                                          ],
                                      onSelected: (action) {
                                        if (action == 'edit') {
                                          _editDevice(device);
                                        }
                                        if (action == 'remove') {
                                          _removeDevice(device);
                                        }
                                      }),
                                ])),
                          ])))),
              Divider(height: 1, color: colors.line),
            ],
        ]));
  }

  Widget _surface(_SilverColors colors, Widget child) => Container(
        decoration: BoxDecoration(
          color: colors.surface,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: colors.line),
          boxShadow: [
            BoxShadow(
                color: colors.shadow,
                blurRadius: 10,
                offset: const Offset(0, 3))
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
            SizedBox(
                width: 130,
                child: XixiDesktopPrimaryButton(
                    key: const Key('save-device'),
                    label: _saving ? '保存中…' : '保存',
                    icon: Icons.check_rounded,
                    onPressed: _saving ? null : _save)),
          ],
        ),
      );
}

class XixiDesktopPrimaryButton extends StatefulWidget {
  final String label;
  final IconData icon;
  final VoidCallback? onPressed;
  const XixiDesktopPrimaryButton(
      {super.key, required this.label, required this.icon, this.onPressed});
  @override
  State<XixiDesktopPrimaryButton> createState() =>
      _XixiDesktopPrimaryButtonState();
}

class _XixiDesktopPrimaryButtonState extends State<XixiDesktopPrimaryButton> {
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
                constraints: const BoxConstraints(minHeight: 46),
                padding:
                    const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                child:
                    Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                  Flexible(
                      child: Text(widget.label,
                          style: TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w600,
                              color:
                                  enabled ? colors.buttonInk : colors.muted))),
                  const SizedBox(width: 8),
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
