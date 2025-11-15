# Audio Session Optimization: Eliminating First-Call Delay

## Problem Summary

The current implementation has a ~2.6 second delay on the **first** call to `startRecording()`. While subsequent calls are fast (~10-50ms), this initial delay is unacceptable for a dictation feature where users expect immediate response.

### Current Behavior

- **First call**: ~2.6 seconds delay (unacceptable)
- **Subsequent calls**: ~10-50ms (acceptable)

### Root Cause

The delay occurs because:
1. The audio session starts with a default category (typically `.soloAmbient` or `.ambient`)
2. When `startRecording()` is called, it needs to change the category to `.record` with mode `.measurement`
3. Changing the category requires deactivating the session, changing the category, then reactivating
4. This deactivation/reactivation cycle takes ~2.6 seconds

### Current Implementation Issue

The code comment at `ios/Classes/AudioEngineManager.swift:59-61` states:

```swift
// Don't configure audio session category here - it requires microphone permission.
// We'll configure it in startRecording() after permission is granted.
// This allows the app to initialize successfully even without permissions.
```

**This comment is incorrect.** Setting the audio session category does **NOT** require microphone permission. Only **activating** the session requires permission. We can safely set the category during initialization without any permission checks.

## Current Status

**⚠️ WORK IN PROGRESS** - Multiple approaches attempted, solution still being refined.

### What's Been Tried

1. ✅ **Pre-configure category during initialization** - Successfully implemented, category is set early
2. ✅ **Pre-configure buffer duration/sample rate** - Successfully implemented, settings are set early  
3. ✅ **Increase buffer duration tolerance** - Fixed to 5ms to account for iOS rounding
4. ❌ **Skip activation when session already active** - FAILED: Audio engine needs activation to get input format

### Current Issue

Even with all settings pre-configured correctly, calling `setActive(true)` on an already-active session still takes ~2.6 seconds. We cannot skip activation because the audio engine requires it to get valid input format information.

### Next Steps

Need to find a way to make activation fast even when the session is already active, or activate during initialization before the first tap.

## Solution: Pre-Configure Category During Initialization

### Key Insight

We can set the audio session category to `.record` during `initialize()` without requiring permission. This eliminates the need to change categories when `startRecording()` is called, removing the ~2.6 second delay.

### Implementation Strategy

1. **During `initialize()`**: Set the audio session category to `.record` with mode `.measurement` (no activation, no permission needed)
2. **During `startRecording()`**: 
   - Check if category is already `.record` (it should be)
   - Skip deactivation if category is correct
   - Activate the session (fast operation, ~10-50ms)
   - Request permission if needed

### Benefits

- **First call**: ~10-50ms (same as subsequent calls)
- **Subsequent calls**: ~10-50ms (unchanged)
- **No user-facing delay**: Recording starts immediately after permission is granted

## Implementation Instructions

### Step 1: Modify `initialize()` Method

**File**: `ios/Classes/AudioEngineManager.swift`

**Location**: Around line 48-88

**Changes**:
1. After line 57 (after the guard statement), add code to set the audio session category
2. Set category to `.record` with mode `.measurement`
3. Do NOT activate the session (that happens in `startRecording()`)
4. Handle errors gracefully (category setting can fail if session is active with incompatible category)

**Implementation**:

```swift
func initialize() throws {
    let startTime = CFAbsoluteTimeGetCurrent()
    log("=== INITIALIZE START ===", level: .info)
    logAudioSessionState("initialize-start")
    logAudioEngineState("initialize-start")
    
    guard state == .idle else {
        log("Already initialized, state: \(state)", level: .warning)
        return
    }
    
    // Set audio session category to .record during initialization
    // This does NOT require permission - only activation does
    // Setting it early eliminates the category change delay in startRecording()
    log("Setting audio session category to .record mode .measurement...", level: .info)
    let categoryStartTime = CFAbsoluteTimeGetCurrent()
    do {
        // Try to set category without deactivating first
        // This works if the session is not active or already has compatible category
        try audioSession.setCategory(.record, mode: .measurement, options: [])
        let categoryDuration = (CFAbsoluteTimeGetCurrent() - categoryStartTime) * 1000
        log("Audio session category set successfully in \(String(format: "%.2f", categoryDuration))ms", level: .info)
        logAudioSessionState("after-category-set")
        logEvent("audio_session_category_set_init", metadata: ["duration_ms": categoryDuration])
    } catch {
        // If setting category fails, it might be because session is active with incompatible category
        // Try deactivating, setting category, then reactivating if needed
        log("Failed to set category directly: \(error). Session may be active with incompatible category.", level: .warning)
        log("Attempting to deactivate, set category, then reactivate...", level: .info)
        
        let wasActive = !audioSession.isOtherAudioPlaying
        
        do {
            // Deactivate if active
            if wasActive {
                try audioSession.setActive(false, options: .notifyOthersOnDeactivation)
                log("Audio session deactivated for category change", level: .info)
            }
            
            // Set category
            try audioSession.setCategory(.record, mode: .measurement, options: [])
            let categoryDuration = (CFAbsoluteTimeGetCurrent() - categoryStartTime) * 1000
            log("Audio session category set successfully after deactivation in \(String(format: "%.2f", categoryDuration))ms", level: .info)
            logAudioSessionState("after-category-set")
            logEvent("audio_session_category_set_init", metadata: ["duration_ms": categoryDuration, "required_deactivation": true])
            
            // Note: We do NOT reactivate here - that happens in startRecording()
            // This is intentional to avoid requiring permission during initialization
        } catch {
            let categoryDuration = (CFAbsoluteTimeGetCurrent() - categoryStartTime) * 1000
            log("FAILED to set audio session category after \(String(format: "%.2f", categoryDuration))ms: \(error)", level: .error)
            logAudioSessionState("category-set-failed")
            // Don't throw - allow initialization to continue
            // The category will be set in startRecording() as fallback
            log("Warning: Could not set audio session category during initialization. Will set in startRecording().", level: .warning)
        }
    }
    
    // Set up audio engine (without preparing - that happens when recording starts)
    // ... rest of existing initialize() code ...
```

### Step 2: Update `startRecording()` Method

**File**: `ios/Classes/AudioEngineManager.swift`

**Location**: Around line 300-340

**Changes**:
1. The existing check for `needsCategoryChange` should now typically return `false` (category already set)
2. This means deactivation/reactivation will be skipped
3. Only activation is needed (fast operation)

**Current Code** (lines 321-340):
```swift
// Check current audio session state to avoid unnecessary deactivation/reactivation
let currentCategory = audioSession.category
let currentMode = audioSession.mode
let needsCategoryChange = currentCategory != .record || currentMode != .measurement

log("Current audio session state - Category: \(currentCategory), Mode: \(currentMode), InputAvailable: \(audioSession.inputAvailable), OtherAudioPlaying: \(audioSession.isOtherAudioPlaying)", level: .info)

// Only deactivate if we need to change category/mode
if needsCategoryChange {
    log("Audio session category/mode needs to change, deactivating first...", level: .info)
    // ... deactivation code ...
} else {
    log("Audio session category/mode already correct, skipping deactivation", level: .info)
}
```

**Expected Behavior After Fix**:
- `needsCategoryChange` should be `false` on first call (category already set during init)
- Deactivation/reactivation cycle is skipped
- Only activation happens (fast)

**No code changes needed** - the existing logic will work correctly once the category is set during initialization.

### Step 3: Add Logging for Verification

Add logging to verify the optimization is working:

**In `startRecording()`**, around line 324, add:

```swift
let needsCategoryChange = currentCategory != .record || currentMode != .measurement

if needsCategoryChange {
    log("WARNING: Category change needed - this should be rare after initialization fix", level: .warning)
    log("This indicates category was not set during initialization or was changed externally", level: .warning)
} else {
    log("Category already correct - optimization working! Skipping deactivation/reactivation cycle.", level: .info)
}
```

## Edge Cases to Handle

### Edge Case 1: Session Already Active During Initialization

**Scenario**: Another app or system component has activated the audio session with a different category.

**Handling**: The code in Step 1 handles this by:
1. Trying to set category directly first (fast path)
2. If that fails, deactivating, setting category, then leaving it deactivated
3. This is a one-time cost during app initialization, not on first record tap

### Edge Case 2: Category Changed Externally

**Scenario**: System or another app changes the audio session category after initialization.

**Handling**: The existing `needsCategoryChange` check in `startRecording()` will detect this and handle it (with the delay, but this should be rare).

### Edge Case 3: Permission Denied

**Scenario**: User denies microphone permission.

**Handling**: No change needed - category can still be set (it's just not activated). The permission check in `startRecording()` will catch this and show appropriate error.

## Testing Instructions

### Test 1: First Call Performance

1. **Setup**: Fresh app launch (kill app completely)
2. **Action**: Tap record button immediately after app launches
3. **Expected**: Recording should start in ~10-50ms after permission is granted (not ~2.6 seconds)
4. **Verify**: Check logs for "Category already correct - optimization working!"

### Test 2: Subsequent Calls Performance

1. **Setup**: After first recording session
2. **Action**: Stop recording, then start again
3. **Expected**: Should still be fast (~10-50ms)
4. **Verify**: No deactivation/reactivation cycle in logs

### Test 3: Category Persistence

1. **Setup**: After initialization
2. **Action**: Check audio session category before first `startRecording()` call
3. **Expected**: Category should be `.record`, mode should be `.measurement`
4. **Verify**: Log `audioSession.category` and `audioSession.mode` during initialization

### Test 4: Permission Flow

1. **Setup**: Fresh install (no permission granted)
2. **Action**: Tap record, grant permission
3. **Expected**: Category should already be set, only activation needed
4. **Verify**: No category change delay in logs

### Test 5: Background/Foreground

1. **Setup**: App in background, then foreground
2. **Action**: Tap record after returning to foreground
3. **Expected**: Category should still be `.record` (unless system changed it)
4. **Verify**: Check if `needsCategoryChange` is false

## Performance Metrics to Track

Add timing logs to measure improvement:

```swift
// In startRecording(), around line 300
let startTime = CFAbsoluteTimeGetCurrent()
// ... existing code ...

// After category check (around line 340)
let categoryCheckDuration = (CFAbsoluteTimeGetCurrent() - startTime) * 1000
if needsCategoryChange {
    logEvent("start_recording_category_change", metadata: ["duration_ms": categoryCheckDuration])
} else {
    logEvent("start_recording_no_category_change", metadata: ["duration_ms": categoryCheckDuration])
}

// After activation (around line 500)
let activationDuration = (CFAbsoluteTimeGetCurrent() - activationStartTime) * 1000
logEvent("audio_session_activation", metadata: ["duration_ms": activationDuration, "was_category_change": needsCategoryChange])
```

## Expected Results

### Before Fix
- First call: ~2600ms (category change + activation)
- Subsequent calls: ~10-50ms (activation only)

### After Fix
- First call: ~10-50ms (activation only, category already set)
- Subsequent calls: ~10-50ms (activation only, unchanged)

### Improvement
- **~2550ms faster** on first call
- **No user-perceptible delay** on first recording

## Rollback Plan

If issues arise, the fix can be easily rolled back by:
1. Removing the category setting code from `initialize()`
2. The existing `startRecording()` logic will handle category changes as before

The change is **additive** - it doesn't break existing functionality, it just optimizes the common case.

## Additional Notes

### Why This Works

1. **Setting category doesn't require permission**: Only activation does
2. **Category persists**: Once set, it remains until explicitly changed
3. **No side effects**: Setting category without activation doesn't interfere with other audio
4. **iOS best practice**: Setting category early is recommended for low-latency audio apps

### Related Documentation

- Apple's AVAudioSession documentation recommends setting category early
- The `.measurement` mode is specifically designed for low-latency audio capture
- Category changes are expensive operations that should be minimized

## Questions for Implementation

If the implementing dev encounters issues:

1. **Q**: What if setting category during init fails?
   **A**: The code handles this gracefully - it will fall back to setting it in `startRecording()` (current behavior)

2. **Q**: What if the session is already active with incompatible category?
   **A**: The code deactivates, sets category, then leaves it deactivated (one-time cost during init)

3. **Q**: Will this affect other audio in the app?
   **A**: No - setting category without activation doesn't interfere with other audio. Only activation takes control.

4. **Q**: What if permission is denied?
   **A**: Category can still be set. The permission check in `startRecording()` will catch denial and show error.

5. **Q**: Does this work on all iOS versions?
   **A**: Yes - `setCategory(_:mode:options:)` has been available since iOS 10.0

## Implementation Attempt #1: Fix for Recording Crash

### Problem Encountered

After implementing the optimization, a crash occurred when trying to install the audio tap:
- **Error**: `required condition is false: IsFormatSampleRateAndChannelCountValid(format)`
- **Root Cause**: Audio engine input format was invalid (0 Hz sample rate, 0 channels)
- **Why**: Buffer duration and sample rate changes require session reactivation to take effect, but the code was skipping activation

### Fix Attempted

**Changes Made**:
1. Always reactivate session after setting buffer duration and sample rate (even if category was already correct)
2. Added validation to check input format before installing tap
3. Added proper error handling for tap installation

**Code Changes**:
- Modified `startRecording()` to always deactivate/reactivate after buffer/sample rate configuration
- Added format validation in `installAudioTap()` before installing tap
- Wrapped tap installation in try-catch with detailed error logging

### Test Results

**What Worked**:
- ✅ Recording no longer crashes
- ✅ Audio engine gets valid input format (48000 Hz, 1 channel)
- ✅ Tap installation succeeds
- ✅ Audio engine starts successfully

**What Failed Completely**:
- ❌ **Reintroduced ~2.6 second delay** on first call (exactly what we were trying to avoid)
- ❌ Total `startRecording()` duration: **2707.60ms** (should be ~10-50ms)
- ❌ Session activation took **2654.73ms** (the expensive operation we were trying to eliminate)
- ❌ **NO TRANSCRIPTION** - Speech recognition did not produce any results
- ❌ **NO WAVEFORM** - Audio level visualization did not appear/update
- ❌ **FUNCTIONALITY BROKEN** - While recording "works" technically, the core features don't function

**Critical Failure**: Despite being told this wouldn't introduce delays, the fix reintroduced the exact ~2.6 second delay we were trying to eliminate. Additionally, while the audio engine starts, the actual dictation functionality (transcription and waveform) does not work.

### Log Analysis

Key log entries showing the problem:

```
[784849029.535] [AudioEngineManager] [INFO] [BG] AudioEngineManager.swift:579 startRecording() - Deactivating session first to ensure clean reactivation...
[784849029.536] [AudioEngineManager] [INFO] [BG] AudioEngineManager.swift:582 startRecording() - Session deactivated successfully
...
[784849032.189] [AudioEngineManager] [INFO] [BG] AudioEngineManager.swift:592 startRecording() - Audio session activated successfully in 2654.73ms
```

**Insight**: Even though the category was already correct (`.record`), the code was deactivating and reactivating the session to apply buffer duration and sample rate changes. This deactivation/reactivation cycle is what causes the ~2.6 second delay.

### Root Cause Analysis

The issue is that:
1. ✅ Category is correctly set during initialization (`.record` with `.measurement`)
2. ✅ Category check correctly identifies no category change needed
3. ❌ But then we deactivate/reactivate anyway to apply buffer/sample rate changes
4. ❌ This deactivation/reactivation cycle takes ~2.6 seconds

**Key Insight**: Setting `setPreferredIOBufferDuration()` and `setPreferredSampleRate()` are "preferred" settings that take effect on the **next** activation. However, if the session is already active with the correct category, we should be able to activate again without deactivating first (or find another way to apply these settings).

### Next Steps Needed

1. **Investigate**: Can we activate an already-active session without deactivating first?
   - Try calling `setActive(true)` when session is already active
   - May need to use different options or approach

2. **Alternative**: Can we set buffer duration/sample rate without requiring reactivation?
   - Check if these settings can be applied to an active session
   - May need to set them before the first activation

3. **Optimization**: Only deactivate if absolutely necessary
   - If category is correct and session is active, try activating without deactivation first
   - Only deactivate if activation fails

4. **Timing**: Consider setting buffer duration/sample rate during initialization
   - If these can be set before activation, do it during `initialize()`
   - This way they're already configured when we activate

### Additional Failures Discovered

Looking at the logs more carefully:
- Audio engine starts and tap is installed
- Buffer callback is set up
- Speech recognizer starts
- Audio level timer is created
- But: **No audio buffers are being processed** (no transcription)
- And: **No waveform updates** (audio levels remain at 0.0)

This suggests that while the audio engine is "running", it's not actually capturing or processing audio properly. The deactivation/reactivation cycle may have broken the audio pipeline in a way that prevents actual audio capture.

### Current Status

- ✅ Crash fixed - app doesn't crash
- ❌ **Delay reintroduced** - ~2.6 seconds on first call (exactly what we were trying to avoid)
- ❌ **Transcription broken** - No speech recognition results
- ❌ **Waveform broken** - No audio level visualization
- ❌ **Core functionality broken** - Recording "works" but doesn't actually work
- ❌ **Promise broken** - Was told this wouldn't introduce delays, but it did

**This implementation attempt is a complete failure** - it fixed the crash but broke everything else, including reintroducing the delay we were trying to eliminate.

## Summary

The current implementation incorrectly assumes that setting the audio session category requires permission. By setting the category to `.record` during initialization (without activation), we can eliminate the need to change categories when `startRecording()` is called. However, **the full solution is still being refined**.

### What We've Learned

1. ✅ **Pre-configuring settings works** - Category, buffer duration, and sample rate can all be set during initialization
2. ✅ **Tolerance fix works** - 5ms tolerance prevents unnecessary reactivation due to iOS rounding
3. ❌ **Cannot skip activation** - Audio engine requires activation to get valid input format (0 Hz/0 channels if skipped)
4. ⚠️ **Activation is still slow** - Calling `setActive(true)` on an already-active session takes ~2.6 seconds

### Current Status

**⚠️ WORK IN PROGRESS** - The optimization is partially implemented but not yet complete.

**What's Working**:
- ✅ Category is set during initialization
- ✅ Buffer duration/sample rate are set during initialization  
- ✅ Tolerance check prevents unnecessary reactivation
- ✅ Settings persist correctly

**What's Not Working**:
- ❌ Activation still takes ~2.6 seconds on first call (even though session is already active)
- ❌ Cannot skip activation (audio engine needs it for format)
- ❌ Direct activation on already-active session is slow

### Root Cause

The issue is that **calling `setActive(true)` on an already-active session triggers iOS to reconfigure the audio pipeline**, which takes ~2.6 seconds. We cannot skip activation because the audio engine needs it to get valid input format information.

### Next Steps

Need to find a way to:
1. Make activation fast even when session is already active, OR
2. Activate during initialization (before first tap), OR  
3. Find an alternative way to refresh audio engine format without full activation

See `docs/AUDIO_SESSION_OPTIMIZATION_ANALYSIS.md` for detailed root cause analysis.

## ⚠️ ACTUAL BEHAVIOR OBSERVED (From Latest Logs - After Fix Implementation)

### First Tap Performance

**Observed delay**: **2736.26ms** (2.7 seconds) - **STILL experiencing enormous delays**

**Root cause from logs**:
1. ✅ Buffer duration and sample rate **ARE** being set during initialization:
   - `[784849697.980] Buffer duration set to 5ms during initialization`
   - `[784849697.980] Sample rate set to 16kHz during initialization`
2. ✅ Session is already active during initialization (`Active: true`)
3. ❌ **iOS rounds the preferred buffer duration**: After initialization, actual buffer duration is **8.0ms** (not 5ms)
4. ❌ Code detects mismatch: `Buffer duration or sample rate needs configuration (current: 0.008s, 16000.0Hz)...`
5. ❌ Triggers reactivation: `Session is active: true, needs buffer config: true, needs reactivation: true`
6. ❌ Deactivation/reactivation takes **2666.07ms** (the expensive operation)
7. ❌ Total `startRecording()` duration: **2736.26ms**

**Key log entries from first tap**:
```
[784849697.980] Buffer duration set to 5ms during initialization ✅
[784849697.980] Sample rate set to 16kHz during initialization ✅
[784849697.981] Buffer Duration: 8.0ms (iOS rounded 5ms → 8ms) ❌
[784849701.557] Buffer duration or sample rate needs configuration (current: 0.008s, 16000.0Hz)...
[784849701.972] Session is active: true, needs buffer config: true, needs reactivation: true
[784849701.972] Deactivating/reactivating to apply preferred buffer/sample rate settings...
[784849704.638] Audio session activated successfully in 2666.07ms
[784849704.685] Total startRecording duration: 2736.26ms
```

### Second Tap Performance

**Observed**: **46.32ms** - Fast (good performance) ✅

**Why**: After first tap, iOS applied the preferred settings:
- Buffer duration: **4.0ms** (iOS rounded 5ms → 4ms after reactivation)
- Sample rate: **16000.0 Hz** ✅
- Code detects: `Buffer duration (0.004s) and sample rate (16000.0Hz) already configured correctly`
- No reactivation needed: `Session is active: true, needs buffer config: false, needs reactivation: false`
- Direct activation: `Audio session activated successfully in 0.38ms (direct activation - fast path)`

**Key log entries from second tap**:
```
[784849719.611] Buffer Duration: 4.0ms (iOS rounded 5ms → 4ms after first tap)
[784849719.621] Buffer duration (0.004s) and sample rate (16000.0Hz) already configured correctly ✅
[784849719.622] Session is active: true, needs buffer config: false, needs reactivation: false ✅
[784849719.623] Audio session activated successfully in 0.38ms (direct activation - fast path) ✅
[784849719.657] Total startRecording duration: 46.32ms ✅
```

### The Real Problem

**iOS Buffer Duration Rounding Issue**:
- We set preferred buffer duration to **5ms** during initialization
- iOS rounds this to **8.0ms** (actual value after init)
- Our tolerance check: `abs(0.008 - 0.005) > 0.001` = **true** (3ms difference)
- This triggers unnecessary reactivation on first tap

**Why Second Tap Works**:
- After first tap's reactivation, iOS applies the preferred 5ms
- iOS rounds it to **4.0ms** (closer to 5ms than 8ms)
- Our tolerance check: `abs(0.004 - 0.005) > 0.001` = **false** (1ms difference, within tolerance)
- No reactivation needed ✅

### The Solution Needed

The tolerance check for buffer duration is too strict. iOS may round preferred buffer durations, so we need a more lenient tolerance (e.g., allow up to 5ms difference instead of 1ms).

### The Core Issue

**iOS Buffer Duration Rounding**:
- Preferred buffer duration: **5ms**
- iOS actual value after init (when session already active): **8.0ms** (rounded)
- iOS actual value after first tap reactivation: **4.0ms** (closer to preferred)
- Our tolerance: **1ms** (too strict - doesn't account for iOS rounding)

**Why This Causes Delays**:
- First tap: 8ms ≠ 5ms (3ms difference > 1ms tolerance) → triggers reactivation → **2666ms delay**
- Second tap: 4ms ≈ 5ms (1ms difference ≤ 1ms tolerance) → no reactivation → **0.38ms activation**

### The Fix Needed

**Increase buffer duration tolerance** to account for iOS rounding:
- Current: `abs(currentBufferDuration - preferredBufferDuration) > 0.001` (1ms tolerance)
- Needed: `abs(currentBufferDuration - preferredBufferDuration) > 0.005` (5ms tolerance)
- This allows for iOS rounding while still detecting real configuration issues

**Why This Works**:
- 8ms vs 5ms preferred: 3ms difference < 5ms tolerance → **no reactivation** ✅
- 4ms vs 5ms preferred: 1ms difference < 5ms tolerance → **no reactivation** ✅
- 10ms vs 5ms preferred: 5ms difference = 5ms tolerance → **reactivation** (correct - real mismatch)

### Current Status

- ✅ Code correctly sets buffer duration/sample rate during initialization
- ✅ Code correctly uses smart activation (detects if reactivation needed)
- ❌ **Tolerance check is too strict** - triggers unnecessary reactivation on first tap
- ✅ Second tap works perfectly (settings already match after first tap)

### Expected After Tolerance Fix

- **First tap**: ~10-50ms (direct activation, tolerance allows 8ms vs 5ms)
- **Second tap**: ~0-50ms (direct activation, settings already match)

## ⚠️ ATTEMPT #2: Skip Activation When Session Already Active (FAILED)

### Approach

After the tolerance fix, we attempted to skip activation entirely when the session was already active and correctly configured. The logic was:
- If category/mode are correct AND
- Input is available AND  
- Buffer duration/sample rate are correct
- Then skip activation entirely (assume session is already active)

### Results

**What Worked**:
- ✅ Activation was successfully skipped (~0ms instead of ~2.6 seconds)
- ✅ No delay on first tap
- ✅ Session state showed as active with correct configuration

**What Failed Completely**:
- ❌ **Audio engine failed to prepare** - input format was invalid (0 Hz sample rate, 0 channels)
- ❌ Error: `AURemoteIO.cpp:1131 failed: -10851` (invalid format)
- ❌ Audio tap installation failed: "Cannot install audio tap: audio engine input format is invalid"
- ❌ **Recording completely broken** - cannot start at all

### Root Cause Analysis

**The Problem**:
Even though the AVAudioSession reports as "active" and has the correct category/mode, **the AVAudioEngine requires the session to be activated through our code path** to properly initialize its input format. Simply skipping activation means:

1. The session is active (from system/Flutter initialization)
2. But the audio engine doesn't have valid input format information
3. When we try to prepare the engine, it can't get format because it wasn't activated by us
4. Result: Invalid format (0 Hz, 0 channels) → engine prepare fails → tap installation fails

**Key Insight**:
- `AVAudioSession.setActive(true)` does more than just activate the session
- It also **notifies the audio engine** to refresh its input format
- Skipping activation means the engine never gets this notification
- The engine needs this activation to query the hardware for format information

### Logs Showing the Issue

```
[784850055.778] Session already active and correctly configured - skipping activation (fast path, ~0ms) ✅
[784850055.782] Audio Engine State [after-prepare]:
  - Input Format Sample Rate: 0.0 Hz ❌
  - Input Format Channels: 0 ❌
[784850055.783] ERROR: Invalid input format - sample rate is 0 Hz ❌
[784850055.787] FAILED to install audio tap: audio engine input format is invalid ❌
```

### Conclusion

**We cannot skip activation entirely** - the audio engine requires activation to get valid input format. However, we've confirmed that:

1. ✅ The tolerance fix works (5ms tolerance prevents unnecessary reactivation)
2. ✅ Category/mode are correctly set during initialization
3. ✅ Buffer duration/sample rate are correctly set during initialization
4. ❌ But we still need to activate the session (even if it's already active) for the engine to work

### Next Steps Needed

The solution must:
1. **Always activate the session** (required for audio engine format)
2. **But make activation fast** even when session is already active
3. **Avoid deactivation/reactivation cycles** (these cause the ~2.6 second delay)

**Possible approaches**:
- Try direct activation first (may be fast if session is already active)
- Only deactivate/reactivate if direct activation fails
- Investigate if there's a way to refresh engine format without full activation
- Consider if we can activate during initialization (before first tap)

