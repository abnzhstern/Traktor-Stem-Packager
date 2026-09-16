import SwiftUI

@main
struct TraktorStemPackagerApp: App {
    @StateObject private var model = PackagerModel()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(model)
                .frame(minWidth: 720, minHeight: 650)
        }
        .windowResizability(.contentSize)
    }
}
