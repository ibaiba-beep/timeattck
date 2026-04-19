import SwiftUI
import Combine

struct TimerView: View {
    @EnvironmentObject var dataModel: DataModel
    @State private var selectedProject: Project? = nil
    @State private var startDate: Date? = nil
    @State private var elapsedTime: TimeInterval = 0

    var body: some View {
        VStack(spacing: 0) {
            VStack(spacing: 16) {
                Text(timeString(from: elapsedTime))
                    .font(.system(size: 64, weight: .thin, design: .monospaced))
                    .onReceive(Timer.publish(every: 0.5, on: .main, in: .common).autoconnect()) { _ in
                        if let start = startDate {
                            elapsedTime = Date().timeIntervalSince(start)
                        }
                    }

                if let project = selectedProject {
                    let category = dataModel.category(for: project)
                    Text("\(category?.icon ?? "📌") \(project.name) 기록 중...")
                        .font(.headline)
                        .foregroundColor(.blue)
                } else {
                    Text("프로젝트를 선택하면 자동으로 시작돼요")
                        .font(.subheadline)
                        .foregroundColor(.gray)
                }
            }
            .padding(.top)

            Divider().padding(.vertical, 12)

            ScrollView {
                VStack(spacing: 10) {
                    ForEach(dataModel.categories) { category in
                        let categoryProjects = dataModel.projects.filter { $0.categoryId == category.id }
                        if !categoryProjects.isEmpty {
                            VStack(alignment: .leading, spacing: 6) {
                                Text("\(category.icon) \(category.name)")
                                    .font(.caption)
                                    .foregroundColor(.gray)
                                    .padding(.horizontal)

                                ForEach(categoryProjects) { project in
                                    Button(action: { selectProject(project) }) {
                                        HStack {
                                            VStack(alignment: .leading, spacing: 2) {
                                                Text(project.name)
                                                    .font(.body)
                                                    .fontWeight(.medium)
                                                    .lineLimit(1)
                                                if project.dailyGoal > 0 {
                                                    let todayTime = dataModel.todayTime(for: project)
                                                    let progress = min(todayTime / project.dailyGoal, 1.0)
                                                    HStack(spacing: 4) {
                                                        ProgressView(value: progress)
                                                            .frame(width: 60)
                                                            .tint(progress >= 1.0 ? .green : .blue)
                                                        Text(String(format: "%.0f%%", progress * 100))
                                                            .font(.caption2)
                                                            .foregroundColor(progress >= 1.0 ? .green : .gray)
                                                    }
                                                }
                                            }
                                            Spacer()
                                            if selectedProject?.id == project.id {
                                                Image(systemName: "record.circle")
                                                    .foregroundColor(.red)
                                            }
                                        }
                                        .padding()
                                        .background(selectedProject?.id == project.id ? Color.blue.opacity(0.15) : Color.gray.opacity(0.1))
                                        .cornerRadius(12)
                                    }
                                    .foregroundColor(.primary)
                                }
                            }
                        }
                    }
                }
                .padding(.horizontal)
            }

            if selectedProject != nil {
                Button(action: { stopAndSave() }) {
                    Text("중단 및 저장")
                        .font(.body)
                        .fontWeight(.medium)
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(Color.red.opacity(0.8))
                        .cornerRadius(12)
                }
                .padding()
            }
        }
        .navigationTitle("타이머")
        .onReceive(NotificationCenter.default.publisher(for: UIApplication.willResignActiveNotification)) { _ in
            saveStartDateToStorage()
        }
        .onReceive(NotificationCenter.default.publisher(for: UIApplication.didBecomeActiveNotification)) { _ in
            restoreStartDateFromStorage()
        }
    }

    func selectProject(_ project: Project) {
        if let current = selectedProject {
            if current.id == project.id { return }
            saveCurrentRecord(for: current)
        }
        selectedProject = project
        startDate = Date()
        elapsedTime = 0
        saveStartDateToStorage()
    }

    func stopAndSave() {
        if let project = selectedProject { saveCurrentRecord(for: project) }
        selectedProject = nil
        startDate = nil
        elapsedTime = 0
        clearStartDateFromStorage()
    }

    func saveCurrentRecord(for project: Project) {
        guard let start = startDate else { return }
        let duration = Date().timeIntervalSince(start)
        if duration > 0 { dataModel.addRecord(projectId: project.id, duration: duration) }
        startDate = nil
        elapsedTime = 0
    }

    func saveStartDateToStorage() {
        if let start = startDate {
            UserDefaults.standard.set(start.timeIntervalSince1970, forKey: "timerStartDate")
            UserDefaults.standard.set(selectedProject?.id.uuidString, forKey: "timerProjectId")
        }
    }

    func restoreStartDateFromStorage() {
        let startInterval = UserDefaults.standard.double(forKey: "timerStartDate")
        guard startInterval > 0 else { return }
        let savedStart = Date(timeIntervalSince1970: startInterval)
        if let projectIdString = UserDefaults.standard.string(forKey: "timerProjectId"),
           let projectId = UUID(uuidString: projectIdString),
           let project = dataModel.projects.first(where: { $0.id == projectId }) {
            selectedProject = project
            startDate = savedStart
            elapsedTime = Date().timeIntervalSince(savedStart)
        }
    }

    func clearStartDateFromStorage() {
        UserDefaults.standard.removeObject(forKey: "timerStartDate")
        UserDefaults.standard.removeObject(forKey: "timerProjectId")
    }

    func timeString(from time: TimeInterval) -> String {
        let h = Int(time) / 3600
        let m = Int(time) / 60 % 60
        let s = Int(time) % 60
        return String(format: "%02d:%02d:%02d", h, m, s)
    }
}

#Preview {
    TimerView().environmentObject(DataModel())
}
