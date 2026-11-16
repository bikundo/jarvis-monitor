import Darwin
import Foundation

public struct ProcessGroup: Sendable, Equatable, Identifiable {
  public var name: String
  public var footprintBytes: UInt64
  public var cpuPercent: Double
  public var processCount: Int

  public var id: String { name }

  public init(name: String, footprintBytes: UInt64, cpuPercent: Double, processCount: Int) {
    self.name = name
    self.footprintBytes = footprintBytes
    self.cpuPercent = cpuPercent
    self.processCount = processCount
  }

  public static func appName(forProcess name: String) -> String {
    for marker in [" Helper", " Web Content", " Networking", " Graphics and Media"] {
      if let range = name.range(of: marker), range.lowerBound > name.startIndex {
        return String(name[..<range.lowerBound])
      }
    }
    return name
  }
}

public enum ProcessOrder: String, Sendable, CaseIterable {
  case memory
  case cpu
}

public struct TopRow: Sendable, Equatable {
  public var pid: Int32
  public var cpuSeconds: Double
  public var footprintBytes: UInt64
  public var command: String

  public init(pid: Int32, cpuSeconds: Double, footprintBytes: UInt64, command: String) {
    self.pid = pid
    self.cpuSeconds = cpuSeconds
    self.footprintBytes = footprintBytes
    self.command = command
  }
}

public enum TopOutput {
  public static let executable = URL(fileURLWithPath: "/usr/bin/top")
  public static let arguments = ["-l", "1", "-stats", "pid,time,mem,command"]

  public static func parse(_ text: String) -> [TopRow] {
    text.split(separator: "\n").compactMap { line in
      let fields = line.split(separator: " ", omittingEmptySubsequences: true)
      guard
        fields.count >= 4,
        let pid = Int32(fields[0]),
        let seconds = seconds(fields[1]),
        let bytes = bytes(fields[2])
      else { return nil }
      let command = fields[3...].joined(separator: " ")
      return TopRow(pid: pid, cpuSeconds: seconds, footprintBytes: bytes, command: command)
    }
  }

  static func seconds(_ field: Substring) -> Double? {
    var total = 0.0
    for part in field.split(separator: ":", omittingEmptySubsequences: false) {
      guard let value = Double(part) else { return nil }
      total = total * 60 + value
    }
    return total
  }

  static func bytes(_ field: Substring) -> UInt64? {
    var digits = field
    while let last = digits.last, last == "+" || last == "-" {
      digits = digits.dropLast()
    }
    guard let unit = digits.last else { return nil }
    let multiplier: Double
    switch unit {
    case "B": multiplier = 1
    case "K": multiplier = 1024
    case "M": multiplier = 1_048_576
    case "G": multiplier = 1_073_741_824
    case "T": multiplier = 1_099_511_627_776
    default: return nil
    }
    guard let value = Double(digits.dropLast()), value >= 0 else { return nil }
    return UInt64(value * multiplier)
  }

  @concurrent
  public static func run() async throws -> String {
    let process = Process()
    let pipe = Pipe()
    process.executableURL = executable
    process.arguments = arguments
    process.standardOutput = pipe
    process.standardError = FileHandle.nullDevice
    try process.run()
    let data = try pipe.fileHandleForReading.readToEnd() ?? Data()
    process.waitUntilExit()
    return String(decoding: data, as: UTF8.self)
  }
}

public struct ProcessSampler {
  private struct Reading {
    var footprintBytes: UInt64
    var cpuPercent: Double
  }

  private var ownReadings: [Int32: Reading] = [:]
  private var otherReadings: [Int32: Reading] = [:]
  private var otherCommands: [Int32: String] = [:]
  private var names: [Int32: String] = [:]
  private var previousOwnCPU: [Int32: UInt64] = [:]
  private var previousOwnUptime: UInt64?
  private var previousOtherCPU: [Int32: Double] = [:]
  private var previousOtherUptime: UInt64?
  private let timebase: mach_timebase_info_data_t

  public init() {
    var info = mach_timebase_info_data_t()
    mach_timebase_info(&info)
    timebase = info
  }

  public static var uptimeNanoseconds: UInt64 {
    clock_gettime_nsec_np(CLOCK_UPTIME_RAW)
  }

  public mutating func sampleOwnProcesses() {
    let now = Self.uptimeNanoseconds
    let elapsed = previousOwnUptime.map { now > $0 ? now - $0 : 0 } ?? 0
    var readings: [Int32: Reading] = [:]
    var cpuTimes: [Int32: UInt64] = [:]
    for pid in Self.allProcessIDs() {
      guard let usage = Self.resourceUsage(of: pid) else { continue }
      let cpuNanoseconds = (usage.ri_user_time + usage.ri_system_time)
        * UInt64(timebase.numer) / UInt64(max(1, timebase.denom))
      cpuTimes[pid] = cpuNanoseconds
      var percent = 0.0
      if elapsed > 0, let previous = previousOwnCPU[pid], cpuNanoseconds >= previous {
        percent = Double(cpuNanoseconds - previous) / Double(elapsed) * 100
      }
      readings[pid] = Reading(footprintBytes: usage.ri_phys_footprint, cpuPercent: percent)
    }
    ownReadings = readings
    previousOwnCPU = cpuTimes
    previousOwnUptime = now
  }

  public mutating func ingest(rows: [TopRow], uptimeNanoseconds now: UInt64) {
    let elapsed = previousOtherUptime.map { now > $0 ? Double(now - $0) / 1_000_000_000 : 0 } ?? 0
    var readings: [Int32: Reading] = [:]
    var cpuTimes: [Int32: Double] = [:]
    var commands: [Int32: String] = [:]
    for row in rows where ownReadings[row.pid] == nil {
      cpuTimes[row.pid] = row.cpuSeconds
      commands[row.pid] = row.command
      var percent = 0.0
      if elapsed > 0, let previous = previousOtherCPU[row.pid], row.cpuSeconds >= previous {
        percent = (row.cpuSeconds - previous) / elapsed * 100
      }
      readings[row.pid] = Reading(footprintBytes: row.footprintBytes, cpuPercent: percent)
    }
    otherReadings = readings
    otherCommands = commands
    previousOtherCPU = cpuTimes
    previousOtherUptime = now
  }

  public mutating func topGroups(by order: ProcessOrder, limit: Int) -> [ProcessGroup] {
    let merged = otherReadings.merging(ownReadings) { _, own in own }
    names = names.filter { merged[$0.key] != nil }
    var groups: [String: ProcessGroup] = [:]
    for (pid, reading) in merged {
      let name = names[pid] ?? Self.name(of: pid) ?? otherCommands[pid] ?? "pid \(pid)"
      names[pid] = name
      let key = ProcessGroup.appName(forProcess: name)
      var group = groups[key] ?? ProcessGroup(name: key, footprintBytes: 0, cpuPercent: 0, processCount: 0)
      group.footprintBytes += reading.footprintBytes
      group.cpuPercent += reading.cpuPercent
      group.processCount += 1
      groups[key] = group
    }
    let sorted = groups.values.sorted { left, right in
      switch order {
      case .memory: (left.footprintBytes, left.name) > (right.footprintBytes, right.name)
      case .cpu: (left.cpuPercent, left.name) > (right.cpuPercent, right.name)
      }
    }
    return Array(sorted.prefix(limit))
  }

  public mutating func reset() {
    self = ProcessSampler()
  }

  static func allProcessIDs() -> [Int32] {
    let estimate = proc_listallpids(nil, 0)
    guard estimate > 0 else { return [] }
    var pids = [Int32](repeating: 0, count: Int(estimate) + 64)
    let filled = pids.withUnsafeMutableBytes { buffer in
      proc_listallpids(buffer.baseAddress, Int32(buffer.count))
    }
    guard filled > 0 else { return [] }
    return pids.prefix(Int(filled)).filter { $0 > 0 }
  }

  static func resourceUsage(of pid: Int32) -> rusage_info_v4? {
    var info = rusage_info_v4()
    let result = withUnsafeMutablePointer(to: &info) { pointer in
      pointer.withMemoryRebound(to: rusage_info_t?.self, capacity: 1) {
        proc_pid_rusage(pid, RUSAGE_INFO_V4, $0)
      }
    }
    return result == 0 ? info : nil
  }

  static func name(of pid: Int32) -> String? {
    var buffer = [CChar](repeating: 0, count: 4096)
    let nameLength = proc_name(pid, &buffer, UInt32(buffer.count))
    if nameLength > 0 {
      return text(buffer, length: Int(nameLength))
    }
    let pathLength = proc_pidpath(pid, &buffer, UInt32(buffer.count))
    guard pathLength > 0 else { return nil }
    let path = text(buffer, length: Int(pathLength))
    return path.split(separator: "/").last.map(String.init)
  }

  private static func text(_ buffer: [CChar], length: Int) -> String {
    String(decoding: buffer.prefix(length).map { UInt8(bitPattern: $0) }, as: UTF8.self)
  }
}
