// SocialView.swift
// timeattck
//
// 소셜 기능 메인 뷰 (친구 통계 / 랭킹 / 공유 목표)

import SwiftUI
import AuthenticationServices

// MARK: - SocialView (탭 진입점)

struct SocialView: View {
    @StateObject private var vm = SocialViewModel()
    @State private var selectedTab = 0

    var body: some View {
        Group {
            if vm.isSignedIn {
                mainView
            } else {
                loginView
            }
        }
        .alert("오류", isPresented: .constant(vm.errorMessage != nil)) {
            Button("확인") { vm.errorMessage = nil }
        } message: {
            Text(vm.errorMessage ?? "")
        }
    }

    // MARK: - 로그인 화면

    var loginView: some View {
        NavigationStack {
            VStack(spacing: 32) {
                Spacer()
                VStack(spacing: 16) {
                    Image(systemName: "person.2.circle.fill")
                        .font(.system(size: 72))
                        .foregroundStyle(.blue)
                    Text("소셜")
                        .font(.largeTitle).bold()
                    Text("친구와 함께 시간을 기록해보세요.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }
                Spacer()
                SignInWithAppleButton(.signIn) { request in
                    request.requestedScopes = [.fullName, .email]
                    request.nonce = vm.prepareSignIn()
                } onCompletion: { result in
                    switch result {
                    case .success(let auth):
                        guard let cred = auth.credential as? ASAuthorizationAppleIDCredential,
                              let tokenData = cred.identityToken,
                              let token = String(data: tokenData, encoding: .utf8) else { return }
                        let name = [cred.fullName?.givenName, cred.fullName?.familyName]
                            .compactMap { $0 }.joined(separator: " ")
                        Task { await vm.completeAppleSignIn(idToken: token, displayName: name.isEmpty ? nil : name) }
                    case .failure(let error):
                        vm.errorMessage = error.localizedDescription
                    }
                }
                .signInWithAppleButtonStyle(.black)
                .frame(height: 50)
                .padding(.horizontal, 40)
                .padding(.bottom, 60)
            }
            .navigationTitle("소셜")
        }
    }

    // MARK: - 메인 화면

    var mainView: some View {
        NavigationStack {
            VStack(spacing: 0) {
                Picker("탭", selection: $selectedTab) {
                    Text("친구").tag(0)
                    Text("랭킹").tag(1)
                    Text("공유 목표").tag(2)
                }
                .pickerStyle(.segmented)
                .padding()

                TabView(selection: $selectedTab) {
                    FriendsStatsView(vm: vm).tag(0)
                    WeeklyRankingView(vm: vm).tag(1)
                    SharedGoalsView(vm: vm).tag(2)
                }
                .tabViewStyle(.page(indexDisplayMode: .never))
            }
            .navigationTitle("소셜")
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    NavigationLink {
                        FriendRequestsView(vm: vm)
                    } label: {
                        ZStack(alignment: .topTrailing) {
                            Image(systemName: "person.badge.plus")
                            if !vm.friendRequests.isEmpty {
                                Circle()
                                    .fill(.red)
                                    .frame(width: 8, height: 8)
                            }
                        }
                    }
                }
            }
        }
        .task { await vm.loadAll() }
    }
}

// MARK: - 친구 통계 뷰

struct FriendsStatsView: View {
    @ObservedObject var vm: SocialViewModel
    @State private var searchName = ""

    var body: some View {
        List {
            // 친구 추가
            Section {
                HStack {
                    TextField("닉네임으로 친구 추가", text: $searchName)
                    Button {
                        Task { await vm.sendFriendRequest(to: searchName) }
                    } label: {
                        Image(systemName: "plus.circle.fill")
                    }
                    .disabled(searchName.isEmpty)
                }
                if let result = vm.searchResult {
                    Text(result)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            // 친구 이번 주 통계
            Section("이번 주 친구 현황") {
                if vm.allFriendsStats.isEmpty {
                    Text("친구를 추가해보세요!")
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(vm.allFriendsStats) { stat in
                        FriendStatRow(stat: stat, vm: vm)
                    }
                }
            }
        }
        .refreshable { await vm.loadFriendsStats() }
    }
}

struct FriendStatRow: View {
    let stat: FriendStat
    let vm: SocialViewModel

    var body: some View {
        HStack {
            Circle()
                .fill(.blue.opacity(0.2))
                .frame(width: 36, height: 36)
                .overlay {
                    Text(String(stat.displayName.prefix(1)))
                        .font(.headline)
                }

            VStack(alignment: .leading, spacing: 2) {
                Text(stat.displayName)
                    .font(.subheadline).bold()
                Text("이번 주 \(vm.formattedTime(stat.totalSeconds))")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()

            // 간단한 진행 바
            ProgressView(value: min(Double(stat.totalSeconds) / (40 * 3600), 1.0))
                .frame(width: 60)
                .tint(.blue)
        }
    }
}

// MARK: - 주간 랭킹 뷰

struct WeeklyRankingView: View {
    @ObservedObject var vm: SocialViewModel

    var body: some View {
        List {
            Section("이번 주 랭킹") {
                if vm.weeklyRanking.isEmpty {
                    Text("아직 랭킹 데이터가 없어요")
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(vm.weeklyRanking) { entry in
                        RankRow(entry: entry, vm: vm)
                    }
                }
            }
        }
        .refreshable { await vm.loadWeeklyRanking() }
    }
}

struct RankRow: View {
    let entry: RankEntry
    let vm: SocialViewModel

    var rankColor: Color {
        switch entry.rank {
        case 1: return .yellow
        case 2: return .gray
        case 3: return .brown
        default: return .clear
        }
    }

    var body: some View {
        HStack(spacing: 12) {
            // 순위
            ZStack {
                Circle()
                    .fill(rankColor.opacity(0.2))
                    .frame(width: 32, height: 32)
                Text("\(entry.rank)")
                    .font(.headline)
                    .foregroundStyle(entry.rank <= 3 ? rankColor : .secondary)
            }

            // 이름
            Text(entry.displayName)
                .font(.subheadline)

            Spacer()

            // 시간
            Text(vm.formattedTime(entry.totalSeconds))
                .font(.subheadline).bold()
                .foregroundStyle(.blue)
        }
    }
}

// MARK: - 공유 목표 뷰

struct SharedGoalsView: View {
    @ObservedObject var vm: SocialViewModel
    @State private var showingNewGoal = false

    var body: some View {
        List {
            Section {
                Button {
                    showingNewGoal = true
                } label: {
                    Label("새 공유 목표 만들기", systemImage: "plus.circle")
                }
            }

            Section("진행 중인 목표") {
                if vm.sharedGoals.isEmpty {
                    Text("함께할 목표를 만들어보세요!")
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(vm.sharedGoals) { goal in
                        SharedGoalRow(goal: goal, vm: vm)
                    }
                }
            }
        }
        .refreshable { await vm.loadSharedGoals() }
        .sheet(isPresented: $showingNewGoal) {
            NewSharedGoalView(vm: vm, isPresented: $showingNewGoal)
        }
    }
}

struct SharedGoalRow: View {
    let goal: SharedGoal
    let vm: SocialViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(goal.title)
                .font(.subheadline).bold()
            HStack {
                Text("목표: \(vm.formattedTime(goal.targetSeconds))")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                Text("참여 \(goal.participants.count)명")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 4)
    }
}

// MARK: - 새 공유 목표 Sheet

struct NewSharedGoalView: View {
    @ObservedObject var vm: SocialViewModel
    @Binding var isPresented: Bool

    @State private var title = ""
    @State private var targetHours: Double = 10
    @State private var selectedFriends: Set<String> = []

    var body: some View {
        NavigationStack {
            Form {
                Section("목표 이름") {
                    TextField("예: 이번 주 각자 10시간!", text: $title)
                }
                Section("목표 시간") {
                    HStack {
                        Slider(value: $targetHours, in: 1...100, step: 1)
                        Text("\(Int(targetHours))h")
                            .frame(width: 40)
                    }
                }
                Section("참여 친구") {
                    ForEach(vm.friends) { friend in
                        HStack {
                            Text(friend.displayName)
                            Spacer()
                            if selectedFriends.contains(friend.id) {
                                Image(systemName: "checkmark")
                                    .foregroundStyle(.blue)
                            }
                        }
                        .contentShape(Rectangle())
                        .onTapGesture {
                            if selectedFriends.contains(friend.id) {
                                selectedFriends.remove(friend.id)
                            } else {
                                selectedFriends.insert(friend.id)
                            }
                        }
                    }
                }
            }
            .navigationTitle("공유 목표 만들기")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("취소") { isPresented = false }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("만들기") {
                        Task {
                            await vm.createSharedGoal(
                                title: title,
                                targetHours: targetHours,
                                friendUIDs: Array(selectedFriends)
                            )
                            isPresented = false
                        }
                    }
                    .disabled(title.isEmpty || selectedFriends.isEmpty)
                }
            }
        }
    }
}

// MARK: - 친구 요청 뷰

struct FriendRequestsView: View {
    @ObservedObject var vm: SocialViewModel

    var body: some View {
        List {
            if vm.friendRequests.isEmpty {
                Text("받은 친구 요청이 없어요")
                    .foregroundStyle(.secondary)
            } else {
                ForEach(vm.friendRequests) { request in
                    HStack {
                        VStack(alignment: .leading) {
                            Text(request.fromDisplayName)
                                .font(.subheadline).bold()
                            Text("친구 요청을 보냈어요")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        Button("수락") {
                            Task { await vm.acceptFriendRequest(request) }
                        }
                        .buttonStyle(.borderedProminent)
                        .controlSize(.small)

                        Button("거절") {
                            Task { await vm.declineFriendRequest(request) }
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                    }
                }
            }
        }
        .navigationTitle("친구 요청")
    }
}
