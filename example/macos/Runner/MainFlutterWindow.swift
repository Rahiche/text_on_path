import Cocoa
import FlutterMacOS

class MainFlutterWindow: NSWindow {
  override func awakeFromNib() {
    let flutterViewController = FlutterViewController()
    // Wide enough for each sample's four panels side by side.
    let screen = NSScreen.main?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1680, height: 1050)
    let size = NSSize(width: min(1640, screen.width), height: min(1060, screen.height))
    let windowFrame = NSRect(
      x: screen.midX - size.width / 2, y: screen.midY - size.height / 2, width: size.width, height: size.height)
    self.contentViewController = flutterViewController
    self.setFrame(windowFrame, display: true)

    RegisterGeneratedPlugins(registry: flutterViewController)

    super.awakeFromNib()
  }
}
