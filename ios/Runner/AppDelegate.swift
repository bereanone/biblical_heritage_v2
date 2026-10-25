import Flutter
import StoreKit
import Security
import CoreMotion
import UIKit
import UniformTypeIdentifiers

@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate {
  private var purchaseBridge: AnyObject?
  private var richClipboardChannel: FlutterMethodChannel?
  private var libraryRootBridge: LibraryRootFolderBridge?
  private var readerTiltMotionBridge: ReaderTiltMotionBridge?
  private var narrationThermalBridge: NarrationThermalBridge?
  private var narrationMediaBridge: NarrationMediaBridge?
  private let watchRemoteBridge = WatchRemoteBridge()

  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  func didInitializeImplicitFlutterEngine(_ engineBridge: FlutterImplicitEngineBridge) {
    GeneratedPluginRegistrant.register(with: engineBridge.pluginRegistry)
    if #available(iOS 15.0, *), let registrar = engineBridge.pluginRegistry.registrar(forPlugin: "StudyBiblePurchaseBridge") {
      let purchases = StudyBiblePurchaseBridge(messenger: registrar.messenger())
      purchases.accessChanged = { [weak self] allowed in self?.watchRemoteBridge.setPurchaseAccess(allowed) }
      purchaseBridge = purchases
      if WatchRemoteBridge.requiresPurchaseAccess { purchases.startAccessChecks() }
    }
    if let registrar = engineBridge.pluginRegistry.registrar(forPlugin: "RichClipboardBridge") {
      let clipboard = FlutterMethodChannel(name: "studybible/rich_clipboard", binaryMessenger: registrar.messenger())
      clipboard.setMethodCallHandler { call, result in
        if call.method == "writeImage" {
          guard let args = call.arguments as? [String:Any],let bytes = args["bytes"] as? FlutterStandardTypedData,
            let image = UIImage(data:bytes.data) else {result(FlutterError(code:"invalid_image",message:"Could not read image",details:nil)); return}
          UIPasteboard.general.image = image
          result(nil); return
        }
        if call.method == "readImage" {
          if let png = UIPasteboard.general.image?.pngData() {result(FlutterStandardTypedData(bytes:png))} else {result(nil)}
          return
        }
        guard call.method == "write" else { result(FlutterMethodNotImplemented); return }
        guard let args = call.arguments as? [String: String], let text = args["text"], let html = args["html"] else {
          result(FlutterError(code: "invalid_arguments", message: "Missing clipboard text or HTML", details: nil)); return
        }
        UIPasteboard.general.items = [[UTType.utf8PlainText.identifier: text, UTType.html.identifier: Data(html.utf8)]]
        result(nil)
      }
      richClipboardChannel = clipboard
    }

    if let registrar = engineBridge.pluginRegistry.registrar(forPlugin: "NarrationThermalBridge") {
      narrationThermalBridge = NarrationThermalBridge(registrar: registrar)
    }
    if let registrar = engineBridge.pluginRegistry.registrar(
      forPlugin: "LibraryRootFolderBridge"
    ) {
      libraryRootBridge = LibraryRootFolderBridge(registrar: registrar)
    }
    if let registrar = engineBridge.pluginRegistry.registrar(forPlugin: "ReaderTiltMotionBridge") {
      readerTiltMotionBridge = ReaderTiltMotionBridge(registrar: registrar)
    }
    // After plugin registration, so its audio session wins over audioplayers'.
    if let registrar = engineBridge.pluginRegistry.registrar(forPlugin: "NarrationMediaBridge") {
      let media = NarrationMediaBridge(registrar: registrar)
      narrationMediaBridge = media
      media.nativeCommandHandler = { [weak self] command in
        self?.watchRemoteBridge.handleMediaCommand(command) ?? false
      }
      watchRemoteBridge.nativePlaybackChanged = { [weak media] active in
        media?.setNativePlaybackActive(active)
      }
      media.setNativePlaybackActive(watchRemoteBridge.hasNativePlayback)
      watchRemoteBridge.attach(messenger: registrar.messenger())
    }
  }
}

final class ReaderTiltMotionBridge: NSObject, FlutterStreamHandler {
  private let manager = CMMotionManager()
  private var sink: FlutterEventSink?

  init(registrar: FlutterPluginRegistrar) {
    super.init()
    FlutterEventChannel(
      name: "studybible/reader_tilt_motion",
      binaryMessenger: registrar.messenger()
    ).setStreamHandler(self)
  }

  func onListen(withArguments arguments: Any?, eventSink events: @escaping FlutterEventSink) -> FlutterError? {
    guard manager.isDeviceMotionAvailable else {
      return FlutterError(code: "motion_unavailable", message: "Device motion is unavailable.", details: nil)
    }
    sink = events
    manager.deviceMotionUpdateInterval = 1.0 / 60.0
    manager.startDeviceMotionUpdates(using: .xArbitraryCorrectedZVertical, to: .main) { [weak self] motion, error in
      if let error = error {
        self?.sink?(FlutterError(code: "motion_error", message: error.localizedDescription, details: nil))
        return
      }
      guard let motion = motion else { return }
      let interfaceOrientation = UIApplication.shared.connectedScenes
        .compactMap { ($0 as? UIWindowScene)?.interfaceOrientation }
        .first ?? .portrait
      let orientation: String
      switch interfaceOrientation {
      case .portraitUpsideDown:
        orientation = "portraitUpsideDown"
      case .landscapeLeft:
        orientation = "landscapeLeft"
      case .landscapeRight:
        orientation = "landscapeRight"
      default:
        orientation = "portrait"
      }
      self?.sink?([
        "attitudePitch": motion.attitude.pitch,
        "attitudeRoll": motion.attitude.roll,
        "orientation": orientation,
      ])
    }
    return nil
  }

  func onCancel(withArguments arguments: Any?) -> FlutterError? {
    manager.stopDeviceMotionUpdates()
    sink = nil
    return nil
  }
}

final class LibraryRootFolderBridge: NSObject, UIDocumentPickerDelegate {
  private enum PendingSelectionKind {
    case folder
    case scannedHtmlFile
    case importFileCopies
    case importZipCopy
    case importPackageCopies
    case importCollectionCopy
    case importFolderCopies

    var requestLabel: String {
      switch self {
      case .folder:
        return "folder"
      case .scannedHtmlFile:
        return "scanned HTML file"
      case .importFileCopies:
        return "import file copy"
      case .importZipCopy:
        return "Pioneer ZIP import copy"
      case .importPackageCopies:
        return "studybook import copy"
      case .importCollectionCopy:
        return "study collection import copy"
      case .importFolderCopies:
        return "import folder copy"
      }
    }
  }

  private let channel: FlutterMethodChannel
  private var pendingResult: FlutterResult?
  private var pendingSelectionKind: PendingSelectionKind?
  private var securityScopedURLs: [URL] = []

  init(registrar: FlutterPluginRegistrar) {
    channel = FlutterMethodChannel(
      name: "studybible/library_root",
      binaryMessenger: registrar.messenger()
    )
    super.init()
    channel.setMethodCallHandler { [weak self] call, result in
      switch call.method {
      case "pickFolder":
        self?.pickFolder(result: result)
      case "pickScannedHtmlFile":
        self?.pickScannedHtmlFile(result: result)
      case "pickImportFiles":
        self?.pickImportFiles(call.arguments, result: result)
      case "pickImportFolders":
        self?.pickImportFolders(result: result)
      case "activateBookmark":
        self?.activateBookmark(call.arguments, result: result)
      default:
        result(FlutterMethodNotImplemented)
      }
    }
  }

  private func pickImportFolders(result: @escaping FlutterResult) {
    DispatchQueue.main.async { [weak self] in
      guard let self = self, let presenter = Self.topViewController() else {
        result(FlutterError(code: "folder_picker_unavailable", message: "Unable to present the book folder picker on iOS.", details: nil))
        return
      }
      let picker: UIDocumentPickerViewController
      if #available(iOS 14.0, *) {
        // UIKit asserts when a folder content type is combined with
        // asCopy=true. Open the selected directory under temporary
        // security-scoped access; Dart immediately copies its package
        // children into app-managed storage.
        picker = UIDocumentPickerViewController(
          forOpeningContentTypes: [.folder],
          asCopy: false
        )
      } else {
        picker = UIDocumentPickerViewController(
          documentTypes: ["public.folder"],
          in: .open
        )
      }
      picker.delegate = self
      // iOS Files providers reliably return the directory the user is
      // currently viewing when this is a single-folder request. Asking for
      // multiple folders makes package folders navigation targets in
      // providers such as OneDrive, leaving no usable selection action.
      picker.allowsMultipleSelection = false
      picker.modalPresentationStyle = .formSheet
      self.pendingSelectionKind = .importFolderCopies
      self.pendingResult = result
      presenter.present(picker, animated: true)
    }
  }

  private func pickFolder(result: @escaping FlutterResult) {
    presentPicker(
      kind: .folder,
      documentTypeIdentifiers: ["public.folder"],
      result: result
    )
  }

  private func pickScannedHtmlFile(result: @escaping FlutterResult) {
    presentPicker(
      kind: .scannedHtmlFile,
      documentTypeIdentifiers: ["public.html"],
      result: result
    )
  }

  private func pickImportFiles(_ arguments: Any?, result: @escaping FlutterResult) {
    let args = arguments as? [String: Any]
    let kind = (args?["kind"] as? String) ?? "html"
    DispatchQueue.main.async { [weak self] in
      print("StudyBible2: iOS import file picker requested (kind=\(kind)).")
      guard let self = self, let presenter = Self.topViewController() else {
        result(
          FlutterError(
            code: "file_picker_unavailable",
            message: "Unable to present the CaptureClipper file picker on iOS.",
            details: nil
          )
        )
        return
      }

      let picker: UIDocumentPickerViewController
      if kind == "pioneerZip" {
        if #available(iOS 14.0, *) {
          // Google Drive may advertise a ZIP as public.zip-archive,
          // public.archive, public.data, or a provider-specific dynamic type.
          // Include the broad fallbacks so Files can enable the document;
          // Dart still requires the selected filename to end in .zip.
          var contentTypes: [UTType] = [.zip, .archive, .data, .item]
          if let extensionType = UTType(filenameExtension: "zip"),
             !contentTypes.contains(extensionType) {
            contentTypes.append(extensionType)
          }
          picker = UIDocumentPickerViewController(
            forOpeningContentTypes: contentTypes,
            asCopy: true
          )
        } else {
          picker = UIDocumentPickerViewController(
            documentTypes: ["public.zip-archive", "public.archive", "public.data", "public.item"],
            in: .import
          )
        }
      } else if kind == "collection" || kind == "bookPackage" || kind == "pioneerPackage" {
        if #available(iOS 14.0, *) {
          // Ask to open one file, with the broad public.item type plus the
          // well-known zip archive type (a .studybook package is literally
          // a ZIP archive under a custom extension). Some cloud providers
          // (OneDrive observed) gray out files they can't confidently type
          // when only the fully generic public.item type is requested for
          // in-place opening; explicitly recognizing .zip lets the provider
          // resolve the file's underlying format. Restricting capability
          // negotiation to a custom package UTI or using the legacy
          // `.import` controller can make OneDrive fail while enumerating
          // the provider before a file is selected.
          picker = UIDocumentPickerViewController(
            forOpeningContentTypes: [.zip, .item],
            asCopy: false
          )
        } else {
          picker = UIDocumentPickerViewController(
            documentTypes: ["public.item"],
            in: .import
          )
        }
      } else if #available(iOS 14.0, *) {
        var contentTypes: [UTType]
        if kind == "assets" {
          contentTypes = [.html, .image, .plainText, .json]
          contentTypes.append(
            contentsOf: ["json", "htm", "html", "css", "txt", "jpg", "jpeg", "png", "gif", "webp"]
              .compactMap { UTType(filenameExtension: $0) }
          )
        } else {
          contentTypes = [.html]
          contentTypes.append(
            contentsOf: ["htm", "html"].compactMap { UTType(filenameExtension: $0) }
          )
        }
        // asCopy hands the app readable local copies; the OneDrive originals
        // are never opened in place, moved, or modified.
        picker = UIDocumentPickerViewController(
          forOpeningContentTypes: contentTypes,
          asCopy: true
        )
      } else {
        let documentTypes: [String]
        switch kind {
        case "assets":
          documentTypes = ["public.json", "public.html", "public.image", "public.text", "public.data"]
        default:
          documentTypes = ["public.html"]
        }
        picker = UIDocumentPickerViewController(
          documentTypes: documentTypes,
          in: .import
        )
      }
      picker.delegate = self
      // OneDrive and Google Drive on the physical iPad disable their entire
      // provider location when multi-document selection is required. A
      // single copied-document request preserves provider navigation; users
      // can repeat the import action for additional books.
      picker.allowsMultipleSelection =
        kind != "pioneerZip" && kind != "collection" && kind != "bookPackage" && kind != "pioneerPackage"
      picker.modalPresentationStyle = .formSheet
      self.pendingSelectionKind =
        kind == "pioneerZip"
          ? .importZipCopy
          : kind == "collection"
          ? .importCollectionCopy
          : (kind == "bookPackage" || kind == "pioneerPackage")
            ? .importPackageCopies
            : .importFileCopies
      self.pendingResult = result
      let isPioneerPackageKind =
        kind == "collection" || kind == "bookPackage" || kind == "pioneerPackage"
      let loggedContentTypes =
        kind == "pioneerZip"
          ? "[public.zip-archive, public.archive, public.data, public.item]"
          : isPioneerPackageKind ? "[public.item]" : "[content-specific]"
      let loggedCopyMode = isPioneerPackageKind ? "open-then-copy-locally" : "asCopy=true"
      let loggedMultipleSelection = !isPioneerPackageKind && kind != "pioneerZip"
      print(
        "StudyBible2: presenting copied-document picker. "
          + "kind=\(kind) contentTypes=\(loggedContentTypes) "
          + "copyMode=\(loggedCopyMode) "
          + "allowsMultipleSelection=\(loggedMultipleSelection) filesOnly=true."
      )
      presenter.present(picker, animated: true)
      print("StudyBible2: copied-document picker presentation requested successfully.")
    }
  }

  private func presentPicker(
    kind: PendingSelectionKind,
    documentTypeIdentifiers: [String],
    result: @escaping FlutterResult
  ) {
    DispatchQueue.main.async { [weak self] in
      print(
        "StudyBible2: iOS \(kind.requestLabel) picker requested. "
          + "contentTypes=\(documentTypeIdentifiers) mode=open asCopy=false. "
          + "Note: providers that do not support folder access grants are shown "
          + "faded by iOS; the app receives no callback for faded locations."
      )
      guard let self = self else {
        result(
          FlutterError(
            code: "folder_picker_unavailable",
            message: "Unable to present the CaptureClipper picker on iOS.",
            details: nil
          )
        )
        return
      }

      guard let presenter = Self.topViewController() else {
        result(
          FlutterError(
            code: "folder_picker_unavailable",
            message: "Unable to present the CaptureClipper picker on iOS.",
            details: nil
          )
        )
        return
      }

      let picker: UIDocumentPickerViewController
      if #available(iOS 14.0, *) {
        let contentTypes = documentTypeIdentifiers.compactMap { UTType($0) }
        picker = UIDocumentPickerViewController(
          forOpeningContentTypes: contentTypes,
          asCopy: false
        )
      } else {
        picker = UIDocumentPickerViewController(
          documentTypes: documentTypeIdentifiers,
          in: .open
        )
      }
      picker.delegate = self
      picker.allowsMultipleSelection = false
      picker.modalPresentationStyle = .formSheet
      self.pendingSelectionKind = kind
      self.pendingResult = result
      presenter.present(picker, animated: true)
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
        options: [],
        relativeTo: nil,
        bookmarkDataIsStale: &isStale
      )
      if url.startAccessingSecurityScopedResource() {
        securityScopedURLs.append(url)
      }
      result(url.path)
    } catch {
      result(
        FlutterError(
          code: "bookmark_activate_failed",
          message: error.localizedDescription,
          details: nil
        )
      )
    }
  }

  func documentPicker(_ controller: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]) {
    let selectionKind = pendingSelectionKind ?? .folder
    if selectionKind == .importFileCopies || selectionKind == .importZipCopy || selectionKind == .importPackageCopies || selectionKind == .importCollectionCopy || selectionKind == .importFolderCopies {
      guard !urls.isEmpty else {
        print("StudyBible2: iOS import file picker returned no selection.")
        finish(
          FlutterError(
            code: "file_picker_empty",
            message: "No files were returned by the Files picker.",
            details: nil
          )
        )
        return
      }
      if selectionKind == .importPackageCopies {
        let invalidNames = urls
          .map { $0.lastPathComponent }
          .filter {
            let lower = $0.lowercased()
            // Some export/backup tools append a redundant .zip suffix on
            // top of .studybook (e.g. "Book.studybook.zip"); a .studybook
            // package is itself a ZIP archive, so accept that variant too.
            return !lower.hasSuffix(".studybook") && !lower.hasSuffix(".studybook.zip")
          }
        if !invalidNames.isEmpty {
          print("StudyBible2: rejected non-studybook copied selection(s): \(invalidNames).")
          finish(
            FlutterError(
              code: "invalid_studybook_selection",
              message: "Choose an individual book package, not a collection file.",
              details: invalidNames
            )
          )
          return
        }
      }
      if selectionKind == .importZipCopy {
        let invalidNames = urls
          .map { $0.lastPathComponent }
          .filter { !$0.lowercased().hasSuffix(".zip") }
        if !invalidNames.isEmpty {
          finish(
            FlutterError(
              code: "invalid_pioneer_zip_selection",
              message: "Choose the Pioneer Library ZIP file you downloaded.",
              details: invalidNames
            )
          )
          return
        }
      }
      if selectionKind == .importCollectionCopy {
        // A .studycollection file is itself a ZIP archive, so a user who
        // downloaded or renamed it as a plain .zip shouldn't be blocked here;
        // the Dart-side inspect() validates the actual archive contents.
        let invalidNames = urls.map { $0.lastPathComponent }.filter {
          let lower = $0.lowercased()
          return !lower.hasSuffix(".studycollection") && !lower.hasSuffix(".zip")
        }
        if !invalidNames.isEmpty {
          finish(FlutterError(code: "invalid_studycollection_selection", message: "That is an individual book package. Choose Pioneers.studycollection to check the full collection.", details: invalidNames))
          return
        }
      }
      var returnedPaths: [String] = []
      for url in urls {
        let startedAccessing = url.startAccessingSecurityScopedResource()
        print(
          "StudyBible2: iOS import picker selection at \(url.path). "
            + "securityScopedAccess=\(startedAccessing ? "started" : "not needed")."
        )
        if selectionKind == .importPackageCopies || selectionKind == .importCollectionCopy {
          do {
            let caches = try FileManager.default.url(
              for: .cachesDirectory,
              in: .userDomainMask,
              appropriateFor: nil,
              create: true
            )
            let inbox = caches.appendingPathComponent("FilesProviderImports", isDirectory: true)
            try FileManager.default.createDirectory(
              at: inbox,
              withIntermediateDirectories: true
            )
            let localURL = inbox.appendingPathComponent(
              "\(UUID().uuidString)-\(url.lastPathComponent)",
              isDirectory: false
            )
            var coordinationError: NSError?
            var coordinatedCopyError: Error?
            var copied = false
            NSFileCoordinator().coordinate(
              readingItemAt: url,
              options: [],
              error: &coordinationError
            ) { coordinatedURL in
              do {
                try FileManager.default.copyItem(at: coordinatedURL, to: localURL)
                copied = true
              } catch {
                coordinatedCopyError = error
              }
            }
            if let error = coordinationError ?? coordinatedCopyError as NSError? {
              throw error
            }
            if !copied {
              throw NSError(
                domain: "StudyBibleFileProviderImport",
                code: 1,
                userInfo: [
                  NSLocalizedDescriptionKey: "OneDrive did not make the selected package available for copying."
                ]
              )
            }
            returnedPaths.append(localURL.path)
          } catch {
            if startedAccessing { url.stopAccessingSecurityScopedResource() }
            finish(
              FlutterError(
                code: "provider_file_copy_failed",
                message: "The selected package could not be copied into StudyBible storage.",
                details: error.localizedDescription
              )
            )
            return
          }
          if startedAccessing { url.stopAccessingSecurityScopedResource() }
        } else {
          returnedPaths.append(url.path)
          if startedAccessing {
            securityScopedURLs.append(url)
          }
        }
      }
      finish(["paths": returnedPaths])
      return
    }
    guard let url = urls.first else {
      print("StudyBible2: iOS \(selectionKind.requestLabel) picker returned no selection.")
      finish(
        FlutterError(
          code: "folder_picker_empty",
          message:
            "OneDrive did not grant folder access. Open the Files app, confirm OneDrive is enabled and signed in, then select the CloudFiles folder inside OneDrive. If folder access is still unavailable, use Pick Scanned HTML File.",
          details: nil
        )
      )
      return
    }

    do {
      let selectedIsDirectory = (try? url.resourceValues(
        forKeys: [.isDirectoryKey]
      ).isDirectory) ?? false
      var selectedTypeIdentifier = "(unknown)"
      if #available(iOS 14.0, *) {
        selectedTypeIdentifier = (try? url.resourceValues(
          forKeys: [.contentTypeKey]
        ).contentType?.identifier) ?? "(unknown)"
      }
      print(
        "StudyBible2: iOS \(selectionKind.requestLabel) picker selected \(url.path). "
          + "selectedItemIsFolder=\(selectedIsDirectory) "
          + "typeIdentifier=\(selectedTypeIdentifier) "
          + "providerUbiquitous=\((try? url.resourceValues(forKeys: [.isUbiquitousItemKey]).isUbiquitousItem) ?? false)."
      )
      let returnedURL: URL
      switch selectionKind {
      case .folder:
        returnedURL = url
      case .scannedHtmlFile:
        returnedURL = selectedIsDirectory ? url : url.deletingLastPathComponent()
      case .importFileCopies, .importZipCopy, .importPackageCopies, .importCollectionCopy, .importFolderCopies:
        // Handled by the early return above; kept for switch exhaustiveness.
        returnedURL = url
      }
      let returnedIsDirectory = (try? returnedURL.resourceValues(
        forKeys: [.isDirectoryKey]
      ).isDirectory) ?? false
      print(
        "StudyBible2: iOS picker returning \(returnedURL.path). returnedIsFolder=\(returnedIsDirectory)."
      )
      let bookmark = try returnedURL.bookmarkData(
        options: [.minimalBookmark],
        includingResourceValuesForKeys: nil,
        relativeTo: nil
      )
      print("StudyBible2: iOS picker bookmark created for \(returnedURL.path).")
      let startedAccessing = returnedURL.startAccessingSecurityScopedResource()
      print(
        "StudyBible2: iOS picker security-scoped access \(startedAccessing ? "started" : "not started") for \(returnedURL.path)."
      )
      if startedAccessing {
        securityScopedURLs.append(returnedURL)
      }
      finish([
        "path": returnedURL.path,
        "bookmark": bookmark.base64EncodedString(),
      ])
    } catch {
      finish(
        FlutterError(
          code: "bookmark_failed",
          message:
            "OneDrive did not grant folder access. Open the Files app, confirm OneDrive is enabled and signed in, then select the CloudFiles folder inside OneDrive. If folder access is still unavailable, use Pick Scanned HTML File.\n\n\(error.localizedDescription)",
          details: nil
        )
      )
    }
  }

  func documentPickerWasCancelled(_ controller: UIDocumentPickerViewController) {
    let selectionKind = pendingSelectionKind ?? .folder
    print("StudyBible2: iOS \(selectionKind.requestLabel) picker cancelled.")
    finish(nil)
  }

  private func finish(_ value: Any?) {
    let result = pendingResult
    pendingResult = nil
    pendingSelectionKind = nil
    result?(value)
  }

  private static func topViewController() -> UIViewController? {
    let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
    let keyWindow = scenes
      .flatMap { $0.windows }
      .first { $0.isKeyWindow }
    var topViewController = keyWindow?.rootViewController
    while let presented = topViewController?.presentedViewController {
      topViewController = presented
    }
    return topViewController
  }
}

// Kept in the registered source file so no Xcode project-file mutation is needed.
final class NarrationThermalBridge: NSObject, FlutterStreamHandler {
  private var sink: FlutterEventSink?
  private var observer: NSObjectProtocol?
  init(registrar: FlutterPluginRegistrar) {
    super.init()
    FlutterMethodChannel(name: "studybible/narration_thermal", binaryMessenger: registrar.messenger())
      .setMethodCallHandler { [weak self] call, result in
        if call.method == "snapshot" { result(self?.snapshot()) }
        else { result(FlutterMethodNotImplemented) }
      }
    FlutterEventChannel(name: "studybible/narration_thermal_events", binaryMessenger: registrar.messenger())
      .setStreamHandler(self)
  }
  private func snapshot() -> [String: Any] {
    let state = ProcessInfo.processInfo.thermalState
    let level: Int
    switch state {
    case .nominal: level = 0
    case .fair: level = 1
    case .serious, .critical: level = 2
    @unknown default: return [:]
    }
    return ["level": level, "status": state.rawValue]
  }
  func onListen(withArguments arguments: Any?, eventSink events: @escaping FlutterEventSink) -> FlutterError? {
    sink = events
    events(snapshot())
    observer = NotificationCenter.default.addObserver(
      forName: ProcessInfo.thermalStateDidChangeNotification, object: nil, queue: .main
    ) { [weak self] _ in
      guard let self = self else { return }
      self.sink?(self.snapshot())
    }
    return nil
  }
  func onCancel(withArguments arguments: Any?) -> FlutterError? {
    if let observer = observer { NotificationCenter.default.removeObserver(observer) }
    observer = nil
    sink = nil
    return nil
  }
  deinit { if let observer = observer { NotificationCenter.default.removeObserver(observer) } }
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

  // WatchConnectivity may wake the phone before Dart has initialized.
  // Resolve verified ownership and schedule trial expiry for that path too.
  func startAccessChecks() {
    enabled = true
    Task { [weak self] in
      guard let self else { return }
      if (try? await self.snapshot()) == nil { self.accessChanged?(false) }
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
