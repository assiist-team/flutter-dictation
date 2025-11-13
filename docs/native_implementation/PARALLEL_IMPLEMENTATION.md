# Parallel Implementation Guide

## Overview

Some phases can be implemented in parallel to speed up development. This guide shows what can be done concurrently and what must be sequential.

## Dependency Graph

```
Phase 1 (Audio Engine)
    ↓
Phase 2 (Speech Recognizer) ──┐
    ↓                          │
Phase 3 (Platform Channels) ←─┘
    ↓                          ↓
Phase 4 (Waveform Streaming)  Phase 5 (Migration)
    ↓                          ↓
Phase 6 (Testing & Optimization)
```

## Sequential Phases (Must Do In Order)

### Phase 1 → Phase 2 → Phase 3
**Why Sequential:**
- Phase 2 needs `AudioEngineManager` from Phase 1
- Phase 3 needs both `AudioEngineManager` and `SpeechRecognizerManager` from Phases 1 & 2

**Cannot be parallelized** - Core native implementation must be sequential.

## Parallel Opportunities

### ✅ Opportunity 1: Phase 5 Infrastructure (Early)

**What**: Design and build the interface and factory pattern

**Can Start**: Immediately (before Phase 1)

**Files to Create**:
- `lib/services/dictation_service_interface.dart` - Define the interface contract
- `lib/services/dictation_service_factory.dart` - Factory pattern (with feature flag)

**Why Parallel**:
- Pure Dart code, no dependencies
- Defines the contract that Phase 3 will implement
- Can be done while Phase 1/2 are being built
- Helps clarify requirements early

**Implementation**:
```dart
// lib/services/dictation_service_interface.dart
abstract class DictationServiceInterface {
  Future<void> initialize();
  Future<void> startListening({
    required Function(String, bool) onResult,
    required Function(String) onStatus,
    required Function(double) onAudioLevel,
  });
  Future<void> stopListening();
  Future<void> cancelListening();
  bool get isReady;
}

// lib/services/dictation_service_factory.dart
class DictationServiceFactory {
  static DictationServiceInterface create() {
    // Will implement later, but structure is ready
    throw UnimplementedError('Native service not yet implemented');
  }
}
```

**Time Saved**: 1-2 hours (can do while waiting for native code)

---

### ✅ Opportunity 2: Phase 4 Dart Side (Early)

**What**: Build WaveformController and NativeWaveform widget

**Can Start**: After Phase 3 starts (once event channel structure is known)

**Files to Create**:
- `lib/services/waveform_controller.dart` - State management
- `lib/widgets/native_waveform.dart` - Custom widget
- `lib/widgets/waveform_painter.dart` - Custom painter

**Why Parallel**:
- Pure Dart/Flutter code
- Can use mock data for testing
- Only needs to know it will receive `double` values via stream
- Can be built while Phase 3 is being completed

**Implementation**:
```dart
// Can build with mock stream for testing
class WaveformController extends ChangeNotifier {
  // Implementation doesn't need real audio data yet
  void updateLevel(double level) {
    // Can test with mock values: 0.0 to 1.0
  }
}
```

**Time Saved**: 2-3 hours (can do while Phase 3 is wrapping up)

---

### ✅ Opportunity 3: Phase 5 Legacy Wrapper (Early)

**What**: Wrap the existing AudioService to implement the interface

**Can Start**: After interface is defined (Opportunity 1)

**Files to Create**:
- `lib/services/legacy_dictation_service.dart` - Wrapper around existing AudioService

**Why Parallel**:
- Can be built once interface is defined
- Doesn't need native code
- Useful for testing the interface design
- Can be done while Phases 1-3 are being built

**Time Saved**: 1-2 hours

---

### ✅ Opportunity 4: Phase 6 Test Structure (Early)

**What**: Set up test infrastructure and write test stubs

**Can Start**: After interface is defined (Opportunity 1)

**Files to Create**:
- `test/services/dictation_service_interface_test.dart` - Interface contract tests
- `test/services/native_dictation_service_test.dart` - Test structure (stubs)
- `test/performance/latency_test.dart` - Performance test structure

**Why Parallel**:
- Test structure can be defined early
- Tests can be written as stubs and filled in later
- Helps clarify requirements
- Can be done while native code is being built

**Time Saved**: 1-2 hours

---

## Recommended Parallel Workflow

### Week 1: Foundation (Parallel)

**Day 1-2:**
- ✅ **Phase 1** (Audio Engine) - 4-6 hours
- ✅ **Phase 5 Step 2** (Interface) - 1 hour (parallel)
- ✅ **Phase 5 Step 3** (Legacy Wrapper) - 1-2 hours (parallel)

**Day 3-4:**
- ✅ **Phase 2** (Speech Recognizer) - 4-6 hours
- ✅ **Phase 6 Test Structure** - 1-2 hours (parallel)

**Day 5:**
- ✅ **Phase 3** (Platform Channels) - 4-6 hours
- ✅ **Phase 4 Dart Side** - 2-3 hours (parallel, start after Phase 3 structure is clear)

### Week 2: Integration & Polish

**Day 1-2:**
- ✅ **Phase 4 Native Side** (audio level streaming) - 2-3 hours
- ✅ **Phase 5 Migration** (complete) - 1 hour
- ✅ **Phase 6 Testing** (fill in tests) - 2-3 hours

**Day 3-5:**
- ✅ **Phase 6 Optimization** - 4-6 hours
- ✅ **Integration testing**
- ✅ **Performance tuning**

## Time Savings

**Sequential Approach**: 21-31 hours
**Parallel Approach**: ~18-25 hours

**Time Saved**: ~3-6 hours (15-20% faster)

## Critical Path

Even with parallelization, the critical path is:
1. Phase 1 (Audio Engine)
2. Phase 2 (Speech Recognizer)
3. Phase 3 (Platform Channels)
4. Phase 4 Native Side (audio streaming)
5. Phase 6 (Testing)

**Minimum Time**: ~18-22 hours (cannot go faster than this)

## Best Practices

1. **Start with Interface** - Define `DictationServiceInterface` first
2. **Build Dart Side Early** - Waveform widgets can be built with mocks
3. **Test Structure First** - Set up tests early, fill in later
4. **Legacy Wrapper Early** - Helps validate interface design
5. **Native Code Sequential** - Phases 1-3 must be sequential

## Risk Mitigation

**Risk**: Building Dart side before native side might need changes
**Mitigation**: 
- Use well-defined interfaces
- Keep changes minimal
- Test with mocks first

**Risk**: Interface might need changes after native implementation
**Mitigation**:
- Start with interface early
- Review with native implementation in mind
- Keep interface simple and focused

## Summary

**Can Be Parallel:**
- ✅ Phase 5 Infrastructure (interface, factory)
- ✅ Phase 4 Dart Side (widgets, controller)
- ✅ Phase 5 Legacy Wrapper
- ✅ Phase 6 Test Structure

**Must Be Sequential:**
- ❌ Phase 1 → Phase 2 → Phase 3 (native code)
- ❌ Phase 4 Native Side (needs Phase 3)
- ❌ Phase 6 Final Testing (needs everything)

**Recommendation**: Start Phase 5 infrastructure and test structure early while building Phases 1-3 sequentially. This can save 3-6 hours without adding risk.

