import Cocoa
import FlutterMacOS
import ServiceManagement

class MainFlutterWindow: NSWindow {
  override func awakeFromNib() {
    let flutterViewController = FlutterViewController()
    let windowFrame = self.frame
    self.contentViewController = flutterViewController
    self.setFrame(windowFrame, display: true)

    RegisterGeneratedPlugins(registry: flutterViewController)

    let loginItemChannel = FlutterMethodChannel(
      name: "dot/login_item",
      binaryMessenger: flutterViewController.engine.binaryMessenger
    )
    loginItemChannel.setMethodCallHandler { call, result in
      guard #available(macOS 13.0, *) else {
        result(false)
        return
      }

      switch call.method {
      case "isSupported":
        result(true)
      case "isEnabled":
        result(SMAppService.mainApp.status == .enabled)
      case "setEnabled":
        guard let enabled = call.arguments as? Bool else {
          result(false)
          return
        }
        do {
          if enabled {
            try SMAppService.mainApp.register()
          } else {
            try SMAppService.mainApp.unregister()
          }
          result(true)
        } catch {
          result(false)
        }
      default:
        result(FlutterMethodNotImplemented)
      }
    }

    super.awakeFromNib()
  }
}
