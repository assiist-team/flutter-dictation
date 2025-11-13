import Flutter
import UIKit

@main
@objc class AppDelegate: FlutterAppDelegate {
  // Pre-warmed audio engine manager for low-latency recording
  private var audioEngineManager: AudioEngineManager?
  
  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    GeneratedPluginRegistrant.register(with: self)
    
    // Pre-warm audio engine at app launch for sub-100ms latency
    prewarmAudioEngine()
    
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
}
