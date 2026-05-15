import SwiftUI

@main
struct piudaWatchApp: App {
    @State private var watchState = WatchAppState()

    var body: some Scene {
        WindowGroup {
            WatchRootView()
                .environment(watchState)
        }
    }
}
