import 'dart:async';

import 'package:desktop_multi_window/desktop_multi_window.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:local_notifier/local_notifier.dart';
import 'package:screen_retriever/screen_retriever.dart';
import 'package:window_manager/window_manager.dart';

import 'app_state.dart';
import 'context_window.dart';
import 'models.dart';
import 'settings_window.dart';
import 'storage.dart';
import 'widgets/task_item.dart';
import 'window_payload.dart';

Future<void> main(List<String> args) async {
  WidgetsFlutterBinding.ensureInitialized();
  final windowController = await WindowController.fromCurrentEngine();
  final payload = WindowPayload.parse(windowController.arguments);
  await windowManager.ensureInitialized();
  if (payload.type == WindowType.context) {
    runApp(ContextWindowApp(payload: payload));
    return;
  }
  if (payload.type == WindowType.settings) {
    runApp(SettingsWindowApp(payload: payload));
    return;
  }
  await localNotifier.setup(
    appName: 'sticky_notes',
    shortcutPolicy: ShortcutPolicy.requireCreate,
  );
  runApp(StickyNotesApp(windowController: windowController));
}

class StickyNotesApp extends StatefulWidget {
  const StickyNotesApp({super.key, required this.windowController});

  final WindowController windowController;

  @override
  State<StickyNotesApp> createState() => _StickyNotesAppState();
}

class _StickyNotesAppState extends State<StickyNotesApp> with WindowListener {
  final AppState _appState = AppState(StorageService());
  bool _ready = false;
  Timer? _boundsDebounce;

  @override
  void initState() {
    super.initState();
    windowManager.addListener(this);
    _init();
  }

  Future<void> _init() async {
    await widget.windowController.setWindowMethodHandler(_handleMethodCall);
    await _appState.load();
    await _configureWindow();
    setState(() {
      _ready = true;
    });
  }

  Future<dynamic> _handleMethodCall(MethodCall call) async {
    if (call.method == 'context_saved') {
      final args = call.arguments is Map
          ? (call.arguments as Map).cast<String, dynamic>()
          : <String, dynamic>{};
      final taskId = args['taskId']?.toString();
      final text = args['text']?.toString() ?? '';
      if (taskId != null && taskId.isNotEmpty) {
        _appState.updateTaskContext(taskId, text);
      }
      return true;
    }
    if (call.method == 'settings_update') {
      final args = call.arguments is Map
          ? (call.arguments as Map).cast<String, dynamic>()
          : <String, dynamic>{};
      final map = args['settings'] is Map
          ? (args['settings'] as Map).cast<String, dynamic>()
          : <String, dynamic>{};
      final newSettings = Settings.fromJson(map);
      final oldSettings = _appState.settings;
      _appState.updateSettings(newSettings);
      if (newSettings.defaultFocusMinutes != oldSettings.defaultFocusMinutes) {
        _appState.updateDefaultFocusMinutes(newSettings.defaultFocusMinutes);
      }
      await windowManager.setAlwaysOnTop(newSettings.alwaysOnTop);
      return true;
    }
    if (call.method == 'settings_opened') {
      _appState.setForceOpaque(true);
      return true;
    }
    if (call.method == 'settings_closed') {
      _appState.setForceOpaque(false);
      return true;
    }
    return null;
  }

  Future<void> _configureWindow() async {
    final settings = _appState.settings;
    final width = settings.windowW ?? 360;
    final height = settings.windowH ?? width;
    final size = Size(width, height);
    final options = WindowOptions(
      size: size,
      minimumSize: const Size(300, 260),
      backgroundColor: Colors.transparent,
      titleBarStyle: TitleBarStyle.hidden,
      alwaysOnTop: settings.alwaysOnTop,
      windowButtonVisibility: false,
      skipTaskbar: false,
    );
    await windowManager.waitUntilReadyToShow(options, () async {
      if (settings.windowX != null &&
          settings.windowY != null &&
          settings.windowW != null &&
          settings.windowH != null) {
        await windowManager.setBounds(
          Rect.fromLTWH(
            settings.windowX!,
            settings.windowY!,
            settings.windowW!,
            settings.windowH!,
          ),
        );
      } else {
        await _moveToDefaultPosition(size);
      }
      await windowManager.setOpacity(settings.opacity);
      await windowManager.show();
      await windowManager.focus();
    });
  }

  Future<void> _moveToDefaultPosition(Size size) async {
    final display = await screenRetriever.getPrimaryDisplay();
    final visibleSize = display.visibleSize ?? display.size;
    final visiblePosition = display.visiblePosition ?? Offset.zero;
    final x = visiblePosition.dx + visibleSize.width - size.width - 24;
    final y = visiblePosition.dy + 24;
    await windowManager.setPosition(Offset(x, y));
  }

  Future<void> _captureBounds() async {
    final position = await windowManager.getPosition();
    final size = await windowManager.getSize();
    _appState.updateWindowBounds(
      x: position.dx,
      y: position.dy,
      width: size.width,
      height: size.height,
    );
  }

  @override
  void onWindowMove() {
    _boundsDebounce?.cancel();
    _boundsDebounce = Timer(const Duration(milliseconds: 500), _captureBounds);
  }

  @override
  void onWindowResize() {
    _boundsDebounce?.cancel();
    _boundsDebounce = Timer(const Duration(milliseconds: 500), _captureBounds);
  }

  @override
  void dispose() {
    windowManager.removeListener(this);
    _boundsDebounce?.cancel();
    _appState.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _appState,
      builder: (context, _) {
        final settings = _appState.settings;
        return MaterialApp(
          debugShowCheckedModeBanner: false,
          title: '桌面便签',
          theme: ThemeData(
            useMaterial3: true,
            brightness: Brightness.dark,
            scaffoldBackgroundColor: Colors.transparent,
            colorScheme: ColorScheme.fromSeed(
              seedColor: const Color(0xFF5C8D89),
              brightness: Brightness.dark,
            ),
            snackBarTheme: const SnackBarThemeData(
              behavior: SnackBarBehavior.floating,
            ),
          ),
          builder: (context, child) {
            final media = MediaQuery.of(context);
            return MediaQuery(
              data: media.copyWith(
                textScaler: TextScaler.linear(settings.fontScale),
              ),
              child: child ?? const SizedBox.shrink(),
            );
          },
          home: _ready
              ? StickyNotesHome(
                  appState: _appState,
                  ownerWindowId: widget.windowController.windowId,
                  onAlwaysOnTopChanged: (value) async {
                    await windowManager.setAlwaysOnTop(value);
                  },
                )
              : const Scaffold(
                  body: Center(child: CircularProgressIndicator()),
                ),
        );
      },
    );
  }
}

class StickyNotesHome extends StatefulWidget {
  const StickyNotesHome({
    super.key,
    required this.appState,
    required this.ownerWindowId,
    required this.onAlwaysOnTopChanged,
  });

  final AppState appState;
  final String ownerWindowId;
  final Future<void> Function(bool value) onAlwaysOnTopChanged;

  @override
  State<StickyNotesHome> createState() => _StickyNotesHomeState();
}

class _StickyNotesHomeState extends State<StickyNotesHome> {
  final TextEditingController _inputController = TextEditingController();
  final FocusNode _inputFocus = FocusNode();
  bool _handlingPaste = false;
  bool _hoveringWindow = false;
  bool _showInput = false;
  Timer? _resizeDebounce;
  double _lastAutoHeight = 0;

  @override
  void dispose() {
    _inputController.dispose();
    _inputFocus.dispose();
    _resizeDebounce?.cancel();
    super.dispose();
  }

  void _submitInput() {
    final text = _inputController.text;
    if (text.trim().isEmpty) {
      return;
    }
    final lines = text.split(RegExp(r'\r?\n'));
    final result = widget.appState.addTasks(lines);
    _inputController.clear();
    if (result.suspended > 0) {
      _showMessage('已新增 ${result.added} 条，其中 ${result.suspended} 条已挂起');
    }
  }

  void _showMessage(String message) {
    final messenger = ScaffoldMessenger.of(context);
    messenger.clearSnackBars();
    messenger.showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _openInput() async {
    if (_showInput) return;
    final taskCount = widget.appState
        .sortedTasks(includeDone: !widget.appState.settings.showOnlyTodo)
        .length;
    final targetHeight = _calculateWindowHeight(taskCount, true);
    final size = await windowManager.getSize();
    if (size.height < targetHeight) {
      await windowManager.setSize(Size(size.width, targetHeight));
    }
    if (!mounted) return;
    setState(() {
      _showInput = true;
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _inputFocus.requestFocus();
    });
  }

  void _closeInput({bool clear = false}) {
    if (!_showInput) return;
    if (clear) {
      _inputController.clear();
    }
    setState(() {
      _showInput = false;
    });
    final taskCount = widget.appState
        .sortedTasks(includeDone: !widget.appState.settings.showOnlyTodo)
        .length;
    final targetHeight = _calculateWindowHeight(taskCount, false);
    _scheduleAutoResize(targetHeight);
  }

  Future<void> _openSettings() async {
    widget.appState.setForceOpaque(true);
    await windowManager.setOpacity(1.0);
    await SettingsWindowLauncher.open(
      ownerWindowId: widget.ownerWindowId,
      settings: widget.appState.settings,
    );
  }

  @override
  Widget build(BuildContext context) {
    final settings = widget.appState.settings;
    final forceOpaque = widget.appState.forceOpaque;
    final tasks = widget.appState.sortedTasks(
      includeDone: !settings.showOnlyTodo,
    );
    final desiredHeight = _calculateWindowHeight(tasks.length, _showInput);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      if (forceOpaque || _hoveringWindow) {
        windowManager.setOpacity(1.0);
      } else {
        windowManager.setOpacity(settings.opacity);
      }
      _scheduleAutoResize(desiredHeight);
    });

    return Scaffold(
      body: MouseRegion(
        onEnter: (_) {
          if (_hoveringWindow) return;
          _hoveringWindow = true;
          if (!widget.appState.forceOpaque) {
            windowManager.setOpacity(1.0);
          }
        },
        onExit: (_) {
          if (!_hoveringWindow) return;
          _hoveringWindow = false;
          if (!widget.appState.forceOpaque) {
            windowManager.setOpacity(settings.opacity);
          }
        },
        child: Container(
          color: Colors.black,
          padding: const EdgeInsets.all(12),
          child: Column(
            children: [
              DragToMoveArea(
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 6),
                  child: Row(
                    children: [
                      const SizedBox(width: 2),
                      Expanded(
                        child: Text(
                          '便签',
                          style: TextStyle(
                            fontWeight: FontWeight.w600,
                            color: Colors.white70,
                            fontSize: 16,
                          ),
                        ),
                      ),
                      IconButton(
                        tooltip: settings.alwaysOnTop ? '取消置顶' : '置顶',
                        icon: Icon(
                          settings.alwaysOnTop
                              ? Icons.push_pin
                              : Icons.push_pin_outlined,
                          size: 18,
                        ),
                        onPressed: () async {
                          final value = !settings.alwaysOnTop;
                          widget.appState.updateSettings(
                            settings.copyWith(alwaysOnTop: value),
                          );
                          await widget.onAlwaysOnTopChanged(value);
                        },
                      ),
                      IconButton(
                        tooltip: settings.showOnlyTodo ? '显示全部' : '仅显示进行中',
                        icon: Icon(
                          settings.showOnlyTodo
                              ? Icons.visibility_off_outlined
                              : Icons.visibility_outlined,
                          size: 18,
                        ),
                        onPressed: () {
                          widget.appState.updateSettings(
                            settings.copyWith(
                                showOnlyTodo: !settings.showOnlyTodo),
                          );
                        },
                      ),
                      IconButton(
                        tooltip: '设置',
                        icon: const Icon(Icons.settings_outlined, size: 18),
                        onPressed: _openSettings,
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 8),
              Expanded(
                child: tasks.isEmpty
                    ? const Center(
                        child: Text(
                          '暂无任务，开始记录吧',
                          style: TextStyle(color: Colors.white54),
                        ),
                      )
                    : ListView.builder(
                        itemCount: tasks.length,
                        itemBuilder: (context, index) {
                          final task = tasks[index];
                          return TaskItem(
                            key: ValueKey(task.id),
                            task: task,
                            appState: widget.appState,
                            isCurrent: widget.appState.currentTaskId == task.id,
                            onOpenContext: (task) =>
                                ContextWindowLauncher.open(
                              ownerWindowId: widget.ownerWindowId,
                              taskId: task.id,
                              taskTitle: task.text,
                              contextText: task.contextText,
                            ),
                          );
                        },
                      ),
              ),
              const SizedBox(height: 8),
              _showInput
                  ? Row(
                      children: [
                        Expanded(
                          child: TextField(
                            controller: _inputController,
                            focusNode: _inputFocus,
                            textInputAction: TextInputAction.done,
                            onSubmitted: (_) {
                              _submitInput();
                              _closeInput();
                            },
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 16,
                            ),
                            minLines: 1,
                            maxLines: 3,
                            onChanged: (value) {
                              if (_handlingPaste) return;
                              if (value.contains('\n') ||
                                  value.contains('\r')) {
                                _handlingPaste = true;
                                    WidgetsBinding.instance
                                        .addPostFrameCallback((_) {
                                      _submitInput();
                                      _closeInput();
                                      _handlingPaste = false;
                                    });
                                  }
                                },
                            decoration: InputDecoration(
                              hintText: '输入任务，回车新增（活动最多 5 条，超出自动挂起）',
                              hintStyle: const TextStyle(color: Colors.white54),
                              filled: true,
                              fillColor: const Color(0xFF1C1C1C),
                              border: InputBorder.none,
                              enabledBorder: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(12),
                                borderSide: BorderSide.none,
                              ),
                              focusedBorder: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(12),
                                borderSide: BorderSide.none,
                              ),
                              contentPadding: const EdgeInsets.symmetric(
                                horizontal: 14,
                                vertical: 12,
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(width: 6),
                        IconButton(
                          tooltip: '保存',
                          icon: const Icon(Icons.check_circle_outline),
                          onPressed: () {
                            _submitInput();
                            _closeInput();
                          },
                        ),
                        IconButton(
                          tooltip: '取消',
                          icon: const Icon(Icons.close),
                          onPressed: () {
                            _closeInput(clear: true);
                          },
                        ),
                      ],
                    )
                  : Center(
                      child: IconButton(
                        tooltip: '新增任务',
                        icon: const Icon(Icons.add_circle_outline, size: 28),
                        onPressed: () {
                          _openInput();
                        },
                      ),
                    ),
            ],
          ),
        ),
      ),
    );
  }

  double _calculateListHeight(int taskCount) {
    const taskHeight = 96.0;
    const emptyHeight = 88.0;
    if (taskCount == 0) {
      return emptyHeight;
    }
    final visibleCount = taskCount > AppState.maxActiveTasks
        ? AppState.maxActiveTasks
        : taskCount;
    return visibleCount * taskHeight;
  }

  double _calculateWindowHeight(int taskCount, bool showInput) {
    const paddingVertical = 24.0;
    const headerHeight = 44.0;
    const spacing = 8.0;
    const inputHeight = 56.0;
    const addButtonHeight = 44.0;
    const bottomSpacing = 8.0;
    final listHeight = _calculateListHeight(taskCount);
    final bottomHeight = showInput ? inputHeight : addButtonHeight;
    return paddingVertical +
        headerHeight +
        spacing +
        listHeight +
        spacing +
        bottomHeight +
        bottomSpacing;
  }


  void _scheduleAutoResize(double targetHeight) {
    if ((targetHeight - _lastAutoHeight).abs() < 1) {
      return;
    }
    _lastAutoHeight = targetHeight;
    _resizeDebounce?.cancel();
    _resizeDebounce = Timer(const Duration(milliseconds: 120), () async {
      final size = await windowManager.getSize();
      if ((size.height - targetHeight).abs() > 1) {
        await windowManager.setSize(Size(size.width, targetHeight));
      }
    });
  }
}
