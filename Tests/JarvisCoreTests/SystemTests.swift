import Foundation
import Testing

@testable import JarvisCore

struct CPULoadTests {
  @Test func `splits tick deltas into user and system shares`() {
    let previous = CPUTicks(user: 100, system: 50, idle: 800, nice: 0)
    let current = CPUTicks(user: 130, system: 60, idle: 860, nice: 0)
    let load = CPULoad(from: previous, to: current)
    #expect(load.user == 0.3)
    #expect(load.system == 0.1)
    #expect(load.busy == 0.4)
  }

  @Test func `counts nice ticks as user time`() {
    let previous = CPUTicks(user: 0, system: 0, idle: 0, nice: 0)
    let current = CPUTicks(user: 10, system: 0, idle: 80, nice: 10)
    #expect(CPULoad(from: previous, to: current).user == 0.2)
  }

  @Test func `survives the tick counters wrapping around`() {
    let previous = CPUTicks(user: .max - 4, system: 0, idle: 0, nice: 0)
    let current = CPUTicks(user: 5, system: 0, idle: 10, nice: 0)
    #expect(CPULoad(from: previous, to: current).user == 0.5)
  }

  @Test func `reports idle when no ticks passed`() {
    let ticks = CPUTicks(user: 7, system: 7, idle: 7, nice: 7)
    #expect(CPULoad(from: ticks, to: ticks) == .idle)
  }

  @Test func `reads live ticks from the kernel`() throws {
    let total = try #require(CPUSampler.readTotalTicks())
    #expect(total.idle > 0)
    #expect(!CPUSampler.readCoreTicks().isEmpty)
  }
}

struct MemoryBreakdownTests {
  let pages = VMPageCounts(
    internalPages: 500,
    purgeablePages: 100,
    wiredPages: 200,
    compressorPages: 300,
    externalPages: 50
  )

  @Test func `matches the Activity Monitor breakdown`() {
    let memory = MemoryBreakdown(pages: pages, pageSize: 10, totalBytes: 10_000)
    #expect(memory.app == 4_000)
    #expect(memory.wired == 2_000)
    #expect(memory.compressed == 3_000)
    #expect(memory.cached == 1_500)
    #expect(memory.used == 9_000)
    #expect(memory.free == 1_000)
    #expect(memory.usedFraction == 0.9)
  }

  @Test func `never reports more used than installed`() {
    let memory = MemoryBreakdown(pages: pages, pageSize: 10, totalBytes: 5_000)
    #expect(memory.used == 5_000)
    #expect(memory.free == 0)
  }

  @Test func `treats more purgeable than internal pages as no app memory`() {
    var pages = pages
    pages.purgeablePages = 900
    #expect(MemoryBreakdown(pages: pages, pageSize: 10, totalBytes: 10_000).app == 0)
  }

  @Test(arguments: [(Int32(1), MemoryPressureLevel.normal), (2, .warning), (4, .critical), (0, .normal)])
  func `maps kernel pressure levels`(kernelLevel: Int32, expected: MemoryPressureLevel) {
    #expect(MemoryPressureLevel(kernelLevel: kernelLevel) == expected)
  }

  @Test func `turns available percent into a pressure fraction`() {
    #expect(MemoryPressure(kernelLevel: 2, availablePercent: 42).fraction == 0.58)
    #expect(MemoryPressure(kernelLevel: 1, availablePercent: 140).fraction == 0)
  }

  @Test func `reads live memory figures`() throws {
    let sampler = MemorySampler()
    let memory = try #require(sampler.breakdown())
    #expect(memory.total > 0)
    #expect(memory.used > 0)
    #expect(sampler.swap() != nil)
    #expect(sampler.pressure() != nil)
  }
}

struct SampleHistoryTests {
  @Test func `keeps samples in order before it fills`() {
    var history = SampleHistory(capacity: 3)
    history.append(1)
    history.append(2)
    #expect(history.values == [1, 2])
  }

  @Test func `drops the oldest samples once full`() {
    var history = SampleHistory(capacity: 3)
    for value in 1...7 {
      history.append(Double(value))
    }
    #expect(history.values == [5, 6, 7])
    #expect(history.count == 3)
  }
}

struct SamplingRateTests {
  @Test(arguments: [
    (SamplingConditions(popoverOpen: false, onBattery: false, lowPowerMode: false, displayAsleep: false), SamplingRate.closed),
    (SamplingConditions(popoverOpen: true, onBattery: false, lowPowerMode: false, displayAsleep: false), .open),
    (SamplingConditions(popoverOpen: true, onBattery: true, lowPowerMode: true, displayAsleep: false), .open),
    (SamplingConditions(popoverOpen: false, onBattery: true, lowPowerMode: false, displayAsleep: false), .saving),
    (SamplingConditions(popoverOpen: false, onBattery: false, lowPowerMode: true, displayAsleep: false), .saving),
    (SamplingConditions(popoverOpen: true, onBattery: false, lowPowerMode: false, displayAsleep: true), .paused),
  ])
  func `picks a rate from the conditions`(conditions: SamplingConditions, expected: SamplingRate) {
    #expect(SamplingRate(conditions) == expected)
  }

  @Test func `allows more timer leeway at slower rates`() {
    #expect(SamplingRate.open.leewayMilliseconds == 500)
    #expect(SamplingRate.closed.leewayMilliseconds == 750)
    #expect(SamplingRate.saving.leewayMilliseconds == 1250)
  }
}

struct BatteryTests {
  @Test func `reads a discharging battery`() throws {
    let state = try #require(BatteryState(description: [
      "Type": "InternalBattery",
      "Current Capacity": 80,
      "Max Capacity": 100,
      "Power Source State": "Battery Power",
      "Is Charging": false,
      "Time to Empty": 215,
    ]))
    #expect(state.percent == 80)
    #expect(state.source == .battery)
    #expect(!state.isCharging)
    #expect(state.minutesRemaining == 215)
  }

  @Test func `reads a charging battery and its time to full`() throws {
    let state = try #require(BatteryState(description: [
      "Type": "InternalBattery",
      "Current Capacity": 41,
      "Max Capacity": 100,
      "Power Source State": "AC Power",
      "Is Charging": true,
      "Time to Full Charge": 62,
      "Time to Empty": 0,
    ]))
    #expect(state.source == .mains)
    #expect(state.isCharging)
    #expect(state.minutesRemaining == 62)
  }

  @Test func `hides the estimate while plugged in and not charging`() throws {
    let state = try #require(BatteryState(description: [
      "Type": "InternalBattery",
      "Current Capacity": 80,
      "Max Capacity": 100,
      "Power Source State": "AC Power",
      "Is Charging": false,
      "Time to Empty": 300,
    ]))
    #expect(state.minutesRemaining == nil)
  }

  @Test func `ignores power sources that are not the internal battery`() {
    #expect(BatteryState(description: ["Type": "UPS", "Current Capacity": 50, "Max Capacity": 100]) == nil)
  }

  @Test func `derives health and wattage from the registry`() {
    let detail = BatteryDetail(registry: [
      "CycleCount": 212,
      "AppleRawMaxCapacity": 4200,
      "DesignCapacity": 4800,
      "Voltage": 12_000,
      "Amperage": -1_500,
    ])
    #expect(detail.cycleCount == 212)
    #expect(detail.healthPercent == 88)
    #expect(detail.batteryWatts == -18)
    #expect(detail.systemWatts == nil)
  }

  @Test func `reads capacity and system draw from the nested dictionaries newer systems use`() {
    let detail = BatteryDetail(registry: [
      "CycleCount": 102,
      "Voltage": 12_367,
      "Amperage": 0,
      "BatteryData": ["DesignCapacity": 6249, "NominalChargeCapacity": 6233],
      "PowerTelemetryData": ["SystemLoad": 14_115],
    ])
    #expect(detail.healthPercent == 100)
    #expect(detail.batteryWatts == 0)
    #expect(detail.systemWatts == 14.115)
  }

  @Test func `names a process owned by another user`() {
    #expect(ProcessSampler.name(of: 1) == "launchd")
  }
}

struct BatteryHistoryTests {
  let start = Date(timeIntervalSince1970: 1_000_000)

  @Test func `records changes and skips repeats inside ten minutes`() {
    var history = BatteryHistory()
    let changes = [
      history.record(percent: 80, charging: false, at: start),
      history.record(percent: 80, charging: false, at: start.addingTimeInterval(120)),
      history.record(percent: 79, charging: false, at: start.addingTimeInterval(180)),
      history.record(percent: 79, charging: true, at: start.addingTimeInterval(200)),
      history.record(percent: 79, charging: true, at: start.addingTimeInterval(200 + 600)),
    ]
    #expect(changes == [true, false, true, true, true])
    #expect(history.samples.map(\.percent) == [80, 79, 79, 79])
  }

  @Test func `drops samples older than a day`() {
    var history = BatteryHistory()
    history.record(percent: 50, charging: false, at: start)
    history.record(percent: 40, charging: false, at: start.addingTimeInterval(3_600))
    history.record(percent: 90, charging: true, at: start.addingTimeInterval(BatteryHistory.window + 1_800))
    #expect(history.samples.map(\.percent) == [40, 90])
  }

  @Test func `extends the line to the present at the last level`() {
    var history = BatteryHistory()
    history.record(percent: 60, charging: false, at: start)
    history.record(percent: 55, charging: false, at: start.addingTimeInterval(1_200))
    let points = history.points(endingAt: start.addingTimeInterval(1_500))
    #expect(points.map(\.offset) == [0, 1_200, 1_500])
    #expect(points.map(\.percent) == [60, 55, 55])
    #expect(BatteryHistory().points(endingAt: start).isEmpty)
  }

  @Test func `survives being saved and loaded`() throws {
    var history = BatteryHistory()
    history.record(percent: 60, charging: true, at: start)
    let data = try JSONEncoder().encode(history)
    #expect(try JSONDecoder().decode(BatteryHistory.self, from: data) == history)
  }
}

struct MacAgeTests {
  static var calendar: Calendar {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(identifier: "UTC")!
    return calendar
  }

  static func date(_ year: Int, _ month: Int, _ day: Int) -> Date {
    calendar.date(from: DateComponents(year: year, month: month, day: day))!
  }

  @Test(arguments: [
    (date(2024, 12, 1), date(2026, 11, 11), "1 yr 11 mo"),
    (date(2024, 11, 11), date(2026, 11, 11), "2 yr"),
    (date(2026, 8, 2), date(2026, 11, 11), "3 mo"),
    (date(2026, 11, 10), date(2026, 11, 11), "1 day"),
    (date(2026, 11, 1), date(2026, 11, 11), "10 days"),
    (date(2026, 11, 11), date(2026, 11, 11), "0 days"),
    (date(2026, 12, 1), date(2026, 11, 11), "0 days"),
  ])
  func `describes how long the Mac has been in use`(start: Date, end: Date, expected: String) {
    #expect(MacAge.describe(from: start, to: end, calendar: Self.calendar) == expected)
  }

  @Test func `finds when this Mac was set up`() throws {
    let setup = try #require(MacAge.setupDate())
    #expect(setup < Date())
  }
}

struct TemperatureTests {
  @Test func `averages the processor die sensors and ignores bad readings`() throws {
    let temperatures = try #require(Temperatures(readings: [
      (name: "PMU tdie1", celsius: 40),
      (name: "PMU2 tdie4", celsius: 50),
      (name: "PMU tdev5", celsius: -9202.9),
      (name: "PMU tdie9", celsius: 999),
      (name: "NAND CH0 temp", celsius: 70),
      (name: "gas gauge battery", celsius: 29),
      (name: "gas gauge battery", celsius: 31),
    ]))
    #expect(temperatures.processor == 45)
    #expect(temperatures.hottest == 50)
    #expect(temperatures.battery == 30)
  }

  @Test func `keeps reading live sensors after the reader has been stored`() throws {
    let reader = try #require(TemperatureReader())
    for _ in 0..<3 {
      let temperatures = try #require(reader.read())
      #expect((1...130).contains(temperatures.processor))
      #expect(temperatures.hottest >= temperatures.processor)
    }
  }

  @Test func `reports nothing without processor sensors`() {
    #expect(Temperatures(readings: [(name: "gas gauge battery", celsius: 29)]) == nil)
    #expect(Temperatures(readings: []) == nil)
  }
}

struct WiFiTests {
  @Test(arguments: [(-40, WiFiQuality.excellent, 4), (-55, .excellent, 4), (-56, .good, 3), (-67, .good, 3), (-70, .fair, 2), (-76, .weak, 1), (-95, .weak, 1)])
  func `grades signal strength`(rssi: Int, quality: WiFiQuality, bars: Int) {
    #expect(WiFiQuality(rssi: rssi) == quality)
    #expect(quality.bars == bars)
  }

  @Test func `has no signal when Wi-Fi is off or not connected`() {
    #expect(WiFiSignal(interface: "en0", poweredOn: false, rssi: -40, megabitsPerSecond: 866, gigahertz: 5) == nil)
    #expect(WiFiSignal(interface: "en0", poweredOn: true, rssi: 0, megabitsPerSecond: 0, gigahertz: nil) == nil)
    #expect(WiFiSignal(interface: "en0", poweredOn: true, rssi: -40, megabitsPerSecond: 866, gigahertz: 5)?.quality == .excellent)
  }
}

struct NetworkTests {
  @Test func `turns byte counters into bits per second`() throws {
    let rate = try #require(NetworkRate(
      from: NetworkTotals(received: 1_000_000, sent: 500_000),
      to: NetworkTotals(received: 1_250_000, sent: 500_500),
      elapsedSeconds: 2
    ))
    #expect(rate.downBitsPerSecond == 1_000_000)
    #expect(rate.upBitsPerSecond == 2_000)
  }

  @Test func `gives no rate when counters reset or no time passed`() {
    let high = NetworkTotals(received: 10, sent: 10)
    let low = NetworkTotals(received: 5, sent: 10)
    #expect(NetworkRate(from: high, to: low, elapsedSeconds: 2) == nil)
    #expect(NetworkRate(from: low, to: high, elapsedSeconds: 0) == nil)
  }

  @Test func `reads full-size totals from netstat`() {
    let output = """
      Name       Mtu   Network       Address            Ipkts Ierrs     Ibytes    Opkts Oerrs     Obytes  Coll
      en0        1500  <Link#14>   aa:bb:cc:dd:ee:ff 98765432     0 119141328625 54321098     0 50123736586     0
      en0        1500  192.168.1     192.168.1.20      98765432     - 119141328625 54321098     - 50123736586     -
      """
    #expect(NetstatOutput.parse(output) == NetworkTotals(received: 119_141_328_625, sent: 50_123_736_586))
    #expect(NetstatOutput.parse("netstat: interface nope99 not found") == nil)
    #expect(NetstatOutput.parse("") == nil)
  }

  @Test func `keeps a network name only when there is one`() {
    #expect(WiFiSignal(interface: "en0", name: "Home", poweredOn: true, rssi: -50, megabitsPerSecond: 1, gigahertz: 5)?.name == "Home")
    #expect(WiFiSignal(interface: "en0", name: "", poweredOn: true, rssi: -50, megabitsPerSecond: 1, gigahertz: 5)?.name == nil)
  }

  @Test func `reads live counters for the loopback interface and the boot date`() throws {
    let totals = try #require(NetworkCounters.totals(interface: "lo0"))
    #expect(totals.combined > 0)
    #expect(NetworkCounters.totals(interface: "nope99") == nil)
    let boot = try #require(NetworkCounters.bootDate())
    #expect(boot < Date())
  }
}

struct ProcessTests {
  static let sample = """
    Processes: 695 total, 3 running, 692 sleeping, 6337 threads
    2026/11/11 20:18:17
    Load Avg: 3.61, 3.04, 2.90
    PhysMem: 23G used (4685M wired, 11G compressor), 158M unused.

    PID    TIME      MEM    COMMAND
    397    3517:54.73 2337M+ WindowServer
    1      217:32.95 21M    launchd
    325    01:02:03  9856K- XProtect Helper
    99999  0:00.10   0B     x
    """

  @Test func `parses process rows and skips the header`() {
    let rows = TopOutput.parse(Self.sample)
    #expect(rows.count == 4)
    #expect(rows[0] == TopRow(pid: 397, cpuSeconds: 211_074.73, footprintBytes: 2337 * 1_048_576, command: "WindowServer"))
    #expect(rows[1].footprintBytes == 21 * 1_048_576)
    #expect(rows[2] == TopRow(pid: 325, cpuSeconds: 3723, footprintBytes: 9856 * 1024, command: "XProtect Helper"))
    #expect(rows[3].footprintBytes == 0)
  }

  @Test(arguments: ["", "12Q", "M", "-5M"])
  func `rejects malformed memory fields`(field: String) {
    #expect(TopOutput.bytes(Substring(field)) == nil)
  }

  @Test func `ranks processes it cannot read from top rows and derives their CPU share`() {
    var sampler = ProcessSampler()
    let pid = Int32.max - 1
    sampler.ingest(
      rows: [TopRow(pid: pid, cpuSeconds: 10, footprintBytes: 1 << 50, command: "ghost")],
      uptimeNanoseconds: 1_000_000_000
    )
    #expect(sampler.topGroups(by: .memory, limit: 1).first?.name == "ghost")
    #expect(sampler.topGroups(by: .memory, limit: 1).first?.cpuPercent == 0)

    sampler.ingest(
      rows: [TopRow(pid: pid, cpuSeconds: 15, footprintBytes: 1 << 50, command: "ghost")],
      uptimeNanoseconds: 11_000_000_000
    )
    #expect(sampler.topGroups(by: .memory, limit: 1).first?.cpuPercent == 50)
  }

  @Test func `prefers its own reading over a top row for the same process`() {
    var sampler = ProcessSampler()
    sampler.sampleOwnProcesses()
    let own = getpid()
    let ownName = ProcessGroup.appName(forProcess: ProcessSampler.name(of: own) ?? "")
    sampler.ingest(
      rows: [TopRow(pid: own, cpuSeconds: 0, footprintBytes: 1 << 50, command: "ghost")],
      uptimeNanoseconds: ProcessSampler.uptimeNanoseconds
    )
    let groups = sampler.topGroups(by: .memory, limit: 10_000)
    let entry = groups.first { $0.name == ownName }
    #expect(entry != nil)
    #expect((entry?.footprintBytes ?? .max) < 1 << 50)
    #expect(!groups.contains { $0.name == "ghost" })
  }

  @Test func `adds helper processes to their app`() {
    var sampler = ProcessSampler()
    sampler.ingest(
      rows: [
        TopRow(pid: .max - 1, cpuSeconds: 0, footprintBytes: 3 << 50, command: "Phantom Browser"),
        TopRow(pid: .max - 2, cpuSeconds: 0, footprintBytes: 2 << 50, command: "Phantom Browser Helper (Renderer)"),
        TopRow(pid: .max - 3, cpuSeconds: 0, footprintBytes: 1 << 50, command: "Phantom Browser Helper (GPU)"),
      ],
      uptimeNanoseconds: 1_000_000_000
    )
    let top = sampler.topGroups(by: .memory, limit: 1).first
    #expect(top == ProcessGroup(name: "Phantom Browser", footprintBytes: 6 << 50, cpuPercent: 0, processCount: 3))
  }

  @Test(arguments: [
    ("Brave Browser Helper (Aperitif", "Brave Browser"),
    ("Antigravity IDE Helper (GPU)", "Antigravity IDE"),
    ("Slack Helper", "Slack"),
    ("Safari Web Content", "Safari"),
    ("node", "node"),
    (" Helper", " Helper"),
  ])
  func `derives the app a process belongs to`(process: String, app: String) {
    #expect(ProcessGroup.appName(forProcess: process) == app)
  }
}
