import SwiftUI

struct ProjectView: View {
    @EnvironmentObject var dataModel: DataModel
    @State private var showingAddProject = false
    @State private var projectToDelete: Project? = nil
    @State private var showingDeleteAlert = false
    @State private var projectToEdit: Project? = nil

    var body: some View {
        NavigationView {
            ScrollView {
                VStack(spacing: 12) {
                    ForEach(ProjectCategory.allCases, id: \.self) { category in
                        let categoryProjects = dataModel.projects.filter { $0.category == category }
                        if !categoryProjects.isEmpty {
                            VStack(alignment: .leading, spacing: 8) {
                                Text("\(category.icon) \(category.rawValue)")
                                    .font(.headline)
                                    .padding(.horizontal)

                                ForEach(categoryProjects) { project in
                                    HStack {
                                        VStack(alignment: .leading, spacing: 4) {
                                            Text(project.name)
                                                .font(.body)
                                                .fontWeight(.medium)
                                                .lineLimit(1)
                                            if project.dailyGoal > 0 {
                                                let todayTime = dataModel.todayTime(for: project)
                                                let progress = min(todayTime / project.dailyGoal, 1.0)
                                                HStack(spacing: 6) {
                                                    ProgressView(value: progress)
                                                        .frame(width: 80)
                                                    Text(timeString(from: todayTime) + " / " + timeString(from: project.dailyGoal))
                                                        .font(.caption2)
                                                        .foregroundColor(progress >= 1.0 ? .green : .gray)
                                                }
                                            }
                                        }
                                        Spacer()
                                        Text(timeString(from: dataModel.totalTime(for: project)))
                                            .font(.caption)
                                            .foregroundColor(.gray)
                                    }
                                    .padding()
                                    .background(Color.gray.opacity(0.1))
                                    .cornerRadius(12)
                                    .padding(.horizontal)
                                    .onTapGesture {
                                        projectToEdit = project
                                    }
                                    .onLongPressGesture {
                                        projectToDelete = project
                                        showingDeleteAlert = true
                                    }
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
                    Button(action: {
                        showingAddProject = true
                    }) {
                        Image(systemName: "plus")
                    }
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

    func timeString(from time: TimeInterval) -> String {
        let hours = Int(time) / 3600
        let minutes = Int(time) / 60 % 60
        let seconds = Int(time) % 60
        return String(format: "%02d:%02d:%02d", hours, minutes, seconds)
    }
}

struct AddProjectView: View {
    @EnvironmentObject var dataModel: DataModel
    @Binding var isPresented: Bool
    @State private var name = ""
    @State private var category: ProjectCategory = .other
    @State private var dailyGoalHours: Int = 0
    @State private var dailyGoalMinutes: Int = 0

    var body: some View {
        NavigationView {
            Form {
                Section(header: Text("앱 이름")) {
                    TextField("예) 카카오톡, 유튜브", text: $name)
                }
                Section(header: Text("카테고리")) {
                    ForEach(ProjectCategory.allCases, id: \.self) { cat in
                        HStack {
                            Text("\(cat.icon) \(cat.rawValue)")
                            Spacer()
                            if category == cat {
                                Image(systemName: "checkmark")
                                    .foregroundColor(.blue)
                            }
                        }
                        .contentShape(Rectangle())
                        .onTapGesture { category = cat }
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
            .toolbar {
                ToolbarItem(placement: .automatic) {
                    Button("추가") {
                        if !name.isEmpty {
                            let goal = TimeInterval(dailyGoalHours * 3600 + dailyGoalMinutes * 60)
                            dataModel.addProject(name: name, category: category, dailyGoal: goal)
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
                    ForEach(ProjectCategory.allCases, id: \.self) { cat in
                        HStack {
                            Text("\(cat.icon) \(cat.rawValue)")
                            Spacer()
                            if project.category == cat {
                                Image(systemName: "checkmark")
                                    .foregroundColor(.blue)
                            }
                        }
                        .contentShape(Rectangle())
                        .onTapGesture { project.category = cat }
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
