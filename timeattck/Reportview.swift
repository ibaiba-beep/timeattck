import SwiftUI
import Charts

struct ReportView: View {
    @EnvironmentObject var dataModel: DataModel
    @State private var selectedPeriod: Int = 0
    @State private var recordToDelete: TimeRecord? = nil
    @State private var showingDeleteAlert = false
    @State private var selectedDate: String? = nil
    @State private var showingDayDetail = false

    var body: some View {
        NavigationView {
            ScrollView {
                VStack(spacing: 20) {
                    Picker("기간", selection: $selectedPeriod) {
                        Text("주별").tag(0)
                        Text("월별").tag(1)
                        Text("기록").tag(2)
                    }
                    .pickerStyle(.segmented)
                    .padding(.horizontal)

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
                if let date = selectedDate {
                    DayDetailView(dateString: date)
                }
            }
        }
    }

    var weeklyView: some View {
        let data = periodCategoryData(days: 7)
        let total = data.reduce(0.0) { $0 + $1.1 }
        return VStack(spacing: 20) {
            summaryCard(title: "이번 주 총 사용시간", hours: total)
            if !data.isEmpty {
                VStack(alignment: .leading, spacing: 12) {
                    Text("카테고리 비중").font(.headline).padding(.horizontal)
                    PieChartView(data: data, total: total)
                        .frame(width: 260, height: 260).frame(maxWidth: .infinity)
                    legendView(data: data, total: total)
                }
                VStack(alignment: .leading, spacing: 8) {
                    Text("일별 사용시간").font(.headline).padding(.horizontal)
                    Text("날짜를 탭하면 상세 내역을 볼 수 있어요")
                        .font(.caption).foregroundColor(.gray).padding(.horizontal)
                    let dailyData = dataModel.dailyTotals(days: 7)
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
                    .frame(height: 180).padding(.horizontal)
                }
            } else { emptyView }
        }
    }

    var monthlyView: some View {
        let data = periodCategoryData(days: 30)
        let total = data.reduce(0.0) { $0 + $1.1 }
        return VStack(spacing: 20) {
            summaryCard(title: "이번 달 총 사용시간", hours: total)
            if !data.isEmpty {
                VStack(alignment: .leading, spacing: 12) {
                    Text("카테고리 비중").font(.headline).padding(.horizontal)
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
                    Text("TOP 5 앱").font(.headline).padding(.horizontal)
                    ForEach(Array(topProjects(days: 30).enumerated()), id: \.1.0.id) { index, item in
                        HStack(spacing: 12) {
                            Text("\(index + 1)").font(.caption).fontWeight(.bold).foregroundColor(.white)
                                .frame(width: 24, height: 24).background(medalColor(index)).clipShape(Circle())
                            let category = dataModel.category(for: item.0)
                            Text("\(category?.icon ?? "📌") \(item.0.name)").font(.body).lineLimit(1)
                            Spacer()
                            Text(String(format: "%.1f시간", item.1)).font(.body).fontWeight(.medium).foregroundColor(.purple)
                        }
                        .padding().background(Color.gray.opacity(0.1)).cornerRadius(12).padding(.horizontal)
                    }
                }
            } else { emptyView }
        }
    }

    var recordListView: some View {
        VStack(spacing: 16) {
            ForEach(dataModel.projects) { project in
                let category = dataModel.category(for: project)
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text("\(category?.icon ?? "📌") \(project.name)").font(.headline)
                        Spacer()
                        Text("총 " + timeString(from: dataModel.totalTime(for: project)))
                            .font(.caption).foregroundColor(.blue).fontWeight(.medium)
                    }.padding(.horizontal)
                    let records = dataModel.records(for: project).sorted { $0.date > $1.date }.prefix(5)
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
        .alert("기록 삭제", isPresented: $showingDeleteAlert) {
            Button("삭제", role: .destructive) {
                if let record = recordToDelete { dataModel.deleteRecord(record) }
            }
            Button("취소", role: .cancel) {}
        } message: { Text("이 기록을 삭제할까요?") }
    }

    func summaryCard(title: String, hours: Double) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text(title).font(.caption).foregroundColor(.gray)
                Text(String(format: "%.0f시간 %.0f분", floor(hours), (hours - floor(hours)) * 60))
                    .font(.title2).fontWeight(.bold)
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
                    Text(String(format: "%.1f시간", item.1)).font(.caption).foregroundColor(.gray)
                    Text(String(format: "%.0f%%", total > 0 ? item.1 / total * 100 : 0))
                        .font(.caption).fontWeight(.medium).frame(width: 36, alignment: .trailing)
                }.padding(.horizontal)
            }
        }
    }

    var emptyView: some View {
        Text("아직 기록이 없어요").foregroundColor(.gray).frame(maxWidth: .infinity).padding()
    }

    func periodCategoryData(days: Int) -> [(String, Double, Color)] {
        let colors: [Color] = [.blue, .purple, .pink, .orange, .green, .teal, .red, .cyan, .mint, .indigo]
        let calendar = Calendar.current
        let start = calendar.date(byAdding: .day, value: -days, to: Date())!
        return dataModel.categories.enumerated().compactMap { index, category in
            let categoryProjects = dataModel.projects.filter { $0.categoryId == category.id }
            let total = categoryProjects.reduce(0.0) { sum, project in
                sum + dataModel.records(for: project).filter { $0.date >= start }.reduce(0.0) { $0 + $1.duration }
            } / 3600.0
            if total > 0 {
                return ("\(category.icon) \(category.name)", total, colors[index % colors.count])
            }
            return nil
        }.sorted { $0.1 > $1.1 }
    }

    func weeklyTotals() -> [(String, Double)] {
        let calendar = Calendar.current
        let today = Date()
        return (0..<4).reversed().compactMap { weekAgo -> (String, Double)? in
            guard let weekStart = calendar.date(byAdding: .weekOfYear, value: -weekAgo, to: today),
                  let weekEnd = calendar.date(byAdding: .day, value: 7, to: weekStart) else { return nil }
            let total = dataModel.records.filter { $0.date >= weekStart && $0.date < weekEnd }.reduce(0.0) { $0 + $1.duration } / 3600.0
            return (weekAgo == 0 ? "이번주" : "\(weekAgo)주전", total)
        }
    }

    func topProjects(days: Int) -> [(Project, Double)] {
        let start = Calendar.current.date(byAdding: .day, value: -days, to: Date())!
        return dataModel.projects.map { project in
            let total = dataModel.records(for: project).filter { $0.date >= start }.reduce(0.0) { $0 + $1.duration } / 3600.0
            return (project, total)
        }.filter { $0.1 > 0 }.sorted { $0.1 > $1.1 }.prefix(5).map { $0 }
    }

    func medalColor(_ index: Int) -> Color {
        [Color.yellow, Color.gray, Color.brown, Color.blue.opacity(0.5)][min(index, 3)]
    }

    func timeString(from time: TimeInterval) -> String {
        String(format: "%02d:%02d:%02d", Int(time) / 3600, Int(time) / 60 % 60, Int(time) % 60)
    }

    func dateString(from date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "MM/dd HH:mm"
        return formatter.string(from: date)
    }
}

struct DayDetailView: View {
    @EnvironmentObject var dataModel: DataModel
    @Environment(\.dismiss) var dismiss
    let dateString: String

    var dayDate: Date? {
        let formatter = DateFormatter()
        formatter.dateFormat = "M/d"
        formatter.locale = Locale(identifier: "ko_KR")
        formatter.timeZone = TimeZone.current
        let year = Calendar.current.component(.year, from: Date())
        guard let parsed = formatter.date(from: dateString) else { return nil }
        var components = Calendar.current.dateComponents([.month, .day], from: parsed)
        components.year = year
        components.hour = 0; components.minute = 0; components.second = 0
        return Calendar.current.date(from: components)
    }

    var categoryData: [(String, Double, Color)] {
        guard let date = dayDate else { return [] }
        let start = Calendar.current.startOfDay(for: date)
        let end = Calendar.current.date(byAdding: .day, value: 1, to: start)!
        let colors: [Color] = [.blue, .purple, .pink, .orange, .green, .teal, .red]
        return dataModel.categories.enumerated().compactMap { index, category in
            let total = dataModel.projects.filter { $0.categoryId == category.id }.reduce(0.0) { sum, project in
                sum + dataModel.records(for: project).filter { $0.date >= start && $0.date < end }.reduce(0.0) { $0 + $1.duration }
            } / 3600.0
            if total > 0 { return ("\(category.icon) \(category.name)", total, colors[index % colors.count]) }
            return nil
        }.sorted { $0.1 > $1.1 }
    }

    var topApps: [(Project, Double)] {
        guard let date = dayDate else { return [] }
        let start = Calendar.current.startOfDay(for: date)
        let end = Calendar.current.date(byAdding: .day, value: 1, to: start)!
        return dataModel.projects.map { project in
            let total = dataModel.records(for: project).filter { $0.date >= start && $0.date < end }.reduce(0.0) { $0 + $1.duration } / 3600.0
            return (project, total)
        }.filter { $0.1 > 0 }.sorted { $0.1 > $1.1 }
    }

    var totalHours: Double { categoryData.reduce(0.0) { $0 + $1.1 } }

    var body: some View {
        NavigationView {
            ScrollView {
                VStack(spacing: 20) {
                    HStack {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("\(dateString) 총 사용시간").font(.caption).foregroundColor(.gray)
                            Text(String(format: "%.0f시간 %.0f분", floor(totalHours), (totalHours - floor(totalHours)) * 60))
                                .font(.title2).fontWeight(.bold)
                        }
                        Spacer()
                    }
                    .padding().background(Color.orange.opacity(0.1)).cornerRadius(16).padding(.horizontal)

                    if categoryData.isEmpty {
                        Text("이 날의 기록이 없어요").foregroundColor(.gray).padding()
                    } else {
                        VStack(alignment: .leading, spacing: 12) {
                            Text("카테고리 비중").font(.headline).padding(.horizontal)
                            PieChartView(data: categoryData, total: totalHours)
                                .frame(width: 260, height: 260).frame(maxWidth: .infinity)
                            VStack(spacing: 8) {
                                ForEach(categoryData, id: \.0) { item in
                                    HStack(spacing: 10) {
                                        RoundedRectangle(cornerRadius: 4).fill(item.2).frame(width: 14, height: 14)
                                        Text(item.0).font(.caption)
                                        Spacer()
                                        Text(String(format: "%.1f시간", item.1)).font(.caption).foregroundColor(.gray)
                                        Text(String(format: "%.0f%%", totalHours > 0 ? item.1 / totalHours * 100 : 0))
                                            .font(.caption).fontWeight(.medium).frame(width: 36, alignment: .trailing)
                                    }.padding(.horizontal)
                                }
                            }
                        }
                        VStack(alignment: .leading, spacing: 8) {
                            Text("앱별 사용시간").font(.headline).padding(.horizontal)
                            ForEach(topApps, id: \.0.id) { item in
                                let category = dataModel.category(for: item.0)
                                HStack {
                                    Text("\(category?.icon ?? "📌") \(item.0.name)").font(.body).lineLimit(1)
                                    Spacer()
                                    GeometryReader { geo in
                                        ZStack(alignment: .leading) {
                                            RoundedRectangle(cornerRadius: 4).fill(Color.gray.opacity(0.15))
                                            RoundedRectangle(cornerRadius: 4).fill(Color.orange.opacity(0.7))
                                                .frame(width: totalHours > 0 ? geo.size.width * CGFloat(item.1 / totalHours) : 0)
                                        }
                                    }.frame(width: 80, height: 8)
                                    Text(String(format: "%.1fh", item.1)).font(.caption).fontWeight(.medium)
                                        .foregroundColor(.orange).frame(width: 40, alignment: .trailing)
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
                Text(String(format: "%.0f시간", total)).font(.title3).fontWeight(.bold)
            }
        }
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
    ReportView().environmentObject(DataModel())
}
