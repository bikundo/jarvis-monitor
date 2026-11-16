import SwiftUI

struct Card<Accessory: View, Content: View>: View {
  var title: String
  var trailing: String?
  @ViewBuilder var accessory: Accessory
  @ViewBuilder var content: Content

  var body: some View {
    VStack(alignment: .leading, spacing: 8) {
      HStack(alignment: .center, spacing: 6) {
        Text(title)
          .font(Theme.text(13, .medium))
          .foregroundStyle(Theme.secondary)
        Spacer(minLength: 4)
        accessory
        if let trailing {
          Text(trailing)
            .font(Theme.number(12))
            .foregroundStyle(Theme.tertiary)
        }
      }
      .lineLimit(1)
      content
    }
    .padding(10)
    .frame(maxWidth: .infinity, alignment: .leading)
    .background(Theme.card, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(Theme.border))
  }
}

extension Card where Accessory == EmptyView {
  init(title: String, trailing: String? = nil, @ViewBuilder content: () -> Content) {
    self.init(title: title, trailing: trailing, accessory: { EmptyView() }, content: content)
  }
}

struct BigValue: View {
  var value: String
  var unit: String?

  var body: some View {
    HStack(alignment: .firstTextBaseline, spacing: 5) {
      Text(value)
        .font(Theme.text(26, .medium))
        .monospacedDigit()
        .foregroundStyle(Theme.primary)
      if let unit {
        Text(unit)
          .font(Theme.text(13))
          .foregroundStyle(Theme.secondary)
      }
    }
    .lineLimit(1)
    .fixedSize()
    .layoutPriority(1)
  }
}

struct Stat: View {
  var label: String
  var value: String

  var body: some View {
    VStack(alignment: .leading, spacing: 2) {
      Text(label)
        .font(Theme.text(12))
        .foregroundStyle(Theme.secondary)
      Text(value)
        .font(Theme.number(15, .medium))
        .foregroundStyle(Theme.primary)
    }
    .lineLimit(1)
    .minimumScaleFactor(0.7)
    .frame(maxWidth: .infinity, alignment: .leading)
    .accessibilityElement(children: .combine)
  }
}

struct Legend: View {
  var color: Color
  var label: String
  var value: String
  var expands = true
  var spread = false

  var body: some View {
    HStack(spacing: 5) {
      Circle().fill(color).frame(width: 6, height: 6)
      Text(label)
        .font(Theme.number(12))
        .foregroundStyle(Theme.secondary)
      if spread {
        Spacer(minLength: 4)
      }
      if !value.isEmpty {
        Text(value)
          .font(Theme.number(12, .medium))
          .foregroundStyle(Theme.primary)
      }
    }
    .lineLimit(1)
    .minimumScaleFactor(0.8)
    .frame(maxWidth: expands ? .infinity : nil, alignment: .leading)
    .accessibilityElement(children: .combine)
  }
}

struct SegmentedBar: View {
  struct Segment: Identifiable {
    var id: Int
    var fraction: Double
    var color: Color
  }

  var segments: [Segment]

  init(_ parts: [(Double, Color)]) {
    segments = parts.enumerated().map { Segment(id: $0.offset, fraction: max(0, $0.element.0), color: $0.element.1) }
  }

  var body: some View {
    GeometryReader { proxy in
      let visible = segments.filter { $0.fraction > 0.004 }
      let total = max(visible.reduce(0) { $0 + $1.fraction }, 0.0001)
      let gap: CGFloat = 3
      let available = max(0, proxy.size.width - gap * CGFloat(max(0, visible.count - 1)))
      HStack(spacing: gap) {
        ForEach(visible) { segment in
          Capsule()
            .fill(segment.color)
            .frame(width: max(3, available * segment.fraction / total))
        }
      }
    }
    .frame(height: 5)
    .accessibilityHidden(true)
  }
}

struct StackedBars: View {
  var series: [[Double]]
  var colors: [Color]
  var slots: Int
  var maximum: Double?

  var body: some View {
    Canvas { context, size in
      for line in 0...3 {
        let y = (size.height - 1) * CGFloat(line) / 3 + 0.5
        var path = Path()
        path.move(to: CGPoint(x: 0, y: y))
        path.addLine(to: CGPoint(x: size.width, y: y))
        context.stroke(path, with: .color(Theme.grid), lineWidth: 1)
      }
      let count = series.map(\.count).max() ?? 0
      guard count > 0, slots > 0 else { return }
      let sums = (0..<count).map { index in
        series.reduce(0) { $0 + (index < $1.count ? $1[index] : 0) }
      }
      let peak = maximum ?? (sums.max() ?? 0)
      guard peak > 0 else { return }
      let slotWidth = size.width / CGFloat(slots)
      let barWidth = max(1, slotWidth * 0.7)
      for index in 0..<count {
        let x = size.width - CGFloat(count - index) * slotWidth + (slotWidth - barWidth) / 2
        var top = size.height
        for (position, values) in series.enumerated() where index < values.count {
          let height = CGFloat(min(1, values[index] / peak)) * size.height
          guard height > 0.2 else { continue }
          let rect = CGRect(x: x, y: top - height, width: barWidth, height: max(0.5, height - 0.6))
          context.fill(Path(rect), with: .color(colors[position % colors.count]))
          top -= height
        }
      }
    }
  }
}

struct LevelChart: View {
  var points: [(offset: TimeInterval, percent: Double)]
  var start: Date?

  private static let axisWidth: CGFloat = 34

  var body: some View {
    VStack(spacing: 4) {
      Canvas { context, size in
        let plotWidth = size.width - Self.axisWidth
        for level in [0.0, 50, 100] {
          let y = (size.height - 1) * CGFloat(1 - level / 100) + 0.5
          var grid = Path()
          grid.move(to: CGPoint(x: 0, y: y))
          grid.addLine(to: CGPoint(x: plotWidth, y: y))
          context.stroke(grid, with: .color(Theme.grid), lineWidth: 1)
          let label = context.resolve(
            Text("\(Int(level))%").font(Theme.number(10)).foregroundStyle(Theme.tertiary)
          )
          let anchor: UnitPoint = level == 100 ? .topTrailing : level == 0 ? .bottomTrailing : .trailing
          context.draw(label, at: CGPoint(x: size.width, y: y), anchor: anchor)
        }
        guard let span = points.last?.offset, span > 0 else { return }
        let positions = points.map { point in
          CGPoint(
            x: plotWidth * CGFloat(point.offset / span),
            y: (size.height - 2) * CGFloat(1 - min(100, max(0, point.percent)) / 100) + 1
          )
        }
        guard let first = positions.first, let last = positions.last else { return }
        var line = Path()
        line.addLines(positions)
        var area = line
        area.addLine(to: CGPoint(x: last.x, y: size.height))
        area.addLine(to: CGPoint(x: first.x, y: size.height))
        area.closeSubpath()
        context.fill(
          area,
          with: .linearGradient(
            Gradient(colors: [Theme.strong.opacity(0.24), Theme.strong.opacity(0)]),
            startPoint: .zero,
            endPoint: CGPoint(x: 0, y: size.height)
          )
        )
        context.stroke(line, with: .color(Theme.strong), style: StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round))
        var marker = Path()
        marker.move(to: CGPoint(x: last.x, y: 0))
        marker.addLine(to: CGPoint(x: last.x, y: size.height))
        context.stroke(marker, with: .color(Theme.soft), style: StrokeStyle(lineWidth: 1, dash: [3, 3]))
        context.fill(Path(ellipseIn: CGRect(x: last.x - 4, y: last.y - 4, width: 8, height: 8)), with: .color(Theme.card))
        context.stroke(Path(ellipseIn: CGRect(x: last.x - 4, y: last.y - 4, width: 8, height: 8)), with: .color(Theme.strong), lineWidth: 2)
      }
      HStack {
        Text(start.map { $0.formatted(date: .omitted, time: .shortened) } ?? "")
        Spacer()
        Text("now")
      }
      .font(Theme.number(11))
      .foregroundStyle(Theme.tertiary)
      .padding(.trailing, Self.axisWidth)
    }
  }
}

struct BarBackground: ViewModifier {
  var fraction: Double

  func body(content: Content) -> some View {
    content
      .lineLimit(1)
      .padding(.horizontal, 6)
      .frame(height: 24)
      .background(alignment: .leading) {
        GeometryReader { proxy in
          RoundedRectangle(cornerRadius: 5)
            .fill(Color.white.opacity(0.11))
            .frame(width: max(4, proxy.size.width * min(1, max(0, fraction))))
        }
      }
      .accessibilityElement(children: .combine)
  }
}
