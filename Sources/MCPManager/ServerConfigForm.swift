import Foundation

/// MCP transport types, per the Claude Code / MCP docs.
enum Transport: String, CaseIterable, Identifiable, Equatable {
    case stdio, http, sse, ws

    var id: String { rawValue }
    var isStdio: Bool { self == .stdio }

    var label: String {
        switch self {
        case .stdio: return "Local (stdio)"
        case .http:  return "HTTP"
        case .sse:   return "SSE"
        case .ws:    return "WebSocket"
        }
    }
}

/// A single editable string (used for `args`), wrapped so SwiftUI's ForEach
/// has a stable identity even when the value is empty or duplicated.
struct ArgItem: Identifiable, Equatable {
    var id = UUID()
    var value: String
}

/// A key/value pair (used for `env` and `headers`).
struct KeyValueItem: Identifiable, Equatable {
    var id = UUID()
    var key: String
    var value: String
}

/// A structured, form-friendly representation of an MCP server config body.
///
/// Only the fields the docs define are representable here. If a config contains
/// anything else (e.g. an `oauth` object, or non-string env values), it is *not*
/// representable and the editor falls back to raw JSON — by design, so the form
/// can never silently drop data it doesn't understand.
struct ServerConfigForm: Equatable {
    var transport: Transport = .stdio
    var command: String = ""
    var args: [ArgItem] = []
    var env: [KeyValueItem] = []
    var url: String = ""
    var headers: [KeyValueItem] = []

    /// The keys this form knows how to round-trip.
    private static let knownKeys: Set<String> = ["type", "command", "args", "env", "url", "headers"]

    /// Try to build a form from a config body. Returns nil if the body contains
    /// anything the form can't faithfully represent.
    static func from(_ config: JSONValue) -> ServerConfigForm? {
        guard let obj = config.objectValue else { return nil }
        // Any unrecognized key (e.g. "oauth") means we can't use the form.
        for key in obj.keys where !Self.knownKeys.contains(key) { return nil }

        var form = ServerConfigForm()

        // Resolve transport.
        if let typeVal = obj["type"] {
            guard case .string(let s) = typeVal, let t = Transport(rawValue: s) else { return nil }
            form.transport = t
        } else if obj["url"] != nil {
            form.transport = .http      // url but no type → remote
        } else {
            form.transport = .stdio
        }

        if form.transport.isStdio {
            // Remote-only keys must not appear.
            if obj["url"] != nil || obj["headers"] != nil { return nil }

            if let c = obj["command"] {
                guard case .string(let s) = c else { return nil }
                form.command = s
            }
            if let a = obj["args"] {
                guard case .array(let arr) = a else { return nil }
                var items: [ArgItem] = []
                for v in arr {
                    guard case .string(let s) = v else { return nil }
                    items.append(ArgItem(value: s))
                }
                form.args = items
            }
            if let e = obj["env"] {
                guard let parsed = parseStringMap(e) else { return nil }
                form.env = parsed
            }
        } else {
            // stdio-only keys must not appear on a remote server.
            if obj["command"] != nil || obj["args"] != nil || obj["env"] != nil { return nil }

            if let u = obj["url"] {
                guard case .string(let s) = u else { return nil }
                form.url = s
            }
            if let h = obj["headers"] {
                guard let parsed = parseStringMap(h) else { return nil }
                form.headers = parsed
            }
        }
        return form
    }

    /// Whether a config body can be represented in the form.
    static func isRepresentable(_ config: JSONValue) -> Bool { from(config) != nil }

    private static func parseStringMap(_ value: JSONValue) -> [KeyValueItem]? {
        guard let obj = value.objectValue else { return nil }
        var items: [KeyValueItem] = []
        for (k, v) in obj.sorted(by: { $0.key < $1.key }) {
            guard case .string(let s) = v else { return nil }
            items.append(KeyValueItem(key: k, value: s))
        }
        return items
    }

    /// Serialize back to a config body. Empty optional sections are omitted.
    func toJSON() -> JSONValue {
        var obj: [String: JSONValue] = [:]

        if transport.isStdio {
            // `type` is omitted for stdio (the default), to match Claude Desktop conventions.
            obj["command"] = .string(command)
            let argValues = args.map { $0.value }
            if !argValues.isEmpty {
                obj["args"] = .array(argValues.map { .string($0) })
            }
            let envPairs = env.filter { !$0.key.isEmpty }
            if !envPairs.isEmpty {
                obj["env"] = .object(mapFrom(envPairs))
            }
        } else {
            obj["type"] = .string(transport.rawValue)
            obj["url"] = .string(url)
            let headerPairs = headers.filter { !$0.key.isEmpty }
            if !headerPairs.isEmpty {
                obj["headers"] = .object(mapFrom(headerPairs))
            }
        }
        return .object(obj)
    }

    private func mapFrom(_ pairs: [KeyValueItem]) -> [String: JSONValue] {
        var dict: [String: JSONValue] = [:]
        for p in pairs { dict[p.key] = .string(p.value) }   // last write wins on dup keys
        return dict
    }

    /// Whether the form currently holds the minimum required to be a valid server.
    var isComplete: Bool {
        if transport.isStdio {
            return !command.trimmingCharacters(in: .whitespaces).isEmpty
        } else {
            return !url.trimmingCharacters(in: .whitespaces).isEmpty
        }
    }

    var completionHint: String? {
        if transport.isStdio && command.trimmingCharacters(in: .whitespaces).isEmpty {
            return "A command is required for a local (stdio) server."
        }
        if !transport.isStdio && url.trimmingCharacters(in: .whitespaces).isEmpty {
            return "A URL is required for a remote server."
        }
        return nil
    }
}
