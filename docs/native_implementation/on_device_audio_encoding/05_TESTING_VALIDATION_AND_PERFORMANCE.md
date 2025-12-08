# Phase 5: Testing, Validation, and Performance

> **Canonical requirements**: All tests and validations MUST treat [Phase 1 requirements](01_REQUIREMENTS_AND_FORMAT_SELECTION.md) as the ground truth for format, limits, and `normalizeAudio(path)` behavior. Tests should fail if implementations drift from those locked settings.

## Objectives

- Verify correctness, robustness, and performance of the on-device encoder and normalization paths on both platforms.
- Ensure encoded/normalized files meet format, quality, and size expectations.
- Avoid regressions in dictation latency or app stability.

## Deliverables

- Automated tests (where feasible) covering encoder configuration, happy paths, and common failure scenarios.
- Manual validation procedures and sample test matrices for real devices.
- Documented performance baselines (encoding time, file size vs. duration, CPU/memory impact).

## Testing Tasks

- **Unit / integration tests (Dart)**
  - Tests around `normalizeAudio(path)` behavior, including:
    - Successful normalization of valid inputs.
    - Handling of non-existent paths, unsupported formats, and corrupted files.
    - Idempotent behavior when input is already canonical.

- **Platform-level tests**
  - Add native tests where possible (e.g., integration tests that invoke the encoder/normalizer with known inputs).
  - Validate error codes and messages for common failure modes.

- **Golden sample validation**
  - Create or collect a set of representative input files:
    - Different formats (WAV, MP3, AAC, etc.).
    - Different bitrates, sample rates, and channel configurations.
  - For each sample:
    - Run through `normalizeAudio(path)` on iOS and Android.
    - Verify the output format, duration, and approximate size.
    - Spot-check audio quality (no major artifacts, clipping, or truncation).

## Performance and Stability Tasks

- **Measure encoding performance**
  - Benchmark encoding duration vs. input duration for typical and worst-case files.
  - Measure CPU and memory usage during live recording and normalization.

- **Stress and edge-case testing**
  - Very long recordings near the maximum supported duration.
  - Rapid start/stop recording cycles.
  - Backgrounding/foregrounding the app during encoding or normalization.

- **Regression checks**
  - Confirm no significant regressions in:
    - Dictation start latency.
    - Recognition accuracy (if audio routing changed).
    - App stability (no leaks, crashes, or ANRs related to encoding).

## Exit Criteria

- Encoded and normalized files pass format and size checks across the supported device matrix.
- No critical performance regressions or stability issues are observed.
- Test coverage is documented and provides confidence for rollout.
