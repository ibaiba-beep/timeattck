import SwiftUI
import Combine
import UserNotifications

// MARK: - 프로젝트 모델 (큰 단위)

struct Project: Identifiable, Codable, Hashable {
    var id = UUID()
    var name: String
    var icon: String

    static let defaults: [Project] = [
        Project(name: "게임",        icon: "🎮"),
        Project(name: "공부",        icon: "📚"),
        Project(name: "SNS",         icon: "💬"),
        Project(name: "엔터테인먼트", icon: "🎬"),
        Project(name: "건강/운동",   icon: "💪"),
        Project(name: "업무",        icon: "💼"),
        Project(name: "기타",        icon: "📌"),
    ]
}

// MARK: - 활동 모델 (작은 단위)

struct Activity: Identifiable, Codable, Hashable {
    var id = UUID()
    var name: String
    var projectId: UUID
    var dailyGoal: TimeInterval = 0
}

// MARK: - 기록 모델

struct TimeRecord: Identifiable, Codable {
    var id: UUID
    var activityId: UUID

    init(id: UUID = UUID(), activityId: UUID, duration: TimeInterval, date: Date = Date()) {
        self.id = id
        self.activityId = activityId
        self.duration = duration
        self.date = date
    }
    var duration: TimeInterval
    var date = Date()
}

// MARK: - DataModel

class DataModel: ObservableObject {
    @Published var projects: [Project] = []
    @Published var activities: [Activity] = []
    @Published var records: [TimeRecord] = []

    init() {
        loadProjects()
        loadActivities()
        loadRecords()
        requestNotificationPermission()

        if projects.isEmpty {
            projects = Project.defaults
            saveProjects()
        }

        // 기존 데이터 마이그레이션 (구버전 → 새 구조)
        migrateIfNeeded()
    }

    private func migrateIfNeeded() {
        // 이미 마이그레이션 완료된 경우 스킵
        guard !UserDefaults.standard.bool(forKey: "migrated_v2") else { return }

        // 구버전 projects 읽기 (category 필드가 있는 구조)
        struct OldProject: Codable {
            var id: UUID
            var name: String
            var category: String  // 구버전 enum rawValue
            var dailyGoal: TimeInterval
        }

        struct OldRecord: Codable {
            var id: UUID
            var projectId: UUID
            var duration: TimeInterval
            var date: Date
        }

        guard let oldProjectData = UserDefaults.standard.data(forKey: "projects"),
              let oldProjects = try? JSONDecoder().decode([OldProject].self, from: oldProjectData),
              activities.isEmpty else {
            UserDefaults.standard.set(true, forKey: "migrated_v2")
            return
        }

        // 카테고리 이름 → 새 Project로 매핑
        var categoryMap: [String: UUID] = [:]
        for oldProject in oldProjects {
            let catName = oldProject.category
            if categoryMap[catName] == nil {
                if let existing = projects.first(where: { $0.name == catName }) {
                    categoryMap[catName] = existing.id
                } else {
                    let newProject = Project(name: catName, icon: iconForCategory(catName))
                    projects.append(newProject)
                    categoryMap[catName] = newProject.id
                }
            }
            // 구버전 project → 새 Activity로 변환
            let activity = Activity(name: oldProject.name, projectId: categoryMap[catName]!, dailyGoal: oldProject.dailyGoal)
            // id는 기존 projectId 유지 (records 연결을 위해)
            var act = activity
            act.id = oldProject.id
            activities.append(act)
        }

        // 구버전 records의 projectId → activityId로 그대로 사용 (id 유지했으므로)
        if let oldRecordData = UserDefaults.standard.data(forKey: "records"),
           let oldRecords = try? JSONDecoder().decode([OldRecord].self, from: oldRecordData) {
            records = oldRecords.map {
                TimeRecord(id: $0.id, activityId: $0.projectId, duration: $0.duration, date: $0.date)
            }
        }

        saveProjects()
        saveActivities()
        saveRecords()
        UserDefaults.standard.set(true, forKey: "migrated_v2")
    }

    private func iconForCategory(_ name: String) -> String {
        switch name {
        case "게임": return "🎮"
        case "공부": return "📚"
        case "SNS": return "💬"
        case "엔터테인먼트": return "🎬"
        case "건강/운동": return "💪"
        case "업무": return "💼"
        default: return "📌"
        }
    }
 

    func requestNotificationPermission() {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { _, _ in }
    }

    // MARK: - 프로젝트 CRUD

    func addProject(name: String, icon: String) {
        let project = Project(name: name, icon: icon)
        projects.append(project)
        saveProjects()
    }

    func updateProject(_ project: Project) {
        if let index = projects.firstIndex(where: { $0.id == project.id }) {
            projects[index] = project
            saveProjects()
        }
    }

    func deleteProject(_ project: Project) {
        projects.removeAll { $0.id == project.id }
        // 해당 프로젝트의 활동과 기록도 함께 삭제
        let deletedActivityIds = activities.filter { $0.projectId == project.id }.map { $0.id }
        activities.removeAll { $0.projectId == project.id }
        records.removeAll { deletedActivityIds.contains($0.activityId) }
        saveProjects()
        saveActivities()
        saveRecords()
    }

    func project(for activity: Activity) -> Project? {
        projects.first { $0.id == activity.projectId }
    }

    // MARK: - 활동 CRUD

    func addActivity(name: String, projectId: UUID, dailyGoal: TimeInterval = 0) {
        let activity = Activity(name: name, projectId: projectId, dailyGoal: dailyGoal)
        activities.append(activity)
        saveActivities()
    }

    func updateActivity(_ activity: Activity) {
        if let index = activities.firstIndex(where: { $0.id == activity.id }) {
            activities[index] = activity
            saveActivities()
        }
    }

    func deleteActivity(at offsets: IndexSet, in projectId: UUID) {
        let projectActivities = activities.filter { $0.projectId == projectId }
        let deletedIds = offsets.map { projectActivities[$0].id }
        activities.removeAll { deletedIds.contains($0.id) }
        records.removeAll { deletedIds.contains($0.activityId) }
        saveActivities()
        saveRecords()
    }

    func activities(for project: Project) -> [Activity] {
        activities.filter { $0.projectId == project.id }
    }

    // MARK: - 기록 CRUD

    func addRecord(activityId: UUID, duration: TimeInterval) {
        let record = TimeRecord(activityId: activityId, duration: duration)
        records.append(record)
        records.sort { $0.date < $1.date }
        saveRecords()
        checkGoal(activityId: activityId)
    }

    func deleteRecord(_ record: TimeRecord) {
        records.removeAll { $0.id == record.id }
        saveRecords()
    }

    // MARK: - 조회 헬퍼

    func records(for activity: Activity) -> [TimeRecord] {
        records.filter { $0.activityId == activity.id }
    }

    func todayRecords(for activity: Activity) -> [TimeRecord] {
        let today = Calendar.current.startOfDay(for: Date())
        return records(for: activity).filter { $0.date >= today }
    }

    func totalTime(for activity: Activity) -> TimeInterval {
        records(for: activity).reduce(0) { $0 + $1.duration }
    }

    func todayTime(for activity: Activity) -> TimeInterval {
        todayRecords(for: activity).reduce(0) { $0 + $1.duration }
    }

    func isTodayGoalAchieved(for activity: Activity) -> Bool {
        guard activity.dailyGoal > 0 else { return false }
        return todayTime(for: activity) >= activity.dailyGoal
    }

    func todayGoalSummary() -> (achieved: Int, total: Int) {
        let goalActivities = activities.filter { $0.dailyGoal > 0 }
        let achieved = goalActivities.filter { isTodayGoalAchieved(for: $0) }.count
        return (achieved, goalActivities.count)
    }

    func streak(for activity: Activity) -> Int {
        guard activity.dailyGoal > 0 else { return 0 }
        let calendar = Calendar.current
        var streak = 0
        var checkDate = calendar.startOfDay(for: Date())
        while true {
            let end = calendar.date(byAdding: .day, value: 1, to: checkDate)!
            let total = records(for: activity).filter { $0.date >= checkDate && $0.date < end }.reduce(0.0) { $0 + $1.duration }
            if total >= activity.dailyGoal {
                streak += 1
                checkDate = calendar.date(byAdding: .day, value: -1, to: checkDate)!
            } else {
                break
            }
        }
        return streak
    }

    func achievedDays(for activity: Activity) -> Int {
        guard activity.dailyGoal > 0 else { return 0 }
        let calendar = Calendar.current
        let today = Date()
        var count = 0
        for daysAgo in 0..<30 {
            guard let date = calendar.date(byAdding: .day, value: -daysAgo, to: today) else { continue }
            let start = calendar.startOfDay(for: date)
            let end = calendar.date(byAdding: .day, value: 1, to: start)!
            let total = records(for: activity).filter { $0.date >= start && $0.date < end }.reduce(0.0) { $0 + $1.duration }
            if total >= activity.dailyGoal { count += 1 }
        }
        return count
    }

    func badge(for activity: Activity) -> String {
        let s = streak(for: activity)
        if s >= 30 { return "🏆" }
        if s >= 14 { return "🥇" }
        if s >= 7  { return "🥈" }
        if s >= 3  { return "🥉" }
        return ""
    }

    func dailyTotals(days: Int = 7) -> [(String, Double)] {
        let calendar = Calendar.current
        let today = Date()
        var result: [(String, Double)] = []
        for daysAgo in (0..<days).reversed() {
            guard let date = calendar.date(byAdding: .day, value: -daysAgo, to: today) else { continue }
            let start = calendar.startOfDay(for: date)
            let end = calendar.date(byAdding: .day, value: 1, to: start)!
            let total = records.filter { $0.date >= start && $0.date < end }.reduce(0.0) { $0 + $1.duration } / 3600.0
            let formatter = DateFormatter()
            formatter.dateFormat = "M/d"
            result.append((formatter.string(from: date), total))
        }
        return result
    }

    // MARK: - 목표 알림

    func checkGoal(activityId: UUID) {
        guard let activity = activities.first(where: { $0.id == activityId }),
              activity.dailyGoal > 0 else { return }
        if todayTime(for: activity) >= activity.dailyGoal {
            sendNotification(activity: activity)
        }
    }

    func sendNotification(activity: Activity) {
        let content = UNMutableNotificationContent()
        content.title = "목표 달성! 🎉"
        content.body = "\(activity.name) 오늘 목표 시간을 달성했어요!"
        content.sound = .default
        let request = UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil)
        UNUserNotificationCenter.current().add(request)
    }

    // MARK: - 저장/로드

    private func saveProjects() {
        if let data = try? JSONEncoder().encode(projects) {
            UserDefaults.standard.set(data, forKey: "projects")
        }
    }

    private func loadProjects() {
        if let data = UserDefaults.standard.data(forKey: "projects"),
           let decoded = try? JSONDecoder().decode([Project].self, from: data) {
            projects = decoded
        }
    }

    private func saveActivities() {
        if let data = try? JSONEncoder().encode(activities) {
            UserDefaults.standard.set(data, forKey: "activities")
        }
    }

    private func loadActivities() {
        if let data = UserDefaults.standard.data(forKey: "activities"),
           let decoded = try? JSONDecoder().decode([Activity].self, from: data) {
            activities = decoded
        }
    }

    func saveRecords() {
        if let data = try? JSONEncoder().encode(records) {
            UserDefaults.standard.set(data, forKey: "records")
        }
    }

    private func loadRecords() {
        if let data = UserDefaults.standard.data(forKey: "records"),
            let decoded = try? JSONDecoder().decode([TimeRecord].self, from: data) {
             records = decoded
         }
     }

     func saveAll() {
         saveProjects()
         saveActivities()
         saveRecords()
     }
 }
