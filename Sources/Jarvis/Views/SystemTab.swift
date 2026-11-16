import JarvisCore
import SwiftUI

struct SystemTab: View {
  var model: AppModel

  var body: some View {
    VStack(spacing: 8) {
      cpuCard
      memoryCard
      batteryCard
      wifiCard
      processCard
    }
  }

  private var cpuCard: some View {
    Card(title: "CPU", trailing: cpuSummary) {
      HStack(alignment: .firstTextBaseline, spacing: 10) {
        BigValue(value: Format.percent(model.cpu.busy), unit: nil)
        Spacer()
        Legend(color: Theme.strong, label: "Apps", value: Format.percent(model.cpu.user), expands: false)
        Legend(color: Theme.medium, label: "System", value: Format.percent(model.cpu.system), expands: false)
      }
      StackedBars(
        series: [model.cpuSystemHistory.values, model.cpuUserHistory.values],
        colors: [Theme.medium, Theme.strong],
        slots: AppModel.historyLength,
        maximum: 1
      )
      .frame(height: 44)
      .accessibilityLabel("How busy the processor has been")
      if !model.cores.isEmpty {
        HStack(alignment: .bottom, spacing: 3) {
          ForEach(Array(model.cores.enumerated()), id: \.offset) { _, core in
            CoreBar(load: core.busy)
          }
        }
        .frame(height: 14)
        .accessibilityElement()
        .accessibilityLabel("How busy each core is")
        .accessibilityValue(model.cores.map { Format.percent($0.busy) }.joined(separator: ", "))
      }
    }
  }

  private var cpuSummary: String? {
    let cores = model.cores.isEmpty ? nil : "\(model.cores.count) cores"
    let heat = model.temperatures.map { "\(Int($0.processor.rounded()))°C" }
    let parts = [heat, cores].compactMap { $0 }
    return parts.isEmpty ? nil : parts.joined(separator: ", ")
  }

  @ViewBuilder private var wifiCard: some View {
    if let wifi = model.wifi {
      Card(title: wifi.name ?? "Wi-Fi", trailing: signalSummary(wifi)) {
        HStack(alignment: .bottom, spacing: 2.5) {
          ForEach(1...4, id: \.self) { bar in
            RoundedRectangle(cornerRadius: 1)
              .fill(bar <= wifi.quality.bars ? Theme.strong : Theme.idle)
              .frame(width: 3.5, height: CGFloat(2 + bar * 3))
          }
        }
        .accessibilityHidden(true)
      } content: {
        HStack(alignment: .firstTextBaseline) {
          trafficValue("arrow.down", model.networkRate?.downBitsPerSecond, "Download")
          Spacer()
          trafficValue("arrow.up", model.networkRate?.upBitsPerSecond, "Upload")
        }
        HStack {
          Text("Mbps right now")
          Spacer()
          if let totals = model.dataUsed, let bootDate = model.bootDate {
            Text("\(Format.dataUsed(totals.combined)) since \(bootDate.formatted(.dateTime.day().month(.abbreviated)))")
              .help("Data sent and received over Wi-Fi since this Mac last started")
          }
        }
        .font(Theme.number(12))
        .foregroundStyle(Theme.tertiary)
        .lineLimit(1)
      }
    }
  }

  private func trafficValue(_ symbol: String, _ bitsPerSecond: Double?, _ name: String) -> some View {
    HStack(alignment: .firstTextBaseline, spacing: 4) {
      Image(systemName: symbol)
        .font(.system(size: 13, weight: .semibold))
        .foregroundStyle(Theme.secondary)
      Text(Format.megabits(bitsPerSecond))
        .font(Theme.text(26, .medium))
        .monospacedDigit()
        .foregroundStyle(Theme.primary)
    }
    .accessibilityElement()
    .accessibilityLabel(name)
    .accessibilityValue("\(Format.megabits(bitsPerSecond)) megabits per second")
  }

  private func signalSummary(_ wifi: WiFiSignal) -> String {
    let band = wifi.gigahertz.map { ", \($0.formatted()) GHz" } ?? ""
    return "\(signalName(wifi.quality))\(band)"
  }

  private func signalName(_ quality: WiFiQuality) -> String {
    switch quality {
    case .excellent: "Excellent"
    case .good: "Good"
    case .fair: "Fair"
    case .weak: "Weak"
    }
  }

  @ViewBuilder private var memoryCard: some View {
    if let memory = model.memory {
      Card(title: "Memory", trailing: "of \(Format.bytes(memory.total))") {
        HStack(alignment: .firstTextBaseline) {
          BigValue(value: Format.gigabytes(memory.used), unit: "GB")
          Spacer()
          PressureBadge(pressure: model.pressure)
        }
        StackedBars(
          series: [
            model.memoryCompressedHistory.values,
            model.memoryWiredHistory.values,
            model.memoryAppHistory.values,
          ],
          colors: [Theme.soft, Theme.medium, Theme.strong],
          slots: AppModel.historyLength,
          maximum: 1
        )
        .frame(height: 44)
        .accessibilityLabel("How much memory has been in use")
        SegmentedBar([
          (Double(memory.app), Theme.strong),
          (Double(memory.wired), Theme.medium),
          (Double(memory.compressed), Theme.soft),
          (Double(memory.free), Theme.idle),
        ])
        Grid(alignment: .leading, horizontalSpacing: 22, verticalSpacing: 5) {
          GridRow {
            Legend(color: Theme.strong, label: "Apps", value: Format.shortBytes(memory.app), spread: true)
            Legend(color: Theme.medium, label: "System", value: Format.shortBytes(memory.wired), spread: true)
          }
          GridRow {
            Legend(color: Theme.soft, label: "Compressed", value: Format.shortBytes(memory.compressed), spread: true)
            Legend(color: Theme.idle, label: "Free", value: Format.shortBytes(memory.free), spread: true)
          }
          GridRow {
            Legend(color: .clear, label: "Cached", value: Format.shortBytes(memory.cached), spread: true)
            Legend(color: .clear, label: "Swap", value: model.swap.map { Format.shortBytes($0.used) } ?? "n/a", spread: true)
          }
        }
      }
    }
  }

  @ViewBuilder private var batteryCard: some View {
    if let battery = model.battery {
      Card(title: "Battery", trailing: batteryStatus(battery)) {
        HStack(alignment: .firstTextBaseline) {
          BigValue(value: "\(battery.percent)%", unit: nil)
            .foregroundStyle(battery.percent <= 20 && battery.source == .battery ? Theme.alert : Theme.primary)
          Spacer()
          if let minutes = battery.minutesRemaining {
            Text(battery.isCharging ? "Full in \(Format.duration(minutes: minutes))" : "\(Format.duration(minutes: minutes)) left")
              .font(Theme.number(12))
              .foregroundStyle(Theme.secondary)
          }
        }
        LevelChart(
          points: model.batteryHistory.points(endingAt: Date()),
          start: model.batteryHistory.samples.first?.date
        )
        .frame(height: 64)
        .accessibilityLabel("Battery level since \(model.batteryHistory.samples.first?.date.formatted(date: .omitted, time: .shortened) ?? "launch")")
        if let detail = model.batteryDetail {
          HStack(spacing: 6) {
            Stat(label: "Health", value: detail.healthPercent.map { "\($0)%" } ?? "n/a")
            Stat(label: "Cycles", value: detail.cycleCount.map(Format.number) ?? "n/a")
            if let setupDate = model.setupDate {
              Stat(label: "Age", value: MacAge.describe(from: setupDate, to: Date()))
                .help("This Mac was set up on \(setupDate.formatted(date: .long, time: .omitted))")
            }
          }
        }
      }
    }
  }

  private var processCard: some View {
    let order = model.settings.processOrder
    let peak = model.processes.first.map { order == .memory ? Double($0.footprintBytes) : $0.cpuPercent } ?? 0
    return Card(title: "Apps") {
      HStack(spacing: 0) {
        sortButton("CPU", .cpu).frame(width: ProcessRow.cpuWidth, alignment: .trailing)
        sortButton("Memory", .memory).frame(width: ProcessRow.memoryWidth, alignment: .trailing)
      }
    } content: {
      if model.processes.isEmpty {
        Text("Checking what's running")
          .font(Theme.text(13))
          .foregroundStyle(Theme.tertiary)
      }
      VStack(spacing: 2) {
        ForEach(model.processes) { process in
          let amount = order == .memory ? Double(process.footprintBytes) : process.cpuPercent
          ProcessRow(process: process, order: order, fraction: peak > 0 ? amount / peak : 0)
        }
      }
      .padding(.horizontal, -6)
    }
  }

  private func sortButton(_ title: String, _ choice: ProcessOrder) -> some View {
    let selected = model.settings.processOrder == choice
    return Button {
      model.settings.processOrder = choice
      model.publishProcesses()
    } label: {
      HStack(spacing: 3) {
        Image(systemName: "chevron.down")
          .font(.system(size: 8, weight: .bold))
          .opacity(selected ? 1 : 0)
        Text(title)
      }
      .font(Theme.text(12, selected ? .semibold : .regular))
      .foregroundStyle(selected ? Theme.primary : Theme.tertiary)
      .padding(.vertical, 3)
      .contentShape(Rectangle())
    }
    .buttonStyle(.plain)
    .accessibilityLabel("Sort by \(title)")
    .accessibilityAddTraits(selected ? .isSelected : [])
  }

  private func batteryStatus(_ battery: BatteryState) -> String {
    if battery.isCharging { return "Charging" }
    if battery.source == .battery { return "On battery" }
    return battery.isCharged ? "Fully charged" : "Plugged in"
  }

}

struct CoreBar: View {
  var load: Double

  var body: some View {
    GeometryReader { proxy in
      ZStack(alignment: .bottom) {
        RoundedRectangle(cornerRadius: 2).fill(Theme.grid)
        RoundedRectangle(cornerRadius: 2)
          .fill(Theme.strong)
          .frame(height: max(2, proxy.size.height * min(1, max(0, load))))
      }
    }
  }
}

struct PressureBadge: View {
  var pressure: MemoryPressure?

  var body: some View {
    if let pressure {
      Legend(color: color(pressure.level), label: "Pressure", value: Format.percent(pressure.fraction), expands: false)
        .help(label(pressure.level))
    }
  }

  private func color(_ level: MemoryPressureLevel) -> Color {
    switch level {
    case .normal: Theme.soft
    case .warning: Theme.strong
    case .critical: Theme.alert
    }
  }

  private func label(_ level: MemoryPressureLevel) -> String {
    switch level {
    case .normal: "Plenty of memory to go around"
    case .warning: "Memory is getting tight"
    case .critical: "The Mac is running out of memory"
    }
  }
}

struct ProcessRow: View {
  static let cpuWidth: CGFloat = 62
  static let memoryWidth: CGFloat = 84

  var process: ProcessGroup
  var order: ProcessOrder
  var fraction: Double

  var body: some View {
    HStack(spacing: 0) {
      Text(process.name)
        .font(Theme.text(13))
        .foregroundStyle(Theme.primary)
        .truncationMode(.tail)
      Spacer(minLength: 6)
      Text("\(process.cpuPercent.formatted(.number.precision(.fractionLength(1))))%")
        .foregroundStyle(order == .cpu ? Theme.primary : Theme.secondary)
        .frame(width: Self.cpuWidth, alignment: .trailing)
      Text(Format.bytes(process.footprintBytes))
        .foregroundStyle(order == .memory ? Theme.primary : Theme.secondary)
        .frame(width: Self.memoryWidth, alignment: .trailing)
    }
    .font(Theme.number(12))
    .modifier(BarBackground(fraction: fraction))
    .help(process.processCount == 1 ? process.name : "\(process.name): \(process.processCount) processes")
  }
}
