# Fast Path Optimizations
## Achieving Sub-100ms Latency on Subsequent Taps

### Prerequisites

Complete **01_CRITICAL_SESSION_FIXES.md** first. These optimizations build on the critical fixes.

---

## Phase 4: Implement Proper Session Lifecycle Management

**Goal:** Activate session once and keep it active, only deactivating when necessary.

**Changes:**

1. **Activate on First Use** (not in `initialize()`)
   - Session activation already happens in `startRecording()` (good)
   - Track with `isSessionActivated` flag (from Phase 1)
   - No changes needed - already correct

2. **Handle App Lifecycle Events** (see Phase 7)

3. **Deactivation Scenarios** (only these):
   - App explicitly backgrounds AND user preference is to deactivate
   - Another app steals audio (handled by iOS automatically)
   - User explicitly requests deactivation (rare)

**Files:**
- `ios/Classes/AudioEngineManager.swift`
- `ios/Classes/FlutterDictationPlugin.swift` (for app lifecycle)

---

## Phase 5: Implement Input Format Refresh Strategy

**Goal:** Handle invalid input formats without reactivating the session - this is critical for fast subsequent starts.

**Problem:**
- After stopping the engine, `inputNode.inputFormat(forBus: 0)` may return invalid format (sampleRate = 0, channelCount = 0)
- This can happen when engine is stopped but session remains active
- Need to refresh format without reactivating session (which would cost 300-3000ms)

**Solution: Call `engine.prepare()`**

The simplest solution is to call `engine.prepare()` when format is invalid:

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
            throw NSError(
                domain: "AudioEngineManager",
                code: -1,
                userInfo: [
                    NSLocalizedDescriptionKey: "Input format still invalid after prepare. Session may not be active."
                ]
            )
        }
        log("Input format refreshed: sampleRate=\(refreshedFormat.sampleRate), channels=\(refreshedFormat.channelCount)", level: .info)
    }
}
```

**When to Call:**
- Call `refreshInputFormat()` before installing tap in `startRecording()`
- Call in `ensureReady()` (Phase 6) before starting engine

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

## Phase 6: Optimize Engine Restart Path

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
   func startRecording() async throws {
       try ensureReady() // Handles warmup and format refresh
       try refreshInputFormat() // Ensure format is valid
       try installAudioTap() // Install tap if needed
       try audioEngine.start() // Fast: ~10-30ms
       state = .recording
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
       guard isSessionActivated else {
           throw NSError(
               domain: "AudioEngineManager",
               code: -1,
               userInfo: [
                   NSLocalizedDescriptionKey: "Session must be active before warmup."
               ]
           )
       }
       guard !isWarmedUp else { return }
       
       engine.prepare()
       try refreshInputFormat()
       isWarmedUp = true
       log("Engine warmed up successfully", level: .info)
   }
   ```

4. **Preserve Engine State:**
   - Don't remove tap unnecessarily (only when stopping)
   - Keep engine prepared if possible
   - Only reset what's necessary

**Expected Latency:**
- First tap: ~100-500ms (session activation + warmup + engine start)
- Subsequent taps: ~20-60ms (format refresh if needed + engine start only)

**Files:**
- `ios/Classes/AudioEngineManager.swift` (refactor `startRecording()`)

---

## Phase 7: Add App Lifecycle Handling

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

- [ ] **Phase 4:** Verify session lifecycle is correct (should already be good)
- [ ] **Phase 5:** Add `refreshInputFormat()` method
- [ ] **Phase 5:** Call `refreshInputFormat()` before installing tap in `startRecording()`
- [ ] **Phase 6:** Add `isWarmedUp` flag
- [ ] **Phase 6:** Add `warmUp()` method
- [ ] **Phase 6:** Add `ensureReady()` method
- [ ] **Phase 6:** Refactor `startRecording()` to use fast path
- [ ] **Phase 7:** Add app lifecycle notification observers
- [ ] **Phase 7:** Add background handler
- [ ] **Phase 7:** Add foreground handler

---

## Expected Results After All Optimizations

**Before (Current):**
- First tap: ~100-500ms ✅
- Second tap: ~300-3000ms ❌ (session reactivation)
- Third tap: ~300-3000ms ❌ (session reactivation)

**After (Optimized):**
- First tap: ~100-500ms ✅ (one-time session activation + warmup)
- Second tap: ~20-60ms ✅ (format refresh if needed + engine start only)
- Third tap: ~20-60ms ✅ (format refresh if needed + engine start only)

**Breakdown for subsequent taps:**
- Format refresh (if needed): ~5-20ms
- Engine start: ~10-30ms
- Total: ~15-50ms (worst case with format refresh)
- Best case (format valid): ~10-30ms (engine start only)

### Edge Cases
- After interruption: May require reactivation (~300-3000ms) - unavoidable
- After app background: Depends on strategy (keep active = instant, deactivate = reactivation cost)
- Route change: May require reactivation - unavoidable

---

## Testing

- [ ] Measure latency on first tap (should be ~100-500ms)
- [ ] Measure latency on subsequent taps (should be <100ms, target 20-60ms)
- [ ] Test interruption handling (phone call, other audio apps)
- [ ] Test app backgrounding/foregrounding
- [ ] Test with different audio routes (AirPods, Bluetooth, etc.)

---

## Key Corrections and Warnings

### ⚠️ Common Mistakes to Avoid

1. **DON'T confuse `isOtherAudioPlaying` with session active state**
   - `isOtherAudioPlaying` = OTHER apps using audio
   - NOT the same as YOUR session being active
   - Track your own state with a flag

2. **DON'T use blocking calls like `usleep()`**
   - Blocks threads unnecessarily
   - Provides no timing guarantees
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

## Reference Implementation Pattern

```swift
// Fast path pattern for subsequent starts
func startRecording() async throws {
    try ensureReady() // Handles warmup and format refresh
    try refreshInputFormat() // Ensure format is valid
    try installAudioTap() // Install tap if needed
    try audioEngine.start() // Fast: ~10-30ms
    state = .recording
}

private func ensureReady() throws {
    if !isWarmedUp {
        try warmUp() // One-time setup
    }
    try refreshInputFormat() // Refresh format if needed
}

func refreshInputFormat() throws {
    let input = engine.inputNode
    let fmt = input.inputFormat(forBus: 0)
    
    if fmt.sampleRate == 0 || fmt.channelCount == 0 {
        engine.prepare() // Fast: ~5-20ms
        let refreshedFormat = input.inputFormat(forBus: 0)
        if refreshedFormat.sampleRate == 0 || refreshedFormat.channelCount == 0 {
            throw NSError(...)
        }
    }
}
```

---

## References

- [Apple AVAudioSession Documentation](https://developer.apple.com/documentation/avfaudio/avaudiosession)
- [Apple AVAudioEngine Documentation](https://developer.apple.com/documentation/avfaudio/avaudioengine)
- Best practices from ChatGPT, Otter, Voice Memos implementations
- iOS audio session activation latency research

