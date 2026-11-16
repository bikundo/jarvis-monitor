import CoreLocation

final class LocationPermission: NSObject, CLLocationManagerDelegate {
  private let manager = CLLocationManager()
  private var onChange: (() -> Void)?

  override init() {
    super.init()
    manager.delegate = self
  }

  func requestIfNeeded(onChange: @escaping () -> Void) {
    self.onChange = onChange
    if manager.authorizationStatus == .notDetermined {
      manager.requestWhenInUseAuthorization()
    }
  }

  nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
    Task { @MainActor in
      self.onChange?()
    }
  }
}
