import Cocoa
import FlutterMacOS

@main
class AppDelegate: FlutterAppDelegate {
  // Every window (the main editor window included) is created from Dart via
  // the windowing API, which requires the engine to enter multi-view mode
  // before any view controller is attached. The engine therefore runs
  // headless here rather than through a xib-instantiated window.
  var engine: FlutterEngine?

  override func applicationDidFinishLaunching(_ notification: Notification) {
    let engine = FlutterEngine(name: "main", project: nil)
    engine.run(withEntrypoint: nil)
    RegisterGeneratedPlugins(registry: engine)
    self.engine = engine

    // The editor draws its own header, so the main window's native title bar
    // collapses to the traffic lights over the content (the windowing API
    // creates the NSWindow, so it is styled as it becomes key). Floating
    // panel windows keep their normal chrome.
    NotificationCenter.default.addObserver(
      forName: NSWindow.didBecomeKeyNotification, object: nil, queue: .main
    ) { note in
      guard let window = note.object as? NSWindow, window.title == "Scene Editor" else { return }
      window.titlebarAppearsTransparent = true
      window.titleVisibility = .hidden
      window.styleMask.insert(.fullSizeContentView)
    }

    // Window dragging for the Flutter-drawn header: the content view covers
    // the title bar area, so the header asks the window to follow the mouse.
    let channel = FlutterMethodChannel(
      name: "scene_editor/window", binaryMessenger: engine.binaryMessenger)
    channel.setMethodCallHandler { call, result in
      switch call.method {
      case "startDrag":
        if let window = NSApp.keyWindow, let event = NSApp.currentEvent {
          window.performDrag(with: event)
        }
        result(nil)
      default:
        result(FlutterMethodNotImplemented)
      }
    }

    super.applicationDidFinishLaunching(notification)
  }

  override func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
    return true
  }

  override func applicationSupportsSecureRestorableState(_ app: NSApplication) -> Bool {
    return true
  }
}
