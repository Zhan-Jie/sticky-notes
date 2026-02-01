import 'dart:io';

import 'package:path_provider/path_provider.dart';

import 'models.dart';

class StorageService {
  Future<File> _dataFile() async {
    final dir = await getApplicationSupportDirectory();
    final appDir = Directory('${dir.path}/sticky_notes');
    if (!await appDir.exists()) {
      await appDir.create(recursive: true);
    }
    return File('${appDir.path}/data.json');
  }

  Future<AppData> load() async {
    try {
      final file = await _dataFile();
      if (!await file.exists()) {
        return AppData.empty();
      }
      final content = await file.readAsString();
      if (content.trim().isEmpty) {
        return AppData.empty();
      }
      return decodeAppData(content);
    } catch (_) {
      return AppData.empty();
    }
  }

  Future<void> save(AppData data) async {
    final file = await _dataFile();
    await file.writeAsString(encodeAppData(data));
  }
}
