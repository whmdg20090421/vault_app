import 'package:flutter/material.dart';
import 'cloud_drive_progress_manager.dart';
import '../models/sync_task.dart';
import '../utils/format_utils.dart';

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
  final List<SyncTask> _taskStack = [];

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

  void _pushTask(SyncTask task) {
    setState(() {
      _taskStack.add(task);
    });
  }

  void _popTask() {
    setState(() {
      if (_taskStack.isNotEmpty) {
        _taskStack.removeLast();
      }
    });
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
            final isRoot = _taskStack.isEmpty;
            final title = isRoot ? '云盘同步进度' : '同步任务详情';

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
                            onPressed: _popTask,
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
                          _buildTaskList(tasks, theme, scrollController, isCyberpunk, false),
                          _buildTaskList(_historyTasks, theme, scrollController, isCyberpunk, true),
                        ],
                      ),
                    ),
                  ] else ...[
                    if (isCyberpunk) Divider(height: 1, color: theme.colorScheme.primary.withOpacity(0.5)),
                    Expanded(
                      child: _buildItemList(_taskStack.last.items, theme, scrollController, isCyberpunk),
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

  Widget _buildTaskList(List<SyncTask> tasks, ThemeData theme, ScrollController scrollController, bool isCyberpunk, bool isHistory) {
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
        return _SyncTaskCard(
          task: task,
          theme: theme,
          isCyberpunk: isCyberpunk,
          isHistory: isHistory,
          onTap: () => _pushTask(task),
        );
      },
    );
  }

  Widget _buildItemList(List<SyncFileItem> items, ThemeData theme, ScrollController scrollController, bool isCyberpunk) {
    if (items.isEmpty) {
      return Center(
        child: Text(
          '当前没有文件',
          style: TextStyle(color: theme.colorScheme.onSurface.withOpacity(0.5)),
        ),
      );
    }
    return ListView.builder(
      controller: scrollController,
      padding: const EdgeInsets.all(16),
      itemCount: items.length,
      itemBuilder: (context, index) {
        final item = items[index];
        return _SyncItemCard(
          item: item,
          theme: theme,
          isCyberpunk: isCyberpunk,
        );
      },
    );
  }
}

class _SyncTaskCard extends StatelessWidget {
  final SyncTask task;
  final ThemeData theme;
  final bool isCyberpunk;
  final bool isHistory;
  final VoidCallback onTap;

  const _SyncTaskCard({
    required this.task,
    required this.theme,
    required this.isCyberpunk,
    required this.isHistory,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final uploadItems = task.items.where((i) => i.action == SyncItemAction.upload).toList();
    final downloadItems = task.items.where((i) => i.action == SyncItemAction.download).toList();

    int totalUploadBytes = uploadItems.fold(0, (sum, i) => sum + i.size);
    int completedUploadBytes = uploadItems.where((i) => i.status == SyncStatus.completed).fold(0, (sum, i) => sum + i.size);
    int totalDownloadBytes = downloadItems.fold(0, (sum, i) => sum + i.size);
    int completedDownloadBytes = downloadItems.where((i) => i.status == SyncStatus.completed).fold(0, (sum, i) => sum + i.size);

    double uploadProgress = totalUploadBytes > 0 ? completedUploadBytes / totalUploadBytes : (uploadItems.isEmpty ? 1.0 : 0.0);
    double downloadProgress = totalDownloadBytes > 0 ? completedDownloadBytes / totalDownloadBytes : (downloadItems.isEmpty ? 1.0 : 0.0);

    bool isUploadCompleted = uploadItems.every((i) => i.status == SyncStatus.completed);
    bool isDownloadCompleted = downloadItems.every((i) => i.status == SyncStatus.completed);

    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
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
                Expanded(
                  child: Text(
                    task.cloudFolderPath,
                    style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                if (!isHistory) ...[
                  IconButton(
                    icon: Icon(task.isUploadPaused ? Icons.play_arrow : Icons.pause, color: Colors.blue, size: 20),
                    onPressed: () {
                      if (task.isUploadPaused) {
                        CloudDriveProgressManager.instance.resumeUpload(task.id);
                      } else {
                        CloudDriveProgressManager.instance.pauseUpload(task.id);
                      }
                    },
                    tooltip: task.isUploadPaused ? '继续上传' : '暂停上传',
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(),
                  ),
                  const SizedBox(width: 8),
                  IconButton(
                    icon: Icon(task.isDownloadPaused ? Icons.play_arrow : Icons.pause, color: Colors.green, size: 20),
                    onPressed: () {
                      if (task.isDownloadPaused) {
                        CloudDriveProgressManager.instance.resumeDownload(task.id);
                      } else {
                        CloudDriveProgressManager.instance.pauseDownload(task.id);
                      }
                    },
                    tooltip: task.isDownloadPaused ? '继续下载' : '暂停下载',
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(),
                  ),
                  const SizedBox(width: 8),
                  IconButton(
                    icon: const Icon(Icons.delete_outline, color: Colors.red, size: 20),
                    onPressed: () => CloudDriveProgressManager.instance.deleteTask(task.id),
                    tooltip: '删除任务',
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(),
                  ),
                ],
              ],
            ),
            const SizedBox(height: 12),
            // Line 1: Upload progress bar
            LinearProgressIndicator(
              value: task.status == SyncStatus.pending ? null : uploadProgress,
              backgroundColor: Colors.blue.withOpacity(0.1),
              valueColor: AlwaysStoppedAnimation<Color>(isUploadCompleted ? Colors.blue.withOpacity(0.5) : Colors.blue),
              borderRadius: BorderRadius.circular(4),
            ),
            const SizedBox(height: 4),
            // Line 2: Upload info
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  '上传',
                  style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.blue),
                ),
                Text(
                  task.status == SyncStatus.pending ? '准备中...' : '${FormatUtils.formatBytes(completedUploadBytes)} / ${FormatUtils.formatBytes(totalUploadBytes)} (${(uploadProgress * 100).toStringAsFixed(1)}%)',
                  style: TextStyle(fontSize: 12, color: theme.colorScheme.onSurface.withOpacity(0.7)),
                ),
              ],
            ),
            const SizedBox(height: 12),
            // Line 3: Download progress bar
            LinearProgressIndicator(
              value: task.status == SyncStatus.pending ? null : downloadProgress,
              backgroundColor: Colors.green.withOpacity(0.1),
              valueColor: AlwaysStoppedAnimation<Color>(isDownloadCompleted ? Colors.green.withOpacity(0.5) : Colors.green),
              borderRadius: BorderRadius.circular(4),
            ),
            const SizedBox(height: 4),
            // Line 4: Download info
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  '下载',
                  style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.green),
                ),
                Text(
                  task.status == SyncStatus.pending ? '准备中...' : '${FormatUtils.formatBytes(completedDownloadBytes)} / ${FormatUtils.formatBytes(totalDownloadBytes)} (${(downloadProgress * 100).toStringAsFixed(1)}%)',
                  style: TextStyle(fontSize: 12, color: theme.colorScheme.onSurface.withOpacity(0.7)),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _SyncItemCard extends StatelessWidget {
  final SyncFileItem item;
  final ThemeData theme;
  final bool isCyberpunk;

  const _SyncItemCard({
    required this.item,
    required this.theme,
    required this.isCyberpunk,
  });

  @override
  Widget build(BuildContext context) {
    Color statusColor;
    String statusText;
    switch (item.status) {
      case SyncStatus.completed:
        statusColor = Colors.green;
        statusText = '完成';
        break;
      case SyncStatus.failed:
        statusColor = Colors.red;
        statusText = '失败';
        break;
      case SyncStatus.syncing:
        statusColor = theme.colorScheme.primary;
        statusText = '同步中';
        break;
      case SyncStatus.paused:
        statusColor = Colors.orange;
        statusText = '已暂停';
        break;
      case SyncStatus.pending:
      default:
        statusColor = theme.colorScheme.onSurface.withOpacity(0.5);
        statusText = '等待中';
        break;
    }

    IconData actionIcon;
    Color actionColor;
    switch (item.action) {
      case SyncItemAction.upload:
        actionIcon = Icons.cloud_upload;
        actionColor = Colors.blue;
        break;
      case SyncItemAction.download:
        actionIcon = Icons.cloud_download;
        actionColor = Colors.green;
        break;
      case SyncItemAction.delete:
        actionIcon = Icons.delete;
        actionColor = Colors.red;
        break;
    }

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest.withOpacity(0.3),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        children: [
          Icon(actionIcon, color: actionColor, size: 20),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  item.name,
                  style: const TextStyle(fontWeight: FontWeight.w500),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                if (item.errorMessage != null)
                  Text(
                    item.errorMessage!,
                    style: const TextStyle(fontSize: 10, color: Colors.red),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  )
                else
                  Text(
                    FormatUtils.formatBytes(item.size),
                    style: TextStyle(fontSize: 10, color: theme.colorScheme.onSurface.withOpacity(0.5)),
                  ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          Text(
            statusText,
            style: TextStyle(fontSize: 12, color: statusColor, fontWeight: FontWeight.bold),
          ),
        ],
      ),
    );
  }
}
