import AVFoundation
import Flutter
import MediaPlayer
import WatchConnectivity

/// Receives immediate Watch commands even when the Flutter reader has not opened.
/// The phone owns playback; the Watch never downloads or speaks Bible audio.
final class WatchRemoteBridge: NSObject, WCSessionDelegate {
  private static let savedStateKey = "studybible.watchRemote.lastState.v1"
  private var channel: FlutterMethodChannel?
  private var readerAttached = false
  private var state: [String: Any]
  private var chapters: [WatchChapter]?
  private var player: AVPlayer?
  private var timeObserver: Any?
  private var endObserver: NSObjectProtocol?
  private var lastReportedVerse: Int?

  override init() {
    state = UserDefaults.standard.dictionary(forKey: Self.savedStateKey) ?? [
      "book": 0, "chapter": 0, "verse": 0, "loop": "off", "lastLoop": "chapter",
      "playing": false, "title": "Open a Bible passage on iPhone",
    ]
    state["playing"] = false // A terminated process cannot still own playback.
    state["pending"] = false
    state.removeValue(forKey: "error")
    super.init()
    if WCSession.isSupported() {
      WCSession.default.delegate = self
      WCSession.default.activate()
    }
  }

  func attach(messenger: FlutterBinaryMessenger) {
    let bridge = FlutterMethodChannel(name: "studybible/watch_remote", binaryMessenger: messenger)
    channel = bridge
    bridge.setMethodCallHandler { [weak self] call, result in
      guard let self else { result(FlutterMethodNotImplemented); return }
      switch call.method {
      case "readerAttached":
        self.readerAttached = true
        result(self.state.merging(["nativePlayback": self.player != nil]) { _, new in new })
      case "readerDetached":
        self.readerAttached = false
        result(nil)
      case "handoffNative":
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
        if flutterPlaying { self.stopNativePlayer() }
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
    state = [
      "book": book, "chapter": chapter, "verse": verse, "loop": loop,
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
      state["chapterCount"] = all.filter { $0.book == book }.map { $0.chapter }.max() ?? 1
      state["verseCount"] = all.first { $0.book == book && $0.chapter == chapter }?.verseStarts.map { $0.verse }.max() ?? 1
    }
    if let error = updated["error"] as? String { state["error"] = error }
    UserDefaults.standard.set(state, forKey: Self.savedStateKey)
    publishToWatch()
    updateNowPlaying()
  }

  private func publishToWatch() {
    guard WCSession.isSupported() else { return }
    let session = WCSession.default
    guard session.activationState == .activated,
          session.isPaired, session.isWatchAppInstalled else { return }
    try? session.updateApplicationContext(state)
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
      if let player, player.currentItem != nil {
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
    try AVAudioSession.sharedInstance().setCategory(.playback, mode: .spokenAudio)
    try AVAudioSession.sharedInstance().setActive(true)
    stopNativePlayer()
    let item = AVPlayerItem(url: url)
    let newPlayer = AVPlayer(playerItem: item)
    player = newPlayer
    state["playing"] = false
    state["pending"] = true
    state.removeValue(forKey: "error")
    store(state)
    newPlayer.seek(to: CMTime(seconds: start, preferredTimescale: 1000), toleranceBefore: .zero, toleranceAfter: .zero) { [weak self, weak newPlayer] finished in
      DispatchQueue.main.async {
        guard let self, let newPlayer, self.player === newPlayer else { return }
        self.state["pending"] = false
        if finished && shouldPlay { newPlayer.play() }
        self.state["playing"] = finished && shouldPlay
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
    timeObserver = nil
    endObserver = nil
    player?.pause()
    player = nil
    lastReportedVerse = nil
  }

  private func updateNowPlaying() {
    guard player != nil else { return }
    MPNowPlayingInfoCenter.default().nowPlayingInfo = [
      MPMediaItemPropertyTitle: state["title"] as? String ?? "Bible",
      MPMediaItemPropertyArtist: "Biblical Heritage Bible",
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
