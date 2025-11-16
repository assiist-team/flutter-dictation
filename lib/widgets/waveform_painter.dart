import 'dart:math' as math;
import 'package:flutter/material.dart';

/// Custom painter for drawing waveform visualization from audio level data.
/// Styled to be smooth and less aggressive, similar to ChatGPT's waveform.
class WaveformPainter extends CustomPainter {
  final List<double> levels;
  final Color color;

  WaveformPainter({required this.levels, required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    if (levels.isEmpty) return;

    final paint =
        Paint()
          ..color = color
          ..style = PaintingStyle.fill;

    // Fixed number of bars for consistent layout (like ChatGPT)
    // Always show 50 bars regardless of data length
    final int visibleBars = 50;
    final barSpacing = 2.0; // Spacing between bars
    final totalSpacing = barSpacing * (visibleBars - 1);
    final availableWidth = size.width - totalSpacing;
    final barWidth = availableWidth / visibleBars;
    final centerY = size.height / 2;

    // Maximum bar height as percentage of available height (less aggressive)
    final maxBarHeightRatio = 0.9;
    // Minimum bar height for visual feedback even at low volumes
    final minBarHeight = 2.0;
    const amplitudeShapeExponent = 1.25;

    // Show the most recent `visibleBars` samples (right-aligned)
    final startIndex = math.max(0, levels.length - visibleBars);

    for (int i = 0; i < visibleBars; i++) {
      final sourceIndex = startIndex + i;
      final level = levels[sourceIndex].clamp(0.0, 1.0);

      // Shape levels with a convex curve so high amplitudes don't look flat.
      final shapedLevel = math.pow(level, amplitudeShapeExponent).toDouble();
      // Blend a little of the raw level back in to keep quieter speech visible.
      final blendedLevel = (shapedLevel * 0.85) + (level * 0.15);

      // Calculate bar height with max ratio and minimum height
      final barHeight = math.max(
        minBarHeight,
        blendedLevel * size.height * maxBarHeightRatio,
      );

      final x = i * (barWidth + barSpacing);

      // Draw bar centered vertically
      final rect = Rect.fromLTWH(
        x,
        centerY - barHeight / 2,
        barWidth,
        barHeight,
      );

      // More rounded corners for smoother appearance
      canvas.drawRRect(
        RRect.fromRectAndRadius(rect, Radius.circular(barWidth / 2)),
        paint,
      );
    }
  }

  @override
  bool shouldRepaint(WaveformPainter oldDelegate) {
    // Since buffer is now fixed-size, length won't change
    // Only repaint if color changes or data changes
    return oldDelegate.color != color ||
        (levels.isNotEmpty &&
            oldDelegate.levels.isNotEmpty &&
            oldDelegate.levels.last != levels.last);
  }
}
