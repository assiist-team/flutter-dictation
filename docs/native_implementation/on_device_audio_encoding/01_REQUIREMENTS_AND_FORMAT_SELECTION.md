# Phase 1: Final Requirements and Format Selection (Implementation-Ready)

This phase locks in **all** key decisions so later phases can implement without revisiting format or behavior choices.

## Canonical Recording / Encoding Settings (Locked)

- **Container**: `.m4a` (MPEG‑4 container).
- **Codec**: AAC‑LC.
- **Channel layout**: **Mono** only. Any stereo input **must be downmixed to mono**.
- **Sample rate**: **44,100 Hz**.
- **Target bitrate**: **64 kbps** (64,000 bits/sec).
- **Target use case**: Voice dictation, optimized for intelligibility and modest file sizes.

These settings MUST be used for:

- All live recordings produced by `flutter_dictation`.
- All outputs of `normalizeAudio(path)` on both iOS and Android.

## Size and Duration Constraints (Locked)

- **Per‑recording soft target**: Keep recordings comfortably under **50 MB**.
- **Approximate size at 64 kbps**:
  - 64 kbps = 8 kB/s ≈ **0.5 MB/min**.
  - 60 minutes ≈ **30 MB** (well under 50 MB), excluding small container overhead.
- **Hard maximum recording duration**: **60 minutes**.
  - Both platforms MUST prevent live recordings from exceeding **60 minutes**.
  - Implementations MAY stop recording earlier if a size estimate predicts the file will exceed **45 MB**.

Implications:

- At 64 kbps and 60 minutes, typical recordings should be ~30 MB, comfortably inside a 50 MB upload limit.
- No additional bitrate adaptation is required; we rely on a fixed bitrate + max duration cap.

## `normalizeAudio(path)` Behavior (Locked)

**Dart signature (conceptual):**

- `Future<NormalizedAudioResult> normalizeAudio(String sourcePath);`

**Input contract**

- `sourcePath` MUST be a local file path accessible to the app.
- The implementation MUST support at least: WAV/PCM, AAC/M4A, MP3, and the canonical format described above.

**Output contract**

- On success:
  - Returns a result containing at minimum:
    - `canonicalPath` (string): absolute path to the canonical `.m4a` file.
    - `durationMs` (int): duration of the output file.
    - `sizeBytes` (int): size of the output file in bytes.
    - `wasReencoded` (bool): `true` if a full re‑encode occurred, `false` if a fast‑path copy was used.
  - The canonical file MUST:
    - Use the container/codec/settings defined above.
    - Respect the 60‑minute limit; longer inputs MUST either fail or be truncated with a clearly documented policy (see below).

- On failure:
  - Returns a structured error (mapped to a Dart exception or error result) with:
    - A stable error code (e.g., `file_not_found`, `unsupported_format`, `duration_too_long`, `io_error`, `encoder_error`).
    - A human‑readable message for logging/diagnostics (not for string matching).

**Behavior rules**

- If the input file is **already canonical** (AAC‑LC `.m4a`, mono, 44.1 kHz, 64 kbps ± 10%, duration ≤ 60 minutes):
  - Implementation SHOULD **avoid re‑encoding**:
    - Copy the file into the app’s managed audio directory with the canonical naming scheme (see below).
    - Set `wasReencoded = false`.
- If the input file is **non‑canonical** (format, channels, sample rate, or bitrate differ) but **duration ≤ 60 minutes**:
  - Implementation MUST **fully re‑encode** to the canonical settings.
  - Set `wasReencoded = true`.
- If the input file’s **duration exceeds 60 minutes**:
  - Preferred behavior: **fail with `duration_too_long`** and do not produce an output file.
  - Truncation/splitting is **out of scope** for this iteration and MUST NOT be implemented silently.

## File Locations, Naming, and Cleanup (Locked)

- **Temporary files**:
  - MUST live in the platform‑appropriate cache/temp directory.
  - MUST be cleaned up on both success and failure.
- **Final canonical files**:
  - MUST live in the same app‑controlled directory used for dictation recordings (the existing plugin recording directory).
  - Filenames MUST follow the pattern:
    - `dictation_<UTC-ISO8601-timestamp>_<randomSuffix>.m4a`
    - Example: `dictation_2025-12-08T10-23-45Z_ab12cd.m4a`
  - Implementations MUST avoid collisions by including a random or UUID‑based suffix.

## Platform-Specific Implementation Notes (Locked)

These are constraints/choices that later phases MUST honor; they are not open questions.

### iOS

- Use `AVFoundation` with:
  - `AVAudioSession` configured for 44.1 kHz, mono recording.
  - `AVAssetWriter` (or equivalent) configured for:
    - Container: MPEG‑4 (`.m4a`).
    - Codec: AAC‑LC.
    - Channels: 1.
    - Sample rate: 44,100 Hz.
    - Bitrate: 64,000 bits/sec.
- For `normalizeAudio(path)`:
  - Use `AVURLAsset` + `AVAssetReader` + `AVAssetWriter` and, where needed, `AVAudioConverter` to downmix/resample to mono 44.1 kHz.
  - Must enforce the 60‑minute duration limit before starting a long transcode, when possible.

### Android

- **Minimum supported API level**: Assume **API 21+** (Lollipop) for encoder implementation.

- **Live recording strategy**:
  - Use `MediaRecorder` with:
    - Audio source: `MediaRecorder.AudioSource.MIC`.
    - Output format: `MediaRecorder.OutputFormat.MPEG_4`.
    - Audio encoder: `MediaRecorder.AudioEncoder.AAC`.
    - Channel count: 1 (mono).
    - Sample rate: 44,100 Hz.
    - Encoding bitrate: 64,000 bits/sec.
  - Later phases MUST ensure the resulting files conform to the canonical format (or document any minor container/metadata differences that do not affect downstream consumers).

- **Normalization strategy**:
  - Use `MediaExtractor` + `MediaCodec` + `MediaMuxer` (or equivalent) to:
    - Read the input audio track.
    - Downmix to mono and resample to 44.1 kHz as needed.
    - Encode AAC‑LC at 64 kbps into an `.m4a`/MPEG‑4 output.
  - Must enforce the 60‑minute duration limit, failing with `duration_too_long` for oversized inputs.

## Summary: What Is No Longer Up for Debate

- Canonical format, bitrate, sample rate, and mono downmixing are fully specified.
- Max duration is fixed at 60 minutes, with behavior for over‑long inputs defined.
- `normalizeAudio(path)` has a concrete input/output contract and behavior rules.
- Platform implementation strategies (AVFoundation on iOS; `MediaRecorder` for live + `MediaExtractor`/`MediaCodec`/`MediaMuxer` for normalization on Android) are chosen and must be followed.

Later phases should treat this document as **source of truth**, not a list of open questions.
