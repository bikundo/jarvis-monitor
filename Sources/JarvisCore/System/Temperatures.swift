import Foundation
import IOKit.hid

@_silgen_name("IOHIDEventSystemClientCreate")
private func IOHIDEventSystemClientCreate(_ allocator: CFAllocator?) -> IOHIDEventSystemClient?

@_silgen_name("IOHIDEventSystemClientSetMatching")
private func IOHIDEventSystemClientSetMatching(_ client: IOHIDEventSystemClient, _ matching: CFDictionary) -> Int32

@_silgen_name("IOHIDServiceClientCopyEvent")
private func IOHIDServiceClientCopyEvent(
  _ service: IOHIDServiceClient,
  _ type: Int64,
  _ options: Int32,
  _ timestamp: Int64
) -> Unmanaged<CFTypeRef>?

@_silgen_name("IOHIDEventGetFloatValue")
private func IOHIDEventGetFloatValue(_ event: CFTypeRef, _ field: Int32) -> Double

public struct Temperatures: Sendable, Equatable {
  public var processor: Double
  public var hottest: Double
  public var battery: Double?

  public init?(readings: [(name: String, celsius: Double)]) {
    let valid = readings.filter { $0.celsius > 0 && $0.celsius < 150 }
    let die = valid.filter { $0.name.contains("tdie") }.map(\.celsius)
    guard let hottest = die.max() else { return nil }
    processor = die.reduce(0, +) / Double(die.count)
    self.hottest = hottest
    let cells = valid.filter { $0.name.localizedCaseInsensitiveContains("battery") }.map(\.celsius)
    battery = cells.isEmpty ? nil : cells.reduce(0, +) / Double(cells.count)
  }
}

public final class TemperatureReader {
  private static let temperatureEvent: Int64 = 15
  private static let temperatureField: Int32 = 15 << 16

  private let client: IOHIDEventSystemClient
  private let services: [IOHIDServiceClient]
  private let names: [String]

  public init?() {
    guard let client = IOHIDEventSystemClientCreate(kCFAllocatorDefault) else { return nil }
    self.client = client
    _ = IOHIDEventSystemClientSetMatching(client, ["PrimaryUsagePage": 0xff00, "PrimaryUsage": 5] as CFDictionary)
    services = IOHIDEventSystemClientCopyServices(client) as? [IOHIDServiceClient] ?? []
    names = services.map { IOHIDServiceClientCopyProperty($0, "Product" as CFString) as? String ?? "" }
    if services.isEmpty { return nil }
  }

  public func read() -> Temperatures? {
    var readings: [(name: String, celsius: Double)] = []
    readings.reserveCapacity(services.count)
    for (service, name) in zip(services, names) {
      guard let event = IOHIDServiceClientCopyEvent(service, Self.temperatureEvent, 0, 0)?.takeRetainedValue() else {
        continue
      }
      readings.append((name: name, celsius: IOHIDEventGetFloatValue(event, Self.temperatureField)))
    }
    return Temperatures(readings: readings)
  }
}
