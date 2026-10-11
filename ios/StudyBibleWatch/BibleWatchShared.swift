import SwiftUI
import WatchConnectivity
import WidgetKit
import AppIntents

@MainActor
final class BibleWatchSession: NSObject, ObservableObject, WCSessionDelegate {
  static let shared = BibleWatchSession()

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

  var skipUnit: String { draftLoopUnit }

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
        session.sendMessage(["command": name]) { continuation.resume(returning: $0) }
          errorHandler: { continuation.resume(throwing: $0) }
      }
      apply(reply, fromReply: true)
      if !confirmed { throw WatchCommandError.unconfirmed }
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
    else if fromReply { message = "iPhone connected" }
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
        command("state")
      }
    }
  }

  nonisolated func session(_ session: WCSession, didReceiveApplicationContext context: [String: Any]) {
    Task { @MainActor in apply(context) }
  }

  nonisolated func sessionReachabilityDidChange(_ session: WCSession) {
    Task { @MainActor in
      if session.isReachable { command("state") }
      else if confirmed {
        confirmed = false
        message = "iPhone unavailable"
      }
    }
  }
}

private enum WatchCommandError: Error { case busy, unavailable, unconfirmed }

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
    UserDefaults(suiteName: suite)?.set([
      "title": title, "loop": loop, "lastLoop": lastLoop,
      "playing": playing, "confirmed": confirmed,
      "message": message ?? ""
    ], forKey: "remoteState")
    WidgetCenter.shared.reloadTimelines(ofKind: kind)
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
