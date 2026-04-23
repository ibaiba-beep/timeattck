import SwiftUI
import Combine

struct TimerView: View {
    @EnvironmentObject var dataModel: DataModel
    @State private var selectedActivity: Activity? = nil
    @State private var startDate: Date? = nil
    @State private var elapsedTime: TimeInterval = 0

    var projectListView: some View {
        ScrollView {
            VStack(spacing: 10) {
                ForEach(dataModel.projects) { project in
                    let projectActivities = dataModel.activities(for: project)
                    if !projectActivities.isEmpty {
                        VStack(alignment: .leading, spacing: 6) {
                            Text("\(project.icon) \(project.name)")
                                .font(.caption)
                                .foregroundColor(.gray)
                                .padding(.horizontal)
                            ForEach(projectActivities) { activity in
                                Button(action: { selectActivity(activity) }) {
                                    HStack {
                                        VStack(alignment: .leading, spacing: 2) {
                                            Text(activity.name)
                                                .font(.body)
                                                .fontWeight(.medium)
                                                .lineLimit(1)
                                            if activity.dailyGoal > 0 {
                                                let todayTime = dataModel.todayTime(for: activity)
                                                let progress = min(todayTime / activity.dailyGoal, 1.0)
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
                                        if selectedActivity?.id == activity.id {
                                            Image(systemName: "record.circle")
                                                .foregroundColor(.red)
                                        }
                                    }
                                    .padding()
                                    .background(selectedActivity?.id == activity.id ? Color.blue.opacity(0.15) : Color.gray.opacity(0.1))
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
    }

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
                if let activity = selectedActivity {
                    let projectIcon = dataModel.projects.first { $0.id == activity.projectId }?.icon ?? "📌"
                    Text("\(projectIcon) \(activity.name) 기록중")
                        .font(.headline)
                        .foregroundColor(.blue)
                } else {
                    Text("활동을 선택하면 자동으로 시작돼요")
                        .font(.subheadline)
                        .foregroundColor(.gray)
                }
            }
            .padding(.top)

            Divider().padding(.vertical, 12)

            projectListView

            if selectedActivity != nil {
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

    func selectActivity(_ activity: Activity) {
        if let current = selectedActivity {
            if current.id == activity.id { return }
            saveCurrentRecord(for: current)
        }
        selectedActivity = activity
        startDate = Date()
        elapsedTime = 0
        saveStartDateToStorage()
    }

    func stopAndSave() {
        if let activity = selectedActivity { saveCurrentRecord(for: activity) }
        selectedActivity = nil
        startDate = nil
        elapsedTime = 0
        clearStartDateFromStorage()
    }

    func saveCurrentRecord(for activity: Activity) {
        guard let start = startDate else { return }
        let duration = Date().timeIntervalSince(start)
        if duration > 0 { dataModel.addRecord(activityId: activity.id, duration: duration) }
        startDate = nil
        elapsedTime = 0
    }

    func saveStartDateToStorage() {
        if let start = startDate {
            UserDefaults.standard.set(start.timeIntervalSince1970, forKey: "timerStartDate")
            UserDefaults.standard.set(selectedActivity?.id.uuidString, forKey: "timerActivityId")
        }
    }

    func restoreStartDateFromStorage() {
        let startInterval = UserDefaults.standard.double(forKey: "timerStartDate")
        guard startInterval > 0 else { return }
        let savedStart = Date(timeIntervalSince1970: startInterval)
        if let activityIdString = UserDefaults.standard.string(forKey: "timerActivityId"),
           let activityId = UUID(uuidString: activityIdString),
           let activity = dataModel.activities.first(where: { $0.id == activityId }) {
            selectedActivity = activity
            startDate = savedStart
            elapsedTime = Date().timeIntervalSince(savedStart)
        }
    }

    func clearStartDateFromStorage() {
        UserDefaults.standard.removeObject(forKey: "timerStartDate")
        UserDefaults.standard.removeObject(forKey: "timerActivityId")
    }

    func timeString(from time: TimeInterval) -> String {
        let totalSeconds = Int(time)
        let days = totalSeconds / 86400
        let hours = (totalSeconds % 86400) / 3600
        let minutes = (totalSeconds % 3600) / 60
        if days > 0 {
            return "\(days)일 \(hours)시간 \(minutes)분"
        } else if hours > 0 {
            return "\(hours)시간 \(minutes)분"
        } else {
            let seconds = totalSeconds % 60
            return "\(minutes)분 \(seconds)초"
        }
    }
}

#Preview {
    TimerView().environmentObject(DataModel())
}
