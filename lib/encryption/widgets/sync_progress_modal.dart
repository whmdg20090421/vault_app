import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../services/encryption_task_manager.dart';
import '../models/encryption_node.dart';
import 'four_color_progress_bar.dart';

class SyncProgressModal extends StatefulWidget {
  const SyncProgressModal({super.key});

  static void show(BuildContext context) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => const SyncProgressModal(),
    );
  }

  @override
  State<SyncProgressModal> createState() => _SyncProgressModalState();
}

class _SyncProgressModalState extends State<SyncProgressModal> {
  @override
  Widget build(BuildContext context) {
    return Container(
      height: MediaQuery.of(context).size.height * 0.7,
      decoration: BoxDecoration(
        color: Theme.of(context).scaffoldBackgroundColor,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
      ),
      child: Column(
        children: [
          Container(
            padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 16),
            decoration: BoxDecoration(
              border: Border(
                bottom: BorderSide(color: Colors.grey.withOpacity(0.2)),
              ),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text(
                  '同步进度',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                ),
                IconButton(
                  icon: const Icon(Icons.close),
                  onPressed: () => Navigator.pop(context),
                ),
              ],
            ),
          ),
          Expanded(
            child: ListenableBuilder(
              listenable: EncryptionTaskManager(),
              builder: (context, _) {
                final manager = EncryptionTaskManager();
                final tasks = manager.globalTasks;

                if (tasks.isEmpty) {
                  return const Center(
                    child: Text('暂无进行中的任务', style: TextStyle(color: Colors.grey)),
                  );
                }

                return ListView.builder(
                  itemCount: tasks.length,
                  itemBuilder: (context, index) {
                    return SyncProgressItem(node: tasks[index], manager: manager);
                  },
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

class SyncProgressItem extends StatefulWidget {
  final EncryptionNode node;
  final EncryptionTaskManager manager;
  final int depth;

  const SyncProgressItem({
    super.key,
    required this.node,
    required this.manager,
    this.depth = 0,
  });

  @override
  State<SyncProgressItem> createState() => _SyncProgressItemState();
}

class _SyncProgressItemState extends State<SyncProgressItem> {
  bool _isExpanded = false;

  void _togglePause() {
    if (widget.node.isPaused) {
      widget.manager.resumeNodeV4(widget.node);
    } else {
      widget.manager.pauseNodeV4(widget.node);
    }
  }

  void _showOptions() {
    showModalBottomSheet(
      context: context,
      builder: (ctx) {
        final hasError = _hasError(widget.node);
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ListTile(
                leading: const Icon(Icons.delete, color: Colors.red),
                title: const Text('移除加密任务', style: TextStyle(color: Colors.red)),
                onTap: () {
                  Navigator.pop(ctx);
                  _confirmDelete();
                },
              ),
              if (hasError)
                ListTile(
                  leading: const Icon(Icons.build, color: Colors.blue),
                  title: const Text('标记为已修复'),
                  onTap: () {
                    Navigator.pop(ctx);
                    widget.manager.markNodeAsFixedV4(widget.node);
                  },
                ),
            ],
          ),
        );
      },
    );
  }

  bool _hasError(EncryptionNode node) {
    if (node.type == EncryptionNodeType.file) {
      return node.status == EncryptionStatus.error;
    }
    if (node.children != null) {
      for (final child in node.children!) {
        if (_hasError(child)) return true;
      }
    }
    return false;
  }

  void _confirmDelete() {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('移除任务'),
        content: const Text('确定要移除此加密任务吗？相关线程将被终止。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () {
              Navigator.pop(ctx);
              widget.manager.deleteNodeV4(widget.node);
            },
            child: const Text('移除', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );
  }

  Map<String, int> _getNodeStats(EncryptionNode node) {
    int completed = 0;
    int encrypting = 0;
    int pending = 0;
    int pausedError = 0;
    int fileCount = 0;
    int completedFileCount = 0;

    void traverse(EncryptionNode n) {
      if (n.type == EncryptionNodeType.file) {
        fileCount++;
        final size = n.rawSize ?? 0;
        if (n.isPaused) {
          pausedError += size;
        } else {
          switch (n.status) {
            case EncryptionStatus.completed:
              completed += size;
              completedFileCount++;
              break;
            case EncryptionStatus.encrypting:
              encrypting += size;
              break;
            case EncryptionStatus.pendingWaiting:
              pending += size;
              break;
            case EncryptionStatus.pendingPaused:
            case EncryptionStatus.error:
            case null:
              pausedError += size;
              break;
          }
        }
      } else if (n.children != null) {
        for (final child in n.children!) {
          if (n.isPaused) {
            _addPausedSize(child, (s) => pausedError += s);
            _addFileCount(child, (c) => fileCount += c);
          } else {
            traverse(child);
          }
        }
      }
    }

    traverse(node);

    return {
      'completed': completed,
      'encrypting': encrypting,
      'pending': pending,
      'pausedError': pausedError,
      'total': completed + encrypting + pending + pausedError,
      'fileCount': fileCount,
      'completedFileCount': completedFileCount,
    };
  }

  void _addPausedSize(EncryptionNode node, Function(int) add) {
    if (node.type == EncryptionNodeType.file) {
      add(node.rawSize ?? 0);
    } else if (node.children != null) {
      for (final child in node.children!) {
        _addPausedSize(child, add);
      }
    }
  }

  void _addFileCount(EncryptionNode node, Function(int) add) {
    if (node.type == EncryptionNodeType.file) {
      add(1);
    } else if (node.children != null) {
      for (final child in node.children!) {
        _addFileCount(child, add);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final stats = _getNodeStats(widget.node);
    final total = stats['total'] ?? 0;
    final completed = stats['completed'] ?? 0;
    final encrypting = stats['encrypting'] ?? 0;
    final pending = stats['pending'] ?? 0;
    final pausedError = stats['pausedError'] ?? 0;
    final fileCount = stats['fileCount'] ?? 0;
    final completedFileCount = stats['completedFileCount'] ?? 0;

    final double percentage = total > 0 ? (completed / total) * 100 : 0.0;
    final bool hasError = _hasError(widget.node);

    return Column(
      children: [
        InkWell(
          onTap: widget.node.type == EncryptionNodeType.folder
              ? () => setState(() => _isExpanded = !_isExpanded)
              : null,
          onLongPress: _showOptions,
          child: Padding(
            padding: EdgeInsets.only(
              left: 16.0 + (widget.depth * 16.0),
              right: 16.0,
              top: 8.0,
              bottom: 8.0,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // 第一行：暂停/继续按钮、名称、异常叹号
                Row(
                  children: [
                    GestureDetector(
                      onTap: _togglePause,
                      child: Icon(
                        widget.node.isPaused
                            ? Icons.play_circle_fill
                            : Icons.pause_circle_filled,
                        size: 20,
                        color: widget.node.isPaused ? Colors.grey : Colors.blue,
                      ),
                    ),
                    const SizedBox(width: 8),
                    if (widget.node.type == EncryptionNodeType.folder)
                      Icon(
                        _isExpanded ? Icons.folder_open : Icons.folder,
                        size: 18,
                        color: Colors.amber,
                      ),
                    if (widget.node.type == EncryptionNodeType.file)
                      const Icon(Icons.insert_drive_file, size: 18, color: Colors.grey),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        widget.node.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontSize: 14),
                      ),
                    ),
                    if (hasError)
                      const Icon(Icons.error_outline, size: 16, color: Colors.red),
                  ],
                ),
                const SizedBox(height: 6),
                // 第二行：极细四色进度条
                FourColorProgressBar(
                  completed: completed,
                  encrypting: encrypting,
                  pending: pending,
                  pausedError: pausedError,
                  total: total,
                  height: 2.0,
                ),
                const SizedBox(height: 6),
                // 第三行：百分比/异常状态、数量统计
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      hasError ? '存在异常' : '${percentage.toStringAsFixed(1)}%',
                      style: TextStyle(
                        fontSize: 12,
                        color: hasError ? Colors.red : Colors.grey.shade600,
                      ),
                    ),
                    Text(
                      widget.node.type == EncryptionNodeType.file
                          ? '1/1'
                          : '$completedFileCount/$fileCount',
                      style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
        if (_isExpanded && widget.node.children != null)
          ...widget.node.children!.map(
            (child) => SyncProgressItem(
              node: child,
              manager: widget.manager,
              depth: widget.depth + 1,
            ),
          ),
      ],
    );
  }
}
