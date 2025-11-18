# Using flutter_dictation from GitHub

A quick guide to add this plugin to your Flutter project using GitHub.

## Installation

### 1. Add Dependency

Add the plugin to your project's `pubspec.yaml`:

```yaml
dependencies:
  flutter_dictation:
    git:
      url: https://github.com/YOUR_USERNAME/flutter_dictation.git
      ref: main  # or use a specific tag/branch
```

**Note:** Replace `YOUR_USERNAME` with your actual GitHub username or organization name.

### 2. Install Dependencies

Run:

```bash
flutter pub get
```

### 3. iOS Setup

#### Install CocoaPods Dependencies

```bash
cd ios
pod install
cd ..
```

#### Add Required Permissions

Add these keys to your `ios/Runner/Info.plist`:

```xml
<key>NSMicrophoneUsageDescription</key>
<string>We need access to your microphone for voice dictation</string>
<key>NSSpeechRecognitionUsageDescription</key>
<string>We need access to speech recognition for voice dictation</string>
```

### 4. Rebuild Your App

**Important:** After adding the plugin, you must rebuild your app (not just hot reload):

```bash
flutter clean
flutter run
```

## Usage

### Basic Example

```dart
import 'package:flutter_dictation/flutter_dictation.dart';
import 'package:flutter/cupertino.dart';

class DictationExample extends StatefulWidget {
  @override
  State<DictationExample> createState() => _DictationExampleState();
}

class _DictationExampleState extends State<DictationExample> {
  final NativeDictationService _dictationService = NativeDictationService();
  final WaveformController _waveformController = WaveformController();
  final TextEditingController _textController = TextEditingController();
  
  bool _isListening = false;
  Duration _elapsedTime = Duration.zero;

  @override
  void initState() {
    super.initState();
    _initializeDictation();
  }

  Future<void> _initializeDictation() async {
    await _dictationService.initialize();
  }

  Future<void> _handleMicPressed() async {
    if (!_isListening) {
      setState(() {
        _isListening = true;
        _elapsedTime = Duration.zero;
      });
      
      await _dictationService.startListening(
        onResult: (text, isFinal) {
          if (isFinal) {
            setState(() {
              _textController.text += text + ' ';
            });
          }
        },
        onStatus: (status) {
          print('Status: $status');
        },
        onAudioLevel: (level) {
          _waveformController.updateLevel(level);
        },
      );
    } else {
      await _dictationService.stopListening();
      setState(() => _isListening = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return AudioControlsDecorator(
      isListening: _isListening,
      elapsedTime: _elapsedTime,
      waveformController: _waveformController,
      onMicPressed: _handleMicPressed,
      onCancelPressed: () async {
        await _dictationService.stopListening();
        setState(() => _isListening = false);
      },
      child: CupertinoTextField(
        controller: _textController,
        placeholder: 'Start dictating...',
      ),
    );
  }

  @override
  void dispose() {
    _dictationService.stopListening();
    _textController.dispose();
    super.dispose();
  }
}
```

## Updating the Plugin

When you push updates to the GitHub repository:

1. **To get the latest changes:**
   ```bash
   flutter pub upgrade flutter_dictation
   ```

2. **Or update to a specific commit/tag:**
   ```yaml
   dependencies:
     flutter_dictation:
       git:
         url: https://github.com/YOUR_USERNAME/flutter_dictation.git
         ref: abc123  # specific commit hash
   ```

3. **Rebuild your app:**
   ```bash
   flutter clean
   flutter run
   ```

## Platform Support

- ✅ **iOS**: Fully supported with native implementation
- ❌ **Android**: Not yet implemented

## Troubleshooting

### MissingPluginException

If you see `MissingPluginException` after adding the plugin:

1. Ensure you've run `pod install` in the `ios` directory
2. Do a full rebuild: `flutter clean && flutter run`
3. Make sure your app's `Info.plist` has the required permission keys

### Plugin Not Found

If Flutter can't find the plugin:

1. Check that the GitHub URL is correct
2. Verify the repository is accessible (public or you have access)
3. Ensure the `ref` (branch/tag) exists in the repository

## Requirements

- Flutter SDK: ^3.7.2
- iOS: 13.0 or higher
- Xcode: Latest stable version

