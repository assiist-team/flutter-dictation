import Flutter
import UIKit

@main
@objc class AppDelegate: FlutterAppDelegate {
  // Pre-warmed managers for low-latency recording and recognition
  private var audioEngineManager: AudioEngineManager?
  private var speechRecognizerManager: SpeechRecognizerManager?
  private var dictationManager: DictationManager?
  private var platformChannelSetupRetries = 0
  private let maxPlatformChannelSetupRetries = 10
  
  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    let result = super.application(application, didFinishLaunchingWithOptions: launchOptions)
    
    GeneratedPluginRegistrant.register(with: self)
    
    // Set up platform channels after super call ensures window is initialized
    // Use async dispatch to ensure FlutterViewController is ready
    DispatchQueue.main.async { [weak self] in
      self?.setupPlatformChannels()
    }
    
    // Defer pre-warming until app becomes active to avoid crashes during launch
    // Pre-warming will happen in applicationDidBecomeActive
    
    return result
  }
  
  override func applicationDidBecomeActive(_ application: UIApplication) {
    super.applicationDidBecomeActive(application)
    
    // Ensure platform channels are set up when app becomes active
    // This is a fallback in case setup failed during launch
    if dictationManager == nil {
      setupPlatformChannels()
    }
    
    // Pre-warm audio engine and speech recognizer after app is fully active
    // This avoids crashes from requesting permissions too early
    if audioEngineManager == nil {
      prewarmAudioEngine()
    }
    if speechRecognizerManager == nil {
      prewarmSpeechRecognizer()
    }
  }
  
  private func setupPlatformChannels() {
    // Guard against setting up channels multiple times
    guard dictationManager == nil else {
      return
    }
    
    // Try to get FlutterViewController from window
    guard let controller = window?.rootViewController as? FlutterViewController else {
      // Retry mechanism with exponential backoff
      platformChannelSetupRetries += 1
      if platformChannelSetupRetries < maxPlatformChannelSetupRetries {
        let delay = min(0.1 * Double(platformChannelSetupRetries), 1.0) // Max 1 second delay
        print("AppDelegate: FlutterViewController not ready - retrying (\(platformChannelSetupRetries)/\(maxPlatformChannelSetupRetries)) in \(delay)s")
        DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
          self?.setupPlatformChannels()
        }
      } else {
        print("AppDelegate: ERROR - Failed to set up platform channels after \(maxPlatformChannelSetupRetries) retries")
        print("AppDelegate: Window: \(String(describing: self.window))")
        print("AppDelegate: RootViewController: \(String(describing: self.window?.rootViewController))")
        print("AppDelegate: RootViewController type: \(type(of: self.window?.rootViewController))")
      }
      return
    }
    
    setupPlatformChannels(with: controller)
  }
  
  private func setupPlatformChannels(with controller: FlutterViewController) {
    // Reset retry counter on success
    platformChannelSetupRetries = 0
    
    // Create method channel
    let methodChannel = FlutterMethodChannel(
      name: "com.flutter_dictation/methods",
      binaryMessenger: controller.binaryMessenger
    )
    
    // Create event channel
    let eventChannel = FlutterEventChannel(
      name: "com.flutter_dictation/events",
      binaryMessenger: controller.binaryMessenger
    )
    
    // Create dictation manager (will use pre-warmed managers if available)
    let dictationManager = DictationManager(
      methodChannel: methodChannel,
      eventChannel: eventChannel,
      audioEngineManager: audioEngineManager,
      speechRecognizerManager: speechRecognizerManager
    )
    
    self.dictationManager = dictationManager
    
    // Set method call handler
    methodChannel.setMethodCallHandler { [weak self] call, result in
      self?.dictationManager?.handleMethodCall(call, result: result)
    }
    
    print("AppDelegate: Platform channels set up successfully")
  }
  
  private func prewarmAudioEngine() {
    // AVAudioEngine operations must be performed on the main thread
    // Use async dispatch to avoid blocking app launch
    DispatchQueue.main.async { [weak self] in
      let manager = AudioEngineManager()
      do {
        try manager.initialize()
        self?.audioEngineManager = manager
        print("AudioEngineManager: Pre-warmed successfully")
        
        // Update dictation manager if it exists
        // Dictation manager will use the pre-warmed manager when it's created
        // or we can update it here if needed
      } catch {
        print("AudioEngineManager: Pre-warming failed: \(error)")
        // Non-critical error - audio engine can still be initialized later
      }
    }
  }
  
  private func prewarmSpeechRecognizer() {
    // Initialize speech recognizer asynchronously to avoid blocking
    // Defer authorization request until app is fully active
    Task { [weak self] in
      guard let self = self else { return }
      
      // Add a small delay to ensure app is fully initialized
      try? await Task.sleep(nanoseconds: 500_000_000) // 0.5 seconds
      
      let manager = SpeechRecognizerManager()
      do {
        try await manager.initialize()
        await MainActor.run {
          self.speechRecognizerManager = manager
          print("SpeechRecognizerManager: Pre-warmed successfully")
        }
      } catch {
        print("SpeechRecognizerManager: Pre-warming failed: \(error.localizedDescription)")
        // Non-critical error - speech recognizer can still be initialized later
        // Don't crash the app if pre-warming fails
      }
    }
  }
}
