import Cocoa
import FlutterMacOS

class LibraryRootFlutterViewController: FlutterViewController {
  private var libraryRootChannel: FlutterMethodChannel?
  private var securityScopedURLs: [URL] = []

  override func viewDidLoad() {
    super.viewDidLoad()
    let channel = FlutterMethodChannel(
      name: "studybible/library_root",
      binaryMessenger: engine.binaryMessenger
    )
    channel.setMethodCallHandler { [weak self] (call: FlutterMethodCall, result: @escaping FlutterResult) in
      switch call.method {
      case "pickFolder":
        self?.pickFolder(result: result)
      case "activateBookmark":
        self?.activateBookmark(call.arguments, result: result)
      default:
        result(FlutterMethodNotImplemented)
      }
    }
    libraryRootChannel = channel
  }

  private func pickFolder(result: @escaping FlutterResult) {
    DispatchQueue.main.async { [weak self] in
      guard self != nil else {
        result(nil)
        return
      }
      NSApp.activate(ignoringOtherApps: true)
      let panel = NSOpenPanel()
      panel.canChooseDirectories = true
      panel.canChooseFiles = false
      panel.allowsMultipleSelection = false
      panel.canCreateDirectories = false
      panel.prompt = "Choose Folder"
      let response = panel.runModal()
      guard response == .OK, let url = panel.url else {
        result(nil)
        return
      }
      do {
        let bookmark = try url.bookmarkData(
          options: [.withSecurityScope],
          includingResourceValuesForKeys: nil,
          relativeTo: nil
        )
        result([
          "path": url.path,
          "bookmark": bookmark.base64EncodedString(),
        ])
      } catch {
        result(FlutterError(
          code: "bookmark_failed",
          message: error.localizedDescription,
          details: nil
        ))
      }
    }
  }

  private func activateBookmark(_ arguments: Any?, result: @escaping FlutterResult) {
    guard
      let args = arguments as? [String: Any],
      let bookmarkString = args["bookmark"] as? String,
      let bookmarkData = Data(base64Encoded: bookmarkString)
    else {
      result(nil)
      return
    }

    var isStale = false
    do {
      let url = try URL(
        resolvingBookmarkData: bookmarkData,
        options: [.withSecurityScope],
        relativeTo: nil,
        bookmarkDataIsStale: &isStale
      )
      if url.startAccessingSecurityScopedResource() {
        securityScopedURLs.append(url)
      }
      result(url.path)
    } catch {
      result(FlutterError(
        code: "bookmark_activate_failed",
        message: error.localizedDescription,
        details: nil
      ))
    }
  }
}

class MainFlutterWindow: NSWindow {
  override func awakeFromNib() {
    let flutterViewController = LibraryRootFlutterViewController()
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
