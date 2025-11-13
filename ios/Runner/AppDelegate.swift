import Flutter
import UIKit

@main
@objc class AppDelegate: FlutterAppDelegate {
  // Pre-warmed managers for low-latency recording and recognition
  private var audioEngineManager: AudioEngineManager?
  private var speechRecognizerManager: SpeechRecognizerManager?
  
  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    GeneratedPluginRegistrant.register(with: self)
    
    // Pre-warm audio engine and speech recognizer at app launch for sub-100ms latency
    prewarmAudioEngine()
    prewarmSpeechRecognizer()
    
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }
  
  private func prewarmAudioEngine() {
    // Initialize audio engine on background queue to avoid blocking app launch
    DispatchQueue.global(qos: .userInitiated).async { [weak self] in
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
    // Initialize speech recognizer on background queue to avoid blocking app launch
    Task {
      let manager = SpeechRecognizerManager()
      do {
        try await manager.initialize()
        await MainActor.run {
          self.speechRecognizerManager = manager
        }
        print("SpeechRecognizerManager: Pre-warmed successfully")
      } catch {
        print("SpeechRecognizerManager: Pre-warming failed: \(error)")
        // Non-critical error - speech recognizer can still be initialized later
      }
    }
  }
}
