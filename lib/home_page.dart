import 'package:flutter/material.dart';
import 'services/stats_service.dart';
import 'utils/format_utils.dart';

class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  @override
  void initState() {
    super.initState();
    // 页面初始化时触发重新计算
    WidgetsBinding.instance.addPostFrameCallback((_) {
      StatsService().recalculate();
    });
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: StatsService(),
      builder: (context, _) {
        final statsService = StatsService();
        final int encryptedBytes = statsService.encryptedBytes;
        final int unencryptedBytes = statsService.unencryptedBytes;
        final int totalBytes = statsService.totalBytes;

        final double encryptedPercentage = totalBytes > 0 ? (encryptedBytes / totalBytes) : 0;

        return RefreshIndicator(
          onRefresh: () async {
            await statsService.recalculate();
          },
          child: SingleChildScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        child: Padding(
          padding: const EdgeInsets.all(16.0),
          child: Card(
            child: Padding(
              padding: const EdgeInsets.all(24.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '数据概览',
                    style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 24),
                  if (totalBytes == 0)
                    const Center(
                      child: Padding(
                        padding: EdgeInsets.symmetric(vertical: 32.0),
                        child: Text(
                          '暂无数据',
                          style: TextStyle(fontSize: 16, color: Colors.grey),
                        ),
                      ),
                    )
                  else
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        TweenAnimationBuilder<double>(
                          tween: Tween<double>(begin: 0, end: encryptedPercentage),
                          duration: const Duration(milliseconds: 1200),
                          curve: Curves.easeOutCubic,
                          builder: (context, value, child) {
                            return Container(
                              height: 24,
                              width: double.infinity,
                              decoration: BoxDecoration(
                                borderRadius: BorderRadius.circular(12),
                                // 未加密部分背景
                                gradient: LinearGradient(
                                  colors: [Colors.red.shade400, Colors.red.shade700],
                                  begin: Alignment.centerLeft,
                                  end: Alignment.centerRight,
                                ),
                                boxShadow: [
                                  BoxShadow(
                                    color: Colors.red.withOpacity(0.3),
                                    blurRadius: 8,
                                    offset: const Offset(0, 2),
                                  ),
                                ],
                              ),
                              child: Stack(
                                children: [
                                  // 已加密部分前景（带发光效果）
                                  FractionallySizedBox(
                                    widthFactor: value,
                                    child: Container(
                                      decoration: BoxDecoration(
                                        borderRadius: BorderRadius.circular(12),
                                        gradient: const LinearGradient(
                                          colors: [Colors.greenAccent, Colors.green],
                                          begin: Alignment.centerLeft,
                                          end: Alignment.centerRight,
                                        ),
                                        boxShadow: [
                                          BoxShadow(
                                            color: Colors.greenAccent.withOpacity(0.6),
                                            blurRadius: 10,
                                            spreadRadius: 1,
                                          ),
                                        ],
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            );
                          },
                        ),
                        const SizedBox(height: 24),
                        Text(
                          '🟩 已加密: ${FormatUtils.formatBytes(encryptedBytes)} (${(encryptedPercentage * 100).toStringAsFixed(0)}%)',
                          style: const TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.bold,
                            fontFamily: 'monospace',
                          ),
                        ),
                        const SizedBox(height: 12),
                        Text(
                          '🟥 未加密: ${FormatUtils.formatBytes(unencryptedBytes)} (${((1 - encryptedPercentage) * 100).toStringAsFixed(0)}%)',
                          style: const TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.bold,
                            fontFamily: 'monospace',
                          ),
                        ),
                      ],
                    ),
                ],
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
