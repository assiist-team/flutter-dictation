# Dart Development Service (DDS) Connection Error

## Issue Description

After recent code changes (native iOS implementation migration), `flutter run` fails with a DDS connection error. The app builds successfully, but Flutter cannot connect to the Dart Development Service for debugging/hot reload.

## Error Message

```
Error connecting to the service protocol: failed to connect to http://127.0.0.1:XXXXX/XXXXX=/ DartDevelopmentServiceException: Failed to start Dart Development Service
```

## Symptoms

- Xcode build completes successfully
- App may actually be running on the simulator/device
- Flutter tool cannot establish DDS connection
- Hot reload and debugging features unavailable
- Error occurs consistently across multiple port attempts

## What Changed

This issue appeared after migrating to native iOS implementation. Previously, the app ran without DDS errors.

## Workaround

The app **does run successfully** when using the `--no-dds` flag:

```bash
cd example
flutter run --no-dds
```

**Note:** This disables Dart Development Service, which means:
- Hot reload still works (via VM Service)
- Advanced debugging features may be limited
- DevTools connection may not work

## Root Cause Analysis Needed

The issue appears to be related to:
1. DDS failing to start/connect after the app launches
2. VM Service is available (visible in verbose logs)
3. DDS cannot establish connection to VM Service
4. May be related to recent native code changes or Flutter version compatibility

## Additional Issues Found

### Compilation/Linter Errors

There are **403 linter errors** across the codebase, likely due to:

1. **Missing Flutter packages resolution**
   - All test files show "Target of URI doesn't exist" for Flutter packages
   - Service files show missing Flutter imports
   - Widget files show missing Flutter imports

2. **Analysis options issue**
   - `analysis_options.yaml` references `package:flutter_lints/flutter.yaml` which may not be resolved
   - Likely needs `flutter pub get` to be run

3. **Affected directories:**
   - `test/` - All test files have import errors
   - `lib/services/` - `native_dictation_service.dart` has import errors
   - `lib/widgets/` - All widget files have import errors
   - `lib/theme/` - Theme files have import errors
   - `legacy/lib/services/` - Legacy service files have import errors

## Next Steps for Troubleshooting

1. **Run `flutter pub get`** in both root and example directories to resolve package dependencies
2. **Check if errors persist** after package resolution
3. **Investigate DDS issue** - May need to:
   - Check Flutter version compatibility (currently 3.29.2)
   - Review recent Flutter/Dart SDK changes
   - Check if native code changes affected VM Service initialization
   - Review iOS simulator/device connection
4. **Test with physical device** to see if issue is simulator-specific
5. **Check Flutter logs** for more detailed DDS startup errors

## Files Modified Recently

Based on git status, these files were modified:
- `example/ios/Runner.xcodeproj/project.pbxproj`
- `example/ios/Runner/AppDelegate.swift`
- `example/lib/main.dart`
- `ios/Runner/AppDelegate.swift`
- `ios/Runner/SpeechRecognizerManager.swift`
- `lib/services/native_dictation_service.dart`

## Environment

- Flutter: 3.29.2 (stable)
- Dart: 3.7.2
- Xcode: 26.1.1 (Build 17B100)
- macOS: 25.1.0 (darwin-arm64)
- iOS Simulator: iPhone 17 Pro

## Related Documentation

- [MissingPluginException Troubleshooting](./MISSING_PLUGIN_EXCEPTION.md)
- [Native Implementation Guide](../native_implementation/README.md)

update: ran flutter pub get and this happened:

Resolving dependencies in `/Users/benjaminmackenzie/Dev/flutter_dictation/example`... 
Downloading packages... 
  async 2.12.0 (2.13.0 available)
  characters 1.4.0 (1.4.1 available)
  fake_async 1.3.2 (1.3.3 available)
  flutter_lints 5.0.0 (6.0.0 available)
  leak_tracker 10.0.8 (11.0.2 available)
  leak_tracker_flutter_testing 3.0.9 (3.0.10 available)
  leak_tracker_testing 3.0.1 (3.0.2 available)
  lints 5.1.1 (6.0.0 available)
  material_color_utilities 0.11.1 (0.13.0 available)
  meta 1.16.0 (1.17.0 available)
  test_api 0.7.4 (0.7.8 available)
  vector_math 2.1.4 (2.2.0 available)
  vm_service 14.3.1 (15.0.2 available)
Got dependencies in `/Users/benjaminmackenzie/Dev/flutter_dictation/example`!
13 packages have newer versions incompatible with dependency constraints.
Try `flutter pub outdated` for more information.
benjaminmackenzie@MacBook-Pro ios % 