import 'dart:collection';

import 'package:flutter/foundation.dart';

/// Controller for managing waveform visualization data.
/// Bridges between native audio levels and waveform widget.
/// Maintains a fixed-size, pre-filled buffer so bars appear immediately
/// and slide left as new data arrives (ChatGPT-style behavior).
class WaveformController extends ChangeNotifier {
  double _currentLevel = 0.0;
  static const int maxSamples = 100; // Fixed buffer size
  final ListQueue<double> _waveformData = ListQueue<double>(maxSamples);

  WaveformController() {
    // Pre-fill with zeros so layout is stable before audio arrives.
    for (int i = 0; i < maxSamples; i++) {
      _waveformData.addLast(0.0);
    }
  }

  /// Current audio level (0.0 - 1.0)
  double get currentLevel => _currentLevel;

  /// List of recent audio level samples for waveform visualization.
  /// Always returns a fixed-size snapshot of the queue.
  List<double> get waveformData => List<double>.unmodifiable(_waveformData);

  /// Update the current audio level.
  /// [level] should be between 0.0 and 1.0.
  /// Removes the oldest sample and appends the new one to keep a sliding window.
  void updateLevel(double level) {
    _currentLevel = level.clamp(0.0, 1.0);

    if (_waveformData.length == maxSamples) {
      _waveformData.removeFirst();
    }
    _waveformData.addLast(_currentLevel);

    notifyListeners();
  }

  /// Reset the waveform data back to zeroed bars.
  void reset() {
    _currentLevel = 0.0;
    _waveformData
      ..clear()
      ..addAll(List<double>.filled(maxSamples, 0.0));
    notifyListeners();
  }
}

