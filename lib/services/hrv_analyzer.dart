import 'dart:math';

/// HRV metrics and cardiac coherence score derived from a list of RR intervals (ms).
class HrvAnalyzer {
  // Frequency band boundaries (Hz)
  static const double _vlfLow  = 0.003;
  static const double _lfLow   = 0.04;
  static const double _lfHigh  = 0.15;
  static const double _hfHigh  = 0.40;

  // Resampling rate for evenly-spaced RR signal (Hz)
  static const double _resampleRate = 4.0;

  final List<double> rrMs;

  const HrvAnalyzer(this.rrMs);

  // ─── Time-domain metrics ──────────────────────────────────────────────────

  double get meanRrMs {
    if (rrMs.isEmpty) return 0;
    return rrMs.reduce((a, b) => a + b) / rrMs.length;
  }

  double get meanBpm => meanRrMs > 0 ? 60000 / meanRrMs : 0;

  /// SDNN – standard deviation of NN intervals.
  double get sdnn {
    if (rrMs.length < 2) return 0;
    final mean = meanRrMs;
    final variance = rrMs.map((r) => pow(r - mean, 2)).reduce((a, b) => a + b) / rrMs.length;
    return sqrt(variance);
  }

  /// RMSSD – root mean square of successive differences.
  double get rmssd {
    if (rrMs.length < 2) return 0;
    double sumSq = 0;
    for (int i = 1; i < rrMs.length; i++) {
      final diff = rrMs[i] - rrMs[i - 1];
      sumSq += diff * diff;
    }
    return sqrt(sumSq / (rrMs.length - 1));
  }

  // ─── Frequency-domain & coherence ────────────────────────────────────────

  /// Full frequency analysis result.
  HrvFrequencyResult get frequencyAnalysis {
    final signal = _resample();
    if (signal.length < 16) return HrvFrequencyResult.empty();

    final psd = _computePsd(signal, _resampleRate);
    final freqs = psd.frequencies;
    final powers = psd.powers;

    double totalPower = 0;
    double lfPower = 0;
    double hfPower = 0;
    double lfPeakPower = 0;
    double lfPeakFreq = 0;

    for (int i = 0; i < freqs.length; i++) {
      final f = freqs[i];
      final p = powers[i];
      if (f >= _vlfLow && f <= _hfHigh) totalPower += p;
      if (f >= _lfLow  && f <= _lfHigh) {
        lfPower += p;
        if (p > lfPeakPower) {
          lfPeakPower = p;
          lfPeakFreq = f;
        }
      }
      if (f > _lfHigh && f <= _hfHigh) hfPower += p;
    }

    final lfHfRatio = hfPower > 0 ? lfPower / hfPower : 0;

    // Coherence ratio: dominant LF peak power / total spectral power.
    // A fully coherent state (resonance at ~0.1 Hz) drives this toward 0.5-0.6.
    final coherenceRatio = totalPower > 0 ? lfPeakPower / totalPower : 0;
    final coherenceScore = (coherenceRatio / 0.6 * 100).clamp(0, 100).toDouble();

    return HrvFrequencyResult(
      totalPower: totalPower,
      lfPower: lfPower,
      hfPower: hfPower,
      lfHfRatio: lfHfRatio,
      lfPeakFreq: lfPeakFreq,
      coherenceRatio: coherenceRatio,
      coherenceScore: coherenceScore,
      frequencies: freqs,
      powers: powers,
    );
  }

  // ─── Internal helpers ─────────────────────────────────────────────────────

  /// Linearly resample unevenly-spaced RR intervals to an evenly-spaced signal.
  List<double> _resample() {
    if (rrMs.length < 4) return [];

    // Build cumulative time axis (seconds) for each RR interval endpoint
    final times = <double>[0];
    for (final rr in rrMs) {
      times.add(times.last + rr / 1000.0);
    }
    final totalDuration = times.last;
    final nSamples = (totalDuration * _resampleRate).floor();
    if (nSamples < 8) return [];

    final resampled = List<double>.filled(nSamples, 0);
    int j = 0;
    for (int i = 0; i < nSamples; i++) {
      final t = i / _resampleRate;
      while (j < times.length - 2 && times[j + 1] < t) {
        j++;
      }
      final t0 = times[j];
      final t1 = times[j + 1];
      final frac = t1 > t0 ? (t - t0) / (t1 - t0) : 0.0;
      resampled[i] = rrMs[j] + frac * (rrMs[min(j + 1, rrMs.length - 1)] - rrMs[j]);
    }

    // Detrend (subtract mean)
    final mean = resampled.reduce((a, b) => a + b) / resampled.length;
    return resampled.map((v) => v - mean).toList();
  }

  /// Power spectral density via DFT with Hann window.
  _PsdResult _computePsd(List<double> signal, double sampleRate) {
    final n = signal.length;

    // Apply Hann window
    final windowed = List<double>.generate(n, (i) {
      final w = 0.5 * (1 - cos(2 * pi * i / (n - 1)));
      return signal[i] * w;
    });

    // Compute one-sided DFT (O(n²) – acceptable for n ≤ ~600)
    final half = n ~/ 2 + 1;
    final freqs  = List<double>.filled(half, 0);
    final powers = List<double>.filled(half, 0);

    for (int k = 0; k < half; k++) {
      double real = 0, imag = 0;
      final angle = 2 * pi * k / n;
      for (int t = 0; t < n; t++) {
        real += windowed[t] * cos(angle * t);
        imag -= windowed[t] * sin(angle * t);
      }
      freqs[k]  = k * sampleRate / n;
      // Normalise and double (one-sided) except DC and Nyquist
      powers[k] = (real * real + imag * imag) / (n * n);
      if (k > 0 && k < half - 1) powers[k] *= 2;
    }

    return _PsdResult(freqs, powers);
  }
}

// ─── Data containers ─────────────────────────────────────────────────────────

class HrvFrequencyResult {
  final double totalPower;
  final double lfPower;
  final double hfPower;
  final double lfHfRatio;
  final double lfPeakFreq;
  final double coherenceRatio;
  final double coherenceScore; // 0–100
  final List<double> frequencies;
  final List<double> powers;

  const HrvFrequencyResult({
    required this.totalPower,
    required this.lfPower,
    required this.hfPower,
    required this.lfHfRatio,
    required this.lfPeakFreq,
    required this.coherenceRatio,
    required this.coherenceScore,
    required this.frequencies,
    required this.powers,
  });

  factory HrvFrequencyResult.empty() => const HrvFrequencyResult(
        totalPower: 0,
        lfPower: 0,
        hfPower: 0,
        lfHfRatio: 0,
        lfPeakFreq: 0,
        coherenceRatio: 0,
        coherenceScore: 0,
        frequencies: [],
        powers: [],
      );

  CoherenceLevel get coherenceLevel {
    if (coherenceScore >= 67) return CoherenceLevel.high;
    if (coherenceScore >= 33) return CoherenceLevel.medium;
    return CoherenceLevel.low;
  }

  bool get isEmpty => totalPower == 0;
}

enum CoherenceLevel { low, medium, high }

extension CoherenceLevelExt on CoherenceLevel {
  String get label {
    switch (this) {
      case CoherenceLevel.low:    return 'Low';
      case CoherenceLevel.medium: return 'Medium';
      case CoherenceLevel.high:   return 'High';
    }
  }
}

class _PsdResult {
  final List<double> frequencies;
  final List<double> powers;
  const _PsdResult(this.frequencies, this.powers);
}
