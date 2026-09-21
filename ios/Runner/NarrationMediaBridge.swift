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
  private var active = false
  private var commandTargets: [(MPRemoteCommand, Any)] = []
  private var observers: [NSObjectProtocol] = []
  private var backgroundTask: UIBackgroundTaskIdentifier = .invalid

  init(registrar: FlutterPluginRegistrar) {
    channel = FlutterMethodChannel(
      name: "studybible/narration_media",
      binaryMessenger: registrar.messenger()
    )
    super.init()
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
    cpuSamples = [(Date(), processCPUSeconds())]
    cpuTimer = Timer.scheduledTimer(withTimeInterval: 15, repeats: true) { [weak self] _ in
      self?.sampleCPU()
    }
  }

  private func stopCPUSampling() {
    cpuTimer?.invalidate()
    cpuTimer = nil
    cpuSamples.removeAll()
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
        + "app=\(state) thermal=\(ProcessInfo.processInfo.thermalState.rawValue)")
  }

  private func processCPUSeconds() -> Double {
    var usage = rusage()
    getrusage(RUSAGE_SELF, &usage)
    func seconds(_ value: timeval) -> Double {
      Double(value.tv_sec) + Double(value.tv_usec) / 1_000_000
    }
    return seconds(usage.ru_utime) + seconds(usage.ru_stime)
  }

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
        self?.report("background task expired")
        self?.endBackgroundTask()
      }
      if backgroundTask == .invalid { report("beginBackgroundTask refused") }
    } else {
      endBackgroundTask()
    }
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
