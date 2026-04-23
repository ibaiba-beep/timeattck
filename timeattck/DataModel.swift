import SwiftUI
import SwiftData
import UserNotifications

// MARK: - Models

@Model final class Project {
    var id: UUID
    var name: String
    var icon: String
    var sortOrder: Int
    @Relationship(deleteRule: .cascade, inverse: \Activity.project)
    var activities: [Activity]

    init(id: UUID = UUID(), name: String, icon: String, sortOrder: Int = 0) {
        self.id = id
        self.name = name
        self.icon = icon
        self.sortOrder = sortOrder
        self.activities = []
    }
}

@Model final class Activity {
    var id: UUID
    var name: String
    var dailyGoal: TimeInterval
    var sortOrder: Int
    var project: Project?
    @Relationship(deleteRule: .cascade, inverse: \TimeRecord.activity)
    var records: [TimeRecord]

    init(id: UUID = UUID(), name: String, project: Project, dailyGoal: TimeInterval = 0, sortOrder: Int = 0) {
        self.id = id
        self.name = name
        self.project = project
        self.dailyGoal = dailyGoal
        self.sortOrder = sortOrder
        self.records = []
    }
}

@Model final class TimeRecord {
    var id: UUID
    var duration: TimeInterval
    var date: Date
    var activity: Activity?

    init(id: UUID = UUID(), activity: Activity, duration: TimeInterval, date: Date = Date()) {
        self.id = id
        self.activity = activity
        self.duration = duration
        self.date = date
    }
}

// MARK: - Project Extension

extension Project {
    var sortedActivities: [Activity] {
        activities.sorted { $0.sortOrder < $1.sortOrder }
    }
}

// MARK: - Activity Extension

extension Activity {
    var todayRecords: [TimeRecord] {
        let today = Calendar.current.startOfDay(for: Date())
        return records.filter { $0.date >= today }
    }

    var todayTime: TimeInterval {
        todayRecords.reduce(0) { $0 + $1.duration }
    }

    var totalTime: TimeInterval {
        records.reduce(0) { $0 + $1.duration }
    }

    var isTodayGoalAchieved: Bool {
        guard dailyGoal > 0 else { return false }
        return todayTime >= dailyGoal
    }

    var streak: Int {
        guard dailyGoal > 0 else { return 0 }
        let calendar = Calendar.current
        var count = 0
        var checkDate = calendar.startOfDay(for: Date())
        while true {
            let end = calendar.date(byAdding: .day, value: 1, to: checkDate)!
            let total = records.filter { $0.date >= checkDate && $0.date < end }.reduce(0.0) { $0 + $1.duration }
            if total >= dailyGoal {
                count += 1
                checkDate = calendar.date(byAdding: .day, value: -1, to: checkDate)!
            } else { break }
        }
        return count
    }

    var badge: String {
        let s = streak
        if s >= 30 { return "🏆" }
        if s >= 14 { return "🥇" }
        if s >= 7  { return "🥈" }
        if s >= 3  { return "🥉" }
        return ""
    }

    func achievedDays(in days: Int = 30) -> Int {
        guard dailyGoal > 0 else { return 0 }
        let calendar = Calendar.current
        let today = Date()
        var count = 0
        for daysAgo in 0..<days {
            guard let date = calendar.date(byAdding: .day, value: -daysAgo, to: today) else { continue }
            let start = calendar.startOfDay(for: date)
            let end = calendar.date(byAdding: .day, value: 1, to: start)!
            let total = records.filter { $0.date >= start && $0.date < end }.reduce(0.0) { $0 + $1.duration }
            if total >= dailyGoal { count += 1 }
        }
        return count
    }
}

// MARK: - ModelContainer

let sharedModelContainer: ModelContainer = {
    let schema = Schema([Project.self, Activity.self, TimeRecord.self])
    let config = ModelConfiguration(schema: schema, isStoredInMemoryOnly: false)
    do {
        return try ModelContainer(for: schema, configurations: [config])
    } catch {
        fatalError("ModelContainer 생성 실패: \(error)")
    }
}()

// MARK: - UserDefaults Migration

private struct LegacyProject: Codable {
    var id: UUID
    var name: String
    var icon: String
}

private struct LegacyActivity: Codable {
    var id: UUID
    var name: String
    var projectId: UUID
    var dailyGoal: TimeInterval
}

private struct LegacyRecord: Codable {
    var id: UUID
    var activityId: UUID
    var duration: TimeInterval
    var date: Date
}

@MainActor
func migrateFromUserDefaults(context: ModelContext) {
    guard !UserDefaults.standard.bool(forKey: "migrated_swiftdata") else { return }

    let ud = UserDefaults.standard
    var insertedProjects: [UUID: Project] = [:]
    var insertedActivities: [UUID: Activity] = [:]

    if let data = ud.data(forKey: "projects"),
       let legacyProjects = try? JSONDecoder().decode([LegacyProject].self, from: data) {
        for (index, lp) in legacyProjects.enumerated() {
            let p = Project(id: lp.id, name: lp.name, icon: lp.icon, sortOrder: index)
            context.insert(p)
            insertedProjects[lp.id] = p
        }
    } else {
        let defaults: [(String, String)] = [
            ("게임", "🎮"), ("공부", "📚"), ("SNS", "💬"),
            ("엔터테인먼트", "🎬"), ("건강/운동", "💪"), ("업무", "💼"), ("기타", "📌")
        ]
        for (index, (name, icon)) in defaults.enumerated() {
            let p = Project(name: name, icon: icon, sortOrder: index)
            context.insert(p)
            insertedProjects[p.id] = p
        }
    }

    if let data = ud.data(forKey: "activities"),
       let legacyActivities = try? JSONDecoder().decode([LegacyActivity].self, from: data) {
        for (index, la) in legacyActivities.enumerated() {
            guard let project = insertedProjects[la.projectId] else { continue }
            let a = Activity(id: la.id, name: la.name, project: project, dailyGoal: la.dailyGoal, sortOrder: index)
            context.insert(a)
            insertedActivities[la.id] = a
        }
    }

    if let data = ud.data(forKey: "records"),
       let legacyRecords = try? JSONDecoder().decode([LegacyRecord].self, from: data) {
        for lr in legacyRecords {
            guard let activity = insertedActivities[lr.activityId] else { continue }
            let r = TimeRecord(id: lr.id, activity: activity, duration: lr.duration, date: lr.date)
            context.insert(r)
        }
    }

    try? context.save()
    ud.set(true, forKey: "migrated_swiftdata")
}

// MARK: - Notification Helpers

func requestNotificationPermission() {
    UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { _, _ in }
}

func checkAndSendGoalNotification(for activity: Activity) {
    guard activity.dailyGoal > 0 else { return }
    let today = Calendar.current.startOfDay(for: Date())
    let notifiedKey = "notified_\(activity.id.uuidString)_\(today.timeIntervalSince1970)"
    guard !UserDefaults.standard.bool(forKey: notifiedKey) else { return }
    if activity.todayTime >= activity.dailyGoal {
        let content = UNMutableNotificationContent()
        content.title = "목표 달성! 🎉"
        content.body = "\(activity.name) 오늘 목표 시간을 달성했어요!"
        content.sound = .default
        let request = UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil)
        UNUserNotificationCenter.current().add(request)
        UserDefaults.standard.set(true, forKey: notifiedKey)
    }
}
