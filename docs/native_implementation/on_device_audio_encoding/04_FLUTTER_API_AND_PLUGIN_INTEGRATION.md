# Phase 4: Flutter API and Plugin Integration

> **Canonical requirements**: This phase MUST use the format, size limits, and `normalizeAudio(path)` behavior defined in [Phase 1 requirements](01_REQUIREMENTS_AND_FORMAT_SELECTION.md). Do **not** redefine canonical settings; assume native layers already implement them per Phase 2–3.

## Objectives

- Expose a clear, minimal API from the `flutter_dictation` plugin for both live encoded recordings and post-hoc normalization.
- Add `normalizeAudio(path)` to the public Dart API, wired through platform channels to the native encoders.
- Ensure imported files and locally recorded audio both flow through the same canonicalization path before upload.

## Deliverables

- Updated Dart plugin API surface in `flutter_dictation.dart` and related services.
- Platform channel methods and message contracts for:
  - Starting/stopping a live recording with canonical encoding.
  - Running `normalizeAudio(path)` on an existing file.
- Updated app-side code that calls `normalizeAudio(path)` for imported audio.
- Basic error handling and UI feedback patterns for encoding/normalization failures.

## API Design Tasks

- **Define Dart API surface**
  - Add a high-level `normalizeAudio(String sourcePath)` method returning a result object or canonical file path.
  - Ensure the existing recording API either:
    - Always produces canonical-format files, or
    - Has explicit options to enable canonical encoding.
  - Decide on return types for both live recordings and normalization (e.g., `DictationRecordingResult`).

- **Define platform channel contracts**
  - Method names (e.g., `startCanonicalRecording`, `stopCanonicalRecording`, `normalizeAudio`).
  - Argument and result schemas (JSON-serializable maps) including:
    - `sourcePath`, `targetPath` (if needed), duration, size, format metadata, and error codes.
  - Error contract: how native errors are mapped to Dart exceptions or result objects.

## Integration Tasks

- **Wire Dart to native**
  - Implement platform channel handlers on iOS and Android that call into the encoder/normalizer components from Phases 2–3.
  - Ensure lifecycle and threading constraints are respected (e.g., marshaling results back to the main isolate).

- **Update app flows**
  - Identify all places where audio is recorded or imported.
  - Route imported files through `normalizeAudio(path)` before upload or further processing.
  - Ensure existing upload code assumes the canonical format and no longer needs to handle diverse input formats.

- **Telemetry and logging hooks**
  - Add optional logging flags to surface encoding/normalization metrics (duration, size, success/failure).
  - Consider a light-weight way to trace problems in production without PII.

## Exit Criteria

- The `flutter_dictation` Dart API exposes `normalizeAudio(path)` and converges all recordings on the canonical format.
- Platform channels are implemented and tested on both iOS and Android.
- The app uses `normalizeAudio(path)` for imported audio and uploads only canonical-format files.
