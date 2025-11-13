import Flutter
import Foundation
import AVFoundation

/// Coordinates AudioEngineManager and SpeechRecognizerManager for Flutter platform channels.
/// Handles method channel calls and streams events to Flutter.
class DictationManager: NSObject, FlutterStreamHandler {
    
    // MARK: - Properties
    
    private let audioEngineManager: AudioEngineManager
    private let speechRecognizerManager: SpeechRecognizerManager
    private let methodChannel: FlutterMethodChannel
    private let eventChannel: FlutterEventChannel
    
    private var eventSink: FlutterEventSink?
    private var audioLevelTimer: Timer?
    private var isStreamingAudioLevels = false
    private let audioLevelQueue = DispatchQueue(label: "com.flutterdictation.dictationManager.audioLevel")
    
    private var state: DictationState = .idle
    private let stateQueue = DispatchQueue(label: "com.flutterdictation.dictationManager.state")
    
    // MARK: - State Management
    
    enum DictationState {
        case idle
        case initializing
        case listening
        case stopping
        case stopped
    }
    
    // MARK: - Initialization
    
    init(
        methodChannel: FlutterMethodChannel,
        eventChannel: FlutterEventChannel,
        audioEngineManager: AudioEngineManager? = nil,
        speechRecognizerManager: SpeechRecognizerManager? = nil
    ) {
        self.methodChannel = methodChannel
        self.eventChannel = eventChannel
        
        // Use provided managers or create new ones
        self.audioEngineManager = audioEngineManager ?? AudioEngineManager()
        self.speechRecognizerManager = speechRecognizerManager ?? SpeechRecognizerManager()
        
        super.init()
        
        // Set up event channel stream handler
        eventChannel.setStreamHandler(self)
        
        // Set up callbacks for speech recognizer
        setupSpeechRecognizerCallbacks()
    }
    
    // MARK: - FlutterStreamHandler
    
    func onListen(withArguments arguments: Any?, eventSink events: @escaping FlutterEventSink) -> FlutterError? {
        self.eventSink = events
        return nil
    }
    
    func onCancel(withArguments arguments: Any?) -> FlutterError? {
        self.eventSink = nil
        return nil
    }
    
    // MARK: - Method Channel Handler
    
    func handleMethodCall(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
        log("=== METHOD CALL: \(call.method) ===", level: .info)
        log("Arguments: \(call.arguments ?? "nil")", level: .debug)
        log("Current thread: \(Thread.isMainThread ? "MAIN" : "BACKGROUND")", level: .debug)
        log("Current state: \(state)", level: .debug)
        
        switch call.method {
        case "initialize":
            handleInitialize(result: result)
            
        case "startListening":
            handleStartListening(result: result)
            
        case "stopListening":
            handleStopListening(result: result)
            
        case "cancelListening":
            handleCancelListening(result: result)
            
        case "getAudioLevel":
            handleGetAudioLevel(result: result)
            
        default:
            log("Unknown method: \(call.method)", level: .warning)
            result(FlutterMethodNotImplemented)
        }
    }
    
    // MARK: - Method Implementations
    
    private func handleInitialize(result: @escaping FlutterResult) {
        let startTime = CFAbsoluteTimeGetCurrent()
        log("=== INITIALIZE START ===", level: .info)
        log("Current state: \(state)", level: .info)
        
        Task {
            do {
                // Initialize audio engine
                log("Initializing audio engine...", level: .info)
                let audioEngineStartTime = CFAbsoluteTimeGetCurrent()
                try audioEngineManager.initialize()
                let audioEngineDuration = (CFAbsoluteTimeGetCurrent() - audioEngineStartTime) * 1000
                log("Audio engine initialized in \(String(format: "%.2f", audioEngineDuration))ms", level: .info)
                logEvent("audio_engine_init", metadata: ["duration_ms": audioEngineDuration])
                
                // Initialize speech recognizer
                log("Initializing speech recognizer...", level: .info)
                let recognizerStartTime = CFAbsoluteTimeGetCurrent()
                try await speechRecognizerManager.initialize()
                let recognizerDuration = (CFAbsoluteTimeGetCurrent() - recognizerStartTime) * 1000
                log("Speech recognizer initialized in \(String(format: "%.2f", recognizerDuration))ms", level: .info)
                logEvent("speech_recognizer_init", metadata: ["duration_ms": recognizerDuration])
                
                let totalDuration = (CFAbsoluteTimeGetCurrent() - startTime) * 1000
                log("=== INITIALIZE COMPLETE in \(String(format: "%.2f", totalDuration))ms ===", level: .info)
                logEvent("initialize_complete", metadata: ["total_duration_ms": totalDuration])
                
                await MainActor.run {
                    self.stateQueue.sync {
                        self.state = .idle
                    }
                    log("Sending 'ready' status to Flutter", level: .info)
                    self.sendStatus("ready")
                    result(nil)
                }
            } catch {
                let totalDuration = (CFAbsoluteTimeGetCurrent() - startTime) * 1000
                let dictationError = DictationError.from(error)
                log("=== INITIALIZE FAILED after \(String(format: "%.2f", totalDuration))ms ===", level: .error)
                log("Error: \(error)", level: .error)
                log("Error type: \(type(of: error))", level: .error)
                log("DictationError code: \(dictationError.code)", level: .error)
                log("DictationError message: \(dictationError.localizedDescription)", level: .error)
                logEvent("initialize_error", metadata: [
                    "duration_ms": totalDuration,
                    "error": dictationError.localizedDescription,
                    "code": dictationError.code
                ])
                
                await MainActor.run {
                    result(FlutterError(
                        code: dictationError.code,
                        message: dictationError.localizedDescription,
                        details: nil
                    ))
                }
            }
        }
    }
    
    private func handleStartListening(result: @escaping FlutterResult) {
        let startTime = CFAbsoluteTimeGetCurrent()
        log("=== START LISTENING START ===", level: .info)
        log("Current state: \(state)", level: .info)
        log("Current thread before Task: \(Thread.isMainThread ? "MAIN" : "BACKGROUND")", level: .info)
        
        // CRITICAL: Ensure we're on main thread to preserve user action context for permission dialogs
        // iOS requires permission requests to be triggered directly from user actions on the main thread
        Task { @MainActor in
            log("Inside Task { @MainActor }, thread: \(Thread.isMainThread ? "MAIN" : "BACKGROUND")", level: .info)
            
            do {
                stateQueue.sync {
                    guard self.state == .idle || self.state == .stopped else {
                        log("Cannot start listening - invalid state: \(self.state)", level: .warning)
                        return
                    }
                    self.state = .initializing
                    log("State changed to: .initializing", level: .info)
                }
                
                // Start audio engine first (now async due to permission checking)
                // We're already on main thread, so permission request will preserve user action context
                log("Starting audio engine...", level: .info)
                let audioEngineStartTime = CFAbsoluteTimeGetCurrent()
                try await audioEngineManager.startRecording()
                let audioEngineDuration = (CFAbsoluteTimeGetCurrent() - audioEngineStartTime) * 1000
                log("Audio engine started in \(String(format: "%.2f", audioEngineDuration))ms", level: .info)
                logEvent("audio_engine_start", metadata: ["duration_ms": audioEngineDuration])
                
                // Set up buffer callback to share audio buffers with speech recognizer
                // AVAudioEngine only supports one tap per bus, so we must share the tap installed by AudioEngineManager
                log("Setting up buffer callback for speech recognition...", level: .info)
                audioEngineManager.setBufferCallback { [weak self] buffer in
                    self?.speechRecognizerManager.appendAudioBuffer(buffer)
                }
                
                // Then start speech recognition
                log("Starting speech recognition...", level: .info)
                let recognizerStartTime = CFAbsoluteTimeGetCurrent()
                try await speechRecognizerManager.startRecognition(
                    audioEngine: audioEngineManager.engine
                )
                let recognizerDuration = (CFAbsoluteTimeGetCurrent() - recognizerStartTime) * 1000
                log("Speech recognizer started in \(String(format: "%.2f", recognizerDuration))ms", level: .info)
                logEvent("speech_recognizer_start", metadata: ["duration_ms": recognizerDuration])
                
                // Start audio level streaming for waveform
                log("Starting audio level streaming...", level: .info)
                startAudioLevelStreaming()
                
                let totalDuration = (CFAbsoluteTimeGetCurrent() - startTime) * 1000
                log("=== START LISTENING COMPLETE in \(String(format: "%.2f", totalDuration))ms ===", level: .info)
                logEvent("start_listening_complete", metadata: ["total_duration_ms": totalDuration])
                
                await MainActor.run {
                    self.stateQueue.sync {
                        self.state = .listening
                    }
                    log("State changed to: .listening", level: .info)
                    log("Sending 'listening' status to Flutter", level: .info)
                    self.sendStatus("listening")
                    result(nil)
                }
            } catch {
                let totalDuration = (CFAbsoluteTimeGetCurrent() - startTime) * 1000
                let dictationError = DictationError.from(error)
                log("=== START LISTENING FAILED after \(String(format: "%.2f", totalDuration))ms ===", level: .error)
                log("Error: \(error)", level: .error)
                log("Error type: \(type(of: error))", level: .error)
                log("Error domain: \((error as NSError).domain)", level: .error)
                log("Error code: \((error as NSError).code)", level: .error)
                log("DictationError code: \(dictationError.code)", level: .error)
                log("DictationError message: \(dictationError.localizedDescription)", level: .error)
                logEvent("start_listening_error", metadata: [
                    "duration_ms": totalDuration,
                    "error": dictationError.localizedDescription,
                    "code": dictationError.code
                ])
                
                await MainActor.run {
                    self.stateQueue.sync {
                        self.state = .stopped
                    }
                    log("State changed to: .stopped", level: .info)
                    log("Sending error to Flutter: \(dictationError.localizedDescription)", level: .error)
                    self.sendError(dictationError.localizedDescription)
                    result(FlutterError(
                        code: dictationError.code,
                        message: dictationError.localizedDescription,
                        details: nil
                    ))
                }
            }
        }
    }
    
    private func handleStopListening(result: @escaping FlutterResult) {
        Task {
            stateQueue.sync {
                guard self.state == .listening else {
                    result(nil)
                    return
                }
                self.state = .stopping
            }
            
            // Stop audio level streaming
            stopAudioLevelStreaming()
            
            // Remove buffer callback (stops forwarding buffers to speech recognizer)
            audioEngineManager.removeBufferCallback()
            
            // Stop speech recognition (will finalize result)
            speechRecognizerManager.stopRecognition()
            
            // Stop audio engine
            audioEngineManager.stopRecording()
            
            await MainActor.run {
                self.stateQueue.sync {
                    self.state = .stopped
                }
                self.sendStatus("stopped")
                result(nil)
            }
        }
    }
    
    private func handleCancelListening(result: @escaping FlutterResult) {
        Task {
            stateQueue.sync {
                guard self.state == .listening || self.state == .initializing else {
                    result(nil)
                    return
                }
            }
            
            // Stop audio level streaming
            stopAudioLevelStreaming()
            
            // Remove buffer callback (stops forwarding buffers to speech recognizer)
            audioEngineManager.removeBufferCallback()
            
            // Cancel speech recognition
            speechRecognizerManager.cancelRecognition()
            
            // Stop audio engine
            audioEngineManager.stopRecording()
            
            await MainActor.run {
                self.stateQueue.sync {
                    self.state = .stopped
                }
                self.sendStatus("cancelled")
                result(nil)
            }
        }
    }
    
    private func handleGetAudioLevel(result: @escaping FlutterResult) {
        let level = audioEngineManager.getAudioLevel()
        result(level)
    }
    
    // MARK: - Speech Recognizer Callbacks
    
    private func setupSpeechRecognizerCallbacks() {
        speechRecognizerManager.setResultCallback { [weak self] text, isFinal in
            self?.sendResult(text, isFinal: isFinal)
        }
        
        speechRecognizerManager.setStatusCallback { [weak self] status in
            // Status updates from speech recognizer are handled separately
            // We'll send our own status updates from DictationManager
        }
    }
    
    // MARK: - Event Streaming
    
    private func sendResult(_ text: String, isFinal: Bool) {
        let event: [String: Any] = [
            "type": "result",
            "text": text,
            "isFinal": isFinal
        ]
        eventSink?(event)
    }
    
    private func sendStatus(_ status: String) {
        let event: [String: Any] = [
            "type": "status",
            "status": status
        ]
        eventSink?(event)
    }
    
    private func sendAudioLevel(_ level: Float) {
        let event: [String: Any] = [
            "type": "audioLevel",
            "level": level
        ]
        eventSink?(event)
    }
    
    private func sendError(_ message: String) {
        let event: [String: Any] = [
            "type": "error",
            "message": message
        ]
        eventSink?(event)
    }
    
    // MARK: - Audio Level Streaming
    
    private func startAudioLevelStreaming() {
        audioLevelQueue.sync {
            guard !isStreamingAudioLevels else { return }
            isStreamingAudioLevels = true
        }
        
        stopAudioLevelStreaming() // Ensure no existing timer
        
        // Create timer on main thread for 60 FPS (every ~16ms)
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            
            // Double-check we should still be streaming
            let shouldStream = self.audioLevelQueue.sync {
                return self.isStreamingAudioLevels
            }
            
            guard shouldStream else { return }
            
            self.audioLevelTimer = Timer.scheduledTimer(withTimeInterval: 0.016, repeats: true) { [weak self] _ in
                guard let self = self else { return }
                
                // Check if we should still be streaming
                let shouldContinue = self.audioLevelQueue.sync {
                    return self.isStreamingAudioLevels
                }
                
                guard shouldContinue else {
                    self.stopAudioLevelStreaming()
                    return
                }
                
                let level = self.audioEngineManager.getAudioLevel()
                self.sendAudioLevel(level)
            }
            
            // Add timer to main run loop to ensure it runs during UI interactions
            if let timer = self.audioLevelTimer {
                RunLoop.main.add(timer, forMode: .common)
            }
        }
    }
    
    private func stopAudioLevelStreaming() {
        audioLevelQueue.sync {
            isStreamingAudioLevels = false
        }
        
        DispatchQueue.main.async { [weak self] in
            self?.audioLevelTimer?.invalidate()
            self?.audioLevelTimer = nil
        }
    }
    
    // MARK: - State Queries
    
    var isListening: Bool {
        return stateQueue.sync {
            return self.state == .listening || self.state == .initializing
        }
    }
    
    // MARK: - Logging
    
    /// Comprehensive logging function that ensures logs are visible in both Xcode and Flutter console.
    private func log(_ message: String, level: LogLevel = .info, file: String = #file, function: String = #function, line: Int = #line) {
        let fileName = (file as NSString).lastPathComponent
        let timestamp = String(format: "%.3f", CFAbsoluteTimeGetCurrent())
        let threadName = Thread.isMainThread ? "MAIN" : "BG"
        let logMessage = "[\(timestamp)] [DictationManager] [\(level.rawValue)] [\(threadName)] \(fileName):\(line) \(function) - \(message)"
        print(logMessage)
        NSLog("%@", logMessage)
    }
    
    private enum LogLevel: String {
        case debug = "DEBUG"
        case info = "INFO"
        case warning = "WARN"
        case error = "ERROR"
    }
    
    /// Logs events with metadata for performance monitoring and debugging.
    /// - Parameters:
    ///   - event: Event name
    ///   - metadata: Additional metadata dictionary
    private func logEvent(_ event: String, metadata: [String: Any] = [:]) {
        let metadataString = metadata.map { "\($0.key)=\($0.value)" }.joined(separator: ", ")
        log("\(event): \(metadataString)", level: .info)
    }
    
    // MARK: - Cleanup
    
    deinit {
        stopAudioLevelStreaming()
        audioEngineManager.stopRecording()
        speechRecognizerManager.cancelRecognition()
    }
}

// MARK: - Error Types

enum DictationError: Error {
    case notAuthorized
    case notAvailable
    case audioEngineFailed
    case recognitionFailed
    case initializationFailed
    case unknown(Error)
    
    var code: String {
        switch self {
        case .notAuthorized:
            return "NOT_AUTHORIZED"
        case .notAvailable:
            return "NOT_AVAILABLE"
        case .audioEngineFailed:
            return "AUDIO_ENGINE_ERROR"
        case .recognitionFailed:
            return "RECOGNITION_ERROR"
        case .initializationFailed:
            return "INIT_ERROR"
        case .unknown:
            return "UNKNOWN_ERROR"
        }
    }
    
    var localizedDescription: String {
        switch self {
        case .notAuthorized:
            return "Speech recognition not authorized. Please grant microphone and speech recognition permissions."
        case .notAvailable:
            return "Speech recognition is not available on this device."
        case .audioEngineFailed:
            return "Audio engine failed to start. Please try again."
        case .recognitionFailed:
            return "Speech recognition failed. Please try again."
        case .initializationFailed:
            return "Failed to initialize dictation service. Please try again."
        case .unknown(let error):
            return error.localizedDescription
        }
    }
    
    static func from(_ error: Error) -> DictationError {
        if let speechError = error as? SpeechRecognizerError {
            switch speechError {
            case .notAuthorized:
                return .notAuthorized
            case .notAvailable:
                return .notAvailable
            case .notInitialized, .requestCreationFailed:
                return .initializationFailed
            }
        }
        
        // Check for audio session errors
        let nsError = error as NSError
        if nsError.domain == "com.apple.coreaudio" || nsError.domain == "AudioEngineManager" {
            // Check if it's a permission error
            let errorMessage = nsError.localizedDescription.lowercased()
            if errorMessage.contains("permission") && errorMessage.contains("denied") {
                return .notAuthorized
            }
            return .audioEngineFailed
        }
        
        return .unknown(error)
    }
}


