import Flutter
import UIKit

@main
@objc class AppDelegate: FlutterAppDelegate {
  // Pre-warmed managers for low-latency recording and recognition
  private var audioEngineManager: AudioEngineManager?
  private var speechRecognizerManager: SpeechRecognizerManager?
  private var dictationManager: DictationManager?
  
  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    GeneratedPluginRegistrant.register(with: self)
    
    // Set up platform channels
    setupPlatformChannels()
    
    // Pre-warm audio engine and speech recognizer at app launch for sub-100ms latency
    prewarmAudioEngine()
    prewarmSpeechRecognizer()
    
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }
  
  private func setupPlatformChannels() {
    guard let controller = window?.rootViewController as? FlutterViewController else {
      print("AppDelegate: Failed to get FlutterViewController")
      return
    }
    
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
    // Initialize audio engine on background queue to avoid blocking app launch
    DispatchQueue.global(qos: .userInitiated).async { [weak self] in
      let manager = AudioEngineManager()
      do {
        try manager.initialize()
        self?.audioEngineManager = manager
        print("AudioEngineManager: Pre-warmed successfully")
        
        // Update dictation manager if it exists
        DispatchQueue.main.async {
          // Dictation manager will use the pre-warmed manager when it's created
          // or we can update it here if needed
        }
      } catch {
        print("AudioEngineManager: Pre-warming failed: \(error)")
        // Non-critical error - audio engine can still be initialized later
      }
    }
  }
  
  private func prewarmSpeechRecognizer() {
    // Initialize speech recognizer on background queue to avoid blocking app launch
    Task {
      let manager = SpeechRecognizerManager()
      do {
        try await manager.initialize()
        await MainActor.run {
          self.speechRecognizerManager = manager
          print("SpeechRecognizerManager: Pre-warmed successfully")
        }
      } catch {
        print("SpeechRecognizerManager: Pre-warming failed: \(error)")
        // Non-critical error - speech recognizer can still be initialized later
      }
    }
  }
}
