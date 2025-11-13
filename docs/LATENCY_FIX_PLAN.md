# Speech Recognition Latency Fix Plan

## Problem Description

There is a significant delay (approximately 3 seconds) when starting speech recognition, particularly noticeable when:
- The app has been idle for a while
- The user clicks the mic button and immediately starts speaking
- The delay occurs between tapping the mic and when recording actually begins

This delay causes the first 2-3 seconds of speech to be lost, which is unacceptable for a dictation feature. The issue manifests as:
- Waveform not appearing immediately after tapping the mic
- Speech recognition status taking 2-3 seconds to transition to "listening"
- Users losing the beginning of their dictation

The root cause appears to be related to iOS speech recognition initialization overhead, particularly when the system resources need to be warmed up after idle periods.

## Plan

### 1. Diagnose Latency

- **Add detailed timing logs** around `_speechToText.listen()` calls, status callbacks, and audio engine activation to pinpoint exactly where the delay occurs
- **Add telemetry** to track audio session setup times in `_initialize()` and `startListening()` to compare cold starts vs warm starts
- **Use Flutter DevTools timeline** to identify any blocking operations on the main thread that might delay mic activation

### 2. Optimize Start Flow

- **Pre-warm audio resources**: After initialization completes, perform a silent "priming" operation (start/stop speech recognition once) to ensure iOS resources are ready
- **Start recording earlier**: Call `RecorderController.record()` immediately when mic is pressed (before UI state changes) to parallelize audio setup with speech recognition setup
- **Use optimal ListenMode**: Ensure we're using `ListenMode.dictation` (not `confirmation`) for better performance with longer speech
- **Configure audio session proactively**: Set up AVAudioSession configuration during initialization rather than on-demand during recording

### 3. Refine Stop/Cancel Cleanup

- **Ensure proper serialization**: Make sure stop/cancel operations fully complete before allowing new listen operations to prevent state conflicts
- **Verify cleanup completion**: Add checks to ensure both speech_to_text and audio_waveforms controllers are fully reset before allowing new recording sessions
- **Remove unnecessary delays**: Eliminate any artificial delays or waits that aren't strictly necessary

### 4. Validate Fixes

- **Test cold starts**: Measure time from mic tap to "listening" status after app has been idle
- **Test warm starts**: Measure time from mic tap to "listening" status when immediately starting a new recording after stopping
- **Target performance**: Achieve sub-500ms latency from tap to active recording
- **Remove debug code**: Clean up temporary logging and telemetry once latency is consistently low

