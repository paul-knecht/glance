import SwiftUI

// The small settings window. It appears when the Glance app is opened
// again while it is already running in the background.
struct SettingsView: View {

    // False if another app already uses the hotkey.
    let hotkeyAvailable: Bool

    // What the buttons do. AppDelegate passes these in.
    let setAPIKey: () -> Void
    let quit: () -> Void

    @State private var startAtLogin = LoginItem.isEnabled

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Glance runs in the background.")
                .font(.headline)

            Text(hotkeyAvailable
                 ? "Select text in any app and press ⌃⌥Space."
                 : "The hotkey ⌃⌥Space is not available: another app is using it.")
                .foregroundStyle(hotkeyAvailable ? .primary : .secondary)

            Toggle("Start Glance when I log in", isOn: $startAtLogin)
                .onChange(of: startAtLogin) { _, wanted in
                    // If macOS refuses the change, show the real state again.
                    if !LoginItem.setEnabled(wanted) {
                        startAtLogin = LoginItem.isEnabled
                    }
                }

            HStack {
                Button("Set API key…", action: setAPIKey)
                Spacer()
                Button("Quit Glance", action: quit)
            }

            Text("To see this window again, open Glance from Applications or Spotlight.")
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
        .padding(20)
        .frame(width: 380)
    }
}
