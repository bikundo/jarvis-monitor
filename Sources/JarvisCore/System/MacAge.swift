import Foundation

public enum MacAge {
  public static let setupMarker = URL(fileURLWithPath: "/private/var/db/.AppleSetupDone")

  public static func setupDate() -> Date? {
    let attributes = try? FileManager.default.attributesOfItem(atPath: setupMarker.path)
    return attributes?[.creationDate] as? Date
  }

  public static func describe(from start: Date, to end: Date, calendar: Calendar = .current) -> String {
    let parts = calendar.dateComponents([.year, .month, .day], from: start, to: max(start, end))
    let years = parts.year ?? 0
    let months = parts.month ?? 0
    let days = parts.day ?? 0
    if years > 0 {
      return months > 0 ? "\(years) yr \(months) mo" : "\(years) yr"
    }
    if months > 0 {
      return "\(months) mo"
    }
    return days == 1 ? "1 day" : "\(days) days"
  }
}
