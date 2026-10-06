import 'dart:convert';

class DeviceValidationException implements Exception {
  final String message;
  const DeviceValidationException(this.message);
  @override
  String toString() => message;
}

class DeviceStorageException implements Exception {
  final String message;
  const DeviceStorageException(this.message);
  @override
  String toString() => message;
}

class DeviceConnectionRequest {
  final String id;
  final bool forceRelay;

  const DeviceConnectionRequest(this.id, {this.forceRelay = false});

  factory DeviceConnectionRequest.parse(String input) {
    var id = input.trim();
    final relay = id.endsWith('/r') || id.endsWith(r'\r');
    if (relay) id = id.substring(0, id.length - 2);
    return DeviceConnectionRequest(normalizeDeviceId(id), forceRelay: relay);
  }
}

String normalizeDeviceId(String input) {
  var id = input.trim();
  if (RegExp(r'^[0-9]+(?: +[0-9]+)*$').hasMatch(id)) {
    id = id.replaceAll(' ', '');
  }
  final invalid = RegExp(
      r'[\x00-\x20\x7f-\x9f\u00a0\u1680\u2000-\u200a\u2028\u2029\u202f\u205f\u3000"<>/\\|?*]');
  if (id.isEmpty || utf8.encode(id).length > 253 || invalid.hasMatch(id)) {
    throw const DeviceValidationException('请输入有效的设备 ID');
  }
  return id;
}

String normalizeDeviceName(String input) {
  final name = input.trim();
  if (name.isEmpty) {
    throw const DeviceValidationException('请给设备起个名称');
  }
  if (name.runes.length > 50 || RegExp(r'[\x00-\x1f\x7f]').hasMatch(name)) {
    throw const DeviceValidationException('设备名称应在 50 字以内，且不含换行');
  }
  return name;
}

String formatDeviceId(String id) {
  if (!RegExp(r'^[0-9]+$').hasMatch(id)) return id;
  return id.replaceAllMapped(RegExp(r'\d(?=(\d{3})+$)'), (m) => '${m[0]} ');
}

class SavedDevice {
  final String id;
  final String name;

  const SavedDevice._(this.id, this.name);

  factory SavedDevice({required String id, required String name}) {
    return SavedDevice._(normalizeDeviceId(id), normalizeDeviceName(name));
  }

  Map<String, String> toJson() => {'id': id, 'name': name};
}

abstract class DeviceStorage {
  String read();
  Future<void> write(String value);
}

class DeviceRepository {
  static const storageKey = 'xixi-saved-devices-v1';
  final DeviceStorage storage;
  List<SavedDevice> _devices = [];
  bool _loaded = false;
  bool _saving = false;

  DeviceRepository(this.storage);

  List<SavedDevice> get devices => List.unmodifiable(_devices);

  void load() {
    final value = storage.read();
    if (value.isEmpty) {
      _devices = [];
      _loaded = true;
      return;
    }
    try {
      final json = jsonDecode(value);
      if (json is! Map ||
          json['schema_version'] != 1 ||
          json['devices'] is! List) {
        throw const FormatException();
      }
      final records = json['devices'] as List;
      if (records.length > 1000) throw const FormatException();
      final loaded = <SavedDevice>[];
      final ids = <String>{};
      for (final record in records) {
        if (record is! Map ||
            record['id'] is! String ||
            record['name'] is! String) {
          throw const FormatException();
        }
        final device = SavedDevice(id: record['id'], name: record['name']);
        if (!ids.add(device.id)) throw const FormatException();
        loaded.add(device);
      }
      _devices = loaded;
      _loaded = true;
    } catch (_) {
      throw const DeviceStorageException('设备列表暂时无法读取，原记录已保留');
    }
  }

  Future<void> add(SavedDevice device) async {
    _checkLoaded();
    if (_devices.length >= 1000) {
      throw const DeviceValidationException('设备列表已满');
    }
    _checkDuplicate(device.id);
    await _commit([..._devices, device]);
  }

  /// Remember a submitted connection without replacing the user's device name.
  Future<void> rememberConnection(String input) async {
    _checkLoaded();
    final id = normalizeDeviceId(input);
    if (_devices.any((device) => device.id == id)) return;
    final name = String.fromCharCodes('设备 $id'.runes.take(50));
    await add(SavedDevice(id: id, name: name));
  }

  Future<void> update(String originalId, SavedDevice device) async {
    _checkLoaded();
    final index = _devices.indexWhere((item) => item.id == originalId);
    if (index < 0) throw const DeviceValidationException('这台设备已从列表移除');
    _checkDuplicate(device.id, except: originalId);
    final next = [..._devices];
    next[index] = device;
    await _commit(next);
  }

  Future<void> remove(String id) async {
    _checkLoaded();
    if (!_devices.any((item) => item.id == id)) return;
    await _commit(_devices.where((item) => item.id != id).toList());
  }

  void _checkLoaded() {
    if (!_loaded) throw const DeviceStorageException('请先读取设备列表');
  }

  void _checkDuplicate(String id, {String? except}) {
    if (_devices.any((item) => item.id == id && item.id != except)) {
      throw const DeviceValidationException('这个 ID 已在设备列表中');
    }
  }

  Future<void> _commit(List<SavedDevice> next) async {
    if (_saving) throw const DeviceStorageException('正在保存，请稍后再试');
    _saving = true;
    try {
      await storage.write(jsonEncode({
        'schema_version': 1,
        'devices': next.map((item) => item.toJson()).toList(),
      }));
      _devices = next;
    } finally {
      _saving = false;
    }
  }
}
