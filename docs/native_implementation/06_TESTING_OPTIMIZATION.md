# Phase 6: Testing & Optimization

## Objective

Thoroughly test the native implementation, measure performance, and optimize for production readiness.

## Goals

- ✅ Comprehensive test coverage
- ✅ Performance benchmarks met (< 100ms latency)
- ✅ Memory and CPU usage optimized
- ✅ Production-ready code quality

## Testing Strategy

### 1. Unit Tests

**File**: `test/services/native_dictation_service_test.dart`

**Test Cases**:
```dart
void main() {
  group('NativeDictationService', () {
    test('initializes successfully', () async {
      final service = NativeDictationService();
      await service.initialize();
      expect(service.isReady, isTrue);
    });
    
    test('starts listening and receives results', () async {
      final service = NativeDictationService();
      await service.initialize();
      
      String? receivedText;
      bool? isFinal;
      
      await service.startListening(
        onResult: (text, finalResult) {
          receivedText = text;
          isFinal = finalResult;
        },
        onStatus: (_) {},
        onAudioLevel: (_) {},
      );
      
      // Wait for result (mock or real)
      await Future.delayed(Duration(seconds: 2));
      
      expect(receivedText, isNotNull);
    });
    
    test('stops listening correctly', () async {
      // Test stop functionality
    });
    
    test('handles errors gracefully', () async {
      // Test error scenarios
    });
  });
}
```

### 2. Integration Tests

**File**: `test/integration/dictation_integration_test.dart`

**Test Scenarios**:
- Full flow: initialize → start → speak → stop
- Multiple start/stop cycles
- Error recovery
- State transitions
- Memory leaks

### 3. Performance Tests

**File**: `test/performance/latency_test.dart`

**Measure Latency**:
```dart
void main() {
  test('start listening latency < 100ms', () async {
    final service = NativeDictationService();
    await service.initialize();
    
    final startTime = DateTime.now();
    await service.startListening(
      onResult: (_, __) {},
      onStatus: (_) {},
      onAudioLevel: (_) {},
    );
    final latency = DateTime.now().difference(startTime);
    
    expect(latency.inMilliseconds, lessThan(100));
  });
  
  test('first result latency < 200ms', () async {
    // Measure time from start to first partial result
  });
  
  test('warm start latency < 50ms', () async {
    // Measure latency after previous session
  });
}
```

### 4. Manual Testing Checklist

**Basic Functionality**:
- [ ] Initialize works
- [ ] Start listening works
- [ ] Speech recognition works
- [ ] Partial results appear
- [ ] Final results appear
- [ ] Stop works
- [ ] Cancel works
- [ ] Waveform displays

**Edge Cases**:
- [ ] App backgrounded during recording
- [ ] Phone call interrupts recording
- [ ] Permission denied
- [ ] Network unavailable (on-device fallback)
- [ ] Multiple rapid start/stop cycles
- [ ] Long recording sessions (> 5 minutes)

**Performance**:
- [ ] Latency < 100ms cold start
- [ ] Latency < 50ms warm start
- [ ] CPU usage < 15% when recording
- [ ] Memory usage stable (no leaks)
- [ ] Battery impact acceptable

## Optimization Areas

### 1. Latency Optimization

**Measure Each Component**:
```swift
// Add timing logs
let startTime = CFAbsoluteTimeGetCurrent()
// ... operation ...
let duration = (CFAbsoluteTimeGetCurrent() - startTime) * 1000
print("Operation took \(duration)ms")
```

**Optimize Hot Paths**:
- Audio engine start
- Speech recognizer start
- First buffer processing
- First result delivery

**Target Breakdown**:
- Audio engine start: < 20ms
- Speech recognizer start: < 30ms
- First buffer: < 10ms
- First result: < 150ms
- **Total**: < 100ms

### 2. Memory Optimization

**Check for Leaks**:
- Use Instruments Leaks tool
- Test long recording sessions
- Test multiple start/stop cycles
- Check for retain cycles

**Memory Targets**:
- Base memory: < 50MB
- Recording overhead: < 20MB
- Waveform data: < 5MB

**Optimization Techniques**:
```swift
// Use weak references
weak var delegate: DictationDelegate?

// Release buffers promptly
buffer = nil

// Limit waveform history
if waveformData.count > maxSamples {
    waveformData.removeFirst()
}
```

### 3. CPU Optimization

**Profile with Instruments**:
- Time Profiler to find hotspots
- Energy Log to check battery impact
- System Trace for system calls

**CPU Targets**:
- Idle: < 1%
- Recording: < 15%
- Processing: < 25%

**Optimization Techniques**:
- Reduce audio level update frequency if needed
- Optimize audio buffer processing
- Use efficient data structures
- Minimize allocations in hot paths

### 4. Battery Optimization

**Measure Battery Impact**:
- Test 30-minute recording session
- Monitor battery drain
- Compare to baseline

**Optimization Techniques**:
- Reduce unnecessary processing
- Optimize update frequencies
- Use efficient algorithms
- Minimize network usage (prefer on-device)

## Benchmarking

### Create Benchmark Suite

**File**: `test/benchmarks/dictation_benchmarks.dart`

```dart
void main() {
  group('Performance Benchmarks', () {
    test('cold start latency', () async {
      // Measure cold start
    });
    
    test('warm start latency', () async {
      // Measure warm start
    });
    
    test('result latency', () async {
      // Measure time to first result
    });
    
    test('memory usage', () async {
      // Measure memory footprint
    });
    
    test('CPU usage', () async {
      // Measure CPU during recording
    });
  });
}
```

### Baseline Comparison

**Compare Against Legacy**:
- Latency: 3000ms → < 100ms (30x improvement)
- CPU: Similar or better
- Memory: Similar or better
- Battery: Similar or better

## Code Quality

### Linting

**Swift**:
- Use SwiftLint
- Follow Swift style guide
- Fix all warnings

**Dart**:
- Run `flutter analyze`
- Fix all linter warnings
- Follow Dart style guide

### Documentation

**Code Comments**:
- Document public APIs
- Explain complex logic
- Add performance notes

**README Updates**:
- Update main README
- Document new architecture
- Add performance metrics

### Error Handling

**Comprehensive Error Handling**:
```swift
enum DictationError: Error {
    case notAuthorized
    case notAvailable
    case audioEngineFailed
    case recognitionFailed
    
    var localizedDescription: String {
        switch self {
        case .notAuthorized:
            return "Speech recognition not authorized"
        // ... other cases
        }
    }
}
```

## Production Readiness Checklist

### Functionality
- [ ] All features working
- [ ] Error handling comprehensive
- [ ] Edge cases handled
- [ ] State management correct

### Performance
- [ ] Latency < 100ms
- [ ] CPU usage acceptable
- [ ] Memory usage stable
- [ ] Battery impact acceptable

### Quality
- [ ] Tests passing
- [ ] No memory leaks
- [ ] No crashes
- [ ] Code reviewed
- [ ] Documentation complete

### Deployment
- [ ] Feature flag ready
- [ ] Rollback plan tested
- [ ] Monitoring in place
- [ ] Metrics collection working

## Monitoring

### Metrics to Track

**Performance**:
- Start latency (cold/warm)
- Result latency
- Error rate
- CPU usage
- Memory usage

**User Experience**:
- Success rate
- User satisfaction
- Crash rate
- Battery impact

### Logging

**Structured Logging**:
```swift
func logEvent(_ event: String, metadata: [String: Any] = [:]) {
    // Log to analytics or crash reporting
    print("[Dictation] \(event): \(metadata)")
}
```

## Iteration Plan

**If Targets Not Met**:

1. **Profile** - Use Instruments to find bottlenecks
2. **Optimize** - Fix identified issues
3. **Re-test** - Verify improvements
4. **Iterate** - Repeat until targets met

**Common Optimizations**:
- Reduce buffer sizes
- Optimize audio processing
- Cache frequently used objects
- Minimize allocations
- Use more efficient algorithms

## Success Criteria

- ✅ Latency < 100ms (cold start)
- ✅ Latency < 50ms (warm start)
- ✅ CPU < 15% (recording)
- ✅ Memory stable (no leaks)
- ✅ All tests passing
- ✅ Production ready

## Next Steps

Once testing and optimization complete:
1. Enable feature flag for production
2. Monitor metrics
3. Gather user feedback
4. Iterate based on data

