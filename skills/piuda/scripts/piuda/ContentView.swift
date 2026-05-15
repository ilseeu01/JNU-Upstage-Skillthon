import SwiftUI

// ContentView는 RootView로 위임합니다.
struct ContentView: View {
    var body: some View {
        RootView()
    }
}

#Preview {
    ContentView()
        .environment(AppState())
}
