# Services Directory

This directory will contain the new native-based dictation service.

## Current Status

**In Transition** - We're migrating from package-based to native iOS implementation.

## Legacy Implementation

The original `audio_service.dart` (package-based) has been moved to `../../legacy/lib/services/` for reference.

## New Implementation

The new native implementation will be created here:
- `native_dictation_service.dart` - Native iOS-based service
- `dictation_service_interface.dart` - Common interface
- `dictation_service_factory.dart` - Factory with feature flag

## Migration

See `../../native_implementation/05_MIGRATION_STRATEGY.md` for migration details.

During migration, both implementations will be available via feature flag.

