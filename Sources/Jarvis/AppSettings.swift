import Foundation
import JarvisCore
import Observation

enum SavedResource: String {
  case batteryHistory = "savedBatteryHistory"
}

@Observable
final class AppSettings {
  @ObservationIgnored private let defaults: UserDefaults
  @ObservationIgnored var onMenuBarChange: (() -> Void)?

  var showCPU: Bool {
    didSet {
      defaults.set(showCPU, forKey: Key.showCPU)
      onMenuBarChange?()
    }
  }

  var showMemory: Bool {
    didSet {
      defaults.set(showMemory, forKey: Key.showMemory)
      onMenuBarChange?()
    }
  }

  var showBattery: Bool {
    didSet {
      defaults.set(showBattery, forKey: Key.showBattery)
      onMenuBarChange?()
    }
  }

  var processOrder: ProcessOrder {
    didSet { defaults.set(processOrder.rawValue, forKey: Key.processOrder) }
  }

  func savedData(for key: SavedResource) -> Data? {
    defaults.data(forKey: key.rawValue)
  }

  func save(_ data: Data?, for key: SavedResource) {
    defaults.set(data, forKey: key.rawValue)
  }

  init(defaults: UserDefaults = .standard) {
    self.defaults = defaults
    defaults.register(defaults: [
      Key.showCPU: true,
      Key.showMemory: true,
      Key.showBattery: false,
    ])
    showCPU = defaults.bool(forKey: Key.showCPU)
    showMemory = defaults.bool(forKey: Key.showMemory)
    showBattery = defaults.bool(forKey: Key.showBattery)
    processOrder = defaults.string(forKey: Key.processOrder).flatMap(ProcessOrder.init) ?? .memory
  }

  private enum Key {
    static let showCPU = "showCPU"
    static let showMemory = "showMemory"
    static let showBattery = "showBattery"
    static let processOrder = "processOrder"
  }
}
