import 'dart:async';

import 'package:flutter/material.dart';

import '../app_state.dart';
import '../models.dart';

class TaskItem extends StatefulWidget {
  const TaskItem({
    super.key,
    required this.task,
    required this.appState,
    required this.isCurrent,
    required this.onOpenContext,
  });

  final Task task;
  final AppState appState;
  final bool isCurrent;
  final Future<void> Function(Task task) onOpenContext;

  @override
  State<TaskItem> createState() => _TaskItemState();
}

class _TaskItemState extends State<TaskItem> {
  late final TextEditingController _controller;
  final FocusNode _focusNode = FocusNode();
  bool _hovered = false;
  bool _editing = false;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.task.text);
    _focusNode.addListener(() {
      if (!_focusNode.hasFocus && _editing) {
        _finishEditing();
      }
    });
  }

  @override
  void didUpdateWidget(covariant TaskItem oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.task.text != widget.task.text && !_editing) {
      _controller.text = widget.task.text;
    }
  }

  void _startEditing() {
    if (widget.task.isDone) {
      return;
    }
    setState(() {
      _editing = true;
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _focusNode.requestFocus();
      _controller.selection = TextSelection(
        baseOffset: 0,
        extentOffset: _controller.text.length,
      );
    });
  }

  void _finishEditing() {
    final text = _controller.text;
    widget.appState.updateTaskText(widget.task.id, text);
    setState(() {
      _editing = false;
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final task = widget.task;
    final textColor = task.isDone
        ? Colors.white54
        : (task.isSuspended
            ? Colors.white38
            : Colors.white);
    final showActions = _hovered || widget.isCurrent || _editing;
    final isRunning = task.focusState == FocusState.running;
    final isPaused = task.focusState == FocusState.paused;
    final statusText = _buildStatusText(task);
    final showProgress = _shouldShowProgress(task);
    final progress = _progressForTask(task);
    final statusColor = task.isSuspended
        ? Colors.white38
        : Colors.white54;
    final highlightColor = widget.isCurrent ? const Color(0xFF5C8D89) : null;

    return MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: GestureDetector(
        onTap: () => widget.appState.setCurrentTask(task.id),
        onDoubleTap: _startEditing,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          margin: const EdgeInsets.symmetric(vertical: 4),
          decoration: BoxDecoration(
            color: _hovered
                ? (widget.isCurrent
                    ? const Color(0xFF1F2A28)
                    : const Color(0xFF1C1C1C))
                : Colors.transparent,
            borderRadius: BorderRadius.circular(10),
            boxShadow: _hovered
                ? [
                    BoxShadow(
                      color: Colors.black.withAlpha((0.08 * 255).round()),
                      blurRadius: 8,
                      offset: const Offset(0, 3),
                    ),
                  ]
                : [],
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(10),
            child: Stack(
              children: [
                if (showProgress && progress > 0)
                  Positioned.fill(
                    child: Align(
                      alignment: Alignment.centerLeft,
                      child: FractionallySizedBox(
                        widthFactor: progress,
                        child: Container(
                          decoration: BoxDecoration(
                            gradient: LinearGradient(
                              colors: [
                                const Color(0xFF5C8D89)
                                    .withValues(alpha: 0.16),
                                const Color(0xFF7AB6AE)
                                    .withValues(alpha: 0.24),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                Padding(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Container(
                        width: 4,
                        height: 42,
                        margin: const EdgeInsets.only(right: 8, top: 4),
                        decoration: BoxDecoration(
                          color: highlightColor ?? Colors.transparent,
                          borderRadius: BorderRadius.circular(3),
                        ),
                      ),
                      Padding(
                        padding: const EdgeInsets.only(top: 2),
                        child: Checkbox(
                          value: task.isDone,
                          materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                          visualDensity: VisualDensity.compact,
                          activeColor: const Color(0xFF5C8D89),
                          checkColor: Colors.black,
                          side: const BorderSide(color: Colors.white54),
                          onChanged: (_) => widget.appState.toggleDone(task.id),
                        ),
                      ),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              crossAxisAlignment: CrossAxisAlignment.center,
                              children: [
                                Expanded(
                                  child: _editing
                                      ? TextField(
                                          controller: _controller,
                                          focusNode: _focusNode,
                                          onSubmitted: (_) => _finishEditing(),
                                          decoration: const InputDecoration(
                                            isDense: true,
                                            border: OutlineInputBorder(
                                              borderSide: BorderSide.none,
                                            ),
                                            contentPadding: EdgeInsets.zero,
                                          ),
                                          style: TextStyle(
                                            color: textColor,
                                            fontSize: 18,
                                          ),
                                        )
                                      : Text(
                                          task.text,
                                          style: TextStyle(
                                            color: textColor,
                                            fontSize: 18,
                                            decoration: task.isDone
                                                ? TextDecoration.lineThrough
                                                : TextDecoration.none,
                                          ),
                                        ),
                                ),
                                if (task.contextText.trim().isNotEmpty)
                                  Container(
                                    width: 6,
                                    height: 6,
                                    margin: const EdgeInsets.only(left: 6),
                                    decoration: const BoxDecoration(
                                      color: Color(0xFF5C8D89),
                                      shape: BoxShape.circle,
                                    ),
                                  ),
                              ],
                            ),
                            if (statusText.isNotEmpty)
                              Padding(
                                padding: const EdgeInsets.only(top: 4),
                                child: Text(
                                  statusText,
                                  style: TextStyle(
                                    fontSize: 12,
                                    color: statusColor,
                                  ),
                                ),
                              ),
                            if (showActions)
                              Padding(
                                padding: const EdgeInsets.only(top: 8),
                                child: Wrap(
                                  spacing: 8,
                                  runSpacing: 6,
                                  children: [
                                    _buildActionButton(
                                      tooltip: '记录',
                                      icon: Icons.edit_note_outlined,
                                      onPressed: () => widget.onOpenContext(task),
                                    ),
                                    if (!isRunning)
                                      _buildActionButton(
                                        tooltip:
                                            task.isSuspended ? '恢复' : '挂起',
                                        icon: task.isSuspended
                                            ? Icons.undo
                                            : Icons.snooze_outlined,
                                        onPressed: () => widget.appState
                                            .toggleSuspend(task.id),
                                      ),
                                    if (!task.isDone && !task.isSuspended)
                                      ..._buildTimerButtons(
                                        context,
                                        isRunning,
                                        isPaused,
                                      ),
                                    if (!isRunning)
                                      _buildActionButton(
                                        tooltip: '删除',
                                        icon: Icons.delete_outline,
                                        onPressed: () =>
                                            _requestDelete(context, task),
                                      ),
                                  ],
                                ),
                              ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  String _buildStatusText(Task task) {
    if (task.isDone) {
      return '';
    }
    if (task.isSuspended) {
      return '挂起';
    }
    if (task.focusState == FocusState.running) {
      return _formatDuration(task.focusRemainingSec);
    }
    if (task.focusState == FocusState.paused) {
      if (task.focusRemainingSec > 0 &&
          task.focusRemainingSec < task.focusDurationSec) {
        return '暂停 ${_formatDuration(task.focusRemainingSec)}';
      }
    }
    if (task.focusRemainingSec == 0 && task.focusDurationSec > 0) {
      return '计时结束 00:00';
    }
    return '';
  }

  bool _shouldShowProgress(Task task) {
    return !task.isDone && task.isActive;
  }

  double _progressForTask(Task task) {
    if (task.focusDurationSec <= 0) {
      return 0.0;
    }
    final remaining = task.focusRemainingSec.clamp(0, task.focusDurationSec);
    final elapsed = task.focusDurationSec - remaining;
    return (elapsed / task.focusDurationSec).clamp(0, 1).toDouble();
  }

  List<Widget> _buildTimerButtons(
    BuildContext context,
    bool isRunning,
    bool isPaused,
  ) {
    final buttons = <Widget>[];
    if (isRunning) {
      buttons.add(
        _buildActionButton(
          tooltip: '暂停',
          icon: Icons.pause_circle_outline,
          onPressed: () => widget.appState.pauseTask(widget.task.id),
        ),
      );
    } else if (isPaused) {
      buttons.add(
        _buildActionButton(
          tooltip: '开始',
          icon: Icons.play_circle_outline,
          onPressed: () => widget.appState.startTask(widget.task.id),
        ),
      );
      buttons.add(
        _buildActionButton(
          tooltip: '重置',
          icon: Icons.restart_alt,
          onPressed: () => widget.appState.resetTask(widget.task.id),
        ),
      );
    } else {
      buttons.add(
        _buildActionButton(
          tooltip: '开始',
          icon: Icons.play_circle_outline,
          onPressed: () => widget.appState.startTask(widget.task.id),
        ),
      );
    }
    return buttons;
  }

  Widget _buildActionButton({
    required String tooltip,
    required IconData icon,
    required VoidCallback onPressed,
  }) {
    return IconButton(
      tooltip: tooltip,
      icon: Icon(icon, size: 22, color: Colors.white70),
      onPressed: onPressed,
      padding: const EdgeInsets.all(6),
      constraints: const BoxConstraints.tightFor(width: 36, height: 36),
      visualDensity: VisualDensity.compact,
    );
  }

  String _formatDuration(int seconds) {
    final minutes = seconds ~/ 60;
    final secs = seconds % 60;
    return '${minutes.toString().padLeft(2, '0')}:${secs.toString().padLeft(2, '0')}';
  }

  void _requestDelete(BuildContext context, Task task) {
    final removed = widget.appState.removeTask(task.id);
    if (removed == null) {
      return;
    }
    final messenger = ScaffoldMessenger.of(context);
    Timer? timer;
    timer = Timer(const Duration(seconds: 5), () {
      timer?.cancel();
    });
    messenger.clearSnackBars();
    messenger.showSnackBar(
      SnackBar(
        duration: const Duration(seconds: 5),
        content: const Text('任务已删除'),
        action: SnackBarAction(
          label: '撤销',
          onPressed: () {
            timer?.cancel();
            widget.appState.restoreTask(removed);
          },
        ),
      ),
    );
  }
}
