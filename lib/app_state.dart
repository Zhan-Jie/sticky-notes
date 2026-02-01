import 'dart:async';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:local_notifier/local_notifier.dart';

import 'models.dart';
import 'storage.dart';

class AddResult {
  AddResult({required this.added, required this.truncated});

  final int added;
  final int truncated;
}

class RemovedTask {
  RemovedTask({required this.task, required this.index});

  final Task task;
  final int index;
}

class AppState extends ChangeNotifier {
  AppState(this.storage);

  final StorageService storage;

  List<Task> tasks = [];
  Settings settings = Settings.defaults();
  String? currentTaskId;
  bool initialized = false;
  bool forceOpaque = false;

  Timer? _ticker;
  Timer? _saveDebounce;

  Future<void> load() async {
    final data = await storage.load();
    tasks = data.tasks;
    settings = data.settings;
    currentTaskId = data.currentTaskId;
    _ensureOrder();
    _normalizeTasks();
    _resumeRunningTasks();
    initialized = true;
    _startTicker();
    notifyListeners();
  }

  Future<void> save() async {
    await storage.save(
      AppData(tasks: tasks, settings: settings, currentTaskId: currentTaskId),
    );
  }

  void _scheduleSave([Duration delay = const Duration(milliseconds: 300)]) {
    _saveDebounce?.cancel();
    _saveDebounce = Timer(delay, () {
      save();
    });
  }

  void _startTicker() {
    _ticker?.cancel();
    _ticker = Timer.periodic(const Duration(seconds: 1), (_) => _tick());
  }

  void _tick() {
    final runningTask = tasks.firstWhere(
      (task) => task.focusState == FocusState.running,
      orElse: () => Task(
        id: '',
        text: '',
        status: TaskStatus.todo,
        createdAt: DateTime.now(),
        order: 0,
        focusDurationSec: 0,
        focusRemainingSec: 0,
        focusState: FocusState.idle,
        overtimeSec: 0,
      ),
    );
    if (runningTask.id.isEmpty) {
      final overtimeTask = tasks.firstWhere(
        (task) => task.focusState == FocusState.overtime,
        orElse: () => Task(
          id: '',
          text: '',
          status: TaskStatus.todo,
          createdAt: DateTime.now(),
          order: 0,
          focusDurationSec: 0,
          focusRemainingSec: 0,
          focusState: FocusState.idle,
          overtimeSec: 0,
        ),
      );
      if (overtimeTask.id.isEmpty) {
        return;
      }
      _applyDelta(overtimeTask);
      notifyListeners();
      return;
    }
    final transitioned = _applyDelta(runningTask);
    if (transitioned) {
      _scheduleSave();
    }
    notifyListeners();
  }

  bool _applyDelta(Task task) {
    final nowMs = DateTime.now().millisecondsSinceEpoch;
    final last = task.lastTickAtMs ?? nowMs;
    final deltaSec = max(0, ((nowMs - last) / 1000).floor());
    task.lastTickAtMs = nowMs;
    if (deltaSec == 0) {
      return false;
    }
    if (task.focusState == FocusState.running) {
      final remaining = task.focusRemainingSec - deltaSec;
      if (remaining <= 0) {
        task.focusRemainingSec = 0;
        task.focusState = FocusState.overtime;
        task.overtimeSec += -remaining;
        _moveTaskToBottom(task);
        if (settings.enableSystemNotification) {
          _notifyOvertime(task);
        }
        return true;
      }
      task.focusRemainingSec = remaining;
    } else if (task.focusState == FocusState.overtime) {
      task.overtimeSec += deltaSec;
    }
    return false;
  }

  void _resumeRunningTasks() {
    final now = DateTime.now().millisecondsSinceEpoch;
    for (final task in tasks) {
      if (task.focusState == FocusState.running ||
          task.focusState == FocusState.overtime) {
        final last = task.lastTickAtMs ?? now;
        final deltaSec = max(0, ((now - last) / 1000).floor());
        task.lastTickAtMs = now;
        if (deltaSec == 0) {
          continue;
        }
        if (task.focusState == FocusState.running) {
          final remaining = task.focusRemainingSec - deltaSec;
          if (remaining <= 0) {
            task.focusRemainingSec = 0;
            task.focusState = FocusState.overtime;
            task.overtimeSec += -remaining;
            _moveTaskToBottom(task);
          } else {
            task.focusRemainingSec = remaining;
          }
        } else {
          task.overtimeSec += deltaSec;
        }
      }
    }
  }

  void _notifyOvertime(Task task) {
    final notification = LocalNotification(
      title: '专注到点了',
      body: '「${task.text}」进入超时计时',
    );
    notification.show();
  }

  void _ensureOrder() {
    tasks.sort((a, b) => a.order.compareTo(b.order));
    for (var i = 0; i < tasks.length; i++) {
      tasks[i].order = i;
    }
  }

  void _normalizeTasks() {
    for (final task in tasks) {
      if (task.focusDurationSec <= 0) {
        task.focusDurationSec = settings.defaultFocusMinutes * 60;
      }
      if (task.focusRemainingSec <= 0 && task.focusState == FocusState.idle) {
        task.focusRemainingSec = task.focusDurationSec;
      }
    }
  }

  List<Task> sortedTasks({required bool includeDone}) {
    final list = tasks.toList()..sort((a, b) => a.order.compareTo(b.order));
    if (includeDone) {
      return list;
    }
    return list.where((task) => !task.isDone).toList();
  }

  AddResult addTasks(List<String> lines) {
    final trimmed = lines.map((line) => line.trim()).where((line) {
      return line.isNotEmpty;
    }).toList();
    if (trimmed.isEmpty) {
      return AddResult(added: 0, truncated: 0);
    }
    final todoCount = tasks.where((task) => !task.isDone).length;
    final available = max(0, 5 - todoCount);
    final toAdd = trimmed.take(available).toList();
    final truncated = max(0, trimmed.length - toAdd.length);
    if (toAdd.isEmpty) {
      return AddResult(added: 0, truncated: trimmed.length);
    }
    final nextOrder =
        tasks.isEmpty ? 0 : tasks.map((task) => task.order).reduce(max) + 1;
    for (var i = 0; i < toAdd.length; i++) {
      final now = DateTime.now();
      tasks.add(
        Task(
          id: now.microsecondsSinceEpoch.toString() + i.toString(),
          text: toAdd[i],
          status: TaskStatus.todo,
          createdAt: now,
          order: nextOrder + i,
          focusDurationSec: settings.defaultFocusMinutes * 60,
          focusRemainingSec: settings.defaultFocusMinutes * 60,
          focusState: FocusState.idle,
          overtimeSec: 0,
        ),
      );
    }
    _scheduleSave();
    notifyListeners();
    return AddResult(added: toAdd.length, truncated: truncated);
  }

  void updateTaskText(String id, String text) {
    final task = tasks.firstWhere((task) => task.id == id, orElse: () => Task(
      id: '',
      text: '',
      status: TaskStatus.todo,
      createdAt: DateTime.now(),
      order: 0,
      focusDurationSec: 0,
      focusRemainingSec: 0,
      focusState: FocusState.idle,
      overtimeSec: 0,
    ));
    if (task.id.isEmpty) {
      return;
    }
    final trimmed = text.trim();
    if (trimmed.isEmpty) {
      return;
    }
    task.text = trimmed;
    _scheduleSave();
    notifyListeners();
  }

  void updateTaskContext(String id, String text) {
    final task = tasks.firstWhere((task) => task.id == id, orElse: () => Task(
      id: '',
      text: '',
      status: TaskStatus.todo,
      createdAt: DateTime.now(),
      order: 0,
      focusDurationSec: 0,
      focusRemainingSec: 0,
      focusState: FocusState.idle,
      overtimeSec: 0,
    ));
    if (task.id.isEmpty) {
      return;
    }
    task.contextText = text.trimRight();
    task.contextUpdatedAt = DateTime.now();
    _scheduleSave();
    notifyListeners();
  }

  void toggleDone(String id) {
    final task = tasks.firstWhere((task) => task.id == id, orElse: () => Task(
      id: '',
      text: '',
      status: TaskStatus.todo,
      createdAt: DateTime.now(),
      order: 0,
      focusDurationSec: 0,
      focusRemainingSec: 0,
      focusState: FocusState.idle,
      overtimeSec: 0,
    ));
    if (task.id.isEmpty) {
      return;
    }
    if (task.isDone) {
      task.status = TaskStatus.todo;
      task.doneAt = null;
    } else {
      task.status = TaskStatus.done;
      task.doneAt = DateTime.now();
      if (task.focusState == FocusState.running ||
          task.focusState == FocusState.overtime) {
        task.focusState = FocusState.idle;
        task.focusRemainingSec = task.focusDurationSec;
        task.overtimeSec = 0;
        task.lastTickAtMs = null;
      }
    }
    _scheduleSave();
    notifyListeners();
  }

  RemovedTask? removeTask(String id) {
    final index = tasks.indexWhere((task) => task.id == id);
    if (index < 0) {
      return null;
    }
    final removed = tasks.removeAt(index);
    if (currentTaskId == removed.id) {
      currentTaskId = null;
    }
    _scheduleSave();
    notifyListeners();
    return RemovedTask(task: removed, index: index);
  }

  void restoreTask(RemovedTask removed) {
    final insertIndex = removed.index.clamp(0, tasks.length);
    tasks.insert(insertIndex, removed.task);
    _scheduleSave();
    notifyListeners();
  }

  void setCurrentTask(String id) {
    if (currentTaskId == id) {
      return;
    }
    final runningIndex = tasks.indexWhere(
      (task) => task.focusState == FocusState.running,
    );
    if (runningIndex >= 0 && tasks[runningIndex].id != id) {
      tasks[runningIndex].focusState = FocusState.paused;
      tasks[runningIndex].lastTickAtMs = null;
    }
    currentTaskId = id;
    _scheduleSave();
    notifyListeners();
  }

  void startTask(String id) {
    final task = tasks.firstWhere((task) => task.id == id, orElse: () => Task(
      id: '',
      text: '',
      status: TaskStatus.todo,
      createdAt: DateTime.now(),
      order: 0,
      focusDurationSec: 0,
      focusRemainingSec: 0,
      focusState: FocusState.idle,
      overtimeSec: 0,
    ));
    if (task.id.isEmpty || task.isDone) {
      return;
    }
    for (final other in tasks) {
      if (other.id == task.id) {
        continue;
      }
      if (other.focusState == FocusState.running ||
          other.focusState == FocusState.overtime) {
        other.focusState = FocusState.paused;
        other.lastTickAtMs = null;
      }
    }
    currentTaskId = task.id;
    if (task.focusState == FocusState.idle) {
      task.focusRemainingSec = task.focusDurationSec;
      task.focusState = FocusState.running;
    } else if (task.focusState == FocusState.paused) {
      if (task.focusRemainingSec == 0) {
        task.focusState = FocusState.overtime;
      } else {
        task.focusState = FocusState.running;
      }
    } else if (task.focusState == FocusState.overtime) {
      task.focusState = FocusState.overtime;
    } else {
      task.focusState = FocusState.running;
    }
    task.lastTickAtMs = DateTime.now().millisecondsSinceEpoch;
    _scheduleSave();
    notifyListeners();
  }

  void pauseTask(String id) {
    final task = tasks.firstWhere((task) => task.id == id, orElse: () => Task(
      id: '',
      text: '',
      status: TaskStatus.todo,
      createdAt: DateTime.now(),
      order: 0,
      focusDurationSec: 0,
      focusRemainingSec: 0,
      focusState: FocusState.idle,
      overtimeSec: 0,
    ));
    if (task.id.isEmpty) {
      return;
    }
    if (task.focusState == FocusState.running ||
        task.focusState == FocusState.overtime) {
      task.focusState = FocusState.paused;
      task.lastTickAtMs = null;
      _scheduleSave();
      notifyListeners();
    }
  }

  void resetTask(String id) {
    final task = tasks.firstWhere((task) => task.id == id, orElse: () => Task(
      id: '',
      text: '',
      status: TaskStatus.todo,
      createdAt: DateTime.now(),
      order: 0,
      focusDurationSec: 0,
      focusRemainingSec: 0,
      focusState: FocusState.idle,
      overtimeSec: 0,
    ));
    if (task.id.isEmpty) {
      return;
    }
    task.focusState = FocusState.idle;
    task.focusDurationSec = max(60, task.focusDurationSec);
    task.focusRemainingSec = task.focusDurationSec;
    task.overtimeSec = 0;
    task.lastTickAtMs = null;
    _scheduleSave();
    notifyListeners();
  }

  void updateSettings(Settings newSettings) {
    settings = newSettings;
    _scheduleSave();
    notifyListeners();
  }

  void setForceOpaque(bool value) {
    if (forceOpaque == value) {
      return;
    }
    forceOpaque = value;
    notifyListeners();
  }

  void updateWindowBounds({
    required double x,
    required double y,
    required double width,
    required double height,
  }) {
    settings = settings.copyWith(
      windowX: x,
      windowY: y,
      windowW: width,
      windowH: height,
    );
    _scheduleSave(const Duration(milliseconds: 800));
  }

  void updateDefaultFocusMinutes(int minutes) {
    settings = settings.copyWith(defaultFocusMinutes: minutes);
    for (final task in tasks) {
      if (task.focusState == FocusState.idle &&
          task.focusRemainingSec == task.focusDurationSec) {
        task.focusDurationSec = minutes * 60;
        task.focusRemainingSec = minutes * 60;
      }
    }
    _scheduleSave();
    notifyListeners();
  }

  void _moveTaskToBottom(Task task) {
    final maxOrder =
        tasks.isEmpty ? 0 : tasks.map((t) => t.order).reduce(max);
    task.order = maxOrder + 1;
  }

  @override
  void dispose() {
    _ticker?.cancel();
    _saveDebounce?.cancel();
    super.dispose();
  }
}
