import Darwin
import Foundation

public struct NetworkTotals: Sendable, Equatable {
  public var received: UInt64
  public var sent: UInt64

  public var combined: UInt64 { received &+ sent }

  public init(received: UInt64, sent: UInt64) {
    self.received = received
    self.sent = sent
  }
}

public struct NetworkRate: Sendable, Equatable {
  public var downBitsPerSecond: Double
  public var upBitsPerSecond: Double

  public init?(from previous: NetworkTotals, to current: NetworkTotals, elapsedSeconds: Double) {
    guard elapsedSeconds > 0, current.received >= previous.received, current.sent >= previous.sent else {
      return nil
    }
    downBitsPerSecond = Double(current.received - previous.received) * 8 / elapsedSeconds
    upBitsPerSecond = Double(current.sent - previous.sent) * 8 / elapsedSeconds
  }
}

public enum NetworkCounters {
  public static func totals(interface name: String) -> NetworkTotals? {
    let index = if_nametoindex(name)
    guard index != 0 else { return nil }
    var mib: [Int32] = [CTL_NET, PF_ROUTE, 0, 0, NET_RT_IFLIST2, Int32(index)]
    var length = 0
    guard sysctl(&mib, UInt32(mib.count), nil, &length, nil, 0) == 0, length > 0 else { return nil }
    var buffer = [UInt8](repeating: 0, count: length)
    guard sysctl(&mib, UInt32(mib.count), &buffer, &length, nil, 0) == 0 else { return nil }
    return buffer.withUnsafeBytes { bytes in
      var offset = 0
      while offset + MemoryLayout<if_msghdr>.size <= length {
        let header = bytes.loadUnaligned(fromByteOffset: offset, as: if_msghdr.self)
        let messageLength = Int(header.ifm_msglen)
        guard messageLength > 0 else { return nil }
        if Int32(header.ifm_type) == RTM_IFINFO2, offset + MemoryLayout<if_msghdr2>.size <= length {
          let message = bytes.loadUnaligned(fromByteOffset: offset, as: if_msghdr2.self)
          if UInt32(message.ifm_index) == index {
            return NetworkTotals(received: message.ifm_data.ifi_ibytes, sent: message.ifm_data.ifi_obytes)
          }
        }
        offset += messageLength
      }
      return nil
    }
  }

  public static func bootDate() -> Date? {
    guard let time = sysctlValue("kern.boottime", as: timeval.self), time.tv_sec > 0 else { return nil }
    return Date(timeIntervalSince1970: TimeInterval(time.tv_sec))
  }
}

public enum NetstatOutput {
  public static let executable = URL(fileURLWithPath: "/usr/sbin/netstat")

  public static func arguments(interface: String) -> [String] {
    ["-ib", "-I", interface]
  }

  public static func parse(_ text: String) -> NetworkTotals? {
    let lines = text.split(separator: "\n").map { $0.split(separator: " ", omittingEmptySubsequences: true) }
    guard let header = lines.first,
      let receivedColumn = header.firstIndex(of: "Ibytes"),
      let sentColumn = header.firstIndex(of: "Obytes")
    else { return nil }
    for fields in lines.dropFirst() {
      let shift = fields.count - header.count
      guard shift >= -1, receivedColumn + shift >= 0, sentColumn + shift < fields.count,
        let received = UInt64(fields[receivedColumn + shift]),
        let sent = UInt64(fields[sentColumn + shift])
      else { continue }
      return NetworkTotals(received: received, sent: sent)
    }
    return nil
  }

  @concurrent
  public static func run(interface: String) async throws -> String {
    let process = Process()
    let pipe = Pipe()
    process.executableURL = executable
    process.arguments = arguments(interface: interface)
    process.standardOutput = pipe
    process.standardError = FileHandle.nullDevice
    try process.run()
    let data = try pipe.fileHandleForReading.readToEnd() ?? Data()
    process.waitUntilExit()
    return String(decoding: data, as: UTF8.self)
  }
}
