import Darwin

public struct VMPageCounts: Sendable, Equatable {
  public var internalPages: UInt64
  public var purgeablePages: UInt64
  public var wiredPages: UInt64
  public var compressorPages: UInt64
  public var externalPages: UInt64

  public init(
    internalPages: UInt64,
    purgeablePages: UInt64,
    wiredPages: UInt64,
    compressorPages: UInt64,
    externalPages: UInt64
  ) {
    self.internalPages = internalPages
    self.purgeablePages = purgeablePages
    self.wiredPages = wiredPages
    self.compressorPages = compressorPages
    self.externalPages = externalPages
  }
}

public struct MemoryBreakdown: Sendable, Equatable {
  public var total: UInt64
  public var app: UInt64
  public var wired: UInt64
  public var compressed: UInt64
  public var cached: UInt64

  public var used: UInt64 { min(total, app + wired + compressed) }
  public var free: UInt64 { total - used }
  public var usedFraction: Double { total == 0 ? 0 : Double(used) / Double(total) }

  public init(pages: VMPageCounts, pageSize: UInt64, totalBytes: UInt64) {
    let appPages = pages.internalPages > pages.purgeablePages
      ? pages.internalPages - pages.purgeablePages
      : 0
    total = totalBytes
    app = appPages * pageSize
    wired = pages.wiredPages * pageSize
    compressed = pages.compressorPages * pageSize
    cached = (pages.externalPages + pages.purgeablePages) * pageSize
  }
}

public struct SwapUsage: Sendable, Equatable {
  public var total: UInt64
  public var used: UInt64

  public init(total: UInt64, used: UInt64) {
    self.total = total
    self.used = used
  }
}

public enum MemoryPressureLevel: Sendable, Equatable {
  case normal
  case warning
  case critical

  public init(kernelLevel: Int32) {
    self = switch kernelLevel {
    case 4: .critical
    case 2: .warning
    default: .normal
    }
  }
}

public struct MemoryPressure: Sendable, Equatable {
  public var level: MemoryPressureLevel
  public var fraction: Double

  public init(kernelLevel: Int32, availablePercent: Int32) {
    level = MemoryPressureLevel(kernelLevel: kernelLevel)
    fraction = Double(100 - min(100, max(0, availablePercent))) / 100
  }
}

public struct MemorySampler: Sendable {
  public let pageSize: UInt64
  public let totalBytes: UInt64

  public init() {
    var size: vm_size_t = 0
    host_page_size(machHost, &size)
    pageSize = UInt64(size)
    totalBytes = sysctlValue("hw.memsize", as: UInt64.self) ?? 0
  }

  public func breakdown() -> MemoryBreakdown? {
    var info = vm_statistics64()
    var count = mach_msg_type_number_t(
      MemoryLayout<vm_statistics64_data_t>.size / MemoryLayout<integer_t>.size
    )
    let result = withUnsafeMutablePointer(to: &info) { pointer in
      pointer.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
        host_statistics64(machHost, HOST_VM_INFO64, $0, &count)
      }
    }
    guard result == KERN_SUCCESS else { return nil }
    let pages = VMPageCounts(
      internalPages: UInt64(info.internal_page_count),
      purgeablePages: UInt64(info.purgeable_count),
      wiredPages: UInt64(info.wire_count),
      compressorPages: UInt64(info.compressor_page_count),
      externalPages: UInt64(info.external_page_count)
    )
    return MemoryBreakdown(pages: pages, pageSize: pageSize, totalBytes: totalBytes)
  }

  public func swap() -> SwapUsage? {
    guard let usage = sysctlValue("vm.swapusage", as: xsw_usage.self) else { return nil }
    return SwapUsage(total: usage.xsu_total, used: usage.xsu_used)
  }

  public func pressure() -> MemoryPressure? {
    guard
      let level = sysctlValue("kern.memorystatus_vm_pressure_level", as: Int32.self),
      let available = sysctlValue("kern.memorystatus_level", as: Int32.self)
    else { return nil }
    return MemoryPressure(kernelLevel: level, availablePercent: available)
  }
}
