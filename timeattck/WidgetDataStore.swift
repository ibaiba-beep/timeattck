import Foundation
import WidgetKit

struct WidgetActivity: Codable, Identifiable {
    let id: String
    let name: String
    let icon: String
}

struct WidgetDataStore {
    private static let defaults = UserDefaults(suiteName: "group.com.timeattck.shared")!

    private enum Key {
        static let todayTotal      = "widget_today_total"
        static let activityName    = "widget_activity_name"
        static let projectIcon     = "widget_project_icon"
        static let timerStart      = "widget_timer_start"
        static let activities      = "widget_activities"
    }

    // MARK: - Write (앱에서 호출)

    static func update(
        todayTotal: TimeInterval,
        activityName: String?,
        projectIcon: String?,
        timerStartDate: Date?,
        activities: [WidgetActivity] = []
    ) {
        defaults.set(todayTotal, forKey: Key.todayTotal)
        defaults.set(activityName, forKey: Key.activityName)
        defaults.set(projectIcon, forKey: Key.projectIcon)
        if let date = timerStartDate {
            defaults.set(date.timeIntervalSince1970, forKey: Key.timerStart)
        } else {
            defaults.removeObject(forKey: Key.timerStart)
        }
        if let data = try? JSONEncoder().encode(activities) {
            defaults.set(data, forKey: Key.activities)
        }
        WidgetCenter.shared.reloadAllTimelines()
    }

    // MARK: - Read (위젯에서 호출)

    static var todayTotal: TimeInterval {
        defaults.double(forKey: Key.todayTotal)
    }

    static var activityName: String? {
        defaults.string(forKey: Key.activityName)
    }

    static var projectIcon: String? {
        defaults.string(forKey: Key.projectIcon)
    }

    static var timerStartDate: Date? {
        let t = defaults.double(forKey: Key.timerStart)
        return t > 0 ? Date(timeIntervalSince1970: t) : nil
    }

    static var recentActivities: [WidgetActivity] {
        guard let data = defaults.data(forKey: Key.activities),
              let list = try? JSONDecoder().decode([WidgetActivity].self, from: data) else { return [] }
        return list
    }
}
