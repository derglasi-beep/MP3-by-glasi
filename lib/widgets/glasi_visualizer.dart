import 'dart:math';
import 'package:flutter/material.dart';

class GlasiVisualizer extends StatefulWidget {
  final bool playing;
  final double? bpm;
  const GlasiVisualizer({super.key, required this.playing, this.bpm});

  @override
  State<GlasiVisualizer> createState() => _GlasiVisualizerState();
}

class _GlasiVisualizerState extends State<GlasiVisualizer>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
    )..repeat();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 74,
      width: double.infinity,
      child: CustomPaint(
        painter: _VisualizerPainter(
          animation: _controller,
          playing: widget.playing,
          bpm: widget.bpm,
          color: Theme.of(context).colorScheme.primary,
        ),
      ),
    );
  }
}

class _VisualizerPainter extends CustomPainter {
  final Animation<double> animation;
  final bool playing;
  final double? bpm;
  final Color color;

  _VisualizerPainter({
    required this.animation,
    required this.playing,
    required this.bpm,
    required this.color,
  }) : super(repaint: animation);

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()..style = PaintingStyle.fill;
    const bars = 32;
    final gap = 3.0;
    final barWidth = max(2.0, (size.width - gap * (bars - 1)) / bars);

    final beatHz = (bpm ?? 120) / 60;
    final pulse = playing
        ? (0.72 + 0.28 * sin(animation.value * 2 * pi * beatHz))
        : 0.18;

    for (var i = 0; i < bars; i++) {
      final x = i * (barWidth + gap);
      final center = (bars - 1) / 2;
      final distance = (i - center).abs() / center;
      final envelope = 1 - distance * 0.72;
      final wave = 0.55 + 0.45 * sin(
        animation.value * 2 * pi + i * 0.52,
      );
      final height = size.height * 0.12 +
          size.height * 0.72 * envelope * (0.35 + wave * 0.65) * pulse;

      paint.color = color.withValues(alpha: 0.35 + envelope * 0.65);
      final rect = RRect.fromRectAndRadius(
        Rect.fromLTWH(
          x,
          (size.height - height) / 2,
          barWidth,
          height,
        ),
        const Radius.circular(4),
      );
      canvas.drawRRect(rect, paint);
    }
  }

  @override
  bool shouldRepaint(covariant _VisualizerPainter oldDelegate) =>
      oldDelegate.playing != playing ||
      oldDelegate.bpm != bpm ||
      oldDelegate.color != color;
}
