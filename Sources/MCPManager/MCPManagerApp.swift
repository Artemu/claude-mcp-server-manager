import SwiftUI

@main
struct MCPManagerApp: App {
    @StateObject private var store = ConfigStore()

    var body: some Scene {
        WindowGroup("MCP Manager") {
            ContentView()
                .environmentObject(store)
                .frame(minWidth: 820, minHeight: 560)
                .onAppear {
                    NSApp.setActivationPolicy(.regular)
                    NSApp.activate(ignoringOtherApps: true)
                    store.load()
                }
        }
        .windowStyle(.titleBar)
        .defaultSize(width: 960, height: 640)
        .commands {
            CommandGroup(after: .newItem) {
                Button("Reload from Disk") { store.load() }
                    .keyboardShortcut("r", modifiers: .command)
            }
        }
    }
}
