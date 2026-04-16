import 'package:flutter/material.dart';
import 'cloud_drive_progress_manager.dart';

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
    final hasChildren = task.isFolder && task.children.isNotEmpty;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        ListTile(
          contentPadding: EdgeInsets.only(
            left: 16.0 + widget.level * 24.0,
            right: 16.0,
          ),
          leading: Icon(
            task.isFolder ? Icons.folder_rounded : Icons.insert_drive_file_rounded,
            color: task.isFolder ? Colors.amber : Colors.blueAccent,
          ),
          title: Text(task.name),
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
          ...task.children.map((child) => _TaskItemNode(
                task: child,
                level: widget.level + 1,
              )),
      ],
    );
  }

  Widget _buildSubtitle(SyncTask task) {
    if (task.isFolder) {
      final total = task.children.length;
      final completed = task.children.where((e) => e.status == SyncTaskStatus.completed).length;
      return Text('文件数量: $completed / $total');
    }

    final percent = (task.progress * 100).toStringAsFixed(1);
    final sizeStr = '${(task.transferredSize / 1024).toStringAsFixed(1)}KB / ${(task.totalSize / 1024).toStringAsFixed(1)}KB';

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('$sizeStr ($percent%)'),
        const SizedBox(height: 4),
        LinearProgressIndicator(
          value: task.progress,
          backgroundColor: Colors.grey.withOpacity(0.2),
        ),
      ],
    );
  }

  Widget _buildActionIcon(SyncTask task) {
    if (task.isFolder) {
      return const SizedBox.shrink();
    }

    final manager = CloudDriveProgressManager.instance;
    switch (task.status) {
      case SyncTaskStatus.running:
      case SyncTaskStatus.pending:
        return IconButton(
          icon: const Icon(Icons.pause_circle_filled_rounded, color: Colors.orange),
          onPressed: () => manager.pauseTask(task.id),
          tooltip: '暂停',
        );
      case SyncTaskStatus.paused:
      case SyncTaskStatus.failed:
        return IconButton(
          icon: const Icon(Icons.play_circle_filled_rounded, color: Colors.green),
          onPressed: () => manager.resumeTask(task.id),
          tooltip: '开始/恢复',
        );
      case SyncTaskStatus.completed:
        return const Icon(Icons.check_circle_rounded, color: Colors.green);
    }
  }
}
