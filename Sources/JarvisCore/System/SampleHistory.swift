public struct SampleHistory: Sendable, Equatable {
  public let capacity: Int
  private var storage: [Double]
  private var next = 0

  public init(capacity: Int) {
    precondition(capacity > 0, "A sample history needs room for at least one sample")
    self.capacity = capacity
    storage = []
    storage.reserveCapacity(capacity)
  }

  public var count: Int { storage.count }

  public var values: [Double] {
    guard storage.count == capacity else { return storage }
    return Array(storage[next...]) + Array(storage[..<next])
  }

  public mutating func append(_ value: Double) {
    if storage.count < capacity {
      storage.append(value)
    } else {
      storage[next] = value
      next = (next + 1) % capacity
    }
  }
}
