import Darwin
import Foundation
import UIKit

/// Read-only device and process telemetry for the narration event log. It
/// exists to tell, after the fact, why speech synthesis slowed down: thermal
/// state, Low Power Mode, memory, and what iOS is doing to the synthesis
/// threads. Nothing here changes behavior.
///
/// iOS does not expose which core a thread runs on, and the QoS class a thread
/// *requested* is not always the one it gets. So threads are reported with the
/// requested QoS beside the scheduler's current and base priority (a demoted
/// thread shows a lower current priority) and their recent CPU share.
enum NarrationTelemetry {
  private static var observers: [NSObjectProtocol] = []

  // MARK: Monitoring

  /// Turns on battery monitoring and logs every change of thermal state,
  /// Low Power Mode and charging state as it happens, through [report].
  static func startMonitoring(report: @escaping (String) -> Void) {
    stopMonitoring()
    UIDevice.current.isBatteryMonitoringEnabled = true
    let center = NotificationCenter.default
    observers.append(
      center.addObserver(
        forName: ProcessInfo.thermalStateDidChangeNotification, object: nil, queue: .main
      ) { _ in report("thermal state -> \(thermalName(ProcessInfo.processInfo.thermalState))") })
    observers.append(
      center.addObserver(
        forName: .NSProcessInfoPowerStateDidChange, object: nil, queue: .main
      ) { _ in
        report("low power mode -> \(ProcessInfo.processInfo.isLowPowerModeEnabled ? "on" : "off")")
      })
    observers.append(
      center.addObserver(
        forName: UIDevice.batteryStateDidChangeNotification, object: nil, queue: .main
      ) { _ in report("charging state -> \(chargingName(UIDevice.current.batteryState))") })
  }

  static func stopMonitoring() {
    for observer in observers { NotificationCenter.default.removeObserver(observer) }
    observers.removeAll()
  }

  // MARK: Device and process state

  /// `thermal=1(fair) lpm=off battery=82% charging=unplugged rss=546MB footprint=812MB avail=1620MB`
  static func stateSummary() -> String {
    let info = ProcessInfo.processInfo
    let level = UIDevice.current.batteryLevel
    let battery = level < 0 ? "?" : "\(Int((level * 100).rounded()))%"
    let memory = memoryUsage()
    return "thermal=\(info.thermalState.rawValue)(\(thermalName(info.thermalState))) "
      + "lpm=\(info.isLowPowerModeEnabled ? "on" : "off") battery=\(battery) "
      + "charging=\(chargingName(UIDevice.current.batteryState)) "
      + "rss=\(memory.resident)MB footprint=\(memory.footprint)MB "
      + "avail=\(Int(os_proc_available_memory() / 1_048_576))MB"
  }

  /// What the event log's synthesis probe asks for: process CPU seconds and
  /// the state summary, plus the busiest threads when [threads] is true.
  static func snapshot(threads: Bool) -> [String: Any] {
    var result: [String: Any] = ["cpu": processCPUSeconds(), "state": stateSummary()]
    if threads { result["threads"] = threadProfile() }
    return result
  }

  static func processCPUSeconds() -> Double {
    var usage = rusage()
    getrusage(RUSAGE_SELF, &usage)
    func seconds(_ value: timeval) -> Double {
      Double(value.tv_sec) + Double(value.tv_usec) / 1_000_000
    }
    return seconds(usage.ru_utime) + seconds(usage.ru_stime)
  }

  private static func memoryUsage() -> (resident: Int, footprint: Int) {
    var info = task_vm_info_data_t()
    var count = mach_msg_type_number_t(
      MemoryLayout<task_vm_info_data_t>.size / MemoryLayout<natural_t>.size)
    let status = withUnsafeMutablePointer(to: &info) {
      $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
        task_info(mach_task_self_, task_flavor_t(TASK_VM_INFO), $0, &count)
      }
    }
    guard status == KERN_SUCCESS else { return (-1, -1) }
    return (Int(info.resident_size / 1_048_576), Int(info.phys_footprint / 1_048_576))
  }

  // MARK: Threads

  /// The busiest threads, e.g.
  /// `[qos=default pri=31/31 cpu=94% run onnx] [qos=user-initiated pri=37/37 cpu=88% run]`.
  ///
  /// `qos` is the class the thread asked for. `pri=current/base` is what the
  /// scheduler is giving it now: current well below base means the thread has
  /// been demoted. `cpu` is the scheduler's recent CPU share.
  static func threadProfile(limit: Int = 8) -> String {
    var list: thread_act_array_t?
    var count = mach_msg_type_number_t(0)
    guard task_threads(mach_task_self_, &list, &count) == KERN_SUCCESS, let threads = list else {
      return "unavailable"
    }
    defer {
      for index in 0..<Int(count) { mach_port_deallocate(mach_task_self_, threads[index]) }
      vm_deallocate(
        mach_task_self_, vm_address_t(bitPattern: threads),
        vm_size_t(Int(count) * MemoryLayout<thread_act_t>.size))
    }
    var rows: [(cpu: Int, text: String)] = []
    for index in 0..<Int(count) {
      let port = threads[index]
      var info = thread_extended_info_data_t()
      var infoCount = mach_msg_type_number_t(
        MemoryLayout<thread_extended_info_data_t>.size / MemoryLayout<natural_t>.size)
      let status = withUnsafeMutablePointer(to: &info) {
        $0.withMemoryRebound(to: integer_t.self, capacity: Int(infoCount)) {
          thread_info(port, thread_flavor_t(THREAD_EXTENDED_INFO), $0, &infoCount)
        }
      }
      guard status == KERN_SUCCESS else { continue }
      // TH_USAGE_SCALE is 1000, so 1000 is one whole core.
      let cpu = Int(info.pth_cpu_usage) / 10
      if cpu < 5 { continue }
      let name = withUnsafePointer(to: &info.pth_name) {
        $0.withMemoryRebound(to: CChar.self, capacity: 64) { String(cString: $0) }
      }
      rows.append(
        (
          cpu,
          "[qos=\(requestedQoS(port)) pri=\(info.pth_curpri)/\(info.pth_priority) "
            + "cpu=\(cpu)% \(runStateName(info.pth_run_state))"
            + (name.isEmpty ? "]" : " \(name)]")
        ))
    }
    if rows.isEmpty { return "none busy" }
    return rows.sorted { $0.cpu > $1.cpu }.prefix(limit).map { $0.text }.joined(separator: " ")
  }

  private static func requestedQoS(_ port: thread_act_t) -> String {
    guard let thread = pthread_from_mach_thread_np(port) else { return "?" }
    var qos = QOS_CLASS_UNSPECIFIED
    var relative: Int32 = 0
    guard pthread_get_qos_class_np(thread, &qos, &relative) == 0 else { return "?" }
    switch qos {
    case QOS_CLASS_USER_INTERACTIVE: return "user-interactive"
    case QOS_CLASS_USER_INITIATED: return "user-initiated"
    case QOS_CLASS_DEFAULT: return "default"
    case QOS_CLASS_UTILITY: return "utility"
    case QOS_CLASS_BACKGROUND: return "background"
    default: return "unspecified"
    }
  }

  private static func runStateName(_ state: Int32) -> String {
    switch state {
    case 1: return "run"
    case 2: return "stopped"
    case 3: return "wait"
    case 4: return "uninterruptible"
    case 5: return "halted"
    default: return "state\(state)"
    }
  }

  // MARK: Names

  static func thermalName(_ state: ProcessInfo.ThermalState) -> String {
    switch state {
    case .nominal: return "nominal"
    case .fair: return "fair"
    case .serious: return "serious"
    case .critical: return "critical"
    @unknown default: return "unknown"
    }
  }

  private static func chargingName(_ state: UIDevice.BatteryState) -> String {
    switch state {
    case .unplugged: return "unplugged"
    case .charging: return "charging"
    case .full: return "full"
    case .unknown: return "unknown"
    @unknown default: return "unknown"
    }
  }
}
