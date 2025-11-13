# Phase 5: Migration Strategy

## Objective

Safely migrate from package-based implementation to native implementation with zero downtime and ability to rollback.

## Goals

- ✅ Feature flag to switch between implementations
- ✅ Side-by-side testing
- ✅ Gradual migration path
- ✅ Easy rollback if needed

## Implementation Steps

### Step 1: Create Feature Flag

**File**: `lib/services/dictation_service_factory.dart`

```dart
class DictationServiceFactory {
  static const bool useNativeImplementation = true;  // Feature flag
  
  static DictationServiceInterface create() {
    if (useNativeImplementation) {
      return NativeDictationService();
    } else {
      return LegacyAudioService();
    }
  }
}
```

**Or use environment variable**:
```dart
static DictationServiceInterface create() {
  const useNative = bool.fromEnvironment('USE_NATIVE_DICTATION', defaultValue: false);
  return useNative ? NativeDictationService() : LegacyAudioService();
}
```

### Step 2: Create Common Interface

**File**: `lib/services/dictation_service_interface.dart`

```dart
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
  bool isRecording(String fieldId);
  
  // For legacy compatibility
  RecorderController? getRecorderController(String fieldId);
}
```

**Implement for Both Services**:
- `NativeDictationService` implements interface
- `LegacyAudioService` wraps existing `AudioService` and implements interface

### Step 3: Wrap Legacy Service

**File**: `lib/services/legacy_dictation_service.dart`

```dart
class LegacyDictationService implements DictationServiceInterface {
  final AudioService _audioService = AudioService();
  final Map<String, RecorderController> _controllers = {};
  String? _currentFieldId;
  
  @override
  Future<void> initialize() async {
    await _audioService.initialize();
  }
  
  @override
  Future<void> startListening({
    required Function(String, bool) onResult,
    required Function(String) onStatus,
    required Function(double) onAudioLevel,
  }) async {
    _currentFieldId = 'legacy_${DateTime.now().millisecondsSinceEpoch}';
    final controller = _audioService.getRecorderController(_currentFieldId!);
    _controllers[_currentFieldId!] = controller;
    
    // Convert legacy callbacks
    await _audioService.startListening(
      fieldId: _currentFieldId!,
      onResult: (result) {
        onResult(result.recognizedWords, result.finalResult);
        if (result.finalResult) {
          onStatus('done');
        } else {
          onStatus('listening');
        }
      },
    );
    
    // Poll audio level from legacy controller
    _startAudioLevelPolling(controller, onAudioLevel);
  }
  
  void _startAudioLevelPolling(RecorderController controller, Function(double) onAudioLevel) {
    Timer.periodic(Duration(milliseconds: 16), (timer) {
      if (!controller.isRecording) {
        timer.cancel();
        return;
      }
      // Get audio level from controller if available
      // This may require checking audio_waveforms API
    });
  }
  
  @override
  Future<void> stopListening() async {
    if (_currentFieldId != null) {
      await _audioService.stopListening(_currentFieldId!);
      _currentFieldId = null;
    }
  }
  
  @override
  Future<void> cancelListening() async {
    if (_currentFieldId != null) {
      await _audioService.cancelListening(_currentFieldId!);
      _currentFieldId = null;
    }
  }
  
  @override
  bool get isReady => _audioService.isReady;
  
  @override
  bool isRecording(String fieldId) {
    return _audioService.isRecording(fieldId);
  }
  
  @override
  RecorderController? getRecorderController(String fieldId) {
    return _controllers[fieldId];
  }
}
```

### Step 4: Update Main Service

**File**: `lib/services/audio_service.dart` (Updated)

```dart
// Keep existing implementation for legacy support
// Add comment: "Legacy implementation - use DictationServiceFactory instead"

// Or rename to legacy_audio_service.dart and update imports
```

### Step 5: Update Example App

**File**: `example/lib/main.dart`

```dart
class _DictationExampleScreenState extends State<DictationExampleScreen> {
  late final DictationServiceInterface _dictationService;
  final WaveformController _waveformController = WaveformController();
  
  @override
  void initState() {
    super.initState();
    _dictationService = DictationServiceFactory.create();
    _initializeInBackground();
  }
  
  void _startListening() async {
    await _dictationService.startListening(
      onResult: _onSpeechResult,
      onStatus: _onStatusUpdate,
      onAudioLevel: (level) {
        _waveformController.updateLevel(level);
      },
    );
  }
  
  // Rest of implementation stays the same
}
```

### Step 6: A/B Testing Setup

**Add Metrics Collection**:
```dart
class DictationMetrics {
  static void recordLatency(String implementation, Duration latency) {
    // Log to analytics or local storage
    print('[$implementation] Latency: ${latency.inMilliseconds}ms');
  }
  
  static void recordError(String implementation, String error) {
    print('[$implementation] Error: $error');
  }
}
```

**In Service**:
```dart
Future<void> startListening(...) async {
  final startTime = DateTime.now();
  try {
    await _actualStartListening(...);
    final latency = DateTime.now().difference(startTime);
    DictationMetrics.recordLatency('native', latency);
  } catch (e) {
    DictationMetrics.recordError('native', e.toString());
    rethrow;
  }
}
```

### Step 7: Gradual Rollout Plan

**Phase 1: Internal Testing** (Week 1)
- Use feature flag: `useNativeImplementation = false`
- Test native implementation manually
- Fix bugs and optimize

**Phase 2: Beta Testing** (Week 2)
- Use feature flag: `useNativeImplementation = true` for beta users
- Collect metrics
- Compare latency between implementations

**Phase 3: Full Rollout** (Week 3)
- Set `useNativeImplementation = true` for all users
- Keep legacy code for 1-2 weeks as backup
- Monitor metrics

**Phase 4: Cleanup** (Week 4)
- Remove legacy code if metrics are good
- Or keep as fallback if needed

### Step 8: Rollback Plan

**If Issues Arise**:
1. Set feature flag back to `false`
2. Legacy implementation immediately available
3. No user impact
4. Investigate and fix native implementation
5. Re-enable when ready

**Emergency Rollback**:
```dart
// Quick rollback via remote config or hot fix
static DictationServiceInterface create() {
  // Check remote config or local override
  if (shouldUseLegacy()) {
    return LegacyDictationService();
  }
  return NativeDictationService();
}
```

## Testing Strategy

### Unit Tests
- Test both implementations with same test cases
- Ensure interface compatibility
- Test error handling

### Integration Tests
- Test full flow: initialize → start → stop
- Test error scenarios
- Test state transitions

### Performance Tests
- Measure latency for both implementations
- Compare CPU/memory usage
- Test under load

### User Testing
- A/B test with real users
- Collect feedback
- Measure satisfaction metrics

## Migration Checklist

- [ ] Feature flag implemented
- [ ] Common interface created
- [ ] Legacy service wrapped
- [ ] Native service implements interface
- [ ] Example app updated
- [ ] Metrics collection added
- [ ] Tests updated
- [ ] Documentation updated
- [ ] Rollback plan tested
- [ ] Performance benchmarks established

## Timeline

**Week 1**: Build native implementation
**Week 2**: Integration and testing
**Week 3**: Beta rollout with metrics
**Week 4**: Full rollout or iterate

## Risk Mitigation

**Risk**: Native implementation has bugs
- **Mitigation**: Feature flag allows instant rollback

**Risk**: Performance not better
- **Mitigation**: Keep both implementations, choose best based on metrics

**Risk**: Breaking changes for users
- **Mitigation**: Interface compatibility ensures no API changes

## Success Criteria

- ✅ Latency < 100ms (vs 3000ms current)
- ✅ No increase in error rate
- ✅ User satisfaction maintained or improved
- ✅ No performance regressions

## Next Phase

Once migration is complete:
→ **Phase 6**: Testing & Optimization (`06_TESTING_OPTIMIZATION.md`)

