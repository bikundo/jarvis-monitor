import AppKit
import SwiftUI

final class PopoverController: NSObject, NSPopoverDelegate, NSWindowDelegate {
  static let contentWidth: CGFloat = 380

  private let model: AppModel
  private let popover = NSPopover()
  private var settingsWindow: NSWindow?

  init(model: AppModel) {
    self.model = model
    super.init()
    popover.behavior = .transient
    popover.animates = false
    popover.delegate = self
    popover.appearance = NSAppearance(named: .darkAqua)
  }

  func toggle(relativeTo button: NSStatusBarButton) {
    if popover.isShown {
      popover.performClose(nil)
      return
    }
    let screenHeight = (button.window?.screen ?? NSScreen.main)?.visibleFrame.height ?? 800
    let root = PopoverView(
      model: model,
      maximumHeight: max(320, screenHeight - 24),
      openSettings: { [weak self] in self?.showSettings() },
      quit: { NSApp.terminate(nil) }
    )
    let controller = NSHostingController(rootView: root)
    controller.sizingOptions = [.preferredContentSize]
    popover.contentViewController = controller
    model.setPopoverOpen(true)
    NSApp.activate()
    popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
    popover.contentViewController?.view.window?.makeKey()
  }

  func popoverDidClose(_ notification: Notification) {
    model.setPopoverOpen(false)
    popover.contentViewController = nil
  }

  func showSettings() {
    popover.performClose(nil)
    if settingsWindow == nil {
      let controller = NSHostingController(rootView: SettingsView(model: model))
      let window = NSWindow(contentViewController: controller)
      window.title = "Jarvis Settings"
      window.styleMask = [.titled, .closable]
      window.isReleasedWhenClosed = false
      window.delegate = self
      window.center()
      settingsWindow = window
    }
    NSApp.activate()
    settingsWindow?.makeKeyAndOrderFront(nil)
  }

  func windowWillClose(_ notification: Notification) {
    settingsWindow?.contentViewController = nil
    settingsWindow = nil
  }
}
