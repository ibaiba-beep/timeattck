import SwiftUI
import SwiftData

// MARK: - 타임라인 메인 뷰 (주간 / 일별 전환)
struct DayTimelineView: View {
    @Environment(\.modelContext) var modelContext
    @Query(sort: \Project.sortOrder) var projects: [Project]
    @Query(sort: \TimeRecord.date) var allRecords: [TimeRecord]

    enum ViewMode: String, CaseIterable {
        case weekly = "주간"
        case daily  = "일별"
    }

    @State private var viewMode: ViewMode = .weekly
    @State private var weekOffset: Int = 0
    @State private var selectedDate: Date = Calendar.current.startOfDay(for: Date())
    @State private var showingRecurringRecord = false

    // 일별 뷰 상태
    @State private var recordToEdit: TimeRecord? = nil
    @State private var recordToDelete: TimeRecord? = nil
    @State private var showingDeleteAlert = false
    @State private var showingAddRecord = false
    @State private var addRecordStartDate: Date = Date()
    @State private var addRecordEndDate: Date = Date()
    @State private var selectedRecord: TimeRecord? = nil
    @State private var showingRecordActions = false
    @State private var showCalendar: Bool = false

    // 주간 간트 상수
    let hourWidth: CGFloat = 44
    let rowHeight: CGFloat = 52
    let labelWidth: CGFloat = 54
    let headerHeight: CGFloat = 22

    // 일별 타임라인 상수
    let hourHeight: CGFloat = 64
    let timeColumnWidth: CGFloat = 48

    var body: some View {
        NavigationView {
            VStack(spacing: 0) {
                Picker("", selection: $viewMode) {
                    ForEach(ViewMode.allCases, id: \.self) { mode in
                        Text(mode.rawValue).tag(mode)
                    }
                }
                .pickerStyle(.segmented)
                .padding(.horizontal, 16)
                .padding(.vertical, 8)

                Divider()

                if viewMode == .weekly {
                    weekNavBar
                    Divider()
                    weekSummaryCard
                    Divider()
                    ganttGrid
                } else {
                    dailyNavBar
                    Divider()
                    dailySummaryBar
                    Divider()
                    dailyTimelineScrollView
                }
            }
            .navigationTitle("타임라인")
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button { showingRecurringRecord = true } label: {
                        VStack(spacing: 2) {
                            Image(systemName: "repeat.circle")
                            Text("반복기록").font(.system(size: 9))
                        }
                    }
                }
            }
            .sheet(item: $recordToEdit) { record in EditRecordView(record: record) }
            .sheet(isPresented: $showingAddRecord) {
                AddRecordView(startDate: addRecordStartDate, endDate: addRecordEndDate, selectedDate: selectedDate)
            }
            .confirmationDialog("기록 옵션", isPresented: $showingRecordActions, titleVisibility: .hidden) {
                Button("수정") { recordToEdit = selectedRecord; selectedRecord = nil }
                Button("삭제", role: .destructive) { recordToDelete = selectedRecord; selectedRecord = nil; showingDeleteAlert = true }
                Button("취소", role: .cancel) { selectedRecord = nil }
            }
            .alert("기록 삭제", isPresented: $showingDeleteAlert) {
                Button("삭제", role: .destructive) { if let r = recordToDelete { modelContext.delete(r) } }
                Button("취소", role: .cancel) {}
            } message: { Text("이 기록을 삭제할까요?") }
            .sheet(isPresented: $showingRecurringRecord) { RecurringRecordView() }
        }
    }

    // MARK: - 주간 헬퍼

    var weekMonday: Date {
        let cal = Calendar.current
        let today = cal.startOfDay(for: Date())
        let weekday = cal.component(.weekday, from: today)
        let daysFromMonday = weekday == 1 ? 6 : weekday - 2
        let thisMonday = cal.date(byAdding: .day, value: -daysFromMonday, to: today)!
        return cal.date(byAdding: .weekOfYear, value: weekOffset, to: thisMonday)!
    }

    var weekDays: [Date] {
        (0..<7).map { Calendar.current.date(byAdding: .day, value: $0, to: weekMonday)! }
    }

    var weekLabel: String {
        let f = DateFormatter(); f.dateFormat = "M/d"
        let sunday = Calendar.current.date(byAdding: .day, value: 6, to: weekMonday)!
        return "\(f.string(from: weekMonday)) ~ \(f.string(from: sunday))"
    }

    var weekTotalSeconds: TimeInterval {
        weekDays.reduce(0) { $0 + dayTotalSeconds(for: $1) }
    }

    func dayTotalSeconds(for date: Date) -> TimeInterval {
        let cal = Calendar.current
        let start = cal.startOfDay(for: date)
        let end = cal.date(byAdding: .day, value: 1, to: start)!
        return allRecords.reduce(0) { sum, r in
            let rEnd = r.date.addingTimeInterval(r.duration)
            guard r.date < end && rEnd > start else { return sum }
            return sum + min(rEnd, end).timeIntervalSince(max(r.date, start))
        }
    }

    func ganttSegments(for date: Date) -> [(record: TimeRecord, displayDate: Date, displayDuration: TimeInterval)] {
        let cal = Calendar.current
        let dayStart = cal.startOfDay(for: date)
        let dayEnd = cal.date(byAdding: .day, value: 1, to: dayStart)!
        return allRecords.compactMap { record in
            let recStart = record.date
            let recEnd = recStart.addingTimeInterval(record.duration)
            guard recStart < dayEnd && recEnd > dayStart else { return nil }
            let ds = max(recStart, dayStart); let de = min(recEnd, dayEnd)
            let dur = de.timeIntervalSince(ds)
            guard dur > 0 else { return nil }
            return (record, ds, dur)
        }.sorted { $0.displayDate < $1.displayDate }
    }

    func xOffset(for date: Date) -> CGFloat {
        let c = Calendar.current
        return (CGFloat(c.component(.hour, from: date)) + CGFloat(c.component(.minute, from: date)) / 60.0) * hourWidth
    }

    func projectColor(for project: Project?) -> Color {
        let palette: [Color] = [.purple, .blue, .pink, .orange, .green, .teal, .red, .cyan, .mint, .indigo]
        guard let p = project, let index = projects.firstIndex(where: { $0.id == p.id }) else { return .gray }
        return palette[index % palette.count]
    }

    // MARK: - 주 네비게이터
    var weekNavBar: some View {
        HStack {
            Button { withAnimation { weekOffset -= 1 } } label: {
                Image(systemName: "chevron.left.circle.fill").font(.title3).foregroundColor(.blue)
            }
            Spacer()
            VStack(spacing: 2) {
                Text(weekOffset == 0 ? "이번 주" : weekOffset > 0 ? "\(weekOffset)주 후" : "\(-weekOffset)주 전")
                    .font(.subheadline).fontWeight(.medium)
                Text(weekLabel).font(.caption).foregroundColor(.gray)
            }
            Spacer()
            Button { withAnimation { weekOffset += 1 } } label: {
                Image(systemName: "chevron.right.circle.fill").font(.title3).foregroundColor(.blue)
            }
        }
        .padding(.horizontal, 20).padding(.vertical, 10)
    }

    // MARK: - 주간 요약 카드
    var weekSummaryCard: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(weekOffset == 0 ? "이번 주 총 기록" : "\(weekLabel) 기록")
                    .font(.caption).foregroundColor(.gray)
                Text(timeString(from: weekTotalSeconds)).font(.title3).fontWeight(.bold)
            }
            Spacer()
            Text("날짜 탭 → 일별 보기").font(.caption2).foregroundColor(.gray)
        }
        .padding(.horizontal, 16).padding(.vertical, 10)
        .background(Color.blue.opacity(0.06))
    }

    // MARK: - 간트 그리드
    var ganttGrid: some View {
        HStack(alignment: .top, spacing: 0) {
            VStack(spacing: 0) {
                Color.clear.frame(width: labelWidth, height: headerHeight)
                ForEach(weekDays, id: \.self) { date in
                    Divider()
                    dayLabelCell(for: date)
                }
                Divider()
            }
            .frame(width: labelWidth)

            ScrollViewReader { proxy in
                ScrollView(.horizontal, showsIndicators: false) {
                    VStack(spacing: 0) {
                        timeHeaderRow
                        ForEach(weekDays, id: \.self) { date in
                            Divider()
                            ganttRow(for: date)
                        }
                        Divider()
                    }
                    .frame(width: hourWidth * 24)
                }
                .onAppear { proxy.scrollTo(7, anchor: .leading) }
                .onChange(of: weekOffset) { _, _ in proxy.scrollTo(7, anchor: .leading) }
            }
        }
    }

    var timeHeaderRow: some View {
        ZStack(alignment: .leading) {
            HStack(spacing: 0) {
                ForEach(0..<24, id: \.self) { hour in
                    Rectangle()
                        .fill(hour % 2 == 0 ? Color.gray.opacity(0.05) : Color.clear)
                        .frame(width: hourWidth, height: headerHeight)
                        .overlay(Rectangle().fill(Color.gray.opacity(0.2)).frame(width: 0.5), alignment: .leading)
                        .id(hour)
                }
            }
            ForEach(stride(from: 0, through: 22, by: 2).map { $0 }, id: \.self) { hour in
                Text(String(format: "%02d", hour))
                    .font(.system(size: 9)).foregroundColor(.gray)
                    .offset(x: CGFloat(hour) * hourWidth + 3)
            }
        }
        .frame(width: hourWidth * 24, height: headerHeight)
    }

    func dayLabelCell(for date: Date) -> some View {
        let cal = Calendar.current
        let isToday = cal.isDateInToday(date)
        let isFuture = cal.startOfDay(for: date) > cal.startOfDay(for: Date())
        return Button {
            selectedDate = cal.startOfDay(for: date)
            viewMode = .daily
        } label: {
            VStack(spacing: 2) {
                Text(weekdayLabel(from: date)).font(.caption2)
                    .foregroundColor(isToday ? .blue : .gray)
                ZStack {
                    Circle().fill(isToday ? Color.blue : Color.clear).frame(width: 26, height: 26)
                    Text(dayNumber(from: date))
                        .font(.system(size: 13, weight: isToday ? .bold : .regular))
                        .foregroundColor(isToday ? .white : isFuture ? Color.gray.opacity(0.4) : .primary)
                }
            }
        }
        .buttonStyle(.plain)
        .frame(width: labelWidth, height: rowHeight)
    }

    func ganttRow(for date: Date) -> some View {
        let segments = ganttSegments(for: date)
        let cal = Calendar.current
        let isToday = cal.isDateInToday(date)
        let nowX = isToday ? xOffset(for: Date()) : nil

        return ZStack(alignment: .leading) {
            HStack(spacing: 0) {
                ForEach(0..<24, id: \.self) { hour in
                    Rectangle()
                        .fill(hour % 2 == 0 ? Color.gray.opacity(0.04) : Color.clear)
                        .frame(width: hourWidth, height: rowHeight)
                        .overlay(Rectangle().fill(Color.gray.opacity(0.15)).frame(width: 0.5), alignment: .leading)
                        .contentShape(Rectangle())
                        .onLongPressGesture(minimumDuration: 0.5) {
                            var comps = Calendar.current.dateComponents([.year, .month, .day], from: date)
                            comps.hour = hour; comps.minute = 0
                            let pressedStart = Calendar.current.date(from: comps) ?? date
                            addRecordStartDate = pressedStart
                            addRecordEndDate = pressedStart.addingTimeInterval(3600)
                            showingAddRecord = true
                        }
                }
            }

            ForEach(segments, id: \.record.id) { seg in
                let x = xOffset(for: seg.displayDate)
                let w = max(CGFloat(seg.displayDuration / 3600.0) * hourWidth, 6)
                let color = projectColor(for: seg.record.activity?.project)
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 4).fill(color.opacity(0.75))
                    if w > 20 {
                        Text(seg.record.activity?.name ?? "")
                            .font(.system(size: 9, weight: .medium))
                            .foregroundColor(.white).lineLimit(1).padding(.horizontal, 4)
                    }
                }
                .frame(width: w, height: rowHeight - 10)
                .offset(x: x)
                .onTapGesture {
                    selectedDate = cal.startOfDay(for: date)
                    viewMode = .daily
                }
            }

            if let nx = nowX {
                Rectangle().fill(Color.red.opacity(0.8))
                    .frame(width: 1.5, height: rowHeight).offset(x: nx)
            }
        }
        .frame(width: hourWidth * 24, height: rowHeight)
        .clipped()
    }

    // MARK: - 일별 헬퍼

    var dailyRecords: [TimeRecord] {
        let cal = Calendar.current
        let start = cal.startOfDay(for: selectedDate)
        let end = cal.date(byAdding: .day, value: 1, to: start)!
        return allRecords.filter { $0.date >= start && $0.date < end }.sorted { $0.date < $1.date }
    }

    var dailySegments: [(record: TimeRecord, displayDate: Date, displayDuration: TimeInterval)] {
        let cal = Calendar.current
        let dayStart = cal.startOfDay(for: selectedDate)
        let dayEnd = cal.date(byAdding: .day, value: 1, to: dayStart)!
        return allRecords.compactMap { record in
            let recStart = record.date
            let recEnd = recStart.addingTimeInterval(record.duration)
            guard recStart < dayEnd && recEnd > dayStart else { return nil }
            let ds = max(recStart, dayStart); let de = min(recEnd, dayEnd)
            let dur = de.timeIntervalSince(ds)
            guard dur > 0 else { return nil }
            return (record, ds, dur)
        }.sorted { $0.displayDate < $1.displayDate }
    }

    var dailyTotalTime: TimeInterval { dailySegments.reduce(0) { $0 + $1.displayDuration } }

    var dailyDateTitle: String {
        let f = DateFormatter(); f.dateFormat = "M월 d일 (E)"; f.locale = Locale(identifier: "ko_KR")
        return f.string(from: selectedDate)
    }

    // MARK: - 일별 네비게이터 (접힘/펼침 달력 포함)
    var dailyNavBar: some View {
        VStack(spacing: 0) {
            HStack {
                Button {
                    withAnimation(.spring(duration: 0.25)) {
                        selectedDate = Calendar.current.date(byAdding: .day, value: -1, to: selectedDate)!
                    }
                } label: {
                    Image(systemName: "chevron.left.circle.fill").font(.title3).foregroundColor(.blue)
                }

                Spacer()

                Button {
                    withAnimation(.spring(duration: 0.3)) { showCalendar.toggle() }
                } label: {
                    HStack(spacing: 5) {
                        VStack(spacing: 1) {
                            Text(dailyDateTitle).font(.subheadline).fontWeight(.medium)
                            if Calendar.current.isDateInToday(selectedDate) {
                                Text("오늘").font(.caption2).foregroundColor(.blue)
                            }
                        }
                        Image(systemName: showCalendar ? "chevron.up" : "chevron.down")
                            .font(.caption2).foregroundColor(.gray)
                    }
                }
                .buttonStyle(.plain)

                Spacer()

                Button {
                    withAnimation(.spring(duration: 0.25)) {
                        selectedDate = Calendar.current.date(byAdding: .day, value: 1, to: selectedDate)!
                    }
                } label: {
                    Image(systemName: "chevron.right.circle.fill").font(.title3).foregroundColor(.blue)
                }
            }
            .padding(.horizontal, 20).padding(.vertical, 10)

            if showCalendar {
                DatePicker("", selection: $selectedDate, displayedComponents: .date)
                    .datePickerStyle(.graphical)
                    .environment(\.locale, Locale(identifier: "ko_KR"))
                    .padding(.horizontal, 8)
                    .padding(.bottom, 4)
                    .onChange(of: selectedDate) { _, _ in
                        withAnimation(.spring(duration: 0.25)) { showCalendar = false }
                    }
                    .transition(.asymmetric(
                        insertion: .opacity.combined(with: .move(edge: .top)),
                        removal: .opacity.combined(with: .move(edge: .top))
                    ))
            }
        }
        .animation(.spring(duration: 0.3), value: showCalendar)
    }

    var dailySummaryBar: some View {
        HStack {
            Text("총 \(timeString(from: dailyTotalTime))").font(.subheadline).fontWeight(.medium)
            Spacer()
            Text("길게 눌러 기록 추가").font(.caption2).foregroundColor(.gray)
        }
        .padding(.horizontal, 16).padding(.vertical, 8)
        .background(Color.blue.opacity(0.05))
    }

    // MARK: - 일별 타임라인 스크롤
    var dailyTimelineScrollView: some View {
        ScrollViewReader { proxy in
            ScrollView {
                ZStack(alignment: .topLeading) {
                    dailyHourGrid
                    dailyRecordBlocks
                }
                .frame(height: hourHeight * 24).padding(.bottom, 20)
            }
            .onAppear { scrollDailyToCurrentTime(proxy: proxy) }
            .onChange(of: selectedDate) { _, _ in scrollDailyToCurrentTime(proxy: proxy) }
        }
    }

    func scrollDailyToCurrentTime(proxy: ScrollViewProxy) {
        let scrollHour: Int
        if Calendar.current.isDateInToday(selectedDate) {
            scrollHour = max(Calendar.current.component(.hour, from: Date()) - 2, 0)
        } else {
            scrollHour = dailySegments.first.map { Calendar.current.component(.hour, from: $0.displayDate) } ?? 8
        }
        proxy.scrollTo(max(scrollHour - 1, 0), anchor: .top)
    }

    var dailyHourGrid: some View {
        VStack(spacing: 0) {
            ForEach(0..<24, id: \.self) { hour in
                HStack(alignment: .top, spacing: 0) {
                    Text(String(format: "%02d:00", hour)).font(.caption2).foregroundColor(.gray)
                        .frame(width: timeColumnWidth, alignment: .trailing)
                        .padding(.trailing, 8).offset(y: -6)
                    ZStack {
                        Rectangle().fill(Color.gray.opacity(0.15)).frame(height: 0.5)
                            .frame(maxWidth: .infinity).offset(y: -hourHeight / 2)
                        Color.clear.contentShape(Rectangle())
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                            .onLongPressGesture(minimumDuration: 0.5) {
                                var components = Calendar.current.dateComponents([.year, .month, .day], from: selectedDate)
                                components.hour = hour; components.minute = 0
                                let pressedStart = Calendar.current.date(from: components) ?? Date()
                                addRecordStartDate = pressedStart
                                let next = dailyRecords.filter { $0.date > pressedStart }.min(by: { $0.date < $1.date })
                                addRecordEndDate = next?.date ?? pressedStart.addingTimeInterval(3600)
                                showingAddRecord = true
                            }
                    }
                }
                .frame(height: hourHeight).id(hour)
            }
        }
    }

    var dailyRecordBlocks: some View {
        GeometryReader { geo in
            let blockWidth = geo.size.width - timeColumnWidth - 16
            let segs = dailySegments
            let cols = layoutColumns(for: segs)
            ForEach(Array(segs.enumerated()), id: \.element.record.id) { index, seg in
                let record = seg.record
                let project = record.activity?.project
                let yOff = yPosition(for: seg.displayDate)
                let maxH = hourHeight * 24 - yOff
                let blockH = max(min(heightForDuration(seg.displayDuration), maxH), 28)
                let colInfo = cols[index]
                let colW = (blockWidth - 8) / CGFloat(colInfo.total)
                let xOff = timeColumnWidth + 8 + colW * CGFloat(colInfo.column)
                let isSelected = selectedRecord?.id == record.id

                ZStack(alignment: .topLeading) {
                    RoundedRectangle(cornerRadius: 6)
                        .fill(projectColor(for: project).opacity(isSelected ? 0.45 : 0.2))
                        .overlay(RoundedRectangle(cornerRadius: 6)
                            .stroke(projectColor(for: project), lineWidth: isSelected ? 2.5 : 1.5))
                    VStack(alignment: .leading, spacing: 2) {
                        HStack(spacing: 4) {
                            Image(systemName: project?.icon ?? "pin")
                                .font(.system(size: 9)).foregroundColor(projectColor(for: project))
                            Text(record.activity?.name ?? "알 수 없음")
                                .font(.caption).fontWeight(.medium).lineLimit(1)
                                .foregroundColor(projectColor(for: project))
                        }
                        if blockH > 44 {
                            Text(timeString(from: seg.displayDuration)).font(.caption2).foregroundColor(.gray)
                        }
                    }
                    .padding(.horizontal, 6).padding(.vertical, 4)
                }
                .frame(width: colW - 2, height: blockH)
                .offset(x: xOff, y: yOff)
                .onTapGesture { recordToEdit = record }
                .onLongPressGesture(minimumDuration: 0.4) { selectedRecord = record; showingRecordActions = true }
            }
        }
    }

    func layoutColumns(for segs: [(record: TimeRecord, displayDate: Date, displayDuration: TimeInterval)]) -> [(column: Int, total: Int)] {
        let maxCols = 5; let n = segs.count
        guard n > 0 else { return [] }
        let tops = segs.map { yPosition(for: $0.displayDate) }
        let bottoms = segs.enumerated().map { i, s in tops[i] + max(heightForDuration(s.displayDuration), 28) }
        var assigned = [Int](repeating: 0, count: n)
        var colBottoms = [CGFloat](repeating: -1, count: maxCols)
        for i in 0..<n {
            var col = maxCols - 1
            for c in 0..<maxCols { if colBottoms[c] <= tops[i] { col = c; break } }
            assigned[i] = col
            colBottoms[col] = max(colBottoms[col], bottoms[i])
        }
        var result = Array(repeating: (column: 0, total: 1), count: n)
        for i in 0..<n {
            var maxCol = assigned[i]
            for j in 0..<n { if tops[i] < bottoms[j] && bottoms[i] > tops[j] { maxCol = max(maxCol, assigned[j]) } }
            result[i] = (column: assigned[i], total: min(maxCol + 1, maxCols))
        }
        return result
    }

    func yPosition(for date: Date) -> CGFloat {
        let c = Calendar.current
        return CGFloat(c.component(.hour, from: date)) * hourHeight
            + CGFloat(c.component(.minute, from: date)) / 60.0 * hourHeight
    }

    func heightForDuration(_ d: TimeInterval) -> CGFloat { CGFloat(d / 3600.0) * hourHeight }

    // MARK: - 포맷 헬퍼
    func weekdayLabel(from date: Date) -> String {
        let f = DateFormatter(); f.dateFormat = "E"; f.locale = Locale(identifier: "ko_KR")
        return f.string(from: date)
    }

    func dayNumber(from date: Date) -> String {
        let f = DateFormatter(); f.dateFormat = "d"; return f.string(from: date)
    }

    func timeString(from time: TimeInterval) -> String {
        let s = Int(time); let h = s / 3600; let m = (s % 3600) / 60
        if h > 0 { return "\(h)시간 \(m)분" }
        return "\(m)분"
    }
}

// MARK: - 기록 추가
struct AddRecordView: View {
    @Environment(\.modelContext) var modelContext
    @Environment(\.dismiss) var dismiss
    @Query(sort: \Project.sortOrder) var projects: [Project]
    @Query(sort: \TimeRecord.date) var allRecords: [TimeRecord]
    @State private var startDateTime: Date
    @State private var endDateTime: Date
    @State private var selectedProject: Project? = nil
    @State private var selectedActivity: Activity? = nil
    @State private var step = 1
    @State private var showingOverlapAlert = false

    init(startDate: Date, endDate: Date, selectedDate: Date) {
        _startDateTime = State(initialValue: startDate)
        _endDateTime = State(initialValue: endDate)
    }

    var duration: TimeInterval { max(endDateTime.timeIntervalSince(startDateTime), 0) }

    func hasOverlap(start: Date, end: Date) -> Bool {
        allRecords.contains { let recEnd = $0.date.addingTimeInterval($0.duration); return start < recEnd && end > $0.date }
    }

    var body: some View {
        NavigationView {
            if step == 1 { projectSelectionView } else { activityAndTimeView }
        }
    }

    var projectSelectionView: some View {
        List {
            ForEach(projects) { project in
                if project.activities.count > 0 {
                    HStack {
                        Image(systemName: project.icon).font(.title3).frame(width: 28, height: 28)
                        Text(project.name).font(.body); Spacer()
                        Text("\(project.activities.count)개").font(.caption).foregroundColor(.gray)
                        Image(systemName: "chevron.right").foregroundColor(.gray).font(.caption)
                    }
                    .contentShape(Rectangle()).onTapGesture { selectedProject = project; step = 2 }
                }
            }
        }
        .navigationTitle("프로젝트 선택")
        .toolbar { ToolbarItem(placement: .cancellationAction) { Button("취소") { dismiss() } } }
    }

    var activityAndTimeView: some View {
        Form {
            Section(header: Text("프로젝트")) {
                HStack {
                    Image(systemName: selectedProject?.icon ?? "pin").foregroundColor(.blue)
                    Text(selectedProject?.name ?? "").foregroundColor(.blue)
                }
                .contentShape(Rectangle()).onTapGesture { step = 1 }
            }
            Section(header: Text("활동 선택")) {
                if let project = selectedProject {
                    ForEach(project.sortedActivities) { activity in
                        HStack {
                            Text(activity.name); Spacer()
                            if selectedActivity?.id == activity.id { Image(systemName: "checkmark").foregroundColor(.blue) }
                        }
                        .contentShape(Rectangle()).onTapGesture { selectedActivity = activity }
                    }
                }
            }
            Section(header: Text("시작")) {
                DatePicker("날짜", selection: $startDateTime, displayedComponents: .date).environment(\.locale, Locale(identifier: "ko_KR"))
                DatePicker("시간", selection: $startDateTime, displayedComponents: .hourAndMinute)
            }
            Section(header: Text("종료")) {
                DatePicker("날짜", selection: $endDateTime, displayedComponents: .date).environment(\.locale, Locale(identifier: "ko_KR"))
                DatePicker("시간", selection: $endDateTime, displayedComponents: .hourAndMinute)
            }
            Section { HStack { Text("총 시간"); Spacer(); Text(timeString(from: duration)).foregroundColor(.blue).fontWeight(.medium) } }
        }
        .navigationTitle("기록 추가")
        .toolbar {
            ToolbarItem(placement: .automatic) {
                Button("추가") {
                    guard let activity = selectedActivity, duration > 0 else { return }
                    if hasOverlap(start: startDateTime, end: endDateTime) { showingOverlapAlert = true }
                    else { modelContext.insert(TimeRecord(activity: activity, duration: duration, date: startDateTime)); dismiss() }
                }
                .disabled(selectedActivity == nil || duration <= 0)
            }
            ToolbarItem(placement: .cancellationAction) { Button("취소") { dismiss() } }
        }
        .alert("시간 겹침", isPresented: $showingOverlapAlert) {
            Button("확인", role: .cancel) {}
        } message: { Text("해당 시간대에 이미 기록이 있어요.\n다른 시간을 선택해주세요.") }
    }

    func timeString(from time: TimeInterval) -> String {
        let s = Int(time); let h = s / 3600; let m = (s % 3600) / 60
        if h > 0 { return "\(h)시간 \(m)분" }; return "\(m)분"
    }
}

// MARK: - 기록 수정
struct EditRecordView: View {
    @Environment(\.dismiss) var dismiss
    @Query(sort: \Project.sortOrder) var projects: [Project]
    @Query(sort: \TimeRecord.date) var allRecords: [TimeRecord]
    let record: TimeRecord
    @State private var startDateTime: Date
    @State private var endDateTime: Date
    @State private var selectedProject: Project?
    @State private var selectedActivity: Activity?
    @State private var showingOverlapAlert = false
    @State private var conflictingRecord: TimeRecord? = nil

    init(record: TimeRecord) {
        self.record = record
        _startDateTime = State(initialValue: record.date)
        _endDateTime = State(initialValue: record.date.addingTimeInterval(record.duration))
        _selectedProject = State(initialValue: record.activity?.project)
        _selectedActivity = State(initialValue: record.activity)
    }

    var duration: TimeInterval { max(endDateTime.timeIntervalSince(startDateTime), 0) }

    var overlapAlertMessage: String {
        guard let c = conflictingRecord else { return "해당 시간대에 이미 기록이 있어요." }
        let f = DateFormatter()
        f.dateFormat = "M/d HH:mm"
        let s = f.string(from: c.date)
        let e = f.string(from: c.date.addingTimeInterval(c.duration))
        let name = c.activity?.name ?? "알 수 없음"
        return "'\(name)' (\(s)~\(e))와 겹쳐요.\n타임라인에서 해당 기록을 확인해주세요."
    }

    func findConflict(start: Date, end: Date) -> TimeRecord? {
        allRecords.filter { $0.id != record.id }.first {
            let recEnd = $0.date.addingTimeInterval($0.duration)
            return start < recEnd && end > $0.date
        }
    }

    var body: some View {
        NavigationView {
            Form {
                Section(header: Text("프로젝트")) {
                    ForEach(projects) { project in
                        if !project.sortedActivities.isEmpty {
                            HStack {
                                Image(systemName: project.icon).font(.body).frame(width: 26, height: 26)
                                Text(project.name); Spacer()
                                if selectedProject?.id == project.id { Image(systemName: "checkmark").foregroundColor(.blue) }
                            }
                            .contentShape(Rectangle())
                            .onTapGesture { if selectedProject?.id != project.id { selectedProject = project; selectedActivity = nil } }
                        }
                    }
                }
                Section(header: Text("활동")) {
                    if let project = selectedProject {
                        ForEach(project.sortedActivities) { activity in
                            HStack {
                                Text(activity.name); Spacer()
                                if selectedActivity?.id == activity.id { Image(systemName: "checkmark").foregroundColor(.blue) }
                            }
                            .contentShape(Rectangle()).onTapGesture { selectedActivity = activity }
                        }
                    } else { Text("프로젝트를 먼저 선택해주세요").foregroundColor(.gray).font(.caption) }
                }
                Section(header: Text("시작")) {
                    DatePicker("날짜", selection: $startDateTime, displayedComponents: .date).environment(\.locale, Locale(identifier: "ko_KR"))
                    DatePicker("시간", selection: $startDateTime, displayedComponents: .hourAndMinute)
                }
                Section(header: Text("종료")) {
                    DatePicker("날짜", selection: $endDateTime, displayedComponents: .date).environment(\.locale, Locale(identifier: "ko_KR"))
                    DatePicker("시간", selection: $endDateTime, displayedComponents: .hourAndMinute)
                }
                Section { HStack { Text("총 시간"); Spacer(); Text(timeString(from: duration)).foregroundColor(.blue).fontWeight(.medium) } }
            }
            .navigationTitle("기록 수정")
            .toolbar {
                ToolbarItem(placement: .automatic) {
                    Button("저장") {
                        guard let activity = selectedActivity, duration > 0 else { return }
                        if let conflict = findConflict(start: startDateTime, end: endDateTime) {
                            conflictingRecord = conflict
                            showingOverlapAlert = true
                        } else {
                            record.activity = activity; record.date = startDateTime; record.duration = duration; dismiss()
                        }
                    }
                    .disabled(selectedActivity == nil || duration <= 0)
                }
                ToolbarItem(placement: .cancellationAction) { Button("취소") { dismiss() } }
            }
            .alert("시간 겹침", isPresented: $showingOverlapAlert) {
                Button("확인", role: .cancel) { conflictingRecord = nil }
            } message: { Text(overlapAlertMessage) }
        }
    }

    func timeString(from time: TimeInterval) -> String {
        let s = Int(time); let h = s / 3600; let m = (s % 3600) / 60
        if h > 0 { return "\(h)시간 \(m)분" }; return "\(m)분"
    }
}

// MARK: - 반복 기록 추가
struct RecurringRecordView: View {
    @Environment(\.modelContext) var modelContext
    @Environment(\.dismiss) var dismiss
    @Query(sort: \Project.sortOrder) var projects: [Project]
    @Query(sort: \TimeRecord.date) var allRecords: [TimeRecord]

    @State private var step = 1
    @State private var selectedProject: Project? = nil
    @State private var selectedActivity: Activity? = nil
    @State private var startTime: Date = Calendar.current.date(bySettingHour: 9, minute: 0, second: 0, of: Date()) ?? Date()
    @State private var endTime: Date = Calendar.current.date(bySettingHour: 18, minute: 0, second: 0, of: Date()) ?? Date()
    @State private var selectedWeekdays: Set<Int> = [2, 3, 4, 5, 6]
    @State private var rangeStart: Date = Calendar.current.startOfDay(for: Date())
    @State private var rangeEnd: Date = Calendar.current.date(byAdding: .weekOfYear, value: 4, to: Date()) ?? Date()

    let weekdayLabels: [(label: String, weekday: Int)] = [
        ("월", 2), ("화", 3), ("수", 4), ("목", 5), ("금", 6), ("토", 7), ("일", 1)
    ]

    var candidateDates: [Date] {
        var dates: [Date] = []; let calendar = Calendar.current
        var current = calendar.startOfDay(for: rangeStart)
        let end = calendar.startOfDay(for: rangeEnd)
        while current <= end {
            if selectedWeekdays.contains(calendar.component(.weekday, from: current)) { dates.append(current) }
            current = calendar.date(byAdding: .day, value: 1, to: current)!
        }
        return dates
    }

    var previewItems: [(date: Date, startDT: Date, endDT: Date, hasOverlap: Bool)] {
        let cal = Calendar.current
        let sh = cal.component(.hour, from: startTime); let sm = cal.component(.minute, from: startTime)
        let eh = cal.component(.hour, from: endTime);   let em = cal.component(.minute, from: endTime)
        return candidateDates.map { date in
            let startDT = cal.date(bySettingHour: sh, minute: sm, second: 0, of: date)!
            var endDT = cal.date(bySettingHour: eh, minute: em, second: 0, of: date)!
            if endDT <= startDT { endDT = cal.date(byAdding: .day, value: 1, to: endDT)! }
            return (date, startDT, endDT, hasOverlapOnDay(start: startDT, end: endDT))
        }
    }

    var nonOverlappingCount: Int { previewItems.filter { !$0.hasOverlap }.count }

    func hasOverlapOnDay(start: Date, end: Date) -> Bool {
        allRecords.contains { let recEnd = $0.date.addingTimeInterval($0.duration); return start < recEnd && end > $0.date }
    }

    var body: some View {
        NavigationView {
            Group {
                if step == 1 { projectSelectionView }
                else if step == 2 { activitySelectionView }
                else { settingsView }
            }
        }
    }

    var projectSelectionView: some View {
        List {
            ForEach(projects) { project in
                if !project.sortedActivities.isEmpty {
                    HStack {
                        Image(systemName: project.icon).font(.title3).frame(width: 28, height: 28)
                        Text(project.name).font(.body); Spacer()
                        Text("\(project.sortedActivities.count)개").font(.caption).foregroundColor(.gray)
                        Image(systemName: "chevron.right").foregroundColor(.gray).font(.caption)
                    }
                    .contentShape(Rectangle()).onTapGesture { selectedProject = project; step = 2 }
                }
            }
        }
        .navigationTitle("반복 기록")
        .toolbar { ToolbarItem(placement: .cancellationAction) { Button("취소") { dismiss() } } }
    }

    var activitySelectionView: some View {
        List {
            Section(header: Text("프로젝트")) {
                HStack {
                    Image(systemName: selectedProject?.icon ?? "pin").foregroundColor(.blue)
                    Text(selectedProject?.name ?? "").foregroundColor(.blue)
                }
                .contentShape(Rectangle()).onTapGesture { step = 1 }
            }
            Section(header: Text("활동")) {
                if let project = selectedProject {
                    ForEach(project.sortedActivities) { activity in
                        HStack {
                            Text(activity.name); Spacer()
                            if selectedActivity?.id == activity.id { Image(systemName: "checkmark").foregroundColor(.blue) }
                        }
                        .contentShape(Rectangle()).onTapGesture { selectedActivity = activity }
                    }
                }
            }
        }
        .navigationTitle("활동 선택")
        .toolbar {
            ToolbarItem(placement: .cancellationAction) { Button("취소") { dismiss() } }
            ToolbarItem(placement: .automatic) { Button("다음") { step = 3 }.disabled(selectedActivity == nil) }
        }
    }

    var settingsView: some View {
        let items = previewItems
        let nonOverlap = items.filter { !$0.hasOverlap }.count
        return Form {
            Section(header: Text("활동")) {
                HStack {
                    Image(systemName: selectedProject?.icon ?? "pin").foregroundColor(.gray)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(selectedProject?.name ?? "").font(.caption).foregroundColor(.gray)
                        Text(selectedActivity?.name ?? "").fontWeight(.medium)
                    }
                }
                .contentShape(Rectangle()).onTapGesture { step = 2 }
            }
            Section(header: Text("시간")) {
                DatePicker("시작", selection: $startTime, displayedComponents: .hourAndMinute)
                DatePicker("종료", selection: $endTime, displayedComponents: .hourAndMinute)
                HStack {
                    Text("소요 시간"); Spacer()
                    let raw = endTime.timeIntervalSince(startTime)
                    Text(timeString(from: raw > 0 ? raw : raw + 86400)).foregroundColor(.blue).fontWeight(.medium)
                }
            }
            Section(header: Text("반복 요일")) {
                HStack(spacing: 6) {
                    ForEach(weekdayLabels, id: \.weekday) { item in
                        let selected = selectedWeekdays.contains(item.weekday)
                        Text(item.label).font(.subheadline).fontWeight(selected ? .bold : .regular)
                            .frame(width: 36, height: 36)
                            .background(selected ? Color.blue : Color.gray.opacity(0.15))
                            .foregroundColor(selected ? .white : .primary).cornerRadius(18)
                            .onTapGesture {
                                if selectedWeekdays.contains(item.weekday) {
                                    if selectedWeekdays.count > 1 { selectedWeekdays.remove(item.weekday) }
                                } else { selectedWeekdays.insert(item.weekday) }
                            }
                    }
                }.padding(.vertical, 4)
            }
            Section(header: Text("기간")) {
                DatePicker("시작일", selection: $rangeStart, displayedComponents: .date)
                DatePicker("종료일", selection: $rangeEnd, in: rangeStart..., displayedComponents: .date)
            }
            Section(header: Text("미리보기 — \(candidateDates.count)일 중 \(nonOverlap)개 추가 가능")) {
                if items.isEmpty {
                    Text("해당 조건에 맞는 날짜가 없어요").foregroundColor(.gray).font(.caption)
                } else {
                    ForEach(items.prefix(10), id: \.date) { item in
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(dateLabel(for: item.date)).font(.caption).foregroundColor(.gray)
                                Text(timeRangeLabel(start: item.startDT, end: item.endDT)).font(.caption2)
                            }
                            Spacer()
                            if item.hasOverlap {
                                Label("겹침", systemImage: "exclamationmark.triangle.fill").font(.caption2).foregroundColor(.orange)
                            } else {
                                Image(systemName: "checkmark.circle.fill").foregroundColor(.green).font(.caption)
                            }
                        }
                    }
                    if items.count > 10 { Text("외 \(items.count - 10)개 더").font(.caption).foregroundColor(.gray) }
                }
            }
        }
        .navigationTitle("반복 설정")
        .toolbar {
            ToolbarItem(placement: .cancellationAction) { Button("취소") { dismiss() } }
            ToolbarItem(placement: .automatic) {
                Button("추가 (\(nonOverlap))") { addRecurringRecords() }
                    .fontWeight(.bold).disabled(nonOverlap == 0 || startTime == endTime)
            }
        }
    }

    func addRecurringRecords() {
        guard let activity = selectedActivity else { return }
        for item in previewItems where !item.hasOverlap {
            let dur = item.endDT.timeIntervalSince(item.startDT)
            if dur > 0 { modelContext.insert(TimeRecord(activity: activity, duration: dur, date: item.startDT)) }
        }
        dismiss()
    }

    func dateLabel(for date: Date) -> String {
        let f = DateFormatter(); f.dateFormat = "M월 d일 (E)"; f.locale = Locale(identifier: "ko_KR")
        return f.string(from: date)
    }

    func timeRangeLabel(start: Date, end: Date) -> String {
        let f = DateFormatter(); f.dateFormat = "HH:mm"
        return "\(f.string(from: start)) ~ \(f.string(from: end))"
    }

    func timeString(from time: TimeInterval) -> String {
        let s = Int(time); let h = s / 3600; let m = (s % 3600) / 60
        if h > 0 { return "\(h)시간 \(m)분" }; return "\(m)분"
    }
}

#Preview {
    let config = ModelConfiguration(isStoredInMemoryOnly: true)
    let container = try! ModelContainer(for: Schema([Project.self, Activity.self, TimeRecord.self]), configurations: [config])
    return DayTimelineView()
        .modelContainer(container)
}
