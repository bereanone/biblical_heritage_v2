import Cocoa
import FlutterMacOS

class MainFlutterWindow: NSWindow {
  override func awakeFromNib() {
    let flutterViewController = FlutterViewController()
    self.contentViewController = flutterViewController

    // Match the older macOS launcher behavior: start at a readable size
    // and prevent tiny window dimensions that break the layout.
    let defaultSize = NSSize(width: 1024, height: 820)
    let minSize = NSSize(width: 900, height: 700)
    self.contentMinSize = minSize

    var frame = self.frame
    if frame.size.width < defaultSize.width || frame.size.height < defaultSize.height {
      frame.size.width = max(frame.size.width, defaultSize.width)
      frame.size.height = max(frame.size.height, defaultSize.height)
      self.setFrame(frame, display: true)
      self.center()
    }

    RegisterGeneratedPlugins(registry: flutterViewController)

    super.awakeFromNib()
  }
}
