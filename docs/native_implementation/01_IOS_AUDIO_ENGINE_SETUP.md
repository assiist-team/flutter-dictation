# Phase 1: iOS Audio Engine Setup

## Objective

Set up `AVAudioEngine` with optimal low-latency configuration for real-time audio recording and waveform visualization.

## Goals

- ✅ Audio engine initialized and ready at app launch
- ✅ Sub-100ms latency from mic tap to recording active
- ✅ Real-time audio buffer access for waveform
- ✅ Optimal audio session configuration

## Implementation Steps

### Step 1: Create AudioEngineManager Class

**File**: `ios/Runner/AudioEngineManager.swift`

**Important**: Create this file in `ios/Runner/` (standard Flutter iOS location), NOT in `native_implementation/ios/`

**Responsibilities**:
- Initialize and configure `AVAudioEngine`
- Manage audio session (`AVAudioSession`)
- Provide audio buffer access
- Handle audio level calculation for waveform

**Key Methods**:
```swift
func initialize() throws
func startRecording() throws
func stopRecording()
func getAudioLevel() -> Float
func setBufferCallback(_ callback: @escaping (AVAudioPCMBuffer) -> Void)
```

### Step 2: Audio Session Configuration

**Critical Settings**:
```swift
// Category: Record mode for low-latency
audioSession.setCategory(.record, mode: .measurement, options: [])

// Buffer duration: 5ms for minimal latency
audioSession.setPreferredIOBufferDuration(0.005)

// Sample rate: 16kHz is sufficient for speech
audioSession.setPreferredSampleRate(16000)

// Activate session
audioSession.setActive(true)
```

**Why These Settings**:
- `.record` category: Optimized for recording
- `.measurement` mode: Low latency, minimal processing
- 5ms buffers: Balance between latency and CPU usage
- 16kHz sample rate: Standard for speech recognition

### Step 3: Audio Engine Setup

**Configuration**:
```swift
let audioEngine = AVAudioEngine()
let inputNode = audioEngine.inputNode
let inputFormat = inputNode.inputFormat(forBus: 0)

// Install tap to capture audio buffers
inputNode.installTap(
    onBus: 0,
    bufferSize: 1024,  // ~64ms at 16kHz
    format: inputFormat
) { buffer, time in
    // Process buffer for waveform
    self.processAudioBuffer(buffer)
}
```

**Buffer Size Considerations**:
- Smaller = lower latency but more CPU
- 1024 samples = ~64ms at 16kHz (good balance)
- Can reduce to 512 for even lower latency if needed

### Step 4: Pre-warming Strategy

**Initialize at App Launch**:
- Create `AudioEngineManager` instance
- Call `initialize()` but don't start recording
- Keep engine ready but idle
- This eliminates cold-start delays

**State Management**:
```swift
enum AudioEngineState {
    case idle          // Initialized, ready
    case recording     // Actively recording
    case stopped       // Stopped, can restart quickly
}
```

### Step 5: Audio Level Calculation

**For Waveform Visualization**:
```swift
func calculateAudioLevel(from buffer: AVAudioPCMBuffer) -> Float {
    guard let channelData = buffer.floatChannelData else { return 0.0 }
    
    let channelDataValue = channelData.pointee
    let channelDataValueArray = stride(
        from: 0,
        to: Int(buffer.frameLength),
        by: buffer.stride
    ).map { channelDataValue[$0] }
    
    let rms = sqrt(channelDataValueArray.map { $0 * $0 }.reduce(0, +) / Float(buffer.frameLength))
    let avgPower = 20 * log10(rms)
    
    // Normalize to 0.0 - 1.0 range
    let normalizedLevel = (avgPower + 60) / 60  // Assuming -60dB to 0dB range
    return max(0.0, min(1.0, normalizedLevel))
}
```

## Testing Checklist

- [ ] Audio engine initializes without errors
- [ ] Audio session configured correctly
- [ ] Can start/stop recording multiple times
- [ ] Audio buffers received in real-time
- [ ] Audio level calculation accurate
- [ ] No memory leaks (test with Instruments)
- [ ] Latency < 100ms from startRecording() to first buffer

## Performance Targets

- **Initialization**: < 50ms
- **Start Recording**: < 50ms
- **Buffer Latency**: < 10ms from mic to buffer callback
- **CPU Usage**: < 5% when idle, < 15% when recording

## Error Handling

**Common Issues**:
- Permission denied → Check microphone permissions
- Audio session conflict → Handle interruptions gracefully
- Engine start failure → Retry with exponential backoff

**Error Recovery**:
```swift
func handleAudioSessionInterruption(_ notification: Notification) {
    // Pause recording
    // Wait for session to resume
    // Restart recording if needed
}
```

## Dependencies

- `AVFoundation` framework
- Microphone permission (`NSMicrophoneUsageDescription`)

## Next Phase

Once audio engine is working:
→ **Phase 2**: Speech Recognizer Setup (`02_SPEECH_RECOGNIZER_SETUP.md`)

