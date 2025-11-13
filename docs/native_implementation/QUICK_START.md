# Quick Start Guide

## Overview

This guide helps you get started with the native iOS dictation implementation. Follow these steps in order.

## Step 1: Review Workspace Reorganization

**Read**: `00_WORKSPACE_REORGANIZATION.md`

**Action**: Decide if you want to reorganize now or later. The reorganization is optional but recommended for a cleaner workspace.

**Quick Reorganization** (if desired):
```bash
# Create directories
mkdir -p legacy/lib/services
mkdir -p docs

# Move legacy code (manual step - be careful!)
# cp lib/services/audio_service.dart legacy/lib/services/

# Planning docs already moved to docs/
```

## Step 2: Start Implementation

**Note**: Some phases can be done in parallel! See `PARALLEL_IMPLEMENTATION.md` for details.

Follow the phases (some can be parallel):

### Phase 1: Audio Engine
**File**: `01_IOS_AUDIO_ENGINE_SETUP.md`
- Create `native_implementation/ios/AudioEngineManager.swift`
- Set up `AVAudioEngine` with optimal configuration
- Test audio recording works

**Estimated Time**: 4-6 hours

### Phase 2: Speech Recognizer
**File**: `02_SPEECH_RECOGNIZER_SETUP.md`
- Create `native_implementation/ios/SpeechRecognizerManager.swift`
- Set up `SFSpeechRecognizer`
- Integrate with audio engine

**Estimated Time**: 4-6 hours

### Phase 3: Platform Channels
**File**: `03_PLATFORM_CHANNELS.md`
- Create `ios/Runner/DictationManager.swift`
- Set up method channels and event channels
- Create `lib/services/native_dictation_service.dart`

**Estimated Time**: 4-6 hours

### Phase 4: Waveform Streaming
**File**: `04_WAVEFORM_STREAMING.md`
- Stream audio levels from native to Flutter
- Create waveform controller and widget
- Replace `audio_waveforms` dependency

**Estimated Time**: 3-4 hours

### Phase 5: Migration
**File**: `05_MIGRATION_STRATEGY.md`
- Create feature flag
- Wrap legacy service
- Update example app

**Estimated Time**: 2-3 hours

### Phase 6: Testing & Optimization
**File**: `06_TESTING_OPTIMIZATION.md`
- Write tests
- Measure performance
- Optimize hot paths

**Estimated Time**: 4-6 hours

## Total Estimated Time

**Sequential**: 21-31 hours (~1 week)
**With Parallelization**: 18-25 hours (~4-5 days)

See `PARALLEL_IMPLEMENTATION.md` for parallel opportunities that can save 3-6 hours.

## Key Files to Create

### Native iOS (Swift)
- `ios/Runner/DictationManager.swift` - Main coordinator
- `ios/Runner/AudioEngineManager.swift` - Audio handling
- `ios/Runner/SpeechRecognizerManager.swift` - Speech recognition

### Flutter (Dart)
- `lib/services/native_dictation_service.dart` - Platform channel interface
- `lib/services/dictation_service_interface.dart` - Common interface
- `lib/services/dictation_service_factory.dart` - Factory with feature flag
- `lib/services/waveform_controller.dart` - Waveform state
- `lib/widgets/native_waveform.dart` - Custom waveform widget

## Testing Strategy

1. **After each phase**: Test that phase's functionality
2. **Integration**: Test phases work together
3. **Performance**: Measure latency at each step
4. **Final**: Comprehensive testing before migration

## Common Issues & Solutions

### Issue: Audio not recording
- Check microphone permissions
- Verify audio session configuration
- Check audio engine state

### Issue: Speech recognition not working
- Check speech recognition permissions
- Verify recognizer initialization
- Check locale settings

### Issue: High latency
- Profile with Instruments
- Check for sequential operations
- Optimize buffer sizes
- Verify pre-warming is working

### Issue: Memory leaks
- Use Instruments Leaks tool
- Check for retain cycles
- Verify proper cleanup

## Getting Help

- Review phase-specific docs for detailed guidance
- Check iOS documentation for API details
- Use Instruments for profiling
- Test incrementally after each phase

## Next Steps

1. Start with Phase 1 (Audio Engine)
2. Test thoroughly before moving to Phase 2
3. Continue through phases sequentially
4. Use feature flag to test both implementations
5. Migrate when ready

Good luck! 🚀

