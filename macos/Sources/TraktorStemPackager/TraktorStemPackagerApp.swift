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
                .frame(minWidth: 720, minHeight: 650)
        }
        .windowResizability(.contentSize)
        .commands {
            CommandGroup(after: .appInfo) {
                Button("Check for Updates…") {
                    updateChecker.checkManually()
                }
            }
        }
    }
}
