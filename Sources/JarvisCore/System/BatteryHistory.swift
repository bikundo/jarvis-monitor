import Foundation

public struct BatteryHistory: Codable, Sendable, Equatable {
  public struct Sample: Codable, Sendable, Equatable {
    public var date: Date
    public var percent: Int
    public var charging: Bool

    public init(date: Date, percent: Int, charging: Bool) {
      self.date = date
      self.percent = percent
      self.charging = charging
    }
  }

  public static let window: TimeInterval = 24 * 60 * 60
  public static let minimumSpacing: TimeInterval = 10 * 60

  public private(set) var samples: [Sample]

  public init(samples: [Sample] = []) {
    self.samples = samples
  }

  @discardableResult
  public mutating func record(percent: Int, charging: Bool, at date: Date) -> Bool {
    let cutoff = date.addingTimeInterval(-Self.window)
    let kept = samples.filter { $0.date >= cutoff && $0.date <= date }
    let pruned = kept.count != samples.count
    samples = kept
    if let last = samples.last {
      let unchanged = last.percent == percent && last.charging == charging
      if unchanged && date.timeIntervalSince(last.date) < Self.minimumSpacing {
        return pruned
      }
    }
    samples.append(Sample(date: date, percent: percent, charging: charging))
    return true
  }

  public func points(endingAt now: Date) -> [(offset: TimeInterval, percent: Double)] {
    guard let first = samples.first else { return [] }
    var points = samples.map { (offset: $0.date.timeIntervalSince(first.date), percent: Double($0.percent)) }
    if let last = samples.last, now > last.date {
      points.append((offset: now.timeIntervalSince(first.date), percent: Double(last.percent)))
    }
    return points
  }
}
