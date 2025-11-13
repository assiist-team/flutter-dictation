import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import '../services/waveform_controller.dart';
import 'waveform_painter.dart';

/// Widget for displaying real-time waveform visualization from native audio levels.
class NativeWaveform extends StatelessWidget {
  final WaveformController controller;
  final double height;
  final Color color;

  const NativeWaveform({
    super.key,
    required this.controller,
    this.height = 40.0,
    this.color = CupertinoColors.systemBlue,
  });

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: controller,
      builder: (context, child) {
        return CustomPaint(
          size: Size(double.infinity, height),
          painter: WaveformPainter(
            levels: controller.waveformData,
            color: color,
          ),
        );
      },
    );
  }
}

