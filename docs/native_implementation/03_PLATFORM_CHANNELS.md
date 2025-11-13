# Phase 3: Platform Channels Integration

## Objective

Create efficient Flutter-to-iOS communication using method channels and event channels for real-time data streaming.

## Goals

- ✅ Low-latency method channel calls
- ✅ Real-time event streaming for results and audio levels
- ✅ Proper error handling and state synchronization
- ✅ Clean Dart API that matches existing interface

## Implementation Steps

### Step 1: Create DictationManager (iOS Coordinator)

**File**: `ios/Runner/DictationManager.swift`

**Responsibilities**:
- Coordinate audio engine and speech recognizer
- Handle platform channel methods
- Stream events to Flutter
- Manage state

**Key Properties**:
```swift
private let audioEngineManager: AudioEngineManager
private let speechRecognizerManager: SpeechRecognizerManager
private let methodChannel: FlutterMethodChannel
private let eventChannel: FlutterEventChannel
```

### Step 2: Method Channel Setup

**In AppDelegate.swift**:
```swift
let controller = window?.rootViewController as! FlutterViewController

let dictationChannel = FlutterMethodChannel(
    name: "com.flutter_dictation/methods",
    binaryMessenger: controller.binaryMessenger
)

let dictationManager = DictationManager(
    methodChannel: dictationChannel,
    eventChannel: FlutterEventChannel(
        name: "com.flutter_dictation/events",
        binaryMessenger: controller.binaryMessenger
    )
)

dictationChannel.setMethodCallHandler { call, result in
    dictationManager.handleMethodCall(call, result: result)
}
```

**Method Channel Methods**:
- `initialize` - Initialize audio and speech recognition
- `startListening` - Start recording and recognition
- `stopListening` - Stop and get final result
- `cancelListening` - Cancel without result
- `getAudioLevel` - Get current audio level (for waveform)

### Step 3: Event Channel Setup

**For Streaming Data**:
- Speech recognition results (partial and final)
- Status updates
- Audio level updates (for waveform)

**Event Channel Stream**:
```swift
func onListen(withArguments arguments: Any?, eventSink events: FlutterEventSink?) -> FlutterError? {
    self.eventSink = events
    return nil
}

func onCancel(withArguments arguments: Any?) -> FlutterError? {
    self.eventSink = nil
    return nil
}
```

**Event Types**:
```swift
enum DictationEvent {
    case result(text: String, isFinal: Bool)
    case status(String)
    case audioLevel(Float)
    case error(String)
}
```

### Step 4: Method Implementations

**Initialize**:
```swift
case "initialize":
    Task {
        do {
            try await dictationManager.initialize()
            result(nil)
        } catch {
            result(FlutterError(code: "INIT_ERROR", message: error.localizedDescription, details: nil))
        }
    }
```

**Start Listening**:
```swift
case "startListening":
    Task {
        do {
            try await dictationManager.startListening()
            result(nil)
        } catch {
            result(FlutterError(code: "START_ERROR", message: error.localizedDescription, details: nil))
        }
    }
```

**Stop Listening**:
```swift
case "stopListening":
    Task {
        await dictationManager.stopListening()
        result(nil)
    }
```

**Get Audio Level**:
```swift
case "getAudioLevel":
    let level = dictationManager.getAudioLevel()
    result(level)
```

### Step 5: Event Streaming

**Send Results**:
```swift
func sendResult(_ text: String, isFinal: Bool) {
    let event: [String: Any] = [
        "type": "result",
        "text": text,
        "isFinal": isFinal
    ]
    eventSink?(event)
}
```

**Send Status**:
```swift
func sendStatus(_ status: String) {
    let event: [String: Any] = [
        "type": "status",
        "status": status
    ]
    eventSink?(event)
}
```

**Send Audio Level**:
```swift
func sendAudioLevel(_ level: Float) {
    let event: [String: Any] = [
        "type": "audioLevel",
        "level": level
    ]
    eventSink?(event)
}
```

### Step 6: Create Dart Service

**File**: `lib/services/native_dictation_service.dart`

**Class Structure**:
```dart
class NativeDictationService {
  static const MethodChannel _methodChannel = MethodChannel('com.flutter_dictation/methods');
  static const EventChannel _eventChannel = EventChannel('com.flutter_dictation/events');
  
  StreamSubscription? _eventSubscription;
  
  // Initialize
  Future<void> initialize() async { ... }
  
  // Start listening
  Future<void> startListening({
    required Function(String, bool) onResult,
    required Function(String) onStatus,
    required Function(double) onAudioLevel,
  }) async { ... }
  
  // Stop listening
  Future<void> stopListening() async { ... }
  
  // Cancel listening
  Future<void> cancelListening() async { ... }
}
```

### Step 7: Event Stream Handling

**Listen to Events**:
```dart
void _setupEventStream({
  required Function(String, bool) onResult,
  required Function(String) onStatus,
  required Function(double) onAudioLevel,
}) {
  _eventSubscription?.cancel();
  
  _eventSubscription = _eventChannel.receiveBroadcastStream().listen(
    (dynamic event) {
      final Map<String, dynamic> data = Map<String, dynamic>.from(event);
      
      switch (data['type']) {
        case 'result':
          onResult(data['text'], data['isFinal']);
          break;
        case 'status':
          onStatus(data['status']);
          break;
        case 'audioLevel':
          onAudioLevel(data['level']);
          break;
        case 'error':
          throw Exception(data['message']);
      }
    },
    onError: (error) {
      // Handle error
    },
  );
}
```

### Step 8: Audio Level Streaming

**For Waveform Visualization**:
- Stream audio levels at 60 FPS (every ~16ms)
- Use a timer on native side to send levels
- Or send levels with each audio buffer

**Native Side Timer**:
```swift
private var audioLevelTimer: Timer?

func startAudioLevelStreaming() {
    audioLevelTimer = Timer.scheduledTimer(withTimeInterval: 0.016, repeats: true) { [weak self] _ in
        let level = self?.audioEngineManager.getAudioLevel() ?? 0.0
        self?.sendAudioLevel(level)
    }
}
```

## Testing Checklist

- [ ] Method channel calls work correctly
- [ ] Event channel streams data properly
- [ ] Results received in real-time
- [ ] Status updates accurate
- [ ] Audio levels stream smoothly
- [ ] Error handling works
- [ ] No memory leaks from streams
- [ ] Latency < 50ms for method calls

## Performance Considerations

**Method Channel**:
- Use async/await for non-blocking calls
- Keep payloads small
- Batch operations when possible

**Event Channel**:
- Stream at appropriate rate (not too fast)
- Use efficient data structures
- Cancel streams properly

**Memory Management**:
- Cancel event subscriptions in dispose
- Weak references where appropriate
- Clean up native resources

## Error Handling

**Dart Side**:
```dart
try {
  await _methodChannel.invokeMethod('startListening');
} on PlatformException catch (e) {
  if (e.code == 'START_ERROR') {
    // Handle start error
  }
}
```

**Swift Side**:
```swift
catch {
  result(FlutterError(
    code: "ERROR_CODE",
    message: error.localizedDescription,
    details: nil
  ))
}
```

## Dependencies

- Flutter method channels
- Flutter event channels
- Audio engine manager (Phase 1)
- Speech recognizer manager (Phase 2)

## Next Phase

Once platform channels are working:
→ **Phase 4**: Waveform Streaming (`04_WAVEFORM_STREAMING.md`)

