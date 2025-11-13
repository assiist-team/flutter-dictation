# Microphone Permission & Audio Engine Startup Error

## Issue Description

When launching the example app and tapping the record button, the app fails with an "Audio engine failed to start" error. The microphone permission dialog never appears, and the audio engine cannot start.

## Error Message

```
flutter: Dictation error: Audio engine failed to start. Please try again.
flutter: Error during start/listen: PlatformException(AUDIO_ENGINE_ERROR, Audio engine failed to start. Please try again., null, null)
```

## Symptoms

- App launches successfully
- No microphone permission dialog appears when tapping record button
- Error occurs immediately when attempting to start recording
- Error code: `AUDIO_ENGINE_ERROR`
- Error message: "Audio engine failed to start. Please try again."

## Root Cause Hypothesis

The audio engine is failing to start because:

1. **Microphone permission is not granted** - The permission dialog is not appearing, so permission remains `.undetermined` or `.denied`
2. **Audio session configuration timing** - The audio session category may need to be set before requesting permission, but the permission request may not be triggering the system dialog
3. **Audio engine preparation failure** - The audio engine may be failing to prepare/start due to missing permissions or incorrect audio session state

## Attempted Fixes

### Fix 1: Deferred Audio Session Configuration
**Date:** Initial attempt
**What was tried:**
- Removed audio session category configuration from `initialize()` method
- Moved `configureAudioSession()` call to `startRecording()` after permission check
- Rationale: Avoid requiring permissions during initialization

**Result:** ❌ Failed - Permission dialog still did not appear

### Fix 2: Main Thread Permission Request
**Date:** Second attempt
**What was tried:**
- Ensured `requestMicrophonePermission()` runs on main thread
- Added thread checking and dispatch to main queue if needed
- Rationale: iOS requires permission dialogs to appear on main thread

**Result:** ❌ Failed - Permission dialog still did not appear

### Fix 3: Set Category Before Permission Request
**Date:** Third attempt
**What was tried:**
- Set audio session category to `.record` BEFORE requesting permission
- Split audio session configuration into two parts:
  1. Set category first (doesn't require permission, just declares intent)
  2. Request permission after category is set
  3. Complete configuration (buffer duration, sample rate, activation) after permission granted
- Added debug logging to track permission status and request flow
- Rationale: iOS needs to know why permission is needed (via category) before showing dialog

**Result:** ❌ Failed - Still getting "Audio engine failed to start" error

### Fix 4: Fix Swift Compiler Error - MainActor.run with Async Function
**Date:** After Fix 3, following Swift compiler error
**What was tried:**
- Fixed Swift compiler error: "Cannot pass function of type '@Sendable () async -> Bool' to parameter expecting synchronous function type"
- Changed from `MainActor.run { return await requestMicrophonePermission() }` to `Task { @MainActor in await requestMicrophonePermission() }.value`
- Rationale: `MainActor.run` expects a synchronous closure, but `requestMicrophonePermission()` is async. Using `Task { @MainActor in ... }` allows async code to run on main actor
- Applied fix to both `ios/Runner/AudioEngineManager.swift` and `example/ios/Runner/AudioEngineManager.swift`

**Result:** ❌ Failed - Same error as before. No permission dialog appeared, no permission was granted. Error: "Audio engine failed to start. Please try again."

## Current Code Flow

1. User taps record button
2. `startRecording()` is called
3. Audio session category is set to `.record` mode `.measurement`
4. Permission status is checked
5. If not granted, `requestMicrophonePermission()` is called
6. Audio session configuration is completed (buffer duration, sample rate, activation)
7. Audio engine is prepared
8. Audio tap is installed
9. Audio engine is started → **FAILS HERE**

## Debug Logging Added

The following debug logs were added to help diagnose the issue:

- `[AudioEngineManager] Requesting microphone permission. Current status: <status>`
- `[AudioEngineManager] Calling requestRecordPermission on thread: main/background`
- `[AudioEngineManager] Permission request completed. Granted: <true/false>`
- `[AudioEngineManager] Audio engine start failed: <error>`
- `[AudioEngineManager] Permission status: <status>`
- `[AudioEngineManager] Audio session category: <category>`

## Possible Root Causes

### 1. Permission Dialog Not Triggering
- iOS may require the app to be in a specific state to show permission dialogs
- The permission request may be happening too early or in the wrong context
- There may be a system-level issue preventing the dialog from appearing

### 2. Audio Session State Issues
- The audio session may be in an invalid state when trying to start the engine
- There may be conflicts with other audio sessions or system audio
- The category/mode combination may not be compatible with the current iOS version

### 3. Audio Engine Preparation Failure
- The audio engine may be failing to prepare due to hardware unavailability
- There may be an exception being thrown during `audioEngine.prepare()` that's not being caught properly
- The audio engine may need additional configuration before it can start

### 4. Info.plist Configuration
- The `NSMicrophoneUsageDescription` and `NSSpeechRecognitionUsageDescription` keys are present in Info.plist
- However, there may be an issue with how they're being read or if they're in the correct location (plugin vs example app)

## Investigation Needed

### 1. Check Console Logs
Run the app and check Xcode console for:
- The debug log messages showing permission status
- Any system-level errors or warnings
- Audio session interruption notifications
- Any AVAudioEngine or AVAudioSession errors

### 2. Verify Info.plist
Check that both Info.plist files have the required keys:
- `NSMicrophoneUsageDescription` - Present ✓
- `NSSpeechRecognitionUsageDescription` - Present ✓

Verify they're in:
- `/ios/Runner/Info.plist` (plugin)
- `/example/ios/Runner/Info.plist` (example app)

### 3. Test Permission Status Directly
Add code to check permission status at various points:
- Before setting category
- After setting category
- Before requesting permission
- After requesting permission
- Before starting audio engine

### 4. Test on Physical Device
The issue may be simulator-specific. Test on a physical iOS device to see if:
- Permission dialog appears
- Audio engine starts successfully
- Different error messages appear

### 5. Check iOS Version Compatibility
Verify that:
- The audio session category/mode combination is supported on the target iOS version
- The permission request API is being called correctly for the iOS version
- There are no deprecated APIs being used

### 6. Test Minimal Example
Create a minimal test case that:
- Only requests microphone permission
- Only starts audio engine
- No speech recognition
- No waveform visualization
- This will help isolate whether the issue is with audio engine or with the integration

## Related Files

- `ios/Runner/AudioEngineManager.swift` - Main audio engine management
- `example/ios/Runner/AudioEngineManager.swift` - Example app copy
- `ios/Runner/DictationManager.swift` - Coordinates audio engine and speech recognition
- `ios/Runner/Info.plist` - Permission descriptions
- `example/ios/Runner/Info.plist` - Example app permission descriptions
- `lib/services/native_dictation_service.dart` - Flutter service interface

## Environment

- Flutter: 3.29.2 (stable)
- Dart: 3.7.2
- Xcode: 26.1.1 (Build 17B100)
- macOS: 25.1.0 (darwin-arm64)
- iOS Simulator: iPhone 17 Pro
- iOS Version: (check simulator/device version)

## Fix Applied

**Date:** Latest fix
**What was fixed:**

### 1. Permission Request Threading and Context Preservation
- **Issue:** Permission request was wrapped in `Task { @MainActor in ... }.value` which might break the user action context required by iOS
- **Fix:** 
  - Changed to use `MainActor.run` to ensure main thread execution
  - Modified `requestMicrophonePermission()` to check if already on main thread and call `requestRecordPermission` directly without additional async dispatch when on main thread
  - This preserves the user action context that iOS requires for permission dialogs to appear
- **Code:** 
  - Changed permission request call from `Task { @MainActor in ... }.value` to `MainActor.run { await requestMicrophonePermission() }`
  - Modified `requestMicrophonePermission()` to check `Thread.isMainThread` and call directly if on main thread, otherwise dispatch to main thread

### 2. Audio Session State Verification
- **Issue:** Audio session state wasn't being verified before activation and engine start
- **Fix:** Added explicit permission checks before audio session activation and before engine start
- **Code:** 
  - Added `preActivationPermission` check before `setActive(true)`
  - Added pre-start verification with checks for permission, session active state, and category

### 3. Enhanced Error Handling and Diagnostics
- **Issue:** Error messages were generic and didn't provide enough context for debugging
- **Fix:** 
  - Added comprehensive pre-start verification logging
  - Added detailed error messages that identify specific failure scenarios
  - Added checks for other apps using microphone
  - Improved error messages to guide users to Settings when permission is denied
- **Code:** 
  - Added pre-start verification print statements
  - Enhanced error messages with specific guidance based on failure scenario
  - Added check for `isOtherAudioPlaying` to detect conflicts

### 4. Permission Status Error Messages
- **Issue:** Error messages didn't distinguish between denied and other permission states
- **Fix:** Added specific error messages for denied vs other permission states with guidance
- **Code:** Added conditional error message based on `finalPermissionStatus == .denied`

### 5. Audio Session Activation Error Handling
- **Issue:** Audio session activation failures weren't providing enough context
- **Fix:** Added explicit permission check before activation and better error messages
- **Code:** Added `preActivationPermission` guard and enhanced error handling with `isOtherAudioPlaying` check

## Changes Made

1. **Permission Request Context Preservation:** 
   - Changed from `Task { @MainActor in ... }.value` to `MainActor.run { await ... }`
   - Modified `requestMicrophonePermission()` to preserve user action context by checking if already on main thread
   - If on main thread, call `requestRecordPermission` directly; otherwise dispatch to main thread

2. **Pre-Activation Permission Check:** Verify permission is granted before attempting to activate audio session

3. **Pre-Start Verification:** Added comprehensive state verification before starting audio engine:
   - Permission granted check
   - Session active check  
   - Category correct check
   - Engine prepared check

4. **Enhanced Error Messages:** 
   - Specific messages for denied permissions with Settings guidance
   - Detection of other apps using microphone
   - Detailed diagnostic information in error messages

5. **Debug Logging:** Added comprehensive logging throughout:
   - Thread information (main/background)
   - Permission status at each step
   - Pre-start verification details
   - Detailed error diagnostics

## Testing

**Actions performed:**

- Modified `requestMicrophonePermission()` to ensure main-thread execution and preserve user-action context.
- Replaced the previous `MainActor.run { await requestMicrophonePermission() }` usage with `Task { @MainActor in ... }.value` where required to satisfy Swift compiler constraints.
- Added pre-activation permission checks and pre-start verification logging in the audio startup sequence.
- Applied these edits to both `ios/Runner/AudioEngineManager.swift` and `example/ios/Runner/AudioEngineManager.swift`.
- Updated this troubleshooting document to record the changes and outcomes.

**Results observed:**

- During an intermediate build, Xcode reported a Swift compiler error: "Cannot pass function of type '@Sendable () async -> Bool' to parameter expecting synchronous function type" in `example/ios/Runner/AudioEngineManager.swift`. This was resolved by switching the permission-call site to `Task { @MainActor in ... }.value`.
- After the fixes, no linter errors were reported for the edited files.
- When running the app, Flutter emitted the following runtime logs:

```
flutter: Dictation error: Audio engine failed to start. Please try again.
flutter: Error during start/listen: PlatformException(AUDIO_ENGINE_ERROR, Audio engine failed to start. Please try again., null, null)
```

- The runtime `AUDIO_ENGINE_ERROR` persisted after the native-code edits; additional native debug logging was added to the native code to capture more diagnostic information.

## Fix Applied (Latest)

**Date:** Current fix
**What was fixed:**

### Root Cause Identified
The permission dialog was not appearing because the user action context was being broken by the `Task { @MainActor in ... }.value` wrapper. iOS requires permission requests to be triggered **directly** from user actions on the main thread, and wrapping the permission request in a Task breaks this context chain.

### Solution Implemented

1. **Main Thread Context Preservation in DictationManager:**
   - Changed `handleStartListening()` to use `Task { @MainActor in ... }` instead of `Task { ... }`
   - This ensures the entire flow (including `startRecording()`) runs on the main thread
   - Preserves the user action context chain from Flutter → DictationManager → AudioEngineManager

2. **Removed Task Wrapper from Permission Request:**
   - Removed `Task { @MainActor in ... }.value` wrapper from `startRecording()` permission request
   - Now calls `requestMicrophonePermission()` directly since we ensure main thread upstream
   - Added guard check to verify main thread execution (programming error if not)
   - This preserves the direct user action → permission request chain that iOS requires

3. **Applied to Both Files:**
   - Fixed `ios/Runner/AudioEngineManager.swift` and `ios/Runner/DictationManager.swift`
   - Fixed `example/ios/Runner/AudioEngineManager.swift` and `example/ios/Runner/DictationManager.swift`

### Key Changes

**DictationManager.swift:**
```swift
// Before:
Task {
    try await audioEngineManager.startRecording()
}

// After:
Task { @MainActor in
    try await audioEngineManager.startRecording()
}
```

**AudioEngineManager.swift:**
```swift
// Before:
let granted = await Task { @MainActor in
    return await requestMicrophonePermission()
}.value

// After:
guard Thread.isMainThread else {
    throw NSError(...) // Programming error
}
let granted = await requestMicrophonePermission()
```

### Why This Should Work

iOS has strict requirements for permission dialogs:
1. Must be triggered from a user action (button tap)
2. Must be on the main thread
3. Must preserve the call stack context from user action → permission request

The `Task { @MainActor in ... }.value` pattern creates a new task context that breaks the call stack chain, preventing iOS from recognizing it as a direct user action. By ensuring the entire flow runs on `@MainActor` and calling the permission request directly, we preserve the user action context.

**Result:** ❌ Failed - Still getting the same error:
```
flutter: Dictation error: Audio engine failed to start. Please try again.
flutter: Error during start/listen: PlatformException(AUDIO_ENGINE_ERROR, Audio engine failed to start. Please try again., null, null)
```

The permission dialog still does not appear, and the audio engine fails to start. The main thread context preservation approach did not resolve the issue.

### Fix 5: Comprehensive Logging Enhancement
**Date:** Latest attempt
**What was tried:**
- Added comprehensive logging throughout the entire flow to diagnose the issue
- Enhanced logging in `AudioEngineManager.swift`:
  - Detailed permission request flow logging (status, thread, timing, call stack)
  - Audio session state logging (permission, category, mode, sample rate, buffer duration)
  - Audio engine state logging (running, prepared, input format)
  - Step-by-step logging in `startRecording()` with timing information
  - Detailed error logging (domain, code, userInfo, localizedDescription)
- Enhanced logging in `DictationManager.swift`:
  - Method channel call logging (method name, arguments, thread, state)
  - State transition logging
  - Error propagation logging with full context
  - Timing information for each operation
- Enhanced logging in `native_dictation_service.dart`:
  - Flutter-side method call logging
  - PlatformException details (code, message, details, stacktrace)
  - Retry logic logging for initialization
- Logging format includes:
  - Timestamp (milliseconds precision)
  - Component name (`[AudioEngineManager]`, `[DictationManager]`, `[NativeDictationService]`)
  - Log level (`DEBUG`, `INFO`, `WARN`, `ERROR`)
  - Thread information (`MAIN` or `BG`)
  - File name, line number, and function name
  - Detailed message
- Logs are visible in both Xcode console (via `print()` and `NSLog()`) and Flutter console (via `print()`)

**Result:** ❌ Failed - Swift compiler errors occurred:
- Multiple errors: "Call to method 'log' in closure requires explicit use of 'self' to make capture semantics explicit"
- Errors occurred in `requestMicrophonePermission()` method where logging calls inside closures needed explicit `self.` prefix
- Fixed by adding `self.` prefix to all `log()` and `logAudioSessionState()` calls inside closures
- After fix, code compiles successfully but logging enhancement is now complete and ready for testing

**Next Steps:**
1. Run the app with enhanced logging and check both Xcode console and Flutter console
2. Look for permission request flow logs to see:
   - Where permission request is called
   - What thread it's on
   - Whether permission callback fires
   - What the audio session state is when engine fails
   - Exact error messages and domain/code
3. Use the comprehensive logs to identify where the flow breaks and why permission dialog doesn't appear

## Next Steps

1. **Test with enhanced logging** - Run the app and check both Xcode console and Flutter console for detailed logs
2. **Analyze permission flow** - Look for permission request logs to see thread, timing, and callback behavior
3. **Check audio session state** - Review audio session state logs at each step to identify configuration issues
4. **Review error details** - Examine detailed error logs (domain, code, userInfo) to understand failure points
5. **Test on physical device** - Verify the behavior on real hardware (not just simulator) with enhanced logging

## Related Documentation

- [DDS Connection Error](./DDS_CONNECTION_ERROR.md)
- [Missing Plugin Exception](./MISSING_PLUGIN_EXCEPTION.md)
- [Native Implementation Guide](../native_implementation/README.md)

