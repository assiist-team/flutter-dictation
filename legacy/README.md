# Legacy Implementation

This directory contains the original Flutter package-based implementation of the dictation feature.

## Contents

- `lib/services/audio_service.dart` - Original implementation using `speech_to_text` and `audio_waveforms` packages

## Why Legacy?

This implementation had latency issues (3+ seconds) due to:
- Package abstraction overhead
- Sequential operations (speech recognition → then recording)
- No direct control over iOS audio session configuration
- Method channel delays

## Status

**Deprecated** - Being replaced by native iOS implementation in `../native_implementation/`

## Migration

The new native implementation provides:
- Sub-100ms latency (vs 3000ms)
- Direct control over audio pipeline
- Better performance and user experience

See `../native_implementation/` for the new implementation.

## Keeping for Reference

This code is kept for:
- Reference during migration
- Rollback capability (via feature flag)
- Comparison testing
- Documentation purposes

## Usage

If you need to use the legacy implementation temporarily:
- Use the feature flag in `DictationServiceFactory`
- Set `useNativeImplementation = false`
- See `../native_implementation/05_MIGRATION_STRATEGY.md` for details

