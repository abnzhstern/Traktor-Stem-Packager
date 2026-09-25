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
            CommandGroup(replacing: .newItem) {
                Button("Start New Package") {
                    model.startNewPackage()
                }
                .keyboardShortcut("n", modifiers: .command)
                .disabled(!model.canStartNewPackage)
            }
            CommandGroup(after: .appInfo) {
                Button("Check for Updates…") {
                    updateChecker.checkManually()
                }
            }
        }

        Settings {
            PreferencesView()
                .environmentObject(model)
        }
    }
}
