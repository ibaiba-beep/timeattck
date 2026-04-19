import SwiftUI

struct DayTimelineView: View {
    @EnvironmentObject var dataModel: DataModel
    @State private var selectedDate = Date()
    @State private var recordToEdit: TimeRecord? = nil
    @State private var recordToDelete: TimeRecord? = nil
    @State private var showingDeleteAlert = false
    @State private var showingAddRecord = false
    @State private var addRecordStartDate: Date = Date()

    let hourHeight: CGFloat = 64
    let timeColumnWidth: CGFloat = 48

    var dayRecords: [TimeRecord] {
        let calendar = Calendar.current
        let start = calendar.startOfDay(for: selectedDate)
        let end = calendar.date(byAdding: .day, value: 1, to: start)!
        return dataModel.records.filter { $0.date >= start && $0.date < end }.sorted { $0.date < $1.date }
    }

    var totalTime: TimeInterval { dayRecords.reduce(0) { $0 + $1.duration } }

    var recentDates: [Date] {
        (0..<30).compactMap { Calendar.current.date(byAdding: .day, value: -$0, to: Date()) }.reversed()
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
            .sheet(item: $recordToEdit) { record in EditRecordView(record: record) }
            .sheet(isPresented: $showingAddRecord) { AddRecordView(startDate: addRecordStartDate, selectedDate: selectedDate) }
            .alert("기록 삭제", isPresented: $showingDeleteAlert) {
                Button("삭제", role: .destructive) { if let record = recordToDelete { dataModel.deleteRecord(record) } }
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
            .onAppear { proxy.scrollTo(recentDates.last, anchor: .trailing) }
            .onChange(of: selectedDate) {_, newDate in withAnimation { proxy.scrollTo(newDate, anchor: .center) } }
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
            ForEach(dayRecords) { record in
                let project = dataModel.projects.first(where: { $0.id == record.projectId })
                let category = project.flatMap { dataModel.category(for: $0) }
                let yOffset = yPosition(for: record.date)
                let blockHeight = max(heightForDuration(record.duration), 28)
                ZStack(alignment: .topLeading) {
                    RoundedRectangle(cornerRadius: 6)
                        .fill(categoryColor(category?.name).opacity(0.2))
                        .overlay(RoundedRectangle(cornerRadius: 6).stroke(categoryColor(category?.name), lineWidth: 1.5))
                    VStack(alignment: .leading, spacing: 2) {
                        HStack(spacing: 4) {
                            Text(category?.icon ?? "📌").font(.system(size: 10))
                            Text(project?.name ?? "알 수 없음").font(.caption).fontWeight(.medium).lineLimit(1)
                                .foregroundColor(categoryColor(category?.name))
                        }
                        if blockHeight > 44 {
                            Text(timeString(from: record.duration)).font(.caption2).foregroundColor(.gray)
                        }
                    }
                    .padding(.horizontal, 6).padding(.vertical, 4)
                }
                .frame(width: blockWidth - 8, height: blockHeight)
                .offset(x: timeColumnWidth + 8, y: yOffset)
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

    func yPosition(for date: Date) -> CGFloat {
        let c = Calendar.current
        return CGFloat(c.component(.hour, from: date)) * hourHeight + CGFloat(c.component(.minute, from: date)) / 60.0 * hourHeight
    }

    func heightForDuration(_ duration: TimeInterval) -> CGFloat { CGFloat(duration / 3600.0) * hourHeight }

    func categoryColor(_ categoryName: String?) -> Color {
        switch categoryName {
        case "게임": return .purple
        case "공부": return .blue
        case "SNS": return .pink
        case "엔터테인먼트": return .orange
        case "건강/운동": return .green
        case "업무": return .teal
        default: return .gray
        }
    }

    func dayOfWeek(from date: Date) -> String {
        let f = DateFormatter(); f.dateFormat = "E"; f.locale = Locale(identifier: "ko_KR")
        return f.string(from: date)
    }

    func dayNumber(from date: Date) -> String {
        let f = DateFormatter(); f.dateFormat = "d"; return f.string(from: date)
    }

    func timeString(from time: TimeInterval) -> String {
        String(format: "%02d:%02d:%02d", Int(time) / 3600, Int(time) / 60 % 60, Int(time) % 60)
    }
}

struct AddRecordView: View {
    @EnvironmentObject var dataModel: DataModel
    @Environment(\.dismiss) var dismiss
    @State var startDate: Date
    @State private var endDate: Date
    @State private var selectedProject: Project? = nil
    let selectedDate: Date

    init(startDate: Date, selectedDate: Date) {
        _startDate = State(initialValue: startDate)
        _endDate = State(initialValue: startDate.addingTimeInterval(3600))
        self.selectedDate = selectedDate
    }

    var body: some View {
        NavigationView {
            Form {
                Section(header: Text("앱 선택")) {
                    ForEach(dataModel.categories) { category in
                        let categoryProjects = dataModel.projects.filter { $0.categoryId == category.id }
                        if !categoryProjects.isEmpty {
                            Section(header: Text("\(category.icon) \(category.name)").font(.caption)) {
                                ForEach(categoryProjects) { project in
                                    HStack {
                                        Text(project.name)
                                        Spacer()
                                        if selectedProject?.id == project.id {
                                            Image(systemName: "checkmark").foregroundColor(.blue)
                                        }
                                    }
                                    .contentShape(Rectangle())
                                    .onTapGesture { selectedProject = project }
                                }
                            }
                        }
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
            .navigationTitle("기록 추가")
            .toolbar {
                ToolbarItem(placement: .automatic) {
                    Button("추가") {
                        guard let project = selectedProject else { return }
                        let duration = max(endDate.timeIntervalSince(startDate), 0)
                        if duration > 0 {
                            let newRecord = TimeRecord(projectId: project.id, duration: duration, date: startDate)
                            dataModel.records.append(newRecord)
                            dataModel.records.sort { $0.date < $1.date }
                            if let data = try? JSONEncoder().encode(dataModel.records) {
                                UserDefaults.standard.set(data, forKey: "records")
                            }
                        }
                        dismiss()
                    }
                    .disabled(selectedProject == nil || endDate <= startDate)
                }
                ToolbarItem(placement: .cancellationAction) { Button("취소") { dismiss() } }
            }
        }
    }

    func timeString(from time: TimeInterval) -> String {
        String(format: "%02d:%02d:%02d", Int(time) / 3600, Int(time) / 60 % 60, Int(time) % 60)
    }
}

struct EditRecordView: View {
    @EnvironmentObject var dataModel: DataModel
    @Environment(\.dismiss) var dismiss
    let record: TimeRecord
    @State private var startDate: Date
    @State private var endDate: Date

    init(record: TimeRecord) {
        self.record = record
        _startDate = State(initialValue: record.date)
        _endDate = State(initialValue: record.date.addingTimeInterval(record.duration))
    }

    var project: Project? { dataModel.projects.first(where: { $0.id == record.projectId }) }

    var body: some View {
        NavigationView {
            Form {
                Section(header: Text("앱")) {
                    HStack {
                        let category = project.flatMap { dataModel.category(for: $0) }
                        Text(category?.icon ?? "📌")
                        Text(project?.name ?? "알 수 없음")
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
                        dataModel.deleteRecord(record)
                        var newRecord = TimeRecord(projectId: record.projectId, duration: duration, date: startDate)
                        newRecord.id = record.id
                        dataModel.records.append(newRecord)
                        dataModel.records.sort { $0.date < $1.date }
                        if let data = try? JSONEncoder().encode(dataModel.records) {
                            UserDefaults.standard.set(data, forKey: "records")
                        }
                        dismiss()
                    }
                    .disabled(endDate <= startDate)
                }
                ToolbarItem(placement: .cancellationAction) { Button("취소") { dismiss() } }
            }
        }
    }

    func timeString(from time: TimeInterval) -> String {
        String(format: "%02d:%02d:%02d", Int(time) / 3600, Int(time) / 60 % 60, Int(time) % 60)
    }
}

#Preview {
    DayTimelineView().environmentObject(DataModel())
}
