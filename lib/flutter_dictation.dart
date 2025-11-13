/// Flutter Dictation Module
/// 
/// A reusable module for voice dictation with waveform visualization.
/// 
/// Example usage:
/// ```dart
/// import 'package:flutter_dictation/flutter_dictation.dart';
/// 
/// // Use AudioControlsDecorator to wrap your text field
/// AudioControlsDecorator(
///   isListening: isListening,
///   elapsedTime: elapsedTime,
///   recorderController: recorderController,
///   onMicPressed: _handleMicPressed,
///   onCancelPressed: _cancelListening,
///   child: CupertinoTextField(...),
/// )
/// ```
library flutter_dictation;

export 'widgets/audio_controls_decorator.dart';
export 'services/audio_service.dart';
export 'services/native_dictation_service.dart';
export 'services/waveform_controller.dart';
export 'widgets/native_waveform.dart';
export 'widgets/waveform_painter.dart';
export 'theme/dictation_styles.dart';
