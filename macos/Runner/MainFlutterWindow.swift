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
    input.onTextFocus = { active, field in
      inputChannel.invokeMethod("textFocus", arguments: ["active": active, "field": field])
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
  private let maxText = 64

  /// Text focus watching: polls the system-wide focused element while a
  /// trusted phone is connected, and reports changes to Dart.
  var onTextFocus: ((Bool, Int) -> Void)?
  private var focusTimer: Timer?
  private var focusedField: AXUIElement?
  private var focusActive = false
  private var fieldCounter = 0
  private var accessibleApps = Set<pid_t>()

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
    case "watchTextFocus":
      let enabled = (call.arguments as? [String: Any])?["enabled"] as? Bool ?? false
      setFocusWatch(enabled)
      result(true)
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
    case "text":
      result(postText(args["text"] as? String))
    case "edit":
      result(postEdit(args["name"] as? String))
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

  private func postText(_ text: String?) -> Bool {
    guard let text = text, !text.isEmpty, text.utf16.count <= maxText,
          !text.unicodeScalars.contains(where: { $0.value < 0x20 || ($0.value >= 0x7f && $0.value < 0xa0) }) else {
      return false
    }
    // One event per character: some apps only read the first character of a
    // multi-character Unicode keyboard event.
    for character in text {
      let units = Array(String(character).utf16)
      guard let down = CGEvent(keyboardEventSource: nil, virtualKey: 0, keyDown: true),
            let up = CGEvent(keyboardEventSource: nil, virtualKey: 0, keyDown: false) else { return false }
      // Clear modifiers so a held Cmd on the Mac never turns text into shortcuts.
      down.flags = []
      up.flags = []
      down.keyboardSetUnicodeString(stringLength: units.count, unicodeString: units)
      up.keyboardSetUnicodeString(stringLength: units.count, unicodeString: units)
      down.post(tap: .cghidEventTap)
      up.post(tap: .cghidEventTap)
    }
    return true
  }

  private func postEdit(_ name: String?) -> Bool {
    let code: CGKeyCode
    switch name {
    case "backspace": code = 51
    case "enter": code = 36
    case "tab": code = 48
    case "left": code = 123
    case "right": code = 124
    case "down": code = 125
    case "up": code = 126
    default: return false
    }
    guard let down = CGEvent(keyboardEventSource: nil, virtualKey: code, keyDown: true),
          let up = CGEvent(keyboardEventSource: nil, virtualKey: code, keyDown: false) else { return false }
    down.flags = []
    up.flags = []
    down.post(tap: .cghidEventTap)
    up.post(tap: .cghidEventTap)
    return true
  }

  private func setFocusWatch(_ enabled: Bool) {
    focusTimer?.invalidate()
    focusTimer = nil
    focusedField = nil
    focusActive = false
    guard enabled else { return }
    let timer = Timer(timeInterval: 0.25, repeats: true) { [weak self] _ in
      self?.pollFocus()
    }
    RunLoop.main.add(timer, forMode: .common)
    focusTimer = timer
    pollFocus()
  }

  private func pollFocus() {
    guard AXIsProcessTrusted() else { report(nil); return }
    if let app = NSWorkspace.shared.frontmostApplication {
      enableAccessibility(app.processIdentifier)
    }
    var value: CFTypeRef?
    guard AXUIElementCopyAttributeValue(AXUIElementCreateSystemWide(),
                                        kAXFocusedUIElementAttribute as CFString,
                                        &value) == .success,
          let raw = value, CFGetTypeID(raw) == AXUIElementGetTypeID() else {
      report(nil)
      return
    }
    let element = raw as! AXUIElement
    report(isTextInput(element) ? element : nil)
  }

  /// Chromium and Electron apps (Chrome, VS Code, Slack) only expose their web
  /// content to Accessibility after a client asks for it.
  private func enableAccessibility(_ pid: pid_t) {
    guard pid != getpid(), !accessibleApps.contains(pid) else { return }
    accessibleApps.insert(pid)
    AXUIElementSetAttributeValue(AXUIElementCreateApplication(pid),
                                 "AXManualAccessibility" as CFString, kCFBooleanTrue)
  }

  private func report(_ element: AXUIElement?) {
    var changed = false
    if let element = element {
      if focusedField == nil || !CFEqual(focusedField!, element) {
        fieldCounter += 1
        focusedField = element
        changed = true
      }
    } else {
      focusedField = nil
    }
    let active = element != nil
    guard active != focusActive || changed else { return }
    focusActive = active
    onTextFocus?(active, fieldCounter)
  }

  private func isTextInput(_ element: AXUIElement) -> Bool {
    var pid: pid_t = 0
    if AXUIElementGetPid(element, &pid) == .success, pid == getpid() { return false }
    if let enabled = attribute(element, kAXEnabledAttribute) as? Bool, !enabled { return false }
    let role = attribute(element, kAXRoleAttribute) as? String ?? ""
    let subrole = attribute(element, kAXSubroleAttribute) as? String ?? ""
    if ["AXTextField", "AXTextArea", "AXComboBox", "AXSearchField"].contains(role) ||
       subrole == "AXSearchField" || subrole == "AXSecureTextField" {
      return true
    }
    // Rich editors and contenteditable regions: an editable caret.
    var settable: DarwinBoolean = false
    return AXUIElementIsAttributeSettable(element, kAXSelectedTextRangeAttribute as CFString,
                                          &settable) == .success && settable.boolValue &&
      attribute(element, kAXSelectedTextRangeAttribute) != nil
  }

  private func attribute(_ element: AXUIElement, _ name: String) -> AnyObject? {
    var value: CFTypeRef?
    guard AXUIElementCopyAttributeValue(element, name as CFString, &value) == .success else { return nil }
    return value
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
