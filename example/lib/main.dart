import 'dart:async';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
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
  late final NativeDictationService _dictationService;
  final WaveformController _waveformController = WaveformController();
  bool _isListening = false;
  bool _isInitializing = true;
  String _status = 'Initializing...';
  Timer? _recordingTimer;
  Duration _elapsedTime = Duration.zero;
  DictationAudioFile? _latestAudioFile;
  bool _isNormalizingImport = false;
  NormalizedAudioResult? _normalizedImportResult;
  String? _normalizeError;

  @override
  void initState() {
    super.initState();
    _dictationService = NativeDictationService();
    _initializeInBackground();
  }

  @override
  void dispose() {
    _recordingTimer?.cancel();
    _textController.dispose();
    _focusNode.dispose();
    _waveformController.dispose();
    _dictationService.dispose();
    super.dispose();
  }

  Future<void> _initializeInBackground() async {
    try {
      await _dictationService.initialize();

      if (mounted) {
        setState(() {
          _isInitializing = false;
          _status = 'Ready to record';
        });
      }
    } catch (e) {
      print("Error during initialization: $e");
      if (mounted) {
        setState(() {
          _isInitializing = false;
          _status = 'Error: $e';
        });
      }
    }
  }

  void _startListening() async {
    if (_isInitializing || _isListening) return;
    if (!mounted) return;

    setState(() {
      _isListening = true;
      _elapsedTime = Duration.zero;
      _status = 'Listening...';
    });

    _waveformController.reset();

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
      await _dictationService.startListening(
        onResult: _onSpeechResult,
        onStatus: _onStatusUpdate,
        onAudioLevel: (level) {
          if (mounted) {
            _waveformController.updateLevel(level);
          }
        },
        onError: _onError,
        onAudioFile: _onAudioFileSaved,
        options: const DictationSessionOptions(
          preserveAudio: true,
          deleteAudioIfCancelled: false,
        ),
      );
    } catch (e) {
      print("Error during start/listen: $e");
      if (mounted) {
        setState(() {
          _isListening = false;
          _status = 'Error: $e';
        });
        _recordingTimer?.cancel();
        _waveformController.reset();
      }
    }
  }

  void _stopListening() async {
    print('[ExampleApp] === STOP LISTENING CALLED ===');
    print('[ExampleApp] Stack trace: ${StackTrace.current}');
    _recordingTimer?.cancel();
    if (mounted) {
      setState(() {
        _isListening = false;
        _status = 'Stopped';
      });
      _waveformController.reset();
    }

    try {
      await _dictationService.stopListening();
    } catch (e) {
      print("Error stopping recording: $e");
    }
  }

  void _onSpeechResult(String text, bool isFinal) {
    if (isFinal && text.isNotEmpty) {
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
          '$text ',
        );
        // Set cursor position after the inserted text
        final newOffset = selection.start + text.length + 1;
        _textController.value = TextEditingValue(
          text: newText,
          selection: TextSelection.collapsed(offset: newOffset),
        );
      } else {
        // If no selection, append at the end
        newText = '$currentText$text ';
        _textController.value = TextEditingValue(
          text: newText,
          selection: TextSelection.collapsed(offset: newText.length),
        );
      }
    }
  }

  void _onStatusUpdate(String status) {
    print('[ExampleApp] === STATUS UPDATE: $status ===');
    print('[ExampleApp] Current _isListening state: $_isListening');
    if (mounted) {
      setState(() {
        _status = status;
      });
    }
  }

  void _onError(String error) {
    print("Dictation error: $error");
    if (mounted) {
      setState(() {
        _isListening = false;
        _status = 'Error: $error';
      });
      _recordingTimer?.cancel();
      _waveformController.reset();
    }
  }

  void _onAudioFileSaved(DictationAudioFile file) {
    print(
      'Dictation audio saved: ${file.path} (${file.duration.inMilliseconds}ms, ${file.fileSizeBytes} bytes)',
    );
    if (!mounted) return;
    setState(() {
      _latestAudioFile = file;
    });
  }

  void _handleMicPressed() async {
    print('[ExampleApp] === MIC BUTTON PRESSED ===');
    print(
      '[ExampleApp] Current state: _isInitializing=$_isInitializing, _isListening=$_isListening',
    );
    if (_isInitializing) {
      print("Still initializing speech recognition...");
      return;
    }
    if (!_isListening) {
      print('[ExampleApp] Starting listening...');
      _startListening();
      _focusNode.requestFocus();
    } else {
      print('[ExampleApp] Stopping listening...');
      _stopListening();
    }
  }

  void _cancelListening() {
    _recordingTimer?.cancel();
    if (mounted) {
      setState(() {
        _isListening = false;
        _status = 'Cancelled';
      });
      _waveformController.reset();
    }

    _dictationService.cancelListening().catchError((e) {
      print("Error cancelling recording: $e");
    });
  }

  Future<void> _importAndNormalizeAudio() async {
    if (_isNormalizingImport) return;
    setState(() {
      _isNormalizingImport = true;
      _normalizedImportResult = null;
      _normalizeError = null;
      _status = 'Selecting file to normalize...';
    });

    try {
      final picked = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: [
          'wav',
          'mp3',
          'm4a',
          'aac',
          'caf',
          'aiff',
          'flac',
          'ogg',
        ],
        allowMultiple: false,
      );

      if (picked == null ||
          picked.files.isEmpty ||
          picked.files.first.path == null) {
        if (mounted) {
          setState(() {
            _status = 'Normalization cancelled';
          });
        }
        return;
      }

      final sourcePath = picked.files.first.path!;
      if (mounted) {
        setState(() {
          _status = 'Normalizing imported audio...';
        });
      }

      final normalizedResult = await _dictationService.normalizeAudio(
        sourcePath,
      );

      if (!mounted) return;
      setState(() {
        _normalizedImportResult = normalizedResult;
        _status = 'Imported audio normalized';
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Normalized audio saved at ${normalizedResult.canonicalPath}',
          ),
        ),
      );
    } on PlatformException catch (e) {
      _handleNormalizationError(e.message ?? 'Platform error (${e.code})');
    } catch (e) {
      _handleNormalizationError(e.toString());
    } finally {
      if (mounted) {
        setState(() {
          _isNormalizingImport = false;
        });
      }
    }
  }

  void _handleNormalizationError(String message) {
    if (!mounted) return;
    setState(() {
      _normalizeError = message;
      _status = 'Normalization failed';
    });
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text('Normalization failed: $message')));
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
                style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 8),
              Text(
                _status,
                style: TextStyle(
                  fontSize: 14,
                  color: CupertinoColors.secondaryLabel.resolveFrom(context),
                ),
              ),
              if (_latestAudioFile != null) ...[
                const SizedBox(height: 4),
                Text(
                  'Last audio file: ${_latestAudioFile!.path}\n'
                  'Duration: ${_latestAudioFile!.duration.inSeconds}s • '
                  'Size: ${(_latestAudioFile!.fileSizeBytes / 1024).toStringAsFixed(1)} KB',
                  style: TextStyle(
                    fontSize: 12,
                    color: CupertinoColors.secondaryLabel.resolveFrom(context),
                  ),
                ),
              ],
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
                    child: SingleChildScrollView(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          CupertinoTextField(
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
                              color: CupertinoColors.systemBackground
                                  .resolveFrom(context),
                              borderRadius: BorderRadius.circular(8.0),
                            ),
                            padding: const EdgeInsets.all(12.0),
                            style: const TextStyle(fontSize: 16),
                          ),
                          const SizedBox(height: 8.0),
                          // Control row with native waveform
                          if (_isListening) ...[
                            Container(
                              height: 40.0,
                              padding: const EdgeInsets.symmetric(
                                vertical: 4.0,
                                horizontal: 8.0,
                              ),
                              child: Row(
                                crossAxisAlignment: CrossAxisAlignment.center,
                                children: [
                                  // Cancel Button (Left)
                                  CupertinoButton(
                                    padding: const EdgeInsets.only(right: 8.0),
                                    minSize: 30,
                                    onPressed: _cancelListening,
                                    child: Icon(
                                      CupertinoIcons.xmark_circle_fill,
                                      color: CupertinoColors.secondaryLabel
                                          .resolveFrom(context),
                                      size: 20.0,
                                    ),
                                  ),
                                  // Native Waveform (Middle, Expanded)
                                  Expanded(
                                    child: NativeWaveform(
                                      controller: _waveformController,
                                      height: 30.0,
                                    ),
                                  ),
                                  // Timer and Checkmark (Right)
                                  Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      // Timer Text
                                      Text(
                                        _formatDuration(_elapsedTime),
                                        style: TextStyle(
                                          color: CupertinoColors.secondaryLabel
                                              .resolveFrom(context),
                                          fontSize: 13,
                                        ),
                                      ),
                                      const SizedBox(width: 8.0),
                                      // Checkmark Button
                                      CupertinoButton(
                                        padding: EdgeInsets.zero,
                                        minSize: 30,
                                        onPressed: _handleMicPressed,
                                        child: Icon(
                                          CupertinoIcons.checkmark_circle_fill,
                                          color: CupertinoColors.secondaryLabel
                                              .resolveFrom(context),
                                          size: 20.0,
                                        ),
                                      ),
                                    ],
                                  ),
                                ],
                              ),
                            ),
                          ] else ...[
                            const SizedBox(height: 8.0),
                            Container(
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                color: CupertinoColors.secondaryLabel
                                    .resolveFrom(context)
                                    .withValues(alpha: 0.1),
                              ),
                              child: CupertinoButton(
                                padding: const EdgeInsets.all(12.0),
                                minSize: 60,
                                onPressed:
                                    _isInitializing ? null : _handleMicPressed,
                                child: Icon(
                                  CupertinoIcons.mic,
                                  color: CupertinoColors.secondaryLabel
                                      .resolveFrom(context),
                                  size: 32.0,
                                ),
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 20),
              _buildNormalizationPanel(context),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildNormalizationPanel(BuildContext context) {
    final normalized = _normalizedImportResult;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SizedBox(height: 16),
        Text(
          'Import & Normalize Audio',
          style: TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.w600,
            color: CupertinoColors.label.resolveFrom(context),
          ),
        ),
        const SizedBox(height: 4),
        Text(
          'Select an existing file and normalize it before uploading.',
          style: TextStyle(
            fontSize: 13,
            color: CupertinoColors.secondaryLabel.resolveFrom(context),
          ),
        ),
        const SizedBox(height: 12),
        CupertinoButton.filled(
          padding: const EdgeInsets.symmetric(vertical: 12),
          onPressed: _isNormalizingImport ? null : _importAndNormalizeAudio,
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              if (_isNormalizingImport) ...[
                const CupertinoActivityIndicator(),
                const SizedBox(width: 8),
              ],
              Text(
                _isNormalizingImport
                    ? 'Normalizing...'
                    : 'Import & Normalize Audio',
              ),
            ],
          ),
        ),
        if (normalized != null) ...[
          const SizedBox(height: 12),
          Text(
            'Normalized file:',
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: CupertinoColors.label.resolveFrom(context),
            ),
          ),
          const SizedBox(height: 4),
          Text(
            'Path: ${normalized.canonicalPath}',
            style: TextStyle(
              fontSize: 12,
              color: CupertinoColors.secondaryLabel.resolveFrom(context),
            ),
          ),
          Text(
            'Duration: ${_formatDuration(normalized.duration)} • '
            'Size: ${_formatFileSize(normalized.sizeBytes)}',
            style: TextStyle(
              fontSize: 12,
              color: CupertinoColors.secondaryLabel.resolveFrom(context),
            ),
          ),
          Text(
            'Reencoded: ${normalized.wasReencoded ? 'Yes' : 'Already canonical'}',
            style: TextStyle(
              fontSize: 12,
              color: CupertinoColors.secondaryLabel.resolveFrom(context),
            ),
          ),
        ],
        if (_normalizeError != null) ...[
          const SizedBox(height: 12),
          Text(
            'Normalization error: $_normalizeError',
            style: TextStyle(fontSize: 12, color: Colors.red.shade600),
          ),
        ],
        const SizedBox(height: 20),
      ],
    );
  }

  String _formatDuration(Duration duration) {
    String twoDigits(int n) => n.toString().padLeft(2, '0');
    final minutes = twoDigits(duration.inMinutes.remainder(60));
    final seconds = twoDigits(duration.inSeconds.remainder(60));
    return "$minutes:$seconds";
  }

  String _formatFileSize(int bytes) {
    const kb = 1024;
    const mb = 1024 * kb;
    if (bytes >= mb) {
      return '${(bytes / mb).toStringAsFixed(2)} MB';
    }
    return '${(bytes / kb).toStringAsFixed(1)} KB';
  }
}
