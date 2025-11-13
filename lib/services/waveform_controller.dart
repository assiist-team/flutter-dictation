import 'package:flutter/foundation.dart';

/// Controller for managing waveform visualization data.
/// Bridges between native audio levels and waveform widget.
class WaveformController extends ChangeNotifier {
  double _currentLevel = 0.0;
  final List<double> _waveformData = [];
  static const int maxSamples = 100; // Keep last 100 samples

  /// Current audio level (0.0 - 1.0)
  double get currentLevel => _currentLevel;

  /// List of recent audio level samples for waveform visualization
  List<double> get waveformData => List.unmodifiable(_waveformData);

  /// Update the current audio level.
  /// [level] should be between 0.0 and 1.0
  void updateLevel(double level) {
    _currentLevel = level.clamp(0.0, 1.0);
    _waveformData.add(_currentLevel);

    // Keep only recent samples
    if (_waveformData.length > maxSamples) {
      _waveformData.removeAt(0);
    }

    notifyListeners();
  }

  /// Reset the waveform data.
  void reset() {
    _currentLevel = 0.0;
    _waveformData.clear();
    notifyListeners();
  }
}

