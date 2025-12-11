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
    
    private var eventSink: FlutterEventSink? // strong ref because FlutterEventSink is a block
    private var audioLevelTimer: Timer?
    private var isStreamingAudioLevels = false
    private let audioLevelQueue = DispatchQueue(label: "com.flutterdictation.dictationManager.audioLevel")
    
    private var state: DictationState = .idle
    private let stateQueue = DispatchQueue(label: "com.flutterdictation.dictationManager.state")
    private var audioPreservationConfig: AudioPreservationConfig?
    private var isHandlingDurationLimit = false
    
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
        self.audioEngineManager.delegate = self
        
        // Set up event channel stream handler
        eventChannel.setStreamHandler(self)
        
        // Set up callbacks for speech recognizer
        setupSpeechRecognizerCallbacks()
    }
    
    // MARK: - FlutterStreamHandler
    
    func onListen(withArguments arguments: Any?, eventSink events: @escaping FlutterEventSink) -> FlutterError? {
        log("=== EVENT STREAM LISTEN START ===", level: .info)
        log("Arguments: \(arguments ?? "nil")", level: .debug)
        self.eventSink = events
        log("Event sink set successfully", level: .info)
        log("=== EVENT STREAM LISTEN COMPLETE ===", level: .info)
        return nil
    }
    
    func onCancel(withArguments arguments: Any?) -> FlutterError? {
        log("=== EVENT STREAM CANCEL ===", level: .info)
        self.eventSink = nil
        log("Event sink cleared", level: .info)
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
            do {
                let options = try DictationStartListeningOptions.from(arguments: call.arguments)
                handleStartListening(options: options, result: result)
            } catch {
                let dictationError = DictationError.from(error)
                result(FlutterError(
                    code: dictationError.code,
                    message: dictationError.localizedDescription,
                    details: nil
                ))
            }
            
        case "stopListening":
            handleStopListening(result: result)
            
        case "cancelListening":
            handleCancelListening(result: result)
            
        case "getAudioLevel":
            handleGetAudioLevel(result: result)
            
        case "normalizeAudio":
            handleNormalizeAudio(arguments: call.arguments, result: result)
            
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
    
    private func handleStartListening(options: DictationStartListeningOptions, result: @escaping FlutterResult) {
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
                self.audioPreservationConfig = options.audioPreservationConfig
                let preservationRequest = options.audioPreservationConfig?.audioEngineRequest
                do {
                    try await audioEngineManager.startRecording(audioPreservationRequest: preservationRequest)
                } catch {
                    self.audioPreservationConfig = nil
                    throw error
                }
                let audioEngineDuration = (CFAbsoluteTimeGetCurrent() - audioEngineStartTime) * 1000
                log("Audio engine started in \(String(format: "%.2f", audioEngineDuration))ms", level: .info)
                logEvent("audio_engine_start", metadata: ["duration_ms": audioEngineDuration])
                
                // Set up buffer callback to share audio buffers with speech recognizer
                // AVAudioEngine only supports one tap per bus, so we must share the tap installed by AudioEngineManager
                log("Setting up buffer callback for speech recognition...", level: .info)
                log("About to call setBufferCallback", level: .info)
                audioEngineManager.setBufferCallback { [weak self] buffer in
                    self?.log("=== BUFFER CALLBACK INVOKED ===", level: .info)
                    self?.log("Buffer frameLength: \(buffer.frameLength)", level: .info)
                    self?.log("Buffer sampleRate: \(buffer.format.sampleRate)", level: .info)
                    self?.log("self is nil: \(self == nil)", level: .info)
                    guard let self = self else {
                        return
                    }
                    self.log("Calling speechRecognizerManager.appendAudioBuffer", level: .info)
                    self.speechRecognizerManager.appendAudioBuffer(buffer)
                    self.log("speechRecognizerManager.appendAudioBuffer completed", level: .info)
                }
                log("Buffer callback set successfully", level: .info)
                
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
                print("🔴 LINE 228: Starting audio level streaming...")
                NSLog("🔴 LINE 228: Starting audio level streaming...")
                log("Starting audio level streaming...", level: .info)
                
                print("🔴 LINE 229: About to call startAudioLevelStreaming()")
                NSLog("🔴 LINE 229: About to call startAudioLevelStreaming()")
                log("About to call startAudioLevelStreaming()", level: .info)
                
                print("🔴 LINE 230: Current thread: \(Thread.isMainThread ? "MAIN" : "BACKGROUND")")
                NSLog("🔴 LINE 230: Current thread: \(Thread.isMainThread ? "MAIN" : "BACKGROUND")")
                log("Current thread: \(Thread.isMainThread ? "MAIN" : "BACKGROUND")", level: .info)
                
                print("🔴 LINE 231: About to invoke startAudioLevelStreaming() - this log should appear")
                NSLog("🔴 LINE 231: About to invoke startAudioLevelStreaming() - this log should appear")
                log("About to invoke startAudioLevelStreaming() - this log should appear", level: .info)
                
                print("🔴 LINE 232: Entering do block")
                NSLog("🔴 LINE 232: Entering do block")
                do {
                    print("🔴 LINE 233: About to call startAudioLevelStreaming() function")
                    NSLog("🔴 LINE 233: About to call startAudioLevelStreaming() function")
                    try startAudioLevelStreaming()
                    print("🔴 LINE 234: startAudioLevelStreaming() call completed successfully")
                    NSLog("🔴 LINE 234: startAudioLevelStreaming() call completed successfully")
                    log("startAudioLevelStreaming() call completed successfully", level: .info)
                } catch {
                    print("🔴 LINE 236: ERROR: Exception caught in startAudioLevelStreaming(): \(error)")
                    NSLog("🔴 LINE 236: ERROR: Exception caught in startAudioLevelStreaming(): \(error)")
                    log("ERROR: Exception caught in startAudioLevelStreaming(): \(error)", level: .error)
                    log("Error type: \(type(of: error))", level: .error)
                }
                print("🔴 LINE 239: After startAudioLevelStreaming() call - this log should also appear")
                NSLog("🔴 LINE 239: After startAudioLevelStreaming() call - this log should also appear")
                log("After startAudioLevelStreaming() call - this log should also appear", level: .info)
                
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
            
            // Stop audio engine and finalize audio preservation
            let preservationResult = audioEngineManager.stopRecording(deletePreservedAudio: false)
            let preservationConfig = self.audioPreservationConfig
            self.audioPreservationConfig = nil
            
            await MainActor.run {
                self.stateQueue.sync {
                    self.state = .stopped
                }
                self.sendStatus("stopped")
                if let config = preservationConfig, let resultMetadata = preservationResult {
                    log("Emitting audioFile event after stop (wasCancelled=false, deleteIfCancelled=\(config.deleteIfCancelled))", level: .info)
                    self.sendAudioFile(resultMetadata, wasCancelled: false)
                }
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
            let preservationConfig = self.audioPreservationConfig
            let shouldDeleteAudio = preservationConfig?.deleteIfCancelled ?? true
            let preservationResult = audioEngineManager.stopRecording(deletePreservedAudio: shouldDeleteAudio)
            self.audioPreservationConfig = nil
            
            await MainActor.run {
                self.stateQueue.sync {
                    self.state = .stopped
                }
                self.sendStatus("cancelled")
                if let config = preservationConfig,
                   let resultMetadata = preservationResult {
                    log("Emitting audioFile event after cancel (wasCancelled=true, deleteIfCancelled=\(config.deleteIfCancelled))", level: .info)
                    self.sendAudioFile(resultMetadata, wasCancelled: true)
                }
                result(nil)
            }
        }
    }
    
    private func handleGetAudioLevel(result: @escaping FlutterResult) {
        let level = audioEngineManager.getAudioLevel()
        result(level)
    }
    
    private func handleNormalizeAudio(arguments: Any?, result: @escaping FlutterResult) {
        guard let sourcePath = arguments as? String else {
            result(FlutterError(
                code: "INVALID_ARGUMENTS",
                message: "normalizeAudio requires a sourcePath string argument",
                details: nil
            ))
            return
        }
        
        Task {
            do {
                let encoder = AudioEncoderManager()
                let normalizedResult = try await encoder.normalizeAudio(sourcePath: sourcePath)
                
                await MainActor.run {
                    let response: [String: Any] = [
                        "canonicalPath": normalizedResult.canonicalPath,
                        "durationMs": Int(normalizedResult.durationMs),
                        "sizeBytes": normalizedResult.sizeBytes,
                        "wasReencoded": normalizedResult.wasReencoded
                    ]
                    result(response)
                }
            } catch {
                let normalizationError = error as? NormalizationError ?? NormalizationError.encoderError("Unknown error: \(error.localizedDescription)")
                
                await MainActor.run {
                    result(FlutterError(
                        code: normalizationError.code,
                        message: normalizationError.localizedDescription,
                        details: nil
                    ))
                }
            }
        }
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
        log("Sending result event: text=\"\(text)\", isFinal=\(isFinal)", level: .info)
        if let sink = eventSink {
            sink(event)
            log("Result event sent successfully", level: .debug)
        } else {
            log("ERROR: Cannot send result event - eventSink is nil!", level: .error)
        }
    }
    
    private func sendStatus(_ status: String) {
        let event: [String: Any] = [
            "type": "status",
            "status": status
        ]
        log("Sending status event: status=\"\(status)\"", level: .info)
        if let sink = eventSink {
            sink(event)
            log("Status event sent successfully", level: .debug)
        } else {
            log("ERROR: Cannot send status event - eventSink is nil!", level: .error)
        }
    }
    
    private func sendAudioLevel(_ level: Float) {
        let event: [String: Any] = [
            "type": "audioLevel",
            "level": level
        ]
        // Only log audio level events occasionally to avoid spam (every 10th event)
        if Int.random(in: 0..<10) == 0 {
            log("Sending audioLevel event: level=\(level)", level: .debug)
        }
        if let sink = eventSink {
            sink(event)
        } else {
            // Only log error occasionally to avoid spam
            if Int.random(in: 0..<100) == 0 {
                log("ERROR: Cannot send audioLevel event - eventSink is nil!", level: .error)
            }
        }
    }
    
    private func sendAudioFile(_ result: AudioPreservationResult, wasCancelled: Bool) {
        let event: [String: Any] = [
            "type": "audioFile",
            "path": result.fileURL.path,
            "durationMs": result.durationMs,
            "fileSizeBytes": result.fileSizeBytes,
            "sampleRate": result.sampleRate,
            "channelCount": result.channelCount,
            "wasCancelled": wasCancelled
        ]
        log("Sending audioFile event: path=\"\(result.fileURL.path)\", durationMs=\(result.durationMs), sizeBytes=\(result.fileSizeBytes), wasCancelled=\(wasCancelled)", level: .info)
        if let sink = eventSink {
            sink(event)
            log("audioFile event sent successfully", level: .debug)
        } else {
            log("ERROR: Cannot send audioFile event - eventSink is nil!", level: .error)
        }
    }
    
    private func sendError(_ message: String, code: String? = nil) {
        var event: [String: Any] = [
            "type": "error",
            "message": message
        ]
        if let code = code {
            event["code"] = code
        }
        log("Sending error event: message=\"\(message)\", code=\(code ?? "none")", level: .error)
        if let sink = eventSink {
            sink(event)
            log("Error event sent successfully", level: .debug)
        } else {
            log("ERROR: Cannot send error event - eventSink is nil!", level: .error)
        }
    }
    
    // MARK: - Audio Level Streaming
    
    // Marked as `throws` so callers can wrap in `do/catch` without changing behavior.
    private func startAudioLevelStreaming() throws {
        // CRITICAL DEBUG: Direct print to verify function is called
        // Using multiple print methods to ensure visibility
        print("🔴🔴🔴 CRITICAL LINE 456: startAudioLevelStreaming() FUNCTION ENTRY - THIS MUST APPEAR 🔴🔴🔴")
        NSLog("🔴🔴🔴 CRITICAL LINE 456: startAudioLevelStreaming() FUNCTION ENTRY - THIS MUST APPEAR 🔴🔴🔴")
        
        log("=== START AUDIO LEVEL STREAMING ===", level: .info)
        log("Function entry - thread: \(Thread.isMainThread ? "MAIN" : "BACKGROUND")", level: .info)
        log("About to enter audioLevelQueue.sync", level: .info)
        
        // Stop any existing timer first (without resetting the flag)
        // Use async to avoid deadlock if already on main thread
        if Thread.isMainThread {
            audioLevelTimer?.invalidate()
            audioLevelTimer = nil
            log("Cleared any existing audio level timer (on main thread)", level: .info)
        } else {
            DispatchQueue.main.sync {
                audioLevelTimer?.invalidate()
                audioLevelTimer = nil
                log("Cleared any existing audio level timer (from background thread)", level: .info)
            }
        }
        
        audioLevelQueue.sync {
            log("Inside audioLevelQueue.sync block", level: .info)
            log("isStreamingAudioLevels before check: \(self.isStreamingAudioLevels)", level: .info)
            guard !isStreamingAudioLevels else {
                log("Already streaming audio levels, returning early", level: .warning)
                return
            }
            isStreamingAudioLevels = true
            log("Set isStreamingAudioLevels = true", level: .info)
        }
        
        // Create timer on main thread for 30 FPS (every ~33ms)
        log("About to dispatch to main queue", level: .info)
        log("Current thread before dispatch: \(Thread.isMainThread ? "MAIN" : "BACKGROUND")", level: .info)
        DispatchQueue.main.async { [weak self] in
            self?.log("=== INSIDE MAIN QUEUE ASYNC BLOCK ===", level: .info)
            self?.log("Thread in async block: \(Thread.isMainThread ? "MAIN" : "BACKGROUND")", level: .info)
            guard let self = self else {
                return
            }
            self.log("self is not nil, continuing", level: .info)
            
            // Double-check we should still be streaming
            self.log("About to check shouldStream", level: .info)
            let shouldStream = self.audioLevelQueue.sync {
                self.log("Inside shouldStream check, isStreamingAudioLevels=\(self.isStreamingAudioLevels)", level: .info)
                return self.isStreamingAudioLevels
            }
            self.log("shouldStream result: \(shouldStream)", level: .info)
            
            guard shouldStream else {
                self.log("Should not stream, aborting timer creation", level: .warning)
                return
            }
            
            self.log("Creating audio level timer (30 FPS, ~33ms interval)", level: .info)
            self.audioLevelTimer = Timer.scheduledTimer(withTimeInterval: 0.033, repeats: true) { [weak self] _ in
                guard let self = self else { return }
                
                // Check if we should still be streaming
                let shouldContinue = self.audioLevelQueue.sync {
                    return self.isStreamingAudioLevels
                }
                
                guard shouldContinue else {
                    self.log("Should not continue streaming, stopping timer", level: .info)
                    self.stopAudioLevelStreaming()
                    return
                }
                
                let level = self.audioEngineManager.getAudioLevel()
                self.sendAudioLevel(level)
            }
            
            self.log("Timer created, audioLevelTimer is nil: \(self.audioLevelTimer == nil)", level: .info)
            
            // Add timer to main run loop to ensure it runs during UI interactions
            if let timer = self.audioLevelTimer {
                RunLoop.main.add(timer, forMode: .common)
                self.log("Audio level timer created and added to run loop", level: .info)
            } else {
                self.log("ERROR: Failed to create audio level timer!", level: .error)
            }
            self.log("=== EXITING MAIN QUEUE ASYNC BLOCK ===", level: .info)
        }
        log("Dispatched to main queue, about to exit function", level: .info)
        log("=== START AUDIO LEVEL STREAMING COMPLETE ===", level: .info)
    }
    
    /// Stops the audio level timer. `forceSynchronousTeardown` is used during deinit
    /// to avoid creating new weak references while the object is being destroyed.
    private func stopAudioLevelStreaming(forceSynchronousTeardown: Bool = false) {
        log("=== STOP AUDIO LEVEL STREAMING ===", level: .info)
        audioLevelQueue.sync {
            isStreamingAudioLevels = false
        }
        
        let tearDownTimer: (DictationManager) -> Void = { manager in
            if let timer = manager.audioLevelTimer {
                timer.invalidate()
                manager.log("Audio level timer invalidated", level: .info)
            } else {
                manager.log("Audio level timer already nil", level: .debug)
            }
            manager.audioLevelTimer = nil
        }
        
        if Thread.isMainThread {
            tearDownTimer(self)
        } else if forceSynchronousTeardown {
            DispatchQueue.main.sync {
                tearDownTimer(self)
            }
        } else {
            DispatchQueue.main.async { [weak self] in
                guard let self = self else { return }
                tearDownTimer(self)
            }
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
        stopAudioLevelStreaming(forceSynchronousTeardown: true)
        audioEngineManager.stopRecording()
        speechRecognizerManager.cancelRecognition()
        eventSink = nil
    }
}

// MARK: - Error Types

enum DictationError: Error {
    case notAuthorized
    case notAvailable
    case audioEngineFailed
    case recognitionFailed
    case initializationFailed
    case invalidArguments(String)
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
        case .invalidArguments:
            return "INVALID_ARGUMENTS"
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
        case .invalidArguments(let message):
            return message
        case .unknown(let error):
            return error.localizedDescription
        }
    }
    
    static func from(_ error: Error) -> DictationError {
        if let dictationError = error as? DictationError {
            return dictationError
        }
        
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

// MARK: - Start Options Parsing

struct DictationStartListeningOptions {
    let audioPreservationConfig: AudioPreservationConfig?
    
    static func from(arguments: Any?) throws -> DictationStartListeningOptions {
        guard let dictionary = arguments as? [String: Any] else {
            return DictationStartListeningOptions(audioPreservationConfig: nil)
        }
        
        let shouldPreserveAudio = dictionary["preserveAudio"] as? Bool ?? false
        guard shouldPreserveAudio else {
            return DictationStartListeningOptions(audioPreservationConfig: nil)
        }
        
        let deleteIfCancelled = dictionary["deleteAudioIfCancelled"] as? Bool ?? true
        let customPath = (dictionary["preservedAudioFilePath"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines)
        let fileURL = try AudioPreservationConfig.resolveFileURL(customPath: customPath)
        let config = AudioPreservationConfig(fileURL: fileURL, deleteIfCancelled: deleteIfCancelled)
        return DictationStartListeningOptions(audioPreservationConfig: config)
    }
}

struct AudioPreservationConfig {
    private static let supportedFileExtensions: Set<String> = ["wav", "caf", "m4a"]
    
    let fileURL: URL
    let deleteIfCancelled: Bool
    
    var audioEngineRequest: AudioPreservationRequest {
        return AudioPreservationRequest(fileURL: fileURL)
    }
    
    static func resolveFileURL(customPath: String?) throws -> URL {
        let targetURL: URL
        if let path = customPath, !path.isEmpty {
            if path.hasPrefix("/") {
                targetURL = URL(fileURLWithPath: path)
            } else {
                targetURL = CanonicalAudioStorage.recordingsDirectory.appendingPathComponent(path)
            }
        } else {
            targetURL = defaultFileURL()
        }
        
        return try sanitizedFileURL(from: targetURL)
    }
    
    private static func sanitizedFileURL(from url: URL) throws -> URL {
        var finalURL = url
        if finalURL.pathExtension.isEmpty {
            finalURL = finalURL.appendingPathExtension("m4a")
        }
        let ext = finalURL.pathExtension.lowercased()
        guard supportedFileExtensions.contains(ext) else {
            throw DictationError.invalidArguments("Unsupported audio file extension \"\(ext)\". Use .wav, .caf, or .m4a.")
        }
        
        let directoryURL = finalURL.deletingLastPathComponent()
        do {
            try FileManager.default.createDirectory(at: directoryURL, withIntermediateDirectories: true)
        } catch {
            throw DictationError.invalidArguments("Failed to prepare directory: \(error.localizedDescription)")
        }

        return finalURL
    }
    
    private static func defaultFileURL() -> URL {
        return CanonicalAudioStorage.makeRecordingURL()
    }
}

extension DictationManager: AudioEngineManagerDelegate {
    func audioEngineManagerDidHitDurationLimit(_ manager: AudioEngineManager) {
        log("Duration limit event received from AudioEngineManager", level: .warning)
        handleDurationLimitReached()
    }
    
    func audioEngineManager(_ manager: AudioEngineManager, didEncounterEncodingError error: Error) {
        let errorInfo = mapEncodingError(error)
        log("Audio encoder failed to start: \(errorInfo.message) [code=\(errorInfo.code)]", level: .error)
        sendError("Audio encoding unavailable: \(errorInfo.message)", code: errorInfo.code)
    }
    
    private func handleDurationLimitReached() {
        guard !isHandlingDurationLimit else {
            return
        }
        isHandlingDurationLimit = true
        
        Task { [weak self] in
            guard let self = self else {
                return
            }
            defer {
                self.isHandlingDurationLimit = false
            }
            
            self.stateQueue.sync {
                guard self.state == .listening else {
                    return
                }
                self.state = .stopping
            }
            
            self.stopAudioLevelStreaming()
            self.audioEngineManager.removeBufferCallback()
            self.speechRecognizerManager.stopRecognition()
            let preservationResult = self.audioEngineManager.stopRecording(deletePreservedAudio: false)
            let config = self.audioPreservationConfig
            self.audioPreservationConfig = nil
            
            await MainActor.run {
                self.stateQueue.sync {
                    self.state = .stopped
                }
                self.sendStatus("duration_limit_reached")
                self.sendError("Recording duration limit reached (60 minutes).", code: "DURATION_LIMIT_REACHED")
                if let config = config, let resultMetadata = preservationResult {
                    self.sendAudioFile(resultMetadata, wasCancelled: false)
                }
            }
        }
    }
    
    private func mapEncodingError(_ error: Error) -> (code: String, message: String) {
        if let encodingError = error as? EncodingError {
            return (encodingError.code, encodingError.localizedDescription)
        }
        
        let nsError = error as NSError
        if nsError.domain == NSCocoaErrorDomain {
            return ("encoding_io_error", nsError.localizedDescription)
        }
        if nsError.domain == AVFoundationErrorDomain {
            return ("encoding_av_error", nsError.localizedDescription)
        }
        return ("encoding_unknown", error.localizedDescription)
    }
}


