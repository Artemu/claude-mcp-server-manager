import Foundation

/// One MCP server entry in the library.
///
/// `config` is exactly the JSON body that lives under the server's name in
/// `claude_desktop_config.json` — e.g. `{ "command": ..., "args": [...], "env": {...} }`.
/// It is stored as a free-form object so the user can put whatever keys they want in it.
struct MCPServerEntry: Identifiable, Codable, Equatable {
    var id: UUID
    var name: String
    var enabled: Bool
    var config: JSONValue

    init(id: UUID = UUID(), name: String, enabled: Bool, config: JSONValue) {
        self.id = id
        self.name = name
        self.enabled = enabled
        self.config = config
    }

    enum CodingKeys: String, CodingKey {
        case id, name, enabled, config
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        // id is optional in the file; generate one if absent.
        self.id = (try? c.decode(UUID.self, forKey: .id)) ?? UUID()
        self.name = try c.decode(String.self, forKey: .name)
        self.enabled = try c.decode(Bool.self, forKey: .enabled)
        self.config = (try? c.decode(JSONValue.self, forKey: .config)) ?? .object([:])
    }
}

/// The on-disk format of `mcp-directory.json` — the app's source of truth.
struct MCPDirectory: Codable {
    var version: Int
    var servers: [MCPServerEntry]

    init(version: Int = 1, servers: [MCPServerEntry] = []) {
        self.version = version
        self.servers = servers
    }
}

/// A config file the app manages the MCP section of.
///
/// The app only ever reads and rewrites the `serversKey` (default `mcpServers`)
/// of each managed file — every other key is preserved byte-faithfully.
struct ManagedConfig: Identifiable, Codable, Equatable {
    var id: UUID
    var name: String
    var path: String        // may contain a leading `~`
    var managed: Bool
    var kind: String        // "desktop" | "cli" | "custom"
    var serversKey: String

    init(id: UUID = UUID(), name: String, path: String, managed: Bool,
         kind: String, serversKey: String = "mcpServers") {
        self.id = id
        self.name = name
        self.path = path
        self.managed = managed
        self.kind = kind
        self.serversKey = serversKey
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.id = (try? c.decode(UUID.self, forKey: .id)) ?? UUID()
        self.name = try c.decode(String.self, forKey: .name)
        self.path = try c.decode(String.self, forKey: .path)
        self.managed = try c.decode(Bool.self, forKey: .managed)
        self.kind = (try? c.decode(String.self, forKey: .kind)) ?? "custom"
        self.serversKey = (try? c.decode(String.self, forKey: .serversKey)) ?? "mcpServers"
    }

    enum CodingKeys: String, CodingKey {
        case id, name, path, managed, kind, serversKey
    }

    var expandedPath: String { (path as NSString).expandingTildeInPath }
    var url: URL { URL(fileURLWithPath: expandedPath) }
    var exists: Bool { FileManager.default.fileExists(atPath: expandedPath) }
    var isRemovable: Bool { kind == "custom" }
}

/// App-level settings persisted to `mcp-manager-settings.json`.
struct AppSettings: Codable {
    var version: Int = 1
    var onboarded: Bool = false
    var configs: [ManagedConfig] = []
}
