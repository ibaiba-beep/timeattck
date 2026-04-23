import SwiftUI
import Combine
import UserNotifications

struct ProjectCategory: Identifiable, Codable, Hashable {
    var id = UUID()
    var name: String
    var icon: String

    static let defaults: [ProjectCategory] = [
        ProjectCategory(name: "게임",       icon: "🎮"),
        ProjectCategory(name: "공부",       icon: "📚"),
        ProjectCategory(name: "SNS",        icon: "💬"),
        ProjectCategory(name: "엔터테인먼트", icon: "🎬"),
        ProjectCategory(name: "건강/운동",   icon: "💪"),
        ProjectCategory(name: "업무",       icon: "💼"),
        ProjectCategory(name: "기타",       icon: "📌"),
    ]
}

struct Project: Identifiable, Codable, Hashable {
    var id = UUID()
    var name: String
    var categoryId: UUID
    var dailyGoal: TimeInterval = 0
}

struct TimeRecord: Identifiable, Codable {
    var id = UUID()
    var projectId: UUID
    var duration: TimeInterval
    var date = Date()
}

class DataModel: ObservableObject {
    @Published var categories: [ProjectCategory] = []
    @Published var projects: [Project] = []
    @Published var records: [TimeRecord] = []

    init() {
        loadCategories()
        loadProjects()
        loadRecords()
        requestNotificationPermission()
        if categories.isEmpty {
            categories = ProjectCategory.defaults
            saveCategories()
        }
        removeSampleDataIfNeeded()
    }

    // MARK: - 카테고리 CRUD
    func addCategory(name: String, icon: String) {
        let category = ProjectCategory(name: name, icon: icon)
        categories.append(category)
        saveCategories()
    }

    func updateCategory(_ category: ProjectCategory) {
        if let index = categories.firstIndex(where: { $0.id == category.id }) {
            categories[index] = category
            saveCategories()
        }
    }

    func deleteCategory(_ category: ProjectCategory) {
        categories.removeAll { $0.id == category.id }
        saveCategories()
    }

    func category(for project: Project) -> ProjectCategory? {
        categories.first { $0.id == project.categoryId }
    }

    // MARK: - 프로젝트 CRUD
    func addProject(name: String, categoryId: UUID, dailyGoal: TimeInterval = 0) {
        let project = Project(name: name, categoryId: categoryId, dailyGoal: dailyGoal)
        projects.append(project)
        saveProjects()
    }

    func updateProject(_ project: Project) {
        if let index = projects.firstIndex(where: { $0.id == project.id }) {
            projects[index] = project
            saveProjects()
        }
    }

    func deleteProject(at offsets: IndexSet) {
        projects.remove(atOffsets: offsets)
        saveProjects()
    }

    // MARK: - 기록 CRUD
    func addRecord(projectId: UUID, duration: TimeInterval) {
        let record = TimeRecord(projectId: projectId, duration: duration)
        records.append(record)
        saveRecords()
        checkGoal(projectId: projectId)
    }

    func deleteRecord(_ record: TimeRecord) {
        records.removeAll { $0.id == record.id }
        saveRecords()
    }

    // MARK: - 시간 계산
    func records(for project: Project) -> [TimeRecord] {
        records.filter { $0.projectId == project.id }
    }

    func todayRecords(for project: Project) -> [TimeRecord] {
        let today = Calendar.current.startOfDay(for: Date())
        return records(for: project).filter { $0.date >= today }
    }

    func totalTime(for project: Project) -> TimeInterval {
        records(for: project).reduce(0) { $0 + $1.duration }
    }

    func todayTime(for project: Project) -> TimeInterval {
        todayRecords(for: project).reduce(0) { $0 + $1.duration }
    }

    func totalTime(for category: ProjectCategory) -> TimeInterval {
        projects.filter { $0.categoryId == category.id }.reduce(0) { $0 + totalTime(for: $1) }
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

    // MARK: - 습관 트래커
    func streak(for project: Project) -> Int {
        guard project.dailyGoal > 0 else { return 0 }
        let calendar = Calendar.current
        var streak = 0
        var checkDate = calendar.startOfDay(for: Date())
        for _ in 0..<365 {
            let end = calendar.date(byAdding: .day, value: 1, to: checkDate)!
            let dayTotal = records(for: project).filter { $0.date >= checkDate && $0.date < end }.reduce(0.0) { $0 + $1.duration }
            if dayTotal >= project.dailyGoal {
                streak += 1
                checkDate = calendar.date(byAdding: .day, value: -1, to: checkDate)!
            } else { break }
        }
        return streak
    }

    func isTodayGoalAchieved(for project: Project) -> Bool {
        guard project.dailyGoal > 0 else { return false }
        return todayTime(for: project) >= project.dailyGoal
    }

    func achievedDays(for project: Project, days: Int = 30) -> Int {
        guard project.dailyGoal > 0 else { return 0 }
        let calendar = Calendar.current
        let today = Date()
        var count = 0
        for daysAgo in 0..<days {
            guard let date = calendar.date(byAdding: .day, value: -daysAgo, to: today) else { continue }
            let start = calendar.startOfDay(for: date)
            let end = calendar.date(byAdding: .day, value: 1, to: start)!
            let dayTotal = records(for: project).filter { $0.date >= start && $0.date < end }.reduce(0.0) { $0 + $1.duration }
            if dayTotal >= project.dailyGoal { count += 1 }
        }
        return count
    }

    func badge(for project: Project) -> String {
        let streak = streak(for: project)
        let achieved = achievedDays(for: project, days: 30)
        if streak >= 30 { return "👑" }
        if streak >= 14 { return "💎" }
        if streak >= 7  { return "🥇" }
        if streak >= 3  { return "🥈" }
        if achieved >= 1 { return "🥉" }
        return ""
    }

    func todayGoalSummary() -> (achieved: Int, total: Int) {
        let withGoal = projects.filter { $0.dailyGoal > 0 }
        let achieved = withGoal.filter { isTodayGoalAchieved(for: $0) }.count
        return (achieved, withGoal.count)
    }

    // MARK: - 알림
    func requestNotificationPermission() {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { _, _ in }
    }

    func checkGoal(projectId: UUID) {
        guard let project = projects.first(where: { $0.id == projectId }),
              project.dailyGoal > 0 else { return }
        if todayTime(for: project) >= project.dailyGoal {
            sendNotification(project: project)
        }
    }

    func sendNotification(project: Project) {
        let content = UNMutableNotificationContent()
        content.title = "목표 달성! 🎉"
        content.body = "\(project.name) 오늘 목표 시간을 달성했어요!"
        content.sound = .default
        let request = UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil)
        UNUserNotificationCenter.current().add(request)
    }

   

    // MARK: - 저장
    private func saveCategories() {
        if let data = try? JSONEncoder().encode(categories) {
            UserDefaults.standard.set(data, forKey: "categories")
        }
    }

    private func loadCategories() {
        if let data = UserDefaults.standard.data(forKey: "categories"),
           let decoded = try? JSONDecoder().decode([ProjectCategory].self, from: data) {
            categories = decoded
        }
    }

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

    private func saveRecords() {
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
}
