import SwiftUI

@main
struct ReadBackApp: App {
    init() {
        _ = ReadbackEngineProvider.sharedStore
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
        }
    }
}
