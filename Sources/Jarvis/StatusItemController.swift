import AppKit

final class StatusItemController: NSObject {
  private let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
  private let model: AppModel
  private let popover: PopoverController
  private let readout = MenuBarReadout()

  init(model: AppModel) {
    self.model = model
    popover = PopoverController(model: model)
    super.init()
    if let button = statusItem.button {
      button.target = self
      button.action = #selector(togglePopover)
      button.imagePosition = .imageOnly
      button.setAccessibilityLabel("Jarvis")
      readout.frame = button.bounds
      readout.autoresizingMask = [.width, .height]
      button.addSubview(readout)
    }
    model.onMenuBarChange = { [weak self] in self?.render() }
    render()
  }

  @objc private func togglePopover() {
    guard let button = statusItem.button else { return }
    popover.toggle(relativeTo: button)
  }

  private func render() {
    let items = model.menuBarItems
    guard let button = statusItem.button else { return }
    readout.items = items
    readout.isHidden = items.isEmpty
    if items.isEmpty {
      button.image = Self.glyph
      statusItem.length = NSStatusItem.variableLength
    } else {
      button.image = nil
      statusItem.length = MenuBarReadout.width(for: items.count)
    }
    button.setAccessibilityValue(items.map { "\($0.label) \($0.value)" }.joined(separator: ", "))
  }
}

extension StatusItemController {
  static let glyph: NSImage = {
    let side: CGFloat = 18
    let image = NSImage(size: NSSize(width: side, height: side), flipped: false) { _ in
      let shape: [(CGFloat, CGFloat)] = [(0.06, 0.24), (0.26, 0.42), (0.42, 0.33), (0.6, 0.6), (0.74, 0.52), (0.84, 0.72)]
      let points = shape.map { NSPoint(x: side * $0.0, y: side * $0.1) }
      let line = NSBezierPath()
      line.move(to: points[0])
      for index in 0..<(points.count - 1) {
        let before = points[max(index - 1, 0)]
        let start = points[index]
        let end = points[index + 1]
        let after = points[min(index + 2, points.count - 1)]
        line.curve(
          to: end,
          controlPoint1: NSPoint(x: start.x + (end.x - before.x) / 6, y: start.y + (end.y - before.y) / 6),
          controlPoint2: NSPoint(x: end.x - (after.x - start.x) / 6, y: end.y - (after.y - start.y) / 6)
        )
      }
      NSColor.black.setStroke()
      line.lineWidth = 1.8
      line.lineCapStyle = .round
      line.lineJoinStyle = .round
      line.stroke()
      let ring = NSBezierPath(ovalIn: NSRect(x: side * 0.72, y: side * 0.66, width: side * 0.24, height: side * 0.24))
      ring.lineWidth = 1.5
      NSGraphicsContext.current?.cgContext.setBlendMode(.clear)
      ring.fill()
      NSGraphicsContext.current?.cgContext.setBlendMode(.normal)
      ring.stroke()
      return true
    }
    image.isTemplate = true
    image.accessibilityDescription = "Jarvis"
    return image
  }()
}

final class MenuBarReadout: NSView {
  private static let labelFont = NSFont.systemFont(ofSize: 8, weight: .semibold)
  private static let valueFont = NSFont.monospacedDigitSystemFont(ofSize: 12, weight: .medium)
  private static let spacing: CGFloat = 6
  private static let padding: CGFloat = 5
  private static let contentHeight: CGFloat = 22

  private static let columnWidth: CGFloat = {
    let widest = NSAttributedString(string: "100%", attributes: [.font: valueFont]).size().width
    return ceil(widest)
  }()

  static func width(for count: Int) -> CGFloat {
    CGFloat(count) * columnWidth + CGFloat(max(0, count - 1)) * spacing + padding * 2
  }

  var items: [MenuBarItem] = [] {
    didSet {
      guard items != oldValue else { return }
      needsDisplay = true
    }
  }

  override func hitTest(_ point: NSPoint) -> NSView? {
    nil
  }

  override func draw(_ dirtyRect: NSRect) {
    let highlighted = (superview as? NSStatusBarButton)?.isHighlighted ?? false
    let color = highlighted ? NSColor.selectedMenuItemTextColor : NSColor.labelColor
    let labelAttributes: [NSAttributedString.Key: Any] = [
      .font: Self.labelFont,
      .foregroundColor: color,
      .kern: 0.4,
    ]
    let valueAttributes: [NSAttributedString.Key: Any] = [.font: Self.valueFont, .foregroundColor: color]
    let baseY = ((bounds.height - Self.contentHeight) / 2).rounded()
    for (index, item) in items.enumerated() {
      let originX = Self.padding + CGFloat(index) * (Self.columnWidth + Self.spacing)
      let label = NSAttributedString(string: item.label, attributes: labelAttributes)
      let value = NSAttributedString(string: item.value, attributes: valueAttributes)
      let labelWidth = label.size().width
      let valueWidth = value.size().width
      label.draw(at: NSPoint(x: (originX + (Self.columnWidth - labelWidth) / 2).rounded(), y: baseY + 12))
      value.draw(at: NSPoint(x: (originX + (Self.columnWidth - valueWidth) / 2).rounded(), y: baseY - 1))
    }
  }
}
