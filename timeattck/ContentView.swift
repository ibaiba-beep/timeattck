import SwiftUI
import SwiftData

struct ContentView: View {
    var body: some View {
        TabView {
            TimerView()
                .tabItem {
                    Label("타이머", systemImage: "timer")
                }
            ProjectView()
                .tabItem {
                    Label("프로젝트", systemImage: "folder")
                }
            DayTimelineView()
                .tabItem {
                    Label("타임라인", systemImage: "calendar.day.timeline.left")
                }
            ReportView()
                .tabItem {
                    Label("리포트", systemImage: "chart.bar")
                }
            SettingsView()
                .tabItem {
                    Label("설정", systemImage: "gearshape")
                }
            SocialView()
                .tabItem {
                    Label("소셜", systemImage: "person.2")
                }
        }
    }
}

#Preview {
    ContentView()
        .modelContainer(sharedModelContainer)
}
