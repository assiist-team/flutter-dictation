## First-tap slowness and choppy waveform — diagnosis

### What you’re seeing
- App launch feels slow; first mic tap is significantly slower than later taps.
- Waveform is choppy during first run; log shows hundreds of duplicate-looking entries.
- After stopping once, subsequent taps are fast and feel normal.

### High‑confidence root causes
- Warm‑up didn’t actually run before the first tap.
  - Lifecycle hook tried to trigger warm‑up before the audio engine manager instance existed; no follow‑up trigger fired once it became available.
  - The “pre‑warm” that did run performed initialization (category/mode setup) but did not activate the session or briefly run the engine.
- Mic permission gating prevents true warm‑up unless permission was already granted pre‑tap.
- Two manager instances can be used (plugin pre‑warm vs. `DictationManager`’s own), so the warmed instance isn’t necessarily the one serving recording.
- Logging is excessive and duplicated (both `print` and `NSLog`), and audio‑level events are emitted at ~60 FPS, causing visible jank and log flood in debug.
- Extra minor: method channel is set via both a closure and a delegate, which risks double handling (even if guards often prevent it).

### Evidence
- Warm‑up tried too early; manager wasn’t ready, and there’s no later retry:

```text
FlutterDictationPlugin: App became active - checking warm-up conditions
FlutterDictationPlugin: Conditions met - triggering warm-up
FlutterDictationPlugin: Audio engine manager not yet initialized - warm-up will happen after init
```

- No “PRE‑WARM SESSION START” logs appear; only an “initialize” path ran. The plugin’s “prewarm” builds the manager and calls `initialize()` (category/mode), not full warm‑up (activation + brief engine run):

```swift
// FlutterDictationPlugin.prewarmAudioEngine()
let manager = AudioEngineManager()
try manager.initialize() // no session activation or brief run here
self?.audioEngineManager = manager
```

- The code that performs true warm‑up (requires mic permission) was never observed running:

```swift
// AudioEngineManager.preWarmSession()
guard audioSession.recordPermission == .granted else { return false }
try audioSession.setActive(true)
try prepareAudioEngineWithPermissionCheck()
try installAudioTap()
try audioEngine.start()
Thread.sleep(forTimeInterval: 0.1)
audioEngine.stop()
// optionally keep session active ("sticky warm")
```

- Two manager instances: `DictationManager` constructs its own if the plugin’s are nil at channel setup, so the “warmed” instance may not be the one used for recording:

```swift
// DictationManager.init(...)
self.audioEngineManager = audioEngineManager ?? AudioEngineManager()
self.speechRecognizerManager = speechRecognizerManager ?? SpeechRecognizerManager()
```

- Subsequent taps are fast because “sticky warm” keeps the session active after the first stop:

```text
[AudioEngineManager] ... stopRecording() - Audio session kept active after stop (for fast subsequent taps)
```

- Log and UI jank contributors:
  - Each native log is emitted twice (`print` + `NSLog`).
  - Audio‑level events are sent at ~60 FPS; Dart logs every event.

### Recommendations (no code here; implementation notes only)
- Ensure true warm‑up runs after the manager exists:
  - If a warm‑up trigger happens while the manager is nil, queue a retry (e.g., immediately after setting `audioEngineManager`, call `triggerWarmUp()`).
- Prompt for mic permission during initialization/onboarding so `preWarmSession()` can succeed pre‑tap.
- Use a single shared instance for `AudioEngineManager`/`SpeechRecognizerManager` (inject warmed instances into `DictationManager`; avoid creating new ones inside it).
- Choose one method channel registration style (closure or `addMethodCallDelegate`), not both.
- Reduce logging volume in hot paths:
  - Use either `print` or `NSLog`, not both.
  - Avoid per‑buffer and per‑tick logs; throttle or sample logs.
- Consider lowering audio‑level event frequency (e.g., 30 FPS) and/or smooth on the Dart side to stabilize the waveform.
- Optionally suppress benign `kAFAssistantErrorDomain 1101` spam after stop in debug builds.

### Expected results after applying the above
- First tap should be low‑latency (≤100–200 ms) because the session will be activated and engine primed pre‑tap.
- Waveform will appear smoother due to less logging overhead and event throttling.
- Logs will be readable and no longer flood the console, improving perceived responsiveness in debug.


