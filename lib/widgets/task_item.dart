import 'dart:async';

import 'package:flutter/material.dart';
import 'package:window_manager/window_manager.dart';

import '../app_state.dart';
import '../models.dart';

class TaskItem extends StatefulWidget {
  const TaskItem({
    super.key,
    required this.task,
    required this.appState,
    required this.isCurrent,
    required this.collapseSignal,
    required this.onOpenContext,
  });

  final Task task;
  final AppState appState;
  final bool isCurrent;
  final int collapseSignal;
  final Future<void> Function(Task task, Subtask? subtask) onOpenContext;

  @override
  State<TaskItem> createState() => _TaskItemState();
}

class _TaskItemState extends State<TaskItem> {
  late final TextEditingController _controller;
  late final TextEditingController _subtaskController;
  late final TextEditingController _subtaskEditController;
  final FocusNode _focusNode = FocusNode();
  final FocusNode _subtaskFocusNode = FocusNode();
  final FocusNode _subtaskEditFocusNode = FocusNode();
  bool _hovered = false;
  bool _editing = false;
  bool _expanded = false;
  bool _showAllDoneSubtasks = false;
  bool _showSubtaskInput = false;
  String? _hoveringSubtaskId;
  String? _editingSubtaskId;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.task.text);
    _subtaskController = TextEditingController();
    _subtaskEditController = TextEditingController();
    _focusNode.addListener(() {
      if (!_focusNode.hasFocus && _editing) {
        _finishEditing();
      }
    });
    _subtaskEditFocusNode.addListener(() {
      if (!_subtaskEditFocusNode.hasFocus && _editingSubtaskId != null) {
        _finishEditingSubtask();
      }
    });
  }

  @override
  void didUpdateWidget(covariant TaskItem oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.task.text != widget.task.text && !_editing) {
      _controller.text = widget.task.text;
    }
    if (widget.task.subtasks.isEmpty && _expanded) {
      _expanded = false;
      _showAllDoneSubtasks = false;
      _showSubtaskInput = false;
      _hoveringSubtaskId = null;
      _editingSubtaskId = null;
      _subtaskController.clear();
    }
    if (oldWidget.collapseSignal != widget.collapseSignal && _expanded) {
      setState(() {
        _expanded = false;
        _showAllDoneSubtasks = false;
        _showSubtaskInput = false;
        _hoveringSubtaskId = null;
        _editingSubtaskId = null;
      });
      _subtaskController.clear();
      _subtaskFocusNode.unfocus();
      _subtaskEditFocusNode.unfocus();
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

  void _toggleExpanded() {
    setState(() {
      _expanded = !_expanded;
      if (!_expanded) {
        _showAllDoneSubtasks = false;
        _showSubtaskInput = false;
      }
    });
    if (!_expanded) {
      _subtaskController.clear();
      _subtaskFocusNode.unfocus();
      _subtaskEditFocusNode.unfocus();
      _editingSubtaskId = null;
      _hoveringSubtaskId = null;
    }
  }

  void _openSubtaskInput() {
    setState(() {
      _showSubtaskInput = true;
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _subtaskFocusNode.requestFocus();
    });
  }

  void _cancelSubtaskInput() {
    setState(() {
      _showSubtaskInput = false;
    });
    _subtaskController.clear();
    _subtaskFocusNode.unfocus();
  }

  void _submitSubtask() {
    final added = widget.appState.addSubtask(
      widget.task.id,
      _subtaskController.text,
    );
    if (!added) {
      return;
    }
    _subtaskController.clear();
    setState(() {
      _expanded = true;
      _showSubtaskInput = false;
    });
    _subtaskFocusNode.unfocus();
    if (widget.task.subtasks.length > 20) {
      _showMessage('子任务已超过 20 条，建议迁移复杂跟踪到外部文档');
    }
  }

  void _startEditingSubtask(Subtask subtask) {
    setState(() {
      _editingSubtaskId = subtask.id;
    });
    _subtaskEditController.text = subtask.text;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) {
        return;
      }
      _subtaskEditFocusNode.requestFocus();
      _subtaskEditController.selection = TextSelection(
        baseOffset: 0,
        extentOffset: _subtaskEditController.text.length,
      );
    });
  }

  void _finishEditingSubtask() {
    final subtaskId = _editingSubtaskId;
    if (subtaskId == null) {
      return;
    }
    widget.appState.updateSubtaskText(
      widget.task.id,
      subtaskId,
      _subtaskEditController.text,
    );
    if (!mounted) {
      return;
    }
    setState(() {
      _editingSubtaskId = null;
    });
  }

  Future<void> _handleToggleDone(Task task) async {
    await widget.appState.toggleDone(task.id);
  }

  void _showMessage(String message) {
    final messenger = ScaffoldMessenger.of(context);
    messenger.clearSnackBars();
    messenger.showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  void dispose() {
    _controller.dispose();
    _subtaskController.dispose();
    _subtaskEditController.dispose();
    _focusNode.dispose();
    _subtaskFocusNode.dispose();
    _subtaskEditFocusNode.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final task = widget.task;
    final textColor = task.isDone
        ? Colors.white54
        : (task.isSuspended ? Colors.white38 : Colors.white);
    final showActions = _hovered;
    final isRunning = task.focusState == FocusState.running;
    final isPaused = task.focusState == FocusState.paused;
    final statusText = _buildStatusText(task);
    final countdownText = _buildCountdownText(task);
    final showProgress = _shouldShowProgress(task);
    final progress = _progressForTask(task);
    final statusColor = task.isSuspended ? Colors.white38 : Colors.white54;
    final highlightColor = widget.isCurrent ? const Color(0xFF5C8D89) : null;
    final subtaskTotal = task.subtasks.length;
    final subtaskDone = task.subtasks.where((subtask) => subtask.isDone).length;
    final activeSubtaskText = widget.appState.activeSubtaskText(task);
    final hasActiveSubtask =
        activeSubtaskText != null && activeSubtaskText.trim().isNotEmpty;
    final hasTaskContext = task.contextText.trim().isNotEmpty;

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
                                const Color(0xFF5C8D89).withValues(alpha: 0.16),
                                const Color(0xFF7AB6AE).withValues(alpha: 0.24),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 8,
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
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
                              materialTapTargetSize:
                                  MaterialTapTargetSize.shrinkWrap,
                              visualDensity: VisualDensity.compact,
                              activeColor: const Color(0xFF5C8D89),
                              checkColor: Colors.black,
                              side: const BorderSide(color: Colors.white54),
                              onChanged: (_) {
                                _handleToggleDone(task);
                              },
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
                                              onSubmitted: (_) =>
                                                  _finishEditing(),
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
                                              hasActiveSubtask
                                                  ? activeSubtaskText
                                                  : task.text,
                                              maxLines: 1,
                                              overflow: TextOverflow.ellipsis,
                                              style: TextStyle(
                                                color: textColor,
                                                fontSize: 18,
                                                decoration: task.isDone
                                                    ? TextDecoration.lineThrough
                                                    : TextDecoration.none,
                                              ),
                                            ),
                                    ),
                                    if (subtaskTotal > 0)
                                      Padding(
                                        padding: const EdgeInsets.only(left: 6),
                                        child: Text(
                                          '（$subtaskDone/$subtaskTotal）',
                                          style: const TextStyle(
                                            fontSize: 14,
                                            color: Colors.white70,
                                          ),
                                        ),
                                      ),
                                    if (countdownText.isNotEmpty)
                                      Padding(
                                        padding: const EdgeInsets.only(left: 8),
                                        child: Text(
                                          countdownText,
                                          style: const TextStyle(
                                            fontSize: 14,
                                            color: Colors.white70,
                                          ),
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
                                if (hasActiveSubtask)
                                  Padding(
                                    padding: const EdgeInsets.only(top: 4),
                                    child: Text(
                                      task.text,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: const TextStyle(
                                        fontSize: 12,
                                        color: Colors.white70,
                                      ),
                                    ),
                                  ),
                                if (showActions)
                                  Padding(
                                    padding: const EdgeInsets.only(top: 8),
                                    child: Wrap(
                                      spacing: 6,
                                      runSpacing: 6,
                                      children: [
                                        _buildActionButton(
                                          tooltip: '记录',
                                          icon: hasTaskContext
                                              ? Icons.note_alt_outlined
                                              : Icons.edit_note_outlined,
                                          onPressed: () => unawaited(
                                            widget.onOpenContext(task, null),
                                          ),
                                        ),
                                        _buildActionButton(
                                          tooltip: _expanded ? '收起子任务' : '子任务',
                                          icon: _expanded
                                              ? Icons.expand_less
                                              : Icons.format_list_bulleted,
                                          onPressed: _toggleExpanded,
                                        ),
                                        if (!isRunning)
                                          _buildActionButton(
                                            tooltip: task.isSuspended
                                                ? '恢复'
                                                : '挂起',
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
                                                _requestDelete(task),
                                          ),
                                      ],
                                    ),
                                  ),
                              ],
                            ),
                          ),
                        ],
                      ),
                      if (_expanded) ...[
                        const SizedBox(height: 8),
                        _buildSubtaskPanel(task),
                      ],
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

  Widget _buildSubtaskPanel(Task task) {
    final todoSubtasks =
        task.subtasks.where((subtask) => !subtask.isDone).toList()
          ..sort((a, b) => a.order.compareTo(b.order));
    final doneSubtasks =
        task.subtasks.where((subtask) => subtask.isDone).toList()..sort((a, b) {
          final aTime = a.doneAt;
          final bTime = b.doneAt;
          if (aTime != null && bTime != null) {
            return bTime.compareTo(aTime);
          }
          if (aTime != null) {
            return -1;
          }
          if (bTime != null) {
            return 1;
          }
          return b.order.compareTo(a.order);
        });

    final shownDone = _showAllDoneSubtasks
        ? doneSubtasks
        : doneSubtasks.take(2).toList();
    final hiddenDoneCount = doneSubtasks.length - shownDone.length;
    final showDoneHeader =
        doneSubtasks.isNotEmpty &&
        (hiddenDoneCount > 0 || _showAllDoneSubtasks);
    final doneHeaderCount = _showAllDoneSubtasks
        ? shownDone.length
        : hiddenDoneCount;

    return Container(
      margin: const EdgeInsets.only(left: 34),
      padding: const EdgeInsets.fromLTRB(10, 10, 10, 8),
      decoration: BoxDecoration(
        color: const Color(0xFF171717),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: Colors.white12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (task.subtasks.length > 20)
            const Padding(
              padding: EdgeInsets.only(bottom: 8),
              child: Text(
                '子任务较多，建议将复杂跟踪迁移到外部文档。',
                style: TextStyle(fontSize: 12, color: Colors.amberAccent),
              ),
            ),
          if (todoSubtasks.isEmpty && shownDone.isEmpty)
            const Padding(
              padding: EdgeInsets.only(bottom: 8),
              child: Text(
                '暂无子任务',
                style: TextStyle(fontSize: 12, color: Colors.white54),
              ),
            ),
          if (showDoneHeader)
            _buildDoneHeader(doneCount: doneHeaderCount, canToggle: true),
          ...shownDone.map((subtask) => _buildSubtaskRow(task, subtask)),
          if (todoSubtasks.isNotEmpty)
            _buildTodoSubtaskList(task, todoSubtasks),
          const SizedBox(height: 4),
          if (_showSubtaskInput)
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _subtaskController,
                    focusNode: _subtaskFocusNode,
                    textInputAction: TextInputAction.done,
                    onSubmitted: (_) => _submitSubtask(),
                    style: const TextStyle(color: Colors.white, fontSize: 14),
                    decoration: InputDecoration(
                      hintText: '输入子任务',
                      hintStyle: const TextStyle(color: Colors.white38),
                      filled: true,
                      fillColor: const Color(0xFF202020),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(8),
                        borderSide: BorderSide.none,
                      ),
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 8,
                      ),
                    ),
                  ),
                ),
                IconButton(
                  tooltip: '保存子任务',
                  icon: const Icon(Icons.check, size: 18),
                  onPressed: _submitSubtask,
                  visualDensity: VisualDensity.compact,
                  constraints: const BoxConstraints.tightFor(
                    width: 30,
                    height: 30,
                  ),
                ),
                IconButton(
                  tooltip: '取消',
                  icon: const Icon(Icons.close, size: 18),
                  onPressed: _cancelSubtaskInput,
                  visualDensity: VisualDensity.compact,
                  constraints: const BoxConstraints.tightFor(
                    width: 30,
                    height: 30,
                  ),
                ),
              ],
            )
          else
            TextButton.icon(
              onPressed: _openSubtaskInput,
              style: TextButton.styleFrom(
                padding: const EdgeInsets.symmetric(horizontal: 4),
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                visualDensity: VisualDensity.compact,
                foregroundColor: Colors.white70,
              ),
              icon: const Icon(Icons.add_circle_outline, size: 16),
              label: const Text('添加子任务'),
            ),
        ],
      ),
    );
  }

  Widget _buildDoneHeader({required int doneCount, required bool canToggle}) {
    final icon = _showAllDoneSubtasks
        ? Icons.keyboard_arrow_down
        : Icons.chevron_right;
    final content = Padding(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
      child: Row(
        children: [
          Icon(icon, size: 18, color: Colors.white60),
          const SizedBox(width: 6),
          Text(
            '已完成（$doneCount）',
            style: const TextStyle(fontSize: 12, color: Colors.white60),
          ),
        ],
      ),
    );
    if (!canToggle) {
      return content;
    }
    return InkWell(
      borderRadius: BorderRadius.circular(6),
      onTap: () {
        setState(() {
          _showAllDoneSubtasks = !_showAllDoneSubtasks;
        });
      },
      child: content,
    );
  }

  Widget _buildTodoSubtaskList(Task task, List<Subtask> todoSubtasks) {
    return ReorderableListView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      buildDefaultDragHandles: false,
      itemCount: todoSubtasks.length,
      onReorder: (oldIndex, newIndex) {
        if (newIndex > oldIndex) {
          newIndex -= 1;
        }
        if (oldIndex == newIndex) {
          return;
        }
        final reordered = todoSubtasks.toList();
        final moved = reordered.removeAt(oldIndex);
        reordered.insert(newIndex, moved);
        widget.appState.reorderTodoSubtasks(
          task.id,
          reordered.map((subtask) => subtask.id).toList(),
        );
      },
      itemBuilder: (context, index) {
        final subtask = todoSubtasks[index];
        return Container(
          key: ValueKey('todo-${subtask.id}'),
          child: ReorderableDelayedDragStartListener(
            index: index,
            child: _buildSubtaskRow(task, subtask),
          ),
        );
      },
    );
  }

  Widget _buildSubtaskRow(Task task, Subtask subtask) {
    final isActive = task.activeSubtaskId == subtask.id;
    final textColor = subtask.isDone ? Colors.white54 : Colors.white;
    final showActionButtons =
        _hoveringSubtaskId == subtask.id || _editingSubtaskId == subtask.id;

    return MouseRegion(
      onEnter: (_) {
        if (_hoveringSubtaskId == subtask.id) {
          return;
        }
        setState(() {
          _hoveringSubtaskId = subtask.id;
        });
      },
      onExit: (_) {
        if (_hoveringSubtaskId != subtask.id) {
          return;
        }
        setState(() {
          _hoveringSubtaskId = null;
        });
      },
      child: Container(
        margin: const EdgeInsets.only(bottom: 6),
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
        decoration: BoxDecoration(
          color: isActive
              ? const Color(0xFF5C8D89).withValues(alpha: 0.16)
              : Colors.transparent,
          borderRadius: BorderRadius.circular(8),
        ),
        child: Row(
          children: [
            MouseRegion(
              cursor: SystemMouseCursors.click,
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: () {
                  widget.appState.toggleSubtaskDone(task.id, subtask.id);
                },
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 2),
                  child: Icon(
                    subtask.isDone
                        ? Icons.check_circle
                        : Icons.radio_button_unchecked,
                    size: 18,
                    color: subtask.isDone
                        ? const Color(0xFF7AB6AE)
                        : Colors.white54,
                  ),
                ),
              ),
            ),
            const SizedBox(width: 6),
            Expanded(
              child: _editingSubtaskId == subtask.id
                  ? TextField(
                      controller: _subtaskEditController,
                      focusNode: _subtaskEditFocusNode,
                      onSubmitted: (_) => _finishEditingSubtask(),
                      style: const TextStyle(color: Colors.white, fontSize: 14),
                      decoration: const InputDecoration(
                        isDense: true,
                        border: OutlineInputBorder(borderSide: BorderSide.none),
                        contentPadding: EdgeInsets.symmetric(vertical: 2),
                      ),
                    )
                  : InkWell(
                      borderRadius: BorderRadius.circular(6),
                      mouseCursor: SystemMouseCursors.basic,
                      onTap: () {
                        widget.appState.toggleActiveSubtask(
                          task.id,
                          subtask.id,
                        );
                      },
                      onDoubleTap: () {
                        _startEditingSubtask(subtask);
                      },
                      child: Padding(
                        padding: const EdgeInsets.symmetric(vertical: 2),
                        child: Text(
                          subtask.text,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 14,
                            color: textColor,
                            decoration: subtask.isDone
                                ? TextDecoration.lineThrough
                                : TextDecoration.none,
                          ),
                        ),
                      ),
                    ),
            ),
            if (showActionButtons)
              Row(
                children: [
                  MouseRegion(
                    cursor: SystemMouseCursors.click,
                    child: IconButton(
                      tooltip: '记录子任务',
                      icon: Icon(
                        subtask.contextText.trim().isNotEmpty
                            ? Icons.note_alt_outlined
                            : Icons.edit_note_outlined,
                        size: 16,
                        color: Colors.white54,
                      ),
                      onPressed: () =>
                          unawaited(widget.onOpenContext(task, subtask)),
                      visualDensity: VisualDensity.compact,
                      constraints: const BoxConstraints.tightFor(
                        width: 28,
                        height: 28,
                      ),
                    ),
                  ),
                  MouseRegion(
                    cursor: SystemMouseCursors.click,
                    child: IconButton(
                      tooltip: subtask.isDone ? '标记未完成' : '完成子任务',
                      icon: Icon(
                        subtask.isDone
                            ? Icons.remove_done_outlined
                            : Icons.done,
                        size: 16,
                        color: subtask.isDone
                            ? Colors.white54
                            : const Color(0xFF7AB6AE),
                      ),
                      onPressed: () {
                        widget.appState.toggleSubtaskDone(task.id, subtask.id);
                      },
                      visualDensity: VisualDensity.compact,
                      constraints: const BoxConstraints.tightFor(
                        width: 28,
                        height: 28,
                      ),
                    ),
                  ),
                  MouseRegion(
                    cursor: SystemMouseCursors.click,
                    child: IconButton(
                      tooltip: '删除子任务',
                      icon: const Icon(
                        Icons.close,
                        size: 16,
                        color: Colors.white54,
                      ),
                      onPressed: () => _requestSubtaskDelete(task, subtask),
                      visualDensity: VisualDensity.compact,
                      constraints: const BoxConstraints.tightFor(
                        width: 28,
                        height: 28,
                      ),
                    ),
                  ),
                ],
              ),
          ],
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
    return '';
  }

  String _buildCountdownText(Task task) {
    if (task.isDone || task.isSuspended) {
      return '';
    }
    if (task.focusDurationSec <= 0) {
      return '';
    }
    if (task.focusRemainingSec <= 0) {
      return '00:00';
    }
    if (task.focusState == FocusState.running ||
        task.focusState == FocusState.paused) {
      return _formatDuration(task.focusRemainingSec);
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

  Future<void> _requestSubtaskDelete(Task task, Subtask subtask) async {
    final confirmed = await _confirmDelete(
      title: '删除子任务？',
      message: '将删除子任务“${subtask.text}”。',
      confirmLabel: '删除子任务',
    );
    if (confirmed != true) {
      return;
    }
    widget.appState.removeSubtask(task.id, subtask.id);
  }

  Future<void> _requestDelete(Task task) async {
    final confirmed = await _confirmDelete(
      title: '删除任务？',
      message: '将删除任务“${task.text}”及其子任务记录。',
      confirmLabel: '删除任务',
    );
    if (confirmed != true || !mounted) {
      return;
    }
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

  Future<bool?> _confirmDelete({
    required String title,
    required String message,
    required String confirmLabel,
  }) async {
    final shouldRestoreOpaque = !widget.appState.forceOpaque;
    if (shouldRestoreOpaque) {
      widget.appState.setForceOpaque(true);
    }
    await windowManager.setOpacity(1.0);
    try {
      if (!mounted) {
        return false;
      }
      return await showDialog<bool>(
        context: context,
        barrierColor: Colors.black45,
        builder: (dialogContext) {
          return AlertDialog(
            backgroundColor: const Color(0xFF202020),
            title: Text(title, style: const TextStyle(color: Colors.white)),
            content: Text(
              message,
              style: const TextStyle(color: Colors.white70),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(dialogContext).pop(false),
                child: const Text('取消'),
              ),
              FilledButton(
                onPressed: () => Navigator.of(dialogContext).pop(true),
                style: FilledButton.styleFrom(
                  backgroundColor: const Color(0xFFB84C3B),
                ),
                child: Text(confirmLabel),
              ),
            ],
          );
        },
      );
    } finally {
      if (shouldRestoreOpaque) {
        widget.appState.setForceOpaque(false);
      }
    }
  }
}
