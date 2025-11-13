# MissingPluginException: Platform Channel Not Found

## Issue Description

When attempting to initialize the native dictation service, the app throws a `MissingPluginException` indicating that the platform channel handler for `com.flutter_dictation/methods` is not found.

This error occurs when **platform channels are not registered in the app's AppDelegate**. Platform channels must be set up in the native iOS code (Swift/Objective-C) during app initialization.

## Symptoms

- `MissingPluginException` when calling `initialize()` on `NativeDictationService`
- Error message: "No implementation found for method initialize on channel com.flutter_dictation/methods"
- Error persists even after full rebuild
- Retry mechanism fails after multiple attempts

## Logs

### Error Message

```
flutter: Error during initialization: Exception: Failed to initialize dictation: Platform channels not available after 10 retries. Please ensure the app has been rebuilt after adding native code.
```

### iOS Console (if channels aren't set up)

```
AppDelegate: ERROR - Failed to set up platform channels after 10 retries
AppDelegate: Window: nil
AppDelegate: RootViewController: nil
```

## Root Cause

The platform channel setup must be implemented in **each app's AppDelegate**. For the example app, this means:

1. **Example app has its own AppDelegate** (`example/ios/Runner/AppDelegate.swift`)
2. The example app's AppDelegate must register the platform channels
3. The Swift manager classes (`DictationManager`, `AudioEngineManager`, `SpeechRecognizerManager`) must be accessible to the example app
4. Platform channels are registered during `didFinishLaunchingWithOptions`, but timing issues can occur if the FlutterViewController isn't ready yet

## Solution

**Ensure platform channels are set up in your app's AppDelegate:**

1. **For the example app**: The AppDelegate has been updated to include platform channel setup
2. **For other apps using this plugin**: Copy the platform channel setup code from `example/ios/Runner/AppDelegate.swift` to your app's AppDelegate
3. **Ensure Swift files are accessible**: The manager classes must be in your app's Xcode project or accessible via the plugin framework

**After making changes, perform a full rebuild:**

```bash
# Stop the app completely
# Then rebuild and run:
flutter clean
flutter pub get
cd ios && pod install && cd ..
flutter run
```

Or in your IDE:
- Stop the app completely
- Use "Run" (not "Hot Restart" or "Hot Reload")
- This will rebuild the native iOS code and register the platform channels

## Verification

After a full rebuild, you should see in the iOS console:
```
AppDelegate: Platform channels set up successfully
AudioEngineManager: Pre-warmed successfully
SpeechRecognizerManager: Pre-warmed successfully
```

And the `initialize()` method should succeed without errors.

## Additional Notes

- **Hot reload/hot restart** only reloads Dart code - native code changes require a full rebuild
- **Platform channel registration** happens at app startup, so timing is critical
- The retry mechanism with exponential backoff helps handle timing issues
- A fallback in `applicationDidBecomeActive` ensures channels are set up even if launch-time setup fails
- Each app using this plugin must have platform channels registered in its own AppDelegate

