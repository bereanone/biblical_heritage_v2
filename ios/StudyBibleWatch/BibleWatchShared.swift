import SwiftUI
import WatchConnectivity
import WidgetKit
import AppIntents

@MainActor
final class BibleWatchSession: NSObject, ObservableObject, WCSessionDelegate {
  static let shared = BibleWatchSession()

  @Published var mode = "bible"
  @Published var libraryBookID = ""
  @Published var libraryBooks: [WatchAudioBook] = []
  @Published var libraryTOC: [WatchAudioContents] = []
  @Published var libraryParagraphs: [WatchAudioContents] = []
  private var foreground = false
  @Published var bookNumber = 1
  @Published var chapterNumber = 1
  @Published var verseNumber = 1
  @Published var chapterCount = 1
  @Published var verseCount = 1
  @Published var title = "Open a Bible passage on iPhone"
  @Published var loop = "off"
  @Published var lastLoop = "chapter"
  @Published var draftLoopUnit = "chapter"
  @Published var playing = false
  @Published var message: String?
  @Published var confirmed = false
  @Published var awaitingReply = false
  private var hasLocalLoopSelection = false

  var selectedLoopUnit: String { loop == "off" ? lastLoop : loop }

  func selectLoopUnit(_ unit: String) {
    guard ["book", "chapter", "verse"].contains(unit) else { return }
    draftLoopUnit = unit
    hasLocalLoopSelection = true
  }

  var skipUnit: String { mode == "library" && draftLoopUnit == "verse" ? "paragraph" : draftLoopUnit }

  func setForeground(_ active: Bool) {
    let changed = foreground != active
    foreground = active
    if active {
      activate()
      if changed && WCSession.default.activationState == .activated { command("state") }
    }
  }

  func activate() {
    guard WCSession.isSupported() else {
      message = "A paired iPhone is required."
      return
    }
    let session = WCSession.default
    session.delegate = self
    if session.activationState != .activated { session.activate() }
  }

  func command(_ name: String) {
    Task { try? await execute(name) }
  }

  func execute(_ name: String) async throws {
    guard !awaitingReply else { throw WatchCommandError.busy }
    awaitingReply = true
    defer { awaitingReply = false }
    activate()
    let session = WCSession.default
    for _ in 0..<30 {
      if session.activationState == .activated { break }
      try await Task.sleep(nanoseconds: 100_000_000)
    }
    guard session.activationState == .activated else { throw WatchCommandError.unavailable }
    message = "Contacting iPhone…"
    do {
      let reply: [String: Any] = try await withCheckedThrowingContinuation { continuation in
        let reply = WatchCommandReply(continuation)
        DispatchQueue.main.asyncAfter(deadline: .now() + 12) {
          reply.finish(.failure(WatchCommandError.timedOut))
        }
        session.sendMessage(["command": name]) { reply.finish(.success($0)) }
          errorHandler: { reply.finish(.failure($0)) }
      }
      apply(reply, fromReply: true)
      if !confirmed && reply["pending"] as? Bool != true { throw WatchCommandError.unconfirmed }
    } catch {
      confirmed = false
      message = "Cannot reach iPhone — command not confirmed."
      saveComplicationState()
      throw error
    }
  }

  private func saveComplicationState() {
    WatchComplicationState.save(title: title, loop: loop, lastLoop: lastLoop,
      playing: playing, confirmed: confirmed, message: message)
  }

  private func apply(_ state: [String: Any], fromReply: Bool = false) {
    confirmed = state["error"] == nil && (state["pending"] as? Bool != true)
    if let mode = state["mode"] as? String, ["bible","library"].contains(mode) {
      if self.mode != mode { hasLocalLoopSelection = false }
      self.mode = mode
    }
    libraryBookID = state["libraryBookID"] as? String ?? ""
    libraryBooks = (state["libraryBooks"] as? [[String:Any]] ?? []).compactMap {
      guard let id = $0["id"] as? String, let title = $0["title"] as? String else { return nil }
      return WatchAudioBook(id:id,title:title)
    }
    libraryTOC = (state["libraryTOC"] as? [[String:Any]] ?? []).enumerated().compactMap { index,row in
      guard let c = row["chapter"] as? Int, let p = row["paragraph"] as? Int, let title = row["title"] as? String else { return nil }
      return WatchAudioContents(id:"\(index):\(c):\(p)",title:title,chapter:c,paragraph:p)
    }
    libraryParagraphs = (state["libraryParagraphs"] as? [[String:Any]] ?? []).compactMap {
      guard let p = $0["number"] as? Int, let title = $0["title"] as? String else { return nil }
      return WatchAudioContents(id:String(p),title:title,chapter:state["chapter"] as? Int ?? 1,paragraph:p)
    }
    if let book = state["book"] as? Int { bookNumber = book }
    if let chapter = state["chapter"] as? Int { chapterNumber = chapter }
    if let verse = state["verse"] as? Int { verseNumber = verse }
    if let count = state["chapterCount"] as? Int { chapterCount = max(1, count) }
    if let count = state["verseCount"] as? Int { verseCount = max(1, count) }
    if let title = state["title"] as? String { self.title = title }
    if let loop = state["loop"] as? String { self.loop = loop }
    if let lastLoop = state["lastLoop"] as? String { self.lastLoop = lastLoop }
    if !hasLocalLoopSelection || (state["loop"] as? String == draftLoopUnit) {
      draftLoopUnit = selectedLoopUnit
      hasLocalLoopSelection = false
    }
    if let playing = state["playing"] as? Bool { self.playing = playing }
    if let error = state["error"] as? String { message = error }
    else if state["pending"] as? Bool == true { message = "Waiting for iPhone to update…" }
    else if fromReply || message == "Waiting for iPhone to update…" { message = "iPhone connected" }
    saveComplicationState()
  }

  nonisolated func session(_ session: WCSession, activationDidCompleteWith state: WCSessionActivationState, error: Error?) {
    Task { @MainActor in
      if error != nil {
        confirmed = false
        message = "Cannot reach iPhone. Try again when connected."
      }
      else if state == .activated {
        apply(session.receivedApplicationContext)
        if foreground { command("state") }
      }
    }
  }

  nonisolated func session(_ session: WCSession, didReceiveApplicationContext context: [String: Any]) {
    Task { @MainActor in apply(context) }
  }

  nonisolated func sessionReachabilityDidChange(_ session: WCSession) {
    Task { @MainActor in
      if session.isReachable && foreground { command("state") }
      else if !session.isReachable && confirmed {
        confirmed = false
        message = "iPhone unavailable"
      }
    }
  }
}

private enum WatchCommandError: Error { case busy, unavailable, unconfirmed, timedOut }

// WatchConnectivity can deliver an error or a late reply after the deadline.
// Resume exactly once so a lost phone reply never leaves controls disabled.
private final class WatchCommandReply: @unchecked Sendable {
  private let lock = NSLock()
  private var continuation: CheckedContinuation<[String: Any], Error>?
  init(_ continuation: CheckedContinuation<[String: Any], Error>) {
    self.continuation = continuation
  }
  func finish(_ result: Result<[String: Any], Error>) {
    lock.lock()
    let pending = continuation
    continuation = nil
    lock.unlock()
    pending?.resume(with: result)
  }
}

struct WatchComplicationState {
  static let suite = "group.com.deanbowen.bibleAppMac.watchremote"
  static let kind = "StudyBibleRemote"
  let title: String
  let loop: String
  let playing: Bool
  let confirmed: Bool

  static func read() -> Self {
    let data = UserDefaults(suiteName: suite)?.dictionary(forKey: "remoteState") ?? [:]
    return Self(title: data["title"] as? String ?? "StudyBible",
      loop: data["loop"] as? String ?? "off", playing: data["playing"] as? Bool ?? false,
      confirmed: data["confirmed"] as? Bool ?? false)
  }
  static func save(title: String, loop: String, lastLoop: String,
    playing: Bool, confirmed: Bool, message: String?) {
    let previous = UserDefaults(suiteName:suite)?.dictionary(forKey:"remoteState")
    let next: [String:Any] = [
      "title": title, "loop": loop, "lastLoop": lastLoop,
      "playing": playing, "confirmed": confirmed,
      "message": message ?? ""
    ]
    if let previous, NSDictionary(dictionary:previous).isEqual(to:next) { return }
    UserDefaults(suiteName:suite)?.set(next,forKey:"remoteState")
    // Connection messages do not change anything displayed by the complication.
    let visible = ["title","loop","playing","confirmed"]
    if previous == nil || visible.contains(where: { !NSObjectEqual(previous?[$0],next[$0]) }) {
      WidgetCenter.shared.reloadTimelines(ofKind:kind)
    }
  }
}

enum BibleRemoteAction: String, AppEnum {
  case previous, toggle, next, loop
  static var typeDisplayRepresentation = TypeDisplayRepresentation(name: "Bible control")
  static var caseDisplayRepresentations: [Self: DisplayRepresentation] = [
    .previous: "Previous loop target", .toggle: "Play or pause", .next: "Next loop target", .loop: "Toggle loop"
  ]
}

struct BibleRemoteIntent: AudioPlaybackIntent {
  static var title: LocalizedStringResource = "Control StudyBible"
  static var openAppWhenRun = true
  @Parameter(title: "Action") var action: BibleRemoteAction
  init() {}
  init(action: BibleRemoteAction) { self.action = action }
  @MainActor func perform() async throws -> some IntentResult {
    let remote = BibleWatchSession.shared
    if action == .loop {
      try await remote.execute("state")
      try await remote.execute(remote.loop == "off" ? "loop:\(remote.lastLoop)" : "loop:off")
    } else {
      try await remote.execute(action.rawValue)
    }
    return .result()
  }
}

private func NSObjectEqual(_ a:Any?,_ b:Any?) -> Bool {
  guard let a, let b else { return a == nil && b == nil }
  return NSDictionary(dictionary:["value":a]).isEqual(to:["value":b])
}
struct WatchAudioBook: Identifiable { let id:String; let title:String }
struct WatchAudioContents: Identifiable { let id:String; let title:String; let chapter:Int; let paragraph:Int }
