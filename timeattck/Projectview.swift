import SwiftUI

struct ProjectView: View {
    @EnvironmentObject var dataModel: DataModel
    @State private var showingAddProject = false
    @State private var showingCategoryManager = false
    @State private var projectToDelete: Project? = nil
    @State private var showingDeleteAlert = false
    @State private var projectToEdit: Project? = nil

    var todaySummary: (achieved: Int, total: Int) {
        dataModel.todayGoalSummary()
    }

    var body: some View {
        NavigationView {
            ScrollView {
                VStack(spacing: 16) {
                    if todaySummary.total > 0 {
                        todaySummaryCard
                    }

                    ForEach(dataModel.categories) { category in
                        let categoryProjects = dataModel.projects.filter { $0.categoryId == category.id }
                        if !categoryProjects.isEmpty {
                            VStack(alignment: .leading, spacing: 8) {
                                Text("\(category.icon) \(category.name)")
                                    .font(.headline)
                                    .padding(.horizontal)

                                ForEach(categoryProjects) { project in
                                    projectCard(project: project)
                                }
                            }
                        }
                    }
                }
                .padding(.top)
            }
            .navigationTitle("프로젝트 (\(dataModel.projects.count))")
            .toolbar {
                ToolbarItem(placement: .automatic) {
                    Menu {
                        Button(action: { showingAddProject = true }) {
                            Label("프로젝트 추가", systemImage: "plus")
                        }
                        Button(action: { showingCategoryManager = true }) {
                            Label("카테고리 관리", systemImage: "folder.badge.gear")
                        }
                    } label: {
                        Image(systemName: "ellipsis.circle")
                    }
                }
            }
            .sheet(isPresented: $showingAddProject) {
                AddProjectView(isPresented: $showingAddProject)
            }
            .sheet(item: $projectToEdit) { project in
                EditProjectView(project: project)
            }
            .sheet(isPresented: $showingCategoryManager) {
                CategoryManagerView()
            }
            .alert("프로젝트 삭제", isPresented: $showingDeleteAlert) {
                Button("삭제", role: .destructive) {
                    if let project = projectToDelete,
                       let index = dataModel.projects.firstIndex(where: { $0.id == project.id }) {
                        dataModel.deleteProject(at: IndexSet(integer: index))
                    }
                }
                Button("취소", role: .cancel) {}
            } message: {
                if let project = projectToDelete {
                    Text("'\(project.name)' 프로젝트를 삭제할까요?")
                }
            }
        }
    }

    var todaySummaryCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("오늘의 목표")
                    .font(.headline)
                Spacer()
                Text("\(todaySummary.achieved) / \(todaySummary.total) 달성")
                    .font(.caption)
                    .fontWeight(.medium)
                    .foregroundColor(todaySummary.achieved == todaySummary.total ? .green : .gray)
            }
            ProgressView(value: Double(todaySummary.achieved), total: Double(max(todaySummary.total, 1)))
                .tint(todaySummary.achieved == todaySummary.total ? .green : .blue)
        }
        .padding()
        .background(Color.blue.opacity(0.08))
        .cornerRadius(16)
        .padding(.horizontal)
    }

    func projectCard(project: Project) -> some View {
        let streak = dataModel.streak(for: project)
        let badge = dataModel.badge(for: project)
        let isAchieved = dataModel.isTodayGoalAchieved(for: project)
        let category = dataModel.category(for: project)

        return HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Text(project.name)
                        .font(.body)
                        .fontWeight(.medium)
                        .lineLimit(1)
                    if !badge.isEmpty { Text(badge).font(.caption) }
                    if isAchieved {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundColor(.green)
                            .font(.caption)
                    }
                }

                if project.dailyGoal > 0 {
                    let todayTime = dataModel.todayTime(for: project)
                    let progress = min(todayTime / project.dailyGoal, 1.0)
                    HStack(spacing: 6) {
                        ProgressView(value: progress)
                            .frame(width: 80)
                            .tint(isAchieved ? .green : .blue)
                        Text(timeString(from: todayTime) + " / " + timeString(from: project.dailyGoal))
                            .font(.caption2)
                            .foregroundColor(isAchieved ? .green : .gray)
                    }
                    if streak > 0 {
                        Text("🔥 \(streak)일 연속 달성")
                            .font(.caption2)
                            .foregroundColor(.orange)
                    }
                }
            }

            Spacer()

            VStack(alignment: .trailing, spacing: 4) {
                Text(timeString(from: dataModel.totalTime(for: project)))
                    .font(.caption)
                    .foregroundColor(.gray)
                if project.dailyGoal > 0 {
                    Text("30일 \(dataModel.achievedDays(for: project))회")
                        .font(.caption2)
                        .foregroundColor(.gray)
                }
            }
        }
        .padding()
        .background(isAchieved ? Color.green.opacity(0.08) : Color.gray.opacity(0.08))
        .cornerRadius(12)
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(isAchieved ? Color.green.opacity(0.3) : Color.clear, lineWidth: 1))
        .padding(.horizontal)
        .onTapGesture { projectToEdit = project }
        .onLongPressGesture {
            projectToDelete = project
            showingDeleteAlert = true
        }
    }

    func timeString(from time: TimeInterval) -> String {
        let h = Int(time) / 3600
        let m = Int(time) / 60 % 60
        let s = Int(time) % 60
        return String(format: "%02d:%02d:%02d", h, m, s)
    }
}

// MARK: - 카테고리 관리
struct CategoryManagerView: View {
    @EnvironmentObject var dataModel: DataModel
    @Environment(\.dismiss) var dismiss
    @State private var showingAddCategory = false
    @State private var categoryToEdit: ProjectCategory? = nil
    @State private var categoryToDelete: ProjectCategory? = nil
    @State private var showingDeleteAlert = false

    var body: some View {
        NavigationView {
            List {
                ForEach(dataModel.categories) { category in
                    HStack {
                        Text(category.icon)
                            .font(.title2)
                        Text(category.name)
                            .font(.body)
                        Spacer()
                        let count = dataModel.projects.filter { $0.categoryId == category.id }.count
                        Text("\(count)개")
                            .font(.caption)
                            .foregroundColor(.gray)
                    }
                    .contentShape(Rectangle())
                    .onTapGesture { categoryToEdit = category }
                    .swipeActions(edge: .trailing) {
                        Button(role: .destructive) {
                            categoryToDelete = category
                            showingDeleteAlert = true
                        } label: {
                            Label("삭제", systemImage: "trash")
                        }
                    }
                }
            }
            .navigationTitle("카테고리 관리")
            .toolbar {
                ToolbarItem(placement: .automatic) {
                    Button(action: { showingAddCategory = true }) {
                        Image(systemName: "plus")
                    }
                }
                ToolbarItem(placement: .cancellationAction) {
                    Button("닫기") { dismiss() }
                }
            }
            .sheet(isPresented: $showingAddCategory) {
                AddCategoryView(isPresented: $showingAddCategory)
            }
            .sheet(item: $categoryToEdit) { category in
                EditCategoryView(category: category)
            }
            .alert("카테고리 삭제", isPresented: $showingDeleteAlert) {
                Button("삭제", role: .destructive) {
                    if let cat = categoryToDelete {
                        dataModel.deleteCategory(cat)
                    }
                }
                Button("취소", role: .cancel) {}
            } message: {
                if let cat = categoryToDelete {
                    Text("'\(cat.name)' 카테고리를 삭제할까요?\n해당 카테고리의 프로젝트는 유지됩니다.")
                }
            }
        }
    }
}

// MARK: - 카테고리 추가
struct AddCategoryView: View {
    @EnvironmentObject var dataModel: DataModel
    @Binding var isPresented: Bool
    @State private var name = ""
    @State private var icon = ""

    let suggestedIcons = ["🎮","📚","💬","🎬","💪","💼","📌","🎵","🍳","✈️","🎨","📷","🏃","💰","🧘","📝","🎯","🛒","🐾","🌱"]

    var body: some View {
        NavigationView {
            Form {
                Section(header: Text("카테고리 이름")) {
                    TextField("예) 독서, 요리, 여행", text: $name)
                }
                Section(header: Text("아이콘")) {
                    TextField("이모지 입력", text: $icon)
                        .font(.title2)

                    LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 5), spacing: 12) {
                        ForEach(suggestedIcons, id: \.self) { emoji in
                            Text(emoji)
                                .font(.title2)
                                .frame(width: 44, height: 44)
                                .background(icon == emoji ? Color.blue.opacity(0.2) : Color.gray.opacity(0.1))
                                .cornerRadius(8)
                                .onTapGesture { icon = emoji }
                        }
                    }
                    .padding(.vertical, 4)
                }
            }
            .navigationTitle("카테고리 추가")
            .toolbar {
                ToolbarItem(placement: .automatic) {
                    Button("추가") {
                        if !name.isEmpty {
                            dataModel.addCategory(name: name, icon: icon.isEmpty ? "📌" : icon)
                            isPresented = false
                        }
                    }
                    .disabled(name.isEmpty)
                }
                ToolbarItem(placement: .cancellationAction) {
                    Button("취소") { isPresented = false }
                }
            }
        }
    }
}

// MARK: - 카테고리 수정
struct EditCategoryView: View {
    @EnvironmentObject var dataModel: DataModel
    @Environment(\.dismiss) var dismiss
    @State var category: ProjectCategory

    let suggestedIcons = ["🎮","📚","💬","🎬","💪","💼","📌","🎵","🍳","✈️","🎨","📷","🏃","💰","🧘","📝","🎯","🛒","🐾","🌱"]

    var body: some View {
        NavigationView {
            Form {
                Section(header: Text("카테고리 이름")) {
                    TextField("이름", text: $category.name)
                }
                Section(header: Text("아이콘")) {
                    TextField("이모지 입력", text: $category.icon)
                        .font(.title2)

                    LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 5), spacing: 12) {
                        ForEach(suggestedIcons, id: \.self) { emoji in
                            Text(emoji)
                                .font(.title2)
                                .frame(width: 44, height: 44)
                                .background(category.icon == emoji ? Color.blue.opacity(0.2) : Color.gray.opacity(0.1))
                                .cornerRadius(8)
                                .onTapGesture { category.icon = emoji }
                        }
                    }
                    .padding(.vertical, 4)
                }
            }
            .navigationTitle("카테고리 수정")
            .toolbar {
                ToolbarItem(placement: .automatic) {
                    Button("저장") {
                        dataModel.updateCategory(category)
                        dismiss()
                    }
                    .disabled(category.name.isEmpty)
                }
                ToolbarItem(placement: .cancellationAction) {
                    Button("취소") { dismiss() }
                }
            }
        }
    }
}

// MARK: - 프로젝트 추가
struct AddProjectView: View {
    @EnvironmentObject var dataModel: DataModel
    @Binding var isPresented: Bool
    @State private var name = ""
    @State private var selectedCategoryId: UUID? = nil
    @State private var dailyGoalHours: Int = 0
    @State private var dailyGoalMinutes: Int = 0

    var body: some View {
        NavigationView {
            Form {
                Section(header: Text("앱 이름")) {
                    TextField("예) 카카오톡, 유튜브", text: $name)
                }
                Section(header: Text("카테고리")) {
                    ForEach(dataModel.categories) { cat in
                        HStack {
                            Text("\(cat.icon) \(cat.name)")
                            Spacer()
                            if selectedCategoryId == cat.id {
                                Image(systemName: "checkmark").foregroundColor(.blue)
                            }
                        }
                        .contentShape(Rectangle())
                        .onTapGesture { selectedCategoryId = cat.id }
                    }
                }
                Section(header: Text("하루 목표 시간 (선택)")) {
                    HStack {
                        Picker("시간", selection: $dailyGoalHours) {
                            ForEach(0..<24) { Text("\($0)시간").tag($0) }
                        }
                        .pickerStyle(.wheel)
                        .frame(width: 120)
                        Picker("분", selection: $dailyGoalMinutes) {
                            ForEach([0, 10, 20, 30, 40, 50], id: \.self) { Text("\($0)분").tag($0) }
                        }
                        .pickerStyle(.wheel)
                        .frame(width: 120)
                    }
                }
            }
            .navigationTitle("새 프로젝트")
            .onAppear {
                if selectedCategoryId == nil {
                    selectedCategoryId = dataModel.categories.first?.id
                }
            }
            .toolbar {
                ToolbarItem(placement: .automatic) {
                    Button("추가") {
                        if !name.isEmpty, let catId = selectedCategoryId {
                            let goal = TimeInterval(dailyGoalHours * 3600 + dailyGoalMinutes * 60)
                            dataModel.addProject(name: name, categoryId: catId, dailyGoal: goal)
                            isPresented = false
                        }
                    }
                    .disabled(name.isEmpty || selectedCategoryId == nil)
                }
                ToolbarItem(placement: .cancellationAction) {
                    Button("취소") { isPresented = false }
                }
            }
        }
    }
}

// MARK: - 프로젝트 수정
struct EditProjectView: View {
    @EnvironmentObject var dataModel: DataModel
    @Environment(\.dismiss) var dismiss
    @State var project: Project
    @State private var dailyGoalHours: Int = 0
    @State private var dailyGoalMinutes: Int = 0

    init(project: Project) {
        _project = State(initialValue: project)
        let totalSeconds = Int(project.dailyGoal)
        _dailyGoalHours = State(initialValue: totalSeconds / 3600)
        _dailyGoalMinutes = State(initialValue: (totalSeconds % 3600) / 60)
    }

    var body: some View {
        NavigationView {
            Form {
                Section(header: Text("앱 이름")) {
                    TextField("이름", text: $project.name)
                }
                Section(header: Text("카테고리")) {
                    ForEach(dataModel.categories) { cat in
                        HStack {
                            Text("\(cat.icon) \(cat.name)")
                            Spacer()
                            if project.categoryId == cat.id {
                                Image(systemName: "checkmark").foregroundColor(.blue)
                            }
                        }
                        .contentShape(Rectangle())
                        .onTapGesture { project.categoryId = cat.id }
                    }
                }
                Section(header: Text("하루 목표 시간")) {
                    HStack {
                        Picker("시간", selection: $dailyGoalHours) {
                            ForEach(0..<24) { Text("\($0)시간").tag($0) }
                        }
                        .pickerStyle(.wheel)
                        .frame(width: 120)
                        Picker("분", selection: $dailyGoalMinutes) {
                            ForEach([0, 10, 20, 30, 40, 50], id: \.self) { Text("\($0)분").tag($0) }
                        }
                        .pickerStyle(.wheel)
                        .frame(width: 120)
                    }
                }
            }
            .navigationTitle("프로젝트 수정")
            .toolbar {
                ToolbarItem(placement: .automatic) {
                    Button("저장") {
                        project.dailyGoal = TimeInterval(dailyGoalHours * 3600 + dailyGoalMinutes * 60)
                        dataModel.updateProject(project)
                        dismiss()
                    }
                }
                ToolbarItem(placement: .cancellationAction) {
                    Button("취소") { dismiss() }
                }
            }
        }
    }
}

#Preview {
    ProjectView()
        .environmentObject(DataModel())
}
