# Native iOS Dictation Rebuild Plan

## Why Rebuild?

The current Flutter package-based approach has fundamental latency limitations:
- Package abstraction layers add overhead
- Sequential operations prevent parallelization
- No direct control over iOS audio session configuration
- Method channel delays for critical paths

A native iOS implementation can achieve **sub-100ms latency** by directly controlling `AVAudioEngine` and `SFSpeechRecognizer`.

## Architecture

### Flutter Side (Dart)
- **NativeDictationService** - Platform channel interface
- **DictationController** - State management and callbacks
- **WaveformGenerator** - Process audio buffers for visualization
- **UI Components** - Reuse existing widgets

### iOS Native Side (Swift)
- **DictationManager** - Main coordinator class
- **AudioEngineManager** - Handles AVAudioEngine setup and recording
- **SpeechRecognizerManager** - Handles SFSpeechRecognizer
- **AudioSessionManager** - Optimized AVAudioSession configuration

## Key Optimizations

### 1. Pre-warming Strategy
- Initialize `AVAudioEngine` and `SFSpeechRecognizer` at app launch
- Keep audio engine running (but not recording) in background
- Pre-configure audio session with optimal settings

### 2. Parallel Operations
- Start audio recording and speech recognition **simultaneously**
- No sequential waits - both operations begin on mic tap
- Use completion handlers to coordinate state

### 3. Audio Session Configuration
```swift
// Configure for low-latency recording
try audioSession.setCategory(.record, mode: .measurement, options: [])
try audioSession.setPreferredIOBufferDuration(0.005) // 5ms buffers
try audioSession.setActive(true)
```

### 4. Direct Audio Buffer Access
- Process audio buffers directly for waveform visualization
- No file I/O delays
- Real-time audio processing

### 5. Smart State Management
- Keep recognizer ready (not cancelled) between sessions
- Reuse audio engine instances
- Minimize state transitions

## Implementation Steps

### Phase 1: Core Native Implementation
1. Create Swift `DictationManager` class
2. Set up `AVAudioEngine` with optimal configuration
3. Set up `SFSpeechRecognizer` with dictation mode
4. Implement platform channel methods:
   - `initialize()`
   - `startListening()`
   - `stopListening()`
   - `cancelListening()`
   - `getAudioLevel()` (for waveform)

### Phase 2: Flutter Integration
1. Create `NativeDictationService` Dart class
2. Set up method channels
3. Implement callbacks for:
   - Speech recognition results
   - Status updates
   - Audio level updates
4. Integrate with existing UI components

### Phase 3: Waveform Visualization
1. Stream audio buffer data from native side
2. Process buffers in Dart for waveform display
3. Optimize for real-time rendering

### Phase 4: Testing & Optimization
1. Measure latency: tap → recording active
2. Target: <100ms cold start, <50ms warm start
3. Profile with Instruments
4. Optimize hot paths

## Migration Path

1. **Keep existing code** - Don't delete yet
2. **Build native implementation** alongside current code
3. **Feature flag** - Switch between implementations
4. **A/B test** - Compare latency metrics
5. **Migrate** - Once native proves superior

## Benefits

- ✅ **Sub-100ms latency** - Achievable with direct control
- ✅ **Better performance** - No package overhead
- ✅ **Full control** - Optimize every aspect
- ✅ **Future-proof** - Easy to add features
- ✅ **iOS-optimized** - Use platform best practices

## Trade-offs

- ⚠️ **More code** - Need to maintain native code
- ⚠️ **iOS-only initially** - Android would need separate implementation
- ⚠️ **More complex** - Direct audio/speech management

## Recommendation

**YES - Rebuild with native implementation.** The latency requirement is critical, and the current package-based approach has fundamental limitations that can't be worked around. A native implementation gives you the control needed to achieve professional-grade dictation latency.

