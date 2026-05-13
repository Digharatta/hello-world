import 'package:flutter/material.dart';
import 'measurement_screen.dart';

class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 32),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const SizedBox(height: 60),
              const Icon(Icons.favorite, size: 52, color: Color(0xFF4CAF50)),
              const SizedBox(height: 24),
              Text(
                'Cardiac\nCoherence',
                style: Theme.of(context).textTheme.displaySmall?.copyWith(
                      fontWeight: FontWeight.bold,
                      height: 1.1,
                    ),
              ),
              const SizedBox(height: 16),
              Text(
                'Measure your heart rate variability and coherence score using only your smartphone camera.',
                style: Theme.of(context)
                    .textTheme
                    .bodyLarge
                    ?.copyWith(color: Colors.white60),
              ),
              const SizedBox(height: 48),
              _InstructionRow(
                icon: Icons.camera_rear,
                text: 'Place your fingertip gently over the rear camera and flash.',
              ),
              const SizedBox(height: 16),
              _InstructionRow(
                icon: Icons.timer_outlined,
                text: 'Hold still for 2 minutes. Results update live after ~30 seconds.',
              ),
              const SizedBox(height: 16),
              _InstructionRow(
                icon: Icons.self_improvement,
                text: 'Breathe at 6 breaths per minute to maximise coherence.',
              ),
              const Spacer(),
              SizedBox(
                width: double.infinity,
                child: FilledButton.icon(
                  onPressed: () => _startMeasurement(context),
                  icon: const Icon(Icons.play_arrow),
                  label: const Text('Start Measurement'),
                  style: FilledButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 18),
                    textStyle: const TextStyle(fontSize: 16),
                  ),
                ),
              ),
              const SizedBox(height: 32),
            ],
          ),
        ),
      ),
    );
  }

  void _startMeasurement(BuildContext context) {
    Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => const MeasurementScreen()),
    );
  }
}

class _InstructionRow extends StatelessWidget {
  final IconData icon;
  final String text;

  const _InstructionRow({required this.icon, required this.text});

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, color: const Color(0xFF4CAF50), size: 22),
        const SizedBox(width: 12),
        Expanded(
          child: Text(
            text,
            style: Theme.of(context)
                .textTheme
                .bodyMedium
                ?.copyWith(color: Colors.white70),
          ),
        ),
      ],
    );
  }
}
