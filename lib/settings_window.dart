import 'dart:async';

import 'package:desktop_multi_window/desktop_multi_window.dart';
import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:window_manager/window_manager.dart';

import 'models.dart';
import 'storage.dart';
import 'window_payload.dart';

class SettingsWindowLauncher {
  static Future<void> open({
    required String ownerWindowId,
    required Settings settings,
  }) async {
    final controllers = await WindowController.getAll();
    for (final controller in controllers) {
      final payload = WindowPayload.parse(controller.arguments);
      if (payload.type == WindowType.settings) {
        await _safeInvoke(controller, 'settings_update', {
          'settings': settings.toJson(),
        });
        await _safeInvoke(controller, 'settings_focus');
        return;
      }
    }
    final payload = WindowPayload.settings(
      ownerWindowId: ownerWindowId,
      settings: settings.toJson(),
    );
    final controller = await WindowController.create(
      WindowConfiguration(hiddenAtLaunch: true, arguments: payload.encode()),
    );
    await _invokeWithRetry(controller, 'settings_focus');
  }

  static Future<bool> _safeInvoke(
    WindowController controller,
    String method, [
    dynamic arguments,
  ]) async {
    try {
      await controller.invokeMethod(method, arguments);
      return true;
    } catch (_) {
      return false;
    }
  }

  static Future<void> _invokeWithRetry(
    WindowController controller,
    String method, [
    dynamic arguments,
  ]) async {
    const attempts = 6;
    const delay = Duration(milliseconds: 120);
    for (var i = 0; i < attempts; i += 1) {
      if (await _safeInvoke(controller, method, arguments)) {
        return;
      }
      await Future.delayed(delay);
    }
  }
}

class SettingsWindowApp extends StatefulWidget {
  const SettingsWindowApp({super.key, required this.payload});

  final WindowPayload payload;

  @override
  State<SettingsWindowApp> createState() => _SettingsWindowAppState();
}

class _SettingsWindowAppState extends State<SettingsWindowApp>
    with WindowListener {
  late Settings _settings;
  late final WindowController _windowController;
  bool _closing = false;
  bool _exporting = false;
  String _defaultBackupDir = '';

  @override
  void initState() {
    super.initState();
    _settings = widget.payload.settings != null
        ? Settings.fromJson(widget.payload.settings!)
        : Settings.defaults();
    windowManager.addListener(this);
    _init();
    _loadDefaultBackupDir();
  }

  Future<void> _init() async {
    _windowController = await WindowController.fromCurrentEngine();
    await _windowController.setWindowMethodHandler(_handleMethodCall);
    await _configureWindow();
    await _focusAndShow();
  }

  Future<void> _configureWindow() async {
    const size = Size(620, 640);
    final options = WindowOptions(
      size: size,
      minimumSize: const Size(560, 520),
      backgroundColor: Colors.black,
      titleBarStyle: TitleBarStyle.hidden,
      alwaysOnTop: true,
      skipTaskbar: true,
      windowButtonVisibility: false,
    );
    await windowManager.waitUntilReadyToShow(options, () async {
      await windowManager.center();
    });
    await windowManager.setPreventClose(true);
  }

  Future<dynamic> _handleMethodCall(MethodCall call) async {
    if (call.method == 'settings_update') {
      final args = call.arguments is Map
          ? (call.arguments as Map).cast<String, dynamic>()
          : <String, dynamic>{};
      final map = args['settings'] is Map
          ? (args['settings'] as Map).cast<String, dynamic>()
          : <String, dynamic>{};
      setState(() {
        _settings = Settings.fromJson(map);
      });
      return true;
    }
    if (call.method == 'settings_focus') {
      await _focusAndShow();
      return true;
    }
    return null;
  }

  Future<void> _notifyOwnerSettings() async {
    final ownerId = widget.payload.ownerWindowId;
    if (ownerId == null) return;
    final owner = WindowController.fromWindowId(ownerId);
    await owner.invokeMethod('settings_update', {
      'settings': _settings.toJson(),
    });
  }

  Future<void> _notifyClosed() async {
    final ownerId = widget.payload.ownerWindowId;
    if (ownerId == null) return;
    final owner = WindowController.fromWindowId(ownerId);
    await owner.invokeMethod('settings_closed');
  }

  Future<void> _notifyOpened() async {
    final ownerId = widget.payload.ownerWindowId;
    if (ownerId == null) return;
    final owner = WindowController.fromWindowId(ownerId);
    await owner.invokeMethod('settings_opened');
  }

  Future<void> _focusAndShow() async {
    await windowManager.center();
    await windowManager.show();
    await windowManager.focus();
    await _notifyOpened();
  }

  Future<void> _hideWindow() async {
    if (_closing) return;
    _closing = true;
    await _notifyClosed();
    await windowManager.hide();
    _closing = false;
  }

  Future<void> _loadDefaultBackupDir() async {
    try {
      final path = await StorageService().defaultBackupDirectoryPath();
      if (!mounted) {
        return;
      }
      setState(() {
        _defaultBackupDir = path;
      });
    } catch (_) {
      // Keep loading fallback text when reading default directory fails.
    }
  }

  Future<void> _pickBackupDir() async {
    try {
      final path = await getDirectoryPath(confirmButtonText: '选择备份目录');
      if (path == null || path.trim().isEmpty) {
        return;
      }
      setState(() {
        _settings = _settings.copyWith(backupDir: path.trim());
      });
      await _notifyOwnerSettings();
    } catch (error) {
      _showMessage('选择目录失败：$error');
    }
  }

  Future<void> _clearBackupDir() async {
    setState(() {
      _settings = _settings.copyWith(backupDir: '');
    });
    await _notifyOwnerSettings();
  }

  Future<void> _exportDoneTasks() async {
    if (_exporting) {
      return;
    }
    final ownerId = widget.payload.ownerWindowId;
    if (ownerId == null) {
      _showMessage('无法找到主窗口，导出失败');
      return;
    }
    setState(() {
      _exporting = true;
    });
    try {
      final owner = WindowController.fromWindowId(ownerId);
      final response = await owner.invokeMethod('archive_done_tasks');
      final map = response is Map
          ? response.cast<String, dynamic>()
          : <String, dynamic>{};
      final success = map['success'] == true;
      final countValue = map['exportedCount'];
      final count = countValue is num ? countValue.toInt() : 0;
      final filePath = map['filePath']?.toString() ?? '';
      final message = map['message']?.toString();
      if (!success) {
        _showMessage(message ?? '导出失败，应用内数据未删除');
      } else if (count <= 0) {
        _showMessage('没有可导出的已完成任务');
      } else {
        final suffix = filePath.trim().isEmpty ? '' : '\n$filePath';
        _showMessage('已导出 $count 个已完成任务$suffix');
      }
    } catch (error) {
      _showMessage('导出失败：$error');
    } finally {
      if (mounted) {
        setState(() {
          _exporting = false;
        });
      }
    }
  }

  String _effectiveBackupDirText() {
    final customPath = _settings.backupDir?.trim() ?? '';
    if (customPath.isNotEmpty) {
      return customPath;
    }
    if (_defaultBackupDir.isNotEmpty) {
      return '$_defaultBackupDir（默认）';
    }
    return '默认目录加载中...';
  }

  void _showMessage(String message) {
    if (!mounted) {
      return;
    }
    final messenger = ScaffoldMessenger.maybeOf(context);
    if (messenger == null) {
      return;
    }
    messenger.clearSnackBars();
    messenger.showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  void onWindowClose() {
    _hideWindow();
  }

  @override
  void dispose() {
    windowManager.removeListener(this);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: '设置',
      theme: ThemeData(
        useMaterial3: true,
        brightness: Brightness.dark,
        scaffoldBackgroundColor: Colors.black,
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF5C8D89),
          brightness: Brightness.dark,
        ),
      ),
      home: Shortcuts(
        shortcuts: {
          LogicalKeySet(LogicalKeyboardKey.escape): const ActivateIntent(),
        },
        child: Actions(
          actions: {
            ActivateIntent: CallbackAction<ActivateIntent>(
              onInvoke: (_) {
                _hideWindow();
                return null;
              },
            ),
          },
          child: Scaffold(
            body: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: DragToMoveArea(
                          child: Text(
                            '设置',
                            style: const TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w600,
                              color: Colors.white,
                            ),
                          ),
                        ),
                      ),
                      IconButton(
                        tooltip: '关闭',
                        icon: const Icon(Icons.close),
                        onPressed: _hideWindow,
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Expanded(
                    child: SingleChildScrollView(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          SwitchListTile(
                            title: const Text('置顶显示'),
                            value: _settings.alwaysOnTop,
                            onChanged: (value) async {
                              setState(() {
                                _settings = _settings.copyWith(
                                  alwaysOnTop: value,
                                );
                              });
                              await _notifyOwnerSettings();
                            },
                          ),
                          SwitchListTile(
                            title: const Text('仅显示进行中'),
                            value: _settings.showOnlyTodo,
                            onChanged: (value) async {
                              setState(() {
                                _settings = _settings.copyWith(
                                  showOnlyTodo: value,
                                );
                              });
                              await _notifyOwnerSettings();
                            },
                          ),
                          SwitchListTile(
                            title: const Text('系统通知提醒'),
                            value: _settings.enableSystemNotification,
                            onChanged: (value) async {
                              setState(() {
                                _settings = _settings.copyWith(
                                  enableSystemNotification: value,
                                );
                              });
                              await _notifyOwnerSettings();
                            },
                          ),
                          const SizedBox(height: 8),
                          _LabeledSlider(
                            label: '透明度',
                            value: _settings.opacity,
                            min: 0.3,
                            max: 1.0,
                            onChanged: (value) async {
                              setState(() {
                                _settings = _settings.copyWith(opacity: value);
                              });
                              await _notifyOwnerSettings();
                            },
                          ),
                          _LabeledSlider(
                            label: '字体大小',
                            value: _settings.fontScale,
                            min: 0.85,
                            max: 1.2,
                            onChanged: (value) async {
                              setState(() {
                                _settings = _settings.copyWith(
                                  fontScale: value,
                                );
                              });
                              await _notifyOwnerSettings();
                            },
                          ),
                          _LabeledSlider(
                            label: '默认专注时长（分钟）',
                            value: _settings.defaultFocusMinutes.toDouble(),
                            min: 10,
                            max: 60,
                            divisions: 10,
                            onChanged: (value) async {
                              setState(() {
                                _settings = _settings.copyWith(
                                  defaultFocusMinutes: value.round(),
                                );
                              });
                              await _notifyOwnerSettings();
                            },
                          ),
                          const SizedBox(height: 16),
                          const Divider(color: Colors.white24),
                          const SizedBox(height: 12),
                          const Text(
                            '已完成任务归档（Markdown）',
                            style: TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          const SizedBox(height: 8),
                          Text(
                            '当前备份目录：${_effectiveBackupDirText()}',
                            style: const TextStyle(
                              fontSize: 12,
                              color: Colors.white70,
                            ),
                          ),
                          const SizedBox(height: 8),
                          Wrap(
                            spacing: 8,
                            runSpacing: 8,
                            children: [
                              OutlinedButton.icon(
                                onPressed: _pickBackupDir,
                                icon: const Icon(Icons.folder_open_outlined),
                                label: const Text('选择备份目录'),
                              ),
                              OutlinedButton.icon(
                                onPressed: _clearBackupDir,
                                icon: const Icon(Icons.restart_alt),
                                label: const Text('恢复默认目录'),
                              ),
                              FilledButton.icon(
                                onPressed: _exporting ? null : _exportDoneTasks,
                                icon: _exporting
                                    ? const SizedBox(
                                        width: 16,
                                        height: 16,
                                        child: CircularProgressIndicator(
                                          strokeWidth: 2,
                                        ),
                                      )
                                    : const Icon(Icons.archive_outlined),
                                label: const Text('立即导出所有已完成任务'),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _LabeledSlider extends StatelessWidget {
  const _LabeledSlider({
    required this.label,
    required this.value,
    required this.min,
    required this.max,
    this.divisions,
    required this.onChanged,
  });

  final String label;
  final double value;
  final double min;
  final double max;
  final int? divisions;
  final ValueChanged<double> onChanged;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('$label：${value.toStringAsFixed(2)}'),
        Slider(
          value: value.clamp(min, max),
          min: min,
          max: max,
          divisions: divisions,
          onChanged: onChanged,
        ),
      ],
    );
  }
}
