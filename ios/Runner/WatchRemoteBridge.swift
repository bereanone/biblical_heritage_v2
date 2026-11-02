import AVFoundation
import Flutter
import MediaPlayer
import WatchConnectivity

// The same source-word migration is used by the native Watch-controlled player.
func remapLibraryAudioPosition(_ saved: [String: Any], manifest: [String: Any]?) -> [String: Any] {
  guard let manifest, let migration = manifest["timeline_migration"] as? [String: Any],
        let target = migration["to"] as? String else { return saved }
  let version = saved["timeline_version"] as? String ?? ""
  guard version != target, (migration["from_versions"] as? [String] ?? []).contains(version),
        let chapter = saved["chapter"] as? Int, let position = saved["position_ms"] as? NSNumber,
        let old = (migration["tracks"] as? [[String: Any]])?.first(where: { $0["chapter"] as? Int == chapter }),
        let current = (manifest["tracks"] as? [[String: Any]])?.first(where: { $0["chapter"] as? Int == chapter }) else { return saved }
  let milliseconds = position.doubleValue
  let previous = (old["cues"] as? [[String: Any]] ?? []).last(where: { (($0["start_ms"] as? NSNumber)?.doubleValue ?? .infinity) <= milliseconds })
  var mapped = 0.0
  if let previous {
    guard let cursor = previous["source_cursor"] as? String,
          let cue = (current["cues"] as? [[String: Any]] ?? []).first(where: { $0["source_cursor"] as? String == cursor }),
          let start = cue["start_ms"] as? NSNumber else { return saved }
    let elapsed = milliseconds - ((previous["start_ms"] as? NSNumber)?.doubleValue ?? 0)
    var offset = 0
    for word in previous["words"] as? [[NSNumber]] ?? [] where word.count == 2 {
      if word[0].doubleValue <= elapsed { offset = word[1].intValue }
    }
    var nearest = -1; var relative = 0.0
    for word in cue["phrases"] as? [[String: Any]] ?? [] {
      if let candidate = word["source_start_offset"] as? Int, candidate <= offset, candidate >= nearest,
         let time = word["start_ms"] as? NSNumber { nearest = candidate; relative = time.doubleValue }
    }
    mapped = start.doubleValue + relative
  }
  var result = saved; result["position_ms"] = Int(mapped.rounded()); result["timeline_version"] = target
  return result
}

/// Receives immediate Watch commands even when the Flutter reader has not opened.
/// The phone owns playback; the Watch never downloads or speaks Bible audio.
final class WatchRemoteBridge: NSObject, WCSessionDelegate {
  private static let savedStateKey = "studybible.watchRemote.lastState.v1"
  private var channel: FlutterMethodChannel?
  private var libraryChannel: FlutterMethodChannel?
  private var libraryMode = false
  private var bibleState: [String: Any] = [:]
  private var lastStoredBible: [String: Any]?
  private var lastPublishedWatch: [String: Any]?
  private lazy var library: WatchLibraryPlayback = {
    let library = WatchLibraryPlayback()
    library.changed = { [weak self] in self?.publishLibraryState() }
    library.readerChanged = { [weak self] in self?.publishLibraryReaderState() }
    library.ownershipChanged = { [weak self] active in self?.nativePlaybackChanged?(active) }
    return library
  }()
  // Only the explicit billing-off build may skip native verification.
  // A missing or malformed build configuration keeps Watch playback closed.
  static var requiresPurchaseAccess: Bool {
    guard let url = Bundle.main.url(forResource: "StudyBibleBilling", withExtension: "plist"),
          let data = try? Data(contentsOf: url),
          let config = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any],
          let enabled = config["enabled"] as? Bool else { return true }
    return enabled
  }
  private var purchaseAccessAllowed: Bool
  func setPurchaseAccess(_ allowed: Bool) {
    purchaseAccessAllowed = allowed
    if !allowed { library.pause(); library.stopPlayer(); stopNativePlayer(); state["playing"] = false }
    state["accessAllowed"] = allowed
    if !allowed { state["error"] = "Open StudyBible on iPhone to unlock access." }
    else { state.removeValue(forKey: "error") }
    publishToWatch()
  }
  private var readerAttached = false
  private var state: [String: Any]
  private var chapters: [WatchChapter]?
  private var player: AVPlayer?
  private var announcementPlayer: AVPlayer?
  private var announcementEndObserver: NSObjectProtocol?
  private var pendingAnnouncementURLs: [URL] = []
  private var needsOpeningAnnouncements = false
  private var timeObserver: Any?
  private var endObserver: NSObjectProtocol?
  private var lastReportedVerse: Int?
  var nativePlaybackChanged: ((Bool) -> Void)?
  var hasNativePlayback: Bool { player != nil || library.hasPlayer }

  /// Headsets remain connected to the phone. Route system transport commands
  /// to its native recording while that recording owns playback.
  func handleMediaCommand(_ command: String) -> Bool {
    guard purchaseAccessAllowed else { return false }
    if libraryMode && library.hasPlayer {
      do { try library.perform(command == "play" ? "start" : command) }
      catch { state["error"] = error.localizedDescription; publishToWatch() }
      return true
    }
    guard player != nil else { return false }
    let nativeCommand = command == "play" ? "start" : command
    do { try performNative(nativeCommand) }
    catch {
      state["error"] = error.localizedDescription
      store(state)
    }
    return true
  }


  init(requiresPurchaseAccess: Bool = WatchRemoteBridge.requiresPurchaseAccess) {
    purchaseAccessAllowed = !requiresPurchaseAccess
    state = UserDefaults.standard.dictionary(forKey: Self.savedStateKey) ?? [
      "book": 0, "chapter": 0, "verse": 0, "loop": "off", "lastLoop": "chapter",
      "playing": false, "title": "Open a Bible passage on iPhone",
    ]
    // Bible is the default on every launch; library positions are kept separately.
    if state["mode"] as? String == "library" {
      state = UserDefaults.standard.dictionary(forKey: "studybible.watchRemote.bible.v1") ?? [
        "book":0,"chapter":0,"verse":0,"loop":"off","lastLoop":"chapter",
        "title":"Open a Bible passage on iPhone"]
    }
    state["mode"] = "bible"
    state["playing"] = false // A terminated process cannot still own playback.
    state["pending"] = false
    state["accessAllowed"] = purchaseAccessAllowed
    if purchaseAccessAllowed { state.removeValue(forKey: "error") }
    else { state["error"] = "Open StudyBible on iPhone to unlock access." }
    bibleState = state
    super.init()
    if WCSession.isSupported() {
      WCSession.default.delegate = self
      WCSession.default.activate()
    }
  }

  func attach(messenger: FlutterBinaryMessenger) {
    let bridge = FlutterMethodChannel(name: "studybible/watch_remote", binaryMessenger: messenger)
    channel = bridge
    let shelf = FlutterMethodChannel(name:"studybible/watch_library",binaryMessenger:messenger)
    libraryChannel = shelf
    shelf.setMethodCallHandler { [weak self] call, result in
      guard let self else { result(nil); return }
      switch call.method {
      case "catalogChanged":
        do { try self.library.refresh(); self.publishLibraryState(); result(nil) }
        catch { result(FlutterError(code:"audio_shelf",message:error.localizedDescription,details:nil)) }
      case "readerState":
        result(self.libraryReaderState())
      case "readerCommand":
        guard self.purchaseAccessAllowed, self.libraryMode,
              let args = call.arguments as? [String: Any],
              let bookId = args["bookId"] as? String,
              let command = args["command"] as? String,
              (bookId == self.library.bookID || command == "libraryBook:\(bookId)") else {
          result(FlutterError(code:"library_owner", message:"The selected phone recording has changed.", details:nil)); return
        }
        do {
          if command == "seek", let chapter = args["chapter"] as? Int,
             let milliseconds = args["position_ms"] as? Int, milliseconds >= 0 {
            try self.library.seekFromReader(chapter:chapter, milliseconds:milliseconds,
                                           play:args["play"] as? Bool ?? false)
          } else { try self.library.perform(command) }
          self.publishLibraryState(); result(self.libraryReaderState())
        } catch { result(FlutterError(code:"library_command", message:error.localizedDescription, details:nil)) }
      case "pauseNative":
        if self.library.hasPlayer { self.library.pause(); self.library.stopPlayer() }
        if self.player != nil { self.stopNativePlayer(); self.state["playing"] = false; self.store(self.state) }
        self.publishLibraryState()
        result(nil)
      default: result(FlutterMethodNotImplemented)
      }
    }
    bridge.setMethodCallHandler { [weak self] call, result in
      guard let self else { result(FlutterMethodNotImplemented); return }
      switch call.method {
      case "readerAttached":
        self.readerAttached = true
        result(self.bibleState.merging(["nativePlayback": !self.libraryMode && self.player != nil]) { _, new in new })
      case "readerDetached":
        self.readerAttached = false
        result(nil)
      case "handoffNative":
        if self.libraryMode { result(self.bibleState.merging(["nativePlayback":false]) { _,new in new }); return }
        let wasPlaying = self.state["playing"] as? Bool ?? false
        let hadPlayer = self.player != nil
        self.stopNativePlayer()
        self.state["playing"] = false
        self.state["pending"] = false
        self.store(self.state)
        result(self.state.merging(["nativePlayback": hadPlayer, "resumePlayback": hadPlayer && wasPlaying]) { _, new in new })
      case "publishState":
        guard let incoming = call.arguments as? [String: Any] else {
          result(FlutterError(code: "bad_state", message: "Missing Watch state", details: nil))
          return
        }
        // A cold-started native recording keeps playing until Flutter actually
        // takes over. Merely opening the reader must not cut off the audio.
        let flutterPlaying = incoming["playing"] as? Bool ?? false
        if self.player != nil && !flutterPlaying {
          result(nil)
          return
        }
        if flutterPlaying {
          self.libraryMode = false
          if self.library.hasPlayer { self.library.pause(); self.library.stopPlayer() }
          self.stopNativePlayer()
        }
        self.store(incoming)
        result(nil)
      default:
        result(FlutterMethodNotImplemented)
      }
    }
  }

  // WCSession callbacks arrive on a background queue. AVPlayer and Flutter
  // channels are handled on the main queue, then the Watch receives a reply.
  func session(_ session: WCSession, activationDidCompleteWith activationState: WCSessionActivationState, error: Error?) {
    DispatchQueue.main.async { self.publishToWatch() }
  }

  func sessionDidBecomeInactive(_ session: WCSession) {}

  func sessionDidDeactivate(_ session: WCSession) {
    session.activate() // The paired active Watch may have changed.
  }

  func session(_ session: WCSession, didReceiveMessage message: [String: Any], replyHandler: @escaping ([String: Any]) -> Void) {
    DispatchQueue.main.async {
      let command = message["command"] as? String ?? ""
      if command == "state" {
        replyHandler(self.state)
        return
      }
      guard self.purchaseAccessAllowed else {
        replyHandler(self.state.merging(["error": "Open StudyBible on iPhone to unlock access."]) { _, new in new })
        return
      }
      if command == "mode:bible" || command == "mode:library" || self.libraryMode {
        self.performLibraryRemote(command,reply:replyHandler)
        return
      }
      let bookJump = command.hasPrefix("book:") && (1...66).contains(Int(command.dropFirst(5)) ?? 0)
      let passageJump = command.hasPrefix("chapter:") || command.hasPrefix("verse:")
      guard bookJump || passageJump || ["previous:book", "previous:chapter", "previous:verse", "next:book", "next:chapter", "next:verse"].contains(command) || ["start", "stop", "pause", "toggle", "next", "previous",
             "loop:off", "loop:book", "loop:chapter", "loop:verse"].contains(command) else {
        replyHandler(["error": "Unsupported command"])
        return
      }
      if self.readerAttached && self.player == nil, let channel = self.channel {
        channel.invokeMethod("command", arguments: command) { response in
          if let error = response as? FlutterError {
            replyHandler(self.state.merging(["error": error.message ?? "The iPhone could not complete that command."]) { _, new in new })
          } else if response != nil {
            replyHandler(self.state.merging(["error": "The iPhone reader is unavailable."]) { _, new in new })
          } else {
            replyHandler(self.state)
          }
        }
        return
      }
      do {
        try self.performNative(command)
        replyHandler(self.state)
      } catch {
        replyHandler(self.state.merging(["error": error.localizedDescription]) { _, new in new })
      }
    }
  }

  private func store(_ updated: [String: Any]) {
    guard let book = updated["book"] as? Int, (1...66).contains(book),
          let chapter = updated["chapter"] as? Int, chapter > 0,
          let verse = updated["verse"] as? Int, verse > 0,
          let loop = updated["loop"] as? String,
          ["off", "verse", "chapter", "book"].contains(loop) else { return }
    let selectedLoop = updated["lastLoop"] as? String ?? "chapter"
    var next: [String: Any] = [
      "mode":"bible", "book": book, "chapter": chapter, "verse": verse, "loop": loop,
      "lastLoop": ["verse", "chapter", "book"].contains(selectedLoop)
        ? selectedLoop : "chapter",
      "playing": updated["playing"] as? Bool ?? false,
      "title": updated["title"] as? String ?? "Book \(book) \(chapter):\(verse)",
      "loopTargetBook": updated["loopTargetBook"] as? Int ?? book,
      "loopTargetChapter": updated["loopTargetChapter"] as? Int ?? chapter,
      "loopTargetVerse": updated["loopTargetVerse"] as? Int ?? verse,
      "pending": updated["pending"] as? Bool ?? false,
    ]
    if let all = try? loadChapters() {
      next["chapterCount"] = all.filter { $0.book == book }.map { $0.chapter }.max() ?? 1
      next["verseCount"] = all.first { $0.book == book && $0.chapter == chapter }?.verseStarts.map { $0.verse }.max() ?? 1
    }
    next["accessAllowed"] = purchaseAccessAllowed
    if !purchaseAccessAllowed {
      next["error"] = "Open StudyBible on iPhone to unlock access."
    } else if let error = updated["error"] as? String { next["error"] = error }
    bibleState = next
    if lastStoredBible == nil || !NSDictionary(dictionary:lastStoredBible!).isEqual(to:next) {
      lastStoredBible = next
      UserDefaults.standard.set(next, forKey:"studybible.watchRemote.bible.v1")
      UserDefaults.standard.set(next, forKey:Self.savedStateKey)
    }
    guard !libraryMode else { return }
    state = next
    publishToWatch()
    updateNowPlaying()
  }

  private func publishToWatch() {
    guard WCSession.isSupported() else { return }
    let session = WCSession.default
    guard session.activationState == .activated,
          session.isPaired, session.isWatchAppInstalled else { return }
    if let lastPublishedWatch, NSDictionary(dictionary:lastPublishedWatch).isEqual(to:state) { return }
    do { try session.updateApplicationContext(state); lastPublishedWatch = state }
    catch { /* Keep the last successful state so a later meaningful update retries. */ }
  }

  private func libraryReaderState() -> [String: Any] {
    var snapshot = library.readerSnapshot()
    snapshot["nativePlayback"] = libraryMode && purchaseAccessAllowed
    return snapshot
  }

  private func publishLibraryReaderState() {
    libraryChannel?.invokeMethod("playbackChanged", arguments:libraryReaderState())
  }

  private func publishLibraryState() {
    publishLibraryReaderState()
    guard libraryMode else { return }
    state = library.snapshot()
    state["accessAllowed"] = purchaseAccessAllowed
    if !purchaseAccessAllowed { state["error"] = "Open StudyBible on iPhone to unlock access." }
    publishToWatch(); updateNowPlaying()
  }

  private func performLibraryRemote(_ command:String, reply:@escaping ([String:Any])->Void) {
    let perform = { [weak self] in
      guard let self else { reply(["error":"iPhone unavailable"]); return }
      do {
        if command == "mode:bible" {
          self.library.pause(); self.library.stopPlayer(); self.libraryMode = false
          self.bibleState["playing"] = false; self.bibleState["pending"] = false
          self.state = self.bibleState; self.store(self.bibleState); self.publishLibraryReaderState(); reply(self.state); return
        }
        if command == "mode:library" {
          try self.library.refresh()
          self.stopNativePlayer(); self.libraryMode = true
        } else { try self.library.perform(command) }
        self.publishLibraryState(); reply(self.state)
      } catch { reply(self.state.merging(["error":error.localizedDescription]) { _,new in new }) }
    }
    // A loop choice does not start/stop an existing recording.
    if command.hasPrefix("loop:") || (libraryMode && library.hasPlayer && !command.hasPrefix("mode:")) {
      perform(); return
    }
    guard let libraryChannel else { reply(state.merging(["error":"Open eLibrary on iPhone once to prepare audio controls."]) { _,new in new }); return }
    var completed = false
    DispatchQueue.main.asyncAfter(deadline: .now() + 8) {
      guard !completed else { return }
      completed = true
      reply(self.state.merging(["error":"iPhone did not confirm the pause. Try switching again."]) { _,new in new })
    }
    libraryChannel.invokeMethod("pauseReaders",arguments:nil) { response in
      // A late pause must not execute an abandoned mode or playback command.
      guard !completed else { return }
      completed = true
      if let error = response as? FlutterError {
        reply(self.state.merging(["error":error.message ?? "The current recording could not pause."]) { _,new in new })
      } else { perform() }
    }
  }

  private func loadChapters() throws -> [WatchChapter] {
    if let chapters { return chapters }
    guard let path = assetPath("assets/audio/qwen_bible/catalog.json") else {
      throw WatchRemoteError.missingRecording
    }
    let catalog = try JSONDecoder().decode(WatchCatalog.self, from: Data(contentsOf: URL(fileURLWithPath: path)))
    guard catalog.chapters.count == 1189 else { throw WatchRemoteError.missingRecording }
    chapters = catalog.chapters
    return catalog.chapters
  }

  private func assetPath(_ asset: String) -> String? {
    let key = FlutterDartProject.lookupKey(forAsset: asset)
    return Bundle.main.path(forResource: key, ofType: nil)
  }

  private func currentChapter() throws -> WatchChapter {
    let book = state["book"] as? Int ?? 0
    let chapter = state["chapter"] as? Int ?? 0
    guard let match = try loadChapters().first(where: { $0.book == book && $0.chapter == chapter }) else {
      throw WatchRemoteError.choosePassage
    }
    return match
  }

  private func performNative(_ command: String) throws {
    if command.hasPrefix("chapter:") || command.hasPrefix("verse:") {
      let parts = command.split(separator: ":")
      guard parts.count == 2, let number = Int(parts[1]), number > 0 else { throw WatchRemoteError.missingRecording }
      let old = state
      let chapter = try currentChapter()
      let targetChapter = parts[0] == "chapter" ? number : chapter.chapter
      let targetVerse = parts[0] == "verse" ? number : 1
      guard let target = try loadChapters().first(where: { $0.book == chapter.book && $0.chapter == targetChapter }),
            target.verseStarts.contains(where: { $0.verse == targetVerse }) else { throw WatchRemoteError.missingVerseTiming }
      state["chapter"] = targetChapter
      state["verse"] = targetVerse
      state["loopTargetBook"] = chapter.book
      state["loopTargetChapter"] = targetChapter
      state["loopTargetVerse"] = targetVerse
      state["title"] = "\(Self.bookName(chapter.book)) \(targetChapter):\(targetVerse)"
      do { try playCurrent(shouldPlay: false) }
      catch { state = old; throw error }
      return
    }
    if command.hasPrefix("book:"), let book = Int(command.dropFirst(5)), (1...66).contains(book) {
      let old = state
      state["book"] = book
      state["chapter"] = 1
      state["verse"] = 1
      state["loopTargetBook"] = book
      state["loopTargetChapter"] = 1
      state["loopTargetVerse"] = 1
      state["title"] = "\(Self.bookName(book)) 1:1"
      do { try playCurrent(shouldPlay: false) }
      catch { state = old; throw error }
      return
    }
    if command.hasPrefix("previous:") || command.hasPrefix("next:") {
      let parts = command.split(separator: ":")
      let scope = String(parts[1])
      guard ["book", "chapter", "verse"].contains(scope) else { throw WatchRemoteError.missingRecording }
      let target = try parts[0] == "next" ? nextLocation(scope: scope) : previousLocation(scope: scope)
      let old = state
      let wasPlaying = state["playing"] as? Bool ?? false
      state["book"] = target.book
      state["chapter"] = target.chapter
      state["verse"] = target.verse
      state["loopTargetBook"] = target.book
      state["loopTargetChapter"] = target.chapter
      state["loopTargetVerse"] = target.verse
      state["title"] = "\(Self.bookName(target.book)) \(target.chapter):\(target.verse)"
      do { try playCurrent(shouldPlay: wasPlaying) }
      catch { state = old; throw error }
      return
    }
    switch command {
    case "start":
      if state["pending"] as? Bool == true { return }
      if let announcementPlayer, announcementPlayer.currentItem != nil {
        announcementPlayer.play()
        state["playing"] = true
        state.removeValue(forKey: "error")
        store(state)
      } else if needsOpeningAnnouncements {
        try playOpeningAnnouncementsThenChapter()
        state["playing"] = true
        state.removeValue(forKey: "error")
        store(state)
      } else if let player, player.currentItem != nil {
        player.play()
        state["playing"] = true
        state["pending"] = false
        state.removeValue(forKey: "error")
        store(state)
      } else {
        try playCurrent(shouldPlay: true)
      }
    case "stop", "pause":
      if state["pending"] as? Bool == true {
        // Cancel an unfinished seek so it cannot start playing after Stop.
        stopNativePlayer()
      } else {
        announcementPlayer?.pause()
        player?.pause() // Keep the exact position for Start / Resume.
      }
      state["playing"] = false
      state["pending"] = false
      store(state)
    case "toggle":
      if state["pending"] as? Bool == true { return }
      if state["playing"] as? Bool == true {
        try performNative("pause")
      } else {
        try performNative("start")
      }
    case "next", "previous":
      let destination = try command == "next" ? nextLocation() : previousLocation()
      let wasPlaying = state["playing"] as? Bool ?? false
      let previousState = state
      state["book"] = destination.book
      state["chapter"] = destination.chapter
      state["verse"] = destination.verse
      state["title"] = "\(Self.bookName(destination.book)) \(destination.chapter):\(destination.verse)"
      state["loopTargetBook"] = destination.book
      state["loopTargetChapter"] = destination.chapter
      state["loopTargetVerse"] = destination.verse
      do {
        try playCurrent(shouldPlay: wasPlaying)
      } catch {
        state = previousState
        throw error
      }
    case "loop:off":
      if let active = state["loop"] as? String, active != "off" {
        state["lastLoop"] = active
      }
      state["loop"] = "off"
      store(state)
    case "loop:book", "loop:chapter", "loop:verse":
      let mode = String(command.dropFirst("loop:".count))
      let chapter = try currentChapter()
      let verse = state["verse"] as? Int ?? 0
      guard mode != "verse" || chapter.verseStarts.contains(where: { $0.verse == verse }) else {
        throw WatchRemoteError.missingVerseTiming
      }
      state["loop"] = mode
      state["lastLoop"] = mode
      state["loopTargetBook"] = chapter.book
      state["loopTargetChapter"] = chapter.chapter
      state["loopTargetVerse"] = verse
      store(state)
    default: break
    }
  }

  private func nextLocation(scope: String? = nil) throws -> (book: Int, chapter: Int, verse: Int) {
    let all = try loadChapters()
    let chapter = try currentChapter()
    guard let index = all.firstIndex(where: { $0.book == chapter.book && $0.chapter == chapter.chapter }) else {
      throw WatchRemoteError.missingRecording
    }
    let mode = scope ?? (state["loop"] as? String ?? "off")
    let targetBook = scope != nil ? chapter.book : (state["loopTargetBook"] as? Int ?? chapter.book)
    let targetChapter = scope != nil ? chapter.chapter : (state["loopTargetChapter"] as? Int ?? chapter.chapter)
    let targetVerse = scope != nil ? (state["verse"] as? Int ?? 1) : (state["loopTargetVerse"] as? Int ?? 1)
    if mode == "verse" {
      let base = targetVerse
      if let next = chapter.verseStarts.first(where: { $0.verse > base }) {
        return (chapter.book, chapter.chapter, next.verse)
      }
    }
    if mode == "book" {
      guard let next = all.first(where: { $0.book > targetBook && $0.chapter == 1 }) else {
        throw WatchRemoteError.endOfBible
      }
      return (next.book, next.chapter, 1)
    }
    if mode == "chapter" {
      guard let next = all.first(where: { $0.book > targetBook || ($0.book == targetBook && $0.chapter > targetChapter) }) else {
        throw WatchRemoteError.endOfBible
      }
      return (next.book, next.chapter, 1)
    }
    guard index + 1 < all.count else { throw WatchRemoteError.endOfBible }
    let next = all[index + 1]
    return (next.book, next.chapter, 1)
  }

  private func previousLocation(scope: String? = nil) throws -> (book: Int, chapter: Int, verse: Int) {
    let all = try loadChapters()
    let chapter = try currentChapter()
    guard let index = all.firstIndex(where: { $0.book == chapter.book && $0.chapter == chapter.chapter }) else {
      throw WatchRemoteError.missingRecording
    }
    let mode = scope ?? (state["loop"] as? String ?? "off")
    let targetBook = scope != nil ? chapter.book : (state["loopTargetBook"] as? Int ?? chapter.book)
    let targetChapter = scope != nil ? chapter.chapter : (state["loopTargetChapter"] as? Int ?? chapter.chapter)
    let targetVerse = scope != nil ? (state["verse"] as? Int ?? 1) : (state["loopTargetVerse"] as? Int ?? 1)
    if mode == "verse" {
      let base = targetVerse
      if let previous = chapter.verseStarts.last(where: { $0.verse < base }) {
        return (chapter.book, chapter.chapter, previous.verse)
      }
    }
    if mode == "book" {
      guard let previous = all.last(where: { $0.book < targetBook && $0.chapter == 1 }) else {
        throw WatchRemoteError.startOfBible
      }
      return (previous.book, previous.chapter, 1)
    }
    if mode == "chapter" {
      guard let previous = all.last(where: { $0.book < targetBook || ($0.book == targetBook && $0.chapter < targetChapter) }) else {
        throw WatchRemoteError.startOfBible
      }
      return (previous.book, previous.chapter, 1)
    }
    guard index > 0 else { throw WatchRemoteError.startOfBible }
    let previous = all[index - 1]
    if mode == "off" { return (previous.book, previous.chapter, 1) }
    guard let lastVerse = previous.verseStarts.last?.verse else {
      throw WatchRemoteError.missingVerseTiming
    }
    return (previous.book, previous.chapter, lastVerse)
  }

  private func playCurrent(shouldPlay: Bool) throws {
    let chapter = try currentChapter()
    let verse = state["verse"] as? Int ?? 1
    guard let start = chapter.verseStarts.first(where: { $0.verse == verse })?.seconds else {
      throw WatchRemoteError.missingVerseTiming
    }
    guard let url = assetPath(chapter.asset).map(URL.init(fileURLWithPath:)) else {
      throw WatchRemoteError.missingRecording
    }
    stopNativePlayer()
    needsOpeningAnnouncements = verse == 1
    try AVAudioSession.sharedInstance().setCategory(.playback, mode: .spokenAudio)
    try AVAudioSession.sharedInstance().setActive(true)
    let item = AVPlayerItem(url: url)
    let newPlayer = AVPlayer(playerItem: item)
    player = newPlayer
    nativePlaybackChanged?(true)
    state["playing"] = false
    state["pending"] = true
    state.removeValue(forKey: "error")
    store(state)
    newPlayer.seek(to: CMTime(seconds: start, preferredTimescale: 1000), toleranceBefore: .zero, toleranceAfter: .zero) { [weak self, weak newPlayer] finished in
      DispatchQueue.main.async {
        guard let self, let newPlayer, self.player === newPlayer else { return }
        self.state["pending"] = false
        var started = false
        if finished && shouldPlay {
          do { try self.playOpeningAnnouncementsThenChapter() }
          catch {
            self.state["error"] = error.localizedDescription
            started = false
          }
          started = self.state["error"] == nil
        }
        self.state["playing"] = started
        if !finished { self.state["error"] = "The iPhone could not seek to that verse." }
        self.store(self.state)
      }
    }
    timeObserver = newPlayer.addPeriodicTimeObserver(forInterval: CMTime(seconds: 0.1, preferredTimescale: 1000), queue: .main) { [weak self] time in
      self?.followPlayback(time.seconds)
    }
    endObserver = NotificationCenter.default.addObserver(forName: .AVPlayerItemDidPlayToEndTime, object: item, queue: .main) { [weak self] _ in
      self?.chapterFinished()
    }
  }

  /// Watch-initiated native playback must use the same saved Qwen cues as the
  /// Flutter reader. A book cue is used at chapter 1, followed by the chapter
  /// cue, before the recorded Scripture begins.
  private func playOpeningAnnouncementsThenChapter() throws {
    guard let chapterPlayer = player else { throw WatchRemoteError.missingRecording }
    let chapter = try currentChapter()
    let verse = state["verse"] as? Int ?? 1
    guard verse == 1 else {
      needsOpeningAnnouncements = false
      chapterPlayer.play()
      return
    }
    pendingAnnouncementURLs = Self.openingAnnouncementAssets(
      book: chapter.book, chapter: chapter.chapter, verse: verse
    ).compactMap { assetPath($0).map(URL.init(fileURLWithPath:)) }
    needsOpeningAnnouncements = false
    guard !pendingAnnouncementURLs.isEmpty else {
      chapterPlayer.play()
      return
    }
    playNextOpeningAnnouncement()
  }

  private func playNextOpeningAnnouncement() {
    if let announcementEndObserver {
      NotificationCenter.default.removeObserver(announcementEndObserver)
      self.announcementEndObserver = nil
    }
    guard !pendingAnnouncementURLs.isEmpty else {
      announcementPlayer = nil
      player?.play()
      return
    }
    let item = AVPlayerItem(url: pendingAnnouncementURLs.removeFirst())
    let cuePlayer = AVPlayer(playerItem: item)
    announcementPlayer = cuePlayer
    announcementEndObserver = NotificationCenter.default.addObserver(
      forName: .AVPlayerItemDidPlayToEndTime, object: item, queue: .main
    ) { [weak self, weak cuePlayer] _ in
      guard let self, self.announcementPlayer === cuePlayer else { return }
      self.playNextOpeningAnnouncement()
    }
    cuePlayer.play()
  }

  static func openingAnnouncementAssets(book: Int, chapter: Int, verse: Int) -> [String] {
    guard (1...66).contains(book), chapter > 0, verse == 1 else { return [] }
    let root = "assets/audio/qwen_loop_cues"
    var assets: [String] = []
    if chapter == 1 {
      assets.append("\(root)/book_\(String(format: "%02d", book)).m4a")
    }
    assets.append("\(root)/chapter_\(String(format: "%03d", chapter)).m4a")
    return assets
  }

  private func followPlayback(_ seconds: Double) {
    guard seconds.isFinite, let chapter = try? currentChapter() else { return }
    let mode = state["loop"] as? String ?? "off"
    if mode == "verse" {
      let target = state["loopTargetVerse"] as? Int ?? 1
      if let index = chapter.verseStarts.firstIndex(where: { $0.verse == target }) {
        let end = index + 1 < chapter.verseStarts.count
          ? chapter.verseStarts[index + 1].seconds : chapter.durationSeconds
        if seconds >= end - 0.03 {
          let start = chapter.verseStarts[index].seconds
          player?.seek(to: CMTime(seconds: start, preferredTimescale: 1000), toleranceBefore: .zero, toleranceAfter: .zero)
        }
      }
      return
    }
    guard let visible = chapter.verseStarts.last(where: { $0.seconds <= seconds }),
          visible.verse != lastReportedVerse else { return }
    lastReportedVerse = visible.verse
    state["verse"] = visible.verse
    state["title"] = "\(Self.bookName(chapter.book)) \(chapter.chapter):\(visible.verse)"
    store(state)
  }

  private func chapterFinished() {
    do {
      let all = try loadChapters()
      let chapter = try currentChapter()
      let mode = state["loop"] as? String ?? "off"
      let targetBook = state["loopTargetBook"] as? Int ?? chapter.book
      let targetChapter = state["loopTargetChapter"] as? Int ?? chapter.chapter
      if mode == "verse" {
        state["book"] = targetBook
        state["chapter"] = targetChapter
        state["verse"] = state["loopTargetVerse"] as? Int ?? 1
      } else if mode == "chapter" {
        state["book"] = targetBook
        state["chapter"] = targetChapter
        state["verse"] = 1
      } else if mode == "book" && all.last(where: { $0.book == targetBook })?.chapter == chapter.chapter {
        state["book"] = targetBook
        state["chapter"] = 1
        state["verse"] = 1
      } else if let next = all.firstIndex(where: { $0.book == chapter.book && $0.chapter == chapter.chapter }).flatMap({ $0 + 1 < all.count ? all[$0 + 1] : nil }) {
        state["book"] = next.book
        state["chapter"] = next.chapter
        state["verse"] = 1
      } else {
        stopNativePlayer()
        state["playing"] = false
        store(state)
        return
      }
      try playCurrent(shouldPlay: true)
    } catch {
      stopNativePlayer()
      state["playing"] = false
      store(state)
    }
  }

  private func stopNativePlayer() {
    if let timeObserver, let player { player.removeTimeObserver(timeObserver) }
    if let endObserver { NotificationCenter.default.removeObserver(endObserver) }
    if let announcementEndObserver { NotificationCenter.default.removeObserver(announcementEndObserver) }
    timeObserver = nil
    endObserver = nil
    announcementEndObserver = nil
    announcementPlayer?.pause()
    announcementPlayer = nil
    pendingAnnouncementURLs = []
    needsOpeningAnnouncements = false
    player?.pause()
    player = nil
    lastReportedVerse = nil
    nativePlaybackChanged?(false)
  }

  private func updateNowPlaying() {
    guard player != nil || (libraryMode && library.hasPlayer) else { return }
    MPNowPlayingInfoCenter.default().playbackState =
      (state["playing"] as? Bool ?? false) ? .playing : .paused
    MPNowPlayingInfoCenter.default().nowPlayingInfo = [
      MPMediaItemPropertyTitle: state["title"] as? String ?? "Bible",
      MPMediaItemPropertyArtist: libraryMode ? "Biblical Heritage eLibrary" : "Biblical Heritage Bible",
      MPNowPlayingInfoPropertyPlaybackRate: (state["playing"] as? Bool ?? false) ? 1.0 : 0.0,
    ]
  }

  private static func bookName(_ number: Int) -> String {
    let names = ["Genesis", "Exodus", "Leviticus", "Numbers", "Deuteronomy", "Joshua", "Judges", "Ruth", "1 Samuel", "2 Samuel", "1 Kings", "2 Kings", "1 Chronicles", "2 Chronicles", "Ezra", "Nehemiah", "Esther", "Job", "Psalms", "Proverbs", "Ecclesiastes", "Song of Solomon", "Isaiah", "Jeremiah", "Lamentations", "Ezekiel", "Daniel", "Hosea", "Joel", "Amos", "Obadiah", "Jonah", "Micah", "Nahum", "Habakkuk", "Zephaniah", "Haggai", "Zechariah", "Malachi", "Matthew", "Mark", "Luke", "John", "Acts", "Romans", "1 Corinthians", "2 Corinthians", "Galatians", "Ephesians", "Philippians", "Colossians", "1 Thessalonians", "2 Thessalonians", "1 Timothy", "2 Timothy", "Titus", "Philemon", "Hebrews", "James", "1 Peter", "2 Peter", "1 John", "2 John", "3 John", "Jude", "Revelation"]
    return (1...names.count).contains(number) ? names[number - 1] : "Book \(number)"
  }
}

private enum WatchRemoteError: LocalizedError {
  case choosePassage, missingRecording, missingVerseTiming, startOfBible, endOfBible
  var errorDescription: String? {
    switch self {
    case .choosePassage: return "Open a Bible passage on the iPhone once before using the Watch remote."
    case .missingRecording: return "The saved Bible recording is unavailable on this iPhone."
    case .missingVerseTiming: return "This verse has no usable position in the saved recording."
    case .startOfBible: return "Already at the beginning of the Bible."
    case .endOfBible: return "Already at the end of the Bible."
    }
  }
}

private struct WatchCatalog: Decodable { let chapters: [WatchChapter] }
private struct WatchChapter: Decodable {
  let book: Int
  let chapter: Int
  let asset: String
  let durationSeconds: Double
  let verseStarts: [WatchVerseStart]
}
private struct WatchVerseStart: Decodable { let verse: Int; let seconds: Double }

// Local Top Shelf audio only. No audio or full book text is transferred to Watch.
private final class WatchLibraryPlayback {
  struct Cue {
    let start: Double
    var end: Double?
    let label: String
  }
  struct Track {
    let chapter: Int
    let title: String
    let url: URL
    let cues: [Cue]
  }
  private let root: URL
  private let defaults: UserDefaults
  var changed: (() -> Void)?
  var readerChanged: (() -> Void)?
  var bookID: String { selectedID }
  var ownershipChanged: ((Bool) -> Void)?
  private(set) var books: [[String: Any]] = []
  private var catalogData: Data?
  private var tracks: [Track] = []
  private var loadedID: String?
  private var loadedManifest: String?
  private var loadedSourceHash: String?
  private var positions: [String: [String: Any]] = [:]
  private var timelineManifest: [String: Any]?
  private var selectedID = ""
  private var chapter = 1
  private var paragraph = 1
  private var position = 0.0
  private var readingRate: Float = 1
  private var loop = "off"
  private var lastLoop = "chapter"
  private var player: AVPlayer?
  private var timeObserver: Any?
  private var boundaryObserver: Any?
  private var endObserver: NSObjectProtocol?
  private var generation = 0
  private var pending = false
  private var playing = false
  var hasPlayer: Bool { player != nil }

  init(root: URL = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0], defaults: UserDefaults = .standard) {
    self.root = root; self.defaults = defaults
    let saved = defaults.dictionary(forKey: "studybible.watchLibrary.v1") ?? [:]
    selectedID = saved["selectedID"] as? String ?? ""
    positions = saved["positions"] as? [String: [String: Any]] ?? [:]
    if let rate = saved["reading_rate"] as? NSNumber, rate.doubleValue.isFinite { readingRate = Float(min(1.5, max(0.75, rate.doubleValue))) }
    loop = saved["loop"] as? String ?? "off"
    lastLoop = saved["lastLoop"] as? String ?? "chapter"
  }

  func refresh() throws {
    let data = try Data(contentsOf: root.appendingPathComponent("watch-audio-shelf.json"))
    guard data != catalogData else { return }
    let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
    guard json?["schema"] as? Int == 1, let supplied = json?["books"] as? [[String: Any]] else { throw LibraryError.unavailable }
    var ids = Set<String>()
    books = supplied.filter { row in
      guard let id = row["id"] as? String, !id.isEmpty, ids.insert(id).inserted,
            row["title"] is String, let relative = row["manifest"] as? String,
            (try? safeManifest(relative)) != nil else { return false }
      return true
    }
    catalogData = data
    if !books.contains(where: { $0["id"] as? String == selectedID }) {
      stopPlayer(); tracks = []; selectedID = books.first?["id"] as? String ?? ""; loadedID = nil; loadedManifest = nil
    }
    if !selectedID.isEmpty { try loadSelected() }
    save()
  }

  private func safeManifest(_ relative: String) throws -> URL {
    guard relative.hasPrefix("elibrary_audio/"), !relative.split(separator: "/").contains("..") else { throw LibraryError.unavailable }
    var url = root.appendingPathComponent(relative).resolvingSymlinksInPath()
    let owned = root.appendingPathComponent("elibrary_audio").resolvingSymlinksInPath().path + "/"
    guard url.path.hasPrefix(owned), url.lastPathComponent == "audio-manifest.json" else { throw LibraryError.unavailable }
    // A cached Watch shelf must follow the verified current managed package,
    // even before the Flutter library screen has refreshed its shelf metadata.
    let folder = url.deletingLastPathComponent().lastPathComponent
    if folder.hasPrefix("bundled-"), folder.count > 73,
       folder.suffix(64).allSatisfy({ $0.isHexDigit && !$0.isUppercase }) {
      let id = String(folder.dropFirst(8).dropLast(65))
      let pointer = root.appendingPathComponent("elibrary_audio/bundled-current.json")
      if let data = try? Data(contentsOf: pointer),
         let current = try? JSONSerialization.jsonObject(with: data) as? [String: String],
         let chosen = current[id], chosen.hasPrefix("bundled-\(id)-"),
         !chosen.contains("/"), !chosen.contains("..") {
        let candidate = root.appendingPathComponent("elibrary_audio/\(chosen)/audio-manifest.json").resolvingSymlinksInPath()
        if candidate.path.hasPrefix(owned), FileManager.default.fileExists(atPath: candidate.path) { url = candidate }
      }
    }
    guard FileManager.default.fileExists(atPath: url.path) else { throw LibraryError.unavailable }
    return url
  }

  private var selected: [String: Any]? { books.first { $0["id"] as? String == selectedID } }
  private var current: Track? { tracks.first { $0.chapter == chapter } }

  private func loadSelected() throws {
    guard let selected, let manifest = selected["manifest"] as? String else { throw LibraryError.unavailable }
    let sourceHash = selected["sourceHash"] as? String
    let file = try safeManifest(manifest)
    if loadedID == selectedID && loadedManifest == file.path && loadedSourceHash == sourceHash {
      adoptPhonePosition(selected)
      return
    }
    stopPlayer()
    tracks = []; loadedID = nil; loadedManifest = nil; loadedSourceHash = nil
    let json = try JSONSerialization.jsonObject(with: Data(contentsOf: file)) as? [String: Any]
    if let required = json?["requires_source_sha256"] as? String {
      guard required == selected["sourceHash"] as? String else { throw LibraryError.edition }
    }
    guard let rows = json?["tracks"] as? [[String: Any]] else { throw LibraryError.unavailable }
    var parsed: [Track] = []
    var seen = Set<Int>()
    for row in rows {
      guard let number = row["chapter"] as? Int, number > 0, seen.insert(number).inserted,
            let name = row["file"] as? String, !name.contains("/"), !name.contains(".."), name.hasSuffix(".mp3") else { continue }
      let url = file.deletingLastPathComponent().appendingPathComponent(name).resolvingSymlinksInPath()
      guard url.deletingLastPathComponent() == file.deletingLastPathComponent(),
            let size = (try? FileManager.default.attributesOfItem(atPath: url.path)[.size]) as? NSNumber, size.intValue > 0 else { continue }
      let raw = row["cues"] as? [[String: Any]] ?? []
      var cues = raw.enumerated().compactMap { pair -> Cue? in
        let (index,cue) = pair
        guard let start = cue["start_ms"] as? NSNumber, start.doubleValue.isFinite, start.doubleValue >= 0 else { return nil }
        let end = (cue["end_ms"] as? NSNumber).map { $0.doubleValue / 1000 }
        return Cue(start: start.doubleValue / 1000, end: end,
                   label: cue["source_refcode"] as? String ?? "Paragraph \(index + 1)")
      }
      cues.sort { $0.start < $1.start }
      if cues.isEmpty { cues = [Cue(start: 0, end: row["duration_seconds"] as? Double, label: "Chapter \(number)")] }
      for i in cues.indices where cues[i].end == nil {
        cues[i].end = i + 1 < cues.count ? cues[i + 1].start : row["duration_seconds"] as? Double
      }
      parsed.append(Track(chapter:number, title:row["title"] as? String ?? "Chapter \(number)", url:url, cues:cues))
    }
    guard !parsed.isEmpty else { throw LibraryError.unavailable }
    tracks = parsed.sorted { $0.chapter < $1.chapter }; loadedID = selectedID; loadedManifest = file.path; loadedSourceHash = sourceHash
    timelineManifest = json
    let saved = remapLibraryAudioPosition(positions[selectedID] ?? [:], manifest: json)
    positions[selectedID] = saved
    chapter = saved["chapter"] as? Int ?? tracks[0].chapter
    if current == nil { chapter = tracks[0].chapter }
    position = max(0, (saved["position_ms"] as? NSNumber)?.doubleValue ?? 0) / 1000
    paragraph = current!.cues.lastIndex(where: { $0.start <= position }).map { $0 + 1 } ?? 1
    adoptPhonePosition(selected)
  }

  private func adoptPhonePosition(_ book: [String: Any]) {
    let revision = book["positionRevision"] as? String ?? ""
    if positions[selectedID]?["phoneRevision"] as? String == revision { return }
    if hasPlayer {
      positions[selectedID, default:[:]]["phoneRevision"] = revision
      return
    }
    if let original = book["position"] as? [String: Any],
       case let saved = remapLibraryAudioPosition(original, manifest: timelineManifest), let c = saved["chapter"] as? Int,
       let track = tracks.first(where: { $0.chapter == c }), let milliseconds = saved["position_ms"] as? NSNumber {
      stopPlayer(); chapter = c; position = max(0, milliseconds.doubleValue / 1000)
      if let rate = saved["reading_rate"] as? NSNumber, rate.doubleValue.isFinite { readingRate = Float(min(1.5, max(0.75, rate.doubleValue))) }
      paragraph = track.cues.lastIndex(where: { $0.start <= position }).map { $0 + 1 } ?? 1
    }
    positions[selectedID, default:[:]]["phoneRevision"] = revision
  }

  func readerSnapshot() -> [String: Any] {
    let duration = player?.currentItem?.duration.seconds ?? 0
    return ["libraryBookID":selectedID, "sourceHash":selected?["sourceHash"] as? String ?? "",
            "chapter":chapter, "verse":paragraph, "position_ms":Int(position * 1000),
            "duration_ms":duration.isFinite && duration > 0 ? Int(duration * 1000) : 0,
            "playing":playing, "pending":pending, "loop":loop, "reading_rate":Double(readingRate)]
  }

  func seekFromReader(chapter c: Int, milliseconds: Int, play: Bool) throws {
    guard let track = tracks.first(where: { $0.chapter == c }), milliseconds >= 0 else { throw LibraryError.location }
    stopPlayer(); chapter = c; position = Double(milliseconds) / 1000
    paragraph = track.cues.lastIndex(where: { $0.start <= position }).map { $0 + 1 } ?? 1
    save(); changed?()
    if play { try start() }
  }

  func snapshot() -> [String: Any] {
    let track = current
    let toc = (selected?["toc"] as? [[String: Any]] ?? []).filter { entry in
      guard let c = entry["chapter"] as? Int, let p = entry["paragraph"] as? Int,
            let t = tracks.first(where: { $0.chapter == c }) else { return false }
      return p > 0 && p <= t.cues.count
    }
    let reference = track?.cues.indices.contains(paragraph - 1) == true ? track!.cues[paragraph - 1].label : ""
    return ["mode":"library", "book":1, "chapter":chapter, "verse":paragraph,
      "chapterCount":tracks.count, "verseCount":track?.cues.count ?? 1,
      "title":"\(selected?["title"] as? String ?? "No Top Shelf audio")\n\(reference)",
      "loop":loop,"lastLoop":lastLoop,"playing":playing,"pending":pending,
      "libraryBookID":selectedID,
      "libraryBooks":books.map { ["id":$0["id"] as? String ?? "", "title":$0["title"] as? String ?? ""] },
      "libraryTOC":toc,
      "libraryParagraphs":(track?.cues.enumerated().map { ["number":$0.offset + 1,"title":$0.element.label] as [String:Any] } ?? [])]
  }

  func perform(_ command: String) throws {
    try refresh()
    if command.hasPrefix("libraryBook:") {
      let id = String(command.dropFirst("libraryBook:".count))
      guard books.contains(where: { $0["id"] as? String == id }) else { throw LibraryError.unavailable }
      save(); stopPlayer(); selectedID = id; loadedID = nil; try loadSelected(); save(); changed?(); return
    }
    try loadSelected()
    if command.hasPrefix("libraryLocation:") {
      let parts = command.split(separator:":")
      guard parts.count == 3, let c = Int(parts[1]), let p = Int(parts[2]) else { throw LibraryError.location }
      try select(chapter:c, paragraph:p, play:false); return
    }
    if command.hasPrefix("chapter:") || command.hasPrefix("verse:") {
      guard let number = Int(command.split(separator:":").last ?? ""), number > 0 else { throw LibraryError.location }
      try select(chapter:command.hasPrefix("chapter:") ? number : chapter,
                 paragraph:command.hasPrefix("verse:") ? number : 1, play:false); return
    }
    if command.hasPrefix("rate:") {
      guard let rate = Float(command.dropFirst(5)), rate.isFinite, (0.75...1.5).contains(rate) else { throw LibraryError.location }
      readingRate = rate
      if playing { player?.rate = rate }
      save(); changed?(); return
    }
    if command.hasPrefix("loop:") {
      let mode = String(command.dropFirst(5)); guard ["off","book","chapter","verse"].contains(mode) else { throw LibraryError.location }
      loop = mode; if mode != "off" { lastLoop = mode }; configureBoundary(); save(); changed?(); return
    }
    if command.hasPrefix("next") || command.hasPrefix("previous") {
      let next = command.hasPrefix("next"); let scope = command.split(separator:":").dropFirst().first.map(String.init) ?? (loop == "off" ? "chapter" : loop)
      if scope == "book" {
        guard let i = books.firstIndex(where: { $0["id"] as? String == selectedID }), books.indices.contains(i + (next ? 1 : -1)) else { throw LibraryError.end }
        let resume = playing; save(); stopPlayer(); selectedID = books[i + (next ? 1 : -1)]["id"] as! String; loadedID = nil; try loadSelected(); try select(chapter:tracks[0].chapter, paragraph:1, play:resume); return
      }
      guard let track = current, let i = tracks.firstIndex(where: { $0.chapter == chapter }) else { throw LibraryError.location }
      if scope == "verse", track.cues.indices.contains(paragraph - 1 + (next ? 1 : -1)) {
        try select(chapter:chapter, paragraph:paragraph + (next ? 1 : -1), play:playing); return
      }
      let j = i + (next ? 1 : -1); guard tracks.indices.contains(j) else { throw LibraryError.end }
      try select(chapter:tracks[j].chapter, paragraph:scope == "verse" && !next ? tracks[j].cues.count : 1, play:playing); return
    }
    switch command {
    case "start": try start()
    case "stop", "pause": pause()
    case "toggle": if playing { pause() } else { try start() }
    default: throw LibraryError.location
    }
  }

  private func select(chapter c: Int, paragraph p: Int, play: Bool) throws {
    guard let track = tracks.first(where: { $0.chapter == c }), track.cues.indices.contains(p - 1) else { throw LibraryError.location }
    stopPlayer(); chapter = c; paragraph = p; position = track.cues[p - 1].start; save(); changed?()
    if play { try start() }
  }

  private func start() throws {
    guard let track = current else { throw LibraryError.unavailable }
    try AVAudioSession.sharedInstance().setCategory(.playback, mode:.spokenAudio)
    try AVAudioSession.sharedInstance().setActive(true)
    if let player { player.playImmediately(atRate:readingRate); playing = true; save(); changed?(); return }
    generation += 1; let token = generation
    let item = AVPlayerItem(url:track.url); item.audioTimePitchAlgorithm = .timeDomain
    let p = AVPlayer(playerItem:item); player = p
    pending = true; ownershipChanged?(true); changed?()
    p.seek(to:CMTime(seconds:position,preferredTimescale:1000),toleranceBefore:.zero,toleranceAfter:.zero) { [weak self,weak p] finished in
      DispatchQueue.main.async {
        guard let self, let p, self.player === p, self.generation == token else { return }
        self.pending = false; self.playing = finished
        if finished { self.configureBoundary(); p.playImmediately(atRate:self.readingRate) }
        self.save(); self.changed?()
      }
    }
    timeObserver = p.addPeriodicTimeObserver(forInterval:CMTime(seconds:0.5,preferredTimescale:1000),queue:.main) { [weak self] time in
      guard let self, self.playing, time.seconds.isFinite, let track = self.current else { return }
      self.position = time.seconds
      self.readerChanged?()
      let next = track.cues.lastIndex(where: { $0.start <= time.seconds }).map { $0 + 1 } ?? 1
      if next != self.paragraph { self.paragraph = next; self.save(); self.changed?() }
    }
    endObserver = NotificationCenter.default.addObserver(forName:.AVPlayerItemDidPlayToEndTime,object:item,queue:.main) { [weak self,weak p] _ in
      guard let self, let p, self.player === p else { return }; self.completed()
    }
  }

  private func configureBoundary() {
    if let boundaryObserver { player?.removeTimeObserver(boundaryObserver); self.boundaryObserver = nil }
    guard loop == "verse", let track = current, track.cues.indices.contains(paragraph - 1) else { return }
    let cue = track.cues[paragraph - 1]
    let end = cue.end ?? player?.currentItem?.duration.seconds
    guard let end, end.isFinite, end > cue.start else { return }
    let c = chapter, p = paragraph
    boundaryObserver = player?.addBoundaryTimeObserver(forTimes:[NSValue(time:CMTime(seconds:end,preferredTimescale:1000))],queue:.main) { [weak self] in
      guard let self, self.playing, self.loop == "verse" else { return }
      do { try self.select(chapter:c,paragraph:p,play:true) } catch { self.pause() }
    }
  }

  private func completed() {
    guard let i = tracks.firstIndex(where: { $0.chapter == chapter }) else { pause(); return }
    do {
      if loop == "verse" { try select(chapter:chapter,paragraph:paragraph,play:true) }
      else if loop == "chapter" { try select(chapter:chapter,paragraph:1,play:true) }
      else if i + 1 < tracks.count { try select(chapter:tracks[i+1].chapter,paragraph:1,play:true) }
      else if loop == "book" { try select(chapter:tracks[0].chapter,paragraph:1,play:true) }
      else { pause() }
    } catch { pause() }
  }

  func pause() {
    if pending { stopPlayer(); save(); changed?(); return }
    generation += 1
    if let time = player?.currentTime().seconds, time.isFinite, !pending { position = time }
    player?.pause(); player?.currentItem?.cancelPendingSeeks(); pending = false; playing = false
    save(); changed?()
    // No keep-awake session, polling timer, or active audio hardware while idle.
    try? AVAudioSession.sharedInstance().setActive(false,options:.notifyOthersOnDeactivation)
  }

  func stopPlayer() {
    generation += 1
    if let timeObserver { player?.removeTimeObserver(timeObserver) }
    if let boundaryObserver { player?.removeTimeObserver(boundaryObserver) }
    if let endObserver { NotificationCenter.default.removeObserver(endObserver) }
    timeObserver = nil; boundaryObserver = nil; endObserver = nil
    player?.pause(); player = nil; playing = false; pending = false; ownershipChanged?(false)
  }

  private func save() {
    if !selectedID.isEmpty {
      let revision = positions[selectedID]?["phoneRevision"] as? String ?? ""
      positions[selectedID] = ["chapter":chapter,"position_ms":Int(position * 1000),"phoneRevision":revision,"reading_rate":Double(readingRate)]
      if let version = timelineManifest?["timeline_version"] as? String { positions[selectedID]?["timeline_version"] = version }
    }
    let saved: [String:Any] = ["selectedID":selectedID,"positions":positions,"loop":loop,"lastLoop":lastLoop,"reading_rate":Double(readingRate)]
    if let old = defaults.dictionary(forKey:"studybible.watchLibrary.v1"), NSDictionary(dictionary:old).isEqual(to:saved) { return }
    defaults.set(saved,forKey:"studybible.watchLibrary.v1")
  }

  private enum LibraryError: LocalizedError {
    case unavailable, edition, location, end
    var errorDescription: String? {
      switch self {
      case .unavailable: return "Open eLibrary on iPhone to refresh Top Shelf books with downloaded audio."
      case .edition: return "The recording does not match this book edition."
      case .location: return "That contents location has no downloaded recording."
      case .end: return "No more downloaded chapters in that direction."
      }
    }
  }
}
