import Flutter
import UIKit
import UniformTypeIdentifiers

@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate {
  private var libraryRootBridge: LibraryRootFolderBridge?

  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  func didInitializeImplicitFlutterEngine(_ engineBridge: FlutterImplicitEngineBridge) {
    GeneratedPluginRegistrant.register(with: engineBridge.pluginRegistry)
    if let registrar = engineBridge.pluginRegistry.registrar(
      forPlugin: "LibraryRootFolderBridge"
    ) {
      libraryRootBridge = LibraryRootFolderBridge(registrar: registrar)
    }
  }
}

final class LibraryRootFolderBridge: NSObject, UIDocumentPickerDelegate {
  private enum PendingSelectionKind {
    case folder
    case scannedHtmlFile
    case importFileCopies
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
      if kind == "collection" || kind == "bookPackage" {
        // The legacy import-mode initializer remains the most compatible
        // copied-document workflow for third-party providers. On the
        // physical iPad, OneDrive and Google Drive disable their locations
        // during capability negotiation with forOpeningContentTypes/asCopy,
        // even for public.data. `.import` copies selected files locally and
        // requests no folder or persistent security-scoped access.
        picker = UIDocumentPickerViewController(
          documentTypes: ["public.data"],
          in: .import
        )
      } else if #available(iOS 14.0, *) {
        var contentTypes: [UTType]
        if kind == "assets" {
          contentTypes = [.html, .image, .plainText]
          contentTypes.append(
            contentsOf: ["htm", "html", "css", "txt", "jpg", "jpeg", "png", "gif", "webp"]
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
          documentTypes = ["public.html", "public.image", "public.text", "public.data"]
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
      picker.allowsMultipleSelection = kind != "collection" && kind != "bookPackage"
      picker.modalPresentationStyle = .formSheet
      self.pendingSelectionKind = kind == "collection" ? .importCollectionCopy : kind == "bookPackage" ? .importPackageCopies : .importFileCopies
      self.pendingResult = result
      let loggedContentTypes = kind == "collection" || kind == "bookPackage" ? "[public.data]" : "[content-specific]"
      let loggedCopyMode = kind == "collection" || kind == "bookPackage" ? "import" : "asCopy=true"
      let loggedMultipleSelection = kind != "collection" && kind != "bookPackage"
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
    if selectionKind == .importFileCopies || selectionKind == .importPackageCopies || selectionKind == .importCollectionCopy || selectionKind == .importFolderCopies {
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
            !$0.lowercased().hasSuffix(".studybook")
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
      if selectionKind == .importCollectionCopy {
        let invalidNames = urls.map { $0.lastPathComponent }.filter { !$0.lowercased().hasSuffix(".studycollection") }
        if !invalidNames.isEmpty {
          finish(FlutterError(code: "invalid_studycollection_selection", message: "That is an individual book package. Choose Pioneers.studycollection to check the full collection.", details: invalidNames))
          return
        }
      }
      for url in urls {
        let startedAccessing = url.startAccessingSecurityScopedResource()
        print(
          "StudyBible2: iOS import picker selection at \(url.path). "
            + "securityScopedAccess=\(startedAccessing ? "started" : "not needed")."
        )
        if startedAccessing {
          securityScopedURLs.append(url)
        }
      }
      finish(["paths": urls.map { $0.path }])
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
      case .importFileCopies, .importPackageCopies, .importCollectionCopy, .importFolderCopies:
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
