import SwiftUI

/// App metadata read from the bundle's Info.plist.
enum AppInfo {
    static var version: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "dev"
    }
    static var build: String {
        Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "0"
    }
}

struct ContentView: View {
    @EnvironmentObject var store: ConfigStore
    @State private var selection: UUID?
    @State private var showingAdd = false
    @State private var showingSettings = false

    var body: some View {
        NavigationSplitView {
            sidebar
                .frame(minWidth: 240)
        } detail: {
            detail
        }
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    showingAdd = true
                } label: {
                    Label("Add Server", systemImage: "plus")
                }
            }
            ToolbarItem(placement: .primaryAction) {
                Button {
                    store.load()
                } label: {
                    Label("Reload", systemImage: "arrow.clockwise")
                }
            }
            ToolbarItem(placement: .primaryAction) {
                Button {
                    showingSettings = true
                } label: {
                    Label("Managed Configs", systemImage: "gearshape")
                }
            }
        }
        .sheet(isPresented: $showingAdd) {
            EntryEditor(mode: .create) { newID in
                selection = newID
            }
            .environmentObject(store)
        }
        .sheet(isPresented: $showingSettings) {
            SettingsView().environmentObject(store)
        }
        .sheet(isPresented: $store.needsOnboarding) {
            OnboardingView().environmentObject(store)
                .interactiveDismissDisabled(true)
        }
        .overlay(alignment: .top) {
            if let toast = store.toast {
                ToastView(toast: toast)
                    .padding(.top, 10)
                    .transition(.move(edge: .top).combined(with: .opacity))
            }
        }
        .animation(.spring(response: 0.35, dampingFraction: 0.85), value: store.toast)
    }

    // MARK: - Sidebar

    private var sidebar: some View {
        List(selection: $selection) {
            Section("MCP Servers") {
                ForEach(store.entries) { entry in
                    ServerRow(entry: entry)
                        .tag(entry.id)
                }
            }
        }
        .listStyle(.sidebar)
        .overlay {
            if store.entries.isEmpty {
                ContentUnavailableView(
                    "No Servers",
                    systemImage: "server.rack",
                    description: Text("Click + to add an MCP server.")
                )
            }
        }
        .safeAreaInset(edge: .bottom) {
            statusBar
        }
    }

    // MARK: - Detail

    @ViewBuilder
    private var detail: some View {
        if let id = selection, let entry = store.entries.first(where: { $0.id == id }) {
            EntryEditor(mode: .edit(entry), onSaved: { _ in })
                .environmentObject(store)
                .id(entry.id)
        } else {
            ContentUnavailableView(
                "Select a Server",
                systemImage: "sidebar.left",
                description: Text("Pick a server on the left, or add a new one.")
            )
        }
    }

    // MARK: - Status bar

    private var statusBar: some View {
        VStack(alignment: .leading, spacing: 6) {
            Divider()
            if let err = store.lastError {
                Label(err, systemImage: "exclamationmark.triangle.fill")
                    .foregroundStyle(.red)
                    .lineLimit(3)
            } else {
                Label(store.statusMessage, systemImage: "checkmark.seal")
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
            HStack(spacing: 12) {
                Button("Config in Finder") { store.revealConfigInFinder() }
                    .buttonStyle(.link)
                Button("Backups") { store.revealBackupsInFinder() }
                    .buttonStyle(.link)
            }
            Text("MCP Manager v\(AppInfo.version)")
                .font(.caption2)
                .foregroundStyle(.tertiary)
        }
        .font(.caption)
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.bar)
    }
}

// MARK: - Toast

struct ToastView: View {
    let toast: Toast

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: toast.isError ? "exclamationmark.triangle.fill" : "checkmark.circle.fill")
            Text(toast.text)
                .font(.callout.weight(.medium))
        }
        .foregroundStyle(.white)
        .padding(.horizontal, 14)
        .padding(.vertical, 9)
        .background(toast.isError ? Color.red : Color.green, in: Capsule())
        .shadow(color: .black.opacity(0.2), radius: 6, y: 2)
    }
}

// MARK: - Sidebar row

struct ServerRow: View {
    @EnvironmentObject var store: ConfigStore
    let entry: MCPServerEntry

    var body: some View {
        HStack {
            Circle()
                .fill(entry.enabled ? Color.green : Color.secondary.opacity(0.4))
                .frame(width: 8, height: 8)
            Text(entry.name)
                .lineLimit(1)
            Spacer()
            Toggle("", isOn: Binding(
                get: { entry.enabled },
                set: { store.setEnabled(entry, $0) }
            ))
            .labelsHidden()
            .toggleStyle(.switch)
            .controlSize(.mini)
        }
    }
}
