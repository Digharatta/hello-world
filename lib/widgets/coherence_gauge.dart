import 'dart:math';
import 'package:flutter/material.dart';
import '../services/hrv_analyzer.dart';

/// Circular arc gauge displaying the cardiac coherence score (0–100).
class CoherenceGauge extends StatelessWidget {
  final double score;     // 0–100
  final double size;

  const CoherenceGauge({super.key, required this.score, this.size = 200});

  @override
  Widget build(BuildContext context) {
    final level = _levelFor(score);
    return SizedBox(
      width: size,
      height: size,
      child: CustomPaint(
        painter: _GaugePainter(score: score, level: level),
        child: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                score.toStringAsFixed(0),
                style: TextStyle(
                  fontSize: size * 0.22,
                  fontWeight: FontWeight.bold,
                  color: _colorFor(level),
                ),
              ),
              Text(
                level.label,
                style: TextStyle(
                  fontSize: size * 0.09,
                  color: _colorFor(level).withAlpha(204),
                  letterSpacing: 1.2,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  CoherenceLevel _levelFor(double s) {
    if (s >= 67) return CoherenceLevel.high;
    if (s >= 33) return CoherenceLevel.medium;
    return CoherenceLevel.low;
  }

  Color _colorFor(CoherenceLevel l) {
    switch (l) {
      case CoherenceLevel.high:   return const Color(0xFF4CAF50);
      case CoherenceLevel.medium: return const Color(0xFFFFB300);
      case CoherenceLevel.low:    return const Color(0xFFEF5350);
    }
  }
}

class _GaugePainter extends CustomPainter {
  final double score;
  final CoherenceLevel level;

  _GaugePainter({required this.score, required this.level});

  static const double _startAngle = 135 * pi / 180;
  static const double _sweepTotal = 270 * pi / 180;

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = size.width * 0.42;
    final strokeWidth = size.width * 0.08;

    final trackPaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth
      ..strokeCap = StrokeCap.round
      ..color = Colors.white12;

    canvas.drawArc(
      Rect.fromCircle(center: center, radius: radius),
      _startAngle,
      _sweepTotal,
      false,
      trackPaint,
    );

    final fill = score.clamp(0, 100) / 100.0;
    if (fill > 0) {
      final arcPaint = Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = strokeWidth
        ..strokeCap = StrokeCap.round
        ..shader = SweepGradient(
          startAngle: _startAngle,
          endAngle: _startAngle + _sweepTotal * fill,
          colors: [_colorFor(level).withAlpha(180), _colorFor(level)],
        ).createShader(Rect.fromCircle(center: center, radius: radius));

      canvas.drawArc(
        Rect.fromCircle(center: center, radius: radius),
        _startAngle,
        _sweepTotal * fill,
        false,
        arcPaint,
      );
    }
  }

  @override
  bool shouldRepaint(_GaugePainter old) => old.score != score;

  Color _colorFor(CoherenceLevel l) {
    switch (l) {
      case CoherenceLevel.high:   return const Color(0xFF4CAF50);
      case CoherenceLevel.medium: return const Color(0xFFFFB300);
      case CoherenceLevel.low:    return const Color(0xFFEF5350);
    }
  }
}
