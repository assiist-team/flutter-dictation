# Phase 2: iOS Encoder Implementation (AVFoundation)

> **Canonical requirements**: This phase MUST implement against the locked settings and behavior defined in [Phase 1 requirements](01_REQUIREMENTS_AND_FORMAT_SELECTION.md). Do **not** re-choose container, codec, bitrate, sample rate, channel layout, duration limits, or `normalizeAudio(path)` semantics—treat Phase 1 as source of truth.

## Canonical Settings Snapshot (for iOS devs)

- Container: `.m4a` (MPEG‑4).
- Codec: AAC‑LC.
- Channels: mono only (downmix any stereo input to mono).
- Sample rate: 44,100 Hz.
- Bitrate: 64,000 bits/sec (64 kbps).
- Max duration: 60 minutes (fail if input to `normalizeAudio(path)` exceeds this; stop live recordings at or before this).

These values are duplicated here so an iOS dev can implement Phase 2 without reading Phase 1.

## Objectives

- Implement an on-device audio encoder on iOS that produces recordings in the canonical format defined in Phase 1.
- Ensure all iOS recordings from `flutter_dictation` are encoded to the canonical format and respect size constraints.
- Implement `normalizeAudio(path)` for iOS to transcode arbitrary audio files on disk into the canonical format.

## Deliverables

- Native Swift implementation for recording directly into the canonical format using `AVFoundation`.
- Normalization pipeline for existing files using `AVAssetReader`/`AVAssetWriter` (or equivalent) and `AVAudioConverter`.
- Clear Swift API surface that the Flutter plugin can call (e.g., via a `DictationEncoderManager`).
- Basic logging and error taxonomy for encoding and normalization failures.

## Recording Pipeline Tasks

- **Review existing iOS recording flow**
  - Map how and where `DictationManager` or related classes currently capture audio.
  - Identify the minimal points to inject/replace encoding logic without destabilizing dictation.

- **Design encoder architecture**
  - Add a dedicated encoder component (e.g., `AudioEncoderManager`) responsible for:
    - Configuring `AVAudioSession` for recording.
    - Creating and managing the encoder (e.g., `AVAssetWriter` with AAC output).
    - Handling file paths, temporary storage, and cleanup.
  - Define a simple interface for "startRecording", "stopRecording", and result delivery (file path + metadata).

- **Implement canonical-format recording**
  - Configure `AVAudioSession` category/mode/sample rate to match canonical settings.
  - Configure `AVAssetWriter` (or equivalent) to write AAC `.m4a` mono at target bitrate.
  - Wire the audio engine output to the encoder, ensuring real-time safe writes.
  - Enforce or approximate size constraints (e.g., guard by duration and bitrate calculations).

- **Error handling and resilience**
  - Enumerate possible failures (session configuration, file I/O, encoder errors) and map them to error codes.
  - Ensure partial files are cleaned up on failure.
  - Add debug logging hooks that can be toggled from Flutter.

## Normalization (`normalizeAudio(path)`) Tasks

- **Design normalization flow**
  - Input: arbitrary local file path.
  - Output: canonical-format file path in an app-controlled directory.
  - Use `AVURLAsset` + `AVAssetReader` + `AVAssetWriter` (or equivalent) to decode and re-encode.

- **Implement transcoding**
  - Validate input file exists and is readable.
  - Inspect track format and duration for sanity checks and sizing.
  - Downmix to mono and resample if needed to match canonical settings.
  - Write output using the same encoder configuration as the live recording pipeline.

- **Edge cases and optimizations**
  - If the input is already in canonical format and within constraints, consider short-circuiting with a copy.
  - Gracefully handle very long files or files that would exceed size limits.
  - Ensure that temporary and output files are placed in deterministic, manageable locations.

## Implementation Status Snapshot (iOS, Dec 2025)

This section tracks how much of the above plan is already implemented in the repo, and what is still outstanding. Treat the bullets below as **status notes**, not as a replacement for the canonical requirements above.

### Live Recording / Canonical Encoding

- **Implemented**
  - `AudioEncoderManager` implements direct recording to the canonical format using `AVAssetWriter` with AAC‑LC `.m4a`, mono, 44.1 kHz, 64 kbps. It also enforces the 60‑minute duration limit at the encoder layer and returns duration/size metadata via `EncodingResult`.
  - `AudioEngineManager` owns the single `AVAudioEngine` and uses an `AudioEncoderManager` instance when `AudioPreservationRequest` is provided. Raw mic buffers are fed into the encoder while also being surfaced for speech recognition and waveform visualization.
  - `DictationManager` exposes preserved‑audio metadata back to Flutter as an `audioFile` event, and Dart’s `NativeDictationService` turns this into a `DictationAudioFile` object for the caller.

- **Gaps / TODOs**
  - The **60‑minute cap is only enforced inside `AudioEncoderManager.append`**, which silently stops the encoder when the limit is reached. `AudioEngineManager` / `DictationManager` / Flutter are not notified, so dictation can keep running past 60 minutes while the file stops growing. We still need:
    - A surfaced status or error when the duration limit is reached.
    - Session‑level stop behavior that aligns with the spec (“stop live recordings at or before 60 minutes”) instead of silently dropping tail audio.
  - Canonical recording is **optional** and disabled by default (`DictationSessionOptions.preserveAudio = false`). The Phase 1 requirements assume that “all iOS recordings” end up in canonical form; we still need a product‑level decision and corresponding implementation:
    - Either make canonical encoding on by default (and document any opt‑out),
    - Or explicitly scope the requirement down to “when `preserveAudio` is enabled” and update the Phase 1/2 docs accordingly.

### File Locations, Naming, and Storage

- **Implemented**
  - Canonical‑format filenames created by `AudioEncoderManager.generateCanonicalFileURL()` follow the locked pattern `dictation_<UTC-ISO8601-timestamp>_<randomSuffix>.m4a` with a short random suffix to avoid collisions.
  - Normalized outputs are written into the app’s documents directory in canonical form, and preserved live recordings are written as `.m4a` regardless of the original requested extension.

- **Gaps / TODOs**
  - `AudioPreservationConfig` still exposes only `.wav` / `.caf` extensions and uses the temporary directory by default, while `AudioEngineManager` silently rewrites the extension to `.m4a`. This mismatches the Phase 1 contract that:
    - The canonical recording directory should be a single app‑controlled location (shared by live recordings and normalization outputs).
    - Callers should be able to request `.m4a` explicitly without going through a `.wav` façade.
  - We still need to:
    - Align the preservation path / directory and the `normalizeAudio` output directory so both share the same canonical recording location.
    - Decide whether callers may still request `.wav` for debugging, and if so, how that coexists with the canonical `.m4a` pipeline.

### `normalizeAudio(path)` Native Pipeline

- **Implemented**
  - `AudioEncoderManager.normalizeAudio(sourcePath:)` on iOS:
    - Validates that the input file exists.
    - Uses `AVURLAsset` + `AVAssetReader`/`AVAssetWriter` to transcode arbitrary audio into the canonical format, downmixing to mono and resampling to 44.1 kHz.
    - Enforces the 60‑minute duration limit, returning a `durationTooLong` error when exceeded.
    - Short‑circuits when the input is already canonical (AAC‑LC `.m4a`, mono, 44.1 kHz, ~64 kbps, ≤ 60 minutes) by copying into a new canonical file and marking `wasReencoded = false`.
    - Returns `NormalizedAudioResult` with `canonicalPath`, `durationMs`, `sizeBytes`, and `wasReencoded`, matching the Phase 1 contract.
  - `DictationManager.handleNormalizeAudio` exposes this native function over the method channel, mapping failures into stable error codes (e.g. `file_not_found`, `unsupported_format`, `duration_too_long`, `io_error`, `encoder_error`) via `NormalizationError`.

- **Gaps / TODOs**
  - There is **no Dart‑level API yet** for `normalizeAudio(path)`. `NativeDictationService` does not expose a corresponding `Future<NormalizedAudioResult> normalizeAudio(String sourcePath)` wrapper, so Flutter cannot currently exercise the native implementation.
  - Error taxonomy is complete for normalization but **incomplete for live recording**:
    - `NormalizationError` includes stable, documented codes.
    - `EncodingError` is only used locally and has no surfaced codes or mapping into `DictationError` / Flutter exceptions, which makes it hard for callers to distinguish user‑correctable issues (e.g. bad path, storage full) from transient encoder failures.

## Exit Criteria

- iOS recordings produced by `flutter_dictation` are consistently written in the canonical format.
- `normalizeAudio(path)` works on iOS for typical input formats, returning a usable canonical file path.
- Error conditions are well-defined, surfaced to Flutter, and logged.
- No known regressions in dictation startup latency or stability.
