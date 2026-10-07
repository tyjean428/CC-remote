import 'device_scope.dart';
import 'saved_devices.dart';

class DeviceConnectionState {
  DeviceProfileScope? _scope;
  DeviceRepository? _repository;
  String? _profileError;
  String? _storageError;

  DeviceProfileScope? get scope => _scope;
  DeviceRepository? get repository => _repository;
  String? get profileError => _profileError;
  String? get storageError => _storageError;
  bool get canConnect => _scope != null;

  void refresh({
    required DeviceProfileScope Function() readScope,
    required DeviceRepository Function(DeviceProfileScope) openRepository,
    bool forceReload = false,
  }) {
    DeviceProfileScope next;
    try {
      next = readScope();
    } on DeviceValidationException catch (error) {
      _clearProfile(error.message);
      return;
    } catch (_) {
      _clearProfile('连接服务配置暂时无法读取');
      return;
    }

    final reuseRepository = !forceReload &&
        _scope?.fingerprint == next.fingerprint &&
        _repository != null;
    _scope = next;
    _profileError = null;
    _storageError = null;
    if (reuseRepository) return;

    _repository = null;
    try {
      final repository = openRepository(next)..load();
      _repository = repository;
    } on DeviceStorageException catch (error) {
      _storageError = error.message;
    } catch (_) {
      _storageError = '设备列表暂时无法读取，原记录已保留';
    }
  }

  void _clearProfile(String message) {
    _scope = null;
    _repository = null;
    _profileError = message;
    _storageError = null;
  }
}
