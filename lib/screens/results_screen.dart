import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import '../services/hrv_analyzer.dart';
import '../widgets/coherence_gauge.dart';

class ResultsScreen extends StatelessWidget {
  final HrvAnalyzer analyzer;

  const ResultsScreen({super.key, required this.analyzer});

  @override
  Widget build(BuildContext context) {
    final freq = analyzer.frequencyAnalysis;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Results'),
        leading: IconButton(
          icon: const Icon(Icons.home),
          onPressed: () => Navigator.of(context).popUntil((r) => r.isFirst),
        ),
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // ── Coherence gauge ──
              Center(child: CoherenceGauge(score: freq.coherenceScore, size: 200)),
              const SizedBox(height: 8),
              Center(
                child: Text(
                  freq.isEmpty
                      ? 'Not enough data for coherence analysis'
                      : 'Cardiac Coherence Score',
                  style: const TextStyle(color: Colors.white54, fontSize: 13),
                ),
              ),
              const SizedBox(height: 32),

              // ── Time-domain metrics ──
              _SectionHeader('Heart Rate Variability'),
              const SizedBox(height: 12),
              Row(
                children: [
                  _MetricCard(
                      label: 'Mean HR', value: '${analyzer.meanBpm.toStringAsFixed(0)} bpm'),
                  const SizedBox(width: 12),
                  _MetricCard(
                      label: 'Mean RR', value: '${analyzer.meanRrMs.toStringAsFixed(0)} ms'),
                ],
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  _MetricCard(
                      label: 'SDNN',
                      value: '${analyzer.sdnn.toStringAsFixed(1)} ms',
                      tooltip: 'Overall HRV – higher is generally healthier'),
                  const SizedBox(width: 12),
                  _MetricCard(
                      label: 'RMSSD',
                      value: '${analyzer.rmssd.toStringAsFixed(1)} ms',
                      tooltip: 'Short-term HRV – reflects parasympathetic tone'),
                ],
              ),
              const SizedBox(height: 32),

              if (!freq.isEmpty) ...[
                // ── Frequency-domain metrics ──
                _SectionHeader('Frequency Domain'),
                const SizedBox(height: 12),
                Row(
                  children: [
                    _MetricCard(
                        label: 'LF Power',
                        value: freq.lfPower.toStringAsExponential(2),
                        tooltip: '0.04–0.15 Hz (sympathetic + parasympathetic)'),
                    const SizedBox(width: 12),
                    _MetricCard(
                        label: 'HF Power',
                        value: freq.hfPower.toStringAsExponential(2),
                        tooltip: '0.15–0.40 Hz (parasympathetic / respiratory)'),
                  ],
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    _MetricCard(
                        label: 'LF/HF Ratio',
                        value: freq.lfHfRatio.toStringAsFixed(2),
                        tooltip: 'Sympathovagal balance indicator'),
                    const SizedBox(width: 12),
                    _MetricCard(
                        label: 'LF Peak',
                        value: '${(freq.lfPeakFreq * 60).toStringAsFixed(1)} cpm',
                        tooltip: 'Dominant respiratory / coherence frequency'),
                  ],
                ),
                const SizedBox(height: 32),

                // ── PSD chart ──
                _SectionHeader('Power Spectral Density'),
                const SizedBox(height: 12),
                _PsdChart(frequencies: freq.frequencies, powers: freq.powers),
                const SizedBox(height: 8),
                const Center(
                  child: Text(
                    'A sharp peak near 0.1 Hz (6 breaths/min) indicates high coherence',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: Colors.white38, fontSize: 11),
                  ),
                ),
                const SizedBox(height: 32),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

// ─── Sub-widgets ──────────────────────────────────────────────────────────────

class _SectionHeader extends StatelessWidget {
  final String title;
  const _SectionHeader(this.title);

  @override
  Widget build(BuildContext context) => Text(
        title.toUpperCase(),
        style: const TextStyle(
            fontSize: 11, letterSpacing: 1.8, color: Colors.white38),
      );
}

class _MetricCard extends StatelessWidget {
  final String label;
  final String value;
  final String? tooltip;

  const _MetricCard({required this.label, required this.value, this.tooltip});

  @override
  Widget build(BuildContext context) {
    Widget card = Expanded(
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Colors.white.withAlpha(13),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: Colors.white12),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(label,
                style:
                    const TextStyle(fontSize: 11, color: Colors.white54)),
            const SizedBox(height: 4),
            Text(value,
                style: const TextStyle(
                    fontSize: 20, fontWeight: FontWeight.bold)),
          ],
        ),
      ),
    );

    return tooltip != null
        ? Tooltip(message: tooltip!, child: card)
        : card;
  }
}

class _PsdChart extends StatelessWidget {
  final List<double> frequencies;
  final List<double> powers;

  const _PsdChart({required this.frequencies, required this.powers});

  @override
  Widget build(BuildContext context) {
    // Show only 0–0.5 Hz range
    final spots = <FlSpot>[];
    for (int i = 0; i < frequencies.length; i++) {
      if (frequencies[i] <= 0.5) {
        spots.add(FlSpot(frequencies[i], powers[i]));
      }
    }
    if (spots.isEmpty) return const SizedBox.shrink();

    final maxPower = spots.map((s) => s.y).reduce((a, b) => a > b ? a : b);

    return SizedBox(
      height: 160,
      child: LineChart(
        LineChartData(
          minX: 0,
          maxX: 0.5,
          minY: 0,
          maxY: maxPower * 1.15,
          clipData: const FlClipData.all(),
          gridData: FlGridData(
            show: true,
            drawVerticalLine: true,
            getDrawingVerticalLine: (v) => FlLine(
              color: Colors.white10,
              strokeWidth: 1,
              dashArray: [4, 4],
            ),
            getDrawingHorizontalLine: (_) =>
                const FlLine(color: Colors.transparent),
            verticalInterval: 0.1,
          ),
          borderData: FlBorderData(show: false),
          titlesData: FlTitlesData(
            bottomTitles: AxisTitles(
              sideTitles: SideTitles(
                showTitles: true,
                interval: 0.1,
                getTitlesWidget: (v, _) => Text(
                  v.toStringAsFixed(1),
                  style:
                      const TextStyle(fontSize: 9, color: Colors.white38),
                ),
              ),
            ),
            leftTitles:
                const AxisTitles(sideTitles: SideTitles(showTitles: false)),
            topTitles:
                const AxisTitles(sideTitles: SideTitles(showTitles: false)),
            rightTitles:
                const AxisTitles(sideTitles: SideTitles(showTitles: false)),
          ),
          lineBarsData: [
            LineChartBarData(
              spots: spots,
              isCurved: true,
              color: const Color(0xFF4CAF50),
              barWidth: 2,
              dotData: const FlDotData(show: false),
              belowBarData: BarAreaData(
                show: true,
                color: const Color(0xFF4CAF50).withAlpha(51),
              ),
            ),
          ],
        ),
        duration: Duration.zero,
      ),
    );
  }
}
