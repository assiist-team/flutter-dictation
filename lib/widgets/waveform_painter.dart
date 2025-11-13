import 'package:flutter/material.dart';

/// Custom painter for drawing waveform visualization from audio level data.
class WaveformPainter extends CustomPainter {
  final List<double> levels;
  final Color color;

  WaveformPainter({
    required this.levels,
    required this.color,
  });

  @override
  void paint(Canvas canvas, Size size) {
    if (levels.isEmpty) return;

    final paint = Paint()
      ..color = color
      ..strokeWidth = 2.0
      ..style = PaintingStyle.fill;

    final barWidth = size.width / levels.length;
    final centerY = size.height / 2;

    for (int i = 0; i < levels.length; i++) {
      final level = levels[i];
      final barHeight = level * size.height;
      final x = i * barWidth;

      // Draw bar centered vertically
      final rect = Rect.fromLTWH(
        x,
        centerY - barHeight / 2,
        barWidth - 1,
        barHeight,
      );

      canvas.drawRRect(
        RRect.fromRectAndRadius(rect, const Radius.circular(2)),
        paint,
      );
    }
  }

  @override
  bool shouldRepaint(WaveformPainter oldDelegate) {
    return oldDelegate.levels.length != levels.length ||
        oldDelegate.color != color ||
        (levels.isNotEmpty &&
            oldDelegate.levels.isNotEmpty &&
            oldDelegate.levels.last != levels.last);
  }
}

