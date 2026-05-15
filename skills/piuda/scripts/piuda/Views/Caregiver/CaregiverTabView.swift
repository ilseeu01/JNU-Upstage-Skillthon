import SwiftUI

struct CaregiverTabView: View {
    @Environment(AppState.self) private var state
    @State private var selectedTab = 0

    var body: some View {
        TabView(selection: $selectedTab) {
            HomeView()
                .tabItem {
                    Label("홈", systemImage: "house.fill")
                }
                .tag(0)

            ReportsView()
                .tabItem {
                    Label("리포트", systemImage: "chart.bar.doc.horizontal")
                }
                .tag(1)

            AlertCenterView()
                .tabItem {
                    Label("알림", systemImage: "bell.badge.fill")
                }
                .badge(state.unreadAlertCount)
                .tag(2)

            SettingsView()
                .tabItem {
                    Label("설정", systemImage: "gearshape.fill")
                }
                .tag(3)
        }
    }
}
