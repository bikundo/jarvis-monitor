import Foundation
import IOKit
import IOKit.ps

public enum PowerSource: Sendable, Equatable {
  case mains
  case battery
}

public struct BatteryState: Sendable, Equatable {
  public var percent: Int
  public var source: PowerSource
  public var isCharging: Bool
  public var isCharged: Bool
  public var minutesRemaining: Int?

  public init?(description: [String: Any]) {
    guard
      description["Type"] as? String == "InternalBattery",
      let current = description["Current Capacity"] as? Int,
      let maximum = description["Max Capacity"] as? Int,
      maximum > 0
    else { return nil }
    percent = min(100, max(0, Int((Double(current) / Double(maximum) * 100).rounded())))
    source = description["Power Source State"] as? String == "Battery Power" ? .battery : .mains
    isCharging = description["Is Charging"] as? Bool ?? false
    isCharged = description["Is Charged"] as? Bool ?? false
    let key = isCharging ? "Time to Full Charge" : "Time to Empty"
    let minutes = description[key] as? Int ?? -1
    let estimating = source == .mains && !isCharging
    minutesRemaining = minutes > 0 && !estimating ? minutes : nil
  }
}

public struct BatteryDetail: Sendable, Equatable {
  public var cycleCount: Int?
  public var healthPercent: Int?
  public var batteryWatts: Double?
  public var systemWatts: Double?

  public init(registry: [String: Any]) {
    let batteryData = registry["BatteryData"] as? [String: Any] ?? [:]
    let telemetry = registry["PowerTelemetryData"] as? [String: Any] ?? [:]
    func capacity(_ key: String) -> Int? {
      registry[key] as? Int ?? batteryData[key] as? Int
    }
    cycleCount = capacity("CycleCount")
    if
      let full = capacity("AppleRawMaxCapacity") ?? capacity("NominalChargeCapacity"),
      let design = capacity("DesignCapacity"),
      design > 0
    {
      healthPercent = min(100, Int((Double(full) / Double(design) * 100).rounded()))
    } else {
      healthPercent = nil
    }
    if
      let millivolts = (registry["Voltage"] as? NSNumber)?.int64Value,
      let milliamps = (registry["Amperage"] as? NSNumber)?.int64Value
    {
      batteryWatts = Double(millivolts) * Double(milliamps) / 1_000_000
    } else {
      batteryWatts = nil
    }
    systemWatts = (telemetry["SystemLoad"] as? NSNumber).map { $0.doubleValue / 1000 }
  }
}

@MainActor
public final class BatteryMonitor {
  public private(set) var state: BatteryState?
  public var onChange: (@MainActor () -> Void)?
  private var runLoopSource: CFRunLoopSource?

  public init() {
    state = Self.readState()
  }

  public func start() {
    guard runLoopSource == nil else { return }
    let context = Unmanaged.passUnretained(self).toOpaque()
    let created = IOPSNotificationCreateRunLoopSource({ context in
      guard let context else { return }
      let monitor = Unmanaged<BatteryMonitor>.fromOpaque(context).takeUnretainedValue()
      MainActor.assumeIsolated {
        monitor.refresh()
      }
    }, context)
    guard let source = created?.takeRetainedValue() else { return }
    CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
    runLoopSource = source
  }

  public func stop() {
    guard let runLoopSource else { return }
    CFRunLoopRemoveSource(CFRunLoopGetMain(), runLoopSource, .commonModes)
    self.runLoopSource = nil
  }

  public func readDetail() -> BatteryDetail? {
    let service = IOServiceGetMatchingService(kIOMainPortDefault, IOServiceMatching("AppleSmartBattery"))
    guard service != 0 else { return nil }
    defer { IOObjectRelease(service) }
    var properties: Unmanaged<CFMutableDictionary>?
    guard
      IORegistryEntryCreateCFProperties(service, &properties, kCFAllocatorDefault, 0) == KERN_SUCCESS,
      let registry = properties?.takeRetainedValue() as? [String: Any]
    else { return nil }
    return BatteryDetail(registry: registry)
  }

  private func refresh() {
    let updated = Self.readState()
    guard updated != state else { return }
    state = updated
    onChange?()
  }

  private static func readState() -> BatteryState? {
    guard
      let info = IOPSCopyPowerSourcesInfo()?.takeRetainedValue(),
      let sources = IOPSCopyPowerSourcesList(info)?.takeRetainedValue() as? [CFTypeRef]
    else { return nil }
    for source in sources {
      guard
        let description = IOPSGetPowerSourceDescription(info, source)?.takeUnretainedValue() as? [String: Any],
        let state = BatteryState(description: description)
      else { continue }
      return state
    }
    return nil
  }
}
