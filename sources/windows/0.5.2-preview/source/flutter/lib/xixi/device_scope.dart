import 'dart:convert';

import 'private_connection_profile.dart';
import 'saved_devices.dart';

class DeviceProfileScope {
  final String server;
  final String relayServer;
  final String publicKey;

  DeviceProfileScope({
    required String server,
    required String relayServer,
    required String publicKey,
  })  : server = server.trim().toLowerCase(),
        relayServer = relayServer.trim().toLowerCase(),
        publicKey = _canonicalKey(server, publicKey);

  factory DeviceProfileScope.fromOptionsJson(String value) {
    dynamic options;
    try {
      options = jsonDecode(value);
    } on FormatException {
      throw const DeviceValidationException('连接服务配置暂时无法读取');
    }
    if (options is! Map) throw const DeviceValidationException('连接服务配置暂时无法读取');
    String option(String name) {
      final value = options[name] ?? '';
      if (value is! String) {
        throw const DeviceValidationException('连接服务配置暂时无法读取');
      }
      return value;
    }

    return DeviceProfileScope(
      server: option('custom-rendezvous-server'),
      relayServer: option('relay-server'),
      publicKey: option('key'),
    );
  }

  factory DeviceProfileScope.fromPublicProfileJson(String value) {
    dynamic profile;
    try {
      profile = jsonDecode(value);
    } on FormatException {
      throw const DeviceValidationException('当前测试服务配置暂时无法读取');
    }
    const fields = {'schemaVersion', 'idServer', 'relayServer', 'publicKey'};
    if (profile is! Map ||
        profile['schemaVersion'] is! int ||
        profile['schemaVersion'] != 1 ||
        profile.keys.toSet().difference(fields).isNotEmpty ||
        !fields.every(profile.containsKey) ||
        profile['idServer'] is! String ||
        profile['relayServer'] is! String ||
        profile['publicKey'] is! String) {
      throw const DeviceValidationException('当前测试服务配置暂时无法读取');
    }
    return DeviceProfileScope(
      server: profile['idServer'],
      relayServer: profile['relayServer'],
      publicKey: profile['publicKey'],
    );
  }

  static String _canonicalKey(String server, String key) {
    requirePrivateConnectionService(server: server, publicKey: key);
    return base64.encode(base64.decode(base64.normalize(key.trim())));
  }

  String get fingerprint => base64Url
      .encode(utf8.encode(jsonEncode([1, server, relayServer, publicKey])))
      .replaceAll('=', '');
}

class LegacyImportResult {
  final int imported;
  final int retained;
  const LegacyImportResult(this.imported, this.retained);
}

bool shouldUseBundledConnection(String optionsJson, DeviceProfileScope previous) {
  final dynamic decoded = jsonDecode(optionsJson);
  if (decoded is! Map) return false;
  String? option(String name) {
    final value = decoded[name] ?? '';
    return value is String ? value.trim() : null;
  }
  final server = option('custom-rendezvous-server');
  final relay = option('relay-server');
  final key = option('key');
  final api = option('api-server');
  if (server == null || relay == null || key == null || api != '') return false;
  if (server.isEmpty && relay.isEmpty && key.isEmpty) return true;
  String withoutDefaultPort(String value, int port) =>
      value.toLowerCase().replaceFirst(RegExp(':$port\$'), '');
  return withoutDefaultPort(server, 21116) ==
          withoutDefaultPort(previous.server, 21116) &&
      (relay.isEmpty ||
          withoutDefaultPort(relay, 21117) ==
              withoutDefaultPort(previous.relayServer, 21117)) &&
      (key.isEmpty || key == previous.publicKey);
}

void requireCurrentDeviceScope(
    DeviceProfileScope expected, DeviceProfileScope current) {
  if (expected.fingerprint != current.fingerprint) {
    throw const DeviceValidationException('连接服务已改变，请从当前列表重新选择设备');
  }
}

class ScopedDeviceStore {
  static const storageKey = 'xixi-saved-devices-v2';
  final DeviceStorage storage;
  final DeviceStorage legacyStorage;
  bool _saving = false;

  ScopedDeviceStore({required this.storage, required this.legacyStorage});

  DeviceRepository repository(DeviceProfileScope scope) =>
      DeviceRepository(_ScopedDeviceStorage(this, scope.fingerprint));

  List<SavedDevice> pendingLegacyDevices() {
    if (_readDocument()['legacy_migrated_to'] != null) return [];
    return _decodeDevices(legacyStorage.read());
  }

  Future<LegacyImportResult> importLegacy(DeviceProfileScope scope) async {
    if (_saving) throw const DeviceStorageException('正在保存，请稍后再试');
    _saving = true;
    try {
      final document = _readDocument();
      if (document['legacy_migrated_to'] != null) {
        throw const DeviceValidationException('旧列表已经导入，原文件仍保留');
      }
      final legacy = _decodeDevices(legacyStorage.read());
      final scopes = document['scopes'] as Map;
      final current = _recordsForScope(scopes, scope.fingerprint);
      final ids = current.map((item) => item.id).toSet();
      final additions = legacy.where((item) => ids.add(item.id)).toList();
      if (current.length + additions.length > 1000) {
        throw const DeviceValidationException('导入后设备列表超过 1000 台，请先整理当前列表');
      }
      scopes[scope.fingerprint] = _devicesDocument([...current, ...additions]);
      document['legacy_migrated_to'] = scope.fingerprint;
      await storage.write(jsonEncode(document));
      return LegacyImportResult(
          additions.length, legacy.length - additions.length);
    } finally {
      _saving = false;
    }
  }

  String _readScope(String fingerprint) {
    final scopes = _readDocument()['scopes'] as Map;
    if (!scopes.containsKey(fingerprint)) return '';
    return jsonEncode(_devicesDocument(_recordsForScope(scopes, fingerprint)));
  }

  Future<void> _writeScope(String fingerprint, String value) async {
    if (_saving) throw const DeviceStorageException('正在保存，请稍后再试');
    _saving = true;
    try {
      final document = _readDocument();
      _recordsForScope(document['scopes'] as Map, fingerprint);
      (document['scopes'] as Map)[fingerprint] =
          _devicesDocument(_decodeDevices(value));
      await storage.write(jsonEncode(document));
    } finally {
      _saving = false;
    }
  }

  Map<String, dynamic> _readDocument() {
    final value = storage.read();
    if (value.isEmpty) {
      return {'schema_version': 2, 'scopes': <String, dynamic>{}};
    }
    try {
      final document = jsonDecode(value);
      if (document is! Map ||
          document['schema_version'] != 2 ||
          document['scopes'] is! Map) {
        throw const FormatException();
      }
      final migrated = document['legacy_migrated_to'];
      if (migrated != null &&
          (migrated is! String ||
              !(document['scopes'] as Map).containsKey(migrated))) {
        throw const FormatException();
      }
      return Map<String, dynamic>.from(document);
    } catch (_) {
      throw const DeviceStorageException('分组设备列表暂时无法读取，原记录已保留');
    }
  }

  static List<SavedDevice> _recordsForScope(Map scopes, String fingerprint) {
    if (!scopes.containsKey(fingerprint)) return [];
    final entry = scopes[fingerprint];
    if (entry is! Map) throw const DeviceStorageException('设备列表格式不正确，原记录已保留');
    return _decodeDevices(jsonEncode(entry));
  }

  static List<SavedDevice> _decodeDevices(String value) =>
      (DeviceRepository(_ReadOnlyStorage(value))..load()).devices;

  static Map<String, dynamic> _devicesDocument(List<SavedDevice> devices) => {
        'schema_version': 1,
        'devices': devices.map((item) => item.toJson()).toList(),
      };
}

class _ScopedDeviceStorage implements DeviceStorage {
  final ScopedDeviceStore store;
  final String fingerprint;
  _ScopedDeviceStorage(this.store, this.fingerprint);
  @override
  String read() => store._readScope(fingerprint);
  @override
  Future<void> write(String value) => store._writeScope(fingerprint, value);
}

class _ReadOnlyStorage implements DeviceStorage {
  final String value;
  _ReadOnlyStorage(this.value);
  @override
  String read() => value;
  @override
  Future<void> write(String value) =>
      throw const DeviceStorageException('旧列表只读');
}
