# Workspace Structure Explained

## The Confusion

You're right to be confused! Let me clarify what goes where.

## Key Point: `docs/native_implementation/` is JUST for Planning Docs

The `docs/native_implementation/` directory is **NOT** where the actual code goes. It's just for:
- Planning documents
- Implementation guides
- Reference materials

## Where Code Actually Goes

### Flutter Projects Have Platform Folders

In Flutter, native code goes in **platform-specific folders** at the root:

```
flutter_dictation/
├── ios/                    # iOS native code goes HERE
│   └── Runner/
│       ├── AppDelegate.swift          # Existing Flutter setup
│       └── DictationManager.swift     # NEW: Our native code
│
├── android/                # Android native code (if we do it)
│   └── app/src/main/kotlin/...
│
├── macos/                  # macOS native code (if we do it)
│   └── Runner/
│
└── lib/                    # Flutter/Dart code
    └── services/
        └── native_dictation_service.dart  # NEW: Dart wrapper
```

## Current Plan: iOS ONLY

**We're focusing on iOS first** because:
1. That's where the latency problem is most critical
2. iOS has excellent native speech recognition APIs
3. We can add Android/macOS later if needed

## Actual File Locations

### Native iOS Code (Swift)
- `ios/Runner/DictationManager.swift` - Main coordinator
- `ios/Runner/AudioEngineManager.swift` - Audio handling
- `ios/Runner/SpeechRecognizerManager.swift` - Speech recognition
- `ios/Runner/AppDelegate.swift` - Modified to set up platform channels

### Flutter/Dart Code
- `lib/services/native_dictation_service.dart` - Platform channel wrapper
- `lib/services/dictation_service_interface.dart` - Common interface
- `lib/services/dictation_service_factory.dart` - Factory with feature flag

### Planning Docs (Reference Only)
- `docs/native_implementation/01_IOS_AUDIO_ENGINE_SETUP.md` - Guide for building AudioEngineManager
- `docs/native_implementation/02_SPEECH_RECOGNIZER_SETUP.md` - Guide for building SpeechRecognizerManager
- etc.

## Why This Structure?

### Flutter Convention
Flutter projects **always** put native code in platform folders:
- `ios/` for iOS
- `android/` for Android  
- `macos/` for macOS
- `windows/` for Windows (if applicable)

### Our Structure
```
flutter_dictation/
├── ios/Runner/              # ← Native iOS code goes HERE (standard Flutter location)
├── lib/services/            # ← Flutter/Dart code goes HERE
├── docs/native_implementation/  # ← Planning docs only (not code!)
└── legacy/                   # ← Old implementation backup
```

## Updated Understanding

1. **`docs/native_implementation/`** = Planning docs and guides (not actual code)
2. **`ios/Runner/`** = Where we'll write Swift code (standard Flutter location)
3. **`lib/services/`** = Where we'll write Dart code
4. **iOS only** = We're focusing on iOS first, not all platforms

## What About Android/macOS?

- **Not in scope yet** - Focusing on iOS first
- **Can add later** - Same pattern: `android/app/src/main/kotlin/...` for Android
- **Same Dart code** - The `lib/services/` code works for all platforms via platform channels

## Next Steps

When we start implementing:
1. Create Swift files in `ios/Runner/` (not `docs/native_implementation/ios/`)
2. Create Dart files in `lib/services/`
3. Reference planning docs in `docs/native_implementation/` as guides

Does this clarify things? The `docs/native_implementation/` folder is just documentation - the actual code goes in the standard Flutter platform folders!

