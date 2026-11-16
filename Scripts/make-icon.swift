import AppKit

let arguments = CommandLine.arguments
guard arguments.count == 2 else {
  FileHandle.standardError.write(Data("usage: make-icon.swift <output.iconset>\n".utf8))
  exit(64)
}
let output = URL(fileURLWithPath: arguments[1])
try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)

func smoothPath(through points: [NSPoint]) -> NSBezierPath {
  let path = NSBezierPath()
  path.move(to: points[0])
  for index in 0..<(points.count - 1) {
    let before = points[max(index - 1, 0)]
    let start = points[index]
    let end = points[index + 1]
    let after = points[min(index + 2, points.count - 1)]
    let first = NSPoint(x: start.x + (end.x - before.x) / 6, y: start.y + (end.y - before.y) / 6)
    let second = NSPoint(x: end.x - (after.x - start.x) / 6, y: end.y - (after.y - start.y) / 6)
    path.curve(to: end, controlPoint1: first, controlPoint2: second)
  }
  return path
}

func render(pixels: Int) -> Data {
  let bitmap = NSBitmapImageRep(
    bitmapDataPlanes: nil,
    pixelsWide: pixels,
    pixelsHigh: pixels,
    bitsPerSample: 8,
    samplesPerPixel: 4,
    hasAlpha: true,
    isPlanar: false,
    colorSpaceName: .deviceRGB,
    bytesPerRow: 0,
    bitsPerPixel: 0
  )!
  NSGraphicsContext.saveGraphicsState()
  NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: bitmap)
  let size = CGFloat(pixels)
  let inset = size * 0.1
  let tile = NSRect(x: inset, y: inset, width: size - inset * 2, height: size - inset * 2)
  let radius = tile.width * 0.225
  let shape = NSBezierPath(roundedRect: tile, xRadius: radius, yRadius: radius)

  NSGradient(
    starting: NSColor(white: 0.16, alpha: 1),
    ending: NSColor(white: 0.035, alpha: 1)
  )!.draw(in: shape, angle: -90)

  NSGraphicsContext.saveGraphicsState()
  shape.addClip()

  let plot = tile.insetBy(dx: tile.width * 0.16, dy: tile.height * 0.2)
  if pixels >= 128 {
    NSColor(white: 1, alpha: 0.07).setStroke()
    for step in 0...3 {
      let y = plot.minY + plot.height * CGFloat(step) / 3
      let line = NSBezierPath()
      line.move(to: NSPoint(x: plot.minX, y: y))
      line.line(to: NSPoint(x: plot.maxX, y: y))
      line.lineWidth = max(1, size * 0.004)
      line.stroke()
    }
  }

  let shape01: [(CGFloat, CGFloat)] = [(0, 0.16), (0.2, 0.36), (0.38, 0.27), (0.58, 0.6), (0.76, 0.5), (1, 0.9)]
  let left = tile.minX - size * 0.03
  let points = shape01.map { NSPoint(x: left + (plot.maxX - left) * $0.0, y: plot.minY + plot.height * $0.1) }
  let line = smoothPath(through: points)

  let area = line.copy() as! NSBezierPath
  area.line(to: NSPoint(x: plot.maxX, y: tile.minY))
  area.line(to: NSPoint(x: left, y: tile.minY))
  area.close()
  NSGraphicsContext.saveGraphicsState()
  area.addClip()
  NSGradient(
    starting: NSColor(white: 1, alpha: 0.3),
    ending: NSColor(white: 1, alpha: 0)
  )!.draw(in: NSRect(x: tile.minX, y: tile.minY, width: tile.width, height: plot.maxY - tile.minY), angle: -90)
  NSGraphicsContext.restoreGraphicsState()

  NSColor(white: 0.97, alpha: 1).setStroke()
  line.lineWidth = size * (pixels >= 128 ? 0.042 : 0.075)
  line.lineCapStyle = .round
  line.lineJoinStyle = .round
  line.stroke()

  if let last = points.last, pixels >= 64 {
    let outer = size * 0.062
    let ring = NSBezierPath(ovalIn: NSRect(x: last.x - outer, y: last.y - outer, width: outer * 2, height: outer * 2))
    NSColor(white: 0.07, alpha: 1).setFill()
    ring.fill()
    NSColor(white: 0.97, alpha: 1).setStroke()
    ring.lineWidth = size * 0.03
    ring.stroke()
  }
  NSGraphicsContext.restoreGraphicsState()

  NSColor(white: 1, alpha: 0.12).setStroke()
  shape.lineWidth = max(1, size * 0.006)
  shape.stroke()

  NSGraphicsContext.restoreGraphicsState()
  return bitmap.representation(using: .png, properties: [:])!
}

let variants: [(String, Int)] = [
  ("icon_16x16", 16), ("icon_16x16@2x", 32), ("icon_32x32", 32), ("icon_32x32@2x", 64),
  ("icon_128x128", 128), ("icon_128x128@2x", 256), ("icon_256x256", 256), ("icon_256x256@2x", 512),
  ("icon_512x512", 512), ("icon_512x512@2x", 1024),
]
for (name, pixels) in variants {
  try render(pixels: pixels).write(to: output.appendingPathComponent("\(name).png"))
}
