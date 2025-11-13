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
        Task {
            do {
                // Initialize audio engine
                try audioEngineManager.initialize()
                
                // Initialize speech recognizer
                try await speechRecognizerManager.initialize()
                
                await MainActor.run {
                    self.stateQueue.sync {
                        self.state = .idle
                    }
                    self.sendStatus("ready")
                    result(nil)
                }
            } catch {
                await MainActor.run {
                    result(FlutterError(
                        code: "INIT_ERROR",
                        message: error.localizedDescription,
                        details: nil
                    ))
                }
            }
        }
    }
    
    private func handleStartListening(result: @escaping FlutterResult) {
        Task {
            do {
                stateQueue.sync {
                    guard self.state == .idle || self.state == .stopped else {
                        return
                    }
                    self.state = .initializing
                }
                
                // Start audio engine first
                try audioEngineManager.startRecording()
                
                // Then start speech recognition
                try await speechRecognizerManager.startRecognition(
                    audioEngine: audioEngineManager.engine
                )
                
                // Start audio level streaming for waveform
                startAudioLevelStreaming()
                
                await MainActor.run {
                    self.stateQueue.sync {
                        self.state = .listening
                    }
                    self.sendStatus("listening")
                    result(nil)
                }
            } catch {
                await MainActor.run {
                    self.stateQueue.sync {
                        self.state = .stopped
                    }
                    self.sendStatus("error")
                    result(FlutterError(
                        code: "START_ERROR",
                        message: error.localizedDescription,
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
    
    // MARK: - Cleanup
    
    deinit {
        stopAudioLevelStreaming()
        audioEngineManager.stopRecording()
        speechRecognizerManager.cancelRecognition()
    }
}


