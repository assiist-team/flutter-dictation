# Phase 2: Speech Recognizer Setup

## Objective

Set up `SFSpeechRecognizer` with optimal configuration for low-latency dictation, integrated with the audio engine.

## Goals

- ✅ Speech recognition initialized and ready at app launch
- ✅ Parallel start with audio recording (no sequential waits)
- ✅ Real-time partial results
- ✅ Proper error handling and state management

## Implementation Steps

### Step 1: Create SpeechRecognizerManager Class

**File**: `ios/Runner/SpeechRecognizerManager.swift`

**Important**: Create this file in `ios/Runner/` (standard Flutter iOS location), NOT in `native_implementation/ios/`

**Responsibilities**:
- Initialize `SFSpeechRecognizer`
- Manage recognition requests
- Handle speech recognition results
- Coordinate with audio engine

**Key Methods**:
```swift
func initialize() async throws
func startRecognition(audioEngine: AVAudioEngine) async throws
func stopRecognition()
func cancelRecognition()
func setResultCallback(_ callback: @escaping (String, Bool) -> Void)
func setStatusCallback(_ callback: @escaping (String) -> Void)
```

### Step 2: Speech Recognizer Configuration

**Initialization**:
```swift
let recognizer = SFSpeechRecognizer(locale: Locale(identifier: "en-US"))

// Configure for dictation (long-form speech)
recognizer?.defaultTaskHint = .dictation

// Enable on-device recognition if available (faster, more private)
if #available(iOS 13.0, *) {
    recognizer?.supportsOnDeviceRecognition = true
}
```

**Why These Settings**:
- `.dictation` task hint: Optimized for longer speech input
- On-device recognition: Lower latency, no network dependency
- English locale: Can add more locales later

### Step 3: Recognition Request Setup

**Create Request**:
```swift
let recognitionRequest = SFSpeechAudioBufferRecognitionRequest()

// Configure for real-time results
recognitionRequest.shouldReportPartialResults = true

// Task hint for dictation
recognitionRequest.taskHint = .dictation

// Attach audio engine's input node
let inputNode = audioEngine.inputNode
let recordingFormat = inputNode.outputFormat(forBus: 0)
inputNode.installTap(onBus: 0, bufferSize: 1024, format: recordingFormat) { buffer, _ in
    recognitionRequest.append(buffer)
}
```

**Key Configuration**:
- `shouldReportPartialResults = true`: Get results as user speaks
- Attach to same audio node as waveform: No duplicate processing
- Use same buffer size: Consistency with audio engine

### Step 4: Parallel Start Strategy

**Critical**: Start recognition and recording simultaneously

```swift
// Start audio engine first (fast)
try audioEngine.start()

// Start recognition immediately after (parallel)
let recognitionTask = recognizer.recognitionTask(with: recognitionRequest) { result, error in
    // Handle results
}

// Both operations happen in parallel - no waiting!
```

**Why This Works**:
- Audio engine start is fast (~10-20ms)
- Recognition task can start while audio is initializing
- No sequential dependency between them

### Step 5: Result Handling

**Process Results**:
```swift
recognitionTask = recognizer.recognitionTask(with: request) { [weak self] result, error in
    guard let self = self else { return }
    
    if let error = error {
        self.handleRecognitionError(error)
        return
    }
    
    guard let result = result else { return }
    
    // Send partial results immediately
    self.resultCallback?(result.bestTranscription.formattedString, result.isFinal)
    
    // Update status
    if result.isFinal {
        self.statusCallback?("done")
    } else {
        self.statusCallback?("listening")
    }
}
```

**Callback Strategy**:
- Partial results → Update UI immediately (real-time feedback)
- Final results → Commit to text field
- Status updates → Update UI state

### Step 6: State Management

**States**:
```swift
enum RecognitionState {
    case idle           // Ready but not active
    case initializing   // Starting up
    case listening      // Actively recognizing
    case processing     // Finalizing result
    case stopped        // Stopped, can restart
    case cancelled      // Cancelled, needs reset
}
```

**State Transitions**:
- `idle` → `initializing` → `listening` → `processing` → `stopped`
- Can cancel from any state → `cancelled` → `idle`

### Step 7: Pre-warming Strategy

**Keep Recognizer Ready**:
- Initialize recognizer at app launch
- Request authorization early
- Don't cancel between sessions (just stop)
- Reuse recognition request when possible

**Authorization**:
```swift
func requestAuthorization() async -> Bool {
    let status = await SFSpeechRecognizer.requestAuthorization()
    return status == .authorized
}
```

**Why Pre-warming Matters**:
- Authorization check can take time
- First recognition request has overhead
- Keeping recognizer ready eliminates cold-start delay

## Testing Checklist

- [ ] Speech recognizer initializes without errors
- [ ] Authorization granted
- [ ] Can start recognition immediately
- [ ] Partial results received in real-time
- [ ] Final results accurate
- [ ] Can stop/cancel gracefully
- [ ] No memory leaks
- [ ] Latency < 100ms from start to first partial result

## Performance Targets

- **Initialization**: < 100ms (includes authorization)
- **Start Recognition**: < 50ms
- **First Partial Result**: < 200ms from start
- **Result Latency**: < 100ms from speech to partial result

## Error Handling

**Common Errors**:
- `SFSpeechRecognizerError.notAuthorized` → Request permission
- `SFSpeechRecognizerError.notAvailable` → Show error message
- `SFSpeechRecognizerError.recognitionTaskUnavailable` → Retry
- Network errors → Fall back to on-device if available

**Error Recovery**:
```swift
func handleRecognitionError(_ error: Error) {
    if let speechError = error as? SFSpeechRecognizerError {
        switch speechError {
        case .notAuthorized:
            // Request authorization
        case .notAvailable:
            // Show unavailable message
        default:
            // Retry or cancel
        }
    }
}
```

## Dependencies

- `Speech` framework
- Speech recognition permission (`NSSpeechRecognitionUsageDescription`)
- Audio engine (from Phase 1)

## Integration with Audio Engine

**Shared Audio Node**:
- Both waveform and recognition use same `inputNode`
- Install two taps on same bus (supported by AVAudioEngine)
- No performance penalty for dual taps

## Next Phase

Once speech recognition is working:
→ **Phase 3**: Platform Channels (`03_PLATFORM_CHANNELS.md`)

