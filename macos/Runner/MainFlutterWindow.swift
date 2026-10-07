import Cocoa
import FlutterMacOS
import ServiceManagement
import ApplicationServices
import CoreGraphics

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

    let input = DotInputController()
    let inputChannel = FlutterMethodChannel(
      name: "dot/input",
      binaryMessenger: flutterViewController.engine.binaryMessenger
    )
    inputChannel.setMethodCallHandler { call, result in
      input.handle(call, result: result)
    }

    let migrationChannel = FlutterMethodChannel(
      name: "dot/migration",
      binaryMessenger: flutterViewController.engine.binaryMessenger
    )
    migrationChannel.setMethodCallHandler { call, result in
      guard call.method == "reloadPreferences" else {
        result(FlutterMethodNotImplemented)
        return
      }
      result(DotPreferenceMigration.reload())
    }

    super.awakeFromNib()
  }
}

/// Main-thread input posting. Every execution rechecks Accessibility trust.
/// Keep this in the Runner's existing source file to avoid target-registration drift.
private final class DotInputController {
  private var dragDown = false
  private let maxDelta = 2000.0

  func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    switch call.method {
    case "isTrusted":
      result(AXIsProcessTrusted())
      return
    case "requestTrust":
      let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true]
      result(AXIsProcessTrustedWithOptions(options as CFDictionary))
      return
    case "openAccessibilitySettings":
      guard let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") else {
        result(false)
        return
      }
      result(NSWorkspace.shared.open(url))
      return
    case "reset":
      result(releaseDrag())
      return
    default:
      break
    }
    guard AXIsProcessTrusted(), let args = call.arguments as? [String: Any] else {
      result(false)
      return
    }
    switch call.method {
    case "move":
      guard let dx = delta(args["dx"]), let dy = delta(args["dy"]),
            let location = CGEvent(source: nil)?.location else {
        result(false)
        return
      }
      let point = clampedPoint(CGPoint(x: location.x + dx, y: location.y + dy))
      result(postMouse(dragDown ? .leftMouseDragged : .mouseMoved, point, .left))
    case "click":
      guard let button = args["button"] as? String,
            button == "left" || button == "right",
            let number = args["count"] as? NSNumber,
            CFGetTypeID(number) != CFBooleanGetTypeID(),
            number.doubleValue == 1 || number.doubleValue == 2,
            let location = CGEvent(source: nil)?.location else {
        result(false)
        return
      }
      guard releaseDrag() else { result(false); return }
      let mouseButton: CGMouseButton = button == "right" ? .right : .left
      let down: CGEventType = button == "right" ? .rightMouseDown : .leftMouseDown
      let up: CGEventType = button == "right" ? .rightMouseUp : .leftMouseUp
      // A double click is two complete pairs, with click state 1 then 2.
      for clickState in 1...number.intValue {
        guard postMouse(down, location, mouseButton, clickState: clickState),
              postMouse(up, location, mouseButton, clickState: clickState) else {
          result(false)
          return
        }
      }
      result(true)
    case "drag":
      guard let state = args["s"] as? String, state == "down" || state == "up" else {
        result(false)
        return
      }
      if state == "up" { result(releaseDrag()); return }
      if dragDown { result(true); return }
      guard let location = CGEvent(source: nil)?.location,
            postMouse(.leftMouseDown, location, .left) else {
        result(false)
        return
      }
      dragDown = true
      result(true)
    case "scroll":
      guard let dx = delta(args["dx"]), let dy = delta(args["dy"]),
            let event = CGEvent(scrollWheelEvent2Source: nil, units: .pixel,
                                wheelCount: 2, wheel1: Int32(dy.rounded()),
                                wheel2: Int32(dx.rounded()), wheel3: 0) else {
        result(false)
        return
      }
      event.post(tap: .cghidEventTap)
      result(true)
    case "key":
      result(postKey(args["name"] as? String))
    case "media":
      result(postMedia(args["name"] as? String))
    default:
      result(FlutterMethodNotImplemented)
    }
  }

  private func delta(_ value: Any?) -> Double? {
    guard let number = value as? NSNumber,
          CFGetTypeID(number) != CFBooleanGetTypeID(),
          number.doubleValue.isFinite else { return nil }
    return min(maxDelta, max(-maxDelta, number.doubleValue))
  }

  private func clampedPoint(_ point: CGPoint) -> CGPoint {
    // CGDisplayBounds uses the same top-left coordinate space as CGEvent.
    // NSScreen.frame uses bottom-left coordinates and cannot be used directly.
    let bounds = NSScreen.screens.compactMap { screen -> CGRect? in
      guard let number = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber else { return nil }
      return CGDisplayBounds(CGDirectDisplayID(number.uint32Value))
    }
    if bounds.contains(where: { $0.contains(point) }) { return point }
    // Clamp to the actual union, including layouts with gaps between screens.
    return bounds.map { rect in
      CGPoint(x: min(rect.maxX - 1, max(rect.minX, point.x)),
              y: min(rect.maxY - 1, max(rect.minY, point.y)))
    }.min { a, b in
      hypot(a.x - point.x, a.y - point.y) < hypot(b.x - point.x, b.y - point.y)
    } ?? point
  }

  private func postMouse(_ type: CGEventType, _ point: CGPoint,
                         _ button: CGMouseButton, clickState: Int = 1) -> Bool {
    guard let event = CGEvent(mouseEventSource: nil, mouseType: type,
                              mouseCursorPosition: point, mouseButton: button) else { return false }
    event.setIntegerValueField(.mouseEventClickState, value: Int64(clickState))
    event.post(tap: .cghidEventTap)
    return true
  }

  private func releaseDrag() -> Bool {
    guard dragDown else { return true }
    dragDown = false
    guard AXIsProcessTrusted(), let location = CGEvent(source: nil)?.location else { return false }
    return postMouse(.leftMouseUp, location, .left)
  }

  private func postKey(_ name: String?) -> Bool {
    let code: CGKeyCode
    var flags: CGEventFlags = []
    switch name {
    case "next": code = 124
    case "prev": code = 123
    case "end", "escape": code = 53
    case "blackout": code = 11
    case "space": code = 49
    case "start":
      // Current generic fallback: Cmd+Return. PowerPoint's dedicated slideshow
      // shortcut is Cmd+Shift+Return; choose that when an app hint is introduced.
      code = 36
      flags = .maskCommand
    case "start_keynote":
      code = 35
      flags = [.maskCommand, .maskAlternate]
    default: return false
    }
    guard let down = CGEvent(keyboardEventSource: nil, virtualKey: code, keyDown: true),
          let up = CGEvent(keyboardEventSource: nil, virtualKey: code, keyDown: false) else { return false }
    down.flags = flags
    up.flags = flags
    down.post(tap: .cghidEventTap)
    up.post(tap: .cghidEventTap)
    return true
  }

  private func postMedia(_ name: String?) -> Bool {
    let keyType: Int
    switch name {
    case "playpause": keyType = 16
    case "next": keyType = 17
    case "prev": keyType = 18
    case "volup": keyType = 0
    case "voldown": keyType = 1
    case "mute": keyType = 7
    default: return false
    }
    func event(_ state: Int) -> CGEvent? {
      NSEvent.otherEvent(with: .systemDefined, location: .zero,
                         modifierFlags: [], timestamp: ProcessInfo.processInfo.systemUptime,
                         windowNumber: 0, context: nil, subtype: 8,
                         data1: (keyType << 16) | (state << 8), data2: 0)?.cgEvent
    }
    guard let down = event(0xa), let up = event(0xb) else { return false }
    down.post(tap: .cghidEventTap)
    up.post(tap: .cghidEventTap)
    return true
  }
}

private enum DotPreferenceMigration {
  static func reload() -> Bool {
    let domain = "com.bemooks.dot"
    guard Bundle.main.bundleIdentifier == domain,
          let library = FileManager.default.urls(for: .libraryDirectory, in: .userDomainMask).first else { return false }
    let url = library.appendingPathComponent("Preferences/\(domain).plist")
    guard let data = try? Data(contentsOf: url),
          let values = (try? PropertyListSerialization.propertyList(from: data, options: [], format: nil)) as? [String: Any] else { return false }
    // Read the target, preserving current settings when it already existed.
    // Refresh Foundation/cfprefsd as well as the file copied by Dart.
    UserDefaults.standard.setPersistentDomain(values, forName: domain)
    return UserDefaults.standard.synchronize()
  }
}
