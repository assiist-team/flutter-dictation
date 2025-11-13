import 'dart:async';
import 'package:flutter/services.dart';

/// Service for managing native iOS dictation via platform channels.
/// Provides low-latency speech recognition with real-time results and audio levels.
class NativeDictationService {
  static const MethodChannel _methodChannel =
      MethodChannel('com.flutter_dictation/methods');
  static const EventChannel _eventChannel =
      EventChannel('com.flutter_dictation/events');

  StreamSubscription<dynamic>? _eventSubscription;

  /// Initialize the native dictation service.
  /// Should be called before starting to listen.
  /// Retries automatically if platform channels aren't ready yet.
  Future<void> initialize({int maxRetries = 10, Duration retryDelay = const Duration(milliseconds: 100)}) async {
    int retryCount = 0;
    
    while (retryCount < maxRetries) {
      try {
        await _methodChannel.invokeMethod('initialize');
        return; // Success, exit retry loop
      } on PlatformException catch (e) {
        // Handle initialization errors from native code
        if (e.code == 'INIT_ERROR') {
          throw Exception('Failed to initialize dictation: ${e.message}');
        }
        rethrow;
      } catch (e) {
        // Handle MissingPluginException (channel not ready yet)
        // MissingPluginException is thrown when platform channel handler isn't registered
        final errorString = e.toString();
        if (errorString.contains('MissingPluginException') || 
            errorString.contains('No implementation found')) {
          retryCount++;
          if (retryCount < maxRetries) {
            // Wait before retrying
            await Future.delayed(retryDelay);
            continue;
          } else {
            throw Exception('Failed to initialize dictation: Platform channels not available after $maxRetries retries. Please ensure the app has been rebuilt after adding native code.');
          }
        }
        // Re-throw other errors
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
  Future<void> startListening({
    required Function(String text, bool isFinal) onResult,
    required Function(String status) onStatus,
    required Function(double level) onAudioLevel,
    Function(String error)? onError,
  }) async {
    // Set up event stream
    _setupEventStream(
      onResult: onResult,
      onStatus: onStatus,
      onAudioLevel: onAudioLevel,
      onError: onError,
    );

    try {
      await _methodChannel.invokeMethod('startListening');
    } on PlatformException catch (e) {
      if (e.code == 'START_ERROR') {
        throw Exception('Failed to start listening: ${e.message}');
      }
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
  }) {
    // Cancel existing subscription if any
    _eventSubscription?.cancel();

    _eventSubscription = _eventChannel.receiveBroadcastStream().listen(
      (dynamic event) {
        final Map<String, dynamic> data = Map<String, dynamic>.from(event);

        switch (data['type']) {
          case 'result':
            onResult(data['text'] as String, data['isFinal'] as bool);
            break;

          case 'status':
            onStatus(data['status'] as String);
            break;

          case 'audioLevel':
            final level = data['level'];
            if (level is num) {
              onAudioLevel(level.toDouble());
            }
            break;

          case 'error':
            final errorMessage = data['message'] as String? ?? 'Unknown error';
            if (onError != null) {
              onError(errorMessage);
            } else {
              throw Exception(errorMessage);
            }
            break;

          default:
            print('Unknown event type: ${data['type']}');
        }
      },
      onError: (error) {
        final errorMessage = error.toString();
        if (onError != null) {
          onError(errorMessage);
        } else {
          print('Event stream error: $errorMessage');
        }
      },
      cancelOnError: false,
    );
  }

  /// Dispose of resources and cancel event subscriptions.
  void dispose() {
    _eventSubscription?.cancel();
    _eventSubscription = null;
  }
}

