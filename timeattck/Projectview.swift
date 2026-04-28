import SwiftUI
import SwiftData

struct ProjectView: View {
    @Environment(\.modelContext) var modelContext
    @Query(sort: \Project.sortOrder) var projects: [Project]
    @State private var showingAddActivity = false
    @State private var showingProjectManager = false
    @State private var activityToDelete: Activity? = nil
    @State private var showingDeleteAlert = false
    @State private var activityToEdit: Activity? = nil
    @State private var isReordering = false

    var body: some View {
        NavigationView {
            ScrollView {
                VStack(spacing: 12) {
                    ForEach(projects) { project in
                        let projectActivities = project.sortedActivities
                        if !projectActivities.isEmpty {
                            if isReordering {
                                VStack(alignment: .leading, spacing: 8) {
                                    Text("\(project.icon) \(project.name)")
                                        .font(.headline)
                                        .padding(.horizontal)
                                    ReorderableActivityList(project: project)
                                }
                            } else {
                                projectCard(project: project, activities: projectActivities)
                            }
                        }
                    }
                }
                .padding(.top)
            }
            .navigationTitle("\(projects.reduce(0) { $0 + $1.activities.count })개의 프로젝트 관리중")
            .toolbar {
                ToolbarItem(placement: .automatic) {
                    Menu {
                        Button(action: { showingAddActivity = true }) {
                            Label("활동 추가", systemImage: "plus")
                        }
                        Button(action: { showingProjectManager = true }) {
                            Label("프로젝트 관리", systemImage: "folder.badge.gear")
                        }
                        Button(action: { isReordering.toggle() }) {
                            Label(isReordering ? "순서 변경 완료" : "순서 변경", systemImage: isReordering ? "checkmark" : "arrow.up.arrow.down")
                        }
                    } label: {
                        Image(systemName: "ellipsis.circle")
                    }
                }
            }
            .sheet(isPresented: $showingAddActivity) {
                AddActivityView(isPresented: $showingAddActivity)
            }
            .sheet(item: $activityToEdit) { activity in
                EditActivityView(activity: activity)
            }
            .sheet(isPresented: $showingProjectManager) {
                ProjectManagerView()
            }
            .alert("활동 삭제", isPresented: $showingDeleteAlert) {
                Button("삭제", role: .destructive) {
                    if let activity = activityToDelete {
                        modelContext.delete(activity)
                    }
                }
                Button("취소", role: .cancel) {}
            } message: {
                if let activity = activityToDelete {
                    Text("'\(activity.name)' 활동을 삭제할까요?")
                }
            }
        }
    }

    func projectCard(project: Project, activities: [Activity]) -> some View {
        HStack(alignment: .top, spacing: 0) {
            VStack(spacing: 6) {
                Text(project.icon).font(.title2)
                Text(project.name)
                    .font(.caption)
                    .foregroundColor(.gray)
                    .multilineTextAlignment(.center)
                    .lineLimit(2)
            }
            .frame(width: 72)
            .frame(maxHeight: .infinity)
            .padding(.vertical, 14)

            Rectangle()
                .fill(Color.gray.opacity(0.2))
                .frame(width: 1)

            VStack(spacing: 0) {
                ForEach(Array(activities.enumerated()), id: \.element.id) { index, activity in
                    activityRow(activity: activity)
                    if index < activities.count - 1 {
                        Divider().padding(.leading, 12)
                    }
                }
            }
        }
        .background(Color.gray.opacity(0.08))
        .cornerRadius(12)
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.gray.opacity(0.15), lineWidth: 1))
        .padding(.horizontal)
    }

    func activityRow(activity: Activity) -> some View {
        let isAchieved = activity.isTodayGoalAchieved
        let streak = activity.streak
        let badge = activity.badge

        return HStack {
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 5) {
                    Text(activity.name)
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
                if activity.dailyGoal > 0 {
                    let todayTime = activity.todayTime
                    let progress = min(todayTime / activity.dailyGoal, 1.0)
                    HStack(spacing: 6) {
                        ProgressView(value: progress)
                            .tint(isAchieved ? .green : .blue)
                        Text(timeString(from: todayTime) + " / " + timeString(from: activity.dailyGoal))
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
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 11)
        .background(isAchieved ? Color.green.opacity(0.06) : Color.clear)
        .contentShape(Rectangle())
        .onTapGesture { activityToEdit = activity }
        .onLongPressGesture {
            activityToDelete = activity
            showingDeleteAlert = true
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

// MARK: - 순서 변경 리스트
struct ReorderableActivityList: View {
    @Environment(\.modelContext) var modelContext
    let project: Project

    var sortedActivities: [Activity] {
        project.sortedActivities
    }

    var body: some View {
        VStack(spacing: 0) {
            ForEach(sortedActivities) { activity in
                HStack {
                    Image(systemName: "line.3.horizontal")
                        .foregroundColor(.gray)
                        .padding(.leading)
                    Text(activity.name)
                        .font(.body)
                        .padding(.vertical, 12)
                    Spacer()
                }
                .background(Color.gray.opacity(0.08))
                .cornerRadius(12)
                .padding(.horizontal)
                .padding(.vertical, 2)
            }
            .onMove { from, to in
                var sorted = sortedActivities
                sorted.move(fromOffsets: from, toOffset: to)
                for (index, activity) in sorted.enumerated() {
                    activity.sortOrder = index
                }
            }
        }
    }
}

// MARK: - 프로젝트 관리
struct ProjectManagerView: View {
    @Environment(\.modelContext) var modelContext
    @Environment(\.dismiss) var dismiss
    @Query(sort: \Project.sortOrder) var projects: [Project]
    @State private var showingAddProject = false
    @State private var projectToEdit: Project? = nil
    @State private var projectToDelete: Project? = nil
    @State private var showingDeleteAlert = false

    var body: some View {
        NavigationView {
            List {
                ForEach(projects) { project in
                    HStack {
                        Text(project.icon).font(.title2)
                        Text(project.name).font(.body)
                        Spacer()
                        Text("\(project.activities.count)개").font(.caption).foregroundColor(.gray)
                    }
                    .contentShape(Rectangle())
                    .onTapGesture { projectToEdit = project }
                    .swipeActions(edge: .trailing) {
                        Button(role: .destructive) {
                            projectToDelete = project
                            showingDeleteAlert = true
                        } label: {
                            Label("삭제", systemImage: "trash")
                        }
                    }
                }
                .onMove { from, to in
                    var sorted = projects
                    sorted.move(fromOffsets: from, toOffset: to)
                    for (index, project) in sorted.enumerated() {
                        project.sortOrder = index
                    }
                }
            }
            .environment(\.editMode, .constant(.active))
            .navigationTitle("프로젝트 관리")
            .toolbar {
                ToolbarItem(placement: .automatic) {
                    Button(action: { showingAddProject = true }) {
                        Image(systemName: "plus")
                    }
                }
                ToolbarItem(placement: .cancellationAction) {
                    Button("닫기") { dismiss() }
                }
            }
            .sheet(isPresented: $showingAddProject) {
                AddProjectView(isPresented: $showingAddProject)
            }
            .sheet(item: $projectToEdit) { project in
                EditProjectView(project: project)
            }
            .alert("프로젝트 삭제", isPresented: $showingDeleteAlert) {
                Button("삭제", role: .destructive) {
                    if let project = projectToDelete {
                        modelContext.delete(project)
                    }
                }
                Button("취소", role: .cancel) {}
            } message: {
                if let project = projectToDelete {
                    Text("'\(project.name)' 프로젝트를 삭제할까요?\n관련 활동과 기록도 모두 삭제됩니다.")
                }
            }
        }
    }
}

// MARK: - 프로젝트 추가
struct AddProjectView: View {
    @Environment(\.modelContext) var modelContext
    @Query(sort: \Project.sortOrder) var projects: [Project]
    @Binding var isPresented: Bool
    @State private var name = ""
    @State private var icon = "📌"

    let suggestedIcons = ["🎮","📚","💬","🎬","💪","💼","📌","🎵","🍳","✈️","🎨","📷","🏃","💰","🧘","📝","🎯","🛒","🐾","🌱"]

    var body: some View {
        NavigationView {
            Form {
                Section(header: Text("프로젝트 이름")) {
                    TextField("예) 자기계발, 취미, 업무", text: $name)
                }
                Section(header: Text("아이콘")) {
                    TextField("이모지 입력", text: $icon).font(.title2)
                    LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 5), spacing: 12) {
                        ForEach(suggestedIcons, id: \.self) { emoji in
                            Text(emoji).font(.title2)
                                .frame(width: 44, height: 44)
                                .background(icon == emoji ? Color.blue.opacity(0.2) : Color.gray.opacity(0.1))
                                .cornerRadius(8)
                                .onTapGesture { icon = emoji }
                        }
                    }
                    .padding(.vertical, 4)
                }
            }
            .navigationTitle("프로젝트 추가")
            .toolbar {
                ToolbarItem(placement: .automatic) {
                    Button("추가") {
                        if !name.isEmpty {
                            let project = Project(name: name, icon: icon, sortOrder: projects.count)
                            modelContext.insert(project)
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

// MARK: - 프로젝트 수정
struct EditProjectView: View {
    @Environment(\.dismiss) var dismiss
    let project: Project
    @State private var name: String
    @State private var icon: String

    let suggestedIcons = ["🎮","📚","💬","🎬","💪","💼","📌","🎵","🍳","✈️","🎨","📷","🏃","💰","🧘","📝","🎯","🛒","🐾","🌱"]

    init(project: Project) {
        self.project = project
        _name = State(initialValue: project.name)
        _icon = State(initialValue: project.icon)
    }

    var body: some View {
        NavigationView {
            Form {
                Section(header: Text("프로젝트 이름")) {
                    TextField("이름", text: $name)
                }
                Section(header: Text("아이콘")) {
                    TextField("이모지 입력", text: $icon).font(.title2)
                    LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 5), spacing: 12) {
                        ForEach(suggestedIcons, id: \.self) { emoji in
                            Text(emoji).font(.title2)
                                .frame(width: 44, height: 44)
                                .background(icon == emoji ? Color.blue.opacity(0.2) : Color.gray.opacity(0.1))
                                .cornerRadius(8)
                                .onTapGesture { icon = emoji }
                        }
                    }
                    .padding(.vertical, 4)
                }
            }
            .navigationTitle("프로젝트 수정")
            .toolbar {
                ToolbarItem(placement: .automatic) {
                    Button("저장") {
                        project.name = name
                        project.icon = icon
                        dismiss()
                    }
                    .disabled(name.isEmpty)
                }
                ToolbarItem(placement: .cancellationAction) {
                    Button("취소") { dismiss() }
                }
            }
        }
    }
}

// MARK: - 활동 추가
struct AddActivityView: View {
    @Environment(\.modelContext) var modelContext
    @Query(sort: \Project.sortOrder) var projects: [Project]
    @Binding var isPresented: Bool
    @State private var selectedProject: Project? = nil
    @State private var name = ""
    @State private var dailyGoalHours: Int = 0
    @State private var dailyGoalMinutes: Int = 0
    @State private var step = 1

    var body: some View {
        NavigationView {
            if step == 1 {
                projectSelectionView
            } else {
                activityInputView
            }
        }
    }

    var projectSelectionView: some View {
        List {
            ForEach(projects) { project in
                HStack {
                    Text(project.icon).font(.title2)
                    Text(project.name).font(.body)
                    Spacer()
                    Image(systemName: "chevron.right").foregroundColor(.gray).font(.caption)
                }
                .contentShape(Rectangle())
                .onTapGesture {
                    selectedProject = project
                    step = 2
                }
            }
        }
        .navigationTitle("프로젝트 선택")
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("취소") { isPresented = false }
            }
        }
    }

    var activityInputView: some View {
        Form {
            Section(header: Text("프로젝트")) {
                HStack {
                    Text(selectedProject?.icon ?? "📌")
                    Text(selectedProject?.name ?? "").foregroundColor(.blue)
                }
            }
            Section(header: Text("활동 이름")) {
                TextField("예) 영어 단어, 유튜브, 헬스", text: $name)
            }
            Section(header: Text("하루 목표 시간 (선택)")) {
                HStack {
                    Picker("시간", selection: $dailyGoalHours) {
                        ForEach(0..<24) { Text("\($0)시간").tag($0) }
                    }
                    .pickerStyle(.wheel).frame(width: 120)
                    Picker("분", selection: $dailyGoalMinutes) {
                        ForEach([0, 10, 20, 30, 40, 50], id: \.self) { Text("\($0)분").tag($0) }
                    }
                    .pickerStyle(.wheel).frame(width: 120)
                }
            }
        }
        .navigationTitle("활동 추가")
        .toolbar {
            ToolbarItem(placement: .automatic) {
                Button("추가") {
                    if !name.isEmpty, let project = selectedProject {
                        let goal = TimeInterval(dailyGoalHours * 3600 + dailyGoalMinutes * 60)
                        let activity = Activity(name: name, project: project, dailyGoal: goal, sortOrder: project.activities.count)
                        modelContext.insert(activity)
                        isPresented = false
                    }
                }
                .disabled(name.isEmpty)
            }
            ToolbarItem(placement: .cancellationAction) {
                Button("뒤로") { step = 1 }
            }
        }
    }
}

// MARK: - 활동 수정
struct EditActivityView: View {
    @Environment(\.modelContext) var modelContext
    @Environment(\.dismiss) var dismiss
    @Query(sort: \Project.sortOrder) var projects: [Project]
    let activity: Activity
    @State private var name: String
    @State private var dailyGoalHours: Int
    @State private var dailyGoalMinutes: Int
    @State private var selectedProject: Project?

    init(activity: Activity) {
        self.activity = activity
        _name = State(initialValue: activity.name)
        let totalSeconds = Int(activity.dailyGoal)
        _dailyGoalHours = State(initialValue: totalSeconds / 3600)
        _dailyGoalMinutes = State(initialValue: (totalSeconds % 3600) / 60)
        _selectedProject = State(initialValue: activity.project)
    }

    var body: some View {
        NavigationView {
            Form {
                Section(header: Text("활동 이름")) {
                    TextField("이름", text: $name)
                }
                Section(header: Text("프로젝트")) {
                    ForEach(projects) { project in
                        HStack {
                            Text("\(project.icon) \(project.name)")
                            Spacer()
                            if selectedProject?.id == project.id {
                                Image(systemName: "checkmark").foregroundColor(.blue)
                            }
                        }
                        .contentShape(Rectangle())
                        .onTapGesture { selectedProject = project }
                    }
                }
                Section(header: Text("하루 목표 시간")) {
                    HStack {
                        Picker("시간", selection: $dailyGoalHours) {
                            ForEach(0..<24) { Text("\($0)시간").tag($0) }
                        }
                        .pickerStyle(.wheel).frame(width: 120)
                        Picker("분", selection: $dailyGoalMinutes) {
                            ForEach([0, 10, 20, 30, 40, 50], id: \.self) { Text("\($0)분").tag($0) }
                        }
                        .pickerStyle(.wheel).frame(width: 120)
                    }
                }
            }
            .navigationTitle("활동 수정")
            .toolbar {
                ToolbarItem(placement: .automatic) {
                    Button("저장") {
                        activity.name = name
                        activity.dailyGoal = TimeInterval(dailyGoalHours * 3600 + dailyGoalMinutes * 60)
                        if let project = selectedProject {
                            activity.project = project
                        }
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
        .modelContainer(sharedModelContainer)
}
