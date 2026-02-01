import 'dart:convert';

enum WindowType { main, context, settings }

class WindowPayload {
  WindowPayload.main()
      : type = WindowType.main,
        taskId = null,
        taskTitle = null,
        contextText = null,
        ownerWindowId = null,
        settings = null;

  WindowPayload.context({
    required this.taskId,
    required this.taskTitle,
    required this.contextText,
    required this.ownerWindowId,
  })  : type = WindowType.context,
        settings = null;

  WindowPayload.settings({
    required this.ownerWindowId,
    required this.settings,
  })  : type = WindowType.settings,
        taskId = null,
        taskTitle = null,
        contextText = null;

  final WindowType type;
  final String? taskId;
  final String? taskTitle;
  final String? contextText;
  final String? ownerWindowId;
  final Map<String, dynamic>? settings;

  Map<String, dynamic> toJson() => {
        'type': type.name,
        'taskId': taskId,
        'taskTitle': taskTitle,
        'contextText': contextText,
        'ownerWindowId': ownerWindowId,
        'settings': settings,
      };

  String encode() => jsonEncode(toJson());

  static WindowPayload parse(String raw) {
    if (raw.trim().isEmpty) {
      return WindowPayload.main();
    }
    try {
      final map = jsonDecode(raw);
      if (map is! Map<String, dynamic>) {
        return WindowPayload.main();
      }
      final typeValue = WindowType.values.firstWhere(
        (value) => value.name == map['type'],
        orElse: () => WindowType.main,
      );
      if (typeValue == WindowType.context) {
        return WindowPayload.context(
          taskId: map['taskId']?.toString(),
          taskTitle: map['taskTitle']?.toString(),
          contextText: map['contextText']?.toString() ?? '',
          ownerWindowId: map['ownerWindowId']?.toString(),
        );
      }
      if (typeValue == WindowType.settings) {
        final settingsValue = map['settings'] is Map
            ? (map['settings'] as Map).cast<String, dynamic>()
            : <String, dynamic>{};
        return WindowPayload.settings(
          ownerWindowId: map['ownerWindowId']?.toString(),
          settings: settingsValue,
        );
      }
      return WindowPayload.main();
    } catch (_) {
      return WindowPayload.main();
    }
  }
}
