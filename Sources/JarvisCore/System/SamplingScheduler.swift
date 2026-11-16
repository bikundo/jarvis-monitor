import Dispatch

public struct SamplingConditions: Sendable, Equatable {
  public var popoverOpen: Bool
  public var onBattery: Bool
  public var lowPowerMode: Bool
  public var displayAsleep: Bool

  public init(popoverOpen: Bool, onBattery: Bool, lowPowerMode: Bool, displayAsleep: Bool) {
    self.popoverOpen = popoverOpen
    self.onBattery = onBattery
    self.lowPowerMode = lowPowerMode
    self.displayAsleep = displayAsleep
  }
}

public enum SamplingRate: Sendable, Equatable {
  case paused
  case every(milliseconds: Int)

  public static let open = SamplingRate.every(milliseconds: 2000)
  public static let closed = SamplingRate.every(milliseconds: 3000)
  public static let saving = SamplingRate.every(milliseconds: 5000)

  public init(_ conditions: SamplingConditions) {
    self = if conditions.displayAsleep {
      .paused
    } else if conditions.popoverOpen {
      .open
    } else if conditions.onBattery || conditions.lowPowerMode {
      .saving
    } else {
      .closed
    }
  }

  public var leewayMilliseconds: Int {
    switch self {
    case .paused: 0
    case .every(let milliseconds): milliseconds <= 1000 ? milliseconds / 10 : milliseconds / 4
    }
  }
}

@MainActor
public final class SamplingScheduler {
  public private(set) var rate = SamplingRate.paused
  private var timer: DispatchSourceTimer?
  private let onTick: @MainActor () -> Void

  public init(onTick: @escaping @MainActor () -> Void) {
    self.onTick = onTick
  }

  public func apply(_ newRate: SamplingRate) {
    guard newRate != rate else { return }
    rate = newRate
    timer?.cancel()
    timer = nil
    guard case .every(let milliseconds) = newRate else { return }
    let source = DispatchSource.makeTimerSource(queue: .main)
    source.schedule(
      deadline: .now(),
      repeating: .milliseconds(milliseconds),
      leeway: .milliseconds(newRate.leewayMilliseconds)
    )
    source.setEventHandler { [weak self] in
      MainActor.assumeIsolated {
        self?.onTick()
      }
    }
    source.resume()
    timer = source
  }
}
