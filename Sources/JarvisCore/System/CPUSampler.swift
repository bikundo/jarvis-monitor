import Darwin

public struct CPUTicks: Sendable, Equatable {
  public var user: UInt32
  public var system: UInt32
  public var idle: UInt32
  public var nice: UInt32

  public init(user: UInt32, system: UInt32, idle: UInt32, nice: UInt32) {
    self.user = user
    self.system = system
    self.idle = idle
    self.nice = nice
  }
}

public struct CPULoad: Sendable, Equatable {
  public var user: Double
  public var system: Double

  public var busy: Double { min(1, user + system) }

  public static let idle = CPULoad(user: 0, system: 0)

  public init(user: Double, system: Double) {
    self.user = user
    self.system = system
  }

  public init(from previous: CPUTicks, to current: CPUTicks) {
    let user = Double(current.user &- previous.user) + Double(current.nice &- previous.nice)
    let system = Double(current.system &- previous.system)
    let idle = Double(current.idle &- previous.idle)
    let total = user + system + idle
    guard total > 0 else {
      self = .idle
      return
    }
    self.init(user: user / total, system: system / total)
  }
}

public struct CPUSampler {
  private var previousTotal: CPUTicks?
  private var previousCores: [CPUTicks] = []

  public init() {}

  public mutating func sampleTotal() -> CPULoad? {
    guard let current = Self.readTotalTicks() else { return nil }
    defer { previousTotal = current }
    guard let previousTotal else { return nil }
    return CPULoad(from: previousTotal, to: current)
  }

  public mutating func sampleCores() -> [CPULoad] {
    let current = Self.readCoreTicks()
    defer { previousCores = current }
    guard previousCores.count == current.count else { return [] }
    return zip(previousCores, current).map { CPULoad(from: $0, to: $1) }
  }

  public mutating func forgetCores() {
    previousCores = []
  }

  static func readTotalTicks() -> CPUTicks? {
    var info = host_cpu_load_info()
    var count = mach_msg_type_number_t(
      MemoryLayout<host_cpu_load_info_data_t>.size / MemoryLayout<integer_t>.size
    )
    let result = withUnsafeMutablePointer(to: &info) { pointer in
      pointer.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
        host_statistics(machHost, HOST_CPU_LOAD_INFO, $0, &count)
      }
    }
    guard result == KERN_SUCCESS else { return nil }
    return CPUTicks(
      user: info.cpu_ticks.0,
      system: info.cpu_ticks.1,
      idle: info.cpu_ticks.2,
      nice: info.cpu_ticks.3
    )
  }

  static func readCoreTicks() -> [CPUTicks] {
    var coreCount: natural_t = 0
    var info: processor_info_array_t?
    var infoCount: mach_msg_type_number_t = 0
    let result = host_processor_info(machHost, PROCESSOR_CPU_LOAD_INFO, &coreCount, &info, &infoCount)
    guard result == KERN_SUCCESS, let info else { return [] }
    defer {
      let size = vm_size_t(Int(infoCount) * MemoryLayout<integer_t>.stride)
      vm_deallocate(mach_task_self_, vm_address_t(UInt(bitPattern: info)), size)
    }
    let stride = Int(CPU_STATE_MAX)
    return (0..<Int(coreCount)).map { core in
      let base = core * stride
      return CPUTicks(
        user: UInt32(bitPattern: info[base + Int(CPU_STATE_USER)]),
        system: UInt32(bitPattern: info[base + Int(CPU_STATE_SYSTEM)]),
        idle: UInt32(bitPattern: info[base + Int(CPU_STATE_IDLE)]),
        nice: UInt32(bitPattern: info[base + Int(CPU_STATE_NICE)])
      )
    }
  }
}
