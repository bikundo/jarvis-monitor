import SwiftUI

struct PopoverView: View {
  var model: AppModel
  var maximumHeight: CGFloat
  var openSettings: () -> Void
  var quit: () -> Void

  var body: some View {
    VStack(spacing: 0) {
      header
      ViewThatFits(in: .vertical) {
        content
        ScrollView {
          content
        }
        .scrollIndicators(.never)
      }
    }
    .frame(width: PopoverController.contentWidth)
    .frame(maxHeight: maximumHeight)
    .fixedSize(horizontal: false, vertical: true)
    .background(Theme.background)
    .preferredColorScheme(.dark)
  }

  private var content: some View {
    SystemTab(model: model)
      .padding(.horizontal, 10)
      .padding(.bottom, 10)
  }

  private var header: some View {
    HStack(spacing: 0) {
      Text("SYSTEM")
        .font(Theme.text(13, .semibold))
        .tracking(0.4)
        .foregroundStyle(Theme.primary)
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .accessibilityAddTraits(.isHeader)

      Spacer(minLength: 8)

      Menu {
        Button("Settings…", action: openSettings)
          .keyboardShortcut(",", modifiers: .command)
        Divider()
        Button("Quit Jarvis", action: quit)
          .keyboardShortcut("q", modifiers: .command)
      } label: {
        Image(systemName: "ellipsis")
          .frame(width: 24, height: 28)
          .contentShape(Rectangle())
      }
      .menuStyle(.button)
      .buttonStyle(.plain)
      .menuIndicator(.hidden)
      .fixedSize()
      .help("Settings and Quit")
      .accessibilityLabel("More")
    }
    .font(.system(size: 13, weight: .medium))
    .foregroundStyle(Theme.secondary)
    .padding(.horizontal, 10)
    .padding(.top, 10)
    .padding(.bottom, 8)
  }
}
