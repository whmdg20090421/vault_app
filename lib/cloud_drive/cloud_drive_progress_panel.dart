import 'package:flutter/material.dart';
import 'cloud_drive_progress_manager.dart';
import '../models/sync_task.dart';

void showCloudDriveProgressPanel(BuildContext context) {
  showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    builder: (context) => const CloudDriveProgressPanel(),
  );
}

class CloudDriveProgressPanel extends StatelessWidget {
  const CloudDriveProgressPanel({super.key});

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: CloudDriveProgressManager.instance,
      builder: (context, _) {
        final manager = CloudDriveProgressManager.instance;
        final tasks = manager.tasks;

        return DraggableScrollableSheet(
          expand: false,
          initialChildSize: 0.6,
          minChildSize: 0.4,
          maxChildSize: 0.9,
          builder: (context, scrollController) {
            return Column(
              children: [
                _buildHeader(context, manager),
                const Divider(height: 1),
                Expanded(
                  child: tasks.isEmpty
                      ? const Center(child: Text('暂无传输任务'))
                      : ListView.builder(
                          controller: scrollController,
                          itemCount: tasks.length,
                          itemBuilder: (context, index) {
                            return _TaskItemNode(task: tasks[index], level: 0);
                          },
                        ),
                ),
              ],
            );
          },
        );
      },
    );
  }

  Widget _buildHeader(BuildContext context, CloudDriveProgressManager manager) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Row(
        children: [
          const Icon(Icons.cloud_sync_rounded),
          const SizedBox(width: 8),
          Text(
            '传输进度',
            style: Theme.of(context).textTheme.titleLarge,
          ),
          const Spacer(),
          TextButton.icon(
            onPressed: manager.pauseAll,
            icon: const Icon(Icons.pause_circle_outline_rounded),
            label: const Text('全部暂停'),
          ),
          TextButton.icon(
            onPressed: manager.startAll,
            icon: const Icon(Icons.play_circle_outline_rounded),
            label: const Text('一键全部开启'),
          ),
        ],
      ),
    );
  }
}

class _TaskItemNode extends StatefulWidget {
  const _TaskItemNode({
    required this.task,
    required this.level,
  });

  final SyncTask task;
  final int level;

  @override
  State<_TaskItemNode> createState() => _TaskItemNodeState();
}

class _TaskItemNodeState extends State<_TaskItemNode> {
  bool _expanded = true;

  @override
  Widget build(BuildContext context) {
    final task = widget.task;
    final hasChildren = task.items.isNotEmpty;

    String taskTitle = task.direction == SyncDirection.cloudToLocal 
        ? '下载: ${task.cloudFolderPath}' 
        : '上传: ${task.localFolderPath}';

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        ListTile(
          contentPadding: EdgeInsets.only(
            left: 16.0 + widget.level * 24.0,
            right: 16.0,
          ),
          leading: const Icon(
            Icons.sync_rounded,
            color: Colors.amber,
          ),
          title: Text(taskTitle),
          subtitle: _buildSubtitle(task),
          trailing: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              _buildActionIcon(task),
              if (hasChildren)
                IconButton(
                  icon: Icon(
                    _expanded ? Icons.expand_less_rounded : Icons.expand_more_rounded,
                  ),
                  onPressed: () {
                    setState(() {
                      _expanded = !_expanded;
                    });
                  },
                ),
            ],
          ),
        ),
        if (_expanded && hasChildren)
          ...task.items.map((item) => _FileItemNode(
                item: item,
                level: widget.level + 1,
              )),
      ],
    );
  }

  Widget _buildSubtitle(SyncTask task) {
    final total = task.items.length;
    final completed = task.items.where((e) => e.status == SyncStatus.completed).length;
    return Text('文件数量: $completed / $total');
  }

  Widget _buildActionIcon(SyncTask task) {
    final manager = CloudDriveProgressManager.instance;
    switch (task.status) {
      case SyncStatus.syncing:
      case SyncStatus.pending:
        return IconButton(
          icon: const Icon(Icons.pause_circle_filled_rounded, color: Colors.orange),
          onPressed: () => manager.pauseTask(task.id),
          tooltip: '暂停',
        );
      case SyncStatus.paused:
      case SyncStatus.failed:
        return IconButton(
          icon: const Icon(Icons.play_circle_filled_rounded, color: Colors.green),
          onPressed: () => manager.resumeTask(task.id),
          tooltip: '开始/恢复',
        );
      case SyncStatus.completed:
        return const Icon(Icons.check_circle_rounded, color: Colors.green);
    }
  }
}

class _FileItemNode extends StatelessWidget {
  const _FileItemNode({
    required this.item,
    required this.level,
  });

  final SyncFileItem item;
  final int level;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      contentPadding: EdgeInsets.only(
        left: 16.0 + level * 24.0,
        right: 16.0,
      ),
      leading: const Icon(
        Icons.insert_drive_file_rounded,
        color: Colors.blueAccent,
      ),
      title: Text(item.name),
      subtitle: _buildSubtitle(item),
      trailing: _buildActionIcon(item),
    );
  }

  Widget _buildSubtitle(SyncFileItem item) {
    final sizeStr = '${(item.size / 1024).toStringAsFixed(1)}KB';
    
    if (item.status == SyncStatus.failed && item.errorMessage != null) {
      return Text('$sizeStr - 失败: ${item.errorMessage}', style: const TextStyle(color: Colors.red));
    }
    
    return Text(sizeStr);
  }

  Widget _buildActionIcon(SyncFileItem item) {
    switch (item.status) {
      case SyncStatus.syncing:
        return const SizedBox(
          width: 24,
          height: 24,
          child: CircularProgressIndicator(strokeWidth: 2),
        );
      case SyncStatus.pending:
        return const Icon(Icons.schedule_rounded, color: Colors.grey);
      case SyncStatus.paused:
        return const Icon(Icons.pause_circle_outline_rounded, color: Colors.orange);
      case SyncStatus.failed:
        return const Icon(Icons.error_outline_rounded, color: Colors.red);
      case SyncStatus.completed:
        return const Icon(Icons.check_circle_rounded, color: Colors.green);
    }
  }
}
