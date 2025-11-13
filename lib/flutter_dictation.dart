/// Flutter Dictation Module
/// 
/// A reusable module for voice dictation with native iOS implementation
/// providing low-latency speech recognition and waveform visualization.
/// 
/// Example usage:
/// ```dart
/// import 'package:flutter_dictation/flutter_dictation.dart';
/// 
/// // Initialize the native dictation service
/// final dictationService = NativeDictationService();
/// final waveformController = WaveformController();
/// await dictationService.initialize();
/// 
/// // Start listening
/// await dictationService.startListening(
///   onResult: (text, isFinal) {
///     // Handle speech results
///   },
///   onStatus: (status) {
///     // Handle status updates
///   },
///   onAudioLevel: (level) {
///     waveformController.updateLevel(level);
///   },
/// );
/// 
/// // Use AudioControlsDecorator to wrap your text field
/// AudioControlsDecorator(
///   isListening: isListening,
///   elapsedTime: elapsedTime,
///   waveformController: waveformController,
///   onMicPressed: _handleMicPressed,
///   onCancelPressed: _cancelListening,
///   child: CupertinoTextField(...),
/// )
/// ```
library flutter_dictation;

export 'widgets/audio_controls_decorator.dart';
export 'services/native_dictation_service.dart';
export 'services/waveform_controller.dart';
export 'widgets/native_waveform.dart';
export 'widgets/waveform_painter.dart';
export 'theme/dictation_styles.dart';
