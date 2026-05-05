import SwiftUI
import SwiftData
                                                                                                                                                                                                        
struct ContentView: View {
    var body: some View {
        TabView {
            TimerView()
                .tabItem {
                    Label("타이머", systemImage: "timer")
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
    let config = ModelConfiguration(isStoredInMemoryOnly: true)
    let container = try! ModelContainer(for: Schema([Project.self, Activity.self, TimeRecord.self]), configurations: [config])
    return ContentView()
        .modelContainer(container)
}                                           
