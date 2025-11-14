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
    private var bufferCount: Int = 0  // Track buffer count for logging
    
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
    /// Note: Audio session category is not set here to avoid requiring permissions during init.
    /// Category will be configured when recording starts (after permission is granted).
    /// - Throws: Audio session configuration errors
    func initialize() throws {
        let startTime = CFAbsoluteTimeGetCurrent()
        log("=== INITIALIZE START ===", level: .info)
        logAudioSessionState("initialize-start")
        logAudioEngineState("initialize-start")
        
        guard state == .idle else {
            log("Already initialized, state: \(state)", level: .warning)
            return
        }
        
        // Don't configure audio session category here - it requires microphone permission.
        // We'll configure it in startRecording() after permission is granted.
        // This allows the app to initialize successfully even without permissions.
        
        // Set up audio engine (without preparing - that happens when recording starts)
        let engineStartTime = CFAbsoluteTimeGetCurrent()
        log("Setting up audio engine...", level: .info)
        do {
            try setupAudioEngine()
            let engineDuration = (CFAbsoluteTimeGetCurrent() - engineStartTime) * 1000
            log("Audio engine setup completed in \(String(format: "%.2f", engineDuration))ms", level: .info)
            logEvent("audio_engine_setup", metadata: ["duration_ms": engineDuration])
        } catch {
            let engineDuration = (CFAbsoluteTimeGetCurrent() - engineStartTime) * 1000
            log("Audio engine setup FAILED after \(String(format: "%.2f", engineDuration))ms: \(error)", level: .error)
            throw error
        }
        
        // Register for audio session interruptions
        log("Setting up interruption handling...", level: .info)
        setupInterruptionHandling()
        
        state = .idle
        
        let totalDuration = (CFAbsoluteTimeGetCurrent() - startTime) * 1000
        log("=== INITIALIZE COMPLETE in \(String(format: "%.2f", totalDuration))ms ===", level: .info)
        logAudioSessionState("initialize-complete")
        logAudioEngineState("initialize-complete")
        logEvent("audio_engine_initialize_complete", metadata: ["total_duration_ms": totalDuration])
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
    
    /// Safely prepares an AVAudioEngine.
    /// - Parameter engine: The AVAudioEngine to prepare
    /// - Throws: NSError if preparation fails
    private func safePrepareAudioEngine(_ engine: AVAudioEngine) throws {
        // AVAudioEngine.prepare() doesn't throw in Swift, but we keep this wrapper
        // for consistency with the original implementation and potential future error handling
        engine.prepare()
    }
    
    private func setupAudioEngine() throws {
        // Check if we're running on a simulator
        #if targetEnvironment(simulator)
        // On simulator, audio engine prepare may fail due to hardware limitations
        // We'll defer the prepare until we actually start recording
        // This allows the app to launch successfully on simulator
        print("AudioEngineManager: Running on simulator - deferring audio engine prepare")
        return
        #endif
        
        // Check microphone permission before preparing
        // Note: We can't request permissions synchronously here, so we'll defer
        // the prepare until startRecording() where we can check permissions properly
        // This allows initialization to succeed even if permissions aren't granted yet
        
        // Note: Tap will be installed when recording starts to avoid
        // processing buffers when idle. This is handled in startRecording()
    }
    
    /// Checks if microphone permission is granted.
    /// - Returns: True if granted, false otherwise
    private func checkMicrophonePermission() -> Bool {
        return audioSession.recordPermission == .granted
    }
    
    /// Requests microphone permission asynchronously.
    /// Must be called on the main thread to ensure the permission dialog appears.
    /// iOS requires permission dialogs to be triggered directly from user actions on the main thread.
    /// - Returns: True if granted, false otherwise
    private func requestMicrophonePermission() async -> Bool {
        let requestStartTime = CFAbsoluteTimeGetCurrent()
        let currentStatus = audioSession.recordPermission
        let isMainThread = Thread.isMainThread
        
        log("=== REQUEST MICROPHONE PERMISSION START ===", level: .info)
        log("Current permission status: \(currentStatus)", level: .info)
        log("Current thread: \(isMainThread ? "MAIN" : "BACKGROUND")", level: .info)
        log("Thread name: \(Thread.current.name ?? "unnamed")", level: .info)
        log("Call stack: \(Thread.callStackSymbols.prefix(5).joined(separator: "\n"))", level: .debug)
        logAudioSessionState("permission-request-start")
        
        // If already granted, return immediately
        if currentStatus == .granted {
            log("Permission already granted, returning immediately", level: .info)
            return true
        }
        
        // If denied, return false immediately (can't request again)
        if currentStatus == .denied {
            log("Permission already denied. User must grant in Settings.", level: .warning)
            return false
        }
        
        // For .undetermined status, request permission
        // CRITICAL: Permission request must happen on main thread to preserve user action context.
        // iOS requires permission dialogs to be triggered directly from user actions on main thread.
        log("Permission status is .undetermined, requesting permission...", level: .info)
        
        return await withCheckedContinuation { continuation in
            // Ensure we're on main thread - this is critical for permission dialog to appear
            if Thread.isMainThread {
                self.log("Calling requestRecordPermission directly on MAIN thread", level: .info)
                let callTime = CFAbsoluteTimeGetCurrent()
                self.audioSession.requestRecordPermission { granted in
                    let callbackTime = CFAbsoluteTimeGetCurrent()
                    let callbackDuration = (callbackTime - callTime) * 1000
                    let totalDuration = (callbackTime - requestStartTime) * 1000
                    
                    self.log("Permission request callback received after \(String(format: "%.2f", callbackDuration))ms", level: .info)
                    self.log("Total permission request duration: \(String(format: "%.2f", totalDuration))ms", level: .info)
                    self.log("Permission granted: \(granted)", level: granted ? .info : .warning)
                    
                    // Verify the status matches what we got
                    let verifiedStatus = self.audioSession.recordPermission
                    self.log("Verified permission status after callback: \(verifiedStatus)", level: .info)
                    
                    if verifiedStatus != (granted ? AVAudioSession.RecordPermission.granted : AVAudioSession.RecordPermission.denied) {
                        self.log("WARNING: Permission status mismatch! Callback said \(granted) but status is \(verifiedStatus)", level: .error)
                    }
                    
                    self.logAudioSessionState("permission-request-complete")
                    self.log("=== REQUEST MICROPHONE PERMISSION COMPLETE ===", level: .info)
                    continuation.resume(returning: granted)
                }
            } else {
                // Dispatch to main thread if we're not already there
                self.log("NOT on main thread! Dispatching to main thread (this may break permission dialog)", level: .warning)
                DispatchQueue.main.async {
                    self.log("Now on main thread, calling requestRecordPermission", level: .info)
                    let callTime = CFAbsoluteTimeGetCurrent()
                    self.audioSession.requestRecordPermission { granted in
                        let callbackTime = CFAbsoluteTimeGetCurrent()
                        let callbackDuration = (callbackTime - callTime) * 1000
                        let totalDuration = (callbackTime - requestStartTime) * 1000
                        
                        self.log("Permission request callback received after \(String(format: "%.2f", callbackDuration))ms", level: .info)
                        self.log("Total permission request duration: \(String(format: "%.2f", totalDuration))ms", level: .info)
                        self.log("Permission granted: \(granted)", level: granted ? .info : .warning)
                        
                        // Verify the status matches what we got
                        let verifiedStatus = self.audioSession.recordPermission
                        self.log("Verified permission status after callback: \(verifiedStatus)", level: .info)
                        
                        if verifiedStatus != (granted ? AVAudioSession.RecordPermission.granted : AVAudioSession.RecordPermission.denied) {
                            self.log("WARNING: Permission status mismatch! Callback said \(granted) but status is \(verifiedStatus)", level: .error)
                        }
                        
                        self.logAudioSessionState("permission-request-complete")
                        self.log("=== REQUEST MICROPHONE PERMISSION COMPLETE ===", level: .info)
                        continuation.resume(returning: granted)
                    }
                }
            }
        }
    }
    
    /// Prepares the audio engine, checking permissions first.
    /// - Throws: Audio engine preparation errors or permission errors
    private func prepareAudioEngineWithPermissionCheck() throws {
        // Check microphone permission synchronously first
        let permissionStatus = audioSession.recordPermission
        
        switch permissionStatus {
        case .undetermined:
            // Permission not yet requested - this shouldn't happen if we're calling
            // requestMicrophonePermission() first, but handle it gracefully
            throw NSError(
                domain: "AudioEngineManager",
                code: -1,
                userInfo: [
                    NSLocalizedDescriptionKey: "Microphone permission not yet requested. Please request permission first."
                ]
            )
            
        case .denied:
            throw NSError(
                domain: "AudioEngineManager",
                code: -1,
                userInfo: [
                    NSLocalizedDescriptionKey: "Microphone permission denied. Please grant microphone access in Settings."
                ]
            )
            
        case .granted:
            // Permission granted - proceed with prepare
            break
            
        @unknown default:
            throw NSError(
                domain: "AudioEngineManager",
                code: -1,
                userInfo: [
                    NSLocalizedDescriptionKey: "Unknown microphone permission status."
                ]
            )
        }
        
        // Prepare the audio engine (required before installing tap)
        try safePrepareAudioEngine(audioEngine)
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
    /// Checks and requests microphone permissions if needed.
    /// - Throws: Audio engine start errors or permission errors
    func startRecording() async throws {
        let startTime = CFAbsoluteTimeGetCurrent()
        log("=== START RECORDING START ===", level: .info)
        log("Current state: \(state)", level: .info)
        log("Current thread: \(Thread.isMainThread ? "MAIN" : "BACKGROUND")", level: .info)
        logAudioSessionState("start-recording-start")
        logAudioEngineState("start-recording-start")
        
        guard state != .recording else {
            log("Already recording, returning early", level: .warning)
            return
        }
        
        // Stop and reset audio engine if it's already running
        if audioEngine.isRunning {
            log("Audio engine is already running, stopping it first...", level: .info)
            audioEngine.stop()
            inputNode.removeTap(onBus: 0)
            log("Audio engine stopped", level: .info)
        }
        
        // Deactivate audio session first to ensure clean state
        // This allows us to reconfigure the session properly
        log("Deactivating audio session to ensure clean state...", level: .info)
        do {
            try audioSession.setActive(false, options: .notifyOthersOnDeactivation)
            log("Audio session deactivated successfully", level: .info)
        } catch {
            // Ignore errors when deactivating - session might not be active
            log("Warning: Failed to deactivate audio session (may not be active): \(error)", level: .warning)
        }
        
        // Set audio session category FIRST (before requesting permission)
        // Setting the category doesn't require permission - it just declares intent
        // This is required for the permission dialog to appear properly
        log("Setting audio session category to .record mode .measurement...", level: .info)
        let sessionStartTime = CFAbsoluteTimeGetCurrent()
        do {
            try audioSession.setCategory(.record, mode: .measurement, options: [])
            let sessionDuration = (CFAbsoluteTimeGetCurrent() - sessionStartTime) * 1000
            log("Audio session category set successfully in \(String(format: "%.2f", sessionDuration))ms", level: .info)
            logAudioSessionState("after-category-set")
            logEvent("audio_session_category_set", metadata: ["duration_ms": sessionDuration])
        } catch {
            let sessionDuration = (CFAbsoluteTimeGetCurrent() - sessionStartTime) * 1000
            log("FAILED to set audio session category after \(String(format: "%.2f", sessionDuration))ms: \(error)", level: .error)
            logAudioSessionState("after-category-set-failed")
            throw NSError(
                domain: "AudioEngineManager",
                code: -1,
                userInfo: [
                    NSLocalizedDescriptionKey: "Failed to set audio session category: \(error.localizedDescription)"
                ]
            )
        }
        
        // Check and request microphone permission if needed
        // Must be done AFTER setting category so iOS knows why we need permission
        log("Checking microphone permission...", level: .info)
        let permissionStartTime = CFAbsoluteTimeGetCurrent()
        let permissionStatus = audioSession.recordPermission
        log("Current permission status: \(permissionStatus)", level: .info)
        log("Current thread: \(Thread.isMainThread ? "MAIN" : "BACKGROUND")", level: .info)
        
        if permissionStatus != .granted {
            log("Permission not granted, requesting permission...", level: .info)
            // Request permission - CRITICAL: Must be called directly on main thread to preserve user action context
            // iOS requires permission dialogs to be triggered directly from user actions on the main thread.
            // The Task wrapper breaks this context chain, so we call directly since we ensure main thread upstream.
            // Verify we're on main thread - if not, this is a programming error
            guard Thread.isMainThread else {
                log("ERROR: Not on main thread! This will prevent permission dialog from appearing.", level: .error)
                log("Thread: \(Thread.current.name ?? "unnamed")", level: .error)
                throw NSError(
                    domain: "AudioEngineManager",
                    code: -1,
                    userInfo: [
                        NSLocalizedDescriptionKey: "Permission request must be called on main thread. This is a programming error."
                    ]
                )
            }
            let granted = await requestMicrophonePermission()
            
            let permissionDuration = (CFAbsoluteTimeGetCurrent() - permissionStartTime) * 1000
            log("Permission request completed in \(String(format: "%.2f", permissionDuration))ms, granted: \(granted)", level: .info)
            logEvent("microphone_permission_request", metadata: ["duration_ms": permissionDuration, "granted": granted, "previous_status": "\(permissionStatus)"])
            
            // Verify permission was actually granted
            let finalPermissionStatus = audioSession.recordPermission
            log("Permission status after request: \(finalPermissionStatus)", level: .info)
            logAudioSessionState("after-permission-request")
            
            guard finalPermissionStatus == .granted else {
                let errorMessage: String
                if finalPermissionStatus == .denied {
                    errorMessage = "Microphone permission denied. Please grant microphone access in Settings > Privacy & Security > Microphone to use dictation."
                } else {
                    errorMessage = "Microphone permission not granted. Current status: \(finalPermissionStatus). Please grant microphone access to use dictation."
                }
                log("Permission not granted after request. Status: \(finalPermissionStatus)", level: .error)
                throw NSError(
                    domain: "AudioEngineManager",
                    code: -1,
                    userInfo: [
                        NSLocalizedDescriptionKey: errorMessage
                    ]
                )
            }
            log("Permission granted successfully!", level: .info)
        } else {
            log("Permission already granted, skipping request", level: .info)
        }
        
        // Complete audio session configuration (now that permission is granted)
        log("Configuring audio session buffer duration and sample rate...", level: .info)
        // Buffer duration: 5ms for minimal latency
        do {
            try audioSession.setPreferredIOBufferDuration(0.005)
            log("Buffer duration set to 5ms", level: .info)
        } catch {
            log("Failed to set buffer duration: \(error)", level: .error)
            throw NSError(
                domain: "AudioEngineManager",
                code: -1,
                userInfo: [
                    NSLocalizedDescriptionKey: "Failed to set buffer duration: \(error.localizedDescription)"
                ]
            )
        }
        
        // Sample rate: 16kHz is sufficient for speech
        do {
            try audioSession.setPreferredSampleRate(16000)
            log("Sample rate set to 16kHz", level: .info)
        } catch {
            log("Failed to set sample rate: \(error)", level: .error)
            throw NSError(
                domain: "AudioEngineManager",
                code: -1,
                userInfo: [
                    NSLocalizedDescriptionKey: "Failed to set sample rate: \(error.localizedDescription)"
                ]
            )
        }
        
        // Activate session - this is critical and must succeed
        // Verify permission is granted before activation
        log("Preparing to activate audio session...", level: .info)
        let preActivationPermission = audioSession.recordPermission
        log("Pre-activation permission check: \(preActivationPermission)", level: .info)
        guard preActivationPermission == .granted else {
            log("ERROR: Cannot activate audio session - permission not granted (status: \(preActivationPermission))", level: .error)
            logAudioSessionState("pre-activation-failed")
            throw NSError(
                domain: "AudioEngineManager",
                code: -1,
                userInfo: [
                    NSLocalizedDescriptionKey: "Cannot activate audio session: microphone permission not granted (status: \(preActivationPermission))"
                ]
            )
        }
        
        log("Activating audio session...", level: .info)
        let activationStartTime = CFAbsoluteTimeGetCurrent()
        do {
            try audioSession.setActive(true)
            let activationDuration = (CFAbsoluteTimeGetCurrent() - activationStartTime) * 1000
            log("Audio session activated successfully in \(String(format: "%.2f", activationDuration))ms", level: .info)
            logAudioSessionState("after-activation")
        } catch {
            let activationDuration = (CFAbsoluteTimeGetCurrent() - activationStartTime) * 1000
            log("FAILED to activate audio session after \(String(format: "%.2f", activationDuration))ms: \(error)", level: .error)
            log("Error type: \(type(of: error))", level: .error)
            log("Error domain: \((error as NSError).domain)", level: .error)
            log("Error code: \((error as NSError).code)", level: .error)
            log("Error userInfo: \((error as NSError).userInfo)", level: .error)
            logAudioSessionState("activation-failed")
            
            // Check if another app is using audio
            if audioSession.isOtherAudioPlaying {
                log("Another app is using audio", level: .error)
                throw NSError(
                    domain: "AudioEngineManager",
                    code: -1,
                    userInfo: [
                        NSLocalizedDescriptionKey: "Cannot activate audio session: another app is using the microphone. Please close other audio apps and try again."
                    ]
                )
            }
            
            throw NSError(
                domain: "AudioEngineManager",
                code: -1,
                userInfo: [
                    NSLocalizedDescriptionKey: "Failed to activate audio session: \(error.localizedDescription). Please ensure microphone permission is granted and no other app is using the microphone."
                ]
            )
        }
        
        let configDuration = (CFAbsoluteTimeGetCurrent() - sessionStartTime) * 1000
        log("Audio session configuration completed in \(String(format: "%.2f", configDuration))ms", level: .info)
        logEvent("audio_session_config_complete", metadata: ["duration_ms": configDuration])
        
        // Prepare audio engine (required before installing tap)
        // This must be done after audio session is activated and permission is granted
        log("Preparing audio engine...", level: .info)
        let prepareStartTime = CFAbsoluteTimeGetCurrent()
        do {
            try prepareAudioEngineWithPermissionCheck()
            let prepareDuration = (CFAbsoluteTimeGetCurrent() - prepareStartTime) * 1000
            log("Audio engine prepared successfully in \(String(format: "%.2f", prepareDuration))ms", level: .info)
            logAudioEngineState("after-prepare")
        } catch {
            let prepareDuration = (CFAbsoluteTimeGetCurrent() - prepareStartTime) * 1000
            log("FAILED to prepare audio engine after \(String(format: "%.2f", prepareDuration))ms: \(error)", level: .error)
            log("Error type: \(type(of: error))", level: .error)
            log("Error domain: \((error as NSError).domain)", level: .error)
            log("Error code: \((error as NSError).code)", level: .error)
            logAudioEngineState("prepare-failed")
            throw NSError(
                domain: "AudioEngineManager",
                code: -1,
                userInfo: [
                    NSLocalizedDescriptionKey: "Failed to prepare audio engine: \(error.localizedDescription)"
                ]
            )
        }
        
        // Install tap (must be done after engine is prepared but before it starts)
        log("Installing audio tap...", level: .info)
        let tapStartTime = CFAbsoluteTimeGetCurrent()
        installAudioTap()
        let tapDuration = (CFAbsoluteTimeGetCurrent() - tapStartTime) * 1000
        log("Audio tap installed in \(String(format: "%.2f", tapDuration))ms", level: .info)
        logEvent("audio_tap_install", metadata: ["duration_ms": tapDuration])
        
        // Verify audio session state before starting engine
        log("Performing pre-start verification...", level: .info)
        let sessionIsActive = !audioSession.isOtherAudioPlaying
        let permissionIsGranted = audioSession.recordPermission == .granted
        let categoryIsCorrect = audioSession.category == .record
        let engineIsPrepared = audioEngine.inputNode.inputFormat(forBus: 0).sampleRate > 0
        
        log("Pre-start verification results:", level: .info)
        log("  - Permission granted: \(permissionIsGranted)", level: .info)
        log("  - Session active: \(sessionIsActive)", level: .info)
        log("  - Category correct: \(categoryIsCorrect)", level: .info)
        log("  - Engine prepared: \(engineIsPrepared)", level: .info)
        log("  - Engine running: \(audioEngine.isRunning)", level: .info)
        logAudioSessionState("pre-start")
        logAudioEngineState("pre-start")
        
        guard permissionIsGranted else {
            log("ERROR: Permission not granted in pre-start check", level: .error)
            throw NSError(
                domain: "AudioEngineManager",
                code: -1,
                userInfo: [
                    NSLocalizedDescriptionKey: "Cannot start audio engine: microphone permission not granted (status: \(audioSession.recordPermission))"
                ]
            )
        }
        
        guard sessionIsActive else {
            log("ERROR: Session not active in pre-start check", level: .error)
            throw NSError(
                domain: "AudioEngineManager",
                code: -1,
                userInfo: [
                    NSLocalizedDescriptionKey: "Cannot start audio engine: audio session is not active. Another app may be using the microphone."
                ]
            )
        }
        
        // Start the audio engine
        log("Starting audio engine...", level: .info)
        let engineStartTime = CFAbsoluteTimeGetCurrent()
        do {
            try audioEngine.start()
            let engineDuration = (CFAbsoluteTimeGetCurrent() - engineStartTime) * 1000
            let totalDuration = (CFAbsoluteTimeGetCurrent() - startTime) * 1000
            log("Audio engine started successfully in \(String(format: "%.2f", engineDuration))ms", level: .info)
            log("Total startRecording duration: \(String(format: "%.2f", totalDuration))ms", level: .info)
            log("Audio engine is running: \(audioEngine.isRunning)", level: .info)
            logAudioEngineState("after-start")
            logAudioSessionState("after-start")
            logEvent("audio_engine_start", metadata: ["duration_ms": engineDuration])
        } catch {
            let engineDuration = (CFAbsoluteTimeGetCurrent() - engineStartTime) * 1000
            let totalDuration = (CFAbsoluteTimeGetCurrent() - startTime) * 1000
            log("ERROR: Audio engine start FAILED after \(String(format: "%.2f", engineDuration))ms", level: .error)
            log("Total startRecording duration before failure: \(String(format: "%.2f", totalDuration))ms", level: .error)
            log("Error: \(error)", level: .error)
            log("Error type: \(type(of: error))", level: .error)
            log("Error domain: \((error as NSError).domain)", level: .error)
            log("Error code: \((error as NSError).code)", level: .error)
            log("Error userInfo: \((error as NSError).userInfo)", level: .error)
            log("Error localizedDescription: \(error.localizedDescription)", level: .error)
            log("Permission status: \(audioSession.recordPermission)", level: .error)
            log("Audio session category: \(audioSession.category.rawValue)", level: .error)
            log("Audio session is active: \(!audioSession.isOtherAudioPlaying)", level: .error)
            log("Audio engine is running: \(audioEngine.isRunning)", level: .error)
            log("Audio engine is prepared: \(audioEngine.inputNode.inputFormat(forBus: 0).sampleRate > 0)", level: .error)
            logAudioSessionState("start-failed")
            logAudioEngineState("start-failed")
            
            logEvent("audio_engine_start_failed", metadata: [
                "duration_ms": engineDuration,
                "error": error.localizedDescription,
                "permission": "\(audioSession.recordPermission)",
                "category": audioSession.category.rawValue,
                "session_active": !audioSession.isOtherAudioPlaying
            ])
            
            // Provide more detailed error message based on the error
            var errorMessage = "Audio engine failed to start: \(error.localizedDescription)"
            
            // Add specific guidance based on common failure scenarios
            if !permissionIsGranted {
                errorMessage += " Microphone permission is not granted. Please grant microphone access in Settings."
            } else if !sessionIsActive {
                errorMessage += " Audio session is not active. Another app may be using the microphone."
            } else {
                errorMessage += " Please ensure microphone permission is granted and no other app is using the microphone."
            }
            
            log("=== START RECORDING FAILED ===", level: .error)
            throw NSError(
                domain: "AudioEngineManager",
                code: -1,
                userInfo: [
                    NSLocalizedDescriptionKey: errorMessage
                ]
            )
        }
        
        state = .recording
        
        let totalDuration = (CFAbsoluteTimeGetCurrent() - startTime) * 1000
        log("=== START RECORDING COMPLETE in \(String(format: "%.2f", totalDuration))ms ===", level: .info)
        logEvent("start_recording_complete", metadata: ["total_duration_ms": totalDuration])
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
        // Log first few buffers to confirm tap is working
        bufferCount += 1
        if bufferCount <= 5 {
            log("=== AUDIO TAP CALLBACK INVOKED (buffer #\(bufferCount)) ===", level: .info)
            log("Buffer frameLength: \(buffer.frameLength)", level: .info)
            log("Buffer sampleRate: \(buffer.format.sampleRate)", level: .info)
            log("Current state: \(state)", level: .info)
        }
        
        // Only process buffers when actively recording
        guard state == .recording else {
            if bufferCount <= 5 {
                log("Skipping buffer processing - state is \(state), not .recording", level: .warning)
            }
            return
        }
        
        // Calculate audio level for waveform visualization
        let newLevel = calculateAudioLevel(from: buffer)
        
        if bufferCount <= 5 {
            log("Calculated audio level: \(newLevel)", level: .info)
        }
        
        // Smooth the level to avoid jittery waveform
        audioLevelQueue.sync {
            self.currentAudioLevel = self.currentAudioLevel * (1.0 - self.levelSmoothingFactor) +
                                   newLevel * self.levelSmoothingFactor
        }
        
        // Call buffer callback if set
        if let callback = bufferCallback {
            if bufferCount <= 5 {
                log("Calling buffer callback...", level: .info)
            }
            callback(buffer)
            if bufferCount <= 5 {
                log("Buffer callback completed", level: .info)
            }
            // Log occasionally to confirm buffers are being processed
            if Int.random(in: 0..<1000) == 0 {
                log("Processed audio buffer: frameLength=\(buffer.frameLength), level=\(newLevel)", level: .debug)
            }
        } else {
            if bufferCount <= 5 {
                log("ERROR: Buffer callback is nil - buffers are not being forwarded!", level: .error)
            } else if Int.random(in: 0..<1000) == 0 {
                log("Buffer callback is nil - buffers are not being forwarded", level: .warning)
            }
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
        log("setBufferCallback called", level: .info)
        bufferCallback = callback
        log("bufferCallback set successfully, is nil: \(bufferCallback == nil)", level: .info)
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
    
    // MARK: - Logging
    
    /// Comprehensive logging function that ensures logs are visible in both Xcode and Flutter console.
    /// Uses print() which is captured by both Xcode console and Flutter's stdout.
    private func log(_ message: String, level: LogLevel = .info, file: String = #file, function: String = #function, line: Int = #line) {
        let fileName = (file as NSString).lastPathComponent
        let timestamp = String(format: "%.3f", CFAbsoluteTimeGetCurrent())
        let threadName = Thread.isMainThread ? "MAIN" : "BG"
        let logMessage = "[\(timestamp)] [AudioEngineManager] [\(level.rawValue)] [\(threadName)] \(fileName):\(line) \(function) - \(message)"
        print(logMessage)
        
        // Also log to system console for Xcode
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
    
    /// Logs detailed audio session state for debugging.
    private func logAudioSessionState(_ context: String) {
        let permission = audioSession.recordPermission
        let category = audioSession.category
        let mode = audioSession.mode
        let isActive = !audioSession.isOtherAudioPlaying
        let sampleRate = audioSession.sampleRate
        let bufferDuration = audioSession.ioBufferDuration
        let inputAvailable = audioSession.isInputAvailable
        
        log("Audio Session State [\(context)]:", level: .debug)
        log("  - Permission: \(permission)", level: .debug)
        log("  - Category: \(category.rawValue)", level: .debug)
        log("  - Mode: \(mode.rawValue)", level: .debug)
        log("  - Active: \(isActive)", level: .debug)
        log("  - Sample Rate: \(sampleRate) Hz", level: .debug)
        log("  - Buffer Duration: \(bufferDuration * 1000)ms", level: .debug)
        log("  - Input Available: \(inputAvailable)", level: .debug)
        log("  - Other Audio Playing: \(audioSession.isOtherAudioPlaying)", level: .debug)
    }
    
    /// Logs detailed audio engine state for debugging.
    private func logAudioEngineState(_ context: String) {
        let isRunning = audioEngine.isRunning
        let isPrepared = audioEngine.inputNode.inputFormat(forBus: 0).sampleRate > 0
        let inputFormat = audioEngine.inputNode.inputFormat(forBus: 0)
        
        log("Audio Engine State [\(context)]:", level: .debug)
        log("  - Running: \(isRunning)", level: .debug)
        log("  - Prepared: \(isPrepared)", level: .debug)
        log("  - Input Format Sample Rate: \(inputFormat.sampleRate) Hz", level: .debug)
        log("  - Input Format Channels: \(inputFormat.channelCount)", level: .debug)
        log("  - Manager State: \(state)", level: .debug)
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

