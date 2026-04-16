import 'package:flutter/material.dart';
import 'package:fl_chart/fl_chart.dart';
import 'services/stats_service.dart';

class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  @override
  Widget build(BuildContext context) {
    final statsService = StatsService();
    final int encryptedBytes = statsService.encryptedBytes;
    final int unencryptedBytes = statsService.unencryptedBytes;
    final int totalBytes = statsService.totalBytes;

    final double encryptedPercentage = totalBytes > 0 ? (encryptedBytes / totalBytes) * 100 : 0;
    final double unencryptedPercentage = totalBytes > 0 ? (unencryptedBytes / totalBytes) * 100 : 0;

    return RefreshIndicator(
      onRefresh: () async {
        await statsService.recalculate();
        if (mounted) {
          setState(() {});
        }
      },
      child: SingleChildScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        child: Padding(
          padding: const EdgeInsets.all(16.0),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                flex: 1,
                child: AspectRatio(
                  aspectRatio: 1,
                  child: Card(
                    elevation: 4,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                    child: Padding(
                      padding: const EdgeInsets.all(24.0),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Text(
                            '数据概览',
                            style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
                          ),
                          const SizedBox(height: 24),
                          Expanded(
                            child: PieChart(
                              PieChartData(
                                sectionsSpace: 2,
                                centerSpaceRadius: 50,
                                sections: [
                                  PieChartSectionData(
                                    color: Colors.blueAccent,
                                    value: encryptedBytes.toDouble() > 0 ? encryptedBytes.toDouble() : 1, // 如果为0时避免报错，可以给个极小值，但如果总数为0不显示也可以。不过当总数都是0，我们显示均匀的或者空的
                                    title: totalBytes > 0 ? '${encryptedPercentage.toStringAsFixed(1)}%' : '0%',
                                    radius: 60,
                                    showTitle: totalBytes > 0,
                                    titleStyle: const TextStyle(
                                      fontSize: 14,
                                      fontWeight: FontWeight.bold,
                                      color: Colors.white,
                                    ),
                                  ),
                                  PieChartSectionData(
                                    color: Colors.grey.shade300,
                                    value: unencryptedBytes.toDouble() > 0 ? unencryptedBytes.toDouble() : (totalBytes == 0 ? 1 : 0),
                                    title: totalBytes > 0 ? '${unencryptedPercentage.toStringAsFixed(1)}%' : '0%',
                                    radius: 60,
                                    showTitle: totalBytes > 0,
                                    titleStyle: const TextStyle(
                                      fontSize: 14,
                                      fontWeight: FontWeight.bold,
                                      color: Colors.black54,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                          const SizedBox(height: 24),
                          Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              _Indicator(
                                color: Colors.blueAccent,
                                text: '已加密',
                                subtext: statsService.formatBytes(encryptedBytes),
                              ),
                              const SizedBox(width: 32),
                              _Indicator(
                                color: Colors.grey.shade300,
                                text: '未加密',
                                subtext: statsService.formatBytes(unencryptedBytes),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 16),
              const Expanded(
                flex: 1,
                child: SizedBox(), // 右侧为空
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Indicator extends StatelessWidget {
  final Color color;
  final String text;
  final String subtext;

  const _Indicator({
    required this.color,
    required this.text,
    required this.subtext,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        Container(
          width: 16,
          height: 16,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: color,
          ),
        ),
        const SizedBox(width: 8),
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              text,
              style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 4),
            Text(
              subtext,
              style: const TextStyle(fontSize: 12, color: Colors.grey),
            ),
          ],
        )
      ],
    );
  }
}
