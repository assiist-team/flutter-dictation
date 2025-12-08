# Phase 3: Android Encoder Implementation (MediaCodec/MediaMuxer or MediaRecorder)

> **Canonical requirements**: This phase MUST implement against the locked settings and behavior defined in [Phase 1 requirements](01_REQUIREMENTS_AND_FORMAT_SELECTION.md). Do **not** re-choose container, codec, bitrate, sample rate, channel layout, duration limits, or `normalizeAudio(path)` semantics—treat Phase 1 as source of truth.

## Objectives

- Implement an on-device audio encoder on Android that produces recordings in the canonical format defined in Phase 1.
- Ensure all Android recordings from `flutter_dictation` are encoded to the canonical format and respect size constraints.
- Implement `normalizeAudio(path)` for Android to transcode arbitrary audio files on disk into the canonical format.

## Deliverables

- Native Kotlin implementation for recording directly into the canonical format using `MediaCodec`/`MediaMuxer` or a well-configured `MediaRecorder`.
- Normalization pipeline for existing files using `MediaExtractor` + `MediaCodec` + `MediaMuxer` (or the closest native combination available).
- Clear Kotlin API surface that the Flutter plugin can call.
- Basic logging and error taxonomy for encoding and normalization failures on Android.

## Recording Pipeline Tasks

- **Review existing Android recording flow**
  - Map how and where audio is currently captured in the Android portion of the plugin.
  - Identify the extension points for inserting canonical encoding logic.

- **Select encoding strategy**
  - Decide whether to use:
    - `MediaRecorder` (simpler, if it supports the required AAC settings and container), or
    - A manual `AudioRecord` + `MediaCodec` + `MediaMuxer` pipeline (more control, more complexity).
  - Document trade-offs and selected approach, given target API levels and devices.

- **Implement canonical-format recording**
  - Configure audio source (`MIC`), sample rate, channel config (mono), and audio format.
  - Configure encoder (AAC profile, bitrate, sample rate) and muxer to output `.m4a` or equivalent container.
  - Ensure the pipeline handles start, stop, and flush reliably.
  - Enforce or approximate size constraints via duration and bitrate calculations.

- **Error handling and resilience**
  - Map codec/muxer/IO errors to structured error codes for Flutter.
  - Clean up partial files on failure and ensure file handles are closed.
  - Add togglable debug logging for encoder behavior.

## Normalization (`normalizeAudio(path)`) Tasks

- **Design normalization flow**
  - Input: arbitrary local file path.
  - Output: canonical-format file path in an app-controlled directory.
  - Use `MediaExtractor` to read the input, `MediaCodec` to decode/encode as needed, and `MediaMuxer` for output.

- **Implement transcoding**
  - Validate input file existence and readability.
  - Inspect track format and duration; reject or warn on unsupported types.
  - Downmix to mono and resample if needed to match canonical settings.
  - Write output using the same encoder configuration as the live recording pipeline.

- **Edge cases and optimizations**
  - If the input is already in canonical format and within constraints, consider copying instead of re-encoding.
  - Handle very long files or those that would exceed size limits with clear error semantics.
  - Ensure encoder resources are released even if the app backgrounding or lifecycle events intervene.

## Exit Criteria

- Android recordings produced by `flutter_dictation` are consistently written in the canonical format.
- `normalizeAudio(path)` works on Android for typical input formats, returning a canonical file path.
- Error conditions are well-defined, surfaced to Flutter, and logged.
- No known regressions in dictation startup latency or stability on Android.
