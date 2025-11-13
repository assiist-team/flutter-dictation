import Flutter
import UIKit

public class FlutterDictationPlugin: NSObject, FlutterPlugin {
  // Pre-warmed managers for low-latency recording and recognition
  private var audioEngineManager: AudioEngineManager?
  private var speechRecognizerManager: SpeechRecognizerManager?
  private var dictationManager: DictationManager?
  private var platformChannelSetupRetries = 0
  private let maxPlatformChannelSetupRetries = 10
  
  public static func register(with registrar: FlutterPluginRegistrar) {
    let instance = FlutterDictationPlugin()
    
    // Create method channel
    let methodChannel = FlutterMethodChannel(
      name: "com.flutter_dictation/methods",
      binaryMessenger: registrar.messenger()
    )
    
    // Create event channel
    let eventChannel = FlutterEventChannel(
      name: "com.flutter_dictation/events",
      binaryMessenger: registrar.messenger()
    )
    
    // Set up platform channels
    instance.setupPlatformChannels(methodChannel: methodChannel, eventChannel: eventChannel)
    
    // Register method channel handler
    registrar.addMethodCallDelegate(instance, channel: methodChannel)
    
    // Pre-warm managers after a delay to avoid crashes during launch
    DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
      instance.prewarmManagers()
    }
  }
  
  private func setupPlatformChannels(methodChannel: FlutterMethodChannel, eventChannel: FlutterEventChannel) {
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
    
    print("FlutterDictationPlugin: Platform channels set up successfully")
  }
  
  public func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    dictationManager?.handleMethodCall(call, result: result)
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
  
  private func prewarmManagers() {
    if audioEngineManager == nil {
      prewarmAudioEngine()
    }
    if speechRecognizerManager == nil {
      prewarmSpeechRecognizer()
    }
  }
}

