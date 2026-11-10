import AVFoundation
import Flutter
import UIKit

@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate {
  private let recognizer = BreezeRecognizer()

  override func applicationDidReceiveMemoryWarning(_ application: UIApplication) {
    super.applicationDidReceiveMemoryWarning(application)
    speechQueue.async { self.recognizer.releaseModel() }
  }

  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  func didInitializeImplicitFlutterEngine(_ engineBridge: FlutterImplicitEngineBridge) {
    GeneratedPluginRegistrant.register(with: engineBridge.pluginRegistry)
    guard let registrar = engineBridge.pluginRegistry.registrar(forPlugin: "BreezeSpeech") else { return }
    let channel = FlutterMethodChannel(name: "anxinban/breeze", binaryMessenger: registrar.messenger())
    channel.setMethodCallHandler { call, reply in
      if call.method == "modelPath" {
        do { reply(try self.recognizer.modelURL().path) }
        catch { reply(FlutterError(code: "storage", message: error.localizedDescription, details: nil)) }
        return
      }
      guard call.method == "transcribe", let path = call.arguments as? String else {
        reply(FlutterMethodNotImplemented)
        return
      }
      let asset = AVURLAsset(url: URL(fileURLWithPath: path))
      asset.loadTracks(withMediaType: .audio) { tracks, error in
        speechQueue.async {
          do {
            if let error { throw error }
            guard let track = tracks?.first else { throw SpeechError("錄音沒有音軌。") }
            let text = try self.recognizer.transcribe(asset, track: track)
            DispatchQueue.main.async { reply(text) }
          } catch {
            DispatchQueue.main.async { reply(FlutterError(code: "speech", message: error.localizedDescription, details: nil)) }
          }
        }
      }
    }
  }
}

private let speechQueue = DispatchQueue(label: "anxinban.breeze", qos: .userInitiated)
