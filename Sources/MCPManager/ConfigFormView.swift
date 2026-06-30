import SwiftUI

/// Structured editor for an MCP server config body.
struct ConfigFormView: View {
    @Binding var form: ServerConfigForm

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            // Transport
            HStack {
                Text("Transport")
                    .frame(width: 90, alignment: .leading)
                    .foregroundStyle(.secondary)
                Picker("", selection: $form.transport) {
                    ForEach(Transport.allCases) { t in
                        Text(t.label).tag(t)
                    }
                }
                .labelsHidden()
                .pickerStyle(.segmented)
            }

            if form.transport.isStdio {
                stdioFields
            } else {
                remoteFields
            }

            if let hint = form.completionHint {
                Label(hint, systemImage: "exclamationmark.circle")
                    .font(.caption)
                    .foregroundStyle(.orange)
            }
        }
    }

    // MARK: - stdio

    private var stdioFields: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text("Command")
                    .frame(width: 90, alignment: .leading)
                    .foregroundStyle(.secondary)
                TextField("e.g. npx  or  /usr/local/bin/my-server", text: $form.command)
                    .textFieldStyle(.roundedBorder)
                    .font(.system(.body, design: .monospaced))
            }

            ListEditor(
                title: "Arguments",
                addLabel: "Add argument",
                isEmpty: form.args.isEmpty,
                emptyText: "No arguments"
            ) {
                ForEach($form.args) { $arg in
                    HStack {
                        TextField("argument", text: $arg.value)
                            .textFieldStyle(.roundedBorder)
                            .font(.system(.body, design: .monospaced))
                        removeButton { form.args.removeAll { $0.id == arg.id } }
                    }
                }
                .onMove { form.args.move(fromOffsets: $0, toOffset: $1) }
            } onAdd: {
                form.args.append(ArgItem(value: ""))
            }

            KeyValueEditor(title: "Environment variables", pairs: $form.env,
                           keyPlaceholder: "VAR_NAME", valuePlaceholder: "value")
        }
    }

    // MARK: - remote

    private var remoteFields: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text("URL")
                    .frame(width: 90, alignment: .leading)
                    .foregroundStyle(.secondary)
                TextField("https://mcp.example.com/mcp", text: $form.url)
                    .textFieldStyle(.roundedBorder)
                    .font(.system(.body, design: .monospaced))
            }
            KeyValueEditor(title: "Headers", pairs: $form.headers,
                           keyPlaceholder: "Header-Name", valuePlaceholder: "value")
        }
    }

    private func removeButton(_ action: @escaping () -> Void) -> some View {
        Button(role: .destructive, action: action) {
            Image(systemName: "minus.circle.fill")
                .foregroundStyle(.secondary)
        }
        .buttonStyle(.borderless)
    }
}

/// Generic labeled section with an Add button and a rows builder.
struct ListEditor<Rows: View>: View {
    let title: String
    let addLabel: String
    let isEmpty: Bool
    let emptyText: String
    @ViewBuilder var rows: () -> Rows
    let onAdd: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(title).foregroundStyle(.secondary)
                Spacer()
                Button(addLabel, systemImage: "plus") { onAdd() }
                    .buttonStyle(.borderless)
                    .font(.caption)
            }
            if isEmpty {
                Text(emptyText)
                    .font(.caption)
                    .foregroundStyle(.tertiary)
                    .padding(.vertical, 2)
            } else {
                rows()
            }
        }
    }
}

/// Editor for a list of key/value string pairs (env, headers).
struct KeyValueEditor: View {
    let title: String
    @Binding var pairs: [KeyValueItem]
    let keyPlaceholder: String
    let valuePlaceholder: String

    var body: some View {
        ListEditor(
            title: title,
            addLabel: "Add",
            isEmpty: pairs.isEmpty,
            emptyText: "None"
        ) {
            ForEach($pairs) { $pair in
                HStack {
                    TextField(keyPlaceholder, text: $pair.key)
                        .textFieldStyle(.roundedBorder)
                        .font(.system(.body, design: .monospaced))
                        .frame(maxWidth: 200)
                    Text("=").foregroundStyle(.tertiary)
                    TextField(valuePlaceholder, text: $pair.value)
                        .textFieldStyle(.roundedBorder)
                        .font(.system(.body, design: .monospaced))
                    Button(role: .destructive) {
                        pairs.removeAll { $0.id == pair.id }
                    } label: {
                        Image(systemName: "minus.circle.fill").foregroundStyle(.secondary)
                    }
                    .buttonStyle(.borderless)
                }
            }
        } onAdd: {
            pairs.append(KeyValueItem(key: "", value: ""))
        }
    }
}
