import AppIntents
import Foundation

struct StartActivityIntent: AppIntent {
    static var title: LocalizedStringResource = "활동 시작"
    static var openAppWhenRun: Bool = true

    @Parameter(title: "활동 ID")
    var activityId: String

    init() { activityId = "" }
    init(id: String) { activityId = id }

    func perform() async throws -> some IntentResult {
        UserDefaults(suiteName: "group.com.timeattck.shared")?.set(activityId, forKey: "widget_pending_activity")
        return .result()
    }
}
