import SwiftUI
import SwiftData

struct DayTimelineView: View {
    @Environment(\.modelContext) var modelContext
    @Query(sort: \Project.sortOrder) var projects: [Project]
    @Query(sort: \TimeRecord.date) var allRecords: [TimeRecord]
    @State private var selectedDate = Date()
    @State private var recordToEdit: TimeRecord? = nil
    @State private var recordToDelete: TimeRecord? = nil
    @State private var showingDeleteAlert = false
    @State private var showingAddRecord = false
    @State private var addRecordStartDate: Date = Date()
    @State private var showingRecurringRecord = false

    let hourHeight: CGFloat = 64
    let timeColumnWidth: CGFloat = 48

    var dayRecords: [TimeRecord] {
        let calendar = Calendar.current
        let start = calendar.startOfDay(for: selectedDate)
        let end = calendar.date(byAdding: .day, value: 1, to: start)!
        return allRecords.filter { $0.date >= start && $0.date < end }.sorted { $0.date < $1.date }
    }

    // 자정 걸치는 기록도 해당 날짜 범위로 잘라서 표시하기 위한 세그먼트
    var daySegments: [(record: TimeRecord, displayDate: Date, displayDuration: TimeInterval)] {
        let cal = Calendar.current
        let dayStart = cal.startOfDay(for: selectedDate)
        let dayEnd = cal.date(byAdding: .day, value: 1, to: dayStart)!
        return allRecords.compactMap { record in
            let recStart = record.date
            let recEnd = recStart.addingTimeInterval(record.duration)
            guard recStart < dayEnd && recEnd > dayStart else { return nil }
            let displayStart = max(recStart, dayStart)
            let displayEnd = min(recEnd, dayEnd)
            let dur = displayEnd.timeIntervalSince(displayStart)
            guard dur > 0 else { return nil }
            return (record, displayStart, dur)
        }.sorted { $0.displayDate < $1.displayDate }
    }

    var totalTime: TimeInterval { daySegments.reduce(0) { $0 + $1.displayDuration } }

    var recentDates: [Date] {
        let cal = Calendar.current
        let today = cal.startOfDay(for: Date())
        return (-29...7).compactMap { cal.date(byAdding: .day, value: $0, to: today) }
    }

    var body: some View {
        NavigationView {
            VStack(spacing: 0) {
                datePicker
                Divider()
                summaryBar
                Divider()
                timelineScrollView
            }
            .navigationTitle("타임라인")
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button(action: { showingRecurringRecord = true }) {
                        Image(systemName: "repeat.circle")
                    }
                }
            }
            .sheet(item: $recordToEdit) { record in EditRecordView(record: record) }
            .sheet(isPresented: $showingAddRecord) { AddRecordView(startDate: addRecordStartDate, selectedDate: selectedDate) }
            .sheet(isPresented: $showingRecurringRecord) { RecurringRecordView() }
            .alert("기록 삭제", isPresented: $showingDeleteAlert) {
                Button("삭제", role: .destructive) { if let record = recordToDelete { modelContext.delete(record) } }
                Button("취소", role: .cancel) {}
            } message: { Text("이 기록을 삭제할까요?") }
        }
    }

    var datePicker: some View {
        ScrollViewReader { proxy in
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) {
                    ForEach(recentDates, id: \.self) { date in
                        let isSelected = Calendar.current.isDate(date, inSameDayAs: selectedDate)
                        let isToday = Calendar.current.isDateInToday(date)
                        VStack(spacing: 2) {
                            Text(dayOfWeek(from: date)).font(.caption2).foregroundColor(isSelected ? .white : .gray)
                            Text(dayNumber(from: date)).font(.system(size: 15, weight: isSelected ? .bold : .regular))
                                .foregroundColor(isSelected ? .white : isToday ? .blue : .primary)
                        }
                        .frame(width: 38, height: 52)
                        .background(isSelected ? Color.blue : (isToday ? Color.blue.opacity(0.1) : Color.clear))
                        .cornerRadius(10).id(date)
                        .onTapGesture { withAnimation { selectedDate = date } }
                    }
                }
                .padding(.horizontal, 12)
            }
            .padding(.vertical, 8)
            .onAppear {
                let today = Calendar.current.startOfDay(for: Date())
                proxy.scrollTo(today, anchor: .center)
            }
            .onChange(of: selectedDate) { _, newDate in withAnimation { proxy.scrollTo(newDate, anchor: .center) } }
        }
    }

    var summaryBar: some View {
        HStack {
            Text("총 \(timeString(from: totalTime))").font(.subheadline).fontWeight(.medium)
            Spacer()
            Text("길게 눌러 기록 추가").font(.caption2).foregroundColor(.gray)
            Text("\(dayRecords.count)개 기록").font(.caption).foregroundColor(.gray)
        }
        .padding(.horizontal, 16).padding(.vertical, 8).background(Color.blue.opacity(0.05))
    }

    var timelineScrollView: some View {
        ScrollViewReader { proxy in
            ScrollView {
                ZStack(alignment: .topLeading) {
                    hourGridWithGesture
                    recordBlocks
                }
                .frame(height: hourHeight * 24).padding(.bottom, 20)
            }
            .onAppear {
                let scrollHour = max(Calendar.current.component(.hour, from: Date()) - 2, 0)
                proxy.scrollTo(scrollHour, anchor: .top)
            }
        }
    }

    var hourGridWithGesture: some View {
        VStack(spacing: 0) {
            ForEach(0..<24, id: \.self) { hour in
                HStack(alignment: .top, spacing: 0) {
                    Text(String(format: "%02d:00", hour)).font(.caption2).foregroundColor(.gray)
                        .frame(width: timeColumnWidth, alignment: .trailing).padding(.trailing, 8).offset(y: -6)
                    ZStack {
                        Rectangle().fill(Color.gray.opacity(0.15)).frame(height: 0.5)
                            .frame(maxWidth: .infinity).offset(y: -hourHeight / 2)
                        Color.clear.contentShape(Rectangle()).frame(maxWidth: .infinity, maxHeight: .infinity)
                            .onLongPressGesture(minimumDuration: 0.5) {
                                var components = Calendar.current.dateComponents([.year, .month, .day], from: selectedDate)
                                components.hour = hour; components.minute = 0
                                addRecordStartDate = Calendar.current.date(from: components) ?? Date()
                                showingAddRecord = true
                            }
                    }
                }
                .frame(height: hourHeight).id(hour)
            }
        }
    }

    var recordBlocks: some View {
        GeometryReader { geo in
            let blockWidth = geo.size.width - timeColumnWidth - 16
            let segments = daySegments
            let columns = layoutColumns(for: segments)
            ForEach(Array(segments.enumerated()), id: \.element.record.id) { index, segment in
                let record = segment.record
                let activity = record.activity
                let project = activity?.project
                let yOffset = yPosition(for: segment.displayDate)
                let maxHeight = hourHeight * 24 - yOffset
                let blockHeight = max(min(heightForDuration(segment.displayDuration), maxHeight), 28)
                let columnInfo = columns[index]
                let colWidth = (blockWidth - 8) / CGFloat(columnInfo.total)
                let xOffset = timeColumnWidth + 8 + colWidth * CGFloat(columnInfo.column)

                ZStack(alignment: .topLeading) {
                    RoundedRectangle(cornerRadius: 6)
                        .fill(projectColor(for: project).opacity(0.2))
                        .overlay(RoundedRectangle(cornerRadius: 6).stroke(projectColor(for: project), lineWidth: 1.5))
                    VStack(alignment: .leading, spacing: 2) {
                        HStack(spacing: 4) {
                            Text(project?.icon ?? "📌").font(.system(size: 10))
                            Text(activity?.name ?? "알 수 없음").font(.caption).fontWeight(.medium).lineLimit(1)
                                .foregroundColor(projectColor(for: project))
                        }
                        if blockHeight > 44 {
                            Text(timeString(from: segment.displayDuration)).font(.caption2).foregroundColor(.gray)
                        }
                    }
                    .padding(.horizontal, 6).padding(.vertical, 4)
                }
                .frame(width: colWidth - 2, height: blockHeight)
                .offset(x: xOffset, y: yOffset)
                .onTapGesture { recordToEdit = record }
                .contextMenu {
                    Button(action: { recordToEdit = record }) { Label("수정", systemImage: "pencil") }
                    Button(role: .destructive, action: { recordToDelete = record; showingDeleteAlert = true }) {
                        Label("삭제", systemImage: "trash")
                    }
                }
            }
        }
    }

    func layoutColumns(for segments: [(record: TimeRecord, displayDate: Date, displayDuration: TimeInterval)]) -> [(column: Int, total: Int)] {
        var result = Array(repeating: (column: 0, total: 1), count: segments.count)
        for i in 0..<segments.count {
            var overlapping = [i]
            let startI = segments[i].displayDate
            let endI = startI.addingTimeInterval(segments[i].displayDuration)
            for j in 0..<segments.count where i != j {
                let startJ = segments[j].displayDate
                let endJ = startJ.addingTimeInterval(segments[j].displayDuration)
                if startI < endJ && endI > startJ {
                    overlapping.append(j)
                }
            }
            let total = overlapping.count
            for (col, idx) in overlapping.sorted().enumerated() {
                result[idx] = (column: col, total: total)
            }
        }
        return result
    }

    func yPosition(for date: Date) -> CGFloat {
        let c = Calendar.current
        return CGFloat(c.component(.hour, from: date)) * hourHeight + CGFloat(c.component(.minute, from: date)) / 60.0 * hourHeight
    }

    func heightForDuration(_ duration: TimeInterval) -> CGFloat {
        CGFloat(duration / 3600.0) * hourHeight
    }

    func projectColor(for project: Project?) -> Color {
        let palette: [Color] = [.purple, .blue, .pink, .orange, .green, .teal, .red, .cyan, .mint, .indigo]
        guard let p = project,
              let index = projects.firstIndex(where: { $0.id == p.id }) else { return .gray }
        return palette[index % palette.count]
    }

    func dayOfWeek(from date: Date) -> String {
        let f = DateFormatter(); f.dateFormat = "E"; f.locale = Locale(identifier: "ko_KR")
        return f.string(from: date)
    }

    func dayNumber(from date: Date) -> String {
        let f = DateFormatter(); f.dateFormat = "d"; return f.string(from: date)
    }

    func timeString(from time: TimeInterval) -> String {
        let totalSeconds = Int(time)
        let hours = totalSeconds / 3600
        let minutes = (totalSeconds % 3600) / 60
        if hours > 0 { return "\(hours)시간 \(minutes)분" }
        return "\(minutes)분"
    }
}

// MARK: - 기록 추가
struct AddRecordView: View {
    @Environment(\.modelContext) var modelContext
    @Environment(\.dismiss) var dismiss
    @Query(sort: \Project.sortOrder) var projects: [Project]
    @Query(sort: \TimeRecord.date) var allRecords: [TimeRecord]
    @State private var recordDate: Date
    @State private var startTime: Date
    @State private var endTime: Date
    @State private var selectedProject: Project? = nil
    @State private var selectedActivity: Activity? = nil
    @State private var step = 1
    @State private var showingOverlapAlert = false

    init(startDate: Date, selectedDate: Date) {
        _recordDate = State(initialValue: Calendar.current.startOfDay(for: selectedDate))
        _startTime = State(initialValue: startDate)
        _endTime = State(initialValue: startDate.addingTimeInterval(3600))
    }

    var startDateTime: Date { combineDateAndTime(date: recordDate, time: startTime) }
    var endDateTime: Date {
        let result = combineDateAndTime(date: recordDate, time: endTime)
        return result <= startDateTime ? Calendar.current.date(byAdding: .day, value: 1, to: result)! : result
    }

    func combineDateAndTime(date: Date, time: Date) -> Date {
        let cal = Calendar.current
        var dc = cal.dateComponents([.year, .month, .day], from: date)
        let tc = cal.dateComponents([.hour, .minute], from: time)
        dc.hour = tc.hour; dc.minute = tc.minute; dc.second = 0
        return cal.date(from: dc) ?? time
    }

    var dayRecords: [TimeRecord] {
        let start = Calendar.current.startOfDay(for: recordDate)
        let end = Calendar.current.date(byAdding: .day, value: 1, to: start)!
        return allRecords.filter { $0.date >= start && $0.date < end }
    }

    func hasOverlap(start: Date, end: Date) -> Bool {
        allRecords.contains {
            let recEnd = $0.date.addingTimeInterval($0.duration)
            return start < recEnd && end > $0.date
        }
    }

    var body: some View {
        NavigationView {
            if step == 1 {
                projectSelectionView
            } else {
                activityAndTimeView
            }
        }
    }

    var projectSelectionView: some View {
        List {
            ForEach(projects) { project in
                let count = project.activities.count
                if count > 0 {
                    HStack {
                        Text(project.icon).font(.title2)
                        Text(project.name).font(.body)
                        Spacer()
                        Text("\(count)개").font(.caption).foregroundColor(.gray)
                        Image(systemName: "chevron.right").foregroundColor(.gray).font(.caption)
                    }
                    .contentShape(Rectangle())
                    .onTapGesture {
                        selectedProject = project
                        step = 2
                    }
                }
            }
        }
        .navigationTitle("프로젝트 선택")
        .toolbar {
            ToolbarItem(placement: .cancellationAction) { Button("취소") { dismiss() } }
        }
    }

    var activityAndTimeView: some View {
        Form {
            Section(header: Text("프로젝트")) {
                HStack {
                    Text(selectedProject?.icon ?? "📌")
                    Text(selectedProject?.name ?? "").foregroundColor(.blue)
                }
                .contentShape(Rectangle())
                .onTapGesture { step = 1 }
            }
            Section(header: Text("활동 선택")) {
                if let project = selectedProject {
                    ForEach(project.sortedActivities) { activity in
                        HStack {
                            Text(activity.name)
                            Spacer()
                            if selectedActivity?.id == activity.id {
                                Image(systemName: "checkmark").foregroundColor(.blue)
                            }
                        }
                        .contentShape(Rectangle())
                        .onTapGesture { selectedActivity = activity }
                    }
                }
            }
            Section(header: Text("날짜")) {
                DatePicker("날짜", selection: $recordDate, displayedComponents: .date)
                    .labelsHidden()
            }
            Section(header: Text("시작 시간")) {
                DatePicker("시작", selection: $startTime, displayedComponents: .hourAndMinute).labelsHidden()
            }
            Section(header: Text("종료 시간")) {
                DatePicker("종료", selection: $endTime, displayedComponents: .hourAndMinute).labelsHidden()
            }
            Section {
                HStack {
                    Text("총 시간")
                    Spacer()
                    let duration = max(endDateTime.timeIntervalSince(startDateTime), 0)
                    Text(timeString(from: duration)).foregroundColor(.blue).fontWeight(.medium)
                }
            }
        }
        .navigationTitle("기록 추가")
        .toolbar {
            ToolbarItem(placement: .automatic) {
                Button("추가") {
                    guard let activity = selectedActivity else { return }
                    let start = startDateTime
                    let end = endDateTime
                    let duration = max(end.timeIntervalSince(start), 0)
                    guard duration > 0 else { return }
                    if hasOverlap(start: start, end: end) {
                        showingOverlapAlert = true
                    } else {
                        modelContext.insert(TimeRecord(activity: activity, duration: duration, date: start))
                        dismiss()
                    }
                }
                .disabled(selectedActivity == nil || endDateTime <= startDateTime)
            }
            ToolbarItem(placement: .cancellationAction) { Button("취소") { dismiss() } }
        }
        .alert("시간 겹침", isPresented: $showingOverlapAlert) {
            Button("확인", role: .cancel) {}
        } message: {
            Text("해당 시간대에 이미 기록이 있어요.\n다른 시간을 선택해주세요.")
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

// MARK: - 기록 수정
struct EditRecordView: View {
    @Environment(\.dismiss) var dismiss
    @Query(sort: \TimeRecord.date) var allRecords: [TimeRecord]
    let record: TimeRecord
    @State private var startDate: Date
    @State private var endDate: Date
    @State private var showingOverlapAlert = false

    init(record: TimeRecord) {
        self.record = record
        _startDate = State(initialValue: record.date)
        _endDate = State(initialValue: record.date.addingTimeInterval(record.duration))
    }

    func hasOverlap(start: Date, end: Date) -> Bool {
        let dayStart = Calendar.current.startOfDay(for: record.date)
        let dayEnd = Calendar.current.date(byAdding: .day, value: 1, to: dayStart)!
        let dayRecords = allRecords.filter { $0.date >= dayStart && $0.date < dayEnd && $0.id != record.id }
        return dayRecords.contains {
            let recEnd = $0.date.addingTimeInterval($0.duration)
            return start < recEnd && end > $0.date
        }
    }

    var body: some View {
        NavigationView {
            Form {
                Section(header: Text("활동")) {
                    HStack {
                        Text(record.activity?.project?.icon ?? "📌")
                        Text(record.activity?.name ?? "알 수 없음")
                    }
                }
                Section(header: Text("시작 시간")) {
                    DatePicker("시작", selection: $startDate, displayedComponents: [.hourAndMinute]).labelsHidden()
                }
                Section(header: Text("종료 시간")) {
                    DatePicker("종료", selection: $endDate, displayedComponents: [.hourAndMinute]).labelsHidden()
                }
                Section {
                    HStack {
                        Text("총 시간")
                        Spacer()
                        let duration = max(endDate.timeIntervalSince(startDate), 0)
                        Text(timeString(from: duration)).foregroundColor(.blue).fontWeight(.medium)
                    }
                }
            }
            .navigationTitle("기록 수정")
            .toolbar {
                ToolbarItem(placement: .automatic) {
                    Button("저장") {
                        let duration = max(endDate.timeIntervalSince(startDate), 0)
                        guard duration > 0 else { return }
                        if hasOverlap(start: startDate, end: endDate) {
                            showingOverlapAlert = true
                        } else {
                            record.date = startDate
                            record.duration = duration
                            dismiss()
                        }
                    }
                    .disabled(endDate <= startDate)
                }
                ToolbarItem(placement: .cancellationAction) { Button("취소") { dismiss() } }
            }
            .alert("시간 겹침", isPresented: $showingOverlapAlert) {
                Button("확인", role: .cancel) {}
            } message: {
                Text("해당 시간대에 이미 기록이 있어요.\n다른 시간을 선택해주세요.")
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
        var dates: [Date] = []
        let calendar = Calendar.current
        var current = calendar.startOfDay(for: rangeStart)
        let end = calendar.startOfDay(for: rangeEnd)
        while current <= end {
            if selectedWeekdays.contains(calendar.component(.weekday, from: current)) {
                dates.append(current)
            }
            current = calendar.date(byAdding: .day, value: 1, to: current)!
        }
        return dates
    }

    var previewItems: [(date: Date, startDT: Date, endDT: Date, hasOverlap: Bool)] {
        let calendar = Calendar.current
        let sh = calendar.component(.hour, from: startTime)
        let sm = calendar.component(.minute, from: startTime)
        let eh = calendar.component(.hour, from: endTime)
        let em = calendar.component(.minute, from: endTime)
        return candidateDates.map { date in
            let startDT = calendar.date(bySettingHour: sh, minute: sm, second: 0, of: date)!
            var endDT = calendar.date(bySettingHour: eh, minute: em, second: 0, of: date)!
            if endDT <= startDT { endDT = calendar.date(byAdding: .day, value: 1, to: endDT)! }
            let overlap = hasOverlapOnDay(date: date, start: startDT, end: endDT)
            return (date, startDT, endDT, overlap)
        }
    }

    var nonOverlappingCount: Int { previewItems.filter { !$0.hasOverlap }.count }

    func hasOverlapOnDay(date: Date, start: Date, end: Date) -> Bool {
        allRecords.contains {
            let recEnd = $0.date.addingTimeInterval($0.duration)
            return start < recEnd && end > $0.date
        }
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
                        Text(project.icon).font(.title2)
                        Text(project.name).font(.body)
                        Spacer()
                        Text("\(project.sortedActivities.count)개").font(.caption).foregroundColor(.gray)
                        Image(systemName: "chevron.right").foregroundColor(.gray).font(.caption)
                    }
                    .contentShape(Rectangle())
                    .onTapGesture { selectedProject = project; step = 2 }
                }
            }
        }
        .navigationTitle("반복 기록")
        .toolbar {
            ToolbarItem(placement: .cancellationAction) { Button("취소") { dismiss() } }
        }
    }

    var activitySelectionView: some View {
        List {
            Section(header: Text("프로젝트")) {
                HStack {
                    Text(selectedProject?.icon ?? "📌")
                    Text(selectedProject?.name ?? "").foregroundColor(.blue)
                }
                .contentShape(Rectangle())
                .onTapGesture { step = 1 }
            }
            Section(header: Text("활동")) {
                if let project = selectedProject {
                    ForEach(project.sortedActivities) { activity in
                        HStack {
                            Text(activity.name)
                            Spacer()
                            if selectedActivity?.id == activity.id {
                                Image(systemName: "checkmark").foregroundColor(.blue)
                            }
                        }
                        .contentShape(Rectangle())
                        .onTapGesture { selectedActivity = activity }
                    }
                }
            }
        }
        .navigationTitle("활동 선택")
        .toolbar {
            ToolbarItem(placement: .cancellationAction) { Button("취소") { dismiss() } }
            ToolbarItem(placement: .automatic) {
                Button("다음") { step = 3 }.disabled(selectedActivity == nil)
            }
        }
    }

    var settingsView: some View {
        let items = previewItems
        let nonOverlap = items.filter { !$0.hasOverlap }.count
        return Form {
            Section(header: Text("활동")) {
                HStack {
                    Text(selectedProject?.icon ?? "📌")
                    VStack(alignment: .leading, spacing: 2) {
                        Text(selectedProject?.name ?? "").font(.caption).foregroundColor(.gray)
                        Text(selectedActivity?.name ?? "").fontWeight(.medium)
                    }
                }
                .contentShape(Rectangle())
                .onTapGesture { step = 2 }
            }
            Section(header: Text("시간")) {
                DatePicker("시작", selection: $startTime, displayedComponents: .hourAndMinute)
                DatePicker("종료", selection: $endTime, displayedComponents: .hourAndMinute)
                HStack {
                    Text("소요 시간")
                    Spacer()
                    let raw = endTime.timeIntervalSince(startTime)
                    let duration = raw > 0 ? raw : raw + 86400
                    Text(timeString(from: duration)).foregroundColor(.blue).fontWeight(.medium)
                }
            }
            Section(header: Text("반복 요일")) {
                HStack(spacing: 6) {
                    ForEach(weekdayLabels, id: \.weekday) { item in
                        let selected = selectedWeekdays.contains(item.weekday)
                        Text(item.label)
                            .font(.subheadline).fontWeight(selected ? .bold : .regular)
                            .frame(width: 36, height: 36)
                            .background(selected ? Color.blue : Color.gray.opacity(0.15))
                            .foregroundColor(selected ? .white : .primary)
                            .cornerRadius(18)
                            .onTapGesture {
                                if selectedWeekdays.contains(item.weekday) {
                                    if selectedWeekdays.count > 1 { selectedWeekdays.remove(item.weekday) }
                                } else {
                                    selectedWeekdays.insert(item.weekday)
                                }
                            }
                    }
                }
                .padding(.vertical, 4)
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
                                Label("겹침", systemImage: "exclamationmark.triangle.fill")
                                    .font(.caption2).foregroundColor(.orange)
                            } else {
                                Image(systemName: "checkmark.circle.fill").foregroundColor(.green).font(.caption)
                            }
                        }
                    }
                    if items.count > 10 {
                        Text("외 \(items.count - 10)개 더").font(.caption).foregroundColor(.gray)
                    }
                }
            }
        }
        .navigationTitle("반복 설정")
        .toolbar {
            ToolbarItem(placement: .cancellationAction) { Button("취소") { dismiss() } }
            ToolbarItem(placement: .automatic) {
                Button("추가 (\(nonOverlap))") { addRecurringRecords() }
                    .fontWeight(.bold)
                    .disabled(nonOverlap == 0 || startTime == endTime)
            }
        }
    }

    func addRecurringRecords() {
        guard let activity = selectedActivity else { return }
        for item in previewItems where !item.hasOverlap {
            let duration = item.endDT.timeIntervalSince(item.startDT)
            if duration > 0 {
                modelContext.insert(TimeRecord(activity: activity, duration: duration, date: item.startDT))
            }
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
        let totalSeconds = Int(time)
        let hours = totalSeconds / 3600
        let minutes = (totalSeconds % 3600) / 60
        if hours > 0 { return "\(hours)시간 \(minutes)분" }
        return "\(minutes)분"
    }
}

#Preview {
    DayTimelineView()
        .modelContainer(sharedModelContainer)
}
