import 'dart:io';

import 'saved_devices.dart';

class FileDeviceStorage implements DeviceStorage {
  final File file;
  FileDeviceStorage(this.file);

  @override
  String read() {
    try {
      return file.readAsStringSync();
    } on FileSystemException catch (error) {
      if (error.osError?.errorCode == 2) return '';
      rethrow;
    }
  }

  @override
  Future<void> write(String value) async {
    final pending = File('${file.path}.pending');
    await pending.writeAsString(value, flush: true);
    await pending.rename(file.path);
  }
}
