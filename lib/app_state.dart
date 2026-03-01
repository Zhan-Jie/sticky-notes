import 'dart:async';
import 'dart:io';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:local_notifier/local_notifier.dart';

import 'models.dart';
import 'storage.dart';

class AddResult {
  AddResult({required this.added, required this.suspended});

  final int added;
  final int suspended;
}

class RemovedTask {
  RemovedTask({required this.task, required this.index});

  final Task task;
  final int index;
}

class ArchiveResult {
  ArchiveResult({
    required this.success,
    required this.exportedCount,
    this.filePath,
    this.message,
  });

  final bool success;
  final int exportedCount;
  final String? filePath;
  final String? message;

  Map<String, dynamic> toJson() => {
    'success': success,
    'exportedCount': exportedCount,
    'filePath': filePath,
    'message': message,
  };
}

class AppState extends ChangeNotifier {
  AppState(this.storage);

  final StorageService storage;
  static const int maxActiveTasks = 5;

  List<Task> tasks = [];
  Settings settings = Settings.defaults();
  String? currentTaskId;
  bool initialized = false;
  bool forceOpaque = false;
  int subtaskCollapseSignal = 0;

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
    _ensureActiveLimit();
    await archiveDoneTasksIfNeeded();
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
      orElse: _placeholderTask,
    );
    if (runningTask.id.isEmpty) {
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
        task.focusState = FocusState.idle;
        task.lastTickAtMs = null;
        _notifyFocusCompleted(task);
        return true;
      }
      task.focusRemainingSec = remaining;
    }
    return false;
  }

  void _notifyFocusCompleted(Task task) {
    if (!settings.enableSystemNotification) {
      return;
    }
    if (task.focusDurationSec <= 0) {
      return;
    }
    try {
      final title = '专注结束';
      final body = task.text.trim().isEmpty
          ? '番茄钟计时已结束'
          : '任务「${task.text.trim()}」计时结束';
      final notification = LocalNotification(title: title, body: body);
      notification.show();
    } catch (_) {}
  }

  void _resumeRunningTasks() {
    final now = DateTime.now().millisecondsSinceEpoch;
    var changed = false;
    for (final task in tasks) {
      if (task.focusState == FocusState.running) {
        final last = task.lastTickAtMs ?? now;
        final deltaSec = max(0, ((now - last) / 1000).floor());
        task.lastTickAtMs = now;
        if (deltaSec == 0) {
          continue;
        }
        final remaining = task.focusRemainingSec - deltaSec;
        if (remaining <= 0) {
          task.focusRemainingSec = 0;
          task.focusState = FocusState.idle;
          task.lastTickAtMs = null;
          _notifyFocusCompleted(task);
          changed = true;
        } else {
          task.focusRemainingSec = remaining;
          changed = true;
        }
      }
    }
    if (changed) {
      _scheduleSave();
    }
  }

  void _ensureOrder() {
    tasks.sort((a, b) => a.order.compareTo(b.order));
    for (var i = 0; i < tasks.length; i += 1) {
      tasks[i].order = i;
    }
  }

  void _normalizeTasks() {
    for (final task in tasks) {
      if (task.focusDurationSec <= 0) {
        task.focusDurationSec = settings.defaultFocusMinutes * 60;
      }
      if (task.focusRemainingSec < 0) {
        task.focusRemainingSec = 0;
      }
      if (task.focusState == FocusState.overtime) {
        task.focusState = FocusState.idle;
        task.focusRemainingSec = 0;
        task.overtimeSec = 0;
        task.lastTickAtMs = null;
      }
      if (task.isSuspended && task.focusState != FocusState.idle) {
        task.focusState = FocusState.idle;
        task.lastTickAtMs = null;
      }
      task.subtasks.sort((a, b) => a.order.compareTo(b.order));
      for (var i = 0; i < task.subtasks.length; i += 1) {
        task.subtasks[i].order = i;
      }
      final activeId = task.activeSubtaskId;
      if (activeId != null &&
          task.subtasks.every((subtask) => subtask.id != activeId)) {
        task.activeSubtaskId = null;
      }
    }
  }

  void _ensureActiveLimit() {
    for (final task in tasks) {
      if (!task.isDone &&
          task.isSuspended &&
          task.focusState != FocusState.idle) {
        task.focusState = FocusState.idle;
        task.lastTickAtMs = null;
      }
    }
    _demoteExtraActive();
    _cleanupCurrentTask();
  }

  void _demoteExtraActive() {
    final active = tasks
        .where((task) => !task.isDone && task.isActive)
        .toList();
    final excess = active.length - maxActiveTasks;
    if (excess <= 0) {
      return;
    }
    final demoteCandidates = <Task>[
      ...active.where(
        (task) =>
            task.focusState == FocusState.idle ||
            task.focusState == FocusState.paused,
      ),
    ];
    if (demoteCandidates.length < excess) {
      demoteCandidates.addAll(
        active.where((task) => task.focusState == FocusState.running),
      );
    }
    demoteCandidates.sort((a, b) => b.order.compareTo(a.order));
    for (final task in demoteCandidates.take(excess)) {
      task.status = TaskStatus.suspended;
      task.focusState = FocusState.idle;
      task.lastTickAtMs = null;
    }
  }

  void _cleanupCurrentTask() {
    if (currentTaskId == null) {
      return;
    }
    final task = _findTask(currentTaskId!);
    if (task == null || task.isDone || task.isSuspended) {
      currentTaskId = null;
    }
  }

  Task? _findTask(String id) {
    for (final task in tasks) {
      if (task.id == id) {
        return task;
      }
    }
    return null;
  }

  Task _placeholderTask() {
    return Task(
      id: '',
      text: '',
      status: TaskStatus.todo,
      createdAt: DateTime.now(),
      order: 0,
      focusDurationSec: 0,
      focusRemainingSec: 0,
      focusState: FocusState.idle,
      overtimeSec: 0,
    );
  }

  List<Task> sortedTasks({required bool includeDone}) {
    final list = tasks.toList()..sort((a, b) => a.order.compareTo(b.order));
    if (includeDone) {
      return list;
    }
    return list.where((task) => !task.isDone && !task.isSuspended).toList();
  }

  bool isTaskInProgress(Task task) {
    if (task.isDone || task.isSuspended) {
      return false;
    }
    final activeSubtaskId = task.activeSubtaskId;
    if (activeSubtaskId != null &&
        task.subtasks.any((subtask) => subtask.id == activeSubtaskId)) {
      return true;
    }
    if (task.subtasks.any((subtask) => subtask.isDone)) {
      return true;
    }
    return task.focusState == FocusState.running || task.isOvertimePhase;
  }

  String? activeSubtaskText(Task task) {
    final activeId = task.activeSubtaskId;
    if (activeId == null) {
      return null;
    }
    for (final subtask in task.subtasks) {
      if (subtask.id == activeId) {
        return subtask.text;
      }
    }
    return null;
  }

  AddResult addTasks(List<String> lines) {
    final trimmed = lines.map((line) => line.trim()).where((line) {
      return line.isNotEmpty;
    }).toList();
    if (trimmed.isEmpty) {
      return AddResult(added: 0, suspended: 0);
    }
    var available =
        maxActiveTasks -
        tasks.where((task) => !task.isDone && task.isActive).length;
    final nextOrder = tasks.isEmpty
        ? 0
        : tasks.map((task) => task.order).reduce(max) + 1;
    var suspendedAdded = 0;
    for (var i = 0; i < trimmed.length; i += 1) {
      final now = DateTime.now();
      final status = available > 0 ? TaskStatus.todo : TaskStatus.suspended;
      if (available > 0) {
        available -= 1;
      } else {
        suspendedAdded += 1;
      }
      tasks.add(
        Task(
          id: '${now.microsecondsSinceEpoch}$i',
          text: trimmed[i],
          status: status,
          createdAt: now,
          order: nextOrder + i,
          focusDurationSec: settings.defaultFocusMinutes * 60,
          focusRemainingSec: settings.defaultFocusMinutes * 60,
          focusState: FocusState.idle,
          overtimeSec: 0,
        ),
      );
    }
    _ensureActiveLimit();
    _scheduleSave();
    notifyListeners();
    return AddResult(added: trimmed.length, suspended: suspendedAdded);
  }

  bool addSubtask(String taskId, String text) {
    final task = _findTask(taskId);
    if (task == null) {
      return false;
    }
    task.subtasks = List<Subtask>.from(task.subtasks);
    final trimmed = text.trim();
    if (trimmed.isEmpty) {
      return false;
    }
    final nextOrder = task.subtasks.isEmpty
        ? 0
        : task.subtasks.map((subtask) => subtask.order).reduce(max) + 1;
    final now = DateTime.now();
    task.subtasks.add(
      Subtask(
        id: '${now.microsecondsSinceEpoch}${task.subtasks.length}',
        taskId: task.id,
        text: trimmed,
        status: SubtaskStatus.todo,
        createdAt: now,
        order: nextOrder,
      ),
    );
    if (task.isDone) {
      task.status = TaskStatus.todo;
      task.doneAt = null;
    }
    _scheduleSave();
    notifyListeners();
    return true;
  }

  void toggleSubtaskDone(String taskId, String subtaskId) {
    final task = _findTask(taskId);
    if (task == null) {
      return;
    }
    Subtask? subtask;
    for (final item in task.subtasks) {
      if (item.id == subtaskId) {
        subtask = item;
        break;
      }
    }
    if (subtask == null) {
      return;
    }
    if (subtask.isDone) {
      subtask.status = SubtaskStatus.todo;
      subtask.doneAt = null;
      if (task.isDone) {
        task.status = TaskStatus.todo;
        task.doneAt = null;
      }
    } else {
      subtask.status = SubtaskStatus.done;
      subtask.doneAt = DateTime.now();
      if (task.activeSubtaskId == subtask.id) {
        _advanceActiveSubtask(task, fromOrder: subtask.order);
      }
    }
    _scheduleSave();
    notifyListeners();
  }

  void toggleActiveSubtask(String taskId, String subtaskId) {
    final task = _findTask(taskId);
    if (task == null) {
      return;
    }
    Subtask? subtask;
    for (final item in task.subtasks) {
      if (item.id == subtaskId) {
        subtask = item;
        break;
      }
    }
    if (subtask == null || subtask.isDone) {
      return;
    }
    if (task.activeSubtaskId == subtask.id) {
      task.activeSubtaskId = null;
    } else {
      task.activeSubtaskId = subtask.id;
    }
    _scheduleSave();
    notifyListeners();
  }

  void removeSubtask(String taskId, String subtaskId) {
    final task = _findTask(taskId);
    if (task == null) {
      return;
    }
    final index = task.subtasks.indexWhere(
      (subtask) => subtask.id == subtaskId,
    );
    if (index < 0) {
      return;
    }
    final removed = task.subtasks.removeAt(index);
    for (var i = 0; i < task.subtasks.length; i += 1) {
      task.subtasks[i].order = i;
    }
    if (task.activeSubtaskId == removed.id) {
      _advanceActiveSubtask(task, fromOrder: removed.order);
    }
    _scheduleSave();
    notifyListeners();
  }

  void _advanceActiveSubtask(Task task, {required int fromOrder}) {
    final todo = task.subtasks.where((subtask) => !subtask.isDone).toList()
      ..sort((a, b) => a.order.compareTo(b.order));
    if (todo.isEmpty) {
      task.activeSubtaskId = null;
      return;
    }
    for (final subtask in todo) {
      if (subtask.order > fromOrder) {
        task.activeSubtaskId = subtask.id;
        return;
      }
    }
    task.activeSubtaskId = todo.first.id;
  }

  void updateTaskText(String id, String text) {
    final task = _findTask(id);
    if (task == null) {
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
    final task = _findTask(id);
    if (task == null) {
      return;
    }
    task.contextText = text.trimRight();
    task.contextUpdatedAt = DateTime.now();
    _scheduleSave();
    notifyListeners();
  }

  Future<ArchiveResult?> toggleDone(String id) async {
    final task = _findTask(id);
    if (task == null) {
      return null;
    }
    final wasDone = task.isDone;
    if (task.isDone) {
      final activeCount = tasks
          .where((item) => !item.isDone && item.isActive)
          .length;
      task.status = activeCount < maxActiveTasks
          ? TaskStatus.todo
          : TaskStatus.suspended;
      task.doneAt = null;
    } else {
      task.status = TaskStatus.done;
      task.doneAt = DateTime.now();
      if (task.focusState == FocusState.running) {
        task.focusState = FocusState.idle;
        task.focusRemainingSec = task.focusDurationSec;
        task.overtimeSec = 0;
        task.lastTickAtMs = null;
      }
    }
    _ensureActiveLimit();
    _scheduleSave();
    notifyListeners();

    if (!wasDone && task.isDone) {
      final result = await archiveDoneTasksIfNeeded();
      if (!result.success || result.exportedCount > 0) {
        return result;
      }
    }
    return null;
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
    _ensureActiveLimit();
    _scheduleSave();
    notifyListeners();
    return RemovedTask(task: removed, index: index);
  }

  void restoreTask(RemovedTask removed) {
    final insertIndex = removed.index.clamp(0, tasks.length);
    tasks.insert(insertIndex, removed.task);
    _ensureActiveLimit();
    _scheduleSave();
    notifyListeners();
  }

  void setCurrentTask(String id) {
    if (currentTaskId == id) {
      return;
    }
    collapseExpandedSubtasks();
    final task = _findTask(id);
    if (task == null || task.isDone || task.isSuspended) {
      return;
    }
    final runningIndex = tasks.indexWhere(
      (item) => item.focusState == FocusState.running,
    );
    if (runningIndex >= 0 && tasks[runningIndex].id != id) {
      tasks[runningIndex].focusState = FocusState.paused;
      tasks[runningIndex].lastTickAtMs = null;
    }
    currentTaskId = id;
    _scheduleSave();
    notifyListeners();
  }

  void updateSubtaskText(String taskId, String subtaskId, String text) {
    final task = _findTask(taskId);
    if (task == null) {
      return;
    }
    Subtask? target;
    for (final subtask in task.subtasks) {
      if (subtask.id == subtaskId) {
        target = subtask;
        break;
      }
    }
    if (target == null) {
      return;
    }
    final trimmed = text.trim();
    if (trimmed.isEmpty) {
      return;
    }
    target.text = trimmed;
    _scheduleSave();
    notifyListeners();
  }

  void reorderTodoSubtasks(String taskId, List<String> orderedTodoIds) {
    final task = _findTask(taskId);
    if (task == null) {
      return;
    }
    final todos = task.subtasks.where((subtask) => !subtask.isDone).toList();
    if (todos.length <= 1 || orderedTodoIds.length != todos.length) {
      return;
    }
    final idSet = orderedTodoIds.toSet();
    if (idSet.length != orderedTodoIds.length) {
      return;
    }
    if (todos.any((subtask) => !idSet.contains(subtask.id))) {
      return;
    }
    final byId = <String, Subtask>{};
    for (final subtask in task.subtasks) {
      byId[subtask.id] = subtask;
    }
    final reorderedTodos = <Subtask>[];
    for (final id in orderedTodoIds) {
      final subtask = byId[id];
      if (subtask == null || subtask.isDone) {
        return;
      }
      reorderedTodos.add(subtask);
    }
    final doneSubtasks =
        task.subtasks.where((subtask) => subtask.isDone).toList()
          ..sort((a, b) => a.order.compareTo(b.order));
    task.subtasks = [...reorderedTodos, ...doneSubtasks];
    for (var i = 0; i < task.subtasks.length; i += 1) {
      task.subtasks[i].order = i;
    }
    _scheduleSave();
    notifyListeners();
  }

  void startTask(String id) {
    final task = _findTask(id);
    if (task == null || task.isDone || task.isSuspended) {
      return;
    }
    for (final other in tasks) {
      if (other.id == task.id) {
        continue;
      }
      if (other.focusState == FocusState.running) {
        other.focusState = FocusState.paused;
        other.lastTickAtMs = null;
      }
    }
    currentTaskId = task.id;
    if (task.focusState == FocusState.idle) {
      final focusDurationSec = settings.defaultFocusMinutes * 60;
      task.focusDurationSec = focusDurationSec;
      task.focusRemainingSec = focusDurationSec;
      task.focusState = FocusState.running;
    } else {
      task.focusState = FocusState.running;
    }
    task.lastTickAtMs = DateTime.now().millisecondsSinceEpoch;
    _scheduleSave();
    notifyListeners();
  }

  void pauseTask(String id) {
    final task = _findTask(id);
    if (task == null || task.isSuspended) {
      return;
    }
    if (task.focusState == FocusState.running) {
      task.focusState = FocusState.paused;
      task.lastTickAtMs = null;
      _scheduleSave();
      notifyListeners();
    }
  }

  void resetTask(String id) {
    final task = _findTask(id);
    if (task == null || task.isSuspended) {
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

  void toggleSuspend(String id) {
    final task = _findTask(id);
    if (task == null || task.isDone) {
      return;
    }
    if (task.isSuspended) {
      final activeCount = tasks
          .where((item) => !item.isDone && item.isActive)
          .length;
      if (activeCount >= maxActiveTasks) {
        return;
      }
      task.status = TaskStatus.todo;
    } else {
      task.status = TaskStatus.suspended;
      task.focusState = FocusState.idle;
      task.lastTickAtMs = null;
      if (currentTaskId == task.id) {
        currentTaskId = null;
      }
    }
    _ensureActiveLimit();
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

  void collapseExpandedSubtasks() {
    subtaskCollapseSignal += 1;
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

  Future<ArchiveResult> exportAllDoneTasks() {
    return archiveDoneTasksIfNeeded(forceAll: true);
  }

  Future<ArchiveResult> archiveDoneTasksIfNeeded({
    bool forceAll = false,
  }) async {
    final doneTasks = tasks.where((task) => task.isDone).toList();
    if (doneTasks.isEmpty) {
      return ArchiveResult(success: true, exportedCount: 0);
    }

    doneTasks.sort((a, b) {
      final aTime = a.doneAt ?? a.createdAt;
      final bTime = b.doneAt ?? b.createdAt;
      return bTime.compareTo(aTime);
    });

    final retention = settings.doneTaskRetention < 0
        ? 0
        : settings.doneTaskRetention;
    final exportTargets = forceAll
        ? doneTasks
        : (doneTasks.length > retention
              ? doneTasks.sublist(retention)
              : <Task>[]);
    if (exportTargets.isEmpty) {
      return ArchiveResult(success: true, exportedCount: 0);
    }

    exportTargets.sort((a, b) {
      final aTime = a.doneAt ?? a.createdAt;
      final bTime = b.doneAt ?? b.createdAt;
      return aTime.compareTo(bTime);
    });

    try {
      final backupDir = await storage.resolveBackupDirectory(
        settings.backupDir,
      );
      final now = DateTime.now();
      final fileName = 'sticky-notes-done-${_yearMonth(now)}.md';
      final file = File('${backupDir.path}/$fileName');
      final content = _buildArchiveMarkdown(now, exportTargets);
      await file.writeAsString(content, mode: FileMode.append, flush: true);

      final removedIds = exportTargets.map((task) => task.id).toSet();
      tasks.removeWhere((task) => removedIds.contains(task.id));
      if (currentTaskId != null && removedIds.contains(currentTaskId)) {
        currentTaskId = null;
      }
      _ensureOrder();
      _ensureActiveLimit();
      await save();
      notifyListeners();

      return ArchiveResult(
        success: true,
        exportedCount: exportTargets.length,
        filePath: file.path,
        message: '已导出 ${exportTargets.length} 个已完成任务',
      );
    } catch (error) {
      return ArchiveResult(
        success: false,
        exportedCount: 0,
        message: '导出失败：$error',
      );
    }
  }

  String _buildArchiveMarkdown(DateTime exportedAt, List<Task> exportTargets) {
    final buffer = StringBuffer();
    buffer.writeln('## 导出时间：${_formatDateTime(exportedAt)}');
    buffer.writeln();
    for (final task in exportTargets) {
      final doneAt = task.doneAt != null ? _formatDateTime(task.doneAt!) : '-';
      buffer.writeln('- [x] ${task.text} (doneAt: $doneAt)');
      if (task.subtasks.isNotEmpty) {
        buffer.writeln('  - 子任务:');
        final subtasks = task.subtasks.toList()
          ..sort((a, b) => a.order.compareTo(b.order));
        for (final subtask in subtasks) {
          final mark = subtask.isDone ? 'x' : ' ';
          buffer.writeln('    - [$mark] ${subtask.text}');
        }
      }
      final activeText = activeSubtaskText(task);
      if (activeText != null && activeText.trim().isNotEmpty) {
        buffer.writeln('  - 当前事项: $activeText');
      }
      if (task.contextText.trim().isNotEmpty) {
        buffer.writeln('  - 上下文: ${task.contextText.trim()}');
      }
      buffer.writeln();
    }
    return buffer.toString();
  }

  String _yearMonth(DateTime value) {
    final year = value.year.toString().padLeft(4, '0');
    final month = value.month.toString().padLeft(2, '0');
    return '$year-$month';
  }

  String _formatDateTime(DateTime value) {
    final year = value.year.toString().padLeft(4, '0');
    final month = value.month.toString().padLeft(2, '0');
    final day = value.day.toString().padLeft(2, '0');
    final hour = value.hour.toString().padLeft(2, '0');
    final minute = value.minute.toString().padLeft(2, '0');
    return '$year-$month-$day $hour:$minute';
  }

  @override
  void dispose() {
    _ticker?.cancel();
    _saveDebounce?.cancel();
    super.dispose();
  }
}
