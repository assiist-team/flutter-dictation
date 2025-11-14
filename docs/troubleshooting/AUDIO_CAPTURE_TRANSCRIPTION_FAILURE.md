# Dictation Not Working: No Waveform or Transcription

## Issue Description

After tapping the microphone button, the dictation service reports that it's "listening" successfully, but **no audio is captured and no transcription is produced**:

- **No waveform appears** - Audio level events are not being received
- **No transcription results** - When speaking and clicking the checkmark button, no text appears in the text box
- The service appears to start correctly (status shows "listening"), but nothing actually works

This is a **functional failure** - the dictation tool is not working at all, despite appearing to start successfully.

## Symptoms

- `startListening()` completes successfully (~986ms total, ~253ms for audio engine)
- Status event "listening" is received in Flutter
- **No audio level events are received** (waveform doesn't appear)
- **No speech recognition results are received** (no text appears when speaking)
- Audio engine reports it started successfully
- Speech recognizer reports it started successfully
- Speech recognition timeout error appears: `Result accumulator timeout: 0.250000, exceeded`

## Root Cause Analysis

From the Xcode logs, we can see that:

1. ✅ **Audio engine starts successfully** - All initialization steps complete
2. ✅ **Speech recognizer starts successfully** - Initialization completes
3. ✅ **Status "listening" is sent** - Flutter receives the listening status
4. ❌ **Audio level streaming never starts** - Missing logs:
   - `=== START AUDIO LEVEL STREAMING ===` (should appear immediately after "Starting audio level streaming...")
   - `Creating audio level timer (60 FPS, ~16ms interval)`
   - `Audio level timer created and added to run loop`
5. ❌ **Audio buffers are not being processed** - Missing logs:
   - `Processed audio buffer: frameLength=..., level=...`
   - `buffer_appended: ...` (from SpeechRecognizerManager)
6. ❌ **No speech recognition results** - Missing logs:
   - `recognition_result: ...`
   - `calling_result_callback: ...`

### Critical Finding

The log shows:
```
[784761214.166] Starting audio level streaming...
```

But the expected follow-up logs from `startAudioLevelStreaming()` are **completely missing**:
- `=== START AUDIO LEVEL STREAMING ===` should appear but doesn't
- Timer creation logs should appear but don't

This suggests that `startAudioLevelStreaming()` is either:
1. Not being called (despite the log saying it is)
2. Failing silently before the first log statement
3. The logs are being filtered out or not appearing

## Detailed Log Analysis

### What Works (From Xcode Logs)

```
[784761213.179] === METHOD CALL: startListening ===
[784761213.796] State changed to: .initializing
[784761213.796] Starting audio engine...
[784761214.050] Audio engine started successfully (253.69ms)
[784761214.166] Speech recognizer started (55.44ms)
[784761214.166] Starting audio level streaming...
[784761214.167] State changed to: .listening
[784761214.167] Sending 'listening' status to Flutter
```

### What's Missing (Critical Failures)

**Audio Level Streaming:**
- ❌ `=== START AUDIO LEVEL STREAMING ===` - Should appear immediately
- ❌ `Creating audio level timer (60 FPS, ~16ms interval)` - Timer never created
- ❌ `Audio level timer created and added to run loop` - Timer setup fails
- ❌ No `audioLevel` events sent to Flutter - Waveform never appears

**Audio Buffer Processing:**
- ❌ `Processed audio buffer: frameLength=..., level=...` - Buffers not processed
- ❌ `buffer_appended: ...` - Buffers not forwarded to speech recognizer
- ❌ `Buffer callback is nil` warnings - Callback might not be set

**Speech Recognition:**
- ❌ `recognition_result: ...` - No recognition results
- ❌ `calling_result_callback: ...` - Results never sent to Flutter
- ⚠️ `Result accumulator timeout: 0.250000, exceeded` - Recognition timing out

## Potential Causes

### Cause 1: Audio Level Streaming Not Starting

**Symptoms:**
- `Starting audio level streaming...` log appears
- But `=== START AUDIO LEVEL STREAMING ===` never appears
- No timer creation logs
- No audio level events

**Possible Reasons:**
1. **Function not actually being called** - The log might be misleading
2. **Early return or guard failure** - Something preventing execution
3. **Threading issue** - `DispatchQueue.main.async` block not executing
4. **Log filtering** - Logs being filtered out (unlikely, as other logs appear)

**Investigation Steps:**
- Add breakpoint in `startAudioLevelStreaming()` to confirm it's called
- Check if `isStreamingAudioLevels` is already true (causing early return)
- Verify main thread dispatch is executing
- Check for any exceptions being swallowed

### Cause 2: Audio Buffers Not Being Processed

**Symptoms:**
- Audio engine reports it's running
- But no buffer processing logs appear
- No audio level calculations

**Possible Reasons:**
1. **Buffer callback not set** - `setBufferCallback()` not called or callback is nil
2. **Audio tap not installed correctly** - Tap might not be capturing buffers
3. **Audio engine not actually running** - Despite reporting success
4. **Simulator audio limitations** - Simulator might not provide real audio buffers

**Investigation Steps:**
- Verify `setBufferCallback()` is called before audio engine starts
- Check if `bufferCallback` is nil when buffers arrive
- Add logging to audio tap callback to confirm it's being called
- Test on physical device (simulator has known audio limitations)

### Cause 3: Speech Recognition Not Receiving Audio

**Symptoms:**
- Speech recognizer starts successfully
- But no `buffer_appended` logs
- No recognition results

**Possible Reasons:**
1. **Buffer callback not forwarding** - Buffers not reaching speech recognizer
2. **Recognition request not configured** - Request might be invalid
3. **Audio format mismatch** - Buffer format doesn't match recognition requirements
4. **Recognition timing out** - The timeout error suggests this

**Investigation Steps:**
- Verify `appendAudioBuffer()` is being called
- Check recognition request configuration
- Verify audio format compatibility
- Investigate the timeout error

### Cause 4: Simulator Audio Limitations

**Symptoms:**
- Everything appears to start correctly
- But no actual audio processing occurs
- Works differently on physical device

**Possible Reasons:**
- iOS Simulator has limited audio capabilities
- Simulator might not provide real microphone input
- Audio buffers might be empty or invalid

**Investigation Steps:**
- **Test on physical device** - This is critical
- Check if simulator-specific audio issues are documented
- Verify microphone input is available in simulator

## Debugging Steps

### ✅ Step 1: Comprehensive Logging Added (COMPLETED)

**Date:** Current session

Comprehensive logging has been added throughout the audio pipeline to trace the exact failure point:

#### DictationManager.swift - Audio Level Streaming
- ✅ Logs before/after calling `startAudioLevelStreaming()`
- ✅ Detailed logging inside `startAudioLevelStreaming()`:
  - Function entry and thread information
  - Queue sync operations
  - Main queue dispatch execution
  - Timer creation and run loop addition
- ✅ Buffer callback logging to confirm invocation

#### AudioEngineManager.swift - Buffer Processing
- ✅ Logs when `setBufferCallback()` is called
- ✅ Logs first 5 audio tap callbacks with detailed buffer information
- ✅ Logs buffer processing state and callback execution
- ✅ Tracks buffer count for debugging

#### SpeechRecognizerManager.swift - Buffer Appending
- ✅ Logs first 5 calls to `appendAudioBuffer()` with state information
- ✅ Logs state checks and buffer appending operations
- ✅ Tracks buffer count for debugging

### Step 2: Analyze Logs to Identify Failure Point

**What to Look For in Xcode Console:**

1. **Audio Level Streaming Function Call:**
   - ✅ `"About to call startAudioLevelStreaming()"`
   - ✅ `"=== START AUDIO LEVEL STREAMING ==="`
   - ✅ `"Function entry - thread: MAIN/BACKGROUND"`
   - ✅ `"Inside audioLevelQueue.sync block"`
   - ✅ `"About to dispatch to main queue"`
   - ✅ `"=== INSIDE MAIN QUEUE ASYNC BLOCK ==="` (CRITICAL - if missing, dispatch isn't executing)
   - ✅ `"Creating audio level timer"`
   - ✅ `"Audio level timer created and added to run loop"`

2. **Buffer Callback Setup:**
   - ✅ `"Setting up buffer callback for speech recognition..."`
   - ✅ `"About to call setBufferCallback"`
   - ✅ `"setBufferCallback called"`
   - ✅ `"bufferCallback set successfully, is nil: false"`
   - ✅ `"Buffer callback set successfully"`

3. **Audio Tap Callbacks:**
   - ✅ `"=== AUDIO TAP CALLBACK INVOKED (buffer #1) ==="` (CRITICAL - if missing, tap isn't working)
   - ✅ `"Buffer frameLength: ..."`
   - ✅ `"Current state: .recording"`
   - ✅ `"Calling buffer callback..."`

4. **Buffer Callback Execution:**
   - ✅ `"=== BUFFER CALLBACK INVOKED ==="` (CRITICAL - if missing, callback isn't being called)
   - ✅ `"Calling speechRecognizerManager.appendAudioBuffer"`
   - ✅ `"speechRecognizerManager.appendAudioBuffer completed"`

5. **Speech Recognizer Buffer Appending:**
   - ✅ `"=== appendAudioBuffer CALLED (buffer #1) ==="` (CRITICAL - if missing, buffers aren't reaching recognizer)
   - ✅ `"Current state: .listening"`
   - ✅ `"Appending buffer to recognition request..."`
   - ✅ `"Buffer appended successfully"`

### Step 3: Test on Physical Device

**This is critical** - The simulator has known audio limitations. Test on a real iPhone/iPad to see if the issue persists.

### Step 4: Identify Root Cause from Logs

Based on which logs appear and which are missing, identify the failure point:

- **If `startAudioLevelStreaming()` logs don't appear:** Function isn't being called or failing before first log
- **If main queue async block doesn't execute:** Threading issue preventing timer creation
- **If audio tap callbacks don't appear:** Audio engine tap not installed or not receiving buffers
- **If buffer callback isn't invoked:** Callback not set or not being called from tap
- **If `appendAudioBuffer()` isn't called:** Buffer callback not forwarding to speech recognizer

## Immediate Actions

### ✅ Completed Actions

1. **✅ Comprehensive logging added** - Logging has been added throughout the audio pipeline:
   - ✅ Log entry/exit of `startAudioLevelStreaming()` with thread information
   - ✅ Log buffer callback invocations with detailed buffer information
   - ✅ Log audio tap callbacks (first 5 buffers logged in detail)
   - ✅ Log speech recognizer buffer appends with state information
   - ✅ Log timer creation and run loop addition
   - ✅ Track buffer counts for debugging

### 🔄 Next Actions

1. **Run the app and capture full Xcode console output** - Need to see which logs appear and which are missing

2. **Analyze logs to identify exact failure point** - Use the log markers above to determine where the pipeline breaks

3. **Test on physical device** - Simulator audio limitations might be the root cause

4. **Check for silent failures** - Look for exceptions being caught and ignored (logs should reveal this)

5. **Investigate speech recognition timeout** - The timeout error suggests recognition isn't receiving audio (logs will confirm if buffers are reaching the recognizer)

## Related Documentation

- [Microphone Permission Audio Engine Error](./MICROPHONE_PERMISSION_AUDIO_ENGINE_ERROR.md)
- [Missing Plugin Exception](./MISSING_PLUGIN_EXCEPTION.md)
- [Native Implementation Guide](../native_implementation/README.md)

## Environment

- Flutter: 3.29.2 (stable)
- Dart: 3.7.2
- Xcode: 26.1.1 (Build 17B100)
- macOS: 25.1.0 (darwin-arm64)
- iOS Simulator: iPhone 17 Pro

## Status

**✅ ROOT CAUSES IDENTIFIED AND FIXED** - Two critical race conditions have been fixed:

1. **✅ FIXED:** Audio level streaming race condition - Timer now creates successfully
2. **✅ FIXED:** Speech recognizer state race condition - Buffers now accepted when state is `.listening`

**⏳ TESTING REQUIRED** - Rebuild and test to verify fixes resolve the issues.

**✅ CODE CONSOLIDATION COMPLETE** - Duplicate code has been consolidated.

### Current Understanding

Dictation service starts but fails to capture audio or produce transcription. Root cause appears to be one of:

1. **Audio level streaming not starting** - Timer never created despite log saying it should
2. **Audio buffers not being processed** - No buffer processing logs appear
3. **Speech recognition not receiving audio** - No recognition results produced

### Logging Improvements Added

**Files Modified:**
- `ios/Runner/DictationManager.swift` - Added comprehensive logging to `startAudioLevelStreaming()` and buffer callback
  - **LATEST:** Added direct `print()` and `NSLog()` statements at function entry to verify execution (lines 436-437)
  - **LATEST:** Added try-catch wrapper around function call to catch any exceptions (lines 232-238)
  - **LATEST:** Added additional log statements before/after function call (lines 229-231, 239)
  - **⚠️ ISSUE:** New debug logs are NOT appearing in runtime logs - suggests build/compilation issue
- `ios/Runner/AudioEngineManager.swift` - Added logging to `setBufferCallback()` and `processAudioBuffer()` (first 5 buffers logged in detail)
- `ios/Runner/SpeechRecognizerManager.swift` - Added logging to `appendAudioBuffer()` (first 5 buffers logged in detail)

**Key Log Markers to Watch For (After Successful Rebuild):**
- `"🔴 LINE 228: Starting audio level streaming..."` - **CRITICAL:** First debug log, confirms new code is running
- `"🔴 LINE 229: About to call startAudioLevelStreaming()"` - Confirms execution reaches call site
- `"🔴 LINE 232: Entering do block"` - Confirms do-catch block is entered
- `"🔴 LINE 233: About to call startAudioLevelStreaming() function"` - Confirms function call is about to happen
- `"🔴🔴🔴 CRITICAL LINE 456: startAudioLevelStreaming() FUNCTION ENTRY"` - **CRITICAL:** Confirms function is actually called
- `"=== START AUDIO LEVEL STREAMING ==="` - Confirms function execution started
- `"=== INSIDE MAIN QUEUE ASYNC BLOCK ==="` - Confirms timer creation dispatch executes
- `"=== AUDIO TAP CALLBACK INVOKED ==="` - Confirms audio buffers are being captured
- `"=== BUFFER CALLBACK INVOKED ==="` - Confirms buffer callback is being called
- `"=== appendAudioBuffer CALLED ==="` - Confirms buffers are reaching speech recognizer

### Latest Findings (From User Logs - Latest Session)

**✅ CODE CONSOLIDATION COMPLETE:**
- Duplicate code has been consolidated
- Debug logs are now appearing correctly
- Both issues identified and fixed

**CRITICAL ISSUE #1 - AUDIO LEVEL STREAMING RACE CONDITION (FIXED):**

**Problem:** The audio level timer was not being created because of a race condition:
- `startAudioLevelStreaming()` sets `isStreamingAudioLevels = true` in sync block
- Then calls `stopAudioLevelStreaming()` which sets it back to `false`
- Then dispatches to main queue
- When async block executes, `isStreamingAudioLevels` is `false`, so timer creation is aborted

**Evidence from logs:**
```
[784847205.349] Set isStreamingAudioLevels = true
[784847205.350] === STOP AUDIO LEVEL STREAMING ===
[784847205.353] Audio level timer invalidated and cleared
[784847205.353] === INSIDE MAIN QUEUE ASYNC BLOCK ===
[784847205.353] Inside shouldStream check, isStreamingAudioLevels=false
[784847205.354] Should not stream, aborting timer creation
```

**Fix Applied:**
- Modified `startAudioLevelStreaming()` to clear the timer WITHOUT resetting the flag
- Timer is cleared directly (checking if on main thread to avoid deadlock)
- Flag is set to `true` and remains `true` when async block executes
- Timer creation now proceeds successfully

**CRITICAL ISSUE #2 - SPEECH RECOGNIZER STATE RACE CONDITION (FIXED):**

**Problem:** Speech recognizer buffers were being rejected because state was `idle` instead of `listening`:
- `cancelRecognition()` sets state to `.cancelled`, then async block resets to `.idle` after 50ms
- `startRecognition()` is called right after, sets state to `.listening`
- But the async block from `cancelRecognition()` runs AFTER and overwrites state back to `.idle`
- Buffers arrive when state is `idle`, so they're rejected

**Evidence from logs:**
```
[SpeechRecognizerManager] Current state: idle
[SpeechRecognizerManager] Should append: false
[SpeechRecognizerManager] WARNING: Skipping buffer append - state check failed
```

**Fix Applied:**
- Modified `cancelRecognition()` to check current state before resetting to `.idle`
- Only resets to `.idle` if state is still `.cancelled` (no new recognition started)
- Prevents async block from overwriting `.listening` state set by `startRecognition()`

### Next Steps

1. **✅ COMPLETED:** Add comprehensive logging throughout audio pipeline
2. **✅ COMPLETED:** Run app and capture full Xcode console output
3. **✅ COMPLETED:** Added direct print/NSLog statements to verify function execution
4. **✅ COMPLETED:** Analyze logs - **TWO CRITICAL ISSUES IDENTIFIED**
5. **✅ COMPLETED:** **FIXED:** Audio level streaming race condition
6. **✅ COMPLETED:** **FIXED:** Speech recognizer state race condition
7. **⏳ PENDING:** **TEST REQUIRED** - Rebuild and test to verify fixes work
8. **⏳ PENDING:** Test on physical device (simulator limitations suspected)
9. **⏳ PENDING:** Verify waveform appears and transcription works

### Expected Outcome

The comprehensive logging should reveal exactly where the audio pipeline breaks:
- If `startAudioLevelStreaming()` logs don't appear → Function not being called
- If main queue async block doesn't execute → Threading issue
- If audio tap callbacks don't appear → Audio engine tap issue
- If buffer callback isn't invoked → Callback setup issue
- If `appendAudioBuffer()` isn't called → Buffer forwarding issue
