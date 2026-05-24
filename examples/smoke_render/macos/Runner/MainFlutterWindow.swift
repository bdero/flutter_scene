import Cocoa
import FlutterMacOS

class MainFlutterWindow: NSWindow {
  override func awakeFromNib() {
    let flutterViewController = FlutterViewController()
    let windowFrame = self.frame
    self.contentViewController = flutterViewController
    self.setFrame(windowFrame, display: true)

    RegisterGeneratedPlugins(registry: flutterViewController)

    super.awakeFromNib()

    // On a headless CI runner the app launches in the background. macOS then
    // marks the window occluded and Flutter's embedder pauses the display
    // link, so no frames are produced and the integration test hangs waiting
    // on tester.pump()/toImage(). Force the app active and the window
    // frontmost so its occlusion state stays visible and frames keep flowing.
    NSApp.setActivationPolicy(.regular)
    NSApp.activate(ignoringOtherApps: true)
    self.orderFrontRegardless()
  }
}
