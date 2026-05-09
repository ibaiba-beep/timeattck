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
    var colorTag: String = "green"  // "red" | "green" | "blue"
    var project: Project?
    @Relationship(deleteRule: .cascade, inverse: \TimeRecord.activity)
    var records: [TimeRecord]

    init(id: UUID = UUID(), name: String, project: Project, dailyGoal: TimeInterval = 0, sortOrder: Int = 0, colorTag: String = "green") {
        self.id = id
        self.name = name
        self.project = project
        self.dailyGoal = dailyGoal
        self.sortOrder = sortOrder
        self.colorTag = colorTag
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
    var sortOrder: Int = 0
}

private struct LegacyActivity: Codable {
    var id: UUID
    var name: String
    var projectId: UUID
    var dailyGoal: TimeInterval
    var sortOrder: Int = 0
    var colorTag: String = "green"
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
            let a = Activity(id: la.id, name: la.name, project: project, dailyGoal: la.dailyGoal, sortOrder: index, colorTag: la.colorTag)
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

// MARK: - Emoji → SF Symbol 매핑

let emojiToSFSymbol: [String: String] = [
    "🎮": "gamecontroller",
    "📚": "book",
    "💬": "bubble.left",
    "🎬": "film",
    "💪": "figure.strengthtraining.traditional",
    "💼": "briefcase",
    "💰": "banknote",
    "🛒": "cart",
    "🌱": "leaf",
    "🧘": "figure.mind.and.body",
    "🎵": "music.note",
    "🍳": "fork.knife",
    "✈️": "airplane",
    "🎨": "paintbrush",
    "📷": "camera",
    "🏃": "figure.run",
    "📌": "pin",
    "📝": "pencil",
    "🎯": "target",
    "🐾": "pawprint",
    "🏠": "house",
    "🚗": "car.fill",
    "💻": "laptopcomputer",
    "🎸": "guitars",
    "🏆": "trophy",
    "❤️": "heart",
    "⭐": "star",
    "📞": "phone",
    "🎓": "graduationcap",
    "💊": "pills"
]

// MARK: - 기존 이모지 → SF Symbol 마이그레이션

@MainActor
func migrateIconsToSFSymbols(context: ModelContext) {
    guard !UserDefaults.standard.bool(forKey: "migrated_icons_sf") else { return }
    let descriptor = FetchDescriptor<Project>()
    let projects = (try? context.fetch(descriptor)) ?? []
    for project in projects {
        if let sf = emojiToSFSymbol[project.icon] {
            project.icon = sf
        }
    }
    try? context.save()
    UserDefaults.standard.set(true, forKey: "migrated_icons_sf")
}

// MARK: - Bundle Backup Import (Simulator)

@MainActor
func importFromBundleBackup(context: ModelContext) {
    #if targetEnvironment(simulator)
    let descriptor = FetchDescriptor<Project>()
    guard (try? context.fetch(descriptor))?.isEmpty == true else { return }

    guard let url = Bundle.main.url(forResource: "timeattck_backup_2026-05-01", withExtension: "json"),
          let data = try? Data(contentsOf: url) else { return }

    struct BackupFile: Codable {
        var projects: [LegacyProject]
        var activities: [LegacyActivity]
        var records: [LegacyRecord]
    }

    guard let backup = try? JSONDecoder().decode(BackupFile.self, from: data) else { return }

    var projectMap: [UUID: Project] = [:]
    for lp in backup.projects {
        let sfIcon = emojiToSFSymbol[lp.icon] ?? "folder"
        let p = Project(id: lp.id, name: lp.name, icon: sfIcon, sortOrder: lp.sortOrder)
        context.insert(p)
        projectMap[lp.id] = p
    }

    var activityMap: [UUID: Activity] = [:]
    for la in backup.activities {
        guard let project = projectMap[la.projectId] else { continue }
        let a = Activity(id: la.id, name: la.name, project: project, dailyGoal: la.dailyGoal, sortOrder: la.sortOrder, colorTag: la.colorTag)
        context.insert(a)
        activityMap[la.id] = a
    }

    for lr in backup.records {
        guard let activity = activityMap[lr.activityId] else { continue }
        let r = TimeRecord(id: lr.id, activity: activity, duration: lr.duration, date: lr.date)
        context.insert(r)
    }

    try? context.save()
    UserDefaults.standard.set(true, forKey: "migrated_swiftdata")
    #endif
}

// MARK: - 시뮬레이터 샘플 데이터

@MainActor
func insertSampleDataIfNeeded(context: ModelContext) {
    #if targetEnvironment(simulator)
    let descriptor = FetchDescriptor<Project>()
    guard (try? context.fetch(descriptor))?.isEmpty == true else { return }

    let cal = Calendar.current
    let today = cal.startOfDay(for: Date())

    let p1 = Project(name: "공부", icon: "book", sortOrder: 0)
    let p2 = Project(name: "건강/운동", icon: "figure.run", sortOrder: 1)
    let p3 = Project(name: "업무", icon: "briefcase", sortOrder: 2)
    let p4 = Project(name: "엔터테인먼트", icon: "film", sortOrder: 3)
    let p5 = Project(name: "기타", icon: "pin", sortOrder: 4)
    [p1, p2, p3, p4, p5].forEach { context.insert($0) }

    let a11 = Activity(name: "독서", project: p1, dailyGoal: 3600, sortOrder: 0, colorTag: "green")
    let a12 = Activity(name: "코딩 공부", project: p1, dailyGoal: 7200, sortOrder: 1, colorTag: "blue")
    let a13 = Activity(name: "강의 수강", project: p1, dailyGoal: 3600, sortOrder: 2, colorTag: "green")
    let a21 = Activity(name: "헬스", project: p2, dailyGoal: 3600, sortOrder: 0, colorTag: "blue")
    let a22 = Activity(name: "러닝", project: p2, dailyGoal: 1800, sortOrder: 1, colorTag: "green")
    let a23 = Activity(name: "명상", project: p2, dailyGoal: 600, sortOrder: 2, colorTag: "green")
    let a31 = Activity(name: "개발", project: p3, dailyGoal: 14400, sortOrder: 0, colorTag: "blue")
    let a32 = Activity(name: "회의", project: p3, dailyGoal: 0, sortOrder: 1, colorTag: "red")
    let a33 = Activity(name: "기획/문서", project: p3, dailyGoal: 3600, sortOrder: 2, colorTag: "green")
    let a41 = Activity(name: "유튜브", project: p4, dailyGoal: 0, sortOrder: 0, colorTag: "red")
    let a42 = Activity(name: "넷플릭스", project: p4, dailyGoal: 0, sortOrder: 1, colorTag: "red")
    let a51 = Activity(name: "먹고 쉬기", project: p5, dailyGoal: 0, sortOrder: 0, colorTag: "green")
    [a11, a12, a13, a21, a22, a23, a31, a32, a33, a41, a42, a51].forEach { context.insert($0) }

    func rec(_ activity: Activity, daysAgo: Int, h: Int, m: Int = 0, mins: Int) {
        guard let day = cal.date(byAdding: .day, value: -daysAgo, to: today),
              let start = cal.date(bySettingHour: h, minute: m, second: 0, of: day) else { return }
        context.insert(TimeRecord(activity: activity, duration: TimeInterval(mins * 60), date: start))
    }

    // 오늘
    rec(a51, daysAgo: 0, h: 8, mins: 30)
    rec(a12, daysAgo: 0, h: 9, mins: 90)
    rec(a32, daysAgo: 0, h: 11, mins: 60)
    rec(a31, daysAgo: 0, h: 13, mins: 120)
    rec(a11, daysAgo: 0, h: 15, m: 30, mins: 60)
    rec(a21, daysAgo: 0, h: 19, mins: 60)
    rec(a41, daysAgo: 0, h: 21, mins: 60)

    // 어제
    rec(a51, daysAgo: 1, h: 8, mins: 30)
    rec(a31, daysAgo: 1, h: 9, mins: 150)
    rec(a32, daysAgo: 1, h: 14, mins: 90)
    rec(a33, daysAgo: 1, h: 16, mins: 60)
    rec(a22, daysAgo: 1, h: 18, m: 30, mins: 30)
    rec(a42, daysAgo: 1, h: 21, mins: 120)

    // 2일 전
    rec(a51, daysAgo: 2, h: 8, mins: 40)
    rec(a12, daysAgo: 2, h: 9, mins: 120)
    rec(a13, daysAgo: 2, h: 11, m: 30, mins: 60)
    rec(a31, daysAgo: 2, h: 14, mins: 90)
    rec(a21, daysAgo: 2, h: 19, mins: 60)
    rec(a23, daysAgo: 2, h: 22, mins: 20)

    // 3일 전
    rec(a51, daysAgo: 3, h: 8, m: 30, mins: 30)
    rec(a31, daysAgo: 3, h: 10, mins: 180)
    rec(a32, daysAgo: 3, h: 15, mins: 60)
    rec(a11, daysAgo: 3, h: 17, mins: 90)
    rec(a22, daysAgo: 3, h: 19, mins: 40)
    rec(a41, daysAgo: 3, h: 21, m: 30, mins: 60)

    // 4일 전
    rec(a51, daysAgo: 4, h: 8, mins: 30)
    rec(a12, daysAgo: 4, h: 9, m: 30, mins: 90)
    rec(a33, daysAgo: 4, h: 11, m: 30, mins: 90)
    rec(a32, daysAgo: 4, h: 14, mins: 60)
    rec(a31, daysAgo: 4, h: 15, m: 30, mins: 120)
    rec(a21, daysAgo: 4, h: 18, m: 30, mins: 60)

    // 5일 전
    rec(a51, daysAgo: 5, h: 8, mins: 30)
    rec(a11, daysAgo: 5, h: 9, mins: 60)
    rec(a13, daysAgo: 5, h: 10, m: 30, mins: 90)
    rec(a12, daysAgo: 5, h: 14, mins: 120)
    rec(a22, daysAgo: 5, h: 18, mins: 35)
    rec(a42, daysAgo: 5, h: 20, mins: 90)

    // 6일 전
    rec(a51, daysAgo: 6, h: 8, mins: 45)
    rec(a31, daysAgo: 6, h: 10, mins: 120)
    rec(a32, daysAgo: 6, h: 13, mins: 90)
    rec(a33, daysAgo: 6, h: 15, mins: 60)
    rec(a21, daysAgo: 6, h: 19, mins: 60)
    rec(a41, daysAgo: 6, h: 21, mins: 45)

    // 7~14일 전
    rec(a12, daysAgo: 7, h: 10, m: 30, mins: 90); rec(a11, daysAgo: 7, h: 14, mins: 60); rec(a22, daysAgo: 7, h: 17, mins: 40); rec(a42, daysAgo: 7, h: 21, mins: 90)
    rec(a31, daysAgo: 8, h: 9, mins: 180); rec(a32, daysAgo: 8, h: 13, mins: 60); rec(a21, daysAgo: 8, h: 18, mins: 60)
    rec(a12, daysAgo: 9, h: 10, mins: 120); rec(a13, daysAgo: 9, h: 13, mins: 90); rec(a41, daysAgo: 9, h: 20, mins: 60)
    rec(a31, daysAgo: 10, h: 9, mins: 240); rec(a33, daysAgo: 10, h: 14, mins: 60); rec(a22, daysAgo: 10, h: 18, mins: 40)
    rec(a11, daysAgo: 11, h: 9, mins: 90); rec(a12, daysAgo: 11, h: 11, mins: 90); rec(a21, daysAgo: 11, h: 18, m: 30, mins: 60); rec(a42, daysAgo: 11, h: 21, mins: 90)
    rec(a31, daysAgo: 12, h: 9, mins: 150); rec(a32, daysAgo: 12, h: 14, mins: 90); rec(a21, daysAgo: 12, h: 19, mins: 45)
    rec(a12, daysAgo: 13, h: 10, m: 30, mins: 120); rec(a13, daysAgo: 13, h: 14, mins: 90); rec(a22, daysAgo: 13, h: 18, mins: 35)
    rec(a11, daysAgo: 14, h: 9, mins: 60); rec(a31, daysAgo: 14, h: 10, m: 30, mins: 120); rec(a21, daysAgo: 14, h: 18, mins: 60)

    try? context.save()
    #endif
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
