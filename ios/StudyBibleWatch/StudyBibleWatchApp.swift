import SwiftUI
import WatchConnectivity

@main
struct StudyBibleWatchApp: App {
  @StateObject private var remote = BibleWatchSession()

  var body: some Scene {
    WindowGroup {
      WatchRemoteView().environmentObject(remote)
    }
  }
}

private struct WatchRemoteView: View {
  @EnvironmentObject private var remote: BibleWatchSession

  var body: some View {
    ScrollView {
      VStack(spacing: 9) {
        Text(remote.title).font(.headline).multilineTextAlignment(.center)
        Text(remote.loop == "off" ? "Loop off" : "Loop: \(remote.loop.capitalized)")
          .font(.caption).foregroundStyle(.secondary)
        HStack(spacing: 8) {
          Button {
            remote.command(remote.confirmed && remote.playing ? "stop" : "start")
          } label: {
            Text(remote.confirmed && remote.playing ? "Stop" : "Start")
              .frame(maxWidth: .infinity)
          }
          .buttonStyle(.borderedProminent)
          Button { remote.command("pause") } label: {
            Text("Pause").frame(maxWidth: .infinity)
          }
          .buttonStyle(.bordered)
        }
        HStack(spacing: 8) {
          Button { remote.command("previous") } label: {
            Text("Previous").frame(maxWidth: .infinity)
          }
          .accessibilityLabel("Previous \(remote.skipUnit)")
          Button { remote.command("next") } label: {
            Text("Next").frame(maxWidth: .infinity)
          }
          .accessibilityLabel("Next \(remote.skipUnit)")
        }
        .buttonStyle(.bordered)
        Divider()
        Text("Choose loop").font(.caption).frame(maxWidth: .infinity, alignment: .leading)
        HStack(spacing: 4) {
          loopUnitButton("Book", unit: "book")
          loopUnitButton("Chapter", unit: "chapter")
          loopUnitButton("Verse", unit: "verse")
        }
        HStack(spacing: 8) {
          Button { remote.command("loop:\(remote.draftLoopUnit)") } label: {
            Text("Engage").frame(maxWidth: .infinity)
          }
          .disabled(remote.awaitingReply || remote.loop == remote.draftLoopUnit)
          Button { remote.command("loop:off") } label: {
            Text("Off").frame(maxWidth: .infinity)
          }
          .disabled(remote.awaitingReply || remote.loop == "off")
        }
        .buttonStyle(.bordered)
        if let message = remote.message {
          Text(message).font(.caption2).multilineTextAlignment(.center)
        }
      }
      .padding(.horizontal, 6)
    }
    .onAppear { remote.activate() }
  }

  private func loopUnitButton(_ label: String, unit: String) -> some View {
    Button { remote.selectLoopUnit(unit) } label: {
      Text(label).font(.caption2).minimumScaleFactor(0.7)
        .frame(maxWidth: .infinity)
    }
    .buttonStyle(.borderedProminent)
    .tint(remote.draftLoopUnit == unit ? .accentColor : .gray)
    .disabled(remote.awaitingReply)
    .accessibilityLabel("Loop \(label)")
    .accessibilityValue(remote.draftLoopUnit == unit ? "Selected" : "Not selected")
  }
}

@MainActor
private final class BibleWatchSession: NSObject, ObservableObject, WCSessionDelegate {
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

  var skipUnit: String {
    switch loop {
    case "book": return "book"
    case "chapter": return "chapter"
    default: return "verse"
    }
  }

  func activate() {
    guard WCSession.isSupported() else {
      message = "A paired iPhone is required."
      return
    }
    let session = WCSession.default
    session.delegate = self
    session.activate()
  }

  func command(_ name: String) {
    guard !awaitingReply else { return }
    let session = WCSession.default
    guard session.activationState == .activated else {
      message = "Connecting to iPhone…"
      session.activate()
      return
    }
    awaitingReply = true
    message = "Contacting iPhone…"
    // A Watch-originated immediate message can wake a suspended or
    // system-terminated companion app. Do not queue a stale Play command.
    session.sendMessage(["command": name]) { [weak self] reply in
      Task { @MainActor in
        self?.awaitingReply = false
        self?.apply(reply, fromReply: true)
      }
    } errorHandler: { [weak self] error in
      Task { @MainActor in
        self?.awaitingReply = false
        self?.confirmed = false
        self?.message = "Cannot reach iPhone — command not confirmed."
      }
    }
  }

  private func apply(_ state: [String: Any], fromReply: Bool = false) {
    confirmed = state["error"] == nil && (state["pending"] as? Bool != true)
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
