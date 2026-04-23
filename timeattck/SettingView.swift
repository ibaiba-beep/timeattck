import SwiftUI
import SwiftData
import UniformTypeIdentifiers

struct SettingsView: View {
    @Environment(\.modelContext) var modelContext
    @Query(sort: \Project.sortOrder) var projects: [Project]
    @Query var allActivities: [Activity]
    @Query var allRecords: [TimeRecord]
    @State private var showingExporter = false
    @State private var showingImporter = false
    @State private var showingRestoreAlert = false
    @State private var pendingRestoreURL: URL? = nil
    @State private var showingSuccessAlert = false
    @State private var alertMessage = ""
    @State private var backupDocument: BackupDocument? = nil

    var body: some View {
        NavigationView {
            List {
                Section(header: Text("데이터 백업")) {
                    Button(action: exportBackup) {
                        HStack {
                            Image(systemName: "arrow.up.doc")
                                .foregroundColor(.blue)
                            Text("백업 내보내기")
                            Spacer()
                            Text("JSON 파일로 저장")
                                .font(.caption)
                                .foregroundColor(.gray)
                        }
                    }
                    Button(action: { showingImporter = true }) {
                        HStack {
                            Image(systemName: "arrow.down.doc")
                                .foregroundColor(.green)
                            Text("백업 복원")
                            Spacer()
                            Text("JSON 파일 불러오기")
                                .font(.caption)
                                .foregroundColor(.gray)
                        }
                    }
                }

                Section(header: Text("데이터 현황")) {
                    HStack {
                        Text("프로젝트")
                        Spacer()
                        Text("\(projects.count)개").foregroundColor(.gray)
                    }
                    HStack {
                        Text("활동")
                        Spacer()
                        Text("\(allActivities.count)개").foregroundColor(.gray)
                    }
                    HStack {
                        Text("기록")
                        Spacer()
                        Text("\(allRecords.count)개").foregroundColor(.gray)
                    }
                }
            }
            .navigationTitle("설정")
            .fileExporter(
                isPresented: $showingExporter,
                document: backupDocument,
                contentType: .json,
                defaultFilename: backupFileName()
            ) { result in
                switch result {
                case .success:
                    alertMessage = "백업이 완료됐어요!"
                    showingSuccessAlert = true
                case .failure(let error):
                    alertMessage = "백업 실패: \(error.localizedDescription)"
                    showingSuccessAlert = true
                }
            }
            .fileImporter(
                isPresented: $showingImporter,
                allowedContentTypes: [.json]
            ) { result in
                switch result {
                case .success(let url):
                    alertMessage = "기존 데이터가 모두 덮어씌워져요. 복원할까요?"
                    showingRestoreAlert = true
                    pendingRestoreURL = url
                case .failure(let error):
                    alertMessage = "불러오기 실패: \(error.localizedDescription)"
                    showingSuccessAlert = true
                }
            }
            .alert("백업 복원", isPresented: $showingRestoreAlert) {
                Button("복원", role: .destructive) {
                    if let url = pendingRestoreURL {
                        restoreBackup(from: url)
                    }
                }
                Button("취소", role: .cancel) {}
            } message: {
                Text("기존 데이터가 모두 덮어씌워져요. 계속할까요?")
            }
            .alert(alertMessage, isPresented: $showingSuccessAlert) {
                Button("확인", role: .cancel) {}
            }
        }
    }

    func exportBackup() {
        let backupProjects = projects.map {
            BackupProject(id: $0.id, name: $0.name, icon: $0.icon, sortOrder: $0.sortOrder)
        }
        let backupActivities = allActivities.map {
            BackupActivity(id: $0.id, name: $0.name, projectId: $0.project?.id ?? UUID(), dailyGoal: $0.dailyGoal, sortOrder: $0.sortOrder)
        }
        let backupRecords = allRecords.map {
            BackupRecord(id: $0.id, activityId: $0.activity?.id ?? UUID(), duration: $0.duration, date: $0.date)
        }
        let backup = BackupData(projects: backupProjects, activities: backupActivities, records: backupRecords)
        if let data = try? JSONEncoder().encode(backup) {
            backupDocument = BackupDocument(data: data)
            showingExporter = true
        }
    }

    func restoreBackup(from url: URL) {
        guard url.startAccessingSecurityScopedResource() else { return }
        defer { url.stopAccessingSecurityScopedResource() }

        guard let data = try? Data(contentsOf: url),
              let backup = try? JSONDecoder().decode(BackupData.self, from: data) else {
            alertMessage = "파일을 읽을 수 없어요. 올바른 백업 파일인지 확인해주세요."
            showingSuccessAlert = true
            return
        }

        allRecords.forEach { modelContext.delete($0) }
        allActivities.forEach { modelContext.delete($0) }
        projects.forEach { modelContext.delete($0) }
        try? modelContext.save()

        var newProjects: [UUID: Project] = [:]
        for bp in backup.projects {
            let p = Project(id: bp.id, name: bp.name, icon: bp.icon, sortOrder: bp.sortOrder)
            modelContext.insert(p)
            newProjects[bp.id] = p
        }

        var newActivities: [UUID: Activity] = [:]
        for ba in backup.activities {
            guard let project = newProjects[ba.projectId] else { continue }
            let a = Activity(id: ba.id, name: ba.name, project: project, dailyGoal: ba.dailyGoal, sortOrder: ba.sortOrder)
            modelContext.insert(a)
            newActivities[ba.id] = a
        }

        for br in backup.records {
            guard let activity = newActivities[br.activityId] else { continue }
            let r = TimeRecord(id: br.id, activity: activity, duration: br.duration, date: br.date)
            modelContext.insert(r)
        }

        try? modelContext.save()

        alertMessage = "복원 완료! 프로젝트 \(backup.projects.count)개, 활동 \(backup.activities.count)개, 기록 \(backup.records.count)개를 불러왔어요."
        showingSuccessAlert = true
    }

    func backupFileName() -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        return "timeattck_backup_\(formatter.string(from: Date()))"
    }
}

// MARK: - 백업 데이터 구조

struct BackupProject: Codable {
    var id: UUID
    var name: String
    var icon: String
    var sortOrder: Int
}

struct BackupActivity: Codable {
    var id: UUID
    var name: String
    var projectId: UUID
    var dailyGoal: TimeInterval
    var sortOrder: Int
}

struct BackupRecord: Codable {
    var id: UUID
    var activityId: UUID
    var duration: TimeInterval
    var date: Date
}

struct BackupData: Codable {
    var projects: [BackupProject]
    var activities: [BackupActivity]
    var records: [BackupRecord]
}

// MARK: - FileDocument

struct BackupDocument: FileDocument {
    static var readableContentTypes: [UTType] { [.json] }
    var data: Data

    init(data: Data) {
        self.data = data
    }

    init(configuration: ReadConfiguration) throws {
        data = configuration.file.regularFileContents ?? Data()
    }

    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        FileWrapper(regularFileWithContents: data)
    }
}

#Preview {
    SettingsView()
        .modelContainer(sharedModelContainer)
}
