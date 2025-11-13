import 'dart:async';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:speech_to_text/speech_recognition_result.dart';
import 'package:audio_waveforms/audio_waveforms.dart';
import 'package:flutter_dictation/flutter_dictation.dart';

void main() {
  runApp(const DictationExampleApp());
}

class DictationExampleApp extends StatelessWidget {
  const DictationExampleApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Flutter Dictation Example',
      theme: ThemeData(
        useMaterial3: true,
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.blue),
      ),
      home: const DictationExampleScreen(),
    );
  }
}

class DictationExampleScreen extends StatefulWidget {
  const DictationExampleScreen({super.key});

  @override
  State<DictationExampleScreen> createState() => _DictationExampleScreenState();
}

class _DictationExampleScreenState extends State<DictationExampleScreen> {
  final TextEditingController _textController = TextEditingController();
  final FocusNode _focusNode = FocusNode();
  bool _isListening = false;
  bool _isProcessing = false;
  bool _isInitializing = true;
  Timer? _recordingTimer;
  Duration _elapsedTime = Duration.zero;
  late final RecorderController _recorderController;
  final String _fieldId = 'example_field_${DateTime.now().millisecondsSinceEpoch}';

  @override
  void initState() {
    super.initState();
    _recorderController = AudioService().getRecorderController(_fieldId);
    _initializeInBackground();
  }

  @override
  void dispose() {
    _recordingTimer?.cancel();
    _textController.dispose();
    _focusNode.dispose();
    AudioService().dispose(_fieldId);
    super.dispose();
  }

  Future<void> _initializeInBackground() async {
    try {
      final audioService = AudioService();
      await audioService.initialize();

      if (mounted) {
        setState(() {
          _isInitializing = false;
        });
      }
    } catch (e) {
      print("Error during initialization: $e");
      if (mounted) {
        setState(() {
          _isInitializing = false;
        });
      }
    }
  }

  void _startListening() async {
    if (_isInitializing) {
      print("Still initializing speech recognition...");
      return;
    }

    if (!AudioService().isReady || _isListening) return;
    if (!mounted) return;

    setState(() {
      _isListening = true;
      _elapsedTime = Duration.zero;
    });

    _recordingTimer?.cancel();
    _recordingTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (!mounted) {
        timer.cancel();
        return;
      }
      setState(() {
        _elapsedTime = Duration(seconds: _elapsedTime.inSeconds + 1);
      });
    });

    try {
      await AudioService().startListening(
        fieldId: _fieldId,
        onResult: _onSpeechResult,
      );
    } catch (e) {
      print("Error during start/listen: $e");
      if (mounted) {
        setState(() => _isListening = false);
        _recordingTimer?.cancel();
      }
    }
  }

  void _stopListening() async {
    // Update UI immediately for responsive feel
    _recordingTimer?.cancel();
    if (mounted) {
      setState(() => _isListening = false);
    }
    
    // Cleanup in background
    try {
      await AudioService().stopListening(_fieldId);
    } catch (e) {
      print("Error stopping recording: $e");
    }
  }

  void _onSpeechResult(SpeechRecognitionResult result) {
    if (result.finalResult && result.recognizedWords.isNotEmpty) {
      if (!mounted) return;

      final currentText = _textController.text;
      final selection = _textController.selection;
      String newText;

      // Append or replace logic
      if (selection.isValid && selection.start != -1) {
        // If there's a selection, replace it
        newText = currentText.replaceRange(
          selection.start,
          selection.end,
          '${result.recognizedWords} ',
        );
        // Set cursor position after the inserted text
        final newOffset = selection.start + result.recognizedWords.length + 1;
        _textController.value = TextEditingValue(
          text: newText,
          selection: TextSelection.collapsed(offset: newOffset),
        );
      } else {
        // If no selection, append at the end
        newText = '$currentText${result.recognizedWords} ';
        _textController.value = TextEditingValue(
          text: newText,
          selection: TextSelection.collapsed(offset: newText.length),
        );
      }
    }
  }

  void _handleMicPressed() async {
    if (_isInitializing) {
      print("Still initializing speech recognition...");
      return;
    }
    if (!AudioService().isReady) {
      print("Speech recognition not available or not initialized.");
      return;
    }
    if (!_isListening) {
      _startListening();
      _focusNode.requestFocus();
    } else {
      _stopListening();
    }
  }

  void _cancelListening() {
    print("CANCEL: Cancel requested. Calling _stopListening...");
    // Update UI immediately for responsive feel
    _recordingTimer?.cancel();
    if (mounted) {
      setState(() => _isListening = false);
    }
    
    // Cleanup in background
    AudioService().cancelListening(_fieldId).catchError((e) {
      print("Error cancelling recording: $e");
    });
  }

  @override
  Widget build(BuildContext context) {
    return CupertinoPageScaffold(
      navigationBar: const CupertinoNavigationBar(
        middle: Text('Dictation Example'),
      ),
      child: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(16.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const SizedBox(height: 20),
              const Text(
                'Voice Dictation Demo',
                style: TextStyle(
                  fontSize: 24,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                _isInitializing
                    ? 'Initializing...'
                    : AudioService().isReady
                        ? 'Ready to record'
                        : 'Not ready - check permissions',
                style: TextStyle(
                  fontSize: 14,
                  color: CupertinoColors.secondaryLabel.resolveFrom(context),
                ),
              ),
              const SizedBox(height: 32),
              Expanded(
                child: Material(
                  type: MaterialType.transparency,
                  child: Container(
                    decoration: BoxDecoration(
                      color: CupertinoColors.systemGrey6.resolveFrom(context),
                      borderRadius: BorderRadius.circular(12.0),
                    ),
                    padding: const EdgeInsets.all(16.0),
                    child: AudioControlsDecorator(
                      isListening: _isListening,
                      isProcessing: _isProcessing,
                      elapsedTime: _elapsedTime,
                      recorderController: _recorderController,
                      onMicPressed: _handleMicPressed,
                      onCancelPressed: _cancelListening,
                      child: CupertinoTextField(
                        controller: _textController,
                        focusNode: _focusNode,
                        placeholder: 'Tap the mic to start dictating...',
                        placeholderStyle: TextStyle(
                          color: CupertinoColors.secondaryLabel
                              .resolveFrom(context)
                              .withOpacity(0.7),
                        ),
                        maxLines: null,
                        minLines: 6,
                        keyboardType: TextInputType.multiline,
                        decoration: BoxDecoration(
                          color: CupertinoColors.systemBackground.resolveFrom(context),
                          borderRadius: BorderRadius.circular(8.0),
                        ),
                        padding: const EdgeInsets.all(12.0),
                        style: const TextStyle(fontSize: 16),
                      ),
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 20),
            ],
          ),
        ),
      ),
    );
  }
}

