import AVFoundation
import Flutter
import MediaPlayer
import UIKit

/// Keeps spoken narration alive and controllable while the screen is locked:
/// the playback audio session, Now Playing metadata, the lock screen and
/// Control Center transport buttons, audio interruptions and route loss.
///
/// Dart owns the playlist. This bridge only reports what the system did
/// ("command", "interruptionBegan", "interruptionEnded", "routeLost") and
/// mirrors what Dart tells it ("updateNowPlaying", "setBuffering").
final class NarrationMediaBridge: NSObject {
  private let channel: FlutterMethodChannel
  /// Read-only telemetry for the Dart synthesis probe (`NarrationTelemetry`).
  private var recordedAudio: RecordedBibleAudioBridge?
  private let probeChannel: FlutterMethodChannel
  private var active = false
  private var commandTargets: [(MPRemoteCommand, Any)] = []
  private var observers: [NSObjectProtocol] = []
  private var backgroundTask: UIBackgroundTaskIdentifier = .invalid

  init(registrar: FlutterPluginRegistrar) {
    channel = FlutterMethodChannel(
      name: "studybible/narration_media",
      binaryMessenger: registrar.messenger()
    )
    probeChannel = FlutterMethodChannel(
      name: "studybible/narration_probe",
      binaryMessenger: registrar.messenger()
    )
    super.init()
    recordedAudio = RecordedBibleAudioBridge(registrar: registrar)
    probeChannel.setMethodCallHandler { call, result in
      guard call.method == "sample" else {
        result(FlutterMethodNotImplemented)
        return
      }
      let threads = (call.arguments as? [String: Any])?["threads"] as? Bool ?? false
      result(NarrationTelemetry.snapshot(threads: threads))
    }
    // Playback ignores the ringer switch and (with the "audio" background
    // mode) survives screen lock. spokenAudio lets other spoken audio, such as
    // a navigation prompt, pause us instead of talking over us. No
    // mixWithOthers: that would make the app ineligible for Now Playing.
    configureSession()
    channel.setMethodCallHandler { [weak self] call, result in
      self?.handle(call, result: result)
    }
  }

  private func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    switch call.method {
    case "keepReaderAwake":
      UIApplication.shared.isIdleTimerDisabled = call.arguments as? Bool ?? false
    case "begin":
      begin()
    case "end":
      end()
    case "updateNowPlaying":
      if let arguments = call.arguments as? [String: Any] { updateNowPlaying(arguments) }
    case "setBuffering":
      dartBuffering = call.arguments as? Bool ?? false
      refreshBackgroundTask()
    case "activate":
      result(activateSession(reason: "dart request"))
      return
    default:
      result(FlutterMethodNotImplemented)
      return
    }
    result(nil)
  }

  /// Every failure here is reported to the Dart event log with the error code
  /// so a session that could not be set up is never silent.
  @discardableResult
  private func configureSession() -> Bool {
    do {
      try AVAudioSession.sharedInstance().setCategory(
        .playback, mode: .spokenAudio, options: [])
      return true
    } catch {
      report("setCategory FAILED \(describe(error)) \(sessionSummary())")
      return false
    }
  }

  /// Asserts our category and activates the session. audioplayers
  /// deactivates the session whenever nothing is playing, and only `begin`
  /// used to bring it back, so a resume after a long pause started with an
  /// inactive session. Returns false if iOS refused.
  private func activateSession(reason: String) -> Bool {
    let configured = configureSession()
    do {
      try AVAudioSession.sharedInstance().setActive(true)
      return configured
    } catch {
      report("activate FAILED (\(reason)) \(describe(error)) \(sessionSummary())")
      return false
    }
  }

  private func describe(_ error: Error) -> String {
    let nsError = error as NSError
    return "code=\(nsError.code) domain=\(nsError.domain) \(nsError.localizedDescription)"
  }

  private func begin() {
    // audioplayers may have reset the session; assert ours on every start.
    let activated = activateSession(reason: "begin")
    report("begin activated=\(activated) \(sessionSummary())")
    guard !active else { return }
    active = true
    registerCommands()
    observeSession()
    startCPUSampling()
  }

  private func end() {
    guard active else { return }
    active = false
    for (command, target) in commandTargets {
      command.removeTarget(target)
      command.isEnabled = false
    }
    commandTargets.removeAll()
    for observer in observers { NotificationCenter.default.removeObserver(observer) }
    observers.removeAll()
    stopCPUSampling()
    MPNowPlayingInfoCenter.default().nowPlayingInfo = nil
    MPNowPlayingInfoCenter.default().playbackState = .stopped
    dartBuffering = false
    commandHold = false
    refreshBackgroundTask()
    // Fails harmlessly while a player is still winding down; audioplayers
    // deactivates the session itself when its last player stops.
    do {
      try AVAudioSession.sharedInstance().setActive(
        false, options: .notifyOthersOnDeactivation)
    } catch {
      report("end: deactivate skipped \(describe(error))")
    }
  }

  // MARK: Lock screen and Control Center

  private func registerCommands() {
    let center = MPRemoteCommandCenter.shared()
    let commands: [(MPRemoteCommand, String)] = [
      (center.playCommand, "play"),
      (center.pauseCommand, "pause"),
      (center.togglePlayPauseCommand, "toggle"),
      (center.nextTrackCommand, "next"),
      (center.previousTrackCommand, "previous"),
    ]
    for (command, name) in commands {
      command.isEnabled = true
      let target = command.addTarget { [weak self] _ in
        DispatchQueue.main.async {
          // A play from the lock screen wakes a suspended app for only a
          // moment. Hold background time now rather than after Dart has
          // scheduled its own request, so the first clip can be finished.
          if name == "play" || name == "toggle" { self?.holdForCommand() }
          self?.channel.invokeMethod("command", arguments: name)
        }
        return .success
      }
      commandTargets.append((command, target))
    }
    // Speech has no meaningful scrub position or fixed skip interval.
    center.skipForwardCommand.isEnabled = false
    center.skipBackwardCommand.isEnabled = false
    center.seekForwardCommand.isEnabled = false
    center.seekBackwardCommand.isEnabled = false
    center.changePlaybackPositionCommand.isEnabled = false
  }

  private func updateNowPlaying(_ arguments: [String: Any]) {
    let playing = arguments["playing"] as? Bool ?? false
    var info: [String: Any] = [
      MPMediaItemPropertyTitle: arguments["title"] as? String ?? "",
      MPNowPlayingInfoPropertyMediaType: MPNowPlayingInfoMediaType.audio.rawValue,
      MPNowPlayingInfoPropertyPlaybackRate: playing ? 1.0 : 0.0,
      MPNowPlayingInfoPropertyDefaultPlaybackRate: 1.0,
    ]
    if let subtitle = arguments["subtitle"] as? String { info[MPMediaItemPropertyArtist] = subtitle }
    if let album = arguments["album"] as? String { info[MPMediaItemPropertyAlbumTitle] = album }
    if let index = arguments["index"] as? Int, let count = arguments["count"] as? Int {
      info[MPNowPlayingInfoPropertyPlaybackQueueIndex] = index
      info[MPNowPlayingInfoPropertyPlaybackQueueCount] = count
    }
    let center = MPNowPlayingInfoCenter.default()
    center.nowPlayingInfo = info
    center.playbackState = playing ? .playing : .paused
  }

  // MARK: Interruptions

  private func observeSession() {
    let center = NotificationCenter.default
    let session = AVAudioSession.sharedInstance()
    observers.append(
      center.addObserver(
        forName: AVAudioSession.interruptionNotification, object: session, queue: .main
      ) { [weak self] note in self?.interruption(note) })
    observers.append(
      center.addObserver(
        forName: AVAudioSession.routeChangeNotification, object: session, queue: .main
      ) { [weak self] note in self?.routeChange(note) })
  }

  private func interruption(_ note: Notification) {
    guard let info = note.userInfo,
      let raw = info[AVAudioSessionInterruptionTypeKey] as? UInt,
      let type = AVAudioSession.InterruptionType(rawValue: raw)
    else {
      report("interruption notification without a usable type")
      return
    }
    switch type {
    case .began:
      let reasonRaw = info[AVAudioSessionInterruptionReasonKey] as? UInt
      report("interruption began reason=\(reasonRaw.map(String.init) ?? "none") \(sessionSummary())")
      // "App was suspended" is the system reporting our own idle state, not
      // a call, Siri or another app taking the speaker.
      if let reasonRaw = reasonRaw,
        AVAudioSession.InterruptionReason(rawValue: reasonRaw) == .appWasSuspended
      {
        return
      }
      channel.invokeMethod("interruptionBegan", arguments: nil)
    case .ended:
      let optionsRaw = info[AVAudioSessionInterruptionOptionKey] as? UInt ?? 0
      let shouldResume = AVAudioSession.InterruptionOptions(rawValue: optionsRaw)
        .contains(.shouldResume)
      report("interruption ended options=\(optionsRaw) shouldResume=\(shouldResume) \(sessionSummary())")
      if shouldResume { _ = activateSession(reason: "interruption ended") }
      channel.invokeMethod("interruptionEnded", arguments: ["shouldResume": shouldResume])
    @unknown default:
      report("interruption of unknown type \(raw)")
    }
  }

  /// Headphones or a Bluetooth speaker went away: pause rather than blurt the
  /// rest of the playlist out of the phone speaker.
  private func routeChange(_ note: Notification) {
    guard let raw = note.userInfo?[AVAudioSessionRouteChangeReasonKey] as? UInt else { return }
    let reason = AVAudioSession.RouteChangeReason(rawValue: raw)
    let previous = (note.userInfo?[AVAudioSessionRouteChangePreviousRouteKey]
      as? AVAudioSessionRouteDescription)?.outputs.map { $0.portType.rawValue }
      .joined(separator: ",") ?? "none"
    report("route change reason=\(raw) previous=\(previous) \(sessionSummary())")
    guard reason == .oldDeviceUnavailable else { return }
    channel.invokeMethod("routeLost", arguments: nil)
  }

  // MARK: Diagnostics

  /// One line for the narration event log on the Dart side. Logging only; it
  /// never changes behavior.
  private func report(_ text: String) {
    channel.invokeMethod("diagnostic", arguments: text)
  }

  private func sessionSummary() -> String {
    let session = AVAudioSession.sharedInstance()
    let outputs = session.currentRoute.outputs.map { $0.portType.rawValue }
      .joined(separator: ",")
    return "[category=\(session.category.rawValue) mode=\(session.mode.rawValue) "
      + "options=\(session.categoryOptions.rawValue) out=\(outputs) "
      + "otherAudioPlaying=\(session.isOtherAudioPlaying)]"
  }

  // iOS kills a backgrounded app that averages more than 80% of a core over
  // 60 s (`cpu_resource_fatal`). Speech synthesis is that heavy, so meter it.
  private var cpuTimer: Timer?
  private var cpuSamples: [(wall: Date, cpu: Double)] = []

  private func startCPUSampling() {
    stopCPUSampling()
    NarrationTelemetry.startMonitoring { [weak self] in self?.report($0) }
    cpuSamples = [(Date(), processCPUSeconds())]
    cpuTimer = Timer.scheduledTimer(withTimeInterval: 15, repeats: true) { [weak self] _ in
      self?.sampleCPU()
    }
  }

  private func stopCPUSampling() {
    cpuTimer?.invalidate()
    cpuTimer = nil
    cpuSamples.removeAll()
    NarrationTelemetry.stopMonitoring()
  }

  private func sampleCPU() {
    let now = (wall: Date(), cpu: processCPUSeconds())
    cpuSamples.append(now)
    cpuSamples.removeAll { now.wall.timeIntervalSince($0.wall) > 65 }
    func percent(since sample: (wall: Date, cpu: Double)) -> Int {
      let wall = now.wall.timeIntervalSince(sample.wall)
      return wall > 0 ? Int(((now.cpu - sample.cpu) / wall * 100).rounded()) : 0
    }
    guard cpuSamples.count >= 2 else { return }
    let state: String
    switch UIApplication.shared.applicationState {
    case .active: state = "active"
    case .inactive: state = "inactive"
    case .background: state = "background"
    @unknown default: state = "unknown"
    }
    report(
      "cpu \(percent(since: cpuSamples[cpuSamples.count - 2]))% last 15s, "
        + "\(percent(since: cpuSamples[0]))% over \(Int(now.wall.timeIntervalSince(cpuSamples[0].wall)))s, "
        + "app=\(state) \(NarrationTelemetry.stateSummary())")
  }

  private func processCPUSeconds() -> Double { NarrationTelemetry.processCPUSeconds() }

  // MARK: Background time

  private var dartBuffering = false
  private var commandHold = false

  /// While the next clip is still being synthesized nothing is audible, so iOS
  /// may suspend a locked app. A background task buys the time (about 30 s)
  /// to finish that clip and start it. It is held while Dart reports
  /// buffering, and for a short while after a lock screen play command.
  private func refreshBackgroundTask() {
    if dartBuffering || commandHold {
      guard backgroundTask == .invalid else { return }
      backgroundTask = UIApplication.shared.beginBackgroundTask(
        withName: "narration-synthesis"
      ) { [weak self] in
        self?.report("background task expired remaining=\(Self.remainingText())")
        self?.endBackgroundTask()
      }
      if backgroundTask == .invalid {
        report("beginBackgroundTask refused")
      } else {
        report("background task started remaining=\(Self.remainingText())")
      }
    } else {
      endBackgroundTask()
    }
  }

  /// Seconds iOS says are left before it suspends the app, or "unlimited"
  /// while the app is in the foreground.
  private static func remainingText() -> String {
    let remaining = UIApplication.shared.backgroundTimeRemaining
    return remaining > 1_000_000 ? "unlimited" : String(format: "%.1fs", remaining)
  }

  private func holdForCommand() {
    commandHold = true
    refreshBackgroundTask()
    DispatchQueue.main.asyncAfter(deadline: .now() + 25) { [weak self] in
      self?.commandHold = false
      self?.refreshBackgroundTask()
    }
  }

  private func endBackgroundTask() {
    guard backgroundTask != .invalid else { return }
    UIApplication.shared.endBackgroundTask(backgroundTask)
    backgroundTask = .invalid
  }
}


final class RecordedBibleAudioBridge: NSObject, AVAudioPlayerDelegate {
  private let channel: FlutterMethodChannel
  private let engine: AVAudioEngine
  private let playerNode: AVAudioPlayerNode
  private let timePitch: AVAudioUnitTimePitch
  private var audioFile: AVAudioFile?
  private var savedFrame: Int64 = 0
  private var lastReportedFrame: Int64 = 0
  private var playing = false
  private var generation = 0
  private var rate: Double = 1.0
  private var pitchSemitones: Double = 0.0
  private var loopStartFrame: Int64?
  private var loopEndFrame: Int64?
  private var loopCuePath: String?
  private struct AnnouncementEvent {
    let frame: Int64
    let paths: [String]
  }
  private var announcementEvents: [AnnouncementEvent] = []
  private var announceOnNextPlay = false
  private var announcementCuesStarted = 0
  private var announcementCuesCompleted = 0
  private var announcementCueErrors = 0
  private var cuePlayer: AVAudioPlayer?
  private var cueCompletion: (() -> Void)?
  private var cueResult: FlutterResult?
  private var cueIsLoop = false
  private var mixerTapInstalled = false
  private var mixerTapBuffers = 0
  private var mixerRmsDb: Double = -999
  private var routeObservers: [NSObjectProtocol] = []
  private var pendingRouteRebuild: DispatchWorkItem?
  private var connectedRoute = ""
  private var needsGraphRebuild = false
  private var interrupted = false

  init(registrar: FlutterPluginRegistrar) {
    channel = FlutterMethodChannel(name: "studybible/recorded_audio", binaryMessenger: registrar.messenger())
    engine = AVAudioEngine()
    playerNode = AVAudioPlayerNode()
    timePitch = AVAudioUnitTimePitch()
    super.init()
    channel.setMethodCallHandler { [weak self] call, result in
      guard let self = self else { result(nil); return }
      self.onMethodCall(call, result: result)
    }
    engine.attach(playerNode)
    engine.attach(timePitch)
    let center = NotificationCenter.default
    routeObservers.append(center.addObserver(
      forName: AVAudioSession.routeChangeNotification,
      object: AVAudioSession.sharedInstance(), queue: .main
    ) { [weak self] note in self?.handleRouteChange(note) })
    routeObservers.append(center.addObserver(
      forName: .AVAudioEngineConfigurationChange,
      object: engine, queue: .main
    ) { [weak self] _ in self?.handleEngineConfigurationChange() })
    routeObservers.append(center.addObserver(
      forName: AVAudioSession.interruptionNotification,
      object: AVAudioSession.sharedInstance(), queue: .main
    ) { [weak self] note in self?.handleInterruption(note) })
  }

  deinit {
    pendingRouteRebuild?.cancel()
    for observer in routeObservers { NotificationCenter.default.removeObserver(observer) }
    cuePlayer?.stop()
    engine.stop()
  }

  private func cancelCue() {
    let pending = cueResult
    cueCompletion = nil
    cueResult = nil
    let player = cuePlayer
    cuePlayer = nil
    cueIsLoop = false
    player?.stop()
    pending?(FlutterError(code: "CANCELLED", message: "Announcement interrupted", details: nil))
  }

  private func playCue(_ path: String, result: FlutterResult? = nil,
                       loopCue: Bool = false,
                       then continuation: @escaping () -> Void) throws {
    cancelCue()
    let session = AVAudioSession.sharedInstance()
    try session.setCategory(.playback, mode: .spokenAudio, options: [])
    try session.setActive(true)
    let player = try AVAudioPlayer(contentsOf: URL(fileURLWithPath: path))
    player.delegate = self
    cuePlayer = player
    cueResult = result
    cueCompletion = continuation
    cueIsLoop = loopCue
    guard player.prepareToPlay(), player.play() else {
      cuePlayer = nil
      cueResult = nil
      cueCompletion = nil
      cueIsLoop = false
      throw NSError(domain: "RecordedAudio", code: 5,
                    userInfo: [NSLocalizedDescriptionKey: "Qwen announcement could not play"])
    }
    announcementCuesStarted += 1
    print("Qwen announcement started: \(URL(fileURLWithPath: path).lastPathComponent)")
  }

  private func playCueSequence(_ paths: [String], result: FlutterResult? = nil,
                               then continuation: @escaping () -> Void) {
    guard let path = paths.first else { continuation(); return }
    do {
      try playCue(path, result: result, loopCue: true) { [weak self] in
        guard let self = self else { return }
        self.playCueSequence(Array(paths.dropFirst()), result: result, then: continuation)
      }
    } catch {
      result?(FlutterError(code: "ERROR", message: error.localizedDescription, details: nil))
      channel.invokeMethod("error", arguments: "Qwen announcement failed: \(error.localizedDescription)")
    }
  }

  private func eventAt(_ frame: Int64) -> AnnouncementEvent? {
    announcementEvents.first { $0.frame == frame }
  }

  func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
    guard cuePlayer === player else { return }
    let continuation = cueCompletion
    let pending = cueResult
    let wasLoop = cueIsLoop
    cueCompletion = nil
    cueResult = nil
    cuePlayer = nil
    cueIsLoop = false
    if flag {
      announcementCuesCompleted += 1
      print("Qwen announcement completed")
      continuation?()
    } else {
      announcementCueErrors += 1
      let error = "Qwen announcement playback failed"
      pending?(FlutterError(code: "ERROR", message: error, details: nil))
      if wasLoop { channel.invokeMethod("error", arguments: error) }
    }
  }

  func audioPlayerDecodeErrorDidOccur(_ player: AVAudioPlayer, error: Error?) {
    guard cuePlayer === player else { return }
    let pending = cueResult
    let wasLoop = cueIsLoop
    cueCompletion = nil
    cueResult = nil
    cuePlayer = nil
    cueIsLoop = false
    let message = "Qwen announcement decode failed: \(error?.localizedDescription ?? "unknown error")"
    announcementCueErrors += 1
    pending?(FlutterError(code: "ERROR", message: message, details: nil))
    if wasLoop { channel.invokeMethod("error", arguments: message) }
  }

  private func routeSignature() -> String {
    let session = AVAudioSession.sharedInstance()
    let outputs = session.currentRoute.outputs.map { "\($0.portType.rawValue):\($0.uid)" }
      .joined(separator: ",")
    return "\(outputs):\(session.sampleRate)"
  }

  private func handleRouteChange(_ note: Notification) {
    guard let raw = note.userInfo?[AVAudioSessionRouteChangeReasonKey] as? UInt else { return }
    let reason = AVAudioSession.RouteChangeReason(rawValue: raw)
    if reason != .oldDeviceUnavailable &&
       routeSignature() == connectedRoute && engine.isRunning {
      return
    }
    needsGraphRebuild = true
    if reason == .oldDeviceUnavailable {
      // A disconnected headset must not make narration burst from the speaker.
      cancelCue()
      if playing { try? handlePause(result: { _ in }) }
      return
    }
    scheduleRouteRebuild()
  }

  private func handleEngineConfigurationChange() {
    guard playing else {
      needsGraphRebuild = true
      return
    }
    if connectedRoute != routeSignature() || !engine.isRunning {
      needsGraphRebuild = true
      scheduleRouteRebuild()
    }
  }

  private func handleInterruption(_ note: Notification) {
    guard let raw = note.userInfo?[AVAudioSessionInterruptionTypeKey] as? UInt,
          let kind = AVAudioSession.InterruptionType(rawValue: raw) else { return }
    if kind == .began {
      interrupted = true
      needsGraphRebuild = true
      cancelCue()
      if playing { try? handlePause(result: { _ in }) }
    } else if kind == .ended {
      interrupted = false
      needsGraphRebuild = true
      // The Dart media lease decides whether interruption playback resumes.
    }
  }

  private func scheduleRouteRebuild() {
    pendingRouteRebuild?.cancel()
    let work = DispatchWorkItem { [weak self] in self?.restoreAfterRouteChange() }
    pendingRouteRebuild = work
    DispatchQueue.main.asyncAfter(deadline: .now() + 0.3, execute: work)
  }

  private func restoreAfterRouteChange() {
    pendingRouteRebuild = nil
    guard let file = audioFile, needsGraphRebuild else { return }
    let wasPlaying = playing
    let frame = max(lastReportedFrame, currentFrame())
    generation += 1
    playing = false
    playerNode.stop()
    savedFrame = min(frame, file.length)
    lastReportedFrame = savedFrame
    connectGraph(file)
    if wasPlaying && !interrupted {
      do {
        try handlePlay(result: { _ in })
      } catch {
        channel.invokeMethod("error", arguments: "Audio route restart failed: \(error.localizedDescription)")
      }
    }
  }

  private func onMethodCall(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    if call.method == "exportSegments" {
      DispatchQueue.global(qos: .userInitiated).async {
        do {
          try Self.exportSegments(call.arguments)
          DispatchQueue.main.async { result(nil) }
        } catch {
          DispatchQueue.main.async {
            result(FlutterError(code: "QWEN_EXPORT", message: error.localizedDescription, details: nil))
          }
        }
      }
      return
    }
    DispatchQueue.main.async { [weak self] in
      guard let self = self else { return }
      do {
        switch call.method {
        case "load":
          try self.handleLoad(call: call, result: result)
        case "play":
          let cuePath = (call.arguments as? [String: Any])?["cuePath"] as? String
          let announceAtStart = ((call.arguments as? [String: Any])?["announceAtStart"] as? Bool ?? false) || self.announceOnNextPlay
          self.announceOnNextPlay = false
          if announceAtStart, let event = self.eventAt(self.savedFrame), !self.playing {
            let expectedGeneration = self.generation
            self.playCueSequence(event.paths, result: result) { [weak self] in
              guard let self = self, self.generation == expectedGeneration else {
                result(FlutterError(code: "CANCELLED", message: "Playback changed during announcement", details: nil))
                return
              }
              do { try self.handlePlay(result: result) }
              catch { result(FlutterError(code: "ERROR", message: error.localizedDescription, details: nil)) }
            }
          } else if let path = cuePath?.trimmingCharacters(in: .whitespacesAndNewlines),
             !path.isEmpty, !self.playing {
            let expectedGeneration = self.generation
            try self.playCue(path, result: result) { [weak self] in
              guard let self = self, self.generation == expectedGeneration else {
                result(FlutterError(code: "CANCELLED", message: "Playback changed during announcement", details: nil))
                return
              }
              do { try self.handlePlay(result: result) }
              catch { result(FlutterError(code: "ERROR", message: error.localizedDescription, details: nil)) }
            }
          } else {
            try self.handlePlay(result: result)
          }
        case "pause":
          try self.handlePause(result: result)
        case "seek":
          try self.handleSeek(call: call, result: result)
        case "stop":
          self.handleStop(result: result)
        case "setRate":
          try self.handleSetRate(call: call, result: result)
        case "setPitch":
          try self.handleSetPitch(call: call, result: result)
        case "setLoopRange":
          try self.handleSetLoopRange(call: call, result: result)
        case "setAnnouncementEvents":
          try self.handleSetAnnouncementEvents(call: call, result: result)
        case "state":
          result(self.handleState())
        default:
          result(FlutterMethodNotImplemented)
        }
      } catch {
        result(FlutterError(code: "ERROR", message: error.localizedDescription, details: nil))
      }
    }
  }

  private func handleLoad(call: FlutterMethodCall, result: FlutterResult) throws {
    guard let args = call.arguments as? [String: Any],
          let path = args["path"] as? String
    else { throw NSError(domain: "InvalidArgs", code: 1, userInfo: [NSLocalizedDescriptionKey: "Invalid path"]) }

    let file = try AVAudioFile(forReading: URL(fileURLWithPath: path))
    guard file.length > 0 else { throw NSError(domain:"RecordedAudio",code:3,userInfo:[NSLocalizedDescriptionKey:"Empty recording"]) }
    pendingRouteRebuild?.cancel()
    pendingRouteRebuild = nil
    cancelCue()
    stopPrior()
    connectGraph(file)
    audioFile = file
    savedFrame = 0
    lastReportedFrame = 0
    loopStartFrame = nil
    loopEndFrame = nil
    loopCuePath = nil
    announcementEvents = []
    announceOnNextPlay = false
    announcementCuesStarted = 0
    announcementCuesCompleted = 0
    announcementCueErrors = 0
    result(nil)
  }

  private func connectGraph(_ file: AVAudioFile) {
    engine.stop()
    if mixerTapInstalled {
      engine.mainMixerNode.removeTap(onBus: 0)
      mixerTapInstalled = false
    }
    engine.disconnectNodeOutput(playerNode)
    engine.disconnectNodeOutput(timePitch)
    engine.connect(playerNode, to: timePitch, format: file.processingFormat)
    engine.connect(timePitch, to: engine.mainMixerNode, format: file.processingFormat)
    mixerRmsDb = -999
    mixerTapBuffers = 0
    engine.mainMixerNode.installTap(onBus: 0, bufferSize: 1024, format: nil) { [weak self] buffer, _ in
      guard let self = self, let channels = buffer.floatChannelData else { return }
      self.mixerTapBuffers += 1
      guard self.mixerTapBuffers % 50 == 0 else { return }
      let frames = Int(buffer.frameLength)
      let channelCount = Int(buffer.format.channelCount)
      guard frames > 0 && channelCount > 0 else { return }
      var power = 0.0
      for channel in 0..<channelCount {
        for index in 0..<frames {
          let sample = Double(channels[channel][index])
          power += sample * sample
        }
      }
      let rms = sqrt(power / Double(frames * channelCount))
      let decibels = 20 * log10(max(rms, 1e-9))
      DispatchQueue.main.async { [weak self] in self?.mixerRmsDb = decibels }
    }
    mixerTapInstalled = true
    connectedRoute = routeSignature()
    needsGraphRebuild = false
  }

  private func handlePlay(result: FlutterResult) throws {
    if playing { result(nil); return }
    guard let file = audioFile else { throw NSError(domain: "NoFile", code: 2, userInfo: [NSLocalizedDescriptionKey: "No file loaded"]) }
    let loopEnd = min(loopEndFrame ?? file.length, file.length)
    if savedFrame >= loopEnd { savedFrame = loopStartFrame ?? 0 }
    // Stop at the next measured verse boundary only when it carries a cue.
    // A loop ending at that same boundary wins, so the next verse is never
    // announced just before repeating the previous verse.
    let nextEvent = announcementEvents.first {
      $0.frame > savedFrame && $0.frame < loopEnd
    }
    let endFrame = nextEvent?.frame ?? loopEnd
    let remaining = endFrame - savedFrame
    guard remaining > 0 && remaining <= Int64(UInt32.max) else { throw NSError(domain:"RecordedAudio",code:4,userInfo:[NSLocalizedDescriptionKey:"Invalid recording length"]) }
    let session = AVAudioSession.sharedInstance()
    try session.setCategory(.playback, mode: .spokenAudio, options: [])
    try session.setActive(true)
    if needsGraphRebuild || connectedRoute != routeSignature() {
      connectGraph(file)
    }
    generation += 1
    playerNode.stop()

    let gen = generation
    playerNode.scheduleSegment(file, startingFrame: AVAudioFramePosition(savedFrame), frameCount: AVAudioFrameCount(remaining), at: nil, completionCallbackType: .dataPlayedBack) { [weak self] _ in
      DispatchQueue.main.async { [weak self] in
        guard let self = self, self.generation == gen, self.playing else { return }
        self.savedFrame = endFrame
        self.lastReportedFrame = endFrame
        self.playing = false
        self.engine.pause()
        if let event = nextEvent {
          self.playCueSequence(event.paths) { [weak self] in
            guard let self = self, self.generation == gen else { return }
            do { try self.handlePlay(result: { _ in }) }
            catch { self.channel.invokeMethod("error", arguments: "Announcement resume failed: \(error.localizedDescription)") }
          }
        } else if let loopStart = self.loopStartFrame, self.loopEndFrame != nil {
          self.savedFrame = loopStart
          self.lastReportedFrame = loopStart
          let restart = { [weak self] in
            guard let self = self, self.generation == gen else { return }
            do {
              try self.handlePlay(result: { _ in })
              self.channel.invokeMethod("looped", arguments: nil)
            } catch {
              self.channel.invokeMethod("error", arguments: "Repeat failed: \(error.localizedDescription)")
            }
          }
          var paths = self.eventAt(loopStart)?.paths ?? []
          if let path = self.loopCuePath, !path.isEmpty { paths.append(path) }
          self.playCueSequence(paths, then: restart)
        } else {
          self.channel.invokeMethod("complete", arguments: nil)
        }
      }
    }

    engine.prepare()
    try engine.start()
    playerNode.play()
    playing = true
    result(nil)
  }

  private func handlePause(result: FlutterResult) throws {
    if cueCompletion != nil {
      cancelCue()
      generation += 1
      result(nil)
      return
    }
    guard playing else { result(nil); return }
    savedFrame = currentFrame()
    lastReportedFrame = savedFrame
    generation += 1
    playerNode.stop()
    engine.pause()
    playing = false
    result(nil)
  }

  private func handleSeek(call: FlutterMethodCall, result: FlutterResult) throws {
    guard let args = call.arguments as? [String: Any],
          let seconds = args["seconds"] as? Double,
          seconds.isFinite, seconds >= 0,
          let file = audioFile
    else { throw NSError(domain: "InvalidArgs", code: 1, userInfo: [NSLocalizedDescriptionKey: "Invalid seconds"]) }

    let wasPlaying = playing
    let announceAtTarget = args["announceAtTarget"] as? Bool ?? false
    if wasPlaying { try handlePause(result: { _ in }) }

    let duration = Double(file.length) / file.processingFormat.sampleRate
    let targetFrame = Int64(min(seconds, duration) * file.processingFormat.sampleRate)
    savedFrame = max(0, targetFrame)
    lastReportedFrame = savedFrame

    if wasPlaying && savedFrame < file.length {
      if announceAtTarget, let event = eventAt(savedFrame) {
        let expectedGeneration = generation
        playCueSequence(event.paths) { [weak self] in
          guard let self = self, self.generation == expectedGeneration else { return }
          do { try self.handlePlay(result: { _ in }) }
          catch { self.channel.invokeMethod("error", arguments: "Verse seek failed: \(error.localizedDescription)") }
        }
      } else {
        try handlePlay(result: { _ in })
      }
    } else {
      announceOnNextPlay = announceAtTarget
    }
    result(nil)
  }

  private func handleStop(result: FlutterResult) {
    pendingRouteRebuild?.cancel()
    pendingRouteRebuild = nil
    cancelCue()
    generation += 1
    playerNode.stop()
    engine.stop()
    audioFile = nil
    savedFrame = 0
    lastReportedFrame = 0
    playing = false
    loopStartFrame = nil
    loopEndFrame = nil
    loopCuePath = nil
    announcementEvents = []
    announceOnNextPlay = false
    result(nil)
  }

  private func handleSetAnnouncementEvents(call: FlutterMethodCall, result: FlutterResult) throws {
    guard let file = audioFile,
          let args = call.arguments as? [String: Any],
          let rows = args["events"] as? [Any] else {
      throw NSError(domain: "InvalidArgs", code: 1,
                    userInfo: [NSLocalizedDescriptionKey: "Invalid announcement events"])
    }
    let sampleRate = file.processingFormat.sampleRate
    var events: [AnnouncementEvent] = []
    for value in rows {
      // Flutter's standard codec bridges each Dart map through NSDictionary;
      // the nonempty collection need not cast directly to [[String: Any]].
      guard let row = value as? [AnyHashable: Any],
            let seconds = row["seconds"] as? Double,
            let paths = row["paths"] as? [String],
            seconds.isFinite, seconds >= 0,
            seconds <= Double(file.length) / sampleRate + 0.05,
            !paths.isEmpty else {
        throw NSError(domain: "InvalidArgs", code: 1,
                      userInfo: [NSLocalizedDescriptionKey: "Invalid announcement boundary"])
      }
      events.append(AnnouncementEvent(
        frame: min(file.length, Int64(seconds * sampleRate)), paths: paths))
    }
    events.sort { $0.frame < $1.frame }
    let wasPlaying = playing
    if wasPlaying { try handlePause(result: { _ in }) }
    announcementEvents = events
    print("Qwen announcement schedule accepted: \(events.count) boundaries")
    if wasPlaying { try handlePlay(result: { _ in }) }
    result(events.count)
  }

  private func handleSetRate(call: FlutterMethodCall, result: FlutterResult) throws {
    guard let args = call.arguments as? [String: Any],
          let r = args["rate"] as? Double,
          r.isFinite, r >= 0.5, r <= 2.0
    else { throw NSError(domain: "InvalidArgs", code: 1, userInfo: [NSLocalizedDescriptionKey: "Invalid rate"]) }

    rate = r
    timePitch.rate = Float(r)
    result(nil)
  }

  private func handleSetPitch(call: FlutterMethodCall, result: FlutterResult) throws {
    guard let args = call.arguments as? [String: Any],
          let p = args["pitch"] as? Double,
          p.isFinite, p >= -6, p <= 6
    else { throw NSError(domain: "InvalidArgs", code: 1, userInfo: [NSLocalizedDescriptionKey: "Invalid pitch"]) }

    pitchSemitones = p
    timePitch.pitch = Float(p * 100)
    result(nil)
  }

  private func handleSetLoopRange(call: FlutterMethodCall, result: FlutterResult) throws {
    guard let file = audioFile else {
      throw NSError(domain: "NoFile", code: 2, userInfo: [NSLocalizedDescriptionKey: "No file loaded"])
    }
    let args = call.arguments as? [String: Any] ?? [:]
    let restart = args["restart"] as? Bool ?? false
    let cuePath = (args["cuePath"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines)
    let sampleRate = file.processingFormat.sampleRate
    let oldEnd = loopEndFrame ?? file.length
    var newStart: Int64?
    var newEnd: Int64?
    if let start = args["startSeconds"] as? Double,
       let end = args["endSeconds"] as? Double {
      guard start.isFinite, end.isFinite, start >= 0, end > start,
            end <= Double(file.length) / sampleRate + 0.05 else {
        throw NSError(domain: "InvalidArgs", code: 1, userInfo: [NSLocalizedDescriptionKey: "Invalid repeat range"])
      }
      newStart = max(0, Int64(start * sampleRate))
      newEnd = min(file.length, Int64(end * sampleRate))
      guard newEnd! > newStart! else {
        throw NSError(domain: "InvalidArgs", code: 1, userInfo: [NSLocalizedDescriptionKey: "Empty repeat range"])
      }
    }
    let wasPlaying = playing
    let wasAnnouncing = cueCompletion != nil && cueIsLoop
    if wasAnnouncing { cancelCue() }
    let position = currentFrame()
    let mustReschedule = wasPlaying && (restart || oldEnd != (newEnd ?? file.length))
    if mustReschedule { try handlePause(result: { _ in }) }
    loopStartFrame = newStart
    loopEndFrame = newEnd
    loopCuePath = newStart == nil ? nil : (cuePath?.isEmpty == false ? cuePath : nil)
    if restart, let start = newStart {
      savedFrame = start
    } else if mustReschedule {
      savedFrame = position
    }
    if let end = newEnd, savedFrame >= end {
      savedFrame = newStart ?? 0
    }
    lastReportedFrame = savedFrame
    if mustReschedule || wasAnnouncing {
      if restart, let event = eventAt(savedFrame) {
        let expectedGeneration = generation
        playCueSequence(event.paths) { [weak self] in
          guard let self = self, self.generation == expectedGeneration else { return }
          do { try self.handlePlay(result: { _ in }) }
          catch { self.channel.invokeMethod("error", arguments: "Repeat start failed: \(error.localizedDescription)") }
        }
      } else {
        try handlePlay(result: { _ in })
      }
    }
    result(nil)
  }

  private func handleState() -> [String: Any] {
    let file = audioFile
    let duration = file.map { Double($0.length) / $0.processingFormat.sampleRate } ?? 0
    let frame = currentFrame()
    if playing { lastReportedFrame = frame }
    let position = Double(frame) / (file?.processingFormat.sampleRate ?? 1)
    let session = AVAudioSession.sharedInstance()
    return [
      "duration": duration,
      "position": position,
      "playing": playing,
      "rate": rate,
      "pitchSemitones": pitchSemitones,
      "engineRunning": engine.isRunning,
      "nodePlaying": playerNode.isPlaying,
      "nodeVolume": playerNode.volume,
      "mixerVolume": engine.mainMixerNode.outputVolume,
      "systemOutputVolume": session.outputVolume,
      "audioCategory": session.category.rawValue,
      "audioRoute": session.currentRoute.outputs.map { $0.portType.rawValue }.joined(separator: ","),
      "mixerRmsDb": mixerRmsDb,
      "announcementEventCount": announcementEvents.count,
      "announcementCuesStarted": announcementCuesStarted,
      "announcementCuesCompleted": announcementCuesCompleted,
      "announcementCueErrors": announcementCueErrors
    ]
  }

  private func currentFrame() -> Int64 {
    guard let file = audioFile else { return 0 }
    guard playing, let time = playerNode.lastRenderTime,
      let played = playerNode.playerTime(forNodeTime: time) else { return savedFrame }
    return min(file.length, savedFrame + max(0, played.sampleTime))
  }

  private func stopPrior() {
    generation += 1
    playing = false
    playerNode.stop()
    engine.stop()
  }
  // Extract clips off the UI thread without touching the reader's live engine.
  private static func exportSegments(_ arguments: Any?) throws {
    guard let args = arguments as? [String: Any],
          let outputPath = args["outputPath"] as? String,
          let segments = args["segments"] as? [[String: Any]],
          !segments.isEmpty else {
      throw NSError(domain: "QwenExport", code: 1,
                    userInfo: [NSLocalizedDescriptionKey: "Invalid recording segments"])
    }
    let output = try AVAudioFile(forWriting: URL(fileURLWithPath: outputPath), settings: [
      AVFormatIDKey: kAudioFormatLinearPCM, AVSampleRateKey: 24000,
      AVNumberOfChannelsKey: 1, AVLinearPCMBitDepthKey: 16,
      AVLinearPCMIsFloatKey: false, AVLinearPCMIsBigEndianKey: false,
      AVLinearPCMIsNonInterleaved: false
    ], commonFormat: .pcmFormatFloat32, interleaved: false)
    for segment in segments {
      guard let path = segment["path"] as? String else {
        throw NSError(domain: "QwenExport", code: 2)
      }
      let file = try AVAudioFile(forReading: URL(fileURLWithPath: path))
      let format = file.processingFormat
      guard format.sampleRate == 24000, format.channelCount == 1 else {
        throw NSError(domain: "QwenExport", code: 3,
                      userInfo: [NSLocalizedDescriptionKey: "Unexpected Qwen recording format"])
      }
      let startSeconds = (segment["startSeconds"] as? NSNumber)?.doubleValue ?? 0
      let endSeconds = (segment["endSeconds"] as? NSNumber)?.doubleValue ?? Double(file.length) / 24000
      guard startSeconds.isFinite, endSeconds.isFinite,
            startSeconds >= 0, endSeconds > startSeconds,
            endSeconds <= Double(file.length) / 24000 + 0.05 else {
        throw NSError(domain: "QwenExport", code: 4)
      }
      let start = Int64(startSeconds * 24000)
      let end = min(file.length, Int64(endSeconds * 24000))
      guard end > start, let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 4096) else {
        throw NSError(domain: "QwenExport", code: 5)
      }
      file.framePosition = start
      while file.framePosition < end {
        try file.read(into: buffer, frameCount: AVAudioFrameCount(min(4096, end - file.framePosition)))
        guard buffer.frameLength > 0 else { throw NSError(domain: "QwenExport", code: 6) }
        try output.write(from: buffer)
      }
    }
  }

}
