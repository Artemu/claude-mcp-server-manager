import SwiftUI
import AppKit

/// Manage which config files the app syncs to. Reachable any time after
/// onboarding via the gear button.
struct SettingsView: View {
    @EnvironmentObject var store: ConfigStore
    @Environment(\.dismiss) private var dismiss

    @State private var configs: [ManagedConfig] = []
    @State private var addError: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Image(systemName: "gearshape")
                    .foregroundStyle(.tint)
                Text("Managed Configs")
                    .font(.headline)
                Spacer()
                Button("Add Config…") { addConfig() }
            }
            .padding(14)
            Divider()

            ScrollView {
                VStack(spacing: 0) {
                    ForEach($configs) { $config in
                        ConfigSettingsRow(config: $config) {
                            configs.removeAll { $0.id == config.id }
                        }
                        Divider()
                    }
                }
            }
            .frame(minHeight: 220)

            if let addError {
                Label(addError, systemImage: "exclamationmark.triangle")
                    .font(.caption)
                    .foregroundStyle(.orange)
                    .padding(.horizontal, 14)
                    .padding(.top, 8)
            }

            Label {
                Text("Every managed config is kept in sync: the same set of enabled servers is written to each. Only the **mcpServers** section is changed.")
            } icon: {
                Image(systemName: "info.circle")
            }
            .font(.caption)
            .foregroundStyle(.secondary)
            .padding(14)

            Divider()
            HStack {
                Spacer()
                Button("Cancel") { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button("Save & Sync") {
                    store.applySettings(configs)
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
                .buttonStyle(.borderedProminent)
            }
            .padding(14)
        }
        .frame(width: 560)
        .onAppear { configs = store.settings.configs }
    }

    private func addConfig() {
        addError = nil
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.json]
        panel.allowsOtherFileTypes = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.message = "Choose a JSON config file with an \"mcpServers\" section to manage."
        guard panel.runModal() == .OK, let url = panel.url else { return }

        let path = url.path
        if configs.contains(where: { $0.expandedPath == path }) {
            addError = "That file is already in the list."
            return
        }
        configs.append(ManagedConfig(
            name: url.deletingPathExtension().lastPathComponent,
            path: path, managed: true, kind: "custom"
        ))
    }
}

struct ConfigSettingsRow: View {
    @Binding var config: ManagedConfig
    var onRemove: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            Toggle("", isOn: $config.managed)
                .labelsHidden()
                .toggleStyle(.switch)
                .controlSize(.small)
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(config.name)
                    kindBadge
                    if !config.exists {
                        Text("missing")
                            .font(.caption2)
                            .foregroundStyle(.orange)
                    }
                }
                Text(OnboardingView.shorten(config.path))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            Spacer()
            if config.isRemovable {
                Button(role: .destructive) { onRemove() } label: {
                    Image(systemName: "trash")
                }
                .buttonStyle(.borderless)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
    }

    private var kindBadge: some View {
        Text(config.kind == "desktop" ? "Desktop" : config.kind == "cli" ? "CLI" : "Custom")
            .font(.caption2)
            .foregroundStyle(.secondary)
            .padding(.horizontal, 6).padding(.vertical, 1)
            .background(.quaternary, in: Capsule())
    }
}
