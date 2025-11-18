# Audio Preservation Reference

End-to-end reference for the optional *raw audio mirroring* path that now ships with `flutter_dictation`. Use this when a product needs to store, review, or upload the source microphone audio in addition to the live transcript.

---

## Goals & Capabilities

- Record the same PCM stream that feeds the waveform/recognizer without installing extra taps or breaking latency guarantees.
- Control the feature per dictation session via Flutter-only switches—no permanent config required.
- Emit deterministic metadata (`path`, `durationMs`, `fileSizeBytes`, etc.) once recording stops so Dart code can manage persistence or uploads.
- Respect product policies: delete cancelled sessions by default while allowing overrides for QA/compliance workflows.

---

## High-Level Flow

1. Flutter callers pass `DictationSessionOptions` + an `onAudioFile` callback into `NativeDictationService.startListening`.
2. Dart converts the options into a method-channel payload (`preserveAudio`, optional `preservedAudioFilePath`, `deleteAudioIfCancelled`).
3. `DictationManager` parses the payload (`DictationStartListeningOptions`) and configures the native pipeline:
   - Builds an `AudioPreservationRequest` with a resolved/sanitized file URL (defaults to `NSTemporaryDirectory()/dictation-<timestamp>.wav`).
   - Hands the request to `AudioEngineManager.startRecording(...)`, which wires up an `AudioPreservationWriter`.
4. Every buffer delivered by the single AVAudioEngine tap now:
   - Updates audio levels (waveform),
   - Feeds the speech recognizer,
   - Streams into the preservation writer.
5. On stop/cancel we:
   - Tear down the tap,
   - Flush/close the writer and optionally delete the file,
   - Emit an `audioFile` event (and invoke Dart’s `onAudioFile`) with metadata describing the final artifact.

---

## Flutter Surface

### DictationSessionOptions

```dart
const options = DictationSessionOptions(
  preserveAudio: true,
  preservedAudioFilePath: 'Recordings/note.wav', // optional
  deleteAudioIfCancelled: false,                 // default true
);
```

| Field | Description |
|-------|-------------|
| `preserveAudio` | Enables/disables the feature per session. |
| `preservedAudioFilePath` | Optional sandbox path (`/absolute/path.wav` or `Documents/Folder/file.caf`). Defaults to timestamped `.wav` in the temp directory. |
| `deleteAudioIfCancelled` | Delete files for cancelled sessions unless explicitly `false`. |

### DictationAudioFile callback

```dart
await _dictationService.startListening(
  onResult: ...,
  onStatus: ...,
  onAudioLevel: ...,
  onError: ...,
  onAudioFile: (file) {
    debugPrint(
      'Audio captured at ${file.path} '
      '(${file.duration.inMilliseconds}ms, '
      '${file.fileSizeBytes} bytes, cancelled? ${file.wasCancelled})',
    );
  },
  options: options,
);
```

`DictationAudioFile` exposes:

| Property | Type | Notes |
|----------|------|-------|
| `path` | `String` | Absolute sandbox path to the `.wav` or `.caf`. |
| `duration` | `Duration` | Derived from written frames. |
| `fileSizeBytes` | `int` | On-disk size after flush. |
| `sampleRate` | `double` | Mirrors engine input (16 kHz in current config). |
| `channelCount` | `int` | Typically `1` (mono). |
| `wasCancelled` | `bool` | Use to audit keep/delete decisions. |

### Event Channel Payload

The native side also pushes identical data over the event channel:

```json
{
  "type": "audioFile",
  "path": ".../dictation-2025-11-16T01-23-45.wav",
  "durationMs": 5423.7,
  "fileSizeBytes": 178523,
  "sampleRate": 16000.0,
  "channelCount": 1,
  "wasCancelled": false
}
```

---

## Native Implementation Notes

### AudioEngineManager.swift

- Accepts an optional `AudioPreservationRequest` when starting the engine.
- Lazily instantiates `AudioPreservationWriter` with the current input format (shared tap, no extra IO nodes).
- Appends every active buffer (`processAudioBuffer`) and flushes on stop.

### AudioPreservationWriter.swift

- Thin wrapper around `AVAudioFile`.
- Ensures the destination directory exists and deletes/clobbers stale files before writing.
- Supports `.wav` (default) and `.caf`; other extensions throw an `INVALID_ARGUMENTS` error.

### DictationManager.swift

- Parses options, resolves safe URLs (absolute or Documents-relative), and enforces suffix + extension rules.
- Emits `DictationError.invalidArguments` when callers provide disallowed extensions or empty strings.
- Keeps per-session config so cancel/stop can honor `deleteAudioIfCancelled`.

---

## File Path & Retention Rules

| Scenario | Behavior |
|----------|----------|
| No path provided | Use `NSTemporaryDirectory()/dictation-<ISO8601>.wav`. |
| Relative path (no leading `/`) | Treat as Documents-relative (`Documents/relative/path.wav`). |
| Absolute path | Must point inside the sandbox; we do not attempt to escape the container. |
| Missing extension | `.wav` is appended automatically. |
| Unsupported extension | Throws `INVALID_ARGUMENTS` before recording starts. |
| Cancel + `deleteAudioIfCancelled=true` | File is deleted, no `audioFile` event/callback. |
| Cancel + `deleteAudioIfCancelled=false` | File retained + event emitted with `wasCancelled=true`. |

> **Tip:** When you keep files for cancelled sessions, annotate downstream storage with the `wasCancelled` flag to avoid confusing QA with incomplete takes.

---

## Error & Edge Cases

- **Permission failures:** Same as baseline dictation flow; no file is created.
- **Disk errors:** Writer logs via `NSLog` and simply skips appending the failing buffer. Stop will return whatever managed to flush; callers should verify `fileSizeBytes > 0`.
- **Concurrent sessions:** Only one dictation session is supported at a time. We guard against duplicate writers and reset state on stop/cancel.
- **Hot-reload / channel drops:** `NativeDictationService.initialize()` already auto-retries; audio preservation piggybacks on that machinery.

---

## Validation Checklist

1. **Happy path (stop):** Verify `audioFile` event arrives with plausible duration/size, and the file plays back via Quick Look or `ffplay`.
2. **Cancel behavior:** Toggle `deleteAudioIfCancelled` to confirm the file is removed/kept as expected.
3. **Custom path:** Test absolute (`/var/mobile/...`) and relative (`Recordings/foo.caf`) inputs.
4. **Unsupported extension:** Pass `.mp3` and ensure Flutter receives an `INVALID_ARGUMENTS` error before the mic opens.
5. **Storage pressure:** Simulate low disk by filling the sandbox—writer should log errors and return either a zero-sized file or nil.

---

## Operational Tips

- Prune temporary recordings periodically if you stream many dictations without moving files elsewhere.
- When uploading to servers, prefer background `Isolate`s or `compute` to avoid blocking UI after you receive `onAudioFile`.
- Use the metadata in integration tests: copy the file into test artifacts to compare waveforms or debug recognition discrepancies.

---

Need changes or clarifications? Drop questions in `docs/native_implementation/05_MIGRATION_STRATEGY.md` or file an issue so the reference stays aligned with the native stack.***

