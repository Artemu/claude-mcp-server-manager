import Foundation
import SwiftUI

/// Owns reading and writing the server library and every managed config file.
///
/// Design:
///  - `mcp-directory.json` is the source of truth. It holds *every* entry
///    (enabled and disabled) with its full config body.
///  - `mcp-manager-settings.json` holds which config files we manage.
///  - Each managed config file is treated as output for its `mcpServers` key
///    only: on save we rewrite that key to the enabled entries and leave every
///    other key in the file untouched. Managing more than one config keeps them
///    in sync, since they all mirror the same library.
///  - Every write is atomic and makes a timestamped backup first, so a crash or
///    bad input can never leave a half-written / broken JSON file.
@MainActor
final class ConfigStore: ObservableObject {
    @Published var entries: [MCPServerEntry] = []
    @Published var settings = AppSettings()
    @Published var statusMessage = ""
    @Published var lastError: String?
    @Published var needsOnboarding = false
    @Published var toast: Toast?

    private var toastTask: Task<Void, Never>?

    /// Show a transient confirmation message that auto-dismisses.
    func showToast(_ text: String, isError: Bool = false) {
        let t = Toast(text: text, isError: isError)
        toast = t
        toastTask?.cancel()
        toastTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 2_400_000_000)
            guard let self, !Task.isCancelled else { return }
            if self.toast?.id == t.id { self.toast = nil }
        }
    }

    // MARK: - Paths

    let appDir: URL          // ~/Library/Application Support/Claude
    let directoryURL: URL    // mcp-directory.json
    let settingsURL: URL     // mcp-manager-settings.json
    let backupDir: URL

    static let desktopConfigPath = "~/Library/Application Support/Claude/claude_desktop_config.json"
    static let cliConfigPath = "~/.claude.json"

    init() {
        let home = FileManager.default.homeDirectoryForCurrentUser
        appDir = home.appendingPathComponent("Library/Application Support/Claude", isDirectory: true)
        directoryURL = appDir.appendingPathComponent("mcp-directory.json")
        settingsURL = appDir.appendingPathComponent("mcp-manager-settings.json")
        backupDir = appDir.appendingPathComponent("mcp-manager-backups", isDirectory: true)
    }

    static func defaultConfigs() -> [ManagedConfig] {
        [
            ManagedConfig(name: "Claude Desktop", path: desktopConfigPath, managed: true, kind: "desktop"),
            ManagedConfig(name: "Claude CLI", path: cliConfigPath, managed: false, kind: "cli")
        ]
    }

    var managedConfigs: [ManagedConfig] { settings.configs.filter { $0.managed } }
    var managedCount: Int { managedConfigs.count }
    var enabledCount: Int { entries.filter { $0.enabled }.count }

    // MARK: - Load

    func load() {
        lastError = nil
        if let loaded = readSettings() {
            settings = loaded
            if settings.configs.isEmpty { settings.configs = Self.defaultConfigs() }
            needsOnboarding = !settings.onboarded
        } else {
            // First run.
            settings = AppSettings(version: 1, onboarded: false, configs: Self.defaultConfigs())
            needsOnboarding = true
        }
        reconcile()
    }

    /// Import every managed config's servers into the library (nothing is ever
    /// lost), then publish. The first managed config that contains a given
    /// server name defines its body; later configs only contribute new names.
    func reconcile() {
        lastError = nil
        do {
            var directory = readDirectory()
            var importedThisPass = Set<String>()

            for config in managedConfigs {
                let live = (try? readConfigFile(config))?[config.serversKey]?.objectValue ?? [:]
                for (name, cfg) in live {
                    if let idx = directory.servers.firstIndex(where: { $0.name == name }) {
                        if !importedThisPass.contains(name) {
                            directory.servers[idx].config = cfg
                            directory.servers[idx].enabled = true
                            importedThisPass.insert(name)
                        }
                    } else {
                        directory.servers.append(MCPServerEntry(name: name, enabled: true, config: cfg))
                        importedThisPass.insert(name)
                    }
                }
            }

            directory.servers.sort { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
            entries = directory.servers
            try writeDirectory(MCPDirectory(servers: entries))

            statusMessage = "Loaded \(entries.count) server(s) · \(enabledCount) enabled · \(managedCount) config(s)"
        } catch {
            lastError = "Failed to load: \(error.localizedDescription)"
        }
    }

    // MARK: - Onboarding & settings

    func completeOnboarding(manageCLI: Bool) {
        settings.onboarded = true
        if let idx = settings.configs.firstIndex(where: { $0.kind == "cli" }) {
            settings.configs[idx].managed = manageCLI
        }
        needsOnboarding = false
        try? writeSettings()
        reconcile()
        persist()
    }

    /// Apply edited settings (managed flags, added/removed configs), then
    /// re-import and push the synced set to all managed configs.
    func applySettings(_ newConfigs: [ManagedConfig]) {
        settings.configs = newConfigs
        try? writeSettings()
        reconcile()
        persist()
    }

    func addCustomConfig(name: String, path: String) {
        let entry = ManagedConfig(
            name: name.isEmpty ? URL(fileURLWithPath: path).lastPathComponent : name,
            path: path, managed: true, kind: "custom"
        )
        var configs = settings.configs
        configs.append(entry)
        applySettings(configs)
    }

    // MARK: - Mutations (each persists immediately)

    func setEnabled(_ entry: MCPServerEntry, _ enabled: Bool) {
        guard let idx = entries.firstIndex(where: { $0.id == entry.id }) else { return }
        entries[idx].enabled = enabled
        persist()
    }

    func update(_ entry: MCPServerEntry, name: String, config: JSONValue) {
        guard let idx = entries.firstIndex(where: { $0.id == entry.id }) else { return }
        entries[idx].name = name
        entries[idx].config = config
        entries.sort { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
        persist()
    }

    @discardableResult
    func addEntry(name: String, config: JSONValue, enabled: Bool = true) -> MCPServerEntry {
        let entry = MCPServerEntry(name: name, enabled: enabled, config: config)
        entries.append(entry)
        entries.sort { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
        persist()
        return entry
    }

    func delete(_ entry: MCPServerEntry) {
        entries.removeAll { $0.id == entry.id }
        persist()
    }

    func nameExists(_ name: String, excluding id: UUID? = nil) -> Bool {
        entries.contains { $0.name == name && $0.id != id }
    }

    // MARK: - Persist

    /// Write the library, then rewrite the `mcpServers` key of every managed
    /// config to the set of enabled entries. Other keys are preserved.
    func persist() {
        lastError = nil
        do {
            try writeDirectory(MCPDirectory(servers: entries))

            var servers: [String: JSONValue] = [:]
            for entry in entries where entry.enabled {
                servers[entry.name] = entry.config
            }

            for config in managedConfigs {
                var full = (try? readConfigFile(config)) ?? [:]
                full[config.serversKey] = .object(servers)
                try writeConfigFile(config, full)
            }

            statusMessage = "Saved · \(enabledCount) of \(entries.count) enabled · synced to \(managedCount) config(s) · \(timeString())"
            let target = managedCount == 1 ? "1 config" : "\(managedCount) configs"
            showToast("Changes written to \(target)")
        } catch {
            lastError = "Save failed (no changes written): \(error.localizedDescription)"
            showToast("Save failed — see status bar", isError: true)
        }
    }

    // MARK: - File IO

    private func readConfigFile(_ config: ManagedConfig) throws -> [String: JSONValue] {
        guard config.exists else { return [:] }
        let data = try Data(contentsOf: config.url)
        let value = try JSONDecoder().decode(JSONValue.self, from: data)
        guard let obj = value.objectValue else {
            throw ConfigError.notAnObject(config.url.lastPathComponent)
        }
        return obj
    }

    private func writeConfigFile(_ config: ManagedConfig, _ contents: [String: JSONValue]) throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        let data = try encoder.encode(JSONValue.object(contents))
        try atomicWrite(data, to: config.url)
    }

    private func readDirectory() -> MCPDirectory {
        guard FileManager.default.fileExists(atPath: directoryURL.path),
              let data = try? Data(contentsOf: directoryURL),
              let dir = try? JSONDecoder().decode(MCPDirectory.self, from: data) else {
            return MCPDirectory()
        }
        return dir
    }

    private func writeDirectory(_ dir: MCPDirectory) throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        let data = try encoder.encode(dir)
        try atomicWrite(data, to: directoryURL)
    }

    private func readSettings() -> AppSettings? {
        guard FileManager.default.fileExists(atPath: settingsURL.path),
              let data = try? Data(contentsOf: settingsURL),
              let s = try? JSONDecoder().decode(AppSettings.self, from: data) else {
            return nil
        }
        return s
    }

    private func writeSettings() throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        let data = try encoder.encode(settings)
        try atomicWrite(data, to: settingsURL)
    }

    /// Back up the existing file (if any) then write atomically, validating that
    /// the bytes we're about to write actually parse as JSON.
    private func atomicWrite(_ data: Data, to url: URL) throws {
        _ = try JSONSerialization.jsonObject(with: data, options: [.fragmentsAllowed])

        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(), withIntermediateDirectories: true)

        if FileManager.default.fileExists(atPath: url.path) {
            try FileManager.default.createDirectory(at: backupDir, withIntermediateDirectories: true)
            let backupURL = backupDir
                .appendingPathComponent("\(url.lastPathComponent).\(backupTimestamp()).bak")
            try? FileManager.default.copyItem(at: url, to: backupURL)
            pruneBackups(for: url.lastPathComponent, keep: 25)
        }

        try data.write(to: url, options: .atomic)
    }

    private func pruneBackups(for prefix: String, keep: Int) {
        guard let files = try? FileManager.default.contentsOfDirectory(
            at: backupDir, includingPropertiesForKeys: [.contentModificationDateKey]
        ) else { return }
        let matching = files
            .filter { $0.lastPathComponent.hasPrefix(prefix) }
            .sorted { a, b in
                let da = (try? a.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate ?? .distantPast
                let db = (try? b.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate ?? .distantPast
                return da > db
            }
        for old in matching.dropFirst(keep) {
            try? FileManager.default.removeItem(at: old)
        }
    }

    // MARK: - Reveal helpers

    func revealConfigInFinder() {
        let target = managedConfigs.first(where: { $0.exists })?.url
            ?? settings.configs.first?.url
        if let target { NSWorkspace.shared.activateFileViewerSelecting([target]) }
    }

    func revealBackupsInFinder() {
        try? FileManager.default.createDirectory(at: backupDir, withIntermediateDirectories: true)
        NSWorkspace.shared.activateFileViewerSelecting([backupDir])
    }

    // MARK: - Time helpers

    private func timeString() -> String {
        let f = DateFormatter()
        f.dateFormat = "HH:mm:ss"
        return f.string(from: Date())
    }

    private func backupTimestamp() -> String {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd_HH-mm-ss"
        return f.string(from: Date())
    }
}

/// A transient confirmation message shown briefly after a write.
struct Toast: Identifiable, Equatable {
    let id = UUID()
    var text: String
    var isError: Bool
}

enum ConfigError: LocalizedError {
    case notAnObject(String)

    var errorDescription: String? {
        switch self {
        case .notAnObject(let file):
            return "\(file) is not a JSON object at its top level."
        }
    }
}
