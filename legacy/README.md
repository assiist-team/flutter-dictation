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

**Reference Only** - This code is kept for reference purposes only. It's not part of the active codebase.

The new native iOS implementation (in `../lib/services/` and `../ios/Runner/`) provides:
- Sub-100ms latency (vs 3000ms)
- Direct control over audio pipeline
- Better performance and user experience

See `../docs/native_implementation/` for the new implementation details.

## Keeping for Reference

This code is kept for:
- Understanding the original package-based approach
- Comparing performance improvements
- Reference during development if needed

**Note**: This code is not maintained and is not part of the active codebase. The native implementation is the only active implementation.

