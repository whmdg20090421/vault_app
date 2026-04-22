import 'package:flutter/material.dart';
import 'cloud_drive_progress_manager.dart';
import '../models/sync_task.dart';

void showCloudDriveProgressPanel(BuildContext context) {
  final theme = Theme.of(context);
  showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    barrierColor: theme.colorScheme.scrim.withValues(alpha: 0.6),
    builder: (context) => const CloudDriveProgressPanel(),
  );
}

class CloudDriveProgressPanel extends StatefulWidget {
  const CloudDriveProgressPanel({super.key});

  @override
  State<CloudDriveProgressPanel> createState() => _CloudDriveProgressPanelState();
}

class _CloudDriveProgressPanelState extends State<CloudDriveProgressPanel> with SingleTickerProviderStateMixin {
  late final TabController _tabController;
  List<SyncTask> _historyTasks = [];

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _loadHistory();
  }

  Future<void> _loadHistory() async {
    final history = await CloudDriveProgressManager.instance.getHistory();
    if (mounted) {
      setState(() {
        _historyTasks = history;
      });
    }
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: CloudDriveProgressManager.instance,
      builder: (context, _) {
        final manager = CloudDriveProgressManager.instance;
        final tasks = manager.tasks;
        final theme = Theme.of(context);
        final isCyberpunk = theme.brightness == Brightness.dark && theme.colorScheme.primary.value == 0xFF00E5FF;
        final surfaceColor = theme.dialogTheme.backgroundColor ?? theme.cardTheme.color ?? theme.colorScheme.surface;

        return DraggableScrollableSheet(
          expand: false,
          initialChildSize: 0.6,
          minChildSize: 0.4,
          maxChildSize: 0.9,
          builder: (context, scrollController) {
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
                        Expanded(
                          child: Text(
                            '云盘同步进度',
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
                        _buildTaskList(tasks, theme, scrollController, isCyberpunk),
                        _buildTaskList(_historyTasks, theme, scrollController, isCyberpunk),
                      ],
                    ),
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }

  Widget _buildTaskList(List<SyncTask> tasks, ThemeData theme, ScrollController scrollController, bool isCyberpunk) {
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
        return TweenAnimationBuilder<double>(
          tween: Tween(begin: 0.8, end: 1.0),
          duration: const Duration(milliseconds: 500),
          curve: Curves.elasticOut,
          builder: (context, value, child) {
            return Transform.scale(
              scale: value,
              child: Opacity(
                opacity: value.clamp(0.0, 1.0),
                child: _buildSyncTaskCard(task, theme, isCyberpunk),
              ),
            );
          },
        );
      },
    );
  }

  Widget _buildSyncTaskCard(SyncTask task, ThemeData theme, bool isCyberpunk) {
    final progress = task.status == SyncStatus.completed ? 1.0 : (task.items.isEmpty ? 0.0 : task.items.where((i) => i.status == SyncStatus.completed).length / task.items.length);
    
    String statusText;
    Color statusColor;
    if (task.status == SyncStatus.completed) {
      statusText = '完成';
      statusColor = Colors.green;
    } else if (task.status == SyncStatus.failed) {
      statusText = '失败';
      statusColor = Colors.red;
    } else if (task.status == SyncStatus.pending) {
      statusText = '准备中...';
      statusColor = theme.colorScheme.primary.withOpacity(0.7);
    } else {
      statusText = '同步中';
      statusColor = theme.colorScheme.primary;
    }

    return AnimatedContainer(
      duration: const Duration(milliseconds: 300),
      curve: Curves.elasticOut,
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: isCyberpunk ? Colors.transparent : theme.colorScheme.surface,
        borderRadius: isCyberpunk ? BorderRadius.zero : BorderRadius.circular(16),
        border: isCyberpunk ? Border.all(color: theme.colorScheme.primary.withOpacity(0.3)) : Border.all(color: Colors.transparent),
        boxShadow: isCyberpunk ? null : [
          BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 10, offset: const Offset(0, 4))
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(task.direction == SyncDirection.cloudToLocal ? Icons.cloud_download : Icons.cloud_upload, color: theme.colorScheme.primary),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  task.id,
                  style: const TextStyle(fontWeight: FontWeight.bold),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              Text(
                statusText,
                style: TextStyle(color: statusColor),
              ),
            ],
          ),
          const SizedBox(height: 12),
          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: LinearProgressIndicator(
              value: task.status == SyncStatus.pending ? null : progress,
              backgroundColor: theme.colorScheme.primary.withOpacity(0.1),
              valueColor: AlwaysStoppedAnimation<Color>(task.status == SyncStatus.completed ? Colors.green : theme.colorScheme.primary),
            ),
          ),
          const SizedBox(height: 8),
          Text(
            task.status == SyncStatus.pending ? '正在扫描文件差异...' : '${(progress * 100).toStringAsFixed(1)}%',
            style: TextStyle(fontSize: 12, color: theme.colorScheme.onSurface.withOpacity(0.7)),
          ),
        ],
      ),
    );
  }
}
