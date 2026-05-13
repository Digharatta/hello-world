import 'dart:async';
import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:wakelock_plus/wakelock_plus.dart';
import '../services/ppg_processor.dart';
import '../services/hrv_analyzer.dart';
import '../widgets/signal_chart.dart';
import '../widgets/coherence_gauge.dart';
import 'results_screen.dart';

const Duration _sessionDuration = Duration(minutes: 2);

class MeasurementScreen extends StatefulWidget {
  const MeasurementScreen({super.key});

  @override
  State<MeasurementScreen> createState() => _MeasurementScreenState();
}

class _MeasurementScreenState extends State<MeasurementScreen> {
  CameraController? _controller;
  final PpgProcessor _ppg = PpgProcessor();

  bool _cameraReady = false;
  bool _measuring = false;
  String? _errorMessage;

  // Live display values (updated by timer, not on every frame)
  double _bpm = 0;
  double _coherenceScore = 0;
  double _elapsed = 0;
  List<double> _chartSamples = [];

  Timer? _uiTimer;
  DateTime? _sessionStart;

  @override
  void initState() {
    super.initState();
    SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);
    WakelockPlus.enable();
    _initCamera();
  }

  @override
  void dispose() {
    _uiTimer?.cancel();
    _controller?.stopImageStream();
    _controller?.dispose();
    WakelockPlus.disable();
    super.dispose();
  }

  // ─── Camera init ──────────────────────────────────────────────────────────

  Future<void> _initCamera() async {
    final cameras = await availableCameras();
    final rear = cameras.firstWhere(
      (c) => c.lensDirection == CameraLensDirection.back,
      orElse: () => cameras.first,
    );

    _controller = CameraController(
      rear,
      ResolutionPreset.low, // small frames → lower CPU load
      enableAudio: false,
      imageFormatGroup: ImageFormatGroup.bgra8888,
    );

    try {
      await _controller!.initialize();
      await _controller!.setFlashMode(FlashMode.torch);
      setState(() => _cameraReady = true);
      _startMeasurement();
    } on CameraException catch (e) {
      setState(() => _errorMessage = 'Camera error: ${e.description}');
    }
  }

  // ─── Measurement lifecycle ────────────────────────────────────────────────

  void _startMeasurement() {
    _ppg.reset();
    _sessionStart = DateTime.now();
    _measuring = true;

    _controller!.startImageStream((image) {
      if (!_measuring) return;
      _ppg.addFrame(image, DateTime.now());
    });

    _uiTimer = Timer.periodic(const Duration(milliseconds: 500), _onTick);
  }

  void _onTick(Timer _) {
    if (!mounted) return;
    final elapsed = _ppg.elapsedSeconds;

    // Update coherence every 2 seconds once enough data exists
    double coherence = _coherenceScore;
    if (_ppg.hasEnoughData) {
      final result = HrvAnalyzer(_ppg.rrIntervalsMs).frequencyAnalysis;
      if (!result.isEmpty) coherence = result.coherenceScore;
    }

    setState(() {
      _elapsed = elapsed;
      _bpm = _ppg.currentBpm ?? _bpm;
      _coherenceScore = coherence;
      _chartSamples = List.of(_ppg.filtered);
    });

    if (elapsed >= _sessionDuration.inSeconds) {
      _finishMeasurement();
    }
  }

  Future<void> _finishMeasurement() async {
    _measuring = false;
    _uiTimer?.cancel();
    await _controller?.stopImageStream();
    await _controller?.setFlashMode(FlashMode.off);

    if (!mounted) return;
    final analyzer = HrvAnalyzer(_ppg.rrIntervalsMs);
    Navigator.of(context).pushReplacement(
      MaterialPageRoute(
        builder: (_) => ResultsScreen(analyzer: analyzer),
      ),
    );
  }

  void _cancelMeasurement() {
    _measuring = false;
    _uiTimer?.cancel();
    _controller?.stopImageStream();
    _controller?.setFlashMode(FlashMode.off);
    Navigator.of(context).pop();
  }

  // ─── UI ───────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    if (_errorMessage != null) return _errorView();
    if (!_cameraReady) return _loadingView();
    return _measurementView();
  }

  Widget _loadingView() => Scaffold(
        body: const Center(child: CircularProgressIndicator()),
        appBar: AppBar(
          leading: BackButton(onPressed: () => Navigator.of(context).pop()),
        ),
      );

  Widget _errorView() => Scaffold(
        appBar: AppBar(title: const Text('Error')),
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Text(_errorMessage ?? 'Unknown error'),
          ),
        ),
      );

  Widget _measurementView() {
    final progress = (_elapsed / _sessionDuration.inSeconds).clamp(0.0, 1.0);
    final remaining = (_sessionDuration.inSeconds - _elapsed).clamp(0.0, double.infinity);
    final mm = (remaining ~/ 60).toString().padLeft(2, '0');
    final ss = (remaining % 60).toStringAsFixed(0).padLeft(2, '0');

    return Scaffold(
      appBar: AppBar(
        title: const Text('Measuring'),
        leading: IconButton(
          icon: const Icon(Icons.close),
          onPressed: _cancelMeasurement,
        ),
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20),
          child: Column(
            children: [
              const SizedBox(height: 16),

              // Progress bar + timer
              Row(
                children: [
                  Expanded(
                    child: LinearProgressIndicator(
                      value: progress,
                      minHeight: 6,
                      borderRadius: BorderRadius.circular(4),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Text(
                    '$mm:$ss',
                    style: const TextStyle(
                        fontFeatures: [FontFeature.tabularFigures()]),
                  ),
                ],
              ),
              const SizedBox(height: 24),

              // BPM
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.baseline,
                textBaseline: TextBaseline.alphabetic,
                children: [
                  Text(
                    _bpm > 0 ? _bpm.toStringAsFixed(0) : '--',
                    style: const TextStyle(
                        fontSize: 64, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(width: 6),
                  const Text('bpm', style: TextStyle(color: Colors.white54)),
                ],
              ),
              const SizedBox(height: 8),

              // PPG chart
              SizedBox(
                height: 130,
                child: SignalChart(samples: _chartSamples),
              ),
              const SizedBox(height: 24),

              // Coherence gauge (shown once data arrives)
              if (_ppg.hasEnoughData) ...[
                const Text(
                  'COHERENCE',
                  style: TextStyle(
                      letterSpacing: 2, fontSize: 12, color: Colors.white54),
                ),
                const SizedBox(height: 12),
                CoherenceGauge(score: _coherenceScore, size: 160),
              ] else
                Column(
                  children: [
                    const Icon(Icons.fingerprint, size: 48, color: Colors.white24),
                    const SizedBox(height: 8),
                    Text(
                      _ppg.rrIntervalsMs.length < 5
                          ? 'Detecting pulse…'
                          : 'Collecting data… (${_ppg.rrIntervalsMs.length} beats)',
                      style: const TextStyle(color: Colors.white38),
                    ),
                  ],
                ),

              const Spacer(),
              FilledButton.tonal(
                onPressed: _ppg.hasEnoughData ? _finishMeasurement : null,
                child: const Text('Finish Early'),
              ),
              const SizedBox(height: 20),
            ],
          ),
        ),
      ),
    );
  }
}
