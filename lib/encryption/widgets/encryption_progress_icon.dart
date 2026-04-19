import 'package:flutter/material.dart';
import '../models/encryption_node.dart';
import '../services/encryption_task_manager.dart';
import '../../utils/format_utils.dart';
import 'encryption_progress_panel.dart';

class EncryptionProgressIcon extends StatelessWidget {
  const EncryptionProgressIcon({super.key});

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: EncryptionTaskManager(),
      builder: (context, _) {
        final tasks = EncryptionTaskManager().tasks;
        int completedSize = 0;
        int encryptingSize = 0;
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
                encryptingSize += node.rawSize;
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

        for (var task in tasks) {
          traverse(task);
        }

        // SubTask 4.2: 点击显示数值提示(如 已加密大小/总大小)
        final tooltipMessage = '已加密: ${FormatUtils.formatBytes(completedSize)} / 总大小: ${FormatUtils.formatBytes(totalSize)}\n'
            '加密中: ${FormatUtils.formatBytes(encryptingSize)}\n'
            '等待中: ${FormatUtils.formatBytes(pendingSize)}\n'
            '异常/暂停: ${FormatUtils.formatBytes(pausedErrorSize)}';

        return Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16.0),
          child: Center(
            child: Tooltip(
              message: tooltipMessage,
              child: GestureDetector(
                onTap: () {
                  showEncryptionProgressPanel(context);
                },
                child: SizedBox(
                  width: 80,
                  height: 12,
                  child: CustomPaint(
                    painter: _EncryptionProgressPainter(
                      completedSize: completedSize,
                      encryptingSize: encryptingSize,
                      pendingSize: pendingSize,
                      pausedErrorSize: pausedErrorSize,
                      totalSize: totalSize,
                    ),
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

class _EncryptionProgressPainter extends CustomPainter {
  final int completedSize;
  final int encryptingSize;
  final int pendingSize;
  final int pausedErrorSize;
  final int totalSize;

  _EncryptionProgressPainter({
    required this.completedSize,
    required this.encryptingSize,
    required this.pendingSize,
    required this.pausedErrorSize,
    required this.totalSize,
  });

  @override
  void paint(Canvas canvas, Size size) {
    if (totalSize == 0) {
      final paint = Paint()..color = Colors.grey.withOpacity(0.3);
      canvas.drawRRect(
          RRect.fromRectAndRadius(Offset.zero & size, const Radius.circular(6)),
          paint);
      return;
    }

    double w = size.width;
    double h = size.height;

    // SubTask 4.2: 进度条强制可视化规则(任一颜色占比<1%但存在数据时强制显示至少1像素长度)
    double minWidth = 1.0;

    double completedW = completedSize > 0 ? (completedSize / totalSize * w) : 0;
    double encryptingW = encryptingSize > 0 ? (encryptingSize / totalSize * w) : 0;
    double pendingW = pendingSize > 0 ? (pendingSize / totalSize * w) : 0;
    double pausedErrorW = pausedErrorSize > 0 ? (pausedErrorSize / totalSize * w) : 0;

    if (completedSize > 0 && completedW < minWidth) completedW = minWidth;
    if (encryptingSize > 0 && encryptingW < minWidth) encryptingW = minWidth;
    if (pendingSize > 0 && pendingW < minWidth) pendingW = minWidth;
    if (pausedErrorSize > 0 && pausedErrorW < minWidth) pausedErrorW = minWidth;

    double totalW = completedW + encryptingW + pendingW + pausedErrorW;

    // Adjust proportionally if we exceed total width
    if (totalW > w) {
      double scale = w / totalW;
      completedW *= scale;
      encryptingW *= scale;
      pendingW *= scale;
      pausedErrorW *= scale;
    }

    // Prepare clipping
    canvas.save();
    canvas.clipRRect(
        RRect.fromRectAndRadius(Offset.zero & size, const Radius.circular(6)));

    double currentX = 0;

    void drawSegment(double width, Color color) {
      if (width <= 0) return;
      final paint = Paint()..color = color;
      canvas.drawRect(Rect.fromLTWH(currentX, 0, width, h), paint);
      currentX += width;
    }

    // SubTask 4.1: completed(绿), encrypting(黄), pending_waiting(红), pending_paused+error(灰)
    drawSegment(completedW, Colors.green);
    drawSegment(encryptingW, Colors.yellow);
    drawSegment(pendingW, Colors.red);
    drawSegment(pausedErrorW, Colors.grey);

    // If there is still space left due to rounding or missing precision, 
    // fill the rest with grey background
    if (currentX < w) {
      drawSegment(w - currentX, Colors.grey.withOpacity(0.3));
    }

    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant _EncryptionProgressPainter oldDelegate) {
    return oldDelegate.completedSize != completedSize ||
        oldDelegate.encryptingSize != encryptingSize ||
        oldDelegate.pendingSize != pendingSize ||
        oldDelegate.pausedErrorSize != pausedErrorSize ||
        oldDelegate.totalSize != totalSize;
  }
}
