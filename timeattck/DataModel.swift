import SwiftUI
import Combine
import UserNotifications

enum ProjectCategory: String, Codable, CaseIterable {
    case game = "게임"
    case study = "공부"
    case sns = "SNS"
    case entertainment = "엔터테인먼트"
    case health = "건강/운동"
    case work = "업무"
    case other = "기타"

    var icon: String {
        switch self {
        case .game: return "🎮"
        case .study: return "📚"
        case .sns: return "💬"
        case .entertainment: return "🎬"
        case .health: return "💪"
        case .work: return "💼"
        case .other: return "📌"
        }
    }
}

struct Project: Identifiable, Codable, Hashable {
    var id = UUID()
    var name: String
    var category: ProjectCategory = .other
    var dailyGoal: TimeInterval = 0
}

struct TimeRecord: Identifiable, Codable {
    var id = UUID()
    var projectId: UUID
    var duration: TimeInterval
    var date = Date()
}

class DataModel: ObservableObject {
    @Published var projects: [Project] = []
    @Published var records: [TimeRecord] = []

    init() {
        loadProjects()
        loadRecords()
        requestNotificationPermission()

        if projects.isEmpty {
            loadSampleData()
        }
    }

    func loadSampleData() {
        // 앱별 (이름, 카테고리, 하루목표, 하루평균사용시간범위(초))
        let sampleApps: [(String, ProjectCategory, TimeInterval, ClosedRange<Int>)] = [
            ("카카오톡",    .sns,           3600,  1800...5400),
            ("인스타그램",  .sns,           1800,  900...3600),
            ("유튜브",      .entertainment, 7200,  3600...9000),
            ("넷플릭스",    .entertainment, 5400,  1800...7200),
            ("듀오링고",    .study,         3600,  600...3000),
            ("리디북스",    .study,         2700,  900...4500),
            ("배틀그라운드",.game,          7200,  1800...10800),
            ("쿠키런",      .game,          1800,  600...3600),
            ("삼성헬스",    .health,        3600,  1200...5400),
            ("슬랙",        .work,          5400,  2700...7200),
            ("노션",        .work,          3600,  1800...5400),
            ("트위터",      .sns,           1800,  600...2700),
        ]

        var createdProjects: [Project] = []
        for (name, category, goal, _) in sampleApps {
            let project = Project(name: name, category: category, dailyGoal: goal)
            createdProjects.append(project)
        }
        projects = createdProjects
        saveProjects()

        var sampleRecords: [TimeRecord] = []
        let calendar = Calendar.current
        let today = Date()

        for (index, project) in projects.enumerated() {
            let range = sampleApps[index].3
            // 30일치 데이터 생성
            for daysAgo in 0..<30 {
                guard let date = calendar.date(byAdding: .day, value: -daysAgo, to: today) else { continue }

                // 주말엔 SNS/게임/엔터 사용량 증가, 평일엔 업무/공부 증가
                let weekday = calendar.component(.weekday, from: date)
                let isWeekend = weekday == 1 || weekday == 7

                var duration: TimeInterval
                switch project.category {
                case .sns, .game, .entertainment:
                    duration = TimeInterval(Int.random(in: isWeekend ? range.upperBound/2...range.upperBound : range))
                case .work, .study:
                    duration = TimeInterval(Int.random(in: isWeekend ? range.lowerBound...range.lowerBound*2 : range))
                default:
                    duration = TimeInterval(Int.random(in: range))
                }

                // 하루에 1~3개 기록으로 분산
                let sessionCount = Int.random(in: 1...3)
                for session in 0..<sessionCount {
                    let sessionDuration = duration / TimeInterval(sessionCount)
                    let hourOffset = session * 4
                    let sessionDate = calendar.date(byAdding: .hour, value: hourOffset, to: date) ?? date
                    let record = TimeRecord(projectId: project.id, duration: sessionDuration, date: sessionDate)
                    sampleRecords.append(record)
                }
            }
        }

        records = sampleRecords
        saveRecords()
    }

    func requestNotificationPermission() {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { _, _ in }
    }

    func addProject(name: String, category: ProjectCategory, dailyGoal: TimeInterval = 0) {
        let project = Project(name: name, category: category, dailyGoal: dailyGoal)
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
        let categoryProjects = projects.filter { $0.category == category }
        return categoryProjects.reduce(0) { $0 + totalTime(for: $1) }
    }

    // 최근 7일 일별 총 사용시간
    func dailyTotals(days: Int = 7) -> [(String, Double)] {
        let calendar = Calendar.current
        let today = Date()
        var result: [(String, Double)] = []

        for daysAgo in (0..<days).reversed() {
            guard let date = calendar.date(byAdding: .day, value: -daysAgo, to: today) else { continue }
            let start = calendar.startOfDay(for: date)
            let end = calendar.date(byAdding: .day, value: 1, to: start)!
            let dayRecords = records.filter { $0.date >= start && $0.date < end }
            let total = dayRecords.reduce(0.0) { $0 + $1.duration } / 3600.0

            let formatter = DateFormatter()
            formatter.dateFormat = "M/d"
            result.append((formatter.string(from: date), total))
        }
        return result
    }

    func checkGoal(projectId: UUID) {
        guard let project = projects.first(where: { $0.id == projectId }),
              project.dailyGoal > 0 else { return }
        let todayTime = todayTime(for: project)
        if todayTime >= project.dailyGoal {
            sendNotification(project: project)
        }
    }

    func sendNotification(project: Project) {
        let content = UNMutableNotificationContent()
        content.title = "목표 달성! 🎉"
        content.body = "\(project.name) 오늘 목표 시간을 달성했어요!"
        content.sound = .default
        let request = UNNotificationRequest(
            identifier: UUID().uuidString,
            content: content,
            trigger: nil
        )
        UNUserNotificationCenter.current().add(request)
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
