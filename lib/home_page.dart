import 'package:flutter/material.dart';
import 'package:fl_chart/fl_chart.dart';

class HomePage extends StatelessWidget {
  const HomePage({super.key});

  String formatBytes(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    if (bytes < 1024 * 1024 * 1024) return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
    return '${(bytes / (1024 * 1024 * 1024)).toStringAsFixed(1)} GB';
  }

  @override
  Widget build(BuildContext context) {
    final int encryptedBytes = 500 * 1024 * 1024;
    final int unencryptedBytes = 1500 * 1024 * 1024;
    final int totalBytes = encryptedBytes + unencryptedBytes;

    final double encryptedPercentage = totalBytes > 0 ? (encryptedBytes / totalBytes) * 100 : 0;
    final double unencryptedPercentage = totalBytes > 0 ? (unencryptedBytes / totalBytes) * 100 : 0;

    final double screenWidth = MediaQuery.of(context).size.width;

    return Center(
      child: SizedBox(
        width: screenWidth / 2,
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
                  SizedBox(
                    height: 250,
                    child: PieChart(
                      PieChartData(
                        sectionsSpace: 2,
                        centerSpaceRadius: 50,
                        sections: [
                          PieChartSectionData(
                            color: Colors.blueAccent,
                            value: encryptedBytes.toDouble(),
                            title: '${encryptedPercentage.toStringAsFixed(1)}%',
                            radius: 60,
                            titleStyle: const TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.bold,
                              color: Colors.white,
                            ),
                          ),
                          PieChartSectionData(
                            color: Colors.grey.shade300,
                            value: unencryptedBytes.toDouble(),
                            title: '${unencryptedPercentage.toStringAsFixed(1)}%',
                            radius: 60,
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
                        subtext: formatBytes(encryptedBytes),
                      ),
                      const SizedBox(width: 32),
                      _Indicator(
                        color: Colors.grey.shade300,
                        text: '未加密',
                        subtext: formatBytes(unencryptedBytes),
                      ),
                    ],
                  ),
                ],
              ),
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
