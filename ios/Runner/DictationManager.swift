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
            result(FlutterMethodNotImplemented)
        }
    }
    
    // MARK: - Method Implementations
    
    private func handleInitialize(result: @escaping FlutterResult) {
        let startTime = CFAbsoluteTimeGetCurrent()
        
        Task {
            do {
                // Initialize audio engine
                let audioEngineStartTime = CFAbsoluteTimeGetCurrent()
                try audioEngineManager.initialize()
                let audioEngineDuration = (CFAbsoluteTimeGetCurrent() - audioEngineStartTime) * 1000
                logEvent("audio_engine_init", metadata: ["duration_ms": audioEngineDuration])
                
                // Initialize speech recognizer
                let recognizerStartTime = CFAbsoluteTimeGetCurrent()
                try await speechRecognizerManager.initialize()
                let recognizerDuration = (CFAbsoluteTimeGetCurrent() - recognizerStartTime) * 1000
                logEvent("speech_recognizer_init", metadata: ["duration_ms": recognizerDuration])
                
                let totalDuration = (CFAbsoluteTimeGetCurrent() - startTime) * 1000
                logEvent("initialize_complete", metadata: ["total_duration_ms": totalDuration])
                
                await MainActor.run {
                    self.stateQueue.sync {
                        self.state = .idle
                    }
                    self.sendStatus("ready")
                    result(nil)
                }
            } catch {
                let totalDuration = (CFAbsoluteTimeGetCurrent() - startTime) * 1000
                let dictationError = DictationError.from(error)
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
        
        Task {
            do {
                stateQueue.sync {
                    guard self.state == .idle || self.state == .stopped else {
                        return
                    }
                    self.state = .initializing
                }
                
                // Start audio engine first
                let audioEngineStartTime = CFAbsoluteTimeGetCurrent()
                try audioEngineManager.startRecording()
                let audioEngineDuration = (CFAbsoluteTimeGetCurrent() - audioEngineStartTime) * 1000
                logEvent("audio_engine_start", metadata: ["duration_ms": audioEngineDuration])
                
                // Then start speech recognition
                let recognizerStartTime = CFAbsoluteTimeGetCurrent()
                try await speechRecognizerManager.startRecognition(
                    audioEngine: audioEngineManager.engine
                )
                let recognizerDuration = (CFAbsoluteTimeGetCurrent() - recognizerStartTime) * 1000
                logEvent("speech_recognizer_start", metadata: ["duration_ms": recognizerDuration])
                
                // Start audio level streaming for waveform
                startAudioLevelStreaming()
                
                let totalDuration = (CFAbsoluteTimeGetCurrent() - startTime) * 1000
                logEvent("start_listening_complete", metadata: ["total_duration_ms": totalDuration])
                
                await MainActor.run {
                    self.stateQueue.sync {
                        self.state = .listening
                    }
                    self.sendStatus("listening")
                    result(nil)
                }
            } catch {
                let totalDuration = (CFAbsoluteTimeGetCurrent() - startTime) * 1000
                let dictationError = DictationError.from(error)
                logEvent("start_listening_error", metadata: [
                    "duration_ms": totalDuration,
                    "error": dictationError.localizedDescription,
                    "code": dictationError.code
                ])
                
                await MainActor.run {
                    self.stateQueue.sync {
                        self.state = .stopped
                    }
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
    
    /// Logs events with metadata for performance monitoring and debugging.
    /// - Parameters:
    ///   - event: Event name
    ///   - metadata: Additional metadata dictionary
    private func logEvent(_ event: String, metadata: [String: Any] = [:]) {
        #if DEBUG
        let metadataString = metadata.map { "\($0.key)=\($0.value)" }.joined(separator: ", ")
        print("[DictationManager] \(event): \(metadataString)")
        #endif
        // In production, this could send to analytics or crash reporting
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
        if nsError.domain == "com.apple.coreaudio" {
            return .audioEngineFailed
        }
        
        return .unknown(error)
    }
}


