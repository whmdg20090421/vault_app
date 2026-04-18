import 'package:flutter/material.dart';

class FourColorProgressBar extends StatelessWidget {
  final int completed;
  final int encrypting;
  final int pending;
  final int pausedError;
  final int total;
  final double height;

  const FourColorProgressBar({
    super.key,
    required this.completed,
    required this.encrypting,
    required this.pending,
    required this.pausedError,
    required this.total,
    this.height = 4.0,
  });

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final double width = constraints.maxWidth;
        if (total == 0 || width <= 0) {
          return Container(
            height: height,
            width: double.infinity,
            color: Colors.grey.shade800,
          );
        }

        // Calculate theoretical pixels
        double completedPx = (completed / total) * width;
        double encryptingPx = (encrypting / total) * width;
        double pendingPx = (pending / total) * width;
        double pausedErrorPx = (pausedError / total) * width;

        // Apply <1% -> 1px rule (only if value > 0)
        if (completed > 0 && completedPx < 1.0) completedPx = 1.0;
        if (encrypting > 0 && encryptingPx < 1.0) encryptingPx = 1.0;
        if (pending > 0 && pendingPx < 1.0) pendingPx = 1.0;
        if (pausedError > 0 && pausedErrorPx < 1.0) pausedErrorPx = 1.0;

        // Normalize if total pixels exceed width due to 1px adjustments
        final totalPx = completedPx + encryptingPx + pendingPx + pausedErrorPx;
        if (totalPx > width && totalPx > 0) {
          final scale = width / totalPx;
          completedPx *= scale;
          encryptingPx *= scale;
          pendingPx *= scale;
          pausedErrorPx *= scale;
        }

        return Container(
          height: height,
          width: double.infinity,
          clipBehavior: Clip.hardEdge,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(height / 2),
            color: Colors.grey.shade800,
          ),
          child: Row(
            children: [
              if (completedPx > 0)
                Container(width: completedPx, color: Colors.green),
              if (encryptingPx > 0)
                Container(width: encryptingPx, color: Colors.amber),
              if (pendingPx > 0)
                Container(width: pendingPx, color: Colors.redAccent),
              if (pausedErrorPx > 0)
                Container(width: pausedErrorPx, color: Colors.grey),
            ],
          ),
        );
      },
    );
  }
}
