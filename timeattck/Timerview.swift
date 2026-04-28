import SwiftUI
import SwiftData
import Combine
import WidgetKit

struct TimerView: View {
    @Environment(\.modelContext) var modelContext
    @Query(sort: \Project.sortOrder) var projects: [Project]
    @Query var allRecords: [TimeRecord]
    @State private var selectedActivity: Activity? = nil
    @State private var startDate: Date? = nil
    @State private var elapsedTime: TimeInterval = 0

    var projectListView: some View {
        ScrollView {
            VStack(spacing: 10) {
                ForEach(projects) { project in
                    let activities = project.sortedActivities
                    if !activities.isEmpty {
                        timerProjectCard(project: project, activities: activities)
                    }
                }
            }
            .padding(.horizontal)
        }
    }

    func timerProjectCard(project: Project, activities: [Activity]) -> some View {
        let anySelected = activities.contains { selectedActivity?.id == $0.id }
        return HStack(alignment: .top, spacing: 0) {
            projectLabel(project: project)

            Rectangle()
                .fill(Color.gray.opacity(0.2))
                .frame(width: 1)

            VStack(spacing: 0) {
                ForEach(Array(activities.enumerated()), id: \.element.id) { index, activity in
                    timerActivityRow(activity: activity)
                    if index < activities.count - 1 {
                        Divider().padding(.leading, 14)
                    }
                }
            }
        }
        .background(anySelected ? Color.blue.opacity(0.12) : Color.gray.opacity(0.08))
        .cornerRadius(12)
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(anySelected ? Color.blue.opacity(0.3) : Color.gray.opacity(0.15), lineWidth: anySelected ? 1.5 : 1))
    }

    func projectLabel(project: Project) -> some View {
        VStack(spacing: 6) {
            Text(project.icon).font(.title2)
            Text(project.name)
                .font(.caption)
                .foregroundColor(.gray)
                .multilineTextAlignment(.center)
                .lineLimit(2)
        }
        .frame(width: 72)
        .frame(maxHeight: .infinity)
        .padding(.vertical, 14)
    }

    func timerActivityRow(activity: Activity) -> some View {
        let isSelected = selectedActivity?.id == activity.id
        return Button(action: { selectActivity(activity) }) {
            HStack {
                VStack(alignment: .leading, spacing: 3) {
                    Text(activity.name)
                        .font(.body)
                        .fontWeight(.medium)
                        .lineLimit(1)
                    if activity.dailyGoal > 0 {
                        timerProgressRow(activity: activity)
                    }
                }
                Spacer()
                if isSelected {
                    Image(systemName: "stop.circle.fill")
                        .foregroundColor(.red)
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 11)
        }
        .foregroundColor(.primary)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    func timerProgressRow(activity: Activity) -> some View {
        let todayTime = activity.todayTime
        let progress = min(todayTime / activity.dailyGoal, 1.0)
        return HStack(spacing: 4) {
            ProgressView(value: progress)
                .tint(progress >= 1.0 ? .green : .blue)
            Text(String(format: "%.0f%%", progress * 100))
                .font(.caption2)
                .foregroundColor(progress >= 1.0 ? .green : .gray)
        }
    }

    var monthFreeTime: TimeInterval {
        let cal = Calendar.current
        let now = Date()
        let monthStart = cal.date(from: cal.dateComponents([.year, .month], from: now))!
        let nextMonth = cal.date(byAdding: .month, value: 1, to: monthStart)!
        let daysInMonth = cal.dateComponents([.day], from: monthStart, to: nextMonth).day ?? 30
        let totalSeconds = TimeInterval(daysInMonth * 24 * 3600)
        let recorded = allRecords
            .filter { $0.date >= monthStart && $0.date < nextMonth }
            .reduce(0.0) { $0 + $1.duration }
        return max(totalSeconds - recorded - elapsedTime, 0)
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("이번달 공백시간").font(.caption2).foregroundColor(.gray)
                    Text(timeString(from: monthFreeTime))
                        .font(.system(.title3, design: .monospaced)).fontWeight(.medium)
                        .foregroundColor(.blue)
                }
                Spacer()
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 10)
            .background(Color.blue.opacity(0.05))

            Divider()

            VStack(spacing: 16) {
                Text(timerString(from: elapsedTime))
                    .font(.system(size: 40, weight: .thin, design: .monospaced))
                    .minimumScaleFactor(0.6)
                    .lineLimit(1)
                    .onReceive(Timer.publish(every: 0.5, on: .main, in: .common).autoconnect()) { _ in
                        if let start = startDate {
                            elapsedTime = Date().timeIntervalSince(start)
                        }
                    }
                if let activity = selectedActivity {
                    let projectIcon = activity.project?.icon ?? "📌"
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
        }
        .navigationTitle("타이머")
        .onReceive(NotificationCenter.default.publisher(for: UIApplication.willResignActiveNotification)) { _ in
            saveStartDateToStorage()
        }
        .onReceive(NotificationCenter.default.publisher(for: UIApplication.didBecomeActiveNotification)) { _ in
            restoreStartDateFromStorage()
            updateWidgetData()
            handlePendingWidgetActivity()
        }
        .onChange(of: projects) { _, _ in
            // 앱 완전 종료 후 재시작 시 @Query 로드 완료 후 복원
            if selectedActivity == nil {
                restoreStartDateFromStorage()
            }
            updateWidgetData()
        }
    }

    var todayRecordedTime: TimeInterval {
        let today = Calendar.current.startOfDay(for: Date())
        return allRecords.filter { $0.date >= today }.reduce(0) { $0 + $1.duration }
    }

    func updateWidgetData(extraDuration: TimeInterval = 0) {
        let allActivities = projects.flatMap { p in
            p.sortedActivities.map { a in
                (widget: WidgetActivity(id: a.id.uuidString, name: a.name, icon: p.icon),
                 total: a.records.reduce(0) { $0 + $1.duration })
            }
        }
        .sorted { $0.total > $1.total }
        .prefix(4)
        .map { $0.widget }
        WidgetDataStore.update(
            todayTotal: todayRecordedTime + extraDuration + elapsedTime,
            activityName: selectedActivity?.name,
            projectIcon: selectedActivity?.project?.icon,
            timerStartDate: startDate,
            activities: allActivities
        )
    }

    func selectActivity(_ activity: Activity) {
        let now = Date()
        if let current = selectedActivity {
            if current.id == activity.id {
                let dur = startDate.map { max(now.timeIntervalSince($0), 0) } ?? 0
                saveCurrentRecord(for: current, endDate: now)
                selectedActivity = nil
                startDate = nil
                elapsedTime = 0
                clearStartDateFromStorage()
                updateWidgetData(extraDuration: dur >= 60 ? dur : 0)
                return
            }
            let dur = startDate.map { max(now.timeIntervalSince($0), 0) } ?? 0
            saveCurrentRecord(for: current, endDate: now)
            selectedActivity = activity
            startDate = now
            elapsedTime = 0
            saveStartDateToStorage()
            updateWidgetData(extraDuration: dur >= 60 ? dur : 0)
            return
        }
        selectedActivity = activity
        startDate = now
        elapsedTime = 0
        saveStartDateToStorage()
        updateWidgetData()
    }

    func saveCurrentRecord(for activity: Activity, endDate: Date = Date()) {
        guard let start = startDate else { return }
        let duration = endDate.timeIntervalSince(start)
        if duration >= 60 {
            let record = TimeRecord(activity: activity, duration: duration, date: start)
            modelContext.insert(record)
            checkAndSendGoalNotification(for: activity)
        }
        startDate = nil
        elapsedTime = 0
    }

    func handlePendingWidgetActivity() {
        let key = "widget_pending_activity"
        guard let idString = UserDefaults(suiteName: "group.com.timeattck.shared")?.string(forKey: key) else { return }
        UserDefaults(suiteName: "group.com.timeattck.shared")?.removeObject(forKey: key)
        let allActivities = projects.flatMap { $0.activities }
        guard let activity = allActivities.first(where: { $0.id.uuidString == idString }) else { return }
        selectActivity(activity)
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
           let activityId = UUID(uuidString: activityIdString) {
            let allActivities = projects.flatMap { $0.activities }
            if let activity = allActivities.first(where: { $0.id == activityId }) {
                selectedActivity = activity
                startDate = savedStart
                elapsedTime = Date().timeIntervalSince(savedStart)
                updateWidgetData()
            }
        }
    }

    func clearStartDateFromStorage() {
        UserDefaults.standard.removeObject(forKey: "timerStartDate")
        UserDefaults.standard.removeObject(forKey: "timerActivityId")
    }

    func timerString(from time: TimeInterval) -> String {
        let totalSeconds = Int(time)
        let hours = (totalSeconds % 86400) / 3600
        let minutes = (totalSeconds % 3600) / 60
        let seconds = totalSeconds % 60
        if hours > 0 {
            return "\(hours)시간 \(minutes)분 \(seconds)초"
        } else {
            return "\(minutes)분 \(seconds)초"
        }
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
    TimerView()
        .modelContainer(sharedModelContainer)
}
