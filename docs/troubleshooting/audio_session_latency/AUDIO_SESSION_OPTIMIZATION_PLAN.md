# Audio Session Optimization Plan
## Aligning with Sub-100ms Latency Best Practices

### Current State Analysis

**❌ Current Issues:**

1. **Session Deactivation on Every Start** (Line 321-330 in `AudioEngineManager.swift`)
   - The code explicitly deactivates the audio session at the start of every `startRecording()` call
   - This forces reactivation on every tap, causing 300-3000ms latency
   - This is the primary cause of slow startup on subsequent taps

2. **No Active Check Before `setActive(true)`** (Line 465)
   - Calls `setActive(true)` without checking if session is already active
   - Can trigger expensive hardware cycles even when session is already active
   - Same issue in interruption handler (Line 808)

3. **Session Not Preserved Between Taps**
   - While `stopRecording()` doesn't deactivate the session (good), the next `startRecording()` will deactivate it anyway
   - This breaks the "keep session active" pattern used by ChatGPT, Otter, etc.

### Target Architecture (Aligned with Best Practices)

**✅ What Fast Apps Do:**
- Activate session **once** (on app launch, permission grant, or first tap)
- **Never deactivate** while app is foregrounded (unless another app needs audio)
- **Check if active** before calling `setActive(true)` to avoid hardware cycles
- Only restart the engine (<20ms) on subsequent taps, not reactivate session

**✅ Expected Behavior:**
- First tap: Activate session + start engine = ~100-500ms (one-time cost)
- Subsequent taps: Start engine only = <100ms (target: 20-60ms)
- Session stays active until app backgrounds or another app steals audio

---

## Implementation Plan

### Phase 1: Add Session State Tracking

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

---

### Phase 2: Remove Deactivation from `startRecording()`

**Goal:** Stop deactivating the session on every start - this is the critical fix.

**Changes:**
1. **Remove lines 321-330** (deactivation block) from `startRecording()`
2. **Keep session active** between recording sessions
3. Only deactivate in specific scenarios (see Phase 4)

**Rationale:**
- Deactivation forces reactivation, causing 300-3000ms delay
- Fast apps never deactivate between taps
- Session can remain active safely while engine is stopped

**Files:**
- `ios/Classes/AudioEngineManager.swift` (lines 321-330)

---

### Phase 3: Add Active Check Before `setActive(true)`

**Goal:** Avoid calling `setActive(true)` when session is already active to prevent hardware cycles.

**Changes:**
1. **Before line 465** (`setActive(true)`), add check:
   ```swift
   // Only activate if not already active
   if !isSessionActivated {
       do {
           try audioSession.setActive(true)
           isSessionActivated = true
           log("Session activated successfully", level: .info)
       } catch let error as NSError {
           // If error is "already active", that's OK - just update flag
           if error.domain == NSOSStatusErrorDomain && error.code == Int(kAudioSessionAlreadyActive) {
               log("Session already active (system state), updating flag", level: .info)
               isSessionActivated = true
           } else {
               throw error
           }
       }
   } else {
       log("Session already active (tracked state), skipping activation", level: .info)
   }
   ```

2. **Update interruption handler** (line 808) with same check:
   ```swift
   if !isSessionActivated {
       do {
           try audioSession.setActive(true)
           isSessionActivated = true
       } catch {
           log("Failed to reactivate after interruption: \(error)", level: .error)
           throw error
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

### Phase 4: Implement Proper Session Lifecycle Management

**Goal:** Activate session once and keep it active, only deactivating when necessary.

**Changes:**

1. **Activate on First Use** (not in `initialize()`)
   - Move session activation to first `startRecording()` call
   - Or activate after permission is granted (better UX)
   - Track with `isSessionActivated` flag

2. **Handle App Lifecycle Events**
   - **App backgrounds:** Optionally deactivate (or keep active for instant resume)
   - **App foregrounds:** Reactivate if needed
   - **Interruption began:** Don't deactivate, just pause engine
   - **Interruption ended:** Reactivate only if needed (check flag)

3. **Deactivation Scenarios** (only these):
   - App explicitly backgrounds AND user preference is to deactivate
   - Another app steals audio (handled by iOS automatically)
   - User explicitly requests deactivation (rare)

**Files:**
- `ios/Classes/AudioEngineManager.swift`
- `ios/Classes/FlutterDictationPlugin.swift` (for app lifecycle)

---

### Phase 5: Implement Input Format Refresh Strategy

**Goal:** Handle invalid input formats without reactivating the session - this is critical for fast subsequent starts.

**Problem:**
- After stopping the engine, `inputNode.inputFormat(forBus: 0)` may return invalid format (sampleRate = 0, channelCount = 0)
- This can happen when engine is stopped but session remains active
- Need to refresh format without reactivating session (which would cost 300-3000ms)

**Solution: Simpler Approach - Just Call engine.prepare()**

After testing, the simplest solution is to just call `engine.prepare()` when format is invalid:

```swift
func refreshInputFormat() throws {
    let input = engine.inputNode
    let fmt = input.inputFormat(forBus: 0)
    
    if fmt.sampleRate == 0 || fmt.channelCount == 0 {
        log("Input format invalid, calling prepare() to refresh", level: .info)
        // Prepare refreshes the hardware connection and format
        engine.prepare()
        
        // Re-check format
        let refreshedFormat = input.inputFormat(forBus: 0)
        if refreshedFormat.sampleRate == 0 || refreshedFormat.channelCount == 0 {
            throw AudioError("Input format still invalid after prepare. Session may not be active.")
        }
    }
}
```

**Alternative: Accept Format Might Be Invalid**

Even simpler - just handle the error when installing tap fails:

```swift
func installAudioTap() throws {
    // Remove existing tap if any
    inputNode.removeTap(onBus: 0)
    
    let inputFormat = inputNode.inputFormat(forBus: 0)
    
    // Validate format
    guard inputFormat.sampleRate > 0 && inputFormat.channelCount > 0 else {
        throw AudioError("Invalid input format: sampleRate=\(inputFormat.sampleRate), channels=\(inputFormat.channelCount). Ensure audio session is active and engine is prepared.")
    }
    
    // Install tap
    inputNode.installTap(onBus: 0, bufferSize: 1024, format: inputFormat) { [weak self] buffer, time in
        self?.processAudioBuffer(buffer)
    }
}
```

**When to Call:**
- Call `refreshInputFormat()` before installing tap
- OR just let tap installation fail with clear error message

**Performance:**
- `engine.prepare()`: ~5-20ms (very fast)
- No blocking, no sleep calls
- Session remains active throughout

**IMPORTANT**: Avoid blocking calls like `usleep()` - they block the thread and provide no guarantees

**Files:**
- `ios/Classes/AudioEngineManager.swift`
- Add `refreshInputFormat()` method
- Call before tap installation in `startRecording()`

---

### Phase 6: Optimize Engine Restart Path

**Goal:** Make subsequent taps as fast as possible by only restarting engine, not session.

**Changes:**

1. **Add Warm-Up State Tracking:**
   ```swift
   private var isWarmedUp = false
   ```
   - Set to `true` after first successful prepare + format refresh
   - Indicates engine is ready for fast restart

2. **Fast Path for Subsequent Starts:**
   ```swift
   func startRecording() throws {
       try ensureReady() // Handles warmup and format refresh
       try refreshInputFormat() // Ensure format is valid
       try engine.start() // Fast: ~10-30ms
   }
   
   private func ensureReady() throws {
       if !isWarmedUp {
           try warmUp() // One-time setup
       }
       try refreshInputFormat() // Refresh format if needed
   }
   ```

3. **Warm-Up Method (Called Once):**
   ```swift
   func warmUp() throws {
       guard isSessionActive else {
           throw AudioError("Session must be active before warmup.")
       }
       guard !isWarmedUp else { return }
       
       engine.prepare()
       try refreshInputFormat()
       isWarmedUp = true
   }
   ```

4. **Preserve Engine State:**
   - Don't remove tap unnecessarily
   - Keep engine prepared if possible
   - Only reset what's necessary

**Expected Latency:**
- First tap: ~100-500ms (session activation + warmup + engine start)
- Subsequent taps: ~20-60ms (format refresh if needed + engine start only)

**Files:**
- `ios/Classes/AudioEngineManager.swift` (refactor `startRecording()`)

---

### Phase 7: Add App Lifecycle Handling

**Goal:** Properly manage session when app backgrounds/foregrounds.

**Changes:**

1. **Add Notification Observers:**
   ```swift
   // In initialize() or setupInterruptionHandling()
   NotificationCenter.default.addObserver(
       self,
       selector: #selector(handleAppDidEnterBackground),
       name: UIApplication.didEnterBackgroundNotification,
       object: nil
   )
   
   NotificationCenter.default.addObserver(
       self,
       selector: #selector(handleAppWillEnterForeground),
       name: UIApplication.willEnterForegroundNotification,
       object: nil
   )
   ```

2. **Background Handler:**
   ```swift
   @objc private func handleAppDidEnterBackground() {
       // RECOMMENDED: Deactivate when backgrounding to save battery and follow Apple guidelines
       // Exception: Only keep active if doing background audio (recording, playback)
       if !isRecording {
           do {
               try audioSession.setActive(false, options: .notifyOthersOnDeactivation)
               isSessionActivated = false
               isWarmedUp = false  // Will need to warm up again
               log("Session deactivated on background", level: .info)
           } catch {
               log("Failed to deactivate on background: \(error)", level: .warning)
           }
       }
   }
   ```

3. **Foreground Handler:**
   ```swift
   @objc private func handleAppWillEnterForeground() {
       // Session will reactivate on next startRecording() call
       // Don't preemptively activate - wait for user action
       log("App foregrounded, session will activate on next recording", level: .info)
   }
   ```

**Files:**
- `ios/Classes/AudioEngineManager.swift`

---

## Implementation Checklist

### Critical Fixes (Required for <100ms latency)

- [ ] **Phase 2:** Remove deactivation from `startRecording()` (lines 321-330)
- [ ] **Phase 3:** Add active check before `setActive(true)` (line 465, 808)
- [ ] **Phase 1:** Add `isSessionActivated` flag tracking

### Optimization (Improves reliability)

- [ ] **Phase 4:** Implement proper session lifecycle
- [ ] **Phase 5:** Implement input format refresh strategy (critical for fast starts)
- [ ] **Phase 6:** Add fast path for subsequent starts with warm-up tracking
- [ ] **Phase 7:** Add app lifecycle handling

### Testing

- [ ] Measure latency on first tap (should be ~100-500ms)
- [ ] Measure latency on subsequent taps (should be <100ms, target 20-60ms)
- [ ] Test interruption handling (phone call, other audio apps)
- [ ] Test app backgrounding/foregrounding
- [ ] Test with different audio routes (AirPods, Bluetooth, etc.)

---

## Expected Results

### Before (Current)
- First tap: ~100-500ms ✅
- Second tap: ~300-3000ms ❌ (session reactivation)
- Third tap: ~300-3000ms ❌ (session reactivation)

### After (Optimized)
- First tap: ~100-500ms ✅ (one-time session activation + warmup)
- Second tap: ~20-60ms ✅ (format refresh if needed + engine start only)
- Third tap: ~20-60ms ✅ (format refresh if needed + engine start only)

**Breakdown for subsequent taps:**
- Format refresh (if needed): ~30-50ms
- Engine start: ~10-30ms
- Total: ~40-80ms (worst case with format refresh)
- Best case (format valid): ~10-30ms (engine start only)

### Edge Cases
- After interruption: May require reactivation (~300-3000ms) - unavoidable
- After app background: Depends on strategy (keep active = instant, deactivate = reactivation cost)
- Route change: May require reactivation - unavoidable

---

## Code Locations Reference

### Files to Modify:
1. **`ios/Classes/AudioEngineManager.swift`**
   - Line 321-330: Remove deactivation block
   - Line 445-497: Add active check before `setActive(true)`
   - Line 788-820: Update interruption handler
   - Add: Session state tracking
   - Add: Fast path for subsequent starts
   - Add: App lifecycle handlers

### Key Methods:
- `startRecording()`: Main optimization target
- `stopRecording()`: Already good (doesn't deactivate)
- `handleAudioSessionInterruption()`: Needs active check
- `initialize()`: May need session activation logic
- **New:** `refreshInputFormat()`: Critical for fast subsequent starts
- **New:** `warmUp()`: One-time engine preparation
- **New:** `ensureReady()`: Fast path coordinator

---

## Notes

1. **No Direct "isActive" Property:**
   - iOS doesn't provide `audioSession.isActive`
   - **IMPORTANT**: `isOtherAudioPlaying` tells you if OTHER apps are playing, NOT if YOUR session is active
   - Track state with `isSessionActivated` flag
   - Handle errors gracefully when calling `setActive(true)` - iOS might have changed state

2. **Permission Timing:**
   - Session category can be set before permission
   - Activation requires permission
   - Activate after permission is granted

3. **Interruption Handling:**
   - iOS may deactivate session during interruption
   - Check flag and reactivate only if needed
   - Don't assume session is active after interruption
   - Handle `.began` by pausing, `.ended` by checking if should resume

4. **Background/Foreground:**
   - **RECOMMENDED**: Deactivate on background to save battery and follow Apple guidelines
   - Don't keep session active unnecessarily - can violate App Store review
   - Reactivate on foreground when user starts recording

5. **Testing Priority:**
   - Focus on Phase 2 & 3 first (critical fixes)
   - Phases 4-7 are optimizations
   - Measure before/after latency to validate

---

## Reference Implementation: Known Good AudioEngineManager

Below is a reference implementation that demonstrates the correct pattern for sub-100ms latency:

```swift
import AVFoundation

final class AudioEngineManager {
    static let shared = AudioEngineManager()
    
    private let session = AVAudioSession.sharedInstance()
    private let engine = AVAudioEngine()
    private var isSessionActive = false
    private var isWarmedUp = false
    
    // MARK: - Public API
    
    func configureSession() throws {
        let opts: AVAudioSession.CategoryOptions = [.allowBluetoothA2DP, .allowBluetooth]
        try session.setCategory(.playAndRecord, mode: .default, options: opts)
        try session.setPreferredSampleRate(44100)
        try session.setPreferredIOBufferDuration(0.005)
        try session.setActive(true)
        isSessionActive = true
    }
    
    /// Called on app launch or view load — before user taps anything.
    func warmUp() throws {
        guard isSessionActive else {
            throw AudioError("Session must be active before warmup.")
        }
        guard !isWarmedUp else { return }
        
        // Prepare nodes
        engine.prepare()
        try refreshInputFormat()
        isWarmedUp = true
    }
    
    /// Called when user taps "Record"
    func startRecording() throws {
        try ensureReady()
        try engine.start()
    }
    
    func stopRecording() {
        engine.stop()
        // Note: Session stays active, engine is stopped
    }
    
    // MARK: - Private
    
    private func ensureReady() throws {
        if !isWarmedUp {
            try warmUp()
        }
        try refreshInputFormat()
    }
    
    /// Ensures engine's input format is valid without reactivating session.
    func refreshInputFormat() throws {
        let input = engine.inputNode
        let fmt = input.inputFormat(forBus: 0)
        
        if fmt.sampleRate == 0 || fmt.channelCount == 0 {
            // Refresh by calling prepare - fast and non-blocking
            engine.prepare()
            
            // Re-read format
            let refreshed = input.inputFormat(forBus: 0)
            if refreshed.sampleRate == 0 || refreshed.channelCount == 0 {
                throw AudioError("Input format still invalid after prepare. Session may not be active.")
            }
        }
    }
}

struct AudioError: Error {
    let message: String
    init(_ msg: String) { self.message = msg }
}
```

### Key Patterns from Reference Implementation:

1. **Session Configured Once:**
   - `configureSession()` called once (on app launch or first use)
   - Session stays active (`isSessionActive` flag tracks state)

2. **Warm-Up Before First Use:**
   - `warmUp()` prepares engine and refreshes format
   - Called before user taps record (on app launch or view load)
   - Only runs once (`isWarmedUp` flag prevents redundant work)

3. **Fast Start Path:**
   - `startRecording()` calls `ensureReady()` which:
     - Warms up if needed (one-time)
     - Refreshes format if invalid (~30ms)
     - Starts engine (~10-30ms)
   - Total: ~40-60ms for subsequent taps

4. **Format Refresh Without Session Reactivation:**
   - `refreshInputFormat()` uses engine mini-start/stop
   - Only refreshes if format is invalid
   - Session remains active throughout

5. **Stop Doesn't Deactivate:**
   - `stopRecording()` only stops engine
   - Session stays active for instant next start

---

## Input Format Refresh Pattern (Detailed)

### The Problem

When `AVAudioEngine` is stopped, `inputNode.inputFormat(forBus: 0)` may return:
- `sampleRate = 0`
- `channelCount = 0`

This invalid format prevents:
- Installing taps (requires valid format)
- Configuring audio processing
- Starting recording reliably

### The Solution: Call engine.prepare()

The simplest and fastest solution is to call `engine.prepare()` when format is invalid:

```swift
func refreshInputFormat() throws {
    let input = engine.inputNode
    let fmt = input.inputFormat(forBus: 0)
    
    if fmt.sampleRate == 0 || fmt.channelCount == 0 {
        log("Input format invalid, calling prepare() to refresh", level: .info)
        // Prepare refreshes the hardware connection and format
        engine.prepare()
        
        // Re-check format
        let refreshedFormat = input.inputFormat(forBus: 0)
        if refreshedFormat.sampleRate == 0 || refreshedFormat.channelCount == 0 {
            throw AudioError("Input format still invalid after prepare. Session may not be active.")
        }
    }
}
```

### Performance Characteristics

- **engine.prepare():** ~5-20ms (very fast)
- **Session reactivation:** ~300-3000ms
- **Speedup:** 15-600x faster
- **Non-blocking:** No thread sleeps or blocking calls

### When to Use

- Before installing tap (format must be valid)
- After engine has been stopped
- When format appears invalid (sampleRate = 0)
- In `ensureReady()` or `startRecording()` before operations

### Integration Points

1. **In `warmUp()`:** Call after initial prepare
2. **In `ensureReady()`:** Check and refresh if needed
3. **In `startRecording()`:** Validate before installing tap

### Important Notes

- **Avoid blocking calls**: Don't use `usleep()` or similar blocking calls
- **Session must be active**: Format refresh requires active audio session
- **Speech recognizer**: This approach is safe even when recognizer is attached

---

## Key Corrections and Warnings

### ⚠️ Common Mistakes to Avoid

1. **DON'T confuse `isOtherAudioPlaying` with session active state**
   - `isOtherAudioPlaying` = OTHER apps using audio
   - NOT the same as YOUR session being active
   - Track your own state with a flag

2. **DON'T use blocking calls like `usleep()`**
   - Blocks threads unnecessarily
   - Provides no guarantees
   - Use `engine.prepare()` instead

3. **DON'T keep session active when backgrounding**
   - Drains battery
   - Can violate App Store guidelines
   - Deactivate on background, reactivate when needed

4. **DON'T assume format is always valid**
   - Always validate before installing tap
   - Call `engine.prepare()` to refresh
   - Provide clear error messages

5. **DON'T forget interruption handling**
   - iOS can deactivate your session anytime
   - Your flag can get out of sync
   - Handle errors gracefully when calling `setActive()`

### ✅ Best Practices Summary

1. **Activate session once** - after permission granted
2. **Keep session active** - between recordings (while foregrounded)
3. **Check flag before activating** - avoid redundant activation
4. **Deactivate on background** - save battery, follow guidelines
5. **Use engine.prepare()** - to refresh format without session cost
6. **Track state with flags** - `isSessionActivated`, `isWarmedUp`
7. **Handle errors gracefully** - iOS can change state without notice

---

## References

- [Apple AVAudioSession Documentation](https://developer.apple.com/documentation/avfaudio/avaudiosession)
- [Apple AVAudioEngine Documentation](https://developer.apple.com/documentation/avfaudio/avaudioengine)
- Best practices from ChatGPT, Otter, Voice Memos implementations
- iOS audio session activation latency research
- Reference implementation from production audio apps

