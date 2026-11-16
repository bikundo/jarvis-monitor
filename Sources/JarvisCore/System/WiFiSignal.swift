import CoreWLAN
import Foundation

public enum WiFiQuality: Sendable, Equatable {
  case excellent
  case good
  case fair
  case weak

  public init(rssi: Int) {
    self = switch rssi {
    case (-55)...: .excellent
    case (-67)...: .good
    case (-75)...: .fair
    default: .weak
    }
  }

  public var bars: Int {
    switch self {
    case .excellent: 4
    case .good: 3
    case .fair: 2
    case .weak: 1
    }
  }
}

public struct WiFiSignal: Sendable, Equatable {
  public var interface: String
  public var name: String?
  public var rssi: Int
  public var megabitsPerSecond: Double
  public var gigahertz: Double?

  public var quality: WiFiQuality { WiFiQuality(rssi: rssi) }

  public init?(interface: String, name: String? = nil, poweredOn: Bool, rssi: Int, megabitsPerSecond: Double, gigahertz: Double?) {
    guard poweredOn, rssi < 0 else { return nil }
    self.interface = interface
    self.name = name.flatMap { $0.isEmpty ? nil : $0 }
    self.rssi = rssi
    self.megabitsPerSecond = megabitsPerSecond
    self.gigahertz = gigahertz
  }

  @MainActor
  public static func current() -> WiFiSignal? {
    guard let interface = CWWiFiClient.shared().interface() else { return nil }
    let band: Double? = switch interface.wlanChannel()?.channelBand {
    case .band2GHz: 2.4
    case .band5GHz: 5
    case .band6GHz: 6
    default: nil
    }
    return WiFiSignal(
      interface: interface.interfaceName ?? "en0",
      name: interface.ssid(),
      poweredOn: interface.powerOn(),
      rssi: interface.rssiValue(),
      megabitsPerSecond: interface.transmitRate(),
      gigahertz: band
    )
  }
}
