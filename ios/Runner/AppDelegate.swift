import Flutter
import UIKit

@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate {
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
      guard call.method == "transcribe", let path = call.arguments as? String else {
        reply(FlutterMethodNotImplemented)
        return
      }
      speechQueue.async {
        do {
          let text = try transcribeRecording(at: URL(fileURLWithPath: path))
          DispatchQueue.main.async { reply(text) }
        } catch {
          DispatchQueue.main.async { reply(FlutterError(code: "speech", message: error.localizedDescription, details: nil)) }
        }
      }
    }
  }
}

private let speechQueue = DispatchQueue(label: "anxinban.breeze", qos: .userInitiated)
