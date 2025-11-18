import 'dart:async';
import 'package:flutter/services.dart';

/// Configuration options for each dictation session.
class DictationSessionOptions {
  const DictationSessionOptions({
    this.preserveAudio = false,
    this.preservedAudioFilePath,
    this.deleteAudioIfCancelled = true,
  });

  /// Whether to mirror the microphone input into a file on the native side.
  final bool preserveAudio;

  /// Optional absolute or sandbox-relative path (e.g., `Recordings/clip.wav`) for the audio file.
  /// When omitted, the native layer will pick a timestamped file inside the temporary directory.
  final String? preservedAudioFilePath;

  /// When true, the audio file is removed if the session is cancelled instead of stopped.
  final bool deleteAudioIfCancelled;

  Map<String, dynamic>? toMap() {
    if (!preserveAudio) return null;
    final trimmedPath = preservedAudioFilePath?.trim();
    if (trimmedPath != null && trimmedPath.isEmpty) {
      throw ArgumentError(
        'preservedAudioFilePath cannot be empty when provided.',
      );
    }
    return <String, dynamic>{
      'preserveAudio': true,
      if (trimmedPath != null) 'preservedAudioFilePath': trimmedPath,
      'deleteAudioIfCancelled': deleteAudioIfCancelled,
    };
  }
}

/// Metadata describing an audio file preserved by the native layer.
class DictationAudioFile {
  const DictationAudioFile({
    required this.path,
    required this.duration,
    required this.fileSizeBytes,
    required this.sampleRate,
    required this.channelCount,
    required this.wasCancelled,
  });

  final String path;
  final Duration duration;
  final int fileSizeBytes;
  final double sampleRate;
  final int channelCount;
  final bool wasCancelled;

  factory DictationAudioFile.fromEvent(Map<String, dynamic> data) {
    final durationMs = (data['durationMs'] as num?)?.toDouble() ?? 0.0;
    return DictationAudioFile(
      path: data['path'] as String,
      duration: Duration(milliseconds: durationMs.round()),
      fileSizeBytes: (data['fileSizeBytes'] as num?)?.toInt() ?? 0,
      sampleRate: (data['sampleRate'] as num?)?.toDouble() ?? 0.0,
      channelCount: (data['channelCount'] as num?)?.toInt() ?? 1,
      wasCancelled: data['wasCancelled'] as bool? ?? false,
    );
  }
}

/// Service for managing native iOS dictation via platform channels.
/// Provides low-latency speech recognition with real-time results and audio levels.
class NativeDictationService {
  static const MethodChannel _methodChannel = MethodChannel(
    'com.flutter_dictation/methods',
  );
  static const EventChannel _eventChannel = EventChannel(
    'com.flutter_dictation/events',
  );

  StreamSubscription<dynamic>? _eventSubscription;

  /// Initialize the native dictation service.
  /// Should be called before starting to listen.
  /// Retries automatically if platform channels aren't ready yet.
  Future<void> initialize({
    int maxRetries = 10,
    Duration retryDelay = const Duration(milliseconds: 100),
  }) async {
    final startTime = DateTime.now();
    print('[NativeDictationService] === INITIALIZE START ===');
    print(
      '[NativeDictationService] Timestamp: ${startTime.millisecondsSinceEpoch}',
    );
    print('[NativeDictationService] Max retries: $maxRetries');

    int retryCount = 0;

    while (retryCount < maxRetries) {
      try {
        print(
          '[NativeDictationService] Invoking initialize method channel (attempt ${retryCount + 1}/$maxRetries)...',
        );
        await _methodChannel.invokeMethod('initialize');
        final duration = DateTime.now().difference(startTime);
        print(
          '[NativeDictationService] === INITIALIZE COMPLETE in ${duration.inMilliseconds}ms ===',
        );
        return; // Success, exit retry loop
      } on PlatformException catch (e) {
        final duration = DateTime.now().difference(startTime);
        print(
          '[NativeDictationService] PlatformException during initialize after ${duration.inMilliseconds}ms',
        );
        print('[NativeDictationService] PlatformException code: ${e.code}');
        print(
          '[NativeDictationService] PlatformException message: ${e.message}',
        );
        print(
          '[NativeDictationService] PlatformException details: ${e.details}',
        );
        // Handle initialization errors from native code
        if (e.code == 'INIT_ERROR') {
          throw Exception('Failed to initialize dictation: ${e.message}');
        }
        rethrow;
      } catch (e, stackTrace) {
        final duration = DateTime.now().difference(startTime);
        // Handle MissingPluginException (channel not ready yet)
        // MissingPluginException is thrown when platform channel handler isn't registered
        final errorString = e.toString();
        print(
          '[NativeDictationService] Error during initialize after ${duration.inMilliseconds}ms: $e',
        );
        print('[NativeDictationService] Error string: $errorString');
        print('[NativeDictationService] StackTrace: $stackTrace');

        if (errorString.contains('MissingPluginException') ||
            errorString.contains('No implementation found')) {
          retryCount++;
          print(
            '[NativeDictationService] MissingPluginException detected, retry $retryCount/$maxRetries',
          );
          if (retryCount < maxRetries) {
            // Wait before retrying
            print(
              '[NativeDictationService] Waiting ${retryDelay.inMilliseconds}ms before retry...',
            );
            await Future.delayed(retryDelay);
            continue;
          } else {
            print(
              '[NativeDictationService] === INITIALIZE FAILED after $maxRetries retries ===',
            );
            throw Exception(
              'Failed to initialize dictation: Platform channels not available after $maxRetries retries. Please ensure the app has been rebuilt after adding native code.',
            );
          }
        }
        // Re-throw other errors
        print(
          '[NativeDictationService] === INITIALIZE FAILED (non-retryable error) ===',
        );
        rethrow;
      }
    }
  }

  /// Start listening for speech recognition.
  ///
  /// [onResult] is called with partial and final results.
  /// [onStatus] is called with status updates (e.g., "listening", "stopped").
  /// [onAudioLevel] is called with audio level updates for waveform visualization.
  /// [onError] is called if an error occurs.
  /// [onAudioFile] fires when the native layer finishes writing the optional preserved audio file.
  /// [options] controls behavior such as whether to keep the raw audio.
  Future<void> startListening({
    required Function(String text, bool isFinal) onResult,
    required Function(String status) onStatus,
    required Function(double level) onAudioLevel,
    Function(String error)? onError,
    Function(DictationAudioFile file)? onAudioFile,
    DictationSessionOptions? options,
  }) async {
    final startTime = DateTime.now();
    print('[NativeDictationService] === START LISTENING START ===');
    print(
      '[NativeDictationService] Timestamp: ${startTime.millisecondsSinceEpoch}',
    );

    // Set up event stream
    print('[NativeDictationService] Setting up event stream...');
    _setupEventStream(
      onResult: onResult,
      onStatus: onStatus,
      onAudioLevel: onAudioLevel,
      onError: onError,
      onAudioFile: onAudioFile,
    );
    print('[NativeDictationService] Event stream set up');

    try {
      print(
        '[NativeDictationService] Invoking startListening method channel...',
      );
      final args = options?.toMap();
      await _methodChannel.invokeMethod('startListening', args);
      final duration = DateTime.now().difference(startTime);
      print(
        '[NativeDictationService] === START LISTENING COMPLETE in ${duration.inMilliseconds}ms ===',
      );
    } on PlatformException catch (e) {
      final duration = DateTime.now().difference(startTime);
      print(
        '[NativeDictationService] === START LISTENING FAILED after ${duration.inMilliseconds}ms ===',
      );
      print('[NativeDictationService] PlatformException code: ${e.code}');
      print('[NativeDictationService] PlatformException message: ${e.message}');
      print('[NativeDictationService] PlatformException details: ${e.details}');
      print(
        '[NativeDictationService] PlatformException stacktrace: ${e.stacktrace}',
      );
      if (e.code == 'START_ERROR') {
        throw Exception('Failed to start listening: ${e.message}');
      }
      rethrow;
    } catch (e, stackTrace) {
      final duration = DateTime.now().difference(startTime);
      print(
        '[NativeDictationService] === START LISTENING FAILED after ${duration.inMilliseconds}ms ===',
      );
      print('[NativeDictationService] Error: $e');
      print('[NativeDictationService] StackTrace: $stackTrace');
      rethrow;
    }
  }

  /// Stop listening and get final result.
  Future<void> stopListening() async {
    try {
      await _methodChannel.invokeMethod('stopListening');
    } on PlatformException catch (e) {
      throw Exception('Failed to stop listening: ${e.message}');
    }
  }

  /// Cancel listening without getting a result.
  Future<void> cancelListening() async {
    try {
      await _methodChannel.invokeMethod('cancelListening');
    } on PlatformException catch (e) {
      throw Exception('Failed to cancel listening: ${e.message}');
    }
  }

  /// Get the current audio level for waveform visualization.
  /// Returns a value between 0.0 and 1.0.
  Future<double> getAudioLevel() async {
    try {
      final level = await _methodChannel.invokeMethod('getAudioLevel');
      return (level as num).toDouble();
    } on PlatformException catch (e) {
      throw Exception('Failed to get audio level: ${e.message}');
    }
  }

  /// Set up event stream to receive real-time updates.
  void _setupEventStream({
    required Function(String text, bool isFinal) onResult,
    required Function(String status) onStatus,
    required Function(double level) onAudioLevel,
    Function(String error)? onError,
    Function(DictationAudioFile file)? onAudioFile,
  }) {
    // Cancel existing subscription if any
    _eventSubscription?.cancel();

    print('[NativeDictationService] Creating event stream subscription...');
    _eventSubscription = _eventChannel.receiveBroadcastStream().listen(
      (dynamic event) {
        print('[NativeDictationService] === EVENT RECEIVED ===');
        print('[NativeDictationService] Event data: $event');
        final Map<String, dynamic> data = Map<String, dynamic>.from(event);
        print('[NativeDictationService] Event type: ${data['type']}');

        switch (data['type']) {
          case 'result':
            final text = data['text'] as String;
            final isFinal = data['isFinal'] as bool;
            print(
              '[NativeDictationService] Processing result event: text="$text", isFinal=$isFinal',
            );
            onResult(text, isFinal);
            break;

          case 'status':
            final status = data['status'] as String;
            print(
              '[NativeDictationService] Processing status event: status="$status"',
            );
            onStatus(status);
            break;

          case 'audioLevel':
            final level = data['level'];
            if (level is num) {
              final levelValue = level.toDouble();
              print(
                '[NativeDictationService] Processing audioLevel event: level=$levelValue',
              );
              onAudioLevel(levelValue);
            } else {
              print(
                '[NativeDictationService] WARNING: audioLevel event has invalid level type: ${level.runtimeType}',
              );
            }
            break;

          case 'audioFile':
            if (onAudioFile != null) {
              print(
                '[NativeDictationService] Processing audioFile event: path=${data['path']}',
              );
              onAudioFile(DictationAudioFile.fromEvent(data));
            } else {
              print(
                '[NativeDictationService] audioFile event received but no handler was provided.',
              );
            }
            break;

          case 'error':
            final errorMessage = data['message'] as String? ?? 'Unknown error';
            print(
              '[NativeDictationService] Processing error event: message="$errorMessage"',
            );
            if (onError != null) {
              onError(errorMessage);
            } else {
              throw Exception(errorMessage);
            }
            break;

          default:
            print(
              '[NativeDictationService] WARNING: Unknown event type: ${data['type']}',
            );
        }
      },
      onError: (error) {
        final errorMessage = error.toString();
        print('[NativeDictationService] === EVENT STREAM ERROR ===');
        print('[NativeDictationService] Error: $errorMessage');
        if (onError != null) {
          onError(errorMessage);
        } else {
          print('[NativeDictationService] No error handler, printing error');
        }
      },
      cancelOnError: false,
    );
    print(
      '[NativeDictationService] Event stream subscription created successfully',
    );
  }

  /// Dispose of resources and cancel event subscriptions.
  void dispose() {
    _eventSubscription?.cancel();
    _eventSubscription = null;
  }
}
