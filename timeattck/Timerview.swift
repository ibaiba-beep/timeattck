import SwiftUI

struct TimerView: View {
    @EnvironmentObject var dataModel: DataModel
    @State private var elapsedTime: TimeInterval = 0
    @State private var timer: Timer? = nil
    @State private var selectedProject: Project? = nil

    var body: some View {
            VStack(spacing: 0) {
                VStack(spacing: 16) {
                    Text(timeString(from: elapsedTime))
                        .font(.system(size: 64, weight: .thin, design: .monospaced))

                    if let project = selectedProject {
                        Text("\(project.name) 기록 중...")
                            .font(.headline)
                            .foregroundColor(.blue)
                    } else {
                        Text("프로젝트를 선택하면 자동으로 시작돼요")
                            .font(.subheadline)
                            .foregroundColor(.gray)
                    }
                }
                .padding(.top)

                Divider()
                    .padding(.vertical, 12)

                ScrollView {
                    VStack(spacing: 10) {
                        ForEach(dataModel.projects) { project in
                            Button(action: {
                                selectProject(project)
                            }) {
                                HStack {
                                    Text(project.name)
                                        .font(.body)
                                        .fontWeight(.medium)
                                        .lineLimit(1)
                                    Spacer()
                                    if selectedProject?.id == project.id {
                                        Image(systemName: "record.circle")
                                            .foregroundColor(.red)
                                    }
                                }
                                .padding()
                                .background(selectedProject?.id == project.id ? Color.blue.opacity(0.15) : Color.gray.opacity(0.1))
                                .cornerRadius(12)
                            }
                            .foregroundColor(.primary)
                        }
                    }
                    .padding(.horizontal)
                }

                if selectedProject != nil {
                    Button(action: {
                        stopAndSave()
                    }) {
                        Text("중단 및 저장")
                            .font(.body)
                            .fontWeight(.medium)
                            .foregroundColor(.white)
                            .frame(maxWidth: .infinity)
                            .padding()
                            .background(Color.red.opacity(0.8))
                            .cornerRadius(12)
                    }
                    .padding()
                }
            }
            .navigationTitle("타이머")
        }

    func selectProject(_ project: Project) {
        if let current = selectedProject {
            if current.id == project.id { return }
            if elapsedTime > 0 {
                dataModel.addRecord(projectId: current.id, duration: elapsedTime)
            }
        }
        elapsedTime = 0
        selectedProject = project
        startTimer()
    }

    func startTimer() {
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { _ in
            elapsedTime += 1
        }
    }

    func stopAndSave() {
        timer?.invalidate()
        timer = nil
        if let project = selectedProject, elapsedTime > 0 {
            dataModel.addRecord(projectId: project.id, duration: elapsedTime)
        }
        elapsedTime = 0
        selectedProject = nil
    }

    func timeString(from time: TimeInterval) -> String {
        let hours = Int(time) / 3600
        let minutes = Int(time) / 60 % 60
        let seconds = Int(time) % 60
        return String(format: "%02d:%02d:%02d", hours, minutes, seconds)
    }
}

#Preview {
    TimerView()
        .environmentObject(DataModel())
}
