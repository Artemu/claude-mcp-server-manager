import SwiftUI

/// Shown once, on first launch. Asks whether to also manage (and keep in sync)
/// the Claude CLI config alongside Claude Desktop.
struct OnboardingView: View {
    @EnvironmentObject var store: ConfigStore
    @State private var manageCLI = true

    private var desktopExists: Bool {
        store.settings.configs.first { $0.kind == "desktop" }?.exists ?? false
    }
    private var cliExists: Bool {
        store.settings.configs.first { $0.kind == "cli" }?.exists ?? false
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(spacing: 12) {
                Image(systemName: "switch.2")
                    .font(.system(size: 30))
                    .foregroundStyle(.tint)
                VStack(alignment: .leading) {
                    Text("Welcome to MCP Manager")
                        .font(.title2).bold()
                    Text("Manage your MCP servers in one place.")
                        .foregroundStyle(.secondary)
                }
            }

            Divider()

            Text("Which configs should this app manage?")
                .font(.headline)

            VStack(alignment: .leading, spacing: 12) {
                configRow(
                    title: "Claude Desktop",
                    subtitle: pathLabel(Self.shorten(ConfigStore.desktopConfigPath), exists: desktopExists),
                    isOn: .constant(true),
                    locked: true
                )
                configRow(
                    title: "Claude CLI  ·  keep in sync with Desktop",
                    subtitle: pathLabel(Self.shorten(ConfigStore.cliConfigPath), exists: cliExists),
                    isOn: $manageCLI,
                    locked: false
                )
            }

            Label {
                Text("The app only ever touches the **mcpServers** section of each file. Everything else is left exactly as-is, and a backup is saved before every change.")
            } icon: {
                Image(systemName: "checkmark.shield")
            }
            .font(.callout)
            .foregroundStyle(.secondary)
            .padding(.top, 2)

            HStack {
                Spacer()
                Button("Get Started") {
                    store.completeOnboarding(manageCLI: manageCLI)
                }
                .keyboardShortcut(.defaultAction)
                .buttonStyle(.borderedProminent)
            }
        }
        .padding(24)
        .frame(width: 520)
    }

    private func configRow(title: String, subtitle: Text, isOn: Binding<Bool>, locked: Bool) -> some View {
        HStack(alignment: .top) {
            Toggle("", isOn: isOn)
                .labelsHidden()
                .toggleStyle(.checkbox)
                .disabled(locked)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                subtitle.font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            if locked {
                Text("Always")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 6).padding(.vertical, 2)
                    .background(.quaternary, in: Capsule())
            }
        }
    }

    private func pathLabel(_ path: String, exists: Bool) -> Text {
        Text(exists ? "\(path)" : "\(path)  (will be created)")
    }

    static func shorten(_ path: String) -> String {
        path.replacingOccurrences(
            of: FileManager.default.homeDirectoryForCurrentUser.path, with: "~")
    }
}
