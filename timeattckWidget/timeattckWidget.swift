import WidgetKit
import SwiftUI
import AppIntents

// MARK: - Timeline Entry

struct TimeattckEntry: TimelineEntry {
    let date: Date
    let activityName: String?
    let projectIcon: String?
    let timerStartDate: Date?
    let recentActivities: [WidgetActivity]

    var isRunning: Bool { timerStartDate != nil }

    static let placeholder = TimeattckEntry(
        date: .now,
        activityName: "영어 공부",
        projectIcon: "📚",
        timerStartDate: Date().addingTimeInterval(-1200),
        recentActivities: [
            WidgetActivity(id: "1", name: "영어 공부", icon: "📚"),
            WidgetActivity(id: "2", name: "어플개발", icon: "💰"),
            WidgetActivity(id: "3", name: "독서", icon: "📖"),
        ]
    )
}

// MARK: - Provider

struct TimeattckProvider: TimelineProvider {

    func placeholder(in context: Context) -> TimeattckEntry { .placeholder }

    func getSnapshot(in context: Context, completion: @escaping (TimeattckEntry) -> Void) {
        completion(context.isPreview ? .placeholder : makeEntry())
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<TimeattckEntry>) -> Void) {
        let entry = makeEntry()
        let next = Date().addingTimeInterval(entry.isRunning ? 900 : 3600)
        completion(Timeline(entries: [entry], policy: .after(next)))
    }

    private func makeEntry() -> TimeattckEntry {
        TimeattckEntry(
            date: .now,
            activityName: WidgetDataStore.activityName,
            projectIcon: WidgetDataStore.projectIcon,
            timerStartDate: WidgetDataStore.timerStartDate,
            recentActivities: WidgetDataStore.recentActivities
        )
    }
}

// MARK: - Small Widget View

struct SmallWidgetView: View {
    let entry: TimeattckEntry

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if entry.isRunning, let icon = entry.projectIcon, let name = entry.activityName {
                Text("\(icon) \(name)")
                    .font(.subheadline.bold())
                    .lineLimit(2)
                Spacer()
                if let start = entry.timerStartDate {
                    Text(start, style: .timer)
                        .font(.system(.title, design: .monospaced).bold())
                        .foregroundStyle(.blue)
                        .monospacedDigit()
                        .minimumScaleFactor(0.7)
                        .lineLimit(1)
                }
            } else {
                Spacer()
                Text("타이머 꺼짐")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
                Spacer()
            }
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .containerBackground(.background, for: .widget)
    }
}

// MARK: - Medium Widget View

struct MediumWidgetView: View {
    let entry: TimeattckEntry

    var body: some View {
        HStack(spacing: 0) {
            // 왼쪽: 활동 선택
            VStack(alignment: .leading, spacing: 8) {
                ForEach(entry.recentActivities.prefix(4)) { activity in
                    Button(intent: StartActivityIntent(id: activity.id)) {
                        HStack(spacing: 6) {
                            if entry.isRunning && entry.activityName == activity.name {
                                Circle().fill(.red).frame(width: 6, height: 6)
                            }
                            Text("\(activity.icon) \(activity.name)")
                                .font(.caption)
                                .lineLimit(1)
                                .foregroundStyle(
                                    entry.isRunning && entry.activityName == activity.name
                                    ? Color.primary : Color.secondary
                                )
                        }
                    }
                    .buttonStyle(.plain)
                }
                if entry.recentActivities.isEmpty {
                    Text("활동 없음")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }
                Spacer()
            }
            .padding()
            .frame(maxWidth: .infinity, alignment: .leading)

            Rectangle()
                .fill(Color.gray.opacity(0.3))
                .frame(width: 0.5)

            // 오른쪽: 현재 타이머 (가운데 정렬)
            VStack(alignment: .center, spacing: 6) {
                if entry.isRunning, let icon = entry.projectIcon, let name = entry.activityName {
                    HStack(spacing: 4) {
                        Circle().fill(.red).frame(width: 8, height: 8)
                        Text("기록 중")
                            .font(.caption)
                            .foregroundStyle(.red)
                    }
                    Text("\(icon) \(name)")
                        .font(.subheadline.bold())
                        .lineLimit(1)
                    Spacer()
                    if let start = entry.timerStartDate {
                        Text(start, style: .timer)
                            .font(.system(.title2, design: .monospaced).bold())
                            .foregroundStyle(.blue)
                            .monospacedDigit()
                    }
                } else {
                    Spacer()
                    Image(systemName: "pause.circle")
                        .font(.title2)
                        .foregroundStyle(.tertiary)
                    Text("실행 중인\n타이머 없음")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                    Spacer()
                }
            }
            .padding()
            .frame(maxWidth: .infinity)
        }
        .containerBackground(.background, for: .widget)
    }
}

// MARK: - Entry View

struct TimeattckWidgetEntryView: View {
    var entry: TimeattckEntry
    @Environment(\.widgetFamily) var family

    var body: some View {
        switch family {
        case .systemMedium: MediumWidgetView(entry: entry)
        default:            SmallWidgetView(entry: entry)
        }
    }
}

// MARK: - Widget

struct TimeattckWidget: Widget {
    let kind = "TimeattckWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: TimeattckProvider()) { entry in
            TimeattckWidgetEntryView(entry: entry)
        }
        .configurationDisplayName("timeattck")
        .description("활동 타이머를 확인하고 선택합니다.")
        .supportedFamilies([.systemSmall, .systemMedium])
    }
}
