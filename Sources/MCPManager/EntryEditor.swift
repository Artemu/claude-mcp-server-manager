import SwiftUI

/// The editor used both for creating a new server (in a sheet) and editing an
/// existing one (in the detail pane).
///
/// The config body can be edited two ways:
///  - **Form**: structured fields for the documented MCP schema (transport,
///    command/args/env or url/headers).
///  - **Raw JSON**: free-form text with live validation.
///
/// If a config can't be represented in the form (unknown keys like `oauth`,
/// non-string env values, or invalid JSON), the editor falls back to Raw and
/// the Form tab is disabled until the JSON parses into a representable shape.
struct EntryEditor: View {
    enum Mode: Equatable {
        case create
        case edit(MCPServerEntry)
    }

    enum EditorMode: Equatable { case form, raw }

    @EnvironmentObject var store: ConfigStore
    @Environment(\.dismiss) private var dismiss

    let mode: Mode
    var onSaved: (UUID) -> Void

    @State private var name: String = ""
    @State private var editorMode: EditorMode = .form
    @State private var form = ServerConfigForm()
    @State private var bodyText: String = "{\n  \n}"
    @State private var validationError: String?
    @State private var nameError: String?
    @State private var dirty = false
    @State private var showDeleteConfirm = false

    private var isCreate: Bool { if case .create = mode { return true }; return false }

    private var editingEntry: MCPServerEntry? {
        if case .edit(let e) = mode { return e }
        return nil
    }

    /// The current value from the store — keeps the Enabled toggle in sync with
    /// the sidebar toggle (both read/write the same store state).
    private var liveEntry: MCPServerEntry? {
        guard let id = editingEntry?.id else { return nil }
        return store.entries.first { $0.id == id }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            Divider()
            ScrollView {
                editorForm
            }
            .frame(maxHeight: .infinity)
            Divider()
            footer
        }
        .frame(minWidth: isCreate ? 580 : nil, minHeight: isCreate ? 520 : nil)
        .onAppear(perform: loadInitial)
    }

    // MARK: - Header

    private var header: some View {
        HStack {
            Image(systemName: "server.rack")
                .foregroundStyle(.tint)
            Text(isCreate ? "Add MCP Server" : "Edit Server")
                .font(.headline)
            Spacer()
            if !isCreate {
                Toggle("Enabled", isOn: Binding(
                    get: { liveEntry?.enabled ?? false },
                    set: { newValue in if let e = liveEntry { store.setEnabled(e, newValue) } }
                ))
                .toggleStyle(.switch)
            }
        }
        .padding(14)
    }

    // MARK: - Body

    private var editorForm: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Name")
                    .frame(width: 90, alignment: .leading)
                    .foregroundStyle(.secondary)
                TextField("e.g. homeassistant", text: $name)
                    .textFieldStyle(.roundedBorder)
                    .onChange(of: name) { _, _ in dirty = true; validateName() }
            }
            if let nameError {
                Label(nameError, systemImage: "exclamationmark.circle")
                    .font(.caption)
                    .foregroundStyle(.orange)
            }

            Divider().padding(.vertical, 2)

            HStack {
                Text("Configuration")
                    .foregroundStyle(.secondary)
                Spacer()
                modeSwitcher
            }

            if editorMode == .form {
                ConfigFormView(form: $form)
                    .onChange(of: form) { _, _ in dirty = true }
            } else {
                rawEditor
            }
        }
        .padding(14)
    }

    private var modeSwitcher: some View {
        HStack(spacing: 6) {
            modeButton("Form", .form)
            modeButton("Raw JSON", .raw)
        }
    }

    private func modeButton(_ title: String, _ target: EditorMode) -> some View {
        // The Form tab is only selectable when the current raw text is representable.
        let disabled = target == .form && editorMode == .raw && !rawIsRepresentable
        let selected = editorMode == target
        return Button {
            if !disabled && editorMode != target { switchMode(to: target) }
        } label: {
            Text(title)
                .font(.caption.weight(selected ? .semibold : .regular))
                .padding(.horizontal, 12)
                .padding(.vertical, 5)
                .background(selected ? Color.accentColor : Color.secondary.opacity(0.12), in: Capsule())
                .foregroundStyle(selected ? Color.white : (disabled ? Color.secondary.opacity(0.5) : Color.primary))
        }
        .buttonStyle(.plain)
        .disabled(disabled)
        .help(disabled ? "This config uses fields the form can't represent." : "")
    }

    private var rawEditor: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Edit the raw JSON body of this server.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                Button("Format") { formatBody() }
                    .buttonStyle(.borderless)
                    .font(.caption)
                    .disabled(validationError != nil)
            }

            CodeEditor(text: $bodyText)
                .frame(minHeight: 220)
                .onChange(of: bodyText) { _, _ in dirty = true; validateBody() }
                .overlay(
                    RoundedRectangle(cornerRadius: 6)
                        .stroke(validationError == nil ? Color.secondary.opacity(0.25) : Color.red.opacity(0.7), lineWidth: 1)
                )

            if let validationError {
                Label(validationError, systemImage: "xmark.octagon.fill")
                    .font(.caption)
                    .foregroundStyle(.red)
            } else if !rawIsRepresentable {
                Label("Valid JSON. This config uses fields the form can't show (e.g. oauth), so it stays in Raw mode.",
                      systemImage: "info.circle.fill")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                Label("Valid JSON object", systemImage: "checkmark.circle.fill")
                    .font(.caption)
                    .foregroundStyle(.green)
            }
        }
    }

    // MARK: - Footer

    private var footer: some View {
        HStack {
            if !isCreate, let e = editingEntry {
                Button(role: .destructive) {
                    showDeleteConfirm = true
                } label: {
                    Label("Delete", systemImage: "trash")
                }
                .confirmationDialog(
                    "Delete “\(e.name)” permanently?",
                    isPresented: $showDeleteConfirm,
                    titleVisibility: .visible
                ) {
                    Button("Delete “\(e.name)”", role: .destructive) {
                        store.delete(e)
                        onSaved(e.id)
                    }
                    Button("Cancel", role: .cancel) {}
                } message: {
                    Text("This removes it from the library and the Claude config. To keep it but stop it loading, turn off “Enabled” instead. A backup is always saved.")
                }
            }
            Spacer()
            if isCreate {
                Button("Cancel") { dismiss() }
                    .keyboardShortcut(.cancelAction)
            }
            Button(isCreate ? "Add" : "Save Changes") { save() }
                .keyboardShortcut(.defaultAction)
                .buttonStyle(.borderedProminent)
                .disabled(!canSave)
        }
        .padding(14)
    }

    // MARK: - Mode switching

    /// Whether the current raw text parses into a form-representable config.
    private var rawIsRepresentable: Bool {
        guard let value = try? JSONValue.parse(bodyText), value.isObject else { return false }
        return ServerConfigForm.isRepresentable(value)
    }

    private func switchMode(to target: EditorMode) {
        switch target {
        case .raw:
            // Form → Raw: serialize the form so the text reflects it.
            bodyText = form.toJSON().prettyPrinted()
            validateBody()
            editorMode = .raw
        case .form:
            // Raw → Form: only if it parses into something representable.
            guard let value = try? JSONValue.parse(bodyText),
                  let parsed = ServerConfigForm.from(value) else { return }
            form = parsed
            editorMode = .form
        }
    }

    // MARK: - Logic

    private var currentConfig: JSONValue? {
        if editorMode == .form { return form.toJSON() }
        guard let value = try? JSONValue.parse(bodyText), value.isObject else { return nil }
        return value
    }

    private var canSave: Bool {
        guard nameError == nil, !name.trimmingCharacters(in: .whitespaces).isEmpty else { return false }
        guard isCreate || dirty else { return false }
        if editorMode == .form { return form.isComplete }
        return validationError == nil
    }

    private func loadInitial() {
        let config: JSONValue
        if let e = editingEntry {
            name = e.name
            config = e.config
        } else {
            config = .object([:])
        }
        bodyText = config.prettyPrinted()
        if let parsed = ServerConfigForm.from(config) {
            form = parsed
            editorMode = .form
        } else {
            editorMode = .raw
        }
        validateName()
        validateBody()
        dirty = false
    }

    private func validateName() {
        let trimmed = name.trimmingCharacters(in: .whitespaces)
        if trimmed.isEmpty {
            nameError = "Name is required."
        } else if store.nameExists(trimmed, excluding: editingEntry?.id) {
            nameError = "A server named “\(trimmed)” already exists."
        } else {
            nameError = nil
        }
    }

    private func validateBody() {
        do {
            let value = try JSONValue.parse(bodyText)
            validationError = value.isObject ? nil : "The config body must be a JSON object ( { … } )."
        } catch {
            validationError = "Invalid JSON: \(error.localizedDescription)"
        }
    }

    private func formatBody() {
        guard let value = try? JSONValue.parse(bodyText) else { return }
        bodyText = value.prettyPrinted()
    }

    private func save() {
        validateName()
        if editorMode == .raw { validateBody() }
        guard canSave, let config = currentConfig else { return }
        let trimmed = name.trimmingCharacters(in: .whitespaces)

        if let e = editingEntry {
            store.update(e, name: trimmed, config: config)
            onSaved(e.id)
            dirty = false
        } else {
            let created = store.addEntry(name: trimmed, config: config, enabled: true)
            onSaved(created.id)
            dismiss()
        }
    }
}

/// A monospaced, scrollable JSON editor backed by NSTextView.
///
/// Crucially this disables macOS smart-quote / dash / text substitutions —
/// SwiftUI's `TextEditor` turns `"` into curly quotes, which silently corrupts
/// JSON. A code editor must keep characters exactly as typed.
struct CodeEditor: NSViewRepresentable {
    @Binding var text: String

    func makeNSView(context: Context) -> NSScrollView {
        let scroll = NSTextView.scrollableTextView()
        scroll.borderType = .noBorder
        scroll.drawsBackground = false
        guard let textView = scroll.documentView as? NSTextView else { return scroll }

        textView.delegate = context.coordinator
        textView.isRichText = false
        textView.isAutomaticQuoteSubstitutionEnabled = false
        textView.isAutomaticDashSubstitutionEnabled = false
        textView.isAutomaticTextReplacementEnabled = false
        textView.isAutomaticSpellingCorrectionEnabled = false
        textView.isAutomaticDataDetectionEnabled = false
        textView.isAutomaticLinkDetectionEnabled = false
        textView.isContinuousSpellCheckingEnabled = false
        textView.allowsUndo = true
        textView.font = .monospacedSystemFont(ofSize: 12, weight: .regular)
        textView.textColor = .labelColor
        textView.backgroundColor = .textBackgroundColor
        textView.textContainerInset = NSSize(width: 6, height: 8)
        textView.string = text
        return scroll
    }

    func updateNSView(_ nsView: NSScrollView, context: Context) {
        guard let textView = nsView.documentView as? NSTextView else { return }
        if textView.string != text {
            textView.string = text
        }
    }

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    final class Coordinator: NSObject, NSTextViewDelegate {
        let parent: CodeEditor
        init(_ parent: CodeEditor) { self.parent = parent }

        func textDidChange(_ notification: Notification) {
            guard let textView = notification.object as? NSTextView else { return }
            parent.text = textView.string
        }
    }
}
