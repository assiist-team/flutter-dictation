# Phase 4: Waveform Visualization Streaming

## Objective

Stream audio level data from native iOS to Flutter for real-time waveform visualization, replacing the `audio_waveforms` package dependency.

## Goals

- ✅ Real-time audio level streaming (60 FPS)
- ✅ Smooth waveform animation
- ✅ Low CPU overhead
- ✅ Reuse existing waveform widget

## Implementation Steps

### Step 1: Audio Level Calculation (Native)

**Already implemented in Phase 1**, but optimize for streaming:

**In AudioEngineManager.swift**:
```swift
private var currentAudioLevel: Float = 0.0
private let levelSmoothingFactor: Float = 0.3  // Smooth transitions

func updateAudioLevel(from buffer: AVAudioPCMBuffer) {
    let newLevel = calculateAudioLevel(from: buffer)
    
    // Smooth the level to avoid jittery waveform
    currentAudioLevel = currentAudioLevel * (1.0 - levelSmoothingFactor) + 
                       newLevel * levelSmoothingFactor
}

func getAudioLevel() -> Float {
    return currentAudioLevel
}
```

**Why Smoothing**:
- Raw audio levels can be jittery
- Smoothing creates more visually appealing waveform
- Still responsive enough for real-time feedback

### Step 2: Stream Audio Levels

**In DictationManager.swift**:
```swift
private var audioLevelTimer: Timer?
private let audioLevelUpdateInterval: TimeInterval = 0.016  // ~60 FPS

func startAudioLevelStreaming() {
    audioLevelTimer = Timer.scheduledTimer(withTimeInterval: audioLevelUpdateInterval, repeats: true) { [weak self] _ in
        guard let self = self else { return }
        let level = self.audioEngineManager.getAudioLevel()
        self.sendAudioLevel(level)
    }
}

func stopAudioLevelStreaming() {
    audioLevelTimer?.invalidate()
    audioLevelTimer = nil
}
```

**Update Frequency**:
- 60 FPS = 16.67ms intervals
- Good balance between smoothness and performance
- Can reduce to 30 FPS if needed for lower CPU

### Step 3: Create Waveform Controller (Dart)

**File**: `lib/services/waveform_controller.dart`

**Purpose**: Bridge between native audio levels and waveform widget

```dart
class WaveformController extends ChangeNotifier {
  double _currentLevel = 0.0;
  final List<double> _waveformData = [];
  static const int maxSamples = 100;  // Keep last 100 samples
  
  double get currentLevel => _currentLevel;
  List<double> get waveformData => List.unmodifiable(_waveformData);
  
  void updateLevel(double level) {
    _currentLevel = level;
    _waveformData.add(level);
    
    // Keep only recent samples
    if (_waveformData.length > maxSamples) {
      _waveformData.removeAt(0);
    }
    
    notifyListeners();
  }
  
  void reset() {
    _currentLevel = 0.0;
    _waveformData.clear();
    notifyListeners();
  }
}
```

### Step 4: Integrate with Native Service

**In native_dictation_service.dart**:
```dart
Future<void> startListening({
  required Function(String, bool) onResult,
  required Function(String) onStatus,
  required Function(double) onAudioLevel,
}) async {
  _setupEventStream(
    onResult: onResult,
    onStatus: onStatus,
    onAudioLevel: onAudioLevel,
  );
  
  await _methodChannel.invokeMethod('startListening');
}
```

**Audio Level Callback**:
```dart
void _setupEventStream({
  required Function(String, bool) onResult,
  required Function(String) onStatus,
  required Function(double) onAudioLevel,
}) {
  _eventSubscription = _eventChannel.receiveBroadcastStream().listen(
    (dynamic event) {
      final Map<String, dynamic> data = Map<String, dynamic>.from(event);
      
      if (data['type'] == 'audioLevel') {
        onAudioLevel(data['level'] as double);
      }
      // ... handle other event types
    },
  );
}
```

### Step 5: Update Waveform Widget

**Option A: Create New Widget** (Recommended)

**File**: `lib/widgets/native_waveform.dart`

```dart
class NativeWaveform extends StatelessWidget {
  final WaveformController controller;
  final double height;
  final Color? color;

  const NativeWaveform({
    required this.controller,
    this.height = 40.0,
    this.color,
  });

  @override
  Widget build(BuildContext context) {
    final waveformColor =
        color ?? DictationStyles.secondaryTextColor(context);

    return ListenableBuilder(
      listenable: controller,
      builder: (context, child) {
        return CustomPaint(
          size: Size(double.infinity, height),
          painter: WaveformPainter(
            levels: controller.waveformData,
            color: waveformColor,
          ),
        );
      },
    );
  }
}
```

**Option B: Adapt Existing Widget**

If keeping `audio_waveforms` widget, create adapter:
```dart
class WaveformAdapter {
  static Widget buildWaveform(WaveformController controller) {
    // Convert controller data to format expected by existing widget
    // Or create new simple widget
  }
}
```

### Step 6: Waveform Painter

**File**: `lib/widgets/waveform_painter.dart`

```dart
class WaveformPainter extends CustomPainter {
  final List<double> levels;
  final Color color;
  
  WaveformPainter({
    required this.levels,
    required this.color,
  });
  
  @override
  void paint(Canvas canvas, Size size) {
    if (levels.isEmpty) return;
    
    final paint = Paint()
      ..color = color
      ..strokeWidth = 2.0
      ..style = PaintingStyle.fill;
    
    final barWidth = size.width / levels.length;
    final centerY = size.height / 2;
    
    for (int i = 0; i < levels.length; i++) {
      final level = levels[i];
      final barHeight = level * size.height;
      final x = i * barWidth;
      
      // Draw bar centered vertically
      final rect = Rect.fromLTWH(
        x,
        centerY - barHeight / 2,
        barWidth - 1,
        barHeight,
      );
      
      canvas.drawRRect(
        RRect.fromRectAndRadius(rect, Radius.circular(2)),
        paint,
      );
    }
  }
  
  @override
  bool shouldRepaint(WaveformPainter oldDelegate) {
    return oldDelegate.levels != levels;
  }
}
```

### Step 7: Integration Example

**In main.dart**:
```dart
class _DictationExampleScreenState extends State<DictationExampleScreen> {
  final WaveformController _waveformController = WaveformController();
  final NativeDictationService _dictationService = NativeDictationService();
  
  void _startListening() async {
    await _dictationService.startListening(
      onResult: _onSpeechResult,
      onStatus: _onStatusUpdate,
      onAudioLevel: (level) {
        _waveformController.updateLevel(level);
      },
    );
  }
  
  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        NativeWaveform(controller: _waveformController),
        // ... rest of UI
      ],
    );
  }
}
```

## Performance Optimization

### Reduce Update Frequency if Needed

**If CPU usage is high**:
```swift
// Reduce to 30 FPS
private let audioLevelUpdateInterval: TimeInterval = 0.033
```

### Batch Updates

**If too many updates**:
```dart
// Throttle updates in Dart
Timer? _updateTimer;
void updateLevel(double level) {
  _pendingLevel = level;
  _updateTimer ??= Timer(Duration(milliseconds: 16), () {
    _currentLevel = _pendingLevel;
    notifyListeners();
    _updateTimer = null;
  });
}
```

### Limit Waveform Samples

**Keep only recent data**:
```dart
static const int maxSamples = 50;  // Reduce if needed
```

## Testing Checklist

- [ ] Audio levels stream at correct frequency
- [ ] Waveform updates smoothly
- [ ] No jittery animation
- [ ] CPU usage acceptable (< 10% for waveform)
- [ ] Memory usage stable (no leaks)
- [ ] Waveform resets when recording stops
- [ ] Works with existing UI components

## Performance Targets

- **Update Rate**: 60 FPS (16ms intervals)
- **CPU Usage**: < 5% for waveform rendering
- **Latency**: < 20ms from audio to visual update
- **Memory**: < 10MB for waveform data

## Alternative: Keep audio_waveforms Package

**If preferred**, can still use `audio_waveforms` package:
- Stream audio level to package's controller
- Less custom code
- But adds dependency and potential latency

**Recommendation**: Custom implementation gives more control and lower latency.

## Dependencies

- Native audio level calculation (Phase 1)
- Event channel streaming (Phase 3)
- Flutter custom painting

## Next Phase

Once waveform is working:
→ **Phase 5**: Migration Strategy (`05_MIGRATION_STRATEGY.md`)

