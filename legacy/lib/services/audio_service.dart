import 'package:audio_waveforms/audio_waveforms.dart';
import 'package:speech_to_text/speech_to_text.dart';
import 'package:speech_to_text/speech_recognition_result.dart';

/// Service for managing audio recording and speech-to-text functionality.
/// Handles initialization, recording, and cleanup for dictation features.
class AudioService {
  static final AudioService _instance = AudioService._internal();
  factory AudioService() => _instance;
  AudioService._internal();

  final SpeechToText _speechToText = SpeechToText();
  final Map<String, RecorderController> _recorderControllers = {};
  bool _isInitialized = false;
  bool _hasPermission = false;
  Future<void>? _initFuture;

  /// Initialize the audio service (speech recognition and permissions).
  Future<void> initialize() async {
    // If already initialized, return immediately
    if (_isInitialized) return;

    // If initialization is in progress, wait for it
    if (_initFuture != null) {
      await _initFuture;
      return;
    }

    // Start initialization
    _initFuture = _initialize();
    try {
      await _initFuture;
    } finally {
      _initFuture = null;
    }
  }

  Future<void> _initialize() async {
    if (_isInitialized) return;

    final startTime = DateTime.now();
    try {
      print("Initializing audio service...");

      // Initialize speech recognition
      _isInitialized = await _speechToText.initialize(
        onError: (error) => print('Speech recognition error: ${error.errorMsg}'),
        onStatus: (status) => print('Speech recognition status: $status'),
        debugLogging: true,
      );

      // Check permissions once
      if (_isInitialized) {
        final controller = RecorderController();
        _hasPermission = await controller.checkPermission();
        controller.dispose();
      }

      final duration = DateTime.now().difference(startTime);
      print(
        "Audio service initialized in ${duration.inMilliseconds}ms: $_isInitialized, permissions: $_hasPermission",
      );
    } catch (e) {
      print("Error initializing audio service: $e");
      _isInitialized = false;
      _hasPermission = false;
      rethrow;
    }
  }

  /// Get or create a recorder controller for a specific field.
  RecorderController getRecorderController(String fieldId) {
    if (!_recorderControllers.containsKey(fieldId)) {
      _recorderControllers[fieldId] = RecorderController();
    }
    return _recorderControllers[fieldId]!;
  }

  /// Start listening for a specific field.
  Future<void> startListening({
    required String fieldId,
    required void Function(SpeechRecognitionResult) onResult,
  }) async {
    if (!_isInitialized || !_hasPermission) {
      throw Exception("Audio service not ready");
    }

    final startTime = DateTime.now();
    final controller = getRecorderController(fieldId);

    try {
      print("Starting recording at ${startTime.millisecondsSinceEpoch}");

      // Ensure speech recognition is fully stopped/cancelled before starting
      // This prevents delays from previous sessions not being fully cleaned up
      if (_speechToText.isListening) {
        print("Speech recognition is still listening, cancelling first...");
        await _speechToText.cancel();
      }

      // Start speech recognition first
      await _speechToText.listen(
        onResult: onResult,
        listenFor: const Duration(minutes: 5),
        pauseFor: const Duration(seconds: 5),
        localeId: "en_US",
        listenOptions: SpeechListenOptions(
          cancelOnError: true,
          partialResults: true,
        ),
      );
      final speechStartTime = DateTime.now();
      print(
        "Speech recognition started in ${speechStartTime.difference(startTime).inMilliseconds}ms",
      );

      // Then start recording
      await controller.record();
      final recordingStartTime = DateTime.now();
      print(
        "Recording started in ${recordingStartTime.difference(speechStartTime).inMilliseconds}ms",
      );
      print(
        "Total start time: ${recordingStartTime.difference(startTime).inMilliseconds}ms",
      );
    } catch (e) {
      print("Error starting listening: $e");
      if (controller.isRecording) {
        await controller.stop();
      }
      rethrow;
    }
  }

  /// Stop listening for a specific field.
  /// Returns immediately after initiating stop operations for responsive UI.
  Future<void> stopListening(String fieldId) async {
    final startTime = DateTime.now();
    final controller = getRecorderController(fieldId);

    try {
      print(
        "Stopping speech recognition at ${startTime.millisecondsSinceEpoch}",
      );

      // Stop recording and speech recognition in parallel for faster cleanup
      final futures = <Future>[];
      
      if (controller.isRecording) {
        futures.add(controller.stop().then((_) {
          final recordingStopTime = DateTime.now();
          print(
            "Recording stopped in ${recordingStopTime.difference(startTime).inMilliseconds}ms",
          );
        }));
      }

      if (_speechToText.isListening) {
        futures.add(_speechToText.stop().then((_) {
          final speechStopTime = DateTime.now();
          print(
            "Speech recognition stopped in ${speechStopTime.difference(startTime).inMilliseconds}ms",
          );
        }));
      }

      // Wait for all operations to complete
      await Future.wait(futures);
      
      final totalStopTime = DateTime.now();
      print(
        "Total stop time: ${totalStopTime.difference(startTime).inMilliseconds}ms",
      );
    } catch (e) {
      print("Error stopping listening: $e");
      // Ensure cleanup even if one operation fails
      if (controller.isRecording) {
        try {
          await controller.stop();
        } catch (_) {}
      }
      if (_speechToText.isListening) {
        try {
          await _speechToText.cancel();
        } catch (_) {}
      }
      rethrow;
    }
  }

  /// Cancel listening for a specific field.
  /// Returns immediately after initiating cancel operations for responsive UI.
  Future<void> cancelListening(String fieldId) async {
    final startTime = DateTime.now();
    final controller = getRecorderController(fieldId);

    try {
      print(
        "Cancelling speech recognition at ${startTime.millisecondsSinceEpoch}",
      );

      // Stop recording and cancel speech recognition in parallel for faster cleanup
      final futures = <Future>[];
      
      if (controller.isRecording) {
        futures.add(controller.stop().then((_) {
          final recordingStopTime = DateTime.now();
          print(
            "Recording stopped in ${recordingStopTime.difference(startTime).inMilliseconds}ms (during cancel)",
          );
        }));
      }

      if (_speechToText.isListening) {
        futures.add(_speechToText.cancel().then((_) {
          final speechStopTime = DateTime.now();
          print(
            "Speech recognition cancelled in ${speechStopTime.difference(startTime).inMilliseconds}ms",
          );
        }));
      } else {
        print(
          "Speech recognition was not listening, nothing to cancel for speech_to_text.",
        );
      }

      // Wait for all operations to complete
      await Future.wait(futures);
      
      final totalCancelTime = DateTime.now();
      print(
        "Total cancel time: ${totalCancelTime.difference(startTime).inMilliseconds}ms",
      );
    } catch (e) {
      print("Error cancelling listening: $e");
      // Ensure cleanup even if one operation fails
      if (controller.isRecording) {
        try {
          await controller.stop();
        } catch (_) {}
      }
      if (_speechToText.isListening) {
        try {
          await _speechToText.cancel();
        } catch (_) {}
      }
    }
  }

  /// Clean up resources for a specific field.
  Future<void> dispose(String fieldId) async {
    final controller = _recorderControllers.remove(fieldId);
    if (controller != null) {
      if (controller.isRecording) {
        await controller.stop();
      }
      controller.dispose();
    }
  }

  /// Check if service is ready.
  bool get isReady => _isInitialized && _hasPermission;

  /// Check if a specific field is recording.
  bool isRecording(String fieldId) {
    final controller = _recorderControllers[fieldId];
    return controller?.isRecording ?? false;
  }
}

