import 'dart:math';
import 'package:camera/camera.dart';

/// Processes raw camera frames to extract a PPG signal and detect heartbeat peaks.
///
/// Pipeline:
///   raw frame → red-channel mean → bandpass filter → peak detection → RR intervals
class PpgProcessor {
  static const int _smoothWindow = 5;     // short moving avg (noise suppression)
  static const int _baselineWindow = 90;  // long moving avg (DC drift removal)
  static const int _minPeakDistanceSamples = 9; // ~300 ms at 30 fps → 200 bpm max
  static const double _peakThreshold = 0.4; // fraction of rolling amplitude

  final List<double> _raw = [];
  final List<double> _filtered = [];
  final List<DateTime> _timestamps = [];
  final List<int> _peakIndices = [];
  final List<double> _rrIntervalsMs = [];

  int get sampleCount => _raw.length;
  List<double> get filtered => List.unmodifiable(_filtered);
  List<double> get rrIntervalsMs => List.unmodifiable(_rrIntervalsMs);

  /// Feed one camera frame. Returns the filtered PPG value for that frame.
  double addFrame(CameraImage image, DateTime timestamp) {
    final raw = _extractRedMean(image);
    _raw.add(raw);
    _timestamps.add(timestamp);

    final filtered = _bandpass(raw);
    _filtered.add(filtered);
    _detectPeaks();
    return filtered;
  }

  void reset() {
    _raw.clear();
    _filtered.clear();
    _timestamps.clear();
    _peakIndices.clear();
    _rrIntervalsMs.clear();
  }

  // ─── Signal extraction ────────────────────────────────────────────────────

  double _extractRedMean(CameraImage image) {
    if (image.format.group == ImageFormatGroup.bgra8888) {
      // iOS: plane 0 is BGRA – red byte is at offset +2
      final bytes = image.planes[0].bytes;
      int sum = 0;
      int count = 0;
      for (int i = 2; i < bytes.length; i += 8) { // stride 8 = sample every 2nd pixel
        sum += bytes[i];
        count++;
      }
      return count > 0 ? sum / count : 0;
    } else {
      // Android: YUV_420_888 – plane 0 is luminance (Y).
      // With the torch on and finger covering the lens, Y ≈ red-channel intensity.
      final bytes = image.planes[0].bytes;
      int sum = 0;
      int count = 0;
      for (int i = 0; i < bytes.length; i += 4) { // sample every 4th pixel
        sum += bytes[i] & 0xFF;
        count++;
      }
      return count > 0 ? sum / count : 0;
    }
  }

  // ─── Bandpass filter ──────────────────────────────────────────────────────

  /// Bandpass by subtracting a long moving average (removes DC + very slow drift)
  /// from a short moving average (removes HF noise). Result is zero-centred.
  double _bandpass(double newValue) {
    if (_raw.isEmpty) return 0;

    final shortStart = max(0, _raw.length - _smoothWindow);
    final shortEnd = _raw.length;
    double shortAvg = 0;
    for (int i = shortStart; i < shortEnd; i++) {
      shortAvg += _raw[i];
    }
    shortAvg /= (shortEnd - shortStart);

    final longStart = max(0, _raw.length - _baselineWindow);
    double longAvg = 0;
    for (int i = longStart; i < shortEnd; i++) {
      longAvg += _raw[i];
    }
    longAvg /= (shortEnd - longStart);

    return shortAvg - longAvg;
  }

  // ─── Peak detection ───────────────────────────────────────────────────────

  void _detectPeaks() {
    final n = _filtered.length;
    if (n < _minPeakDistanceSamples + 2) return;

    final i = n - _minPeakDistanceSamples - 1; // check candidate at this index

    // Must be higher than neighbours within the min-distance window
    final candidate = _filtered[i];
    bool isLocalMax = true;
    for (int j = max(0, i - _minPeakDistanceSamples);
        j <= min(n - 1, i + _minPeakDistanceSamples);
        j++) {
      if (j != i && _filtered[j] >= candidate) {
        isLocalMax = false;
        break;
      }
    }
    if (!isLocalMax) return;

    // Rolling amplitude threshold
    final recentStart = max(0, i - _baselineWindow);
    double maxVal = _filtered[recentStart];
    double minVal = _filtered[recentStart];
    for (int j = recentStart + 1; j <= i; j++) {
      if (_filtered[j] > maxVal) maxVal = _filtered[j];
      if (_filtered[j] < minVal) minVal = _filtered[j];
    }
    final amplitude = maxVal - minVal;
    if (amplitude < 0.0001) return; // flat signal – no finger
    if (candidate < minVal + amplitude * _peakThreshold) return;

    // Enforce minimum distance to last peak
    if (_peakIndices.isNotEmpty && i - _peakIndices.last < _minPeakDistanceSamples) return;

    _peakIndices.add(i);

    if (_peakIndices.length >= 2) {
      final prev = _peakIndices[_peakIndices.length - 2];
      final curr = _peakIndices.last;
      final dt = _timestamps[curr].difference(_timestamps[prev]).inMicroseconds / 1000.0;
      // Sanity check: HR between 30 and 220 bpm
      if (dt > 270 && dt < 2000) {
        _rrIntervalsMs.add(dt);
      }
    }
  }

  // ─── Derived metrics ──────────────────────────────────────────────────────

  /// Most recent heart rate estimate in BPM, or null if insufficient data.
  double? get currentBpm {
    if (_rrIntervalsMs.length < 3) return null;
    final recent = _rrIntervalsMs.sublist(max(0, _rrIntervalsMs.length - 8));
    final meanRr = recent.reduce((a, b) => a + b) / recent.length;
    return 60000 / meanRr;
  }

  /// Elapsed recording time in seconds.
  double get elapsedSeconds {
    if (_timestamps.length < 2) return 0;
    return _timestamps.last.difference(_timestamps.first).inMilliseconds / 1000.0;
  }

  /// True once there is enough signal to compute a coherence score.
  bool get hasEnoughData => _rrIntervalsMs.length >= 30; // ~30 beats ≈ ~30 s min
}
