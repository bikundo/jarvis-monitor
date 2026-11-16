import AppKit
import Foundation
import JarvisCore
import Observation

struct MenuBarItem: Equatable {
  var label: String
  var value: String
}

@Observable
final class AppModel {
  static let historyLength = 60
  static let processLimit = 5

  let settings: AppSettings
  let setupDate = MacAge.setupDate()

  private(set) var cpu = CPULoad.idle
  private(set) var cores: [CPULoad] = []
  private(set) var memory: MemoryBreakdown?
  private(set) var swap: SwapUsage?
  private(set) var pressure: MemoryPressure?
  private(set) var battery: BatteryState?
  private(set) var batteryDetail: BatteryDetail?
  private(set) var batteryHistory = BatteryHistory()
  private(set) var temperatures: Temperatures?
  private(set) var wifi: WiFiSignal?
  private(set) var networkRate: NetworkRate?
  private(set) var dataUsed: NetworkTotals?
  let bootDate = NetworkCounters.bootDate()
  private(set) var processes: [ProcessGroup] = []
  private(set) var cpuUserHistory = SampleHistory(capacity: historyLength)
  private(set) var cpuSystemHistory = SampleHistory(capacity: historyLength)
  private(set) var memoryAppHistory = SampleHistory(capacity: historyLength)
  private(set) var memoryWiredHistory = SampleHistory(capacity: historyLength)
  private(set) var memoryCompressedHistory = SampleHistory(capacity: historyLength)
  private(set) var popoverOpen = false

  @ObservationIgnored var onMenuBarChange: (() -> Void)?
  @ObservationIgnored private var cpuSampler = CPUSampler()
  @ObservationIgnored private let memorySampler = MemorySampler()
  @ObservationIgnored private var processSampler = ProcessSampler()
  @ObservationIgnored private let batteryMonitor = BatteryMonitor()
  @ObservationIgnored private var scheduler: SamplingScheduler?
  @ObservationIgnored private var otherProcessesTask: Task<Void, Never>?
  @ObservationIgnored private var temperatureReader: TemperatureReader?
  @ObservationIgnored private var networkSampledAt: UInt64?
  @ObservationIgnored private var networkTotals: NetworkTotals?
  @ObservationIgnored private var dataUsedTask: Task<Void, Never>?
  @ObservationIgnored private let location = LocationPermission()
  @ObservationIgnored private var observers: [any NSObjectProtocol] = []
  @ObservationIgnored private var displayAsleep = false
  @ObservationIgnored private var screenLocked = false
  @ObservationIgnored private var tickCount = 0
  @ObservationIgnored private var lastMenuBarItems: [MenuBarItem] = []

  init() {
    let settings = AppSettings()
    self.settings = settings
    battery = batteryMonitor.state
    if let saved = settings.savedData(for: .batteryHistory),
      let history = try? JSONDecoder().decode(BatteryHistory.self, from: saved)
    {
      batteryHistory = history
    }
    recordBattery()
  }

  var totalMemoryBytes: UInt64 { memorySampler.totalBytes }

  var menuBarItems: [MenuBarItem] {
    var items: [MenuBarItem] = []
    if settings.showCPU {
      items.append(MenuBarItem(label: "CPU", value: Format.percent(cpu.busy)))
    }
    if settings.showMemory {
      items.append(MenuBarItem(label: "RAM", value: Format.percent(memory?.usedFraction ?? 0)))
    }
    if settings.showBattery, let battery {
      items.append(MenuBarItem(label: "BAT", value: "\(battery.percent)%"))
    }
    return items
  }

  func start() {
    settings.onMenuBarChange = { [weak self] in self?.publishMenuBar(force: true) }
    scheduler = SamplingScheduler { [weak self] in self?.tick() }
    batteryMonitor.onChange = { [weak self] in self?.batteryChanged() }
    batteryMonitor.start()
    observeEnvironment()
    applyConditions()
  }

  func setPopoverOpen(_ open: Bool) {
    guard open != popoverOpen else { return }
    popoverOpen = open
    if open {
      temperatureReader = TemperatureReader()
      location.requestIfNeeded { [weak self] in self?.sampleSurroundings() }
      sampleSurroundings()
      loadDataUsed()
      recordBattery()
      batteryDetail = batteryMonitor.readDetail()
      sampleDetail()
      startOtherProcessSampling()
    } else {
      otherProcessesTask?.cancel()
      otherProcessesTask = nil
      processSampler.reset()
      cpuSampler.forgetCores()
      processes = []
      temperatureReader = nil
      networkTotals = nil
      networkRate = nil
      networkSampledAt = nil
      dataUsedTask?.cancel()
      dataUsedTask = nil
      cores = []
    }
    applyConditions()
  }

  private func tick() {
    tickCount &+= 1
    if let load = cpuSampler.sampleTotal() {
      cpu = load
      cpuUserHistory.append(load.user)
      cpuSystemHistory.append(load.system)
    }
    if let breakdown = memorySampler.breakdown() {
      memory = breakdown
      let total = Double(max(1, breakdown.total))
      memoryAppHistory.append(Double(breakdown.app) / total)
      memoryWiredHistory.append(Double(breakdown.wired) / total)
      memoryCompressedHistory.append(Double(breakdown.compressed) / total)
    }
    if popoverOpen {
      sampleDetail()
    }
    publishMenuBar(force: false)
  }

  private func sampleDetail() {
    cores = cpuSampler.sampleCores()
    swap = memorySampler.swap()
    pressure = memorySampler.pressure()
    processSampler.sampleOwnProcesses()
    publishProcesses()
    sampleNetwork()
    if tickCount.isMultiple(of: 2) {
      sampleSurroundings()
    }
    if tickCount.isMultiple(of: 5) {
      batteryDetail = batteryMonitor.readDetail()
    }
  }

  private func sampleSurroundings() {
    temperatures = temperatureReader?.read()
    wifi = WiFiSignal.current()
  }

  private func loadDataUsed() {
    guard let interface = wifi?.interface else {
      dataUsed = nil
      return
    }
    dataUsedTask?.cancel()
    dataUsedTask = Task { [weak self] in
      let output = try? await NetstatOutput.run(interface: interface)
      guard !Task.isCancelled, let output else { return }
      self?.dataUsed = NetstatOutput.parse(output)
    }
  }

  private func sampleNetwork() {
    guard let interface = wifi?.interface, let totals = NetworkCounters.totals(interface: interface) else {
      networkTotals = nil
      networkRate = nil
      networkSampledAt = nil
      return
    }
    let now = ProcessSampler.uptimeNanoseconds
    if let previous = networkTotals, let sampledAt = networkSampledAt, now > sampledAt {
      networkRate = NetworkRate(from: previous, to: totals, elapsedSeconds: Double(now - sampledAt) / 1_000_000_000)
    }
    networkTotals = totals
    networkSampledAt = now
  }

  func publishProcesses() {
    processes = processSampler.topGroups(by: settings.processOrder, limit: Self.processLimit)
  }

  private func startOtherProcessSampling() {
    otherProcessesTask?.cancel()
    otherProcessesTask = Task { [weak self] in
      while !Task.isCancelled {
        if let output = try? await TopOutput.run(), !Task.isCancelled {
          self?.ingestOtherProcesses(output)
        }
        try? await Task.sleep(for: .seconds(15))
      }
    }
  }

  private func ingestOtherProcesses(_ output: String) {
    guard popoverOpen else { return }
    processSampler.ingest(rows: TopOutput.parse(output), uptimeNanoseconds: ProcessSampler.uptimeNanoseconds)
    publishProcesses()
  }

  private func recordBattery() {
    guard let battery else { return }
    guard batteryHistory.record(percent: battery.percent, charging: battery.isCharging, at: Date()) else { return }
    settings.save(try? JSONEncoder().encode(batteryHistory), for: .batteryHistory)
  }

  private func batteryChanged() {
    battery = batteryMonitor.state
    recordBattery()
    if popoverOpen {
      batteryDetail = batteryMonitor.readDetail()
    }
    publishMenuBar(force: false)
    applyConditions()
  }

  private func publishMenuBar(force: Bool) {
    let items = menuBarItems
    guard force || items != lastMenuBarItems else { return }
    lastMenuBarItems = items
    onMenuBarChange?()
  }

  private func applyConditions() {
    let conditions = SamplingConditions(
      popoverOpen: popoverOpen,
      onBattery: battery?.source == .battery,
      lowPowerMode: ProcessInfo.processInfo.isLowPowerModeEnabled,
      displayAsleep: displayAsleep || screenLocked
    )
    scheduler?.apply(SamplingRate(conditions))
  }

  private func observeEnvironment() {
    let workspace = NSWorkspace.shared.notificationCenter
    let distributed = DistributedNotificationCenter.default()
    observe(workspace, NSWorkspace.screensDidSleepNotification) { $0.displayAsleep = true }
    observe(workspace, NSWorkspace.screensDidWakeNotification) { $0.displayAsleep = false }
    observe(distributed, Notification.Name("com.apple.screenIsLocked")) { $0.screenLocked = true }
    observe(distributed, Notification.Name("com.apple.screenIsUnlocked")) { $0.screenLocked = false }
    observe(NotificationCenter.default, .NSProcessInfoPowerStateDidChange) { _ in }
  }

  private func observe(
    _ center: NotificationCenter,
    _ name: Notification.Name,
    update: @escaping @MainActor (AppModel) -> Void
  ) {
    let observer = center.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
      Task { @MainActor in
        guard let self else { return }
        update(self)
        self.applyConditions()
      }
    }
    observers.append(observer)
  }
}
