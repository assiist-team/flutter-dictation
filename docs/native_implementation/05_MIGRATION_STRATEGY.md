# Phase 5: Implementation Strategy

## Objective

Build and deploy the native iOS dictation implementation as the primary (and only) implementation.

## Key Simplification

**No Migration Needed**: Since there are no existing products using the legacy implementation, we can build the native implementation directly without migration complexity. This eliminates the need for:
- Feature flags to switch between implementations
- Side-by-side testing of both implementations
- Gradual rollout plans
- Rollback mechanisms
- Legacy compatibility layers

## Implementation Approach

### Direct Native Implementation

Since we're building fresh without migration concerns, we can:

1. **Build the native implementation directly** - Focus on getting the native iOS implementation working correctly
2. **Use the native service as the primary API** - No need for abstraction layers or factories
3. **Remove legacy code when ready** - Once native implementation is stable, clean up legacy code
4. **Keep legacy code for reference only** - The code in `legacy/` directory serves as reference, not as a fallback

### Implementation Steps

#### Step 1: Complete Native Implementation

**File**: `lib/services/native_dictation_service.dart` (Already exists)

The `NativeDictationService` is the primary service. Ensure it:
- ✅ Handles initialization
- ✅ Manages listening lifecycle
- ✅ Streams results and audio levels
- ✅ Handles errors gracefully

#### Step 2: Update Example App

**File**: `example/lib/main.dart`

Update the example app to use `NativeDictationService` directly:

```dart
class _DictationExampleScreenState extends State<DictationExampleScreen> {
  late final NativeDictationService _dictationService;
  final WaveformController _waveformController = WaveformController();
  
  @override
  void initState() {
    super.initState();
    _dictationService = NativeDictationService();
    _initializeInBackground();
  }
  
  Future<void> _initializeInBackground() async {
    try {
      await _dictationService.initialize();
    } catch (e) {
      print('Failed to initialize dictation: $e');
    }
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
  
  // Rest of implementation
}
```

#### Step 3: Clean Up Legacy Code

Once the native implementation is stable and tested:

1. **Remove legacy service from active code** - The `lib/services/audio_service.dart` can be removed or moved to `legacy/` if not already there
2. **Update documentation** - Remove references to migration/feature flags
3. **Update README** - Reflect that native implementation is the only implementation

**Note**: Keep `legacy/` directory for reference purposes, but it's not part of the active codebase.

## Testing Strategy

### Unit Tests
- Test native service initialization
- Test listening lifecycle (start/stop/cancel)
- Test error handling
- Test event streaming

### Integration Tests
- Test full flow: initialize → start → receive results → stop
- Test error scenarios (permissions denied, etc.)
- Test state transitions
- Test cleanup and disposal

### Performance Tests
- Measure latency: target < 100ms from mic tap to recording active
- Measure CPU/memory usage: target < 15% CPU when recording
- Test under various conditions (background/foreground, interruptions)

### Manual Testing
- Test on physical devices (simulator may not reflect real performance)
- Test with various audio conditions
- Test edge cases (rapid start/stop, interruptions, etc.)

## Implementation Checklist

- [ ] Native iOS implementation complete (Phases 1-4)
- [ ] Platform channels working correctly
- [ ] Example app updated to use native service
- [ ] Unit tests written and passing
- [ ] Integration tests written and passing
- [ ] Performance benchmarks meet targets (< 100ms latency)
- [ ] Error handling tested and working
- [ ] Documentation updated
- [ ] Legacy code cleaned up (moved to `legacy/` or removed)

## Timeline

**Week 1**: Complete native implementation (Phases 1-4)
**Week 2**: Testing and bug fixes
**Week 3**: Performance optimization and polish
**Week 4**: Documentation and cleanup

## Success Criteria

- ✅ Latency < 100ms (vs 3000ms legacy)
- ✅ Stable and reliable operation
- ✅ Good error handling and user feedback
- ✅ Clean, maintainable code
- ✅ Comprehensive test coverage

## Why This Is Simpler

Without migration concerns, we can:

1. **Focus on quality** - Spend time making the native implementation excellent rather than maintaining compatibility layers
2. **Simpler architecture** - No need for factories, interfaces, or abstraction layers just for migration
3. **Faster development** - No time spent on migration tooling and testing both implementations
4. **Cleaner codebase** - One implementation path, easier to understand and maintain

## Legacy Code Reference

The `legacy/` directory contains the old package-based implementation for reference purposes only. It's useful for:
- Understanding the original approach
- Comparing performance improvements
- Reference during development if needed

However, it's **not** part of the active codebase and doesn't need to be maintained or kept compatible.

## Next Phase

Once implementation is complete:
→ **Phase 6**: Testing & Optimization (`06_TESTING_OPTIMIZATION.md`)

