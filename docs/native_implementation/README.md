# Native iOS Dictation Implementation

This directory contains the planning and implementation for rebuilding the dictation feature with native iOS code to achieve sub-100ms latency.

## Overview

The native implementation replaces the Flutter package-based approach (`speech_to_text` + `audio_waveforms`) with direct iOS APIs (`AVAudioEngine` + `SFSpeechRecognizer`) for optimal performance.

## Goals

- **Sub-100ms latency** from mic tap to recording active
- **Real-time waveform visualization** without package dependencies
- **Production-ready** implementation with comprehensive testing

## Planning Documents

The implementation is broken into phases, each with its own planning document:

1. **[00_WORKSPACE_REORGANIZATION.md](00_WORKSPACE_REORGANIZATION.md)** - Workspace structure and migration plan
2. **[01_IOS_AUDIO_ENGINE_SETUP.md](01_IOS_AUDIO_ENGINE_SETUP.md)** - Native audio engine implementation
3. **[02_SPEECH_RECOGNIZER_SETUP.md](02_SPEECH_RECOGNIZER_SETUP.md)** - Speech recognition setup
4. **[03_PLATFORM_CHANNELS.md](03_PLATFORM_CHANNELS.md)** - Flutter integration via platform channels
5. **[04_WAVEFORM_STREAMING.md](04_WAVEFORM_STREAMING.md)** - Real-time waveform visualization
6. **[05_MIGRATION_STRATEGY.md](05_MIGRATION_STRATEGY.md)** - Safe migration from legacy implementation
7. **[06_TESTING_OPTIMIZATION.md](06_TESTING_OPTIMIZATION.md)** - Testing and performance optimization
8. **[PARALLEL_IMPLEMENTATION.md](PARALLEL_IMPLEMENTATION.md)** - ⚡ Guide for parallelizing phases to save time

## Architecture

### Native iOS (Swift) - Code Location: `ios/Runner/`
- `DictationManager.swift` - Main coordinator (in `ios/Runner/`)
- `AudioEngineManager.swift` - Audio recording and processing (in `ios/Runner/`)
- `SpeechRecognizerManager.swift` - Speech recognition (in `ios/Runner/`)

**Note**: Native code goes in `ios/Runner/` (standard Flutter location), NOT in `native_implementation/ios/`

### Flutter (Dart) - Code Location: `lib/services/`
- `NativeDictationService` - Platform channel interface (in `lib/services/`)
- `WaveformController` - Waveform state management (in `lib/services/`)
- `NativeWaveform` - Custom waveform widget (in `lib/widgets/`)

**Note**: This directory (`native_implementation/`) contains PLANNING DOCS only, not actual code!

## Implementation Status

- [ ] Phase 1: Audio Engine Setup
- [ ] Phase 2: Speech Recognizer Setup
- [ ] Phase 3: Platform Channels
- [ ] Phase 4: Waveform Streaming
- [ ] Phase 5: Migration Strategy
- [ ] Phase 6: Testing & Optimization

## Getting Started

1. Review workspace reorganization plan (`00_WORKSPACE_REORGANIZATION.md`)
2. **Check parallel opportunities** (`PARALLEL_IMPLEMENTATION.md`) - Can save 3-6 hours!
3. Follow phases (some can be done in parallel - see guide)
4. Test each phase before moving to next
5. Use feature flag to switch between implementations

## Key Optimizations

1. **Pre-warming**: Initialize resources at app launch
2. **Parallel Operations**: Start recording and recognition simultaneously
3. **Optimal Audio Session**: Configure for low-latency recording
4. **Direct Buffer Access**: Real-time audio processing
5. **Smart State Management**: Minimize state transitions

## Performance Targets

- **Cold Start Latency**: < 100ms
- **Warm Start Latency**: < 50ms
- **First Result Latency**: < 200ms
- **CPU Usage**: < 15% when recording
- **Memory**: Stable, no leaks

## Migration Path

1. Build native implementation alongside legacy
2. Use feature flag to switch between implementations
3. A/B test with metrics collection
4. Gradual rollout
5. Remove legacy code once proven

## Resources

- [AVAudioEngine Documentation](https://developer.apple.com/documentation/avfaudio/avaudioengine)
- [SFSpeechRecognizer Documentation](https://developer.apple.com/documentation/speech/sfspeechrecognizer)
- [Flutter Platform Channels](https://docs.flutter.dev/development/platform-integration/platform-channels)

