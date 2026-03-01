import 'dart:convert';

enum TaskStatus { todo, suspended, done }

enum FocusState { idle, running, paused, overtime }

enum SubtaskStatus { todo, done }

class Subtask {
  Subtask({
    required this.id,
    required this.taskId,
    required this.text,
    required this.status,
    required this.createdAt,
    required this.order,
    this.doneAt,
  });

  final String id;
  final String taskId;
  String text;
  SubtaskStatus status;
  DateTime createdAt;
  DateTime? doneAt;
  int order;

  bool get isDone => status == SubtaskStatus.done;

  Map<String, dynamic> toJson() => {
    'id': id,
    'taskId': taskId,
    'text': text,
    'status': status.name,
    'createdAt': createdAt.toIso8601String(),
    'doneAt': doneAt?.toIso8601String(),
    'order': order,
  };

  factory Subtask.fromJson(Map<String, dynamic> json) {
    final createdAt = DateTime.tryParse(json['createdAt'] ?? '');
    final doneAt = DateTime.tryParse(json['doneAt'] ?? '');
    final statusValue = SubtaskStatus.values.firstWhere(
      (value) => value.name == json['status'],
      orElse: () => SubtaskStatus.todo,
    );
    return Subtask(
      id: json['id'] ?? '',
      taskId: json['taskId'] ?? '',
      text: json['text'] ?? '',
      status: statusValue,
      createdAt: createdAt ?? DateTime.now(),
      doneAt: doneAt,
      order: json['order'] ?? 0,
    );
  }
}

class Task {
  Task({
    required this.id,
    required this.text,
    required this.status,
    required this.createdAt,
    required this.order,
    required this.focusDurationSec,
    required this.focusRemainingSec,
    required this.focusState,
    required this.overtimeSec,
    List<Subtask>? subtasks,
    this.activeSubtaskId,
    this.doneAt,
    this.contextText = '',
    this.contextUpdatedAt,
    this.lastTickAtMs,
  }) : subtasks = List<Subtask>.from(subtasks ?? const []);

  final String id;
  String text;
  TaskStatus status;
  DateTime createdAt;
  DateTime? doneAt;
  int order;
  String contextText;
  DateTime? contextUpdatedAt;
  FocusState focusState;
  int focusDurationSec;
  int focusRemainingSec;
  int overtimeSec;
  int? lastTickAtMs;
  List<Subtask> subtasks;
  String? activeSubtaskId;

  bool get isDone => status == TaskStatus.done;

  bool get isSuspended => status == TaskStatus.suspended;

  bool get isActive => status == TaskStatus.todo;

  bool get isOvertimePhase =>
      focusRemainingSec == 0 &&
      (focusState == FocusState.overtime || overtimeSec > 0);

  Map<String, dynamic> toJson() => {
    'id': id,
    'text': text,
    'status': status.name,
    'createdAt': createdAt.toIso8601String(),
    'doneAt': doneAt?.toIso8601String(),
    'order': order,
    'contextText': contextText,
    'contextUpdatedAt': contextUpdatedAt?.toIso8601String(),
    'focusState': focusState.name,
    'focusDurationSec': focusDurationSec,
    'focusRemainingSec': focusRemainingSec,
    'overtimeSec': overtimeSec,
    'lastTickAtMs': lastTickAtMs,
    'subtasks': subtasks.map((subtask) => subtask.toJson()).toList(),
    'activeSubtaskId': activeSubtaskId,
  };

  factory Task.fromJson(Map<String, dynamic> json) {
    final createdAt = DateTime.tryParse(json['createdAt'] ?? '');
    final doneAt = DateTime.tryParse(json['doneAt'] ?? '');
    final contextUpdatedAt = DateTime.tryParse(json['contextUpdatedAt'] ?? '');
    final statusValue = TaskStatus.values.firstWhere(
      (value) => value.name == json['status'],
      orElse: () => TaskStatus.todo,
    );
    final focusStateValue = FocusState.values.firstWhere(
      (value) => value.name == json['focusState'],
      orElse: () => FocusState.idle,
    );
    final rawSubtasks = (json['subtasks'] as List<dynamic>? ?? [])
        .whereType<Map<String, dynamic>>()
        .toList();
    return Task(
      id: json['id'] ?? '',
      text: json['text'] ?? '',
      status: statusValue,
      createdAt: createdAt ?? DateTime.now(),
      doneAt: doneAt,
      order: json['order'] ?? 0,
      contextText: json['contextText'] ?? '',
      contextUpdatedAt: contextUpdatedAt,
      focusState: focusStateValue,
      focusDurationSec: json['focusDurationSec'] ?? 1500,
      focusRemainingSec: json['focusRemainingSec'] ?? 1500,
      overtimeSec: json['overtimeSec'] ?? 0,
      lastTickAtMs: json['lastTickAtMs'],
      subtasks: rawSubtasks.map(Subtask.fromJson).toList(),
      activeSubtaskId: json['activeSubtaskId']?.toString(),
    );
  }
}

class Settings {
  Settings({
    required this.alwaysOnTop,
    required this.opacity,
    required this.showOnlyTodo,
    required this.fontScale,
    required this.defaultFocusMinutes,
    required this.enableSystemNotification,
    required this.doneTaskRetention,
    this.backupDir,
    this.windowX,
    this.windowY,
    this.windowW,
    this.windowH,
  });

  final bool alwaysOnTop;
  final double opacity;
  final bool showOnlyTodo;
  final double fontScale;
  final int defaultFocusMinutes;
  final bool enableSystemNotification;
  final int doneTaskRetention;
  final String? backupDir;
  final double? windowX;
  final double? windowY;
  final double? windowW;
  final double? windowH;

  Settings copyWith({
    bool? alwaysOnTop,
    double? opacity,
    bool? showOnlyTodo,
    double? fontScale,
    int? defaultFocusMinutes,
    bool? enableSystemNotification,
    int? doneTaskRetention,
    String? backupDir,
    double? windowX,
    double? windowY,
    double? windowW,
    double? windowH,
  }) {
    return Settings(
      alwaysOnTop: alwaysOnTop ?? this.alwaysOnTop,
      opacity: opacity ?? this.opacity,
      showOnlyTodo: showOnlyTodo ?? this.showOnlyTodo,
      fontScale: fontScale ?? this.fontScale,
      defaultFocusMinutes: defaultFocusMinutes ?? this.defaultFocusMinutes,
      enableSystemNotification:
          enableSystemNotification ?? this.enableSystemNotification,
      doneTaskRetention: doneTaskRetention ?? this.doneTaskRetention,
      backupDir: backupDir ?? this.backupDir,
      windowX: windowX ?? this.windowX,
      windowY: windowY ?? this.windowY,
      windowW: windowW ?? this.windowW,
      windowH: windowH ?? this.windowH,
    );
  }

  static Settings defaults() {
    return Settings(
      alwaysOnTop: true,
      opacity: 0.85,
      showOnlyTodo: true,
      fontScale: 1.0,
      defaultFocusMinutes: 25,
      enableSystemNotification: true,
      doneTaskRetention: 10,
    );
  }

  Map<String, dynamic> toJson() => {
    'alwaysOnTop': alwaysOnTop,
    'opacity': opacity,
    'showOnlyTodo': showOnlyTodo,
    'fontScale': fontScale,
    'defaultFocusMinutes': defaultFocusMinutes,
    'enableSystemNotification': enableSystemNotification,
    'doneTaskRetention': doneTaskRetention,
    'backupDir': backupDir,
    'windowX': windowX,
    'windowY': windowY,
    'windowW': windowW,
    'windowH': windowH,
  };

  factory Settings.fromJson(Map<String, dynamic> json) {
    return Settings(
      alwaysOnTop: json['alwaysOnTop'] ?? true,
      opacity: (json['opacity'] ?? 0.85).toDouble(),
      showOnlyTodo: json['showOnlyTodo'] ?? true,
      fontScale: (json['fontScale'] ?? 1.0).toDouble(),
      defaultFocusMinutes: json['defaultFocusMinutes'] ?? 25,
      enableSystemNotification: json['enableSystemNotification'] ?? true,
      doneTaskRetention: json['doneTaskRetention'] ?? 10,
      backupDir: json['backupDir']?.toString(),
      windowX: (json['windowX'] as num?)?.toDouble(),
      windowY: (json['windowY'] as num?)?.toDouble(),
      windowW: (json['windowW'] as num?)?.toDouble(),
      windowH: (json['windowH'] as num?)?.toDouble(),
    );
  }
}

class AppData {
  AppData({
    required this.tasks,
    required this.settings,
    required this.currentTaskId,
  });

  final List<Task> tasks;
  final Settings settings;
  final String? currentTaskId;

  Map<String, dynamic> toJson() => {
    'tasks': tasks.map((task) => task.toJson()).toList(),
    'settings': settings.toJson(),
    'currentTaskId': currentTaskId,
  };

  factory AppData.fromJson(Map<String, dynamic> json) {
    final rawTasks = (json['tasks'] as List<dynamic>? ?? [])
        .whereType<Map<String, dynamic>>()
        .toList();
    return AppData(
      tasks: rawTasks.map(Task.fromJson).toList(),
      settings: json['settings'] is Map<String, dynamic>
          ? Settings.fromJson(json['settings'])
          : Settings.defaults(),
      currentTaskId: json['currentTaskId'],
    );
  }

  static AppData empty() =>
      AppData(tasks: [], settings: Settings.defaults(), currentTaskId: null);
}

String encodeAppData(AppData data) => jsonEncode(data.toJson());

AppData decodeAppData(String raw) {
  final json = jsonDecode(raw) as Map<String, dynamic>;
  return AppData.fromJson(json);
}
