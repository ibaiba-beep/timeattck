// SocialViewModel.swift
// timeattck
//
// SwiftUI View들이 사용하는 ViewModel
// SocialDataService 프로토콜에만 의존하므로 Firebase/CloudKit 구분 없음

import SwiftUI
import Combine

@MainActor
final class SocialViewModel: ObservableObject {

    // MARK: - Published State

    @Published var friends: [UserProfile] = []
    @Published var friendRequests: [FriendRequest] = []
    @Published var allFriendsStats: [FriendStat] = []
    @Published var weeklyRanking: [RankEntry] = []
    @Published var sharedGoals: [SharedGoal] = []
    @Published var myProfile: UserProfile?

    @Published var isLoading = false
    @Published var errorMessage: String?
    @Published var searchResult: String?  // 친구 검색 결과 메시지

    // MARK: - Dependencies

    private let service: SocialDataService

    // MARK: - Init

    /// Firebase 사용: SocialViewModel()
    /// CloudKit 전환 시: SocialViewModel(service: CloudKitSocialService())
    init(service: SocialDataService? = nil) {
        let svc = service ?? FirebaseSocialService()
        self.service = svc
        self.isSignedIn = svc.currentUserUID != nil
    }

    // MARK: - Auth

    @Published var isSignedIn: Bool = false

    func prepareSignIn() -> String {
        service.prepareAppleSignIn()
    }

    func completeAppleSignIn(idToken: String, displayName: String?) async {
        do {
            myProfile = try await service.signInWithApple(idToken: idToken, displayName: displayName)
            isSignedIn = true
            await loadAll()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func signOut() {
        do {
            try service.signOut()
            isSignedIn = false
            clearState()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    // MARK: - Load

    func loadAll() async {
        guard isSignedIn else { return }
        isLoading = true
        defer { isLoading = false }

        await withTaskGroup(of: Void.self) { group in
            group.addTask { await self.loadMyProfile() }
            group.addTask { await self.loadFriends() }
            group.addTask { await self.loadFriendRequests() }
            group.addTask { await self.loadWeeklyRanking() }
            group.addTask { await self.loadSharedGoals() }
        }
    }

    func loadMyProfile() async {
        do { myProfile = try await service.fetchMyProfile() }
        catch { errorMessage = error.localizedDescription }
    }

    func loadFriends() async {
        do { friends = try await service.fetchFriends() }
        catch { errorMessage = error.localizedDescription }
    }

    func loadFriendRequests() async {
        do { friendRequests = try await service.fetchFriendRequests() }
        catch { errorMessage = error.localizedDescription }
    }

    func loadWeeklyRanking() async {
        do { weeklyRanking = try await service.fetchWeeklyRanking() }
        catch { errorMessage = error.localizedDescription }
    }

    func loadSharedGoals() async {
        do { sharedGoals = try await service.fetchSharedGoals() }
        catch { errorMessage = error.localizedDescription }
    }

    func loadFriendsStats() async {
        do { allFriendsStats = try await service.fetchAllFriendsStats() }
        catch { errorMessage = error.localizedDescription }
    }

    // MARK: - Actions

    func sendFriendRequest(to displayName: String) async {
        isLoading = true
        defer { isLoading = false }
        do {
            try await service.sendFriendRequest(toDisplayName: displayName)
            searchResult = "'\(displayName)'님에게 친구 요청을 보냈어요!"
        } catch {
            searchResult = error.localizedDescription
        }
    }

    func acceptFriendRequest(_ request: FriendRequest) async {
        do {
            try await service.respondToFriendRequest(requestId: request.id, accept: true)
            friendRequests.removeAll { $0.id == request.id }
            await loadFriends()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func declineFriendRequest(_ request: FriendRequest) async {
        do {
            try await service.respondToFriendRequest(requestId: request.id, accept: false)
            friendRequests.removeAll { $0.id == request.id }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func createSharedGoal(title: String, targetHours: Double, friendUIDs: [String]) async {
        guard let myUID = service.currentUserUID else { return }
        let goal = SharedGoal(
            id: UUID().uuidString,
            title: title,
            targetSeconds: Int(targetHours * 3600),
            participants: [myUID] + friendUIDs,
            weekKey: service.currentWeekKey(),
            createdAt: Date()
        )
        do {
            try await service.createSharedGoal(goal)
            await loadSharedGoals()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    // MARK: - Helpers

    func formattedTime(_ seconds: Int) -> String {
        let hours = seconds / 3600
        let minutes = (seconds % 3600) / 60
        if hours > 0 { return "\(hours)h \(minutes)m" }
        return "\(minutes)m"
    }

    private func clearState() {
        friends = []
        friendRequests = []
        allFriendsStats = []
        weeklyRanking = []
        sharedGoals = []
        myProfile = nil
    }
}
