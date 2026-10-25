import Cocoa
import StoreKit
import Security
import FlutterMacOS

class LibraryRootFlutterViewController: FlutterViewController {
  private var purchaseBridge: AnyObject?
  private var recordedAudio: RecordedBibleAudioBridge?
  private var richClipboardChannel: FlutterMethodChannel?
  private var libraryRootChannel: FlutterMethodChannel?
  private var securityScopedURLs: [URL] = []

  override func viewDidLoad() {
    super.viewDidLoad()
    if #available(macOS 12.0, *) {
      purchaseBridge = StudyBiblePurchaseBridge(messenger: engine.binaryMessenger)
    }
    recordedAudio = RecordedBibleAudioBridge(messenger: engine.binaryMessenger)
    let clipboard = FlutterMethodChannel(name: "studybible/rich_clipboard", binaryMessenger: engine.binaryMessenger)
    clipboard.setMethodCallHandler { call, result in
      if call.method == "writeImage" {
        guard let args = call.arguments as? [String: Any], let bytes = args["bytes"] as? FlutterStandardTypedData,
          let image = NSImage(data: bytes.data) else {
          result(FlutterError(code:"invalid_image",message:"Could not read image",details:nil)); return
        }
        NSPasteboard.general.clearContents()
        result(NSPasteboard.general.writeObjects([image]) ? nil : FlutterError(code:"clipboard_failed",message:"Could not copy image",details:nil)); return
      }
      if call.method == "readImage" {
        let objects = NSPasteboard.general.readObjects(forClasses:[NSImage.self],options:nil)
        guard let image = objects?.first as? NSImage, let tiff = image.tiffRepresentation,
          let bitmap = NSBitmapImageRep(data:tiff), let png = bitmap.representation(using:.png,properties:[:]) else {result(nil); return}
        result(FlutterStandardTypedData(bytes:png)); return
      }
      guard call.method == "write" else { result(FlutterMethodNotImplemented); return }
      guard let args = call.arguments as? [String: String], let text = args["text"], let html = args["html"] else {
        result(FlutterError(code: "invalid_arguments", message: "Missing clipboard text or HTML", details: nil)); return
      }
      let item = NSPasteboardItem()
      item.setString(text, forType: .string)
      item.setString(html, forType: .html)
      NSPasteboard.general.clearContents()
      result(NSPasteboard.general.writeObjects([item]) ? nil : FlutterError(code: "clipboard_failed", message: "Could not copy study", details: nil))
    }
    richClipboardChannel = clipboard

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
  override var title: String {
    get { super.title }
    set {
      #if DEBUG
      let build = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? ""
      super.title = "Biblical Heritage — Beta \(build) — In Testing — Not Final"
      #else
      super.title = "Biblical Heritage"
      #endif
    }
  }

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
    self.title = "Biblical Heritage"
  }
}

// Permanent access uses only StoreKit-verified transactions. No code or brand
// name grants ownership; discounted/free offers redeem the same product.
@available(iOS 15.0, macOS 12.0, *)
@MainActor
final class StudyBiblePurchaseBridge {
  static let unlockID = "studybible_full_access"
  static let trialID = "studybible_trial_14_days"
  private let channel: FlutterMethodChannel
  private var updates: Task<Void, Never>?
  private var expiryTimer: Timer?
  private var enabled = false
  var accessChanged: ((Bool) -> Void)?

  init(messenger: FlutterBinaryMessenger) {
    channel = FlutterMethodChannel(name: "studybible/purchases", binaryMessenger: messenger)
    channel.setMethodCallHandler { [weak self] call, result in
      guard let self else { result(FlutterMethodNotImplemented); return }
      Task { @MainActor in
        do {
          switch call.method {
          case "initialize":
            self.enabled = true
            if (call.arguments as? [String: Any])?["existingCustomer"] as? Bool == true {
              try self.writeSecure("legacy", value: "yes")
            }
            result(try await self.snapshot())
          case "refresh": result(try await self.snapshot())
          case "restore":
            try await AppStore.sync()
            result(try await self.snapshot())
          case "products":
            let products = try await Product.products(for: [Self.unlockID, Self.trialID])
            result(products.map { ["id": $0.id, "price": $0.displayPrice, "name": $0.displayName] })
          case "purchase":
            let id = (call.arguments as? [String: Any])?["id"] as? String ?? ""
            guard [Self.unlockID, Self.trialID].contains(id),
                  let product = try await Product.products(for: [id]).first else {
              throw PurchaseFailure.unavailable
            }
            switch try await product.purchase() {
            case .success(let verification):
              guard case .verified(let transaction) = verification else { throw PurchaseFailure.unverified }
              await transaction.finish()
              result(["outcome": "purchased", "access": try await self.snapshot()])
            case .pending: result(["outcome": "pending"])
            case .userCancelled: result(["outcome": "cancelled"])
            @unknown default: throw PurchaseFailure.unavailable
            }
          case "redeem":
            #if os(iOS)
            SKPaymentQueue.default().presentCodeRedemptionSheet()
            #else
            NSWorkspace.shared.open(URL(string: "https://apps.apple.com/redeem?ctx=offercodes&id=6760154157")!)
            #endif
            result(nil)
          default: result(FlutterMethodNotImplemented)
          }
        } catch {
          result(FlutterError(code: "purchase_failed", message: error.localizedDescription, details: nil))
        }
      }
    }
    updates = Task { [weak self] in
      for await update in Transaction.updates {
        guard let self else { return }
        guard case .verified(let transaction) = update,
              [Self.unlockID, Self.trialID].contains(transaction.productID) else { continue }
        // Notify first; a failed refresh remains eligible for StoreKit redelivery.
        if let access = try? await self.snapshot() {
          self.channel.invokeMethod("accessChanged", arguments: access)
          await transaction.finish()
        }
      }
    }
  }

  private func snapshot() async throws -> [String: Any] {
    var paid = false
    var trialStart: Date?
    for await verification in Transaction.currentEntitlements {
      guard case .verified(let transaction) = verification,
            transaction.revocationDate == nil, !transaction.isUpgraded else { continue }
      if transaction.productID == Self.unlockID { paid = true }
      if transaction.productID == Self.trialID, transaction.ownershipType == .purchased {
        trialStart = min(trialStart ?? transaction.originalPurchaseDate, transaction.originalPurchaseDate)
      }
    }
    var legacy = readSecure("legacy") == "yes"
    if !legacy {
      if #available(iOS 16.0, macOS 13.0, *),
         let verification = try? await AppTransaction.shared,
         case .verified(let app) = verification,
         app.environment == .production,
         app.bundleID == Bundle.main.bundleIdentifier {
        #if os(iOS)
        // Last free builds predate the payment release. StoreKit uses the
        // original build number on iOS; sandbox receipts never qualify here.
        let old = Int(app.originalAppVersion).map { (1...144).contains($0) } ?? false
        #else
        let old = ["1.0", "1.0.0", "1.0.1"].contains(app.originalAppVersion)
        #endif
        if old { try writeSecure("legacy", value: "yes"); legacy = true }
      }
    }
    // A high-water clock survives reinstall and prevents clock rollback from
    // extending a redeemed trial. StoreKit retains its original purchase date.
    let now = max(Date().timeIntervalSince1970, Double(readSecure("lastSeen") ?? "0") ?? 0)
    try writeSecure("lastSeen", value: String(now))
    let end = trialStart?.addingTimeInterval(14 * 24 * 60 * 60)
    let allowed = paid || legacy || (end.map { now < $0.timeIntervalSince1970 } ?? false)
    expiryTimer?.invalidate()
    if !paid && !legacy, let end, end.timeIntervalSince1970 > now {
      expiryTimer = Timer.scheduledTimer(withTimeInterval: end.timeIntervalSince1970 - now, repeats: false) { [weak self] _ in
        Task { @MainActor in
          guard let self, let access = try? await self.snapshot() else { return }
          self.channel.invokeMethod("accessChanged", arguments: access)
        }
      }
    }
    if enabled { accessChanged?(allowed) }
    var value: [String: Any] = ["paid": paid, "legacy": legacy, "allowed": allowed,
                              "trialStarted": trialStart != nil, "checkedAt": now * 1000]
    if let end { value["trialEndsAt"] = end.timeIntervalSince1970 * 1000 }
    return value
  }

  private func secureQuery(_ key: String) -> [String: Any] {
    [kSecClass as String: kSecClassGenericPassword,
     kSecAttrService as String: "studybible.purchase-access.v1",
     kSecAttrAccount as String: key]
  }
  private func readSecure(_ key: String) -> String? {
    var query = secureQuery(key)
    query[kSecReturnData as String] = true
    var item: CFTypeRef?
    guard SecItemCopyMatching(query as CFDictionary, &item) == errSecSuccess,
          let data = item as? Data else { return nil }
    return String(data: data, encoding: .utf8)
  }
  private func writeSecure(_ key: String, value: String) throws {
    let query = secureQuery(key)
    let attributes: [String: Any] = [kSecValueData as String: Data(value.utf8)]
    var status = SecItemUpdate(query as CFDictionary, attributes as CFDictionary)
    if status == errSecItemNotFound {
      var addition = query.merging(attributes) { _, new in new }
      addition[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
      status = SecItemAdd(addition as CFDictionary, nil)
    }
    guard status == errSecSuccess else { throw PurchaseFailure.storage }
  }
  enum PurchaseFailure: LocalizedError {
    case unavailable, unverified, storage
    var errorDescription: String? {
      switch self {
      case .unavailable: return "This purchase is not available from the App Store yet. Please try again later."
      case .unverified: return "Apple could not verify this purchase. Try Restore Purchases."
      case .storage: return "Access could not be saved securely. Please unlock your device and try again."
      }
    }
  }
  deinit { updates?.cancel(); expiryTimer?.invalidate() }
}
