import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';

import 'models.dart';

class StorageService {
  static const String _namespaceDefine = String.fromEnvironment(
    'STICKY_NOTES_DATA_NAMESPACE',
  );

  String _resolvedAppDirName() {
    final customNamespace = _namespaceDefine.trim();
    if (customNamespace.isNotEmpty) {
      return _normalizeDirName('sticky_notes_$customNamespace');
    }
    if (kReleaseMode) {
      return 'sticky_notes';
    }
    return 'sticky_notes_dev';
  }

  String _normalizeDirName(String value) {
    final normalized = value.replaceAll(RegExp(r'[^A-Za-z0-9._-]'), '_');
    if (normalized.isEmpty) {
      return 'sticky_notes_dev';
    }
    return normalized;
  }

  Future<Directory> appDirectory() async {
    final dir = await getApplicationSupportDirectory();
    final appDir = Directory('${dir.path}/${_resolvedAppDirName()}');
    if (!await appDir.exists()) {
      await appDir.create(recursive: true);
    }
    return appDir;
  }

  Future<File> _dataFile() async {
    final appDir = await appDirectory();
    return File('${appDir.path}/data.json');
  }

  Future<Directory> resolveBackupDirectory(String? backupDir) async {
    final normalized = backupDir?.trim() ?? '';
    if (normalized.isNotEmpty) {
      final custom = Directory(normalized);
      if (!await custom.exists()) {
        await custom.create(recursive: true);
      }
      return custom;
    }
    final appDir = await appDirectory();
    final fallback = Directory('${appDir.path}/backup');
    if (!await fallback.exists()) {
      await fallback.create(recursive: true);
    }
    return fallback;
  }

  Future<String> defaultBackupDirectoryPath() async {
    final dir = await resolveBackupDirectory('');
    return dir.path;
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
