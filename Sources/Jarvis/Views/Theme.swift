import SwiftUI

enum Theme {
  static let background = Color(red: 0.035, green: 0.035, blue: 0.04)
  static let card = Color(red: 0.07, green: 0.07, blue: 0.075)
  static let raised = Color(red: 0.11, green: 0.11, blue: 0.118)
  static let border = Color.white.opacity(0.04)
  static let grid = Color.white.opacity(0.06)
  static let primary = Color.white.opacity(0.94)
  static let secondary = Color.white.opacity(0.7)
  static let tertiary = Color.white.opacity(0.48)

  static let strong = Color.white.opacity(0.92)
  static let medium = Color.white.opacity(0.64)
  static let soft = Color.white.opacity(0.36)
  static let alert = Color(red: 1, green: 0.32, blue: 0.28)
  static let idle = Color.white.opacity(0.2)

  static func number(_ size: CGFloat, _ weight: Font.Weight = .regular) -> Font {
    .system(size: size, weight: weight).monospacedDigit()
  }

  static func text(_ size: CGFloat, _ weight: Font.Weight = .regular) -> Font {
    .system(size: size, weight: weight)
  }
}
