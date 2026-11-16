import Foundation
import ServiceManagement
import os

enum LoginItem {
  private static let enabledOnceKey = "loginItemEnabledOnce"
  private static let logger = Logger(subsystem: "app.jarvis.monitor", category: "LoginItem")

  static var isEnabled: Bool {
    SMAppService.mainApp.status == .enabled
  }

  static func enableOnFirstLaunch(defaults: UserDefaults = .standard) {
    guard !defaults.bool(forKey: enabledOnceKey) else { return }
    guard Bundle.main.bundlePath.hasPrefix("/Applications/") else { return }
    do {
      try setEnabled(true)
      defaults.set(true, forKey: enabledOnceKey)
    } catch {
      logger.error("Could not add Jarvis to login items: \(error.localizedDescription, privacy: .public)")
    }
  }

  static func setEnabled(_ enabled: Bool) throws {
    guard enabled != isEnabled else { return }
    if enabled {
      try SMAppService.mainApp.register()
    } else {
      try SMAppService.mainApp.unregister()
    }
  }
}
