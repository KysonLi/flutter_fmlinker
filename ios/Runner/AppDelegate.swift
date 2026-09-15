import Flutter
import UIKit
import Network

@main
@objc class AppDelegate: FlutterAppDelegate {
  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    GeneratedPluginRegistrant.register(with: self)

    if let controller = window?.rootViewController as? FlutterViewController {
      let channel = FlutterMethodChannel(
        name: "fmlink/network_info",
        binaryMessenger: controller.binaryMessenger
      )
      channel.setMethodCallHandler { (call, result) in
        if call.method == "getNetworkType" {
          self.getNetworkType { type in
            result(type)
          }
        } else {
          result(FlutterMethodNotImplemented)
        }
      }
    }

    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  /// 获取当前网络类型：wifi / cellular / none / unknown（异步回调）
  private func getNetworkType(completion: @escaping (String) -> Void) {
    let monitor = NWPathMonitor()
    monitor.pathUpdateHandler = { path in
      var type = "unknown"
      if path.status == .satisfied {
        if path.usesInterfaceType(.wifi) {
          type = "wifi"
        } else if path.usesInterfaceType(.cellular) {
          type = "cellular"
        }
      } else {
        type = "none"
      }
      monitor.cancel()
      completion(type)
    }
    monitor.start(queue: DispatchQueue(label: "network_monitor"))
  }
}
