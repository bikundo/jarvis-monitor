import SwiftUI

struct SettingsView: View {
  var model: AppModel

  @State private var launchAtLogin = LoginItem.isEnabled
  @State private var launchError: String?

  var body: some View {
    @Bindable var settings = model.settings
    Form {
      Section("Show in the menu bar") {
        Toggle("CPU", isOn: $settings.showCPU)
        Toggle("Memory", isOn: $settings.showMemory)
        Toggle("Battery", isOn: $settings.showBattery)
      }

      Section("General") {
        Toggle("Open Jarvis when I log in", isOn: $launchAtLogin)
          .onChange(of: launchAtLogin) { _, enabled in
            setLaunchAtLogin(enabled)
          }
        if let launchError {
          Text(launchError).font(.caption).foregroundStyle(.red)
        }
      }
    }
    .formStyle(.grouped)
    .frame(width: 480)
    .fixedSize(horizontal: false, vertical: true)
  }

  private func setLaunchAtLogin(_ enabled: Bool) {
    do {
      try LoginItem.setEnabled(enabled)
      launchError = nil
    } catch {
      launchError = error.localizedDescription
      launchAtLogin = LoginItem.isEnabled
    }
  }
}
