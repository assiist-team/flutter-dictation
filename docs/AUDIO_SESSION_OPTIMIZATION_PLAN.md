# Audio Session Optimization Plan

## Objective
Keep `startRecording()` latency under 100 ms on every tap (ideal: 10‑50 ms) without destabilizing transcription, waveform, or user audio playback.

## Guiding Principles
- **Measure first**: Instrument the full path so we can prove each optimization helps.
- **Configure once**: Centralize AVAudioSession settings and reuse them.
- **Warm off the hot path**: Pay expensive setup costs before the user taps Record.
- **Be polite**: Never hijack other apps’ audio without warning.

## Assumptions & Invariants (Skeptical Engineer)
- Calling `AVAudioSession.setActive(true)` triggers a hardware configuration cycle that can take ~2.6s on some devices/routes when the session is already active; therefore we must avoid calling it unless strictly necessary.
- There is no reliable public API to query “isActive”; we infer “already active for recording” from a combination of: category/mode, `isInputAvailable`, recent activation performed by us, and recent warm state.
- Preferred IO buffer duration and sample rate only take effect on the next activation cycle; changing them while active requires deactivate/reactivate (slow path).
- AVAudioEngine input format may be invalid (0 Hz, 0 channels) until the engine has started at least once; a brief start/stop refreshes the format without a session reactivation.
- iOS may round preferred buffer durations/rates; tolerance checks (5ms duration, 1Hz rate) prevent unnecessary reconfiguration/reactivation.
- Subsequent taps must not call `setActive(true)` if the session is already active and correctly configured; this is the primary mechanism to avoid 2.6s delays between taps.
- To guarantee ≤100 ms on the very first tap, the session must be pre-activated and kept active through the first tap; pre-warming and then deactivating does not guarantee ≤100 ms on the first tap.

## Phase 1 – Instrumentation & Telemetry
1. Add timers and structured logs around:
   - Initialization (category/mode, buffer duration, sample rate, session active flag)
   - Warm-up/preparation work
   - Every `setActive` call (duration + options + success/failure)
   - Tap installation and engine start (input format, frame rate, failures)
2. Emit metrics (e.g., `logEvent`) for:
   - `initialize_total_ms`
   - `warmup_duration_ms`
   - `start_recording_latency_ms`
   - `activation_method` (`direct`, `deactivate_reactivate`, `skipped_already_active`, `skipped_due_to_other_audio`)
3. Capture current tolerance comparisons so we know when reactivation was triggered.

## Phase 2 – Unified Session Configuration
1. Implement `configureSessionForDictation()`:
   - Sets category `.record` with mode `.measurement`
   - Applies preferred IO buffer duration (5 ms tolerance 0.005) and sample rate (16 kHz tolerance 1 Hz)
   - Logs success/failure but does not throw so app still boots
2. Call this function from:
   - `initialize()`
   - Any recovery paths after interruptions or route changes
3. Store the last-known configuration snapshot (`configuredAt`, buffer duration, sample rate, category, mode) for comparison later.

## Phase 3 – Warm-Up Off the User Path
Triggered when microphone permission transitions to `.granted` (either immediately on launch for returning users or right after permission grant).

1. `preWarmSession()` task:
   - Checks `recordPermission == .granted`
   - Skips if `AVAudioSession.sharedInstance().secondaryAudioShouldBeSilencedHint == false` **and** `isOtherAudioPlaying == true` (don’t interrupt other audio)
   - Calls `configureSessionForDictation()`
   - Activates session with `.notifyOthersOnDeactivation`
   - Prepares audio engine, installs tap, starts engine for ~100 ms, then stops, removes tap, and deactivates
   - Records `warmState` metadata (timestamp, buffer duration, sample rate, engine input format)
2. Retry/backoff logic:
   - If another app is using audio, schedule a retry (e.g., exponential backoff capped at 30 s)
   - If activation fails, log and retry once user foregrounds the app again
3. Sticky warm mode (required to guarantee ≤100 ms first tap):
   - If no other audio is playing and the app is foregrounded, pre-activate and keep the session active after the brief engine start/stop (do not deactivate).
   - Remove tap and stop the engine after the warm pulse, but keep the session active until the first actual recording, app background, or a 5-minute idle timeout (whichever comes first).
   - If other audio starts while idle, deactivate immediately and surface a non-intrusive warning (“First tap may be slower; another app started audio.”).
   - Record `warmState` and `keepActive=true` metadata so Phase 4 can skip activation.

## Phase 4 – Fast Path Inside `startRecording()`
1. **Permission validation**: Request if needed (main-thread requirement stays).
2. **Compare with warm state**:
   - If `warmState.age < 5 minutes` and current session metrics are within tolerance, mark `canUseWarmPath = true`
3. **Category/mode check**:
   - Check if category is `.record` and mode is `.measurement`
   - If not, deactivate session (if active), then call `configureSessionForDictation()`, then activate (expect slow path only on first fix-up)
   - If already correct, skip deactivation and proceed to buffer/sample rate check
4. **Buffer/sample reconfiguration**:
   - Re-run tolerance check; only reconfigure if outside thresholds (5ms tolerance for buffer, 1Hz for sample rate)
   - **CRITICAL**: If we need to change buffer/sample rate AND session is already active, we must deactivate/reactivate (slow path ~2.6s) because preferred settings only apply on next activation
   - If session is inactive, just call `configureSessionForDictation()` before activating
5. **Activation logic** (CRITICAL - see "Critical Finding" section):
   - **DO NOT** call `setActive(true)` if:
     - Session is already active (`audioSession.isActive == true` OR `audioSession.isInputAvailable == true`)
     - Category and mode are already correct (from step 3)
     - Buffer duration and sample rate are within tolerance (from step 4)
   - **DO** call `setActive(true)` only when:
     - Session is inactive (needs activation)
     - Category/mode was changed (requires deactivate/reactivate anyway - already done in step 3)
     - Buffer/sample rate config changed while session was active (requires reactivation - already done in step 4)
   - **For engine format refresh**: If engine input format is invalid (0 Hz, 0 channels) after prepare, start the engine briefly (~50ms) then stop it. This refreshes the format without reactivating the session.
   - If activation throws `isBusy`, fall back to deactivate/reactivate (slow path) but log `activation_fallback = true`
6. **Waveform/tap safety**:
   - Keep existing input format validation (sample rate > 0, channels > 0)
   - If format is invalid after prepare, use engine start/stop workaround (see step 5)
   - Abort start with user-friendly error if format still invalid after workaround rather than crashing

## Phase 5 – Maintenance Hooks
1. **App foregrounding**:
   - On `sceneDidBecomeActive`, queue `preWarmSession()` if not currently recording, permission granted, and no other audio
2. **Stop recording (updated default)**:
   - By default, DO NOT deactivate the session on stop. Keep the session active while the app is foregrounded to guarantee subsequent taps avoid `setActive(true)` and its 2.6s cost.
   - Add a safety auto-release: if idle for >5 minutes, or when app backgrounds, deactivate to be polite.
   - If other audio starts playing and we can detect it, deactivate proactively and show a banner/toast explaining that subsequent first tap may be slower.
3. **Other-audio detection**:
   - Before deactivating/reactivating, check `isOtherAudioPlaying`
   - If true when user taps record, show toast/banner (“Pause other audio apps to dictate”) instead of hijacking audio
4. **Interruption recovery**:
   - After interruptions route back, re-run configuration tolerance checks; prefer format refresh via engine brief start over calling `setActive(true)` if the session remains active.

## Latency Budget & Guarantees
- Target tap-to-engine-start: 10–50ms typical, hard cap ≤100ms for subsequent taps.
- First ever activation after cold start or permission grant may exceed 100ms due to initial hardware bring-up; to guarantee ≤100 ms on the first tap, enable sticky warm mode (keep session active through first tap). If sticky warm is disabled, the first tap may exceed 100ms.
- Enforce via telemetry:
  - `start_recording_latency_ms` per tap
  - `activation_method` per tap must be `skipped_already_active` for subsequent taps
  - Alert if any subsequent tap shows `deactivate_reactivate` or `direct` methods unexpectedly.

## Phase 6 – Validation & Regression Safety
1. **Manual scenarios**:
   - Cold launch, grant permission, first tap latency <100 ms
   - Returning user (permission already granted) – first tap latency <50 ms
   - Foreground after >5 min idle – tap still <100 ms
   - Competing audio app running – we surface warning and avoid interruption
2. **Automated smoke tests** (where feasible via XCTest / integration tests):
   - Mock AVAudioSession to simulate rounding behavior and ensure tolerance logic prevents unnecessary reactivation
3. **Monitoring**:
   - Add log-based alerts for `start_recording_latency_ms > 200` or `activation_method == deactivate_reactivate` more than X times per session
   - Track warm-up success rate to confirm the background task is doing its job
4. **Acceptance checks (must pass)**
   - For N≥10 consecutive taps (no route change, no permission change), `activation_method == skipped_already_active` and `start_recording_latency_ms ≤ 100`.
   - After stopping and waiting 30s, next tap still `≤ 100ms` with `skipped_already_active`.
   - After app foreground resume (≤5 min idle), first tap `≤ 100ms` with `skipped_already_active`.
   - If other audio starts while idle, we deactivate and surface a warning; the next tap may use `direct` with higher latency, and we log `skipped_due_to_other_audio` on the prior idle window.

## Failure Modes & Mitigations
- Hidden reactivation via unnoticed buffer/sample change:
  - Mitigation: Persist last-known session config and compare with tolerances before each start; only change when beyond tolerance and log the delta.
- Interruption toggles activity behind our back:
  - Mitigation: Interruption handlers reconcile state and prefer engine start/stop for format refresh; only call `setActive(true)` if session is definitely inactive.
- Warm-up deactivates then we forget to keep active between taps:
  - Mitigation: Default policy keeps session active after a successful recording until backgrounding or 5-minute idle timeout.
- Engine format invalid after route change:
  - Mitigation: Brief engine start/stop to refresh format; abort with descriptive error if still invalid.

## Critical Finding: `setActive(true)` Behavior on Already-Active Sessions

### Problem Discovered
During implementation, it was discovered that calling `setActive(true)` on an already-active AVAudioSession triggers a **full hardware reconfiguration cycle** that takes ~2.6 seconds, not the fast ~10-50ms refresh that was assumed in Phase 4.

### Evidence from Logs

**First tap:**
```
[784851287.907] Attempting to activate audio session (smart activation)...
[784851290.595] Audio session refreshed (was already active) in 2687.89ms (refresh_already_active)
```

**Second tap (subsequent):**
```
[784851312.773] Attempting to activate audio session (smart activation)...
[784851315.447] Audio session refreshed (was already active) in 2673.63ms (refresh_already_active)
```

Between these logs, system messages indicate hardware reconfiguration:
- `HALSystem.cpp:2229   AudioObjectPropertiesChanged: no such object`
- `AQMEIO_HAL.cpp:2914  timeout`
- `AudioHardware-mac-imp.cpp:2987   AudioDeviceStop: no device with given ID`

### Root Cause Analysis

1. **Phase 4 assumption was incorrect**: The plan stated "Always call `setActive(true)` so AVAudioEngine refreshes its format" and assumed this would be fast (~10-50ms) when the session is already active. This assumption does not hold on iOS.

2. **iOS behavior**: On iOS, calling `setActive(true)` on an already-active session is **not** a no-op. It triggers:
   - Full audio hardware reconfiguration
   - Audio device stop/start cycle
   - ~2.6 second delay (same as deactivate/reactivate)

3. **Engine format issue**: The AVAudioEngine's input format becomes invalid (0 Hz, 0 channels) when:
   - Session is deactivated after stop (Phase 5: "Optionally deactivate session")
   - Session is reactivated, but engine format isn't refreshed until engine is actually started

### Corrected Approach

**DO NOT** call `setActive(true)` if:
- Session is already active (`audioSession.isActive == true`)
- Category and mode are already correct
- Buffer duration and sample rate are within tolerance

**DO** call `setActive(true)` only when:
- Session is inactive (needs activation)
- Category/mode needs to change (requires deactivate/reactivate anyway)
- Buffer/sample rate config changed while session was active (requires reactivation)

**For engine format refresh**: Instead of relying on `setActive(true)`, refresh the engine format by:
- Starting the engine briefly (if format is invalid after prepare)
- This is already implemented as a workaround and works correctly

### Impact on Phase 4

Phase 4 Step 3 must be revised:
- **Original**: "Always call `setActive(true)` so AVAudioEngine refreshes its format"
- **Corrected**: "Only call `setActive(true)` when session is inactive or needs reconfiguration. Skip activation if session is already active and correctly configured. Refresh engine format by starting the engine if needed, not by reactivating the session."

### Lessons Learned

1. **Measure assumptions**: The assumption that `setActive(true)` on an active session would be fast was not validated before implementation.
2. **iOS audio behavior**: iOS audio session management is more expensive than expected - even "refresh" operations trigger full hardware cycles.
3. **Format refresh strategy**: Engine format refresh should be done via engine start, not session reactivation.

## Rollout & Risks
- **Risks**:
  - Warm-up activating audio could still pause other apps if detection fails ➜ mitigated via `isOtherAudioPlaying` checks and short activation windows
  - Background warm-up might fail silently ➜ instrumentation + retries
  - Added complexity ➜ isolate logic into well-named helpers (`configureSessionForDictation`, `preWarmSession`, `shouldWarmNow`)
- **Rollback**:
  - Disable warm-up task (feature flag / runtime guard) if it misbehaves
  - Keep telemetry so we can revert with data

## Success Criteria
- Measured `start_recording_latency_ms` p95 < 80 ms across cold launches and foreground resumes
- Zero crashes or tap failures attributed to audio session configuration
- User audio (Music/Podcast apps) not paused unexpectedly during idle warm-up
- Logs show <5% of recordings requiring deactivate/reactivate path

Once these steps are implemented, we should finally have consistently low-latency dictation startup regardless of app lifecycle or prior permission state.

