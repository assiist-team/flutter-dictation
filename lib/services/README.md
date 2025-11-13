# Services Directory

This directory contains the native-based dictation service.

## Current Status

**Native Implementation** - Building the native iOS implementation directly as the primary implementation.

## Legacy Implementation

The original `audio_service.dart` (package-based) has been moved to `../../legacy/lib/services/` for reference only. It's not part of the active codebase.

## Native Implementation

The native implementation is located here:
- `native_dictation_service.dart` - Native iOS-based service (primary implementation)
- `waveform_controller.dart` - Waveform state management

## Implementation Strategy

See `../../docs/native_implementation/05_MIGRATION_STRATEGY.md` for implementation details.

Since there are no existing products to migrate, we're building the native implementation directly without migration complexity.

