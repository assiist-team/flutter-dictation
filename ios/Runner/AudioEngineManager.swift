import AVFoundation
import Foundation

/// Manages AVAudioEngine for low-latency audio recording and waveform visualization.
/// Provides real-time audio buffer access with optimal configuration for speech recognition.
class AudioEngineManager {
    
    // MARK: - Properties
    
    private let audioEngine = AVAudioEngine()
    private let audioSession = AVAudioSession.sharedInstance()
    
    /// Exposes the audio engine for speech recognizer attachment.
    var engine: AVAudioEngine {
        return audioEngine
    }
    
    private var inputNode: AVAudioInputNode {
        return audioEngine.inputNode
    }
    
    private var bufferCallback: ((AVAudioPCMBuffer) -> Void)?
    private var currentAudioLevel: Float = 0.0
    private var state: AudioEngineState = .idle
    
    // Audio level smoothing for waveform visualization
    private let levelSmoothingFactor: Float = 0.3  // Smooth transitions
    
    // Thread-safe audio level access
    private let audioLevelQueue = DispatchQueue(label: "com.flutterdictation.audioLevel")
    
    // MARK: - State Management
    
    enum AudioEngineState {
        case idle          // Initialized, ready
        case recording     // Actively recording
        case stopped       // Stopped, can restart quickly
    }
    
    // MARK: - Initialization
    
    /// Initializes the audio engine with optimal low-latency configuration.
    /// Should be called at app launch for pre-warming.
    /// - Throws: Audio session configuration errors
    func initialize() throws {
        guard state == .idle else {
            // Already initialized
            return
        }
        
        // Configure audio session for low-latency recording
        try configureAudioSession()
        
        // Set up audio engine
        setupAudioEngine()
        
        // Register for audio session interruptions
        setupInterruptionHandling()
        
        state = .idle
    }
    
    // MARK: - Audio Session Configuration
    
    private func configureAudioSession() throws {
        // Category: Record mode for low-latency
        try audioSession.setCategory(.record, mode: .measurement, options: [])
        
        // Buffer duration: 5ms for minimal latency
        try audioSession.setPreferredIOBufferDuration(0.005)
        
        // Sample rate: 16kHz is sufficient for speech
        try audioSession.setPreferredSampleRate(16000)
        
        // Activate session
        try audioSession.setActive(true)
    }
    
    // MARK: - Audio Engine Setup
    
    private func setupAudioEngine() {
        // Prepare the audio engine (required before installing tap)
        audioEngine.prepare()
        
        // Note: Tap will be installed when recording starts to avoid
        // processing buffers when idle. This is handled in startRecording()
    }
    
    private func installAudioTap() {
        // Remove existing tap if any
        inputNode.removeTap(onBus: 0)
        
        let inputFormat = inputNode.inputFormat(forBus: 0)
        
        // Install tap to capture audio buffers
        // Buffer size: 1024 samples = ~64ms at 16kHz (good balance)
        inputNode.installTap(
            onBus: 0,
            bufferSize: 1024,
            format: inputFormat
        ) { [weak self] buffer, time in
            self?.processAudioBuffer(buffer)
        }
    }
    
    // MARK: - Recording Control
    
    /// Starts audio recording.
    /// - Throws: Audio engine start errors
    func startRecording() throws {
        guard state != .recording else {
            // Already recording
            return
        }
        
        // Ensure audio session is active
        if !audioSession.isOtherAudioPlaying {
            try audioSession.setActive(true)
        }
        
        // Install tap (must be done before engine starts)
        // If engine is already running, stop it first
        if audioEngine.isRunning {
            audioEngine.stop()
        }
        
        installAudioTap()
        
        // Start the audio engine
        try audioEngine.start()
        
        state = .recording
    }
    
    /// Stops audio recording.
    func stopRecording() {
        guard state == .recording else {
            return
        }
        
        // Stop the audio engine
        if audioEngine.isRunning {
            audioEngine.stop()
        }
        
        // Remove tap to stop processing buffers
        inputNode.removeTap(onBus: 0)
        
        // Reset audio level
        audioLevelQueue.sync {
            self.currentAudioLevel = 0.0
        }
        
        state = .stopped
    }
    
    // MARK: - Buffer Processing
    
    private func processAudioBuffer(_ buffer: AVAudioPCMBuffer) {
        // Only process buffers when actively recording
        guard state == .recording else {
            return
        }
        
        // Calculate audio level for waveform visualization
        let newLevel = calculateAudioLevel(from: buffer)
        
        // Smooth the level to avoid jittery waveform
        audioLevelQueue.sync {
            self.currentAudioLevel = self.currentAudioLevel * (1.0 - self.levelSmoothingFactor) +
                                   newLevel * self.levelSmoothingFactor
        }
        
        // Call buffer callback if set
        if let callback = bufferCallback {
            callback(buffer)
        }
    }
    
    // MARK: - Audio Level Calculation
    
    /// Calculates audio level from buffer for waveform visualization.
    /// - Parameter buffer: Audio PCM buffer
    /// - Returns: Normalized audio level (0.0 - 1.0)
    private func calculateAudioLevel(from buffer: AVAudioPCMBuffer) -> Float {
        guard let channelData = buffer.floatChannelData else { return 0.0 }
        
        let channelDataValue = channelData.pointee
        let channelDataValueArray = stride(
            from: 0,
            to: Int(buffer.frameLength),
            by: buffer.stride
        ).map { channelDataValue[$0] }
        
        // Calculate RMS (Root Mean Square)
        let sumOfSquares = channelDataValueArray.map { $0 * $0 }.reduce(0, +)
        let rms = sqrt(sumOfSquares / Float(buffer.frameLength))
        
        // Convert to decibels
        let avgPower = 20 * log10(max(rms, 1e-10)) // Avoid log(0)
        
        // Normalize to 0.0 - 1.0 range (assuming -60dB to 0dB range)
        let normalizedLevel = (avgPower + 60) / 60
        return max(0.0, min(1.0, normalizedLevel))
    }
    
    /// Gets the current audio level for waveform visualization.
    /// - Returns: Normalized audio level (0.0 - 1.0)
    func getAudioLevel() -> Float {
        return audioLevelQueue.sync {
            return self.currentAudioLevel
        }
    }
    
    // MARK: - Buffer Callback
    
    /// Sets a callback to receive audio buffers in real-time.
    /// - Parameter callback: Closure called with each audio buffer
    func setBufferCallback(_ callback: @escaping (AVAudioPCMBuffer) -> Void) {
        bufferCallback = callback
    }
    
    /// Removes the buffer callback.
    func removeBufferCallback() {
        bufferCallback = nil
    }
    
    // MARK: - Interruption Handling
    
    private func setupInterruptionHandling() {
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleAudioSessionInterruption(_:)),
            name: AVAudioSession.interruptionNotification,
            object: audioSession
        )
        
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleAudioSessionRouteChange(_:)),
            name: AVAudioSession.routeChangeNotification,
            object: audioSession
        )
    }
    
    @objc private func handleAudioSessionInterruption(_ notification: Notification) {
        guard let userInfo = notification.userInfo,
              let typeValue = userInfo[AVAudioSessionInterruptionTypeKey] as? UInt,
              let type = AVAudioSession.InterruptionType(rawValue: typeValue) else {
            return
        }
        
        switch type {
        case .began:
            // Interruption started - pause recording
            if state == .recording {
                audioEngine.pause()
            }
            
        case .ended:
            // Interruption ended - resume if needed
            if let optionsValue = userInfo[AVAudioSessionInterruptionOptionKey] as? UInt {
                let options = AVAudioSession.InterruptionOptions(rawValue: optionsValue)
                if options.contains(.shouldResume) && state == .recording {
                    do {
                        try audioSession.setActive(true)
                        try audioEngine.start()
                    } catch {
                        print("AudioEngineManager: Failed to resume after interruption: \(error)")
                        state = .stopped
                    }
                }
            }
            
        @unknown default:
            break
        }
    }
    
    @objc private func handleAudioSessionRouteChange(_ notification: Notification) {
        guard let userInfo = notification.userInfo,
              let reasonValue = userInfo[AVAudioSessionRouteChangeReasonKey] as? UInt,
              let reason = AVAudioSession.RouteChangeReason(rawValue: reasonValue) else {
            return
        }
        
        switch reason {
        case .oldDeviceUnavailable:
            // Headphones unplugged, etc.
            if state == .recording {
                stopRecording()
            }
            
        default:
            break
        }
    }
    
    // MARK: - Cleanup
    
    deinit {
        NotificationCenter.default.removeObserver(self)
        if audioEngine.isRunning {
            audioEngine.stop()
        }
        // Remove tap if installed (safe to call even if no tap exists)
        inputNode.removeTap(onBus: 0)
    }
    
    // MARK: - State Queries
    
    /// Returns whether the audio engine is currently recording.
    var isRecording: Bool {
        return state == .recording
    }
    
    /// Returns whether the audio engine is running.
    var isRunning: Bool {
        return audioEngine.isRunning
    }
}

