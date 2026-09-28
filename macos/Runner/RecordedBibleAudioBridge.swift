import Foundation
import AVFoundation
import FlutterMacOS

// macOS counterpart of the recorded Bible bridge used by iOS.
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
  private var connectedRoute = ""
  private var needsGraphRebuild = false

  init(messenger: FlutterBinaryMessenger) {
    channel = FlutterMethodChannel(name: "studybible/recorded_audio", binaryMessenger: messenger)
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
      forName: .AVAudioEngineConfigurationChange,
      object: engine, queue: .main
    ) { [weak self] _ in self?.handleEngineConfigurationChange() })
  }

  deinit {
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
    let format = engine.outputNode.outputFormat(forBus: 0)
    return "\(format.sampleRate):\(format.channelCount)"
  }

  private func handleEngineConfigurationChange() {
    needsGraphRebuild = true
    guard playing || cueCompletion != nil else { return }
    // Pause when the output changes, including a disconnected headset.
    // The next explicit Play reconnects the engine to the current output.
    let frame = max(lastReportedFrame, currentFrame())
    cancelCue()
    generation += 1
    playing = false
    playerNode.stop()
    engine.stop()
    savedFrame = frame
    lastReportedFrame = frame
    channel.invokeMethod("error", arguments: "Audio output changed. Press Play to continue.")
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
      "audioRoute": routeSignature(),
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
