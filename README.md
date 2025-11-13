# Flutter Dictation Module

A reusable Flutter module for voice dictation with waveform visualization. This module provides a complete solution for adding voice input capabilities to your Flutter applications.

## 🚧 Currently Under Refactor

**We're rebuilding with native iOS implementation for sub-100ms latency!**

The current package-based implementation (in `legacy/`) had latency issues. We're migrating to a native iOS implementation for optimal performance.

- **Current**: Package-based (`speech_to_text` + `audio_waveforms`) - ~3000ms latency
- **New**: Native iOS (`AVAudioEngine` + `SFSpeechRecognizer`) - <100ms latency target

See `docs/native_implementation/` for implementation details and progress.

## Features

- 🎤 Voice recording with waveform visualization
- 🗣️ Speech-to-text conversion
- ⏱️ Recording timer display
- 🎨 Customizable UI controls (mic, cancel, checkmark)
- 📱 iOS-style Cupertino design
- 🔄 Processing state indicators

## Installation

Add this to your `pubspec.yaml`:

```yaml
dependencies:
  flutter_dictation:
    path: /path/to/flutter_dictation
```

Or if you publish it:

```yaml
dependencies:
  flutter_dictation: ^0.0.1
```

## Usage

### Basic Example

```dart
import 'package:flutter_dictation/flutter_dictation.dart';
import 'package:audio_waveforms/audio_waveforms.dart';
import 'package:speech_to_text/speech_recognition_result.dart';

class MyDictationWidget extends StatefulWidget {
  @override
  State<MyDictationWidget> createState() => _MyDictationWidgetState();
}

class _MyDictationWidgetState extends State<MyDictationWidget> {
  final TextEditingController _textController = TextEditingController();
  bool _isListening = false;
  Duration _elapsedTime = Duration.zero;
  late final RecorderController _recorderController;
  final String _fieldId = 'my_field_${DateTime.now().millisecondsSinceEpoch}';

  @override
  void initState() {
    super.initState();
    _recorderController = AudioService().getRecorderController(_fieldId);
    AudioService().initialize();
  }

  @override
  void dispose() {
    _textController.dispose();
    AudioService().dispose(_fieldId);
    super.dispose();
  }

  void _handleMicPressed() async {
    if (!_isListening) {
      setState(() {
        _isListening = true;
        _elapsedTime = Duration.zero;
      });
      await AudioService().startListening(
        fieldId: _fieldId,
        onResult: (result) {
          if (result.finalResult) {
            setState(() {
              _textController.text += result.recognizedWords + ' ';
            });
          }
        },
      );
    } else {
      await AudioService().stopListening(_fieldId);
      setState(() => _isListening = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return AudioControlsDecorator(
      isListening: _isListening,
      elapsedTime: _elapsedTime,
      recorderController: _recorderController,
      onMicPressed: _handleMicPressed,
      onCancelPressed: () {
        AudioService().stopListening(_fieldId);
        setState(() => _isListening = false);
      },
      child: CupertinoTextField(
        controller: _textController,
        placeholder: 'Start dictating...',
      ),
    );
  }
}
```

## Components

### AudioControlsDecorator

A widget that wraps your text input field and adds audio recording controls below it.

**Properties:**
- `child` - The widget to decorate (typically a TextField)
- `isListening` - Whether recording is currently active
- `isProcessing` - Whether speech is being processed
- `elapsedTime` - Duration of the current recording
- `recorderController` - Optional RecorderController for waveform display
- `onMicPressed` - Callback when mic/checkmark button is pressed
- `onCancelPressed` - Callback when cancel button is pressed

### AudioService

A singleton service that manages audio recording and speech recognition.

**Methods:**
- `initialize()` - Initialize the service (call once at app startup)
- `getRecorderController(String fieldId)` - Get or create a recorder controller
- `startListening({required String fieldId, required onResult})` - Start recording
- `stopListening(String fieldId)` - Stop recording
- `cancelListening(String fieldId)` - Cancel recording
- `dispose(String fieldId)` - Clean up resources
- `isReady` - Check if service is ready to use

## Running the Example

To run the example app:

```bash
flutter run
```

Or run from the example directory:

```bash
cd example
flutter run
```

## Permissions

This module requires microphone permissions. Make sure to add the necessary permissions to your platform-specific configuration files:

### iOS (`ios/Runner/Info.plist`)

```xml
<key>NSMicrophoneUsageDescription</key>
<string>We need access to your microphone for voice dictation</string>
<key>NSSpeechRecognitionUsageDescription</key>
<string>We need access to speech recognition for voice dictation</string>
```

### Android (`android/app/src/main/AndroidManifest.xml`)

```xml
<uses-permission android:name="android.permission.RECORD_AUDIO" />
```

## Project Structure

```
flutter_dictation/
├── docs/                     # Planning documentation
│   └── native_implementation/  # Native iOS implementation plans
│       ├── 00-06_*.md          # Implementation phase guides
│       └── QUICK_START.md      # Quick reference
├── legacy/                   # OLD: Package-based implementation (reference)
│   └── lib/services/         # Original audio_service.dart
├── lib/                      # Flutter package code
│   ├── services/             # Dictation services (being updated)
│   ├── widgets/             # UI components (reused)
│   └── theme/               # Styling (reused)
├── ios/Runner/              # Native iOS code (Swift)
└── example/                  # Example app for testing
```

## Dependencies

**Current (Legacy)**:
- `speech_to_text: ^7.0.0` - Speech recognition
- `audio_waveforms: ^1.3.0` - Waveform visualization
- `cupertino_icons: ^1.0.2` - iOS-style icons

**New (Native)**:
- Native iOS frameworks: `AVFoundation`, `Speech`
- No Flutter package dependencies for core functionality

## Migration Status

- ✅ Workspace reorganized
- ✅ Planning documents created
- 🚧 Native implementation in progress
- ⏳ Migration with feature flag (planned)

See `docs/native_implementation/README.md` for implementation status.

## License

This project is available for use in your applications.
