import SwiftUI
import SwiftData
import Charts

struct ReportView: View {
    @Query(sort: \Project.sortOrder) var projects: [Project]
    @Query var allRecords: [TimeRecord]
    @Environment(\.modelContext) var modelContext
    @State private var selectedPeriod: Int = 0
    @State private var recordToDelete: TimeRecord? = nil
    @State private var showingDeleteAlert = false
    @State private var selectedDate: String? = nil
    @State private var showingDayDetail = false
    @State private var weekOffset: Int = 0

    var body: some View {
        NavigationView {
            ScrollView {
                VStack(spacing: 20) {
                    Picker("기간", selection: $selectedPeriod) {
                        Text("주별").tag(0)
                        Text("월별").tag(1)
                        Text("기록").tag(2)
                    }
                    .pickerStyle(.segmented).padding(.horizontal)

                    switch selectedPeriod {
                    case 0: weeklyView
                    case 1: monthlyView
                    case 2: recordListView
                    default: weeklyView
                    }
                }
                .padding(.top)
            }
            .navigationTitle("리포트")
            .sheet(isPresented: $showingDayDetail) {
                if let date = selectedDate { DayDetailView(dateString: date) }
            }
        }
    }

    var weeklyView: some View {
        let data = weeklyProjectData()
        let total = data.reduce(0.0) { $0 + $1.1 }
        let range = weekRange(offset: weekOffset)
        return VStack(spacing: 20) {
            summaryCard(
                title: weekOffset == 0 ? "이번 주 총 사용시간" : "\(weekRangeLabel(range)) 사용시간",
                hours: total
            )

            // Week navigator
            HStack {
                Button(action: { withAnimation { weekOffset -= 1 } }) {
                    Image(systemName: "chevron.left.circle.fill")
                        .font(.title3).foregroundColor(.blue)
                }
                Spacer()
                VStack(spacing: 2) {
                    Text(weekOffset == 0 ? "이번 주" : "\(-weekOffset)주 전")
                        .font(.subheadline).fontWeight(.medium)
                    Text(weekRangeLabel(range)).font(.caption).foregroundColor(.gray)
                }
                Spacer()
                Button(action: { withAnimation { weekOffset += 1 } }) {
                    Image(systemName: "chevron.right.circle.fill")
                        .font(.title3)
                        .foregroundColor(weekOffset >= 0 ? Color.gray.opacity(0.35) : .blue)
                }
                .disabled(weekOffset >= 0)
            }
            .padding(.horizontal, 20)

            if !data.isEmpty {
                VStack(alignment: .leading, spacing: 12) {
                    Text("프로젝트 비중").font(.headline).padding(.horizontal)
                    PieChartView(data: data, total: total)
                        .frame(width: 260, height: 260).frame(maxWidth: .infinity)
                    legendView(data: data, total: total)
                }
            }

            VStack(alignment: .leading, spacing: 8) {
                Text("일별 사용시간").font(.headline).padding(.horizontal)
                Text("좌우로 밀어 이번 달 전체 보기 · 탭하면 상세")
                    .font(.caption2).foregroundColor(.gray).padding(.horizontal)
                let dailyData = monthDailyTotals()
                ScrollViewReader { scrollProxy in
                    ScrollView(.horizontal, showsIndicators: false) {
                        Chart {
                            ForEach(dailyData, id: \.0) { item in
                                BarMark(x: .value("날짜", item.0), y: .value("시간", item.1))
                                    .foregroundStyle(selectedDate == item.0 ? Color.orange.gradient : Color.blue.gradient)
                                    .cornerRadius(4)
                            }
                        }
                        .chartOverlay { proxy in
                            GeometryReader { geo in
                                Rectangle().fill(Color.clear).contentShape(Rectangle())
                                    .onTapGesture { location in
                                        let x = location.x - geo[proxy.plotFrame!].origin.x
                                        if let date: String = proxy.value(atX: x) {
                                            selectedDate = date
                                            showingDayDetail = true
                                        }
                                    }
                            }
                        }
                        .frame(width: CGFloat(dailyData.count) * 44, height: 180)
                        .id("dailyChart")
                    }
                    .onAppear {
                        scrollProxy.scrollTo("dailyChart", anchor: .trailing)
                    }
                }
                .padding(.horizontal)
            }

            if data.isEmpty { emptyView }
        }
    }

    var monthlyView: some View {
        let data = periodProjectData(days: 30)
        let total = data.reduce(0.0) { $0 + $1.1 }
        return VStack(spacing: 20) {
            summaryCard(title: "이번 달 총 사용시간", hours: total)
            if !data.isEmpty {
                VStack(alignment: .leading, spacing: 12) {
                    Text("프로젝트 비중").font(.headline).padding(.horizontal)
                    PieChartView(data: data, total: total)
                        .frame(width: 260, height: 260).frame(maxWidth: .infinity)
                    legendView(data: data, total: total)
                }
                VStack(alignment: .leading, spacing: 8) {
                    Text("주별 사용시간").font(.headline).padding(.horizontal)
                    Chart {
                        ForEach(weeklyTotals(), id: \.0) { item in
                            BarMark(x: .value("주", item.0), y: .value("시간", item.1))
                                .foregroundStyle(Color.purple.gradient).cornerRadius(4)
                        }
                    }
                    .frame(height: 180).padding(.horizontal)
                }
                VStack(alignment: .leading, spacing: 8) {
                    Text("TOP 5 활동").font(.headline).padding(.horizontal)
                    ForEach(Array(topActivities(days: 30).enumerated()), id: \.1.0.id) { index, item in
                        HStack(spacing: 12) {
                            Text("\(index + 1)").font(.caption).fontWeight(.bold).foregroundColor(.white)
                                .frame(width: 24, height: 24).background(medalColor(index)).clipShape(Circle())
                            Text("\(item.0.project?.icon ?? "📌") \(item.0.name)").font(.body).lineLimit(1)
                            Spacer()
                            Text(timeString(from: item.1 * 3600)).font(.body).fontWeight(.medium).foregroundColor(.purple)
                        }
                        .padding().background(Color.gray.opacity(0.1)).cornerRadius(12).padding(.horizontal)
                    }
                }
            } else { emptyView }
        }
    }

    var recordListView: some View {
        VStack(spacing: 16) {
            ForEach(projects) { project in
                let projectActivities = project.sortedActivities
                if !projectActivities.isEmpty {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("\(project.icon) \(project.name)").font(.headline).padding(.horizontal)
                        ForEach(projectActivities) { activity in
                            VStack(alignment: .leading, spacing: 4) {
                                HStack {
                                    Text(activity.name).font(.subheadline).fontWeight(.medium)
                                    Spacer()
                                    Text("총 " + timeString(from: activity.totalTime))
                                        .font(.caption).foregroundColor(.blue).fontWeight(.medium)
                                }.padding(.horizontal)
                                let records = activity.records.filter { $0.duration >= 60 }.sorted { $0.date > $1.date }.prefix(5)
                                if records.isEmpty {
                                    Text("기록 없음").foregroundColor(.gray).font(.caption).padding(.horizontal)
                                } else {
                                    ForEach(records) { record in
                                        HStack {
                                            Text(dateString(from: record.date)).font(.caption).foregroundColor(.gray)
                                            Spacer()
                                            Text(timeString(from: record.duration)).font(.body).fontWeight(.medium)
                                            Button(action: { recordToDelete = record; showingDeleteAlert = true }) {
                                                Image(systemName: "trash").foregroundColor(.red).font(.caption)
                                            }
                                        }
                                        .padding().background(Color.gray.opacity(0.1)).cornerRadius(12).padding(.horizontal)
                                    }
                                }
                            }
                        }
                    }
                }
            }
        }
        .alert("기록 삭제", isPresented: $showingDeleteAlert) {
            Button("삭제", role: .destructive) {
                if let record = recordToDelete { modelContext.delete(record) }
            }
            Button("취소", role: .cancel) {}
        } message: { Text("이 기록을 삭제할까요?") }
    }

    func summaryCard(title: String, hours: Double) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text(title).font(.caption).foregroundColor(.gray)
                Text(timeString(from: hours * 3600)).font(.title2).fontWeight(.bold)
            }
            Spacer()
        }
        .padding().background(Color.blue.opacity(0.1)).cornerRadius(16).padding(.horizontal)
    }

    func legendView(data: [(String, Double, Color)], total: Double) -> some View {
        VStack(spacing: 8) {
            ForEach(data, id: \.0) { item in
                HStack(spacing: 10) {
                    RoundedRectangle(cornerRadius: 4).fill(item.2).frame(width: 14, height: 14)
                    Text(item.0).font(.caption)
                    Spacer()
                    Text(timeString(from: item.1 * 3600)).font(.caption).foregroundColor(.gray)
                    Text(String(format: "%.0f%%", total > 0 ? item.1 / total * 100 : 0))
                        .font(.caption).fontWeight(.medium).frame(width: 36, alignment: .trailing)
                }.padding(.horizontal)
            }
        }
    }

    var emptyView: some View {
        Text("아직 기록이 없어요").foregroundColor(.gray).frame(maxWidth: .infinity).padding()
    }

    // MARK: - Week helpers

    // Returns Monday 00:00 ~ next Monday 00:00 (exclusive end) for the given offset
    func weekRange(offset: Int) -> (start: Date, end: Date) {
        let calendar = Calendar.current
        let today = Date()
        let weekday = calendar.component(.weekday, from: today)  // 1=Sun, 2=Mon ... 7=Sat
        let daysFromMonday = weekday == 1 ? 6 : weekday - 2
        let thisMonday = calendar.date(byAdding: .day, value: -daysFromMonday, to: calendar.startOfDay(for: today))!
        let monday = calendar.date(byAdding: .weekOfYear, value: offset, to: thisMonday)!
        return (monday, calendar.date(byAdding: .day, value: 7, to: monday)!)
    }

    func weekRangeLabel(_ range: (start: Date, end: Date)) -> String {
        let f = DateFormatter(); f.dateFormat = "M/d"
        let sunday = Calendar.current.date(byAdding: .day, value: -1, to: range.end)!
        return "\(f.string(from: range.start)) ~ \(f.string(from: sunday))"
    }

    func weeklyProjectData() -> [(String, Double, Color)] {
        let range = weekRange(offset: weekOffset)
        let colors: [Color] = [.blue, .purple, .pink, .orange, .green, .teal, .red, .cyan, .mint, .indigo]
        return projects.enumerated().compactMap { index, project in
            let total = project.activities.reduce(0.0) { sum, activity in
                sum + activity.records.filter { $0.date >= range.start && $0.date < range.end }.reduce(0.0) { $0 + $1.duration }
            } / 3600.0
            if total > 0 { return ("\(project.icon) \(project.name)", total, colors[index % colors.count]) }
            return nil
        }.sorted { $0.1 > $1.1 }
    }

    func monthDailyTotals() -> [(String, Double)] {
        let calendar = Calendar.current
        let today = Date()
        let startOfMonth = calendar.date(from: calendar.dateComponents([.year, .month], from: today))!
        let f = DateFormatter(); f.dateFormat = "M/d"
        var results: [(String, Double)] = []
        var current = startOfMonth
        while current <= today {
            let next = calendar.date(byAdding: .day, value: 1, to: current)!
            let total = allRecords.filter { $0.date >= current && $0.date < next }.reduce(0.0) { $0 + $1.duration } / 3600.0
            results.append((f.string(from: current), total))
            current = next
        }
        return results
    }

    // MARK: - Shared helpers

    func periodProjectData(days: Int) -> [(String, Double, Color)] {
        let colors: [Color] = [.blue, .purple, .pink, .orange, .green, .teal, .red, .cyan, .mint, .indigo]
        let start = Calendar.current.date(byAdding: .day, value: -days, to: Date())!
        return projects.enumerated().compactMap { index, project in
            let total = project.activities.reduce(0.0) { sum, activity in
                sum + activity.records.filter { $0.date >= start }.reduce(0.0) { $0 + $1.duration }
            } / 3600.0
            if total > 0 { return ("\(project.icon) \(project.name)", total, colors[index % colors.count]) }
            return nil
        }.sorted { $0.1 > $1.1 }
    }

    func weeklyTotals() -> [(String, Double)] {
        let calendar = Calendar.current
        let today = Date()
        return (0..<4).reversed().compactMap { weekAgo -> (String, Double)? in
            guard let weekStart = calendar.date(byAdding: .weekOfYear, value: -weekAgo, to: today),
                  let weekEnd = calendar.date(byAdding: .day, value: 7, to: weekStart) else { return nil }
            let total = allRecords.filter { $0.date >= weekStart && $0.date < weekEnd }.reduce(0.0) { $0 + $1.duration } / 3600.0
            return (weekAgo == 0 ? "이번주" : "\(weekAgo)주전", total)
        }
    }

    func topActivities(days: Int) -> [(Activity, Double)] {
        let start = Calendar.current.date(byAdding: .day, value: -days, to: Date())!
        return projects.flatMap { $0.activities }.map { activity in
            let total = activity.records.filter { $0.date >= start }.reduce(0.0) { $0 + $1.duration } / 3600.0
            return (activity, total)
        }.filter { $0.1 > 0 }.sorted { $0.1 > $1.1 }.prefix(5).map { $0 }
    }

    func medalColor(_ index: Int) -> Color {
        [Color.yellow, Color.gray, Color.brown, Color.blue.opacity(0.5)][min(index, 3)]
    }

    func timeString(from time: TimeInterval) -> String {
        let totalSeconds = Int(time)
        let days = totalSeconds / 86400
        let hours = (totalSeconds % 86400) / 3600
        let minutes = (totalSeconds % 3600) / 60
        if days > 0 { return "\(days)일 \(hours)시간 \(minutes)분" }
        if hours > 0 { return "\(hours)시간 \(minutes)분" }
        return "\(minutes)분"
    }

    func dateString(from date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "MM/dd HH:mm"
        return formatter.string(from: date)
    }
}

// MARK: - 일별 상세
struct DayDetailView: View {
    @Query(sort: \Project.sortOrder) var projects: [Project]
    @Environment(\.dismiss) var dismiss
    let dateString: String

    var dayDate: Date? {
        let formatter = DateFormatter()
        formatter.dateFormat = "M/d"
        formatter.locale = Locale(identifier: "ko_KR")
        guard let parsed = formatter.date(from: dateString) else { return nil }
        let now = Date()
        let year = Calendar.current.component(.year, from: now)
        var components = Calendar.current.dateComponents([.month, .day], from: parsed)
        components.year = year
        components.hour = 0; components.minute = 0; components.second = 0
        if let date = Calendar.current.date(from: components), date > now {
            components.year = year - 1
        }
        return Calendar.current.date(from: components)
    }

    var projectData: [(String, Double, Color)] {
        guard let date = dayDate else { return [] }
        let start = Calendar.current.startOfDay(for: date)
        let end = Calendar.current.date(byAdding: .day, value: 1, to: start)!
        let colors: [Color] = [.blue, .purple, .pink, .orange, .green, .teal, .red]
        return projects.enumerated().compactMap { index, project in
            let total = project.activities.reduce(0.0) { sum, activity in
                sum + activity.records.filter { $0.date >= start && $0.date < end }.reduce(0.0) { $0 + $1.duration }
            } / 3600.0
            if total > 0 { return ("\(project.icon) \(project.name)", total, colors[index % colors.count]) }
            return nil
        }.sorted { $0.1 > $1.1 }
    }

    var topActivities: [(Activity, Double)] {
        guard let date = dayDate else { return [] }
        let start = Calendar.current.startOfDay(for: date)
        let end = Calendar.current.date(byAdding: .day, value: 1, to: start)!
        return projects.flatMap { $0.activities }.map { activity in
            let total = activity.records.filter { $0.date >= start && $0.date < end }.reduce(0.0) { $0 + $1.duration } / 3600.0
            return (activity, total)
        }.filter { $0.1 > 0 }.sorted { $0.1 > $1.1 }
    }

    var totalHours: Double { projectData.reduce(0.0) { $0 + $1.1 } }

    var body: some View {
        NavigationView {
            ScrollView {
                VStack(spacing: 20) {
                    HStack {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("\(dateString) 총 사용시간").font(.caption).foregroundColor(.gray)
                            Text(timeString(from: totalHours * 3600)).font(.title2).fontWeight(.bold)
                        }
                        Spacer()
                    }
                    .padding().background(Color.orange.opacity(0.1)).cornerRadius(16).padding(.horizontal)

                    if projectData.isEmpty {
                        Text("이 날의 기록이 없어요").foregroundColor(.gray).padding()
                    } else {
                        VStack(alignment: .leading, spacing: 12) {
                            Text("프로젝트 비중").font(.headline).padding(.horizontal)
                            PieChartView(data: projectData, total: totalHours)
                                .frame(width: 260, height: 260).frame(maxWidth: .infinity)
                            VStack(spacing: 8) {
                                ForEach(projectData, id: \.0) { item in
                                    HStack(spacing: 10) {
                                        RoundedRectangle(cornerRadius: 4).fill(item.2).frame(width: 14, height: 14)
                                        Text(item.0).font(.caption)
                                        Spacer()
                                        Text(timeString(from: item.1 * 3600)).font(.caption).foregroundColor(.gray)
                                        Text(String(format: "%.0f%%", totalHours > 0 ? item.1 / totalHours * 100 : 0))
                                            .font(.caption).fontWeight(.medium).frame(width: 36, alignment: .trailing)
                                    }.padding(.horizontal)
                                }
                            }
                        }
                        VStack(alignment: .leading, spacing: 8) {
                            Text("활동별 사용시간").font(.headline).padding(.horizontal)
                            ForEach(topActivities, id: \.0.id) { item in
                                HStack {
                                    Text("\(item.0.project?.icon ?? "📌") \(item.0.name)").font(.body).lineLimit(1)
                                    Spacer()
                                    GeometryReader { geo in
                                        ZStack(alignment: .leading) {
                                            RoundedRectangle(cornerRadius: 4).fill(Color.gray.opacity(0.15))
                                            RoundedRectangle(cornerRadius: 4).fill(Color.orange.opacity(0.7))
                                                .frame(width: totalHours > 0 ? geo.size.width * CGFloat(item.1 / totalHours) : 0)
                                        }
                                    }.frame(width: 80, height: 8)
                                    Text(timeString(from: item.1 * 3600)).font(.caption).fontWeight(.medium)
                                        .foregroundColor(.orange).frame(width: 50, alignment: .trailing)
                                }
                                .padding().background(Color.gray.opacity(0.1)).cornerRadius(12).padding(.horizontal)
                            }
                        }
                    }
                }
                .padding(.top)
            }
            .navigationTitle("\(dateString) 상세")
            .toolbar {
                ToolbarItem(placement: .automatic) { Button("닫기") { dismiss() } }
            }
        }
    }

    func timeString(from time: TimeInterval) -> String {
        let totalSeconds = Int(time)
        let days = totalSeconds / 86400
        let hours = (totalSeconds % 86400) / 3600
        let minutes = (totalSeconds % 3600) / 60
        if days > 0 { return "\(days)일 \(hours)시간 \(minutes)분" }
        if hours > 0 { return "\(hours)시간 \(minutes)분" }
        return "\(minutes)분"
    }
}

struct PieChartView: View {
    let data: [(String, Double, Color)]
    let total: Double

    var slices: [(startAngle: Angle, endAngle: Angle, color: Color)] {
        var result: [(Angle, Angle, Color)] = []
        var currentAngle = Angle(degrees: -90)
        for item in data {
            let angle = Angle(degrees: total > 0 ? 360 * item.1 / total : 0)
            result.append((currentAngle, currentAngle + angle, item.2))
            currentAngle += angle
        }
        return result
    }

    var body: some View {
        ZStack {
            ForEach(Array(slices.enumerated()), id: \.offset) { _, slice in
                PieSlice(startAngle: slice.startAngle, endAngle: slice.endAngle, innerRadiusRatio: 0.55)
                    .fill(slice.color)
                    .overlay(PieSlice(startAngle: slice.startAngle, endAngle: slice.endAngle, innerRadiusRatio: 0.55).stroke(Color.white, lineWidth: 2))
            }
            VStack(spacing: 2) {
                Text("총").font(.caption).foregroundColor(.gray)
                Text(timeString(from: total * 3600)).font(.title3).fontWeight(.bold)
            }
        }
    }

    func timeString(from time: TimeInterval) -> String {
        let totalSeconds = Int(time)
        let hours = totalSeconds / 3600
        let minutes = (totalSeconds % 3600) / 60
        if hours > 0 { return "\(hours)시간 \(minutes)분" }
        return "\(minutes)분"
    }
}

struct PieSlice: Shape {
    var startAngle: Angle
    var endAngle: Angle
    var innerRadiusRatio: CGFloat

    func path(in rect: CGRect) -> Path {
        let center = CGPoint(x: rect.midX, y: rect.midY)
        let radius = min(rect.width, rect.height) / 2
        let innerRadius = radius * innerRadiusRatio
        var path = Path()
        path.addArc(center: center, radius: radius, startAngle: startAngle, endAngle: endAngle, clockwise: false)
        path.addArc(center: center, radius: innerRadius, startAngle: endAngle, endAngle: startAngle, clockwise: true)
        path.closeSubpath()
        return path
    }
}

#Preview {
    ReportView()
        .modelContainer(sharedModelContainer)
}
