import SwiftUI

@main
struct TraktorStemPackagerApp: App {
    @StateObject private var model = PackagerModel()
    @StateObject private var updateChecker = UpdateChecker()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(model)
                .environmentObject(updateChecker)
                .frame(minWidth: 720, minHeight: 520)
        }
        .windowResizability(.contentSize)
        .commands {
            CommandGroup(after: .appInfo) {
                Button("Check for Updates…") {
                    updateChecker.checkManually()
                }
            }
            CommandMenu("Tracks") {
                Button("Clear All Tracks") {
                    model.clearAll()
                }
                .keyboardShortcut("k", modifiers: [.command, .shift])
                .disabled(model.files.isEmpty)
            }
        }
    }
}
