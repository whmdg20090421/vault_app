import 'package:flutter/material.dart';
import '../services/encryption_task_manager.dart';
import '../models/encryption_node.dart';
import '../../utils/format_utils.dart';

void showEncryptionProgressPanel(BuildContext context) {
  final theme = Theme.of(context);
  showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    barrierColor: theme.colorScheme.scrim.withValues(alpha: 0.6),
    builder: (context) => const EncryptionProgressPanel(),
  );
}

class EncryptionProgressPanel extends StatefulWidget {
  const EncryptionProgressPanel({super.key});

  @override
  State<EncryptionProgressPanel> createState() => _EncryptionProgressPanelState();
}

class _EncryptionProgressPanelState extends State<EncryptionProgressPanel> with SingleTickerProviderStateMixin {
  late final TabController _tabController;
  final List<FolderNode> _folderStack = [];
  bool _isStackHistory = false;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  void _pushFolder(FolderNode folder, bool isHistory) {
    setState(() {
      if (_folderStack.isEmpty) {
        _isStackHistory = isHistory;
      }
      _folderStack.add(folder);
    });
  }

  void _popFolder() {
    setState(() {
      if (_folderStack.isNotEmpty) {
        _folderStack.removeLast();
      }
    });
  }

  void _showErrorDialog(BuildContext context, String errorMessage) {
    final theme = Theme.of(context);
    showGeneralDialog(
      context: context,
      barrierDismissible: true,
      barrierLabel: 'Error',
      barrierColor: Colors.black.withOpacity(0.6),
      pageBuilder: (context, animation, secondaryAnimation) {
        return ScaleTransition(
          scale: CurvedAnimation(parent: animation, curve: Curves.easeOutBack),
          child: AlertDialog(
            backgroundColor: theme.colorScheme.surface,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
            title: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.hourglass_disabled, size: 32),
                const SizedBox(height: 8),
                const Text('解析失败', style: TextStyle(fontWeight: FontWeight.bold)),
              ],
            ),
            content: Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.red.shade900,
                borderRadius: BorderRadius.circular(8),
              ),
              child: SingleChildScrollView(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Text('未知错误', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                    const SizedBox(height: 8),
                    Text(
                      errorMessage,
                      style: const TextStyle(color: Colors.white70, fontSize: 12),
                    ),
                  ],
                ),
              ),
            ),
            actions: [
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: () => Navigator.of(context).pop(),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: theme.colorScheme.primary.withOpacity(0.2),
                    foregroundColor: theme.colorScheme.onSurface,
                  ),
                  child: const Text('取消'),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: EncryptionTaskManager(),
      builder: (context, _) {
        final manager = EncryptionTaskManager();
        final tasks = manager.tasks;
        final historyTasks = manager.historyTasks;
        final theme = Theme.of(context);
        final isCyberpunk = theme.brightness == Brightness.dark && theme.colorScheme.primary.value == 0xFF00E5FF;
        final surfaceColor = theme.dialogTheme.backgroundColor ?? theme.cardTheme.color ?? theme.colorScheme.surface;

        return DraggableScrollableSheet(
          expand: false,
          initialChildSize: 0.6,
          minChildSize: 0.4,
          maxChildSize: 0.9,
          builder: (context, scrollController) {
            final isRoot = _folderStack.isEmpty;
            final title = isRoot ? '加密任务进度' : _folderStack.last.name;

            return Container(
              decoration: BoxDecoration(
                color: surfaceColor,
                borderRadius: isCyberpunk ? BorderRadius.zero : const BorderRadius.vertical(top: Radius.circular(20)),
                border: isCyberpunk ? Border(top: BorderSide(color: theme.colorScheme.primary, width: 2)) : null,
              ),
              child: Column(
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
                    child: Row(
                      children: [
                        if (!isRoot)
                          IconButton(
                            icon: const Icon(Icons.arrow_back),
                            onPressed: _popFolder,
                          ),
                        Expanded(
                          child: Text(
                            title,
                            style: theme.textTheme.titleLarge?.copyWith(
                              fontWeight: FontWeight.bold,
                              color: isCyberpunk ? theme.colorScheme.secondary : null,
                            ),
                          ),
                        ),
                        IconButton(
                          icon: const Icon(Icons.close),
                          onPressed: () => Navigator.of(context).pop(),
                        ),
                      ],
                    ),
                  ),
                  if (isRoot) ...[
                    TabBar(
                      controller: _tabController,
                      labelColor: isCyberpunk ? theme.colorScheme.secondary : theme.colorScheme.primary,
                      unselectedLabelColor: theme.colorScheme.onSurface.withOpacity(0.5),
                      indicatorColor: isCyberpunk ? theme.colorScheme.secondary : theme.colorScheme.primary,
                      tabs: const [
                        Tab(text: '进行中'),
                        Tab(text: '历史记录'),
                      ],
                    ),
                    if (isCyberpunk) Divider(height: 1, color: theme.colorScheme.primary.withOpacity(0.5)),
                    Expanded(
                      child: TabBarView(
                        controller: _tabController,
                        children: [
                          _buildTaskList(tasks, scrollController, isCyberpunk, theme, false),
                          _buildTaskList(historyTasks, scrollController, isCyberpunk, theme, true),
                        ],
                      ),
                    ),
                  ] else ...[
                    if (isCyberpunk) Divider(height: 1, color: theme.colorScheme.primary.withOpacity(0.5)),
                    Expanded(
                      child: _buildTaskList(_folderStack.last.children, scrollController, isCyberpunk, theme, _isStackHistory),
                    ),
                  ],
                ],
              ),
            );
          },
        );
      },
    );
  }

  Widget _buildTaskList(List<EncryptionNode> tasks, ScrollController scrollController, bool isCyberpunk, ThemeData theme, bool isHistory) {
    if (tasks.isEmpty) {
      return Center(
        child: Text(
          '当前没有任务',
          style: TextStyle(color: theme.colorScheme.onSurface.withOpacity(0.5)),
        ),
      );
    }
    return ListView.builder(
      controller: scrollController,
      padding: const EdgeInsets.all(16),
      itemCount: tasks.length,
      itemBuilder: (context, index) {
        final task = tasks[index];
        return _EncryptionTaskCard(
          task: task,
          isCyberpunk: isCyberpunk,
          theme: theme,
          isHistory: isHistory,
          onTap: task is FolderNode ? () => _pushFolder(task, isHistory) : null,
        );
      },
    );
  }
}

class _EncryptionTaskCard extends StatelessWidget {
  final EncryptionNode task;
  final bool isCyberpunk;
  final ThemeData theme;
  final bool isHistory;
  final VoidCallback? onTap;

  const _EncryptionTaskCard({
    required this.task,
    required this.isCyberpunk,
    required this.theme,
    this.isHistory = false,
    this.onTap,
  });

  void _showActionMenu(BuildContext context) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (context) {
        final surfaceColor = theme.dialogTheme.backgroundColor ?? theme.cardTheme.color ?? theme.colorScheme.surface;
        return Container(
          margin: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: surfaceColor,
            borderRadius: BorderRadius.circular(16),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (isHistory)
                ListTile(
                  leading: const Icon(Icons.delete_outline, color: Colors.red),
                  title: const Text('删除历史记录', style: TextStyle(color: Colors.red)),
                  subtitle: const Text('仅清除列表数据，不删除文件'),
                  onTap: () {
                    Navigator.pop(context);
                    EncryptionTaskManager().removeHistoryTask(task);
                  },
                )
              else ...[
                ListTile(
                  leading: const Icon(Icons.delete_outline, color: Colors.red),
                  title: const Text('移除任务', style: TextStyle(color: Colors.red)),
                  onTap: () {
                    Navigator.pop(context);
                    EncryptionTaskManager().removeTask(task);
                  },
                ),
                const Divider(height: 1),
                ListTile(
                  leading: const Icon(Icons.build_circle_outlined),
                  title: const Text('标记已修复并重试'),
                  onTap: () {
                    Navigator.pop(context);
                    EncryptionTaskManager().markTaskAsFixed(task);
                  },
                ),
              ],
            ],
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    int completedSize = 0;
    int encryptingCompletedSize = 0;
    int encryptingRemainingSize = 0;
    int pendingSize = 0;
    int pausedErrorSize = 0;
    int totalSize = 0;

    void traverse(EncryptionNode node) {
      if (node is FolderNode) {
        for (var child in node.children) {
          traverse(child);
        }
      } else if (node is FileNode) {
        totalSize += node.rawSize;
        switch (node.status) {
          case NodeStatus.completed:
            completedSize += node.rawSize;
            break;
          case NodeStatus.encrypting:
            encryptingCompletedSize += node.encryptingCompletedBytes;
            encryptingRemainingSize += (node.rawSize - node.encryptingCompletedBytes);
            break;
          case NodeStatus.pending_waiting:
            pendingSize += node.rawSize;
            break;
          case NodeStatus.pending_paused:
          case NodeStatus.error:
            pausedErrorSize += node.rawSize;
            break;
        }
      }
    }

    traverse(task);

    final double progress = totalSize > 0 ? (completedSize + encryptingCompletedSize) / totalSize : 0;
    final bool isPaused = task.isPaused;
    final bool isError = task.status == NodeStatus.error;
    final bool isCompleted = task.status == NodeStatus.completed;

    return GestureDetector(
      onLongPress: () => _showActionMenu(context),
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 300),
        curve: Curves.elasticOut,
        margin: const EdgeInsets.only(bottom: 12),
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: isCyberpunk ? Colors.transparent : theme.colorScheme.surface,
          borderRadius: isCyberpunk ? BorderRadius.zero : BorderRadius.circular(16),
          border: isCyberpunk
              ? Border.all(color: theme.colorScheme.primary.withOpacity(0.3))
              : Border.all(color: Colors.transparent),
          boxShadow: isCyberpunk
              ? null
              : [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.05),
                    blurRadius: 10,
                    offset: const Offset(0, 4),
                  )
                ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Line 1: Pause button + Name
            Row(
              children: [
                IconButton(
                  icon: Icon(
                    isCompleted
                        ? Icons.check_circle_outline
                        : (isPaused || isError)
                            ? Icons.play_arrow_rounded
                            : Icons.pause_rounded,
                    color: isCompleted
                        ? Colors.green
                        : isError
                            ? Colors.red
                            : theme.colorScheme.primary,
                  ),
                  onPressed: isCompleted
                      ? null
                      : () {
                          if (isError) {
                            EncryptionTaskManager().markTaskAsFixed(task); // Retry on error
                          } else if (isPaused) {
                            EncryptionTaskManager().resumeTask(task);
                          } else {
                            EncryptionTaskManager().pauseTask(task);
                          }
                        },
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        task.name,
                        style: const TextStyle(fontWeight: FontWeight.bold),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      if (isError && task.errorMessage != null)
                        GestureDetector(
                          onTap: () {
                            showDialog(
                              context: context,
                              builder: (context) => AlertDialog(
                                title: const Text('解析失败', style: TextStyle(color: Colors.red)),
                                content: SingleChildScrollView(
                                  child: Text(task.errorMessage!, style: const TextStyle(fontSize: 12)),
                                ),
                                actions: [
                                  TextButton(
                                    onPressed: () => Navigator.pop(context),
                                    child: const Text('关闭'),
                                  ),
                                ],
                              ),
                            );
                          },
                          child: Text(
                            task.errorMessage!,
                            style: const TextStyle(color: Colors.red, fontSize: 12),
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                    ],
                  ),
                ),
                if (task is FolderNode)
                  Icon(
                    Icons.chevron_right,
                    color: theme.colorScheme.onSurface.withOpacity(0.5),
                  ),
              ],
            ),
            const SizedBox(height: 12),
            // Line 2: Very thin 4-color progress bar (1% rule)
            SizedBox(
              height: 4,
              width: double.infinity,
              child: CustomPaint(
                painter: _EncryptionProgressLinePainter(
                              completedSize: completedSize,
                              encryptingCompletedSize: encryptingCompletedSize,
                              encryptingRemainingSize: encryptingRemainingSize,
                              pendingSize: pendingSize,
                              pausedErrorSize: pausedErrorSize,
                              totalSize: totalSize,
                            ),
              ),
            ),
            const SizedBox(height: 8),
            // Line 3: Percentage + Statistics
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  '${(progress * 100).toStringAsFixed(1)}%',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                    color: theme.colorScheme.onSurface.withOpacity(0.7),
                  ),
                ),
                Text(
                  '${FormatUtils.formatBytes(completedSize + encryptingCompletedSize)} / ${FormatUtils.formatBytes(totalSize)}',
                  style: TextStyle(
                    fontSize: 12,
                    color: theme.colorScheme.onSurface.withOpacity(0.5),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _EncryptionProgressLinePainter extends CustomPainter {
  final int completedSize;
  final int encryptingCompletedSize;
  final int encryptingRemainingSize;
  final int pendingSize;
  final int pausedErrorSize;
  final int totalSize;

  _EncryptionProgressLinePainter({
    required this.completedSize,
    required this.encryptingCompletedSize,
    required this.encryptingRemainingSize,
    required this.pendingSize,
    required this.pausedErrorSize,
    required this.totalSize,
  });

  @override
  void paint(Canvas canvas, Size size) {
    if (totalSize == 0) {
      final paint = Paint()..color = Colors.grey.withOpacity(0.3);
      canvas.drawRRect(
        RRect.fromRectAndRadius(Offset.zero & size, const Radius.circular(2)),
        paint,
      );
      return;
    }

    double w = size.width;
    double h = size.height;

    // 1% rule: if a segment has data, it must be at least 1% of the width
    double minWidth = w * 0.01;

    double completedW = completedSize > 0 ? (completedSize / totalSize * w) : 0;
    double encryptingCompletedW = encryptingCompletedSize > 0 ? (encryptingCompletedSize / totalSize * w) : 0;
    double encryptingRemainingW = encryptingRemainingSize > 0 ? (encryptingRemainingSize / totalSize * w) : 0;
    double pendingW = pendingSize > 0 ? (pendingSize / totalSize * w) : 0;
    double pausedErrorW = pausedErrorSize > 0 ? (pausedErrorSize / totalSize * w) : 0;

    if (completedSize > 0 && completedW < minWidth) completedW = minWidth;
    if (encryptingCompletedSize > 0 && encryptingCompletedW < minWidth) encryptingCompletedW = minWidth;
    if (encryptingRemainingSize > 0 && encryptingRemainingW < minWidth) encryptingRemainingW = minWidth;
    if (pendingSize > 0 && pendingW < minWidth) pendingW = minWidth;
    if (pausedErrorSize > 0 && pausedErrorW < minWidth) pausedErrorW = minWidth;

    double totalW = completedW + encryptingCompletedW + encryptingRemainingW + pendingW + pausedErrorW;

    if (totalW > w) {
      double scale = w / totalW;
      completedW *= scale;
      encryptingCompletedW *= scale;
      encryptingRemainingW *= scale;
      pendingW *= scale;
      pausedErrorW *= scale;
    }

    canvas.save();
    canvas.clipRRect(
      RRect.fromRectAndRadius(Offset.zero & size, const Radius.circular(2)),
    );

    double currentX = 0;

    void drawSegment(double width, Color color) {
      if (width <= 0) return;
      final paint = Paint()..color = color;
      canvas.drawRect(Rect.fromLTWH(currentX, 0, width, h), paint);
      currentX += width;
    }

    // 1. Fully completed files (Green)
    drawSegment(completedW, Colors.green);

    // 2. White separator if both fully completed and partially completed portions exist
    if (completedW > 0 && encryptingCompletedW > 0) {
      final whitePaint = Paint()..color = Colors.white;
      canvas.drawRect(Rect.fromLTWH(currentX - 1, 0, 2, h), whitePaint);
    }

    // 3. Partially completed files (Green)
    drawSegment(encryptingCompletedW, Colors.green);

    // 4. Remaining to encrypt (Yellow)
    drawSegment(encryptingRemainingW, Colors.yellow);

    // 5. Paused/Error (Red)
    drawSegment(pausedErrorW, Colors.red);

    // 6. Pending (Grey)
    drawSegment(pendingW, Colors.grey.withOpacity(0.4));

    if (currentX < w) {
      drawSegment(w - currentX, Colors.grey.withOpacity(0.3));
    }

    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant _EncryptionProgressLinePainter oldDelegate) {
    return oldDelegate.completedSize != completedSize ||
        oldDelegate.encryptingCompletedSize != encryptingCompletedSize ||
        oldDelegate.encryptingRemainingSize != encryptingRemainingSize ||
        oldDelegate.pendingSize != pendingSize ||
        oldDelegate.pausedErrorSize != pausedErrorSize ||
        oldDelegate.totalSize != totalSize;
  }
}
