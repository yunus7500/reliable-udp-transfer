import Flutter
import UIKit
import UniformTypeIdentifiers

@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate, UIDocumentPickerDelegate {
  private var pickResult: FlutterResult?
  private var bgTask: UIBackgroundTaskIdentifier = .invalid

  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  func didInitializeImplicitFlutterEngine(_ engineBridge: FlutterImplicitEngineBridge) {
    GeneratedPluginRegistrant.register(with: engineBridge.pluginRegistry)

    let channel = FlutterMethodChannel(
      name: "udp_transfer/platform",
      binaryMessenger: engineBridge.applicationRegistrar.messenger()
    )

    channel.setMethodCallHandler { [weak self] call, result in
      guard let self = self else { return }
      switch call.method {
      case "pickFile":
        self.openDocumentPicker(result: result)
      case "getSaveDir":
        let dir = NSSearchPathForDirectoriesInDomains(.documentDirectory, .userDomainMask, true).first
        result(dir)
      case "shareFile":
        let args = call.arguments as? [String: Any]
        if let path = args?["path"] as? String, let root = self.activeRootController() {
          let fileUrl = URL(fileURLWithPath: path)
          let vc = UIActivityViewController(activityItems: [fileUrl], applicationActivities: nil)
          vc.popoverPresentationController?.sourceView = root.view
          root.present(vc, animated: true)
        }
        result(nil)
      case "setBackgroundActive":
        let args = call.arguments as? [String: Any]
        let active = args?["active"] as? Bool ?? false
        self.setBackground(active: active)
        result(nil)
      default:
        result(FlutterMethodNotImplemented)
      }
    }
  }

  private func activeRootController() -> UIViewController? {
    for scene in UIApplication.shared.connectedScenes {
      if let windowScene = scene as? UIWindowScene {
        for window in windowScene.windows where window.isKeyWindow {
          return window.rootViewController
        }
        return windowScene.windows.first?.rootViewController
      }
    }
    return nil
  }

  private func openDocumentPicker(result: @escaping FlutterResult) {
    guard let root = activeRootController() else {
      result(nil)
      return
    }
    pickResult = result
    let picker = UIDocumentPickerViewController(forOpeningContentTypes: [.item], asCopy: true)
    picker.delegate = self
    picker.allowsMultipleSelection = false
    root.present(picker, animated: true)
  }

  func documentPicker(_ controller: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]) {
    guard let url = urls.first else {
      pickResult?(nil)
      pickResult = nil
      return
    }
    pickResult?(["path": url.path, "name": url.lastPathComponent])
    pickResult = nil
  }

  func documentPickerWasCancelled(_ controller: UIDocumentPickerViewController) {
    pickResult?(nil)
    pickResult = nil
  }

  private func setBackground(active: Bool) {
    UIApplication.shared.isIdleTimerDisabled = active
    if active {
      if bgTask == .invalid {
        bgTask = UIApplication.shared.beginBackgroundTask(withName: "udp_transfer") { [weak self] in
          if let id = self?.bgTask, id != .invalid {
            UIApplication.shared.endBackgroundTask(id)
            self?.bgTask = .invalid
          }
        }
      }
    } else if bgTask != .invalid {
      UIApplication.shared.endBackgroundTask(bgTask)
      bgTask = .invalid
    }
  }
}
