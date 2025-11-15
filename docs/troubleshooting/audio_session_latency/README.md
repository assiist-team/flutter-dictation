# Audio Session Latency Fixes

This directory contains the implementation plan to fix the 300-3000ms latency issue on subsequent recording taps.

## Problem

The current implementation deactivates the audio session on every `startRecording()` call, forcing a 300-3000ms reactivation delay on subsequent taps.

**Current Behavior:**
- First tap: ~100-500ms ✅
- Second tap: ~300-3000ms ❌ (session reactivation)
- Third tap: ~300-3000ms ❌ (session reactivation)

**Target Behavior:**
- First tap: ~100-500ms ✅ (one-time session activation)
- Second tap: <100ms ✅ (engine start only)
- Third tap: <100ms ✅ (engine start only)

## Implementation Plan

The work is split into two focused documents:

### 1. [Critical Session Fixes](./01_CRITICAL_SESSION_FIXES.md)
**Must do first** - Fixes the core latency problem.

- Phase 1: Add session state tracking
- Phase 2: Remove deactivation from `startRecording()`
- Phase 3: Add active check before `setActive(true)`

**Expected Result:** Subsequent taps drop from 300-3000ms to <100ms.

### 2. [Fast Path Optimizations](./02_FAST_PATH_OPTIMIZATIONS.md)
**Do after critical fixes** - Optimizes for sub-100ms latency.

- Phase 4: Proper session lifecycle management
- Phase 5: Input format refresh strategy
- Phase 6: Engine restart path optimization
- Phase 7: App lifecycle handling

**Expected Result:** Subsequent taps achieve 20-60ms latency.

## Quick Start

1. **Start with critical fixes:**
   - Read `01_CRITICAL_SESSION_FIXES.md`
   - Implement Phases 1-3
   - Test and measure latency improvement

2. **Then optimize:**
   - Read `02_FAST_PATH_OPTIMIZATIONS.md`
   - Implement Phases 4-7
   - Test and measure final latency

## Files to Modify

- `ios/Classes/AudioEngineManager.swift` - Main implementation
- `ios/Classes/FlutterDictationPlugin.swift` - App lifecycle (if needed)

## Related Documents

- [Plan Review Findings](./PLAN_REVIEW_FINDINGS.md) - Technical review and corrections
- [Original Optimization Plan](./AUDIO_SESSION_OPTIMIZATION_PLAN.md) - Complete reference (all phases)

## Testing Checklist

- [ ] Measure latency on first tap (should be ~100-500ms)
- [ ] Measure latency on subsequent taps (should be <100ms, target 20-60ms)
- [ ] Test interruption handling (phone call, other audio apps)
- [ ] Test app backgrounding/foregrounding
- [ ] Test with different audio routes (AirPods, Bluetooth, etc.)

