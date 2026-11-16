import Foundation

enum Format {
  static func percent(_ fraction: Double) -> String {
    "\(Int((min(1, max(0, fraction)) * 100).rounded()))%"
  }

  static func bytes(_ count: UInt64) -> String {
    let formatter = ByteCountFormatter()
    formatter.countStyle = .memory
    formatter.allowedUnits = [.useMB, .useGB]
    formatter.zeroPadsFractionDigits = false
    return formatter.string(fromByteCount: Int64(clamping: count))
  }

  static func shortBytes(_ count: UInt64) -> String {
    let gigabytes = Double(count) / 1_073_741_824
    if gigabytes >= 1 {
      return "\(gigabytes.formatted(.number.precision(.fractionLength(1)))) GB"
    }
    return "\(Int((Double(count) / 1_048_576).rounded())) MB"
  }

  static func megabits(_ bitsPerSecond: Double?) -> String {
    guard let bitsPerSecond else { return "0.00" }
    let megabits = bitsPerSecond / 1_000_000
    return megabits.formatted(.number.precision(.fractionLength(megabits >= 100 ? 0 : megabits >= 10 ? 1 : 2)))
  }

  static func dataUsed(_ bytes: UInt64) -> String {
    let gigabytes = Double(bytes) / 1_000_000_000
    if gigabytes >= 1 {
      return "\(gigabytes.formatted(.number.precision(.fractionLength(1)))) GB"
    }
    return "\(Int((Double(bytes) / 1_000_000).rounded())) MB"
  }

  static func gigabytes(_ count: UInt64) -> String {
    (Double(count) / 1_073_741_824).formatted(.number.precision(.fractionLength(2)))
  }

  static func number(_ value: Int) -> String {
    value.formatted(.number.grouping(.automatic))
  }

  static func duration(minutes: Int) -> String {
    let hours = minutes / 60
    let remainder = minutes % 60
    return hours > 0 ? "\(hours) h \(remainder) min" : "\(remainder) min"
  }
}
