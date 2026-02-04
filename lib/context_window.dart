import 'dart:async';

import 'package:desktop_multi_window/desktop_multi_window.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:window_manager/window_manager.dart';

import 'models.dart';
import 'storage.dart';
import 'window_payload.dart';

class ContextWindowLauncher {
  static Future<void> open({
    required String ownerWindowId,
    required String taskId,
    required String taskTitle,
    required String contextText,
  }) async {
    final controllers = await WindowController.getAll();
    for (final controller in controllers) {
      final payload = WindowPayload.parse(controller.arguments);
      if (payload.type == WindowType.context && payload.taskId == taskId) {
        await _safeInvoke(controller, 'context_update', {
          'taskTitle': taskTitle,
          'contextText': contextText,
        });
        await _safeInvoke(controller, 'context_focus');
        return;
      }
    }
    final payload = WindowPayload.context(
      taskId: taskId,
      taskTitle: taskTitle,
      contextText: contextText,
      ownerWindowId: ownerWindowId,
    );
    final controller = await WindowController.create(
      WindowConfiguration(
        hiddenAtLaunch: true,
        arguments: payload.encode(),
      ),
    );
    await _invokeWithRetry(controller, 'context_focus');
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

class ContextWindowApp extends StatefulWidget {
  const ContextWindowApp({super.key, required this.payload});

  final WindowPayload payload;

  @override
  State<ContextWindowApp> createState() => _ContextWindowAppState();
}

class _ContextWindowAppState extends State<ContextWindowApp> with WindowListener {
  late final TextEditingController _controller;
  late final WindowController _windowController;
  String _taskTitle = '';
  bool _closing = false;
  bool _isPinned = false;
  bool _hoveringWindow = false;
  double _inactiveOpacity = Settings.defaults().opacity;
  Timer? _autoSaveDebounce;
  Timer? _blurDebounce;
  String _lastSyncedText = '';

  @override
  void initState() {
    super.initState();
    _taskTitle = widget.payload.taskTitle ?? '';
    _controller = TextEditingController(text: widget.payload.contextText ?? '');
    _lastSyncedText = _controller.text;
    windowManager.addListener(this);
    _init();
    _loadOpacity();
  }

  Future<void> _init() async {
    _windowController = await WindowController.fromCurrentEngine();
    await _windowController.setWindowMethodHandler(_handleMethodCall);
    await _configureWindow();
    await _focusAndShow();
  }

  Future<void> _configureWindow() async {
    const size = Size(640, 420);
    final options = WindowOptions(
      size: size,
      minimumSize: const Size(480, 320),
      backgroundColor: Colors.black,
      titleBarStyle: TitleBarStyle.hidden,
      alwaysOnTop: _isPinned,
      skipTaskbar: true,
      windowButtonVisibility: false,
    );
    await windowManager.waitUntilReadyToShow(options, () async {
      await windowManager.center();
    });
    await windowManager.setPreventClose(true);
  }

  Future<dynamic> _handleMethodCall(MethodCall call) async {
    if (call.method == 'context_update') {
      final args = call.arguments is Map
          ? (call.arguments as Map).cast<String, dynamic>()
          : <String, dynamic>{};
      final title = args['taskTitle']?.toString();
      final text = args['contextText']?.toString();
      if (title != null && title.isNotEmpty) {
        setState(() {
          _taskTitle = title;
        });
      }
      if (text != null) {
        _controller.text = text;
        _lastSyncedText = text;
        _autoSaveDebounce?.cancel();
      }
      return true;
    }
    if (call.method == 'context_focus') {
      await _focusAndShow();
      return true;
    }
    return null;
  }

  Future<void> _sendAndHide() async {
    if (_closing) return;
    _closing = true;
    _autoSaveDebounce?.cancel();
    await _sendUpdate();
    await windowManager.hide();
    _closing = false;
  }

  Future<void> _sendUpdate({bool force = false}) async {
    final ownerId = widget.payload.ownerWindowId;
    final taskId = widget.payload.taskId;
    if (ownerId == null || taskId == null) {
      return;
    }
    final text = _controller.text;
    if (!force && text == _lastSyncedText) {
      return;
    }
    final owner = WindowController.fromWindowId(ownerId);
    try {
      await owner.invokeMethod('context_saved', {
        'taskId': taskId,
        'text': text,
      });
      _lastSyncedText = text;
    } catch (_) {}
  }

  Future<void> _focusAndShow() async {
    _closing = false;
    await windowManager.center();
    await windowManager.show();
    await windowManager.focus();
    await _applyPinState();
  }

  Future<void> _loadOpacity() async {
    final data = await StorageService().load();
    if (!mounted) return;
    setState(() {
      _inactiveOpacity = data.settings.opacity;
    });
    if (_isPinned && !_hoveringWindow) {
      await windowManager.setOpacity(_inactiveOpacity);
    }
  }

  Future<void> _applyPinState() async {
    await windowManager.setAlwaysOnTop(_isPinned);
    if (_isPinned && !_hoveringWindow) {
      await windowManager.setOpacity(_inactiveOpacity);
      return;
    }
    await windowManager.setOpacity(1.0);
  }

  void _scheduleAutoSave([Duration delay = const Duration(milliseconds: 450)]) {
    _autoSaveDebounce?.cancel();
    _autoSaveDebounce = Timer(delay, () {
      _sendUpdate();
    });
  }

  void _handleBlur() {
    _blurDebounce?.cancel();
    _blurDebounce = Timer(const Duration(milliseconds: 160), () async {
      if (!mounted) return;
      if (_isPinned) {
        await _sendUpdate();
        return;
      }
      final focused = await windowManager.isFocused();
      if (!focused) {
        await _sendAndHide();
      }
    });
  }

  @override
  void onWindowBlur() {
    _handleBlur();
  }

  @override
  void onWindowFocus() {
    unawaited(_applyPinState());
  }

  @override
  void onWindowClose() {
    _sendAndHide();
  }

  @override
  void dispose() {
    windowManager.removeListener(this);
    _autoSaveDebounce?.cancel();
    _blurDebounce?.cancel();
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: '任务记录',
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
          LogicalKeySet(LogicalKeyboardKey.control, LogicalKeyboardKey.enter):
              const ActivateIntent(),
        },
        child: Actions(
          actions: {
            ActivateIntent: CallbackAction<ActivateIntent>(
              onInvoke: (_) {
                _sendAndHide();
                return null;
              },
            ),
          },
          child: MouseRegion(
            onEnter: (_) {
              _hoveringWindow = true;
              if (_isPinned) {
                windowManager.setOpacity(1.0);
              }
            },
            onExit: (_) {
              _hoveringWindow = false;
              if (_isPinned) {
                windowManager.setOpacity(_inactiveOpacity);
              }
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
                              '任务记录：$_taskTitle',
                              style: const TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.w600,
                                color: Colors.white,
                              ),
                            ),
                          ),
                        ),
                        IconButton(
                          tooltip: _isPinned ? '取消置顶' : '置顶',
                          icon: Icon(
                            _isPinned ? Icons.push_pin : Icons.push_pin_outlined,
                          ),
                          onPressed: () async {
                            final value = !_isPinned;
                            setState(() {
                              _isPinned = value;
                            });
                            await _applyPinState();
                          },
                        ),
                        IconButton(
                          tooltip: '关闭',
                          icon: const Icon(Icons.close),
                          onPressed: _sendAndHide,
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    Expanded(
                      child: TextField(
                        controller: _controller,
                        autofocus: true,
                        expands: true,
                        maxLines: null,
                        onChanged: (_) => _scheduleAutoSave(),
                        textAlignVertical: TextAlignVertical.top,
                        style:
                            const TextStyle(color: Colors.white, fontSize: 16),
                        decoration: const InputDecoration(
                          border: InputBorder.none,
                          enabledBorder: OutlineInputBorder(
                            borderSide: BorderSide.none,
                            borderRadius: BorderRadius.all(Radius.circular(12)),
                          ),
                          focusedBorder: OutlineInputBorder(
                            borderSide: BorderSide.none,
                            borderRadius: BorderRadius.all(Radius.circular(12)),
                          ),
                          hintText: '记录已验证结论/下一步/关键点…',
                          hintStyle: TextStyle(color: Colors.white54),
                          filled: true,
                          fillColor: Color(0xFF1C1C1C),
                          contentPadding: EdgeInsets.all(16),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
