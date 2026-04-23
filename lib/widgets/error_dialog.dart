import 'package:flutter/material.dart';

void showVfsErrorDialog(BuildContext context, String errorMessage, {String title = '解析失败'}) {
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
              Text(title, style: const TextStyle(fontWeight: FontWeight.bold)),
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
