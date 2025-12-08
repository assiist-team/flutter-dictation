# On-Device Audio Encoding for `flutter_dictation`

This directory defines the phased implementation plan for adding an on-device audio encoder to the `flutter_dictation` plugin so that all recordings are standardized and size-bounded for upload.

## Goals

- **Canonical upload format**: All recordings produced as AAC `.m4a` (or another voice-optimized container) at ~64 kbps mono.
- **Size-bounded recordings**: Keep even long recordings under ~50 MB via bitrate and duration-aware guardrails.
- **Native-only encoding**: Use only native platform APIs (e.g., `AVFoundation` on iOS and `MediaCodec`/`MediaMuxer` or properly configured `MediaRecorder` on Android). No FFmpeg or third-party archived binaries.
- **Post-hoc normalization**: Ability to take any existing audio file on disk, transcode it to the canonical format/bitrate, and return the new file path.
- **Flutter API surface**: Expose `normalizeAudio(path)` from `flutter_dictation` and wire it into the app for imported files as well.

## Phased Plan

Implementation is broken into phases, each with its own document:

1. **[01_REQUIREMENTS_AND_FORMAT_SELECTION.md](01_REQUIREMENTS_AND_FORMAT_SELECTION.md)** – Locks in canonical format/bitrate, size limits, and `normalizeAudio(path)` behavior. Treat this as the source of truth for all later phases.
2. **[02_IOS_ENCODER_IMPLEMENTATION.md](02_IOS_ENCODER_IMPLEMENTATION.md)** – Implement native on-device encoder and normalization pipeline on iOS with `AVFoundation`.
3. **[03_ANDROID_ENCODER_IMPLEMENTATION.md](03_ANDROID_ENCODER_IMPLEMENTATION.md)** – Implement native on-device encoder and normalization pipeline on Android with `MediaCodec`/`MediaMuxer` or `MediaRecorder`.
4. **[04_FLUTTER_API_AND_PLUGIN_INTEGRATION.md](04_FLUTTER_API_AND_PLUGIN_INTEGRATION.md)** – Expose encoding/normalization APIs in the `flutter_dictation` plugin, including `normalizeAudio(path)`.
5. **[05_TESTING_VALIDATION_AND_PERFORMANCE.md](05_TESTING_VALIDATION_AND_PERFORMANCE.md)** – Define and implement tests, validation flows, and performance checks.

Each phase is designed to be reasonably sized and, where possible, parallelizable across iOS and Android.
