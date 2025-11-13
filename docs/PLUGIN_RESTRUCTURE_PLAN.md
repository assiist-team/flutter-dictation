# Flutter Plugin Restructure Plan

## Problem Statement

**Current Issue:** The project has duplicate native iOS code in two locations:
- `ios/Runner/` (plugin root)
- `example/ios/Runner/` (example app)

This violates the core principle of code centralization and makes maintenance impossible. Changes must be made in two places, leading to bugs and confusion.

**Goal:** Restructure as a proper Flutter plugin where:
- ✅ Native code exists in ONE location (plugin's `ios/Classes/`)
- ✅ Example app uses the plugin's code (no duplicates)
- ✅ Development workflow remains smooth (can run example app)
- ✅ Plugin can be published/used by other apps

## Current Structure (WRONG)

```
flutter_dictation/
├── ios/Runner/                          # ❌ Native code here (wrong location)
│   ├── DictationManager.swift
│   ├── AudioEngineManager.swift
│   └── SpeechRecognizerManager.swift
├── lib/                                 # ✅ Dart code (correct)
├── example/
│   └── ios/Runner/                     # ❌ DUPLICATE native code (wrong!)
│       ├── DictationManager.swift      # ❌ Same files, different versions
│       ├── AudioEngineManager.swift    # ❌ Out of sync with plugin
│       └── SpeechRecognizerManager.swift # ❌ Causes bugs
└── (no .podspec file)                  # ❌ Not a proper plugin
```

## Target Structure (CORRECT)

```
flutter_dictation/
├── ios/
│   ├── Classes/                        # ✅ Native code HERE (plugin code)
│   │   ├── DictationManager.swift
│   │   ├── AudioEngineManager.swift
│   │   ├── SpeechRecognizerManager.swift
│   │   └── AudioEngineHelper.h/m
│   ├── flutter_dictation.podspec      # ✅ Plugin definition
│   └── Podfile                        # ✅ For plugin development
├── lib/                                # ✅ Dart code
│   ├── flutter_dictation.dart
│   └── services/
├── example/                            # ✅ Example app (NO native code!)
│   ├── lib/                           # ✅ Only Dart code
│   └── ios/Runner/
│       ├── AppDelegate.swift          # ✅ Only registers plugin
│       └── Info.plist                 # ✅ App config only
└── pubspec.yaml                        # ✅ Plugin definition
```

## Step-by-Step Migration Plan

### Phase 1: Create Proper Plugin Structure

#### Step 1.1: Create `ios/Classes/` Directory
```bash
mkdir -p ios/Classes
```

#### Step 1.2: Move Native Code to `ios/Classes/`
```bash
# Move Swift files
mv ios/Runner/DictationManager.swift ios/Classes/
mv ios/Runner/AudioEngineManager.swift ios/Classes/
mv ios/Runner/SpeechRecognizerManager.swift ios/Classes/
mv ios/Runner/AudioEngineHelper.h ios/Classes/
mv ios/Runner/AudioEngineHelper.m ios/Classes/
```

#### Step 1.3: Create `flutter_dictation.podspec`
Create `ios/flutter_dictation.podspec`:
```ruby
Pod::Spec.new do |s|
  s.name             = 'flutter_dictation'
  s.version          = '0.0.1'
  s.summary          = 'Flutter plugin for native iOS dictation'
  s.description      = <<-DESC
A Flutter plugin providing native iOS dictation with low-latency speech recognition.
                       DESC
  s.homepage         = 'https://github.com/yourusername/flutter_dictation'
  s.license          = { :file => '../LICENSE' }
  s.author           = { 'Your Name' => 'your.email@example.com' }
  s.source           = { :path => '.' }
  s.source_files     = 'Classes/**/*'
  s.public_header_files = 'Classes/**/*.h'
  s.dependency 'Flutter'
  s.platform = :ios, '13.0'
  s.swift_version = '5.0'
  
  # Flutter.framework does not contain a i386 slice.
  s.pod_target_xcconfig = { 'DEFINES_MODULE' => 'YES', 'EXCLUDED_ARCHS[sdk=iphonesimulator*]' => 'i386' }
end
```

### Phase 2: Update Example App

#### Step 2.1: Remove Duplicate Native Files from Example
```bash
# Remove duplicate Swift files
rm example/ios/Runner/DictationManager.swift
rm example/ios/Runner/AudioEngineManager.swift
rm example/ios/Runner/SpeechRecognizerManager.swift
rm example/ios/Runner/AudioEngineHelper.h
rm example/ios/Runner/AudioEngineHelper.m
```

#### Step 2.2: Update Example App's AppDelegate
The example app's `AppDelegate.swift` should ONLY:
1. Import Flutter
2. Register the plugin (Flutter handles this automatically via podspec)
3. Set up platform channels (if needed for testing)

**File:** `example/ios/Runner/AppDelegate.swift`
```swift
import UIKit
import Flutter

@UIApplicationMain
@objc class AppDelegate: FlutterAppDelegate {
  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    // Flutter will automatically register plugins via podspec
    GeneratedPluginRegistrant.register(with: self)
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }
}
```

#### Step 2.3: Update Example App's Podfile
**File:** `example/ios/Podfile`
```ruby
platform :ios, '13.0'

# ... existing Flutter setup ...

target 'Runner' do
  use_frameworks!
  
  # Flutter will automatically include the plugin via pubspec.yaml
  flutter_install_all_ios_pods File.dirname(File.realpath(__FILE__))
end
```

The plugin will be automatically included because:
- `example/pubspec.yaml` has `flutter_dictation: path: ../`
- Flutter reads `ios/flutter_dictation.podspec`
- CocoaPods includes the plugin's `Classes/` files

### Phase 3: Update Plugin Registration

#### Step 3.1: Create Plugin Registration File
**File:** `ios/Classes/FlutterDictationPlugin.swift` (if needed)
```swift
import Flutter
import UIKit

public class FlutterDictationPlugin: NSObject, FlutterPlugin {
  public static func register(with registrar: FlutterPluginRegistrar) {
    // Platform channels are set up in AppDelegate
    // This is just for plugin registration if needed
  }
}
```

#### Step 3.2: Update Root AppDelegate (if exists)
If there's an `ios/Runner/AppDelegate.swift` at the root (for plugin testing), it should:
- Set up platform channels for the plugin
- This is ONLY for plugin development/testing

**Note:** The root `ios/Runner/` directory might not be needed if we're purely a plugin. We can keep it for plugin development/testing, but it should reference `Classes/` files, not duplicate them.

### Phase 4: Update Build Configuration

#### Step 4.1: Update Xcode Project (if needed)
- Remove old file references from `ios/Runner.xcodeproj`
- Add new file references from `ios/Classes/`
- Update build settings to include `Classes/` in header search paths

#### Step 4.2: Update Example App's Xcode Project
- Ensure example app's project references the plugin via CocoaPods
- No direct file references to plugin's Swift files
- All plugin code comes through the pod

### Phase 5: Testing & Verification

#### Step 5.1: Clean Build
```bash
cd example
flutter clean
rm -rf ios/Pods ios/Podfile.lock
cd ios && pod install && cd ..
flutter pub get
```

#### Step 5.2: Verify Plugin Integration
1. Run `flutter run` from example directory
2. Verify plugin code is loaded (check logs)
3. Test dictation functionality
4. Verify no duplicate code warnings

#### Step 5.3: Verify File Structure
```bash
# Should show NO duplicate Swift files
find . -name "DictationManager.swift" -type f
# Should only show: ios/Classes/DictationManager.swift
```

## Migration Checklist

### Pre-Migration
- [ ] Backup current codebase
- [ ] Commit current state to git
- [ ] Create feature branch: `git checkout -b plugin-restructure`

### Phase 1: Plugin Structure
- [ ] Create `ios/Classes/` directory
- [ ] Move Swift files to `ios/Classes/`
- [ ] Move Objective-C files to `ios/Classes/`
- [ ] Create `ios/flutter_dictation.podspec`
- [ ] Update any import paths in moved files
- [ ] Test that moved files compile

### Phase 2: Example App
- [ ] Remove duplicate Swift files from `example/ios/Runner/`
- [ ] Remove duplicate Objective-C files from `example/ios/Runner/`
- [ ] Update `example/ios/Runner/AppDelegate.swift` (simplify)
- [ ] Update `example/ios/Podfile` (if needed)
- [ ] Verify example app references plugin correctly

### Phase 3: Plugin Registration
- [ ] Create plugin registration file (if needed)
- [ ] Update root AppDelegate (if exists)
- [ ] Verify platform channels still work

### Phase 4: Build Configuration
- [ ] Update root Xcode project (remove old references)
- [ ] Update example Xcode project (verify pod integration)
- [ ] Update build settings
- [ ] Clean and rebuild

### Phase 5: Testing
- [ ] Clean build (`flutter clean`, remove Pods)
- [ ] Reinstall pods (`pod install`)
- [ ] Run example app (`flutter run`)
- [ ] Test dictation functionality
- [ ] Verify no duplicate code
- [ ] Check logs for plugin loading

### Post-Migration
- [ ] Update documentation
- [ ] Update `WORKSPACE_STRUCTURE_EXPLAINED.md`
- [ ] Update troubleshooting docs
- [ ] Commit changes
- [ ] Create PR for review

## Key Principles

1. **Single Source of Truth:** Native code exists ONLY in `ios/Classes/`
2. **No Duplicates:** Example app has ZERO native code files
3. **Plugin Structure:** Follows Flutter plugin conventions
4. **Development Workflow:** Can still develop/test via example app
5. **Publishable:** Plugin can be published to pub.dev

## Benefits After Migration

✅ **No More Duplicate Code**
- Changes made once, work everywhere
- No sync issues between copies
- Easier debugging

✅ **Proper Plugin Structure**
- Can be published to pub.dev
- Other apps can use it easily
- Follows Flutter conventions

✅ **Better Development**
- Example app still works for testing
- Clear separation of concerns
- Easier to understand structure

✅ **Maintainability**
- Single codebase to maintain
- Clear plugin boundaries
- Standard Flutter patterns

## Rollback Plan

If migration fails:
1. Revert git commit
2. Restore files from backup
3. Document what went wrong
4. Fix issues and retry

## Timeline Estimate

- **Phase 1:** 30 minutes (create structure, move files)
- **Phase 2:** 20 minutes (clean example app)
- **Phase 3:** 15 minutes (plugin registration)
- **Phase 4:** 30 minutes (build configuration)
- **Phase 5:** 30 minutes (testing)
- **Total:** ~2 hours

## Next Steps

1. Review this plan
2. Create backup/commit current state
3. Start with Phase 1
4. Test after each phase
5. Document any issues encountered

## Questions to Resolve

1. **Root `ios/Runner/` directory:** Do we need it? Or can we remove it entirely?
   - **Answer:** Keep minimal structure for plugin development, but no duplicate code

2. **AppDelegate in root:** Do we need it?
   - **Answer:** Only if we want to test the plugin standalone. Otherwise, example app's AppDelegate is sufficient.

3. **Platform channel setup:** Where should it live?
   - **Answer:** In the plugin's Classes/ files, called from AppDelegate (either root or example)

4. **Bridging header:** Where should it be?
   - **Answer:** In `ios/Classes/` with the plugin code

## References

- [Flutter Plugin Development](https://docs.flutter.dev/development/packages-and-plugins/developing-packages)
- [CocoaPods Podspec Reference](https://guides.cocoapods.org/syntax/podspec.html)
- [Flutter Plugin Structure](https://docs.flutter.dev/development/packages-and-plugins/developing-packages#plugin)

