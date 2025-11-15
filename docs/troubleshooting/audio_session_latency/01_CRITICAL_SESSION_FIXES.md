# Critical Session Fixes
## Fixing the 300-3000ms Latency Problem

### Problem Summary

The current implementation deactivates the audio session on every `startRecording()` call (lines 321-330), forcing a 300-3000ms reactivation delay on subsequent taps. This is the root cause of slow startup.

**Current Behavior:**
- First tap: ~100-500ms ✅
- Second tap: ~300-3000ms ❌ (session reactivation)
- Third tap: ~300-3000ms ❌ (session reactivation)

**Target Behavior:**
- First tap: ~100-500ms ✅ (one-time session activation)
- Second tap: <100ms ✅ (engine start only, no session reactivation)
- Third tap: <100ms ✅ (engine start only, no session reactivation)

---

## Phase 1: Add Session State Tracking

**Goal:** Track whether the session has been activated to avoid unnecessary reactivations.

**Changes:**
1. Add `private var isSessionActivated: Bool = false` to `AudioEngineManager`
2. Set to `true` after successful activation
3. Set to `false` only when:
   - App backgrounds (via notification)
   - Another app steals audio (via interruption)
   - User explicitly deactivates (rare)

**Files:**
- `ios/Classes/AudioEngineManager.swift`

**Implementation:**
```swift
// Add property near other state variables (around line 25)
private var isSessionActivated: Bool = false
```

---

## Phase 2: Remove Deactivation from `startRecording()`

**Goal:** Stop deactivating the session on every start - this is the critical fix.

**Changes:**
1. **Remove lines 321-330** (deactivation block) from `startRecording()`
2. **Keep session active** between recording sessions
3. Only deactivate in specific scenarios (see Phase 4 in optimization doc)

**Rationale:**
- Deactivation forces reactivation, causing 300-3000ms delay
- Fast apps never deactivate between taps
- Session can remain active safely while engine is stopped

**Files:**
- `ios/Classes/AudioEngineManager.swift` (lines 321-330)

**What to Remove:**
```swift
// DELETE THIS BLOCK (lines 321-330):
// Deactivate audio session first to ensure clean state
// This allows us to reconfigure the session properly
log("Deactivating audio session to ensure clean state...", level: .info)
do {
    try audioSession.setActive(false, options: .notifyOthersOnDeactivation)
    log("Audio session deactivated successfully", level: .info)
} catch {
    // Ignore errors when deactivating - session might not be active
    log("Warning: Failed to deactivate audio session (may not be active): \(error)", level: .warning)
}
```

---

## Phase 3: Add Active Check Before `setActive(true)`

**Goal:** Avoid calling `setActive(true)` when session is already active to prevent hardware cycles.

**Changes:**

1. **Before line 465** (`setActive(true)`), add check:
   ```swift
   // Only activate if not already active
   if !isSessionActivated {
       log("Activating audio session...", level: .info)
       let activationStartTime = CFAbsoluteTimeGetCurrent()
       do {
           try audioSession.setActive(true)
           isSessionActivated = true
           let activationDuration = (CFAbsoluteTimeGetCurrent() - activationStartTime) * 1000
           log("Audio session activated successfully in \(String(format: "%.2f", activationDuration))ms", level: .info)
           logAudioSessionState("after-activation")
       } catch let error as NSError {
           let activationDuration = (CFAbsoluteTimeGetCurrent() - activationStartTime) * 1000
           // If error is "already active", that's OK - just update flag
           if error.domain == NSOSStatusErrorDomain && error.code == Int(kAudioSessionAlreadyActive) {
               log("Session already active (system state), updating flag", level: .info)
               isSessionActivated = true
           } else {
               log("FAILED to activate audio session after \(String(format: "%.2f", activationDuration))ms: \(error)", level: .error)
               // ... existing error handling ...
               throw error
           }
       }
   } else {
       log("Session already active (tracked state), skipping activation", level: .info)
   }
   ```

2. **Update interruption handler** (line 808) with same check:
   ```swift
   case .ended:
       // Interruption ended - resume if needed
       if let optionsValue = userInfo[AVAudioSessionInterruptionOptionKey] as? UInt {
           let options = AVAudioSession.InterruptionOptions(rawValue: optionsValue)
           if options.contains(.shouldResume) && state == .recording {
               do {
                   // Only reactivate if not already active
                   if !isSessionActivated {
                       try audioSession.setActive(true)
                       isSessionActivated = true
                   }
                   try audioEngine.start()
               } catch {
                   log("Failed to resume after interruption: \(error)", level: .error)
                   state = .stopped
               }
           }
       }
   ```

**Rationale:**
- Calling `setActive(true)` on an already-active session can trigger 400-3000ms hardware cycle
- Check prevents unnecessary activation calls
- **IMPORTANT**: Do NOT use `isOtherAudioPlaying` - it indicates if OTHER apps are playing, not if YOUR session is active
- Handle the case where iOS might have activated session without our knowledge

**Files:**
- `ios/Classes/AudioEngineManager.swift` (lines 445-497, 788-820)

---

## Implementation Checklist

- [ ] **Phase 1:** Add `isSessionActivated: Bool` flag to `AudioEngineManager`
- [ ] **Phase 2:** Remove deactivation block from `startRecording()` (lines 321-330)
- [ ] **Phase 3:** Add active check before `setActive(true)` at line 465
- [ ] **Phase 3:** Update interruption handler at line 808 with active check
- [ ] **Phase 3:** Add error handling for "already active" errors

---

## Expected Results After Critical Fixes

**Before:**
- First tap: ~100-500ms ✅
- Second tap: ~300-3000ms ❌ (session reactivation)
- Third tap: ~300-3000ms ❌ (session reactivation)

**After:**
- First tap: ~100-500ms ✅ (one-time session activation + engine start)
- Second tap: <100ms ✅ (engine start only, no session reactivation)
- Third tap: <100ms ✅ (engine start only, no session reactivation)

**Breakdown for subsequent taps:**
- Engine start: ~10-30ms
- Total: ~10-30ms (10-300x faster than current)

---

## Important Notes

1. **No Direct "isActive" Property:**
   - iOS doesn't provide `audioSession.isActive`
   - **IMPORTANT**: `isOtherAudioPlaying` tells you if OTHER apps are playing, NOT if YOUR session is active
   - Track state with `isSessionActivated` flag
   - Handle errors gracefully when calling `setActive(true)` - iOS might have changed state

2. **Testing Priority:**
   - Focus on these critical fixes first
   - Measure before/after latency to validate
   - Test interruption handling (phone call, other audio apps)

---

## Next Steps

After completing these critical fixes, proceed to:
- **02_FAST_PATH_OPTIMIZATIONS.md** - Format refresh, warm-up pattern, and lifecycle optimizations

