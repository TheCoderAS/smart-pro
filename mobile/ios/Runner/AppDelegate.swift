import Flutter
import NetworkExtension
import SystemConfiguration.CaptiveNetwork
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

    // Wi-Fi join/read channel — counterpart of the Android
    // implementation in MainActivity.kt. Requires the Hotspot
    // Configuration entitlement (see mobile/RELEASE.md).
    let messenger = engineBridge.applicationRegistrar.messenger()
    let channel = FlutterMethodChannel(
      name: "in.unisync.unisync/wifi",
      binaryMessenger: messenger
    )
    channel.setMethodCallHandler { call, result in
      switch call.method {
      case "join":
        guard
          let args = call.arguments as? [String: Any],
          let ssid = args["ssid"] as? String,
          let password = args["password"] as? String
        else {
          result(FlutterError(code: "args", message: "ssid and password required", details: nil))
          return
        }
        let config = NEHotspotConfiguration(ssid: ssid, passphrase: password, isWEP: false)
        config.joinOnce = false
        NEHotspotConfigurationManager.shared.apply(config) { error in
          if let error = error as NSError? {
            // "already associated" is success for our purposes.
            if error.domain == NEHotspotConfigurationErrorDomain,
               error.code == NEHotspotConfigurationError.alreadyAssociated.rawValue {
              result(true)
            } else {
              result(false)
            }
          } else {
            result(true)
          }
        }
      case "currentSsid":
        NEHotspotNetwork.fetchCurrent { network in
          result(network?.ssid)
        }
      case "release":
        // No process-level binding on iOS; nothing to undo.
        result(true)
      default:
        result(FlutterMethodNotImplemented)
      }
    }
  }
}
