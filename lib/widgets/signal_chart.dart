import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';

/// Scrolling real-time PPG waveform chart.
class SignalChart extends StatelessWidget {
  final List<double> samples;
  final int windowSize; // number of samples to display

  const SignalChart({
    super.key,
    required this.samples,
    this.windowSize = 120,
  });

  @override
  Widget build(BuildContext context) {
    final visible = samples.length > windowSize
        ? samples.sublist(samples.length - windowSize)
        : samples;

    if (visible.isEmpty) {
      return const Center(
        child: Text(
          'Place your finger on the camera lens',
          style: TextStyle(color: Colors.white54),
        ),
      );
    }

    double minY = visible.reduce((a, b) => a < b ? a : b);
    double maxY = visible.reduce((a, b) => a > b ? a : b);
    final range = maxY - minY;
    if (range < 0.001) {
      minY -= 1;
      maxY += 1;
    } else {
      minY -= range * 0.1;
      maxY += range * 0.1;
    }

    final spots = List.generate(
      visible.length,
      (i) => FlSpot(i.toDouble(), visible[i]),
    );

    return LineChart(
      LineChartData(
        minX: 0,
        maxX: (windowSize - 1).toDouble(),
        minY: minY,
        maxY: maxY,
        clipData: const FlClipData.all(),
        gridData: const FlGridData(show: false),
        borderData: FlBorderData(show: false),
        titlesData: const FlTitlesData(show: false),
        lineBarsData: [
          LineChartBarData(
            spots: spots,
            isCurved: true,
            curveSmoothness: 0.2,
            color: const Color(0xFF4CAF50),
            barWidth: 2,
            dotData: const FlDotData(show: false),
            belowBarData: BarAreaData(
              show: true,
              gradient: LinearGradient(
                colors: [
                  const Color(0xFF4CAF50).withAlpha(77),
                  const Color(0xFF4CAF50).withAlpha(0),
                ],
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
              ),
            ),
          ),
        ],
      ),
      duration: Duration.zero,
    );
  }
}
