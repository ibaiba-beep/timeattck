import SwiftUI

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
            
            ReportView()
                .tabItem {
                    Label("리포트", systemImage: "chart.bar")
                }
        }
    }
}

#Preview {
    ContentView()
}
