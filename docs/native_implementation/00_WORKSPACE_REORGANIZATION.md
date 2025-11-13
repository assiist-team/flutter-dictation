# Workspace Reorganization Plan

## Current State

The workspace has:
- Root-level Flutter package (`lib/`, `ios/`, `android/`, `macos/`)
- `example/` directory with its own Flutter app
- Multiple platform folders at root and in example
- Old planning docs at root level

## Proposed Structure

```
flutter_dictation/
├── native_implementation/          # NEW: Planning docs ONLY (not actual code!)
│   ├── 00-06_*.md                  # Implementation phase guides
│   └── README.md                   # Overview
│
├── ios/Runner/                     # ACTUAL native iOS code goes HERE
│   ├── DictationManager.swift      # Native Swift code
│   ├── AudioEngineManager.swift    # Native Swift code
│   └── SpeechRecognizerManager.swift # Native Swift code
│
├── legacy/                         # OLD: Current Flutter package implementation
│   ├── lib/                        # Current Dart code
│   │   ├── services/
│   │   │   └── audio_service.dart  # Package-based implementation
│   │   ├── widgets/
│   │   └── theme/
│   ├── ios/                        # Current iOS Flutter setup
│   ├── android/                    # Current Android setup
│   ├── macos/                      # Current macOS setup
│   └── README.md                   # Notes about legacy implementation
│
├── lib/                            # NEW: Updated Flutter package
│   ├── services/
│   │   └── native_dictation_service.dart  # New native-based service
│   ├── widgets/                    # Keep existing widgets
│   └── theme/                      # Keep existing theme
│
├── ios/                            # Standard Flutter iOS folder
│   └── Runner/                     # Native iOS code goes HERE (standard location)
│       ├── DictationManager.swift  # Native implementation
│       ├── AudioEngineManager.swift
│       └── SpeechRecognizerManager.swift
│
├── example/                        # Keep for testing both implementations
│   └── lib/
│       └── main.dart              # Can test legacy vs native
│
├── docs/                           # Move planning docs here
│   ├── LATENCY_FIX_PLAN.md        # Old plan (for reference)
│   └── NATIVE_REBUILD_PLAN.md     # High-level plan
│
└── README.md                       # Updated with new architecture
```

## Migration Steps

### Step 1: Create New Directories
```bash
mkdir -p native_implementation  # Planning docs only
mkdir -p legacy                  # Legacy code backup
mkdir -p docs                    # Old planning docs
# Note: Native code goes in ios/Runner/ (already exists)
```

### Step 2: Move Legacy Code
Move current implementation to `legacy/`:
- `lib/services/audio_service.dart` → `legacy/lib/services/audio_service.dart`
- Keep `lib/widgets/` and `lib/theme/` at root (we'll reuse these)

### Step 3: Move Planning Docs
- `LATENCY_FIX_PLAN.md` → `docs/LATENCY_FIX_PLAN.md`
- `NATIVE_REBUILD_PLAN.md` → `docs/NATIVE_REBUILD_PLAN.md`

### Step 4: Clean Up Platform Folders
- Keep root `ios/` for new native implementation
- Move old iOS configs to `legacy/ios/` if needed
- `example/ios/` stays for testing

## Benefits

✅ **Clear separation** - Old vs new code is obvious
✅ **Easy rollback** - Legacy code preserved
✅ **Clean workspace** - Only active code at root
✅ **Better organization** - Planning docs grouped together
✅ **Gradual migration** - Can test both side-by-side

## What to Keep at Root

- `lib/` - New implementation (but widgets/theme reused)
- `ios/` - New native implementation
- `example/` - Testing app
- `pubspec.yaml` - Updated dependencies
- `README.md` - Updated documentation
- `native_implementation/` - New work directory

## What Goes to Legacy

- `lib/services/audio_service.dart` - Old package-based service
- Any old planning docs (moved to `docs/`)
- Old platform-specific code that's being replaced

## Implementation Notes

- **Don't delete anything yet** - Move to legacy first
- **Feature flag** - Use a flag to switch between implementations during migration
- **Git strategy** - Consider a branch for the native implementation work
- **Documentation** - Update README to explain the new structure

## Next Steps

1. ✅ Create directory structure
2. ✅ Create planning docs
3. Move legacy code (manual step - see commands above)
4. Start implementing native code in `native_implementation/ios/`
5. Update `lib/services/` with new native service
6. Test both implementations side-by-side
7. Migrate fully once native is proven

