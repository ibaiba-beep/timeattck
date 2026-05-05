import SwiftUI
import SwiftData
import Charts

fileprivate struct ActivityLinePoint: Identifiable {
    let activityName: String
    let weekday: String
    let hours: Double
    let color: Color
    var id: String { "\(activityName)_\(weekday)" }
}

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
    @State private var monthOffset: Int = 0
    @State private var recordSortMode: Int = 0
    @State private var selectedActivityIDs: Set<UUID> = []
    @State private var highlightedActivity: String? = nil
    @State private var showingActivityFilter = false

    var allActivityIDs: Set<UUID> { Set(projects.flatMap { $0.activities }.map { $0.id }) }

    // 전체 선택 또는 빈 상태면 전체 반환
    var effectiveRecords: [TimeRecord] {
        if selectedActivityIDs.isEmpty || selectedActivityIDs == allActivityIDs { return allRecords }
        return allRecords.filter { $0.activity.map { selectedActivityIDs.contains($0.id) } ?? false }
    }

    // 실제로 일부만 선택된 상태인지
    var isFiltered: Bool {
        !selectedActivityIDs.isEmpty && selectedActivityIDs != allActivityIDs
    }

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
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button { showingActivityFilter = true } label: {
                        ZStack(alignment: .topTrailing) {
                            VStack(spacing: 2) {
                                Image(systemName: isFiltered
                                      ? "line.3.horizontal.decrease.circle.fill"
                                      : "line.3.horizontal.decrease.circle")
                                    .font(.title3)
                                    .foregroundColor(isFiltered ? .blue : .primary)
                                Text("활동필터")
                                    .font(.system(size: 9))
                                    .foregroundColor(isFiltered ? .blue : .primary)
                            }
                            if isFiltered {
                                Circle()
                                    .fill(Color.blue)
                                    .frame(width: 8, height: 8)
                                    .offset(x: 4, y: -4)
                            }
                        }
                    }
                }
            }
            .sheet(isPresented: $showingDayDetail) {
                if let date = selectedDate { DayDetailView(dateString: date) }
            }
            .sheet(isPresented: $showingActivityFilter) {
                ActivityFilterView(projects: projects, selectedIDs: $selectedActivityIDs)
            }
        }
    }

    var weeklyView: some View {
        let data = weeklyProjectData(offset: weekOffset)
        let prevData = weeklyProjectData(offset: weekOffset - 1)
        let total = data.reduce(0.0) { $0 + $1.2 }
        let range = weekRange(offset: weekOffset)
        let weekFreeSeconds = max(7 * 24 * 3600 - total * 3600, 0)
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
                    PieChartView(data: data, total: total, freeTime: weekFreeSeconds)
                        .frame(width: 260, height: 260).frame(maxWidth: .infinity)
                    legendView(data: data, total: total, prevData: prevData)
                }
            }

            VStack(alignment: .leading, spacing: 8) {
                Text("일별 사용시간").font(.headline).padding(.horizontal)
                let stackData = weekDailyTotals(offset: weekOffset)
                let dayOrder = weekDayOrder(offset: weekOffset)
                Chart {
                    ForEach(Array(stackData.enumerated()), id: \.offset) { _, item in
                        BarMark(
                            x: .value("요일", item.1),
                            y: .value("시간", item.4),
                            stacking: .standard
                        )
                        .foregroundStyle(item.3)
                        .opacity(selectedDate == nil || selectedDate == item.0 ? 1.0 : 0.35)
                    }
                }
                .chartXScale(domain: dayOrder.map { $0.1 })
                .chartLegend(.hidden)
                .chartOverlay { proxy in
                    GeometryReader { geo in
                        Rectangle().fill(Color.clear).contentShape(Rectangle())
                            .onTapGesture { location in
                                let x = location.x - geo[proxy.plotFrame!].origin.x
                                if let weekday: String = proxy.value(atX: x),
                                   let match = dayOrder.first(where: { $0.1 == weekday }) {
                                    selectedDate = match.0
                                    showingDayDetail = true
                                }
                            }
                    }
                }
                .frame(height: 180)
                .padding(.horizontal)
            }

            activityLineChartSection(offset: weekOffset)

            if data.isEmpty { emptyView }
        }
    }

    var monthlyView: some View {
        let calendar = Calendar.current
        let thisMonth = calendar.date(from: calendar.dateComponents([.year, .month], from: Date()))!
        let mStart = calendar.date(byAdding: .month, value: monthOffset, to: thisMonth)!
        let mEnd = calendar.date(byAdding: .month, value: 1, to: mStart)!
        let prevMStart = calendar.date(byAdding: .month, value: monthOffset - 1, to: thisMonth)!
        let data = monthProjectData(start: mStart, end: mEnd)
        let prevData = monthProjectData(start: prevMStart, end: mStart)
        let total = data.reduce(0.0) { $0 + $1.2 }
        let daysInMonth = Double(calendar.dateComponents([.day], from: mStart, to: mEnd).day ?? 30)
        let freeSeconds = max(daysInMonth * 24 * 3600 - total * 3600, 0)
        let mf = DateFormatter()
        mf.dateFormat = "yyyy년 M월"
        let monthLabel = mf.string(from: mStart)
        return VStack(spacing: 20) {
            summaryCard(title: "\(monthLabel) 총 사용시간", hours: total)

            HStack {
                Button(action: { withAnimation { monthOffset -= 1 } }) {
                    Image(systemName: "chevron.left.circle.fill")
                        .font(.title3).foregroundColor(.blue)
                }
                Spacer()
                Text(monthLabel).font(.subheadline).fontWeight(.medium)
                Spacer()
                Button(action: { withAnimation { monthOffset += 1 } }) {
                    Image(systemName: "chevron.right.circle.fill")
                        .font(.title3)
                        .foregroundColor(monthOffset >= 0 ? Color.gray.opacity(0.35) : .blue)
                }
                .disabled(monthOffset >= 0)
            }
            .padding(.horizontal, 20)

            if !data.isEmpty {
                VStack(alignment: .leading, spacing: 12) {
                    Text("프로젝트 비중").font(.headline).padding(.horizontal)
                    PieChartView(data: data, total: total, freeTime: freeSeconds)
                        .frame(width: 260, height: 260).frame(maxWidth: .infinity)
                    legendView(data: data, total: total, prevData: prevData)
                }
                VStack(alignment: .leading, spacing: 8) {
                    Text("주별 사용시간").font(.headline).padding(.horizontal)
                    Chart {
                        ForEach(monthWeeklyTotals(start: mStart, end: mEnd), id: \.0) { item in
                            BarMark(x: .value("주", item.0), y: .value("시간", item.1))
                                .foregroundStyle(Color.purple.gradient).cornerRadius(4)
                        }
                    }
                    .frame(height: 180).padding(.horizontal)
                }
                VStack(alignment: .leading, spacing: 8) {
                    Text("TOP 5 활동").font(.headline).padding(.horizontal)
                    ForEach(Array(monthTopActivities(start: mStart, end: mEnd).enumerated()), id: \.1.0.id) { index, item in
                        HStack(spacing: 12) {
                            Text("\(index + 1)").font(.caption).fontWeight(.bold).foregroundColor(.white)
                                .frame(width: 24, height: 24).background(medalColor(index)).clipShape(Circle())
                            HStack(spacing: 6) {
                                Image(systemName: item.0.project?.icon ?? "pin").font(.body)
                                Text(item.0.name).font(.body).lineLimit(1)
                            }
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
            Picker("보기", selection: $recordSortMode) {
                Text("카테고리별").tag(0)
                Text("시간순").tag(1)
            }
            .pickerStyle(.segmented)
            .padding(.horizontal)

            if recordSortMode == 0 {
                categoryRecordView
            } else {
                timeOrderedRecordView
            }
        }
        .alert("기록 삭제", isPresented: $showingDeleteAlert) {
            Button("삭제", role: .destructive) {
                if let record = recordToDelete { modelContext.delete(record) }
            }
            Button("취소", role: .cancel) {}
        } message: { Text("이 기록을 삭제할까요?") }
    }

    var categoryRecordView: some View {
        VStack(spacing: 16) {
            ForEach(projects) { project in
                let projectActivities = project.sortedActivities
                if !projectActivities.isEmpty {
                    VStack(alignment: .leading, spacing: 8) {
                        HStack(spacing: 6) {
                            Image(systemName: project.icon).font(.headline)
                            Text(project.name).font(.headline)
                        }.padding(.horizontal)
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
    }

    var timeOrderedRecordView: some View {
        let sorted = allRecords
            .filter { $0.duration >= 60 }
            .sorted { $0.date > $1.date }
        return VStack(spacing: 8) {
            ForEach(sorted) { record in
                HStack(spacing: 12) {
                    VStack(alignment: .leading, spacing: 2) {
                        HStack(spacing: 4) {
                            Image(systemName: record.activity?.project?.icon ?? "pin").font(.subheadline)
                            Text(record.activity?.name ?? "-").font(.subheadline).fontWeight(.medium).lineLimit(1)
                        }
                        Text(dateString(from: record.date)).font(.caption).foregroundColor(.gray)
                    }
                    Spacer()
                    Text(timeString(from: record.duration))
                        .font(.body).fontWeight(.medium).foregroundColor(.blue)
                    Button(action: { recordToDelete = record; showingDeleteAlert = true }) {
                        Image(systemName: "trash").foregroundColor(.red).font(.caption)
                    }
                }
                .padding().background(Color.gray.opacity(0.1)).cornerRadius(12).padding(.horizontal)
            }
        }
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

    func legendView(data: [(String, String, Double, Color)], total: Double, prevData: [(String, String, Double, Color)] = []) -> some View {
        VStack(spacing: 8) {
            ForEach(data.indices, id: \.self) { i in
                let item = data[i]
                let prevHours = prevData.first(where: { $0.1 == item.1 })?.2 ?? 0
                let delta = item.2 - prevHours
                let cTag = projectColorTag(item.1)
                HStack(spacing: 8) {
                    RoundedRectangle(cornerRadius: 4).fill(item.3).frame(width: 14, height: 14)
                    Image(systemName: item.0).font(.caption2).foregroundColor(item.3)
                    Text(item.1).font(.caption)
                    Spacer()
                    if !prevData.isEmpty && abs(delta) >= 1.0 / 60.0 {
                        deltaBadge(delta: delta, colorTag: cTag)
                    }
                    Text(timeString(from: item.2 * 3600)).font(.caption).foregroundColor(.gray)
                    Text(String(format: "%.0f%%", total > 0 ? item.2 / total * 100 : 0))
                        .font(.caption).fontWeight(.medium).frame(width: 36, alignment: .trailing)
                }.padding(.horizontal)
            }
        }
    }

    func deltaBadge(delta: Double, colorTag: String = "green") -> some View {
        // 빨강(부정): 감소가 좋은 것 / 파랑·초록(긍정·중립): 증가가 좋은 것
        let isGood = colorTag == "red" ? delta < 0 : delta > 0
        let isUp = delta > 0
        let label = shortTimeString(from: abs(delta) * 3600)
        return HStack(spacing: 2) {
            Image(systemName: isUp ? "arrow.up" : "arrow.down")
                .font(.system(size: 8, weight: .bold))
            Text(label)
                .font(.system(size: 9, weight: .medium))
        }
        .foregroundColor(isGood ? .green : .red)
        .padding(.horizontal, 5)
        .padding(.vertical, 2)
        .background((isGood ? Color.green : Color.red).opacity(0.12))
        .cornerRadius(4)
    }

    func projectColorTag(_ projectName: String) -> String {
        guard let project = projects.first(where: { $0.name == projectName }) else { return "green" }
        let tags = project.activities.map { $0.colorTag }
        let redCount  = tags.filter { $0 == "red"  }.count
        let blueCount = tags.filter { $0 == "blue" }.count
        if redCount > 0 && blueCount == 0  { return "red"  }
        if blueCount > 0 && redCount == 0  { return "blue" }
        return "green"
    }

    func shortTimeString(from time: TimeInterval) -> String {
        let totalSeconds = Int(time)
        let hours = totalSeconds / 3600
        let minutes = (totalSeconds % 3600) / 60
        if hours > 0 && minutes > 0 { return "\(hours)시간\(minutes)분" }
        if hours > 0 { return "\(hours)시간" }
        return "\(minutes)분"
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

    func weeklyProjectData(offset: Int) -> [(String, String, Double, Color)] {
        let range = weekRange(offset: offset)
        let colors: [Color] = [.blue, .purple, .pink, .orange, .green, .teal, .red, .cyan, .mint, .indigo]
        let weekRecords = effectiveRecords.filter { r in
            r.date < range.end && r.date.addingTimeInterval(r.duration) > range.start
        }
        var result: [(String, String, Double, Color)] = []
        for (index, project) in projects.enumerated() {
            let total = weekRecords
                .filter { $0.activity?.project?.id == project.id }
                .reduce(0.0) { sum, r in
                    let recEnd = r.date.addingTimeInterval(r.duration)
                    return sum + min(recEnd, range.end).timeIntervalSince(max(r.date, range.start))
                } / 3600.0
            if total > 0 { result.append((project.icon, project.name, total, colors[index % colors.count])) }
        }
        return result.sorted { $0.2 > $1.2 }
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
            let total = allRecords.reduce(0.0) { sum, r in
                let recEnd = r.date.addingTimeInterval(r.duration)
                guard r.date < next && recEnd > current else { return sum }
                return sum + min(recEnd, next).timeIntervalSince(max(r.date, current))
            } / 3600.0
            results.append((f.string(from: current), total))
            current = next
        }
        return results
    }

    func weekDailyTotals(offset: Int) -> [(String, String, String, Color, Double)] {
        let range = weekRange(offset: offset)
        let cal = Calendar.current
        let dateFmt = DateFormatter(); dateFmt.dateFormat = "M/d"
        let wdFmt = DateFormatter(); wdFmt.locale = Locale(identifier: "ko_KR"); wdFmt.dateFormat = "E"
        let colors: [Color] = [.blue, .purple, .pink, .orange, .green, .teal, .red, .cyan, .mint, .indigo]
        let weekRecords = effectiveRecords.filter { r in
            r.date < range.end && r.date.addingTimeInterval(r.duration) > range.start
        }
        var results: [(String, String, String, Color, Double)] = []
        var current = range.start
        while current < range.end {
            let next = cal.date(byAdding: .day, value: 1, to: current)!
            let dateKey = dateFmt.string(from: current)
            let weekday = wdFmt.string(from: current)
            for (index, project) in projects.enumerated() {
                let total = weekRecords
                    .filter { $0.activity?.project?.id == project.id }
                    .reduce(0.0) { sum, r in
                        let recEnd = r.date.addingTimeInterval(r.duration)
                        guard r.date < next && recEnd > current else { return sum }
                        return sum + min(recEnd, next).timeIntervalSince(max(r.date, current))
                    } / 3600.0
                if total > 0 {
                    results.append((dateKey, weekday, project.name, colors[index % colors.count], total))
                }
            }
            current = next
        }
        return results
    }

    func weekDayOrder(offset: Int) -> [(String, String)] {
        let range = weekRange(offset: offset)
        let cal = Calendar.current
        let dateFmt = DateFormatter(); dateFmt.dateFormat = "M/d"
        let wdFmt = DateFormatter(); wdFmt.locale = Locale(identifier: "ko_KR"); wdFmt.dateFormat = "E"
        var result: [(String, String)] = []
        var current = range.start
        while current < range.end {
            result.append((dateFmt.string(from: current), wdFmt.string(from: current)))
            current = cal.date(byAdding: .day, value: 1, to: current)!
        }
        return result
    }

    // MARK: - Shared helpers

    func monthProjectData(start: Date, end: Date) -> [(String, String, Double, Color)] {
        let colors: [Color] = [.blue, .purple, .pink, .orange, .green, .teal, .red, .cyan, .mint, .indigo]
        let periodRecords = effectiveRecords.filter { r in
            r.date < end && r.date.addingTimeInterval(r.duration) > start
        }
        var result: [(String, String, Double, Color)] = []
        for (index, project) in projects.enumerated() {
            let total = periodRecords
                .filter { $0.activity?.project?.id == project.id }
                .reduce(0.0) { sum, r in
                    let recEnd = r.date.addingTimeInterval(r.duration)
                    return sum + min(recEnd, end).timeIntervalSince(max(r.date, start))
                } / 3600.0
            if total > 0 { result.append((project.icon, project.name, total, colors[index % colors.count])) }
        }
        return result.sorted { $0.2 > $1.2 }
    }

    func monthWeeklyTotals(start: Date, end: Date) -> [(String, Double)] {
        let calendar = Calendar.current
        var results: [(String, Double)] = []
        var weekStart = start
        var weekNum = 1
        while weekStart < end {
            let weekEnd = min(calendar.date(byAdding: .day, value: 7, to: weekStart)!, end)
            let total = effectiveRecords.reduce(0.0) { sum, r in
                let recEnd = r.date.addingTimeInterval(r.duration)
                guard r.date < weekEnd && recEnd > weekStart else { return sum }
                return sum + min(recEnd, weekEnd).timeIntervalSince(max(r.date, weekStart))
            } / 3600.0
            results.append(("\(weekNum)주", total))
            weekStart = weekEnd
            weekNum += 1
        }
        return results
    }

    func monthTopActivities(start: Date, end: Date) -> [(Activity, Double)] {
        let periodRecords = effectiveRecords.filter { r in
            r.date < end && r.date.addingTimeInterval(r.duration) > start
        }
        var result: [(Activity, Double)] = []
        for activity in projects.flatMap({ $0.activities }) {
            let total = periodRecords
                .filter { $0.activity?.id == activity.id }
                .reduce(0.0) { sum, r in
                    let recEnd = r.date.addingTimeInterval(r.duration)
                    return sum + min(recEnd, end).timeIntervalSince(max(r.date, start))
                } / 3600.0
            if total > 0 { result.append((activity, total)) }
        }
        return result.sorted { $0.1 > $1.1 }.prefix(5).map { $0 }
    }

    // MARK: - 활동별 꺾은선 그래프

    fileprivate func weekActivityLinePoints(offset: Int) -> ([ActivityLinePoint], [(String, Color)]) {
        let range = weekRange(offset: offset)
        let cal = Calendar.current
        let wdFmt = DateFormatter()
        wdFmt.locale = Locale(identifier: "ko_KR"); wdFmt.dateFormat = "E"
        let palette: [Color] = [.blue, .purple, .pink, .orange, .green, .teal, .red, .cyan, .mint, .indigo]

        var points: [ActivityLinePoint] = []
        var legendItems: [(String, Color, Double)] = []

        for (projIdx, project) in projects.enumerated() {
            let color = palette[projIdx % palette.count]
            for activity in project.sortedActivities {
                guard selectedActivityIDs.isEmpty || selectedActivityIDs.contains(activity.id) else { continue }
                var dayPoints: [ActivityLinePoint] = []
                var weekTotal = 0.0
                var current = range.start
                while current < range.end {
                    let next = cal.date(byAdding: .day, value: 1, to: current)!
                    let wd = wdFmt.string(from: current)
                    let h = activity.records.reduce(0.0) { sum, r in
                        let re = r.date.addingTimeInterval(r.duration)
                        guard r.date < next && re > current else { return sum }
                        return sum + min(re, next).timeIntervalSince(max(r.date, current))
                    } / 3600.0
                    dayPoints.append(ActivityLinePoint(activityName: activity.name, weekday: wd, hours: h, color: color))
                    weekTotal += h
                    current = next
                }
                if weekTotal > 0 {
                    points.append(contentsOf: dayPoints)
                    legendItems.append((activity.name, color, weekTotal))
                }
            }
        }

        let top8 = legendItems.sorted { $0.2 > $1.2 }.prefix(8)
        let topNames = Set(top8.map { $0.0 })
        return (points.filter { topNames.contains($0.activityName) }, top8.map { ($0.0, $0.1) })
    }

    @ViewBuilder
    func activityLineChartSection(offset: Int) -> some View {
        let result = weekActivityLinePoints(offset: offset)
        let points = result.0
        let legend = result.1
        let dayOrder = weekDayOrder(offset: offset)

        if !points.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text("활동별 추이").font(.headline)
                    Spacer()
                    if highlightedActivity != nil {
                        Button("전체 보기") { withAnimation { highlightedActivity = nil } }
                            .font(.caption).foregroundColor(.blue)
                    }
                }
                .padding(.horizontal)

                Chart {
                    ForEach(points) { pt in
                        let dimmed = highlightedActivity != nil && highlightedActivity != pt.activityName
                        LineMark(
                            x: .value("요일", pt.weekday),
                            y: .value("시간", pt.hours),
                            series: .value("활동", pt.activityName)
                        )
                        .foregroundStyle(pt.color.opacity(dimmed ? 0.12 : 1.0))
                        .interpolationMethod(.catmullRom)
                        .lineStyle(StrokeStyle(
                            lineWidth: highlightedActivity == pt.activityName ? 3.5 : 2
                        ))
                    }
                    ForEach(points.filter { $0.hours > 0 }) { pt in
                        let dimmed = highlightedActivity != nil && highlightedActivity != pt.activityName
                        PointMark(
                            x: .value("요일", pt.weekday),
                            y: .value("시간", pt.hours)
                        )
                        .foregroundStyle(pt.color.opacity(dimmed ? 0.12 : 1.0))
                        .symbolSize(highlightedActivity == pt.activityName ? 55 : 28)
                    }
                }
                .chartXScale(domain: dayOrder.map { $0.1 })
                .chartYAxis {
                    AxisMarks(values: .automatic) { v in
                        AxisGridLine()
                        AxisValueLabel {
                            if let h = v.as(Double.self) {
                                Text(h < 1 && h > 0 ? String(format: "%.0f분", h * 60) : "\(Int(h))시간")
                                    .font(.system(size: 9))
                            }
                        }
                    }
                }
                .chartLegend(.hidden)
                .frame(height: 200)
                .padding(.horizontal)

                // 탭 가능한 범례
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 10) {
                        ForEach(legend.indices, id: \.self) { i in
                            let name = legend[i].0
                            let color = legend[i].1
                            let isSelected = highlightedActivity == name
                            Button {
                                withAnimation(.easeInOut(duration: 0.2)) {
                                    highlightedActivity = isSelected ? nil : name
                                }
                            } label: {
                                HStack(spacing: 5) {
                                    RoundedRectangle(cornerRadius: 2)
                                        .fill(color)
                                        .frame(width: isSelected ? 24 : 16, height: isSelected ? 4 : 3)
                                    Text(name)
                                        .font(.caption2)
                                        .fontWeight(isSelected ? .semibold : .regular)
                                        .foregroundColor(isSelected ? color : .primary)
                                }
                                .padding(.vertical, 5)
                                .padding(.horizontal, 8)
                                .background(isSelected ? color.opacity(0.12) : Color.gray.opacity(0.08))
                                .cornerRadius(8)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.horizontal)
                }
            }
            .padding(.bottom, 8)
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

    var projectData: [(String, String, Double, Color)] {
        guard let date = dayDate else { return [] }
        let start = Calendar.current.startOfDay(for: date)
        let end = Calendar.current.date(byAdding: .day, value: 1, to: start)!
        let colors: [Color] = [.blue, .purple, .pink, .orange, .green, .teal, .red]
        return projects.enumerated().compactMap { index, project in
            let total = project.activities.reduce(0.0) { sum, activity in
                sum + activity.records.filter { $0.date >= start && $0.date < end }.reduce(0.0) { $0 + $1.duration }
            } / 3600.0
            if total > 0 { return (project.icon, project.name, total, colors[index % colors.count]) }
            return nil
        }.sorted { $0.2 > $1.2 }
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

    var totalHours: Double { projectData.reduce(0.0) { $0 + $1.2 } }

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
                                ForEach(projectData.indices, id: \.self) { i in
                                    let item = projectData[i]
                                    HStack(spacing: 10) {
                                        RoundedRectangle(cornerRadius: 4).fill(item.3).frame(width: 14, height: 14)
                                        Image(systemName: item.0).font(.caption2).foregroundColor(item.3)
                                        Text(item.1).font(.caption)
                                        Spacer()
                                        Text(timeString(from: item.2 * 3600)).font(.caption).foregroundColor(.gray)
                                        Text(String(format: "%.0f%%", totalHours > 0 ? item.2 / totalHours * 100 : 0))
                                            .font(.caption).fontWeight(.medium).frame(width: 36, alignment: .trailing)
                                    }.padding(.horizontal)
                                }
                            }
                        }
                        VStack(alignment: .leading, spacing: 8) {
                            Text("활동별 사용시간").font(.headline).padding(.horizontal)
                            ForEach(topActivities, id: \.0.id) { item in
                                HStack {
                                    HStack(spacing: 6) {
                                        Image(systemName: item.0.project?.icon ?? "pin").font(.body)
                                        Text(item.0.name).font(.body).lineLimit(1)
                                    }
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

// MARK: - 활동 필터 시트
struct ActivityFilterView: View {
    @Environment(\.dismiss) var dismiss
    let projects: [Project]
    @Binding var selectedIDs: Set<UUID>

    var allActivities: [Activity] { projects.flatMap { $0.sortedActivities } }
    var allIDs: Set<UUID> { Set(allActivities.map { $0.id }) }
    var isAll: Bool { selectedIDs == allIDs || selectedIDs.isEmpty }

    func isChecked(_ activity: Activity) -> Bool {
        selectedIDs.isEmpty || selectedIDs.contains(activity.id)
    }

    func toggle(_ activity: Activity) {
        if selectedIDs.isEmpty {
            // 현재 전체 선택 상태 → 해당 항목만 해제
            selectedIDs = allIDs.subtracting([activity.id])
        } else if selectedIDs.contains(activity.id) {
            selectedIDs.remove(activity.id)
            if selectedIDs.isEmpty { selectedIDs = allIDs } // 마지막 하나 해제 시 전체로 복귀
        } else {
            selectedIDs.insert(activity.id)
            if selectedIDs == allIDs { selectedIDs.removeAll() } // 전부 선택 시 "전체" 상태로
        }
    }

    var body: some View {
        NavigationView {
            List {
                Section {
                    HStack {
                        Text(isAll ? "전체 활동 선택됨" : "\(selectedIDs.count)개 활동 선택됨")
                            .font(.subheadline).foregroundColor(.secondary)
                        Spacer()
                        Button("전체 선택") {
                            selectedIDs.removeAll() // empty = 전체
                        }
                        .font(.caption).foregroundColor(.blue)
                        .disabled(isAll)
                    }
                }
                ForEach(projects) { project in
                    if !project.sortedActivities.isEmpty {
                        Section(header: HStack(spacing: 6) {
                            Image(systemName: project.icon).font(.caption)
                            Text(project.name)
                        }) {
                            ForEach(project.sortedActivities) { activity in
                                HStack {
                                    Text(activity.name)
                                    Spacer()
                                    Image(systemName: isChecked(activity) ? "checkmark.circle.fill" : "circle")
                                        .foregroundColor(isChecked(activity) ? .blue : .gray.opacity(0.4))
                                }
                                .contentShape(Rectangle())
                                .onTapGesture { toggle(activity) }
                            }
                        }
                    }
                }
            }
            .navigationTitle("활동 필터")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("닫기") { dismiss() }
                }
            }
        }
    }
}

struct PieChartView: View {
    let data: [(String, String, Double, Color)]
    let total: Double
    var freeTime: Double? = nil

    var slices: [(startAngle: Angle, endAngle: Angle, color: Color)] {
        var result: [(Angle, Angle, Color)] = []
        var currentAngle = Angle(degrees: -90)
        for item in data {
            let angle = Angle(degrees: total > 0 ? 360 * item.2 / total : 0)
            result.append((currentAngle, currentAngle + angle, item.3))
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
            GeometryReader { geo in
                let size = min(geo.size.width, geo.size.height)
                let cx = geo.size.width / 2
                let cy = geo.size.height / 2
                let labelR = size / 2 * 0.73
                ForEach(Array(slices.enumerated()), id: \.offset) { index, slice in
                    let span = (slice.endAngle - slice.startAngle).degrees
                    if span > 22 {
                        let midRad = ((slice.startAngle.degrees + slice.endAngle.degrees) / 2) * Double.pi / 180.0
                        Image(systemName: data[index].0)
                            .font(.system(size: 13))
                            .foregroundColor(.white)
                            .position(x: cx + CGFloat(cos(midRad)) * labelR,
                                      y: cy + CGFloat(sin(midRad)) * labelR)
                    }
                }
            }
            VStack(spacing: 2) {
                Text("총").font(.caption).foregroundColor(.gray)
                Text(timeString(from: total * 3600)).font(.title3).fontWeight(.bold)
                if let free = freeTime, free > 0 {
                    Rectangle().fill(Color.gray.opacity(0.3)).frame(width: 56, height: 0.5).padding(.vertical, 2)
                    Text("공백").font(.caption2).foregroundColor(.gray)
                    Text(timeString(from: free)).font(.caption2).fontWeight(.medium).foregroundColor(.blue)
                }
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
    let config = ModelConfiguration(isStoredInMemoryOnly: true)
    let container = try! ModelContainer(for: Schema([Project.self, Activity.self, TimeRecord.self]), configurations: [config])
    return ReportView()
        .modelContainer(container)
}
