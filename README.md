# Flutter Dictation Module

Low-latency, native-backed dictation for Flutter with real-time waveform streaming. The legacy plugin is preserved under `legacy/`, but the actively developed system is the native iOS stack described below.

## Status Snapshot
- Primary focus: native iOS path (`AVAudioEngine` + `SFSpeechRecognizer`) with a <100 ms latency target.
- Legacy (`speech_to_text` + `audio_waveforms`) implementation kept only for reference.
- Spec, migration, and troubleshooting guides live in `docs/`.

## Feature Highlights
- Streaming speech recognition with partial + final transcripts over event channels.
- ChatGPT-style waveform driven by native audio levels at 30 FPS.
- Canonically encoded `.m4a` captures (AAC‑LC, mono, 44.1 kHz, 64 kbps) with built-in 60‑minute duration guardrails plus surfaced “duration_limit_reached” status/errors.
- Normalization helper (`normalizeAudio`) that ingests any local file, enforces the canonical format/bitrate/duration, and returns a normalized path + metadata.
- Import workflow in the example app that routes selected audio files through `normalizeAudio`, surfaces canonical metadata, and shows error feedback before any upload step.
- Pre-warmed audio engine / speech recognizer for instant mic activation.
- Robust permission guardrails (microphone + speech) with surfaced error states.
- Cupertino-friendly UI primitives (`AudioControlsDecorator`, `NativeWaveform`) you can drop around any text input.

## Offline Dictation Support
- **iOS (current native path)**: `SpeechRecognizerManager` always enables `supportsOnDeviceRecognition` on iOS 13+ whenever the selected locale has an Apple-provided offline dictation pack installed. When that pack exists on the device, recognition runs entirely on-device with no extra plugin configuration.
- **Language coverage**: Apple currently ships on-device packs for the major locales (e.g., English, Spanish, French, German, Mandarin, Japanese, Korean). If a locale is missing—or the user deletes the downloaded pack—iOS transparently falls back to network-backed recognition, so surface a heads-up in your UX if “offline-only” is critical.
- **User setup**: Point users to iOS Settings (`General → Keyboard → Dictation Languages`) to download the offline pack they need; the plugin does not bundle its own acoustic models.
- **Android**: The actively developed native stack is iOS-only right now. Android still relies on the legacy plugin or another speech provider, so there is no packaged offline capability on that platform yet.

## System Architecture
```
Flutter UI --> NativeDictationService (Dart) --> MethodChannel com.flutter_dictation/methods
         ^                                          |
         |                                          v
  Widgets & Waveform <--- EventChannel com.flutter_dictation/events <--- DictationManager
                                                             |
                                   AudioEngineManager  +  SpeechRecognizerManager (Swift)
```

- **Flutter UI layer**: Text inputs, buttons, and waveform widgets respond to service callbacks.
- **Service layer (`NativeDictationService`)**: Owns platform channel contract, event routing, retries, and teardown.
- **Platform channels**: `MethodChannel('com.flutter_dictation/methods')` and `EventChannel('com.flutter_dictation/events')`.
- **Native runtime**:
  - `FlutterDictationPlugin` registers channels and pre-warms managers.
  - `DictationManager` orchestrates initialization, lifecycle, and event fan-out.
  - `AudioEngineManager` owns `AVAudioEngine`, session tuning, tap installation, and waveform-level smoothing.
  - `SpeechRecognizerManager` streams buffers into `SFSpeechRecognizer` and emits partial/final results.

## Runtime Flow
1. Flutter constructs `NativeDictationService` and calls `initialize()` (retries until channels are ready).
2. `initialize` triggers native pre-warm of audio engine + speech recognizer and returns once both report ready.
3. `startListening()` wires the Dart-side event stream, then invokes the native method channel.
4. `DictationManager` (Swift) requests microphone permission on the main thread, spins up the audio engine, shares buffers with the speech recognizer, and starts waveform streaming.
5. Native emits `result`, `status`, `audioLevel`, or `error` events. Dart surfaces them to UI widgets and the `WaveformController`.
6. `stopListening()` finalizes the recognition request; `cancelListening()` drops audio immediately. `dispose()` tears down event subscriptions.

## Platform Channel Contract
**Method channel `com.flutter_dictation/methods`**

| Method            | Args | Native work                                                                 |
|-------------------|------|-------------------------------------------------------------------------------|
| `initialize`      | —    | Pre-warm audio engine + speech recognizer, register interruption handlers.   |
| `startListening`  | Optional `{ preserveAudio, preservedAudioFilePath, deleteAudioIfCancelled }` | Request mic permission (main thread), start engine, attach tap + recognizer, optionally start audio file capture. |
| `stopListening`   | —    | Stop recognizer gracefully, end audio, stop engine.                          |
| `cancelListening` | —    | Abort in-flight recognition and stop engine immediately.                     |
| `getAudioLevel`   | —    | Returns smoothed `0.0-1.0` level from `AudioEngineManager`.                  |
| `normalizeAudio`  | `sourcePath` (string) | Transcode/copy the requested file into canonical `.m4a`, enforce duration limits, and return normalized metadata (`normalizedResult`). |

**Event channel `com.flutter_dictation/events`**

| Event type  | Payload                                                                 | Notes                                          |
|-------------|-------------------------------------------------------------------------|------------------------------------------------|
| `status`    | `{ "status": "ready|listening|stopped|cancelled|duration_limit_reached|error:code" }`          | Drives UI state + timers.                      |
| `result`    | `{ "text": "<transcript>", "isFinal": bool }`                           | Partial + final text; final marks commit.      |
| `audioLevel`| `{ "level": double }`                                                   | 30 FPS waveform samples, already smoothed.     |
| `audioFile` | `{ "path": string, "durationMs": double, "fileSizeBytes": int, "sampleRate": double, "channelCount": int, "wasCancelled": bool }` | Fired after stop/cancel when audio preservation is enabled. Also emitted immediately when the duration limit fires so Flutter can upload the partial recording. |
| `error`     | `{ "message": "<human-readable>", "code": "<stable-code>"? }`                                     | Emitted before Flutter error callback fires.   |

## Flutter API Surface
### `NativeDictationService`
- `Future<void> initialize({int maxRetries, Duration retryDelay})`
- `Future<void> startListening({required onResult, required onStatus, required onAudioLevel, Function(String)? onError, Function(DictationAudioFile)? onAudioFile, DictationSessionOptions? options})`
- `Future<void> stopListening()`
- `Future<void> cancelListening()`
- `Future<double> getAudioLevel()`
- `Future<NormalizedAudioResult> normalizeAudio(String sourcePath)`
- `void dispose()`
- `DictationSessionOptions` + `DictationAudioFile` let you mirror the microphone input to disk (`preserveAudio`, `preservedAudioFilePath`, `deleteAudioIfCancelled`) and observe the resulting file via the `onAudioFile` callback.

`NormalizedAudioResult` contains canonical metadata (`canonicalPath`, `duration`, `sizeBytes`, `wasReencoded`) so you can upload or inspect normalized files in a structured way.

Responsibilities: manage platform channels, hook/unhook the event subscription, surface audio levels to waveforms, and guard retries when Flutter hot reload temporarily drops the native plugin.

### `WaveformController` + `NativeWaveform`
- Fixed-length sliding window (100 samples) pre-filled with zeros so the waveform appears immediately.
- `updateLevel(double)` clamps input and notifies listeners.
- `reset()` clears the buffer—call it when you stop or cancel recording.
- `NativeWaveform` widget listens to the controller and paints ChatGPT-style bars; can be slotted into custom layouts.

### `AudioControlsDecorator`
- Optional convenience widget that renders cancel/mic/checkmark controls, timer, and waveform around any `child` (typically a `CupertinoTextField`).
- Accepts `WaveformController`, `isListening`, `elapsedTime`, and mic/cancel callbacks so you can keep business logic in your screen/state object.

## Usage Example (Native Path)
```dart
class DictationField extends StatefulWidget {
  const DictationField({super.key});

  @override
  State<DictationField> createState() => _DictationFieldState();
}

class _DictationFieldState extends State<DictationField> {
  final _textController = TextEditingController();
  final _dictation = NativeDictationService();
  final _waveform = WaveformController();

  bool _isListening = false;
  String _status = 'initializing';
  Duration _elapsed = Duration.zero;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _dictation.initialize().then((_) {
      if (mounted) setState(() => _status = 'ready');
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    _dictation.dispose();
    _waveform.dispose();
    _textController.dispose();
    super.dispose();
  }

  Future<void> _toggleMic() async {
    if (_isListening) {
      await _dictation.stopListening();
      _timer?.cancel();
      _waveform.reset();
      setState(() {
        _isListening = false;
        _status = 'stopped';
      });
      return;
    }

    setState(() {
      _isListening = true;
      _elapsed = Duration.zero;
      _status = 'listening';
    });
    _timer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() => _elapsed += const Duration(seconds: 1));
    });

    await _dictation.startListening(
      onResult: (text, isFinal) {
        if (isFinal && mounted) {
          _textController.text = '${_textController.text}$text ';
          _textController.selection =
              TextSelection.collapsed(offset: _textController.text.length);
        }
      },
      onStatus: (status) => mounted ? setState(() => _status = status) : null,
      onAudioLevel: (level) => _waveform.updateLevel(level),
      onError: (message) {
        if (!mounted) return;
        _timer?.cancel();
        _waveform.reset();
        setState(() {
          _isListening = false;
          _status = 'error: $message';
        });
      },
      onAudioFile: (file) {
        // Persist the path or upload the recording once transcription finishes.
        debugPrint('Audio saved to ${file.path} (${file.duration.inSeconds}s)');
      },
      options: const DictationSessionOptions(
        preserveAudio: true,
        deleteAudioIfCancelled: false,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return AudioControlsDecorator(
      child: CupertinoTextField(controller: _textController),
      isListening: _isListening,
      elapsedTime: _elapsed,
      onMicPressed: _toggleMic,
      onCancelPressed: () {
        _dictation.cancelListening();
        _timer?.cancel();
        _waveform.reset();
        setState(() {
          _isListening = false;
          _status = 'cancelled';
        });
      },
      waveformController: _waveform,
    );
  }
}
```

## Integration Checklist
- **Service lifecycle**: Create one `NativeDictationService` per UI surface, call `initialize` before the first listen, and `dispose` when the widget leaves the tree.
- **Permission UX**: Surface microphone + speech permission rationale before calling `startListening()` so the native prompt preserves user intent.
- **Status wiring**: Mirror `status` events into your UI (buttons, timers, loader states) and log errors for telemetry.
- **Waveform hygiene**: Reset the `WaveformController` when you stop/cancel to avoid stale bars.
- **Thread affinity**: `startListening` must originate from a UI action so the native layer can request permissions on the main thread.
- **Non-iOS platforms**: Gate access (e.g., hide mic) or provide a fallback since the current native implementation is iOS-specific.
- **Spec references**: Link feature specs to `docs/native_implementation/*.md` for engineering details.

## Native Runtime Details
- **`AudioEngineManager.swift`**: Configures `AVAudioSession` (record + measurement mode, 5 ms buffer, 16 kHz sample rate), requests mic permission, installs a single tap for both waveform + recognition, smooths RMS/peak values, and streams audio levels at 30 FPS.
- **`SpeechRecognizerManager.swift`**: Manages `SFSpeechRecognizer`, tracks authorization, receives shared buffers via callback, emits partial/final transcripts, and maps Speech framework error codes.
- **`DictationManager.swift`**: Core coordinator for platform calls, state machine (`idle → initializing → listening → stopping`), error mapping, event fan-out, and waveform timer management.
- **`FlutterDictationPlugin.swift`**: Registers channels, pre-warms managers after app launch, and shields Flutter from platform channel timing issues.

See the deeper design notes in `docs/native_implementation/01_IOS_AUDIO_ENGINE_SETUP.md` through `06_TESTING_OPTIMIZATION.md`.

## Waveform & Audio Level Streaming
- Audio tap runs once; buffers feed both waveform smoothing and the speech recognizer (since AVAudioEngine allows only one tap per bus).
- Levels are normalized to `0–1` using blended RMS + peak + decibel shaping, so quiet voices still render a visible waveform.
- `NativeDictationService` forwards `audioLevel` events to your callback where you update the `WaveformController`.

## Audio Preservation
- Pass `DictationSessionOptions(preserveAudio: true, ...)` to `startListening` whenever you need access to the raw microphone PCM stream after dictation finishes.
- Handle the `onAudioFile` callback (and the matching `audioFile` event) to receive a `DictationAudioFile` with the final path, duration, size (bytes), sample rate, channel count, and whether the session ended in a cancel.
- Canonical recordings now live under `Documents/FlutterDictationRecordings` and always use `.m4a` (AAC‑LC, 44.1 kHz, mono, 64 kbps). Provide either an absolute sandbox path or a Documents-relative path via `preservedAudioFilePath`; we also respect `.wav`/`.caf` for backwards compatibility, but new captures default to canonical `.m4a`.
- Control retention on cancel flows via `deleteAudioIfCancelled` (defaults to `true`).
- Files are written as encoded AAC instead of PCM, so no additional encoding step is required before upload—the returned metadata already reflects the canonical format.

## Permissions
Add both microphone and speech recognition descriptions in `ios/Runner/Info.plist`:
```xml
<key>NSMicrophoneUsageDescription</key>
<string>We need access to your microphone for low-latency dictation.</string>
<key>NSSpeechRecognitionUsageDescription</key>
<string>We need speech recognition to convert your voice into text.</string>
```

## Project Structure
```
flutter_dictation/
├── lib/
│   ├── flutter_dictation.dart      # Export surface
│   ├── services/
│   │   ├── native_dictation_service.dart
│   │   └── waveform_controller.dart
│   ├── widgets/
│   │   ├── audio_controls_decorator.dart
│   │   ├── native_waveform.dart
│   │   └── waveform_painter.dart
│   └── theme/
├── ios/Classes/                    # Native Swift managers + plugin entry point
├── example/lib/native_waveform_example.dart
├── docs/native_implementation/     # Architecture + migration specs
├── docs/troubleshooting/           # Issue-specific runbooks
├── legacy/                         # Old package-based implementation
└── test/                           # Benchmarks + integration tests
```

## Documentation Map
- `docs/native_implementation/QUICK_START.md` – phase-by-phase plan.
- `docs/native_implementation/01_IOS_AUDIO_ENGINE_SETUP.md` – AVAudioEngine design.
- `docs/native_implementation/02_SPEECH_RECOGNIZER_SETUP.md` – recognition flow.
- `docs/native_implementation/03_PLATFORM_CHANNELS.md` – channel contract + error codes.
- `docs/native_implementation/04_WAVEFORM_STREAMING.md` – waveform math + timers.
- `docs/native_implementation/05_MIGRATION_STRATEGY.md` – example app + cleanup strategy.
- `docs/native_implementation/06_TESTING_OPTIMIZATION.md` – latency + instrumentation guidance.
- `docs/troubleshooting/*.md` – targeted runbooks for permission, latency, and session issues.

## Running the Example App
```bash
flutter run                            # runs the package example from repo root
# or
cd example && flutter run
```

## Legacy Module
`legacy/` maintains the original `speech_to_text` + `audio_waveforms` implementation for reference only. Do not mix it with the native path; specs should target the native stack unless explicitly stated.

## Verify

```bash
flutter pub get
flutter test
```

The package currently passes 23 Dart and Flutter tests. Native microphone, speech
recognition, and latency behavior still require an iOS simulator or device.

## License
MIT. See `LICENSE`.
