// SocialDataService.swift
// timeattck
//
// 추상화 레이어 — Firebase ↔ CloudKit 교체 시 이 파일은 그대로 유지됩니다.

import Foundation

// MARK: - Models

struct UserProfile: Identifiable, Codable {
    let id: String          // Firebase UID
    var displayName: String
    var friends: [String]   // 친구 UID 목록
    var weeklyGoals: [String: Int]  // "2025-W17": 36000 (초 단위)
}

struct FriendStat: Identifiable, Codable {
    let id: String          // UID
    let displayName: String
    let totalSeconds: Int   // 이번 주 총 시간
    let date: Date
}

struct SharedGoal: Identifiable, Codable {
    let id: String
    var title: String
    var targetSeconds: Int  // 목표 시간 (초)
    var participants: [String]  // 참여자 UID 목록
    var weekKey: String     // "2025-W17"
    var createdAt: Date
}

struct RankEntry: Identifiable, Codable {
    let id: String          // UID
    let displayName: String
    let totalSeconds: Int
    var rank: Int
}

struct FriendRequest: Identifiable, Codable {
    let id: String
    let fromUID: String
    let fromDisplayName: String
    let toUID: String
    var status: FriendRequestStatus
    let createdAt: Date
}

enum FriendRequestStatus: String, Codable {
    case pending
    case accepted
    case declined
}

// MARK: - Protocol

/// 소셜 기능 추상화 프로토콜
/// Firebase 구현체: FirebaseSocialService
/// CloudKit 전환 시: CloudKitSocialService 로 교체
protocol SocialDataService {

    // MARK: 인증
    /// 현재 로그인된 유저 UID 반환 (없으면 nil)
    var currentUserUID: String? { get }

    /// Apple Sign-In 요청 전 nonce 준비 — 반환값을 ASAuthorizationPasswordRequest.nonce에 전달
    func prepareAppleSignIn() -> String

    /// Apple idToken + rawNonce로 Firebase 로그인 후 프로필 반환
    func signInWithApple(idToken: String, displayName: String?) async throws -> UserProfile

    /// 로그아웃
    func signOut() throws

    // MARK: 프로필
    /// 내 프로필 가져오기
    func fetchMyProfile() async throws -> UserProfile

    /// 프로필 업데이트
    func updateProfile(displayName: String) async throws

    // MARK: 친구
    /// 친구 요청 보내기 (displayName으로 검색)
    func sendFriendRequest(toDisplayName: String) async throws

    /// 받은 친구 요청 목록
    func fetchFriendRequests() async throws -> [FriendRequest]

    /// 친구 요청 수락/거절
    func respondToFriendRequest(requestId: String, accept: Bool) async throws

    /// 친구 목록 가져오기
    func fetchFriends() async throws -> [UserProfile]

    // MARK: 통계
    /// 친구의 이번 주 시간 통계
    func fetchFriendStats(friendUID: String) async throws -> [FriendStat]

    /// 친구들 전체 통계 (피드용)
    func fetchAllFriendsStats() async throws -> [FriendStat]

    // MARK: 공유 목표
    /// 공유 목표 생성
    func createSharedGoal(_ goal: SharedGoal) async throws

    /// 내가 참여 중인 공유 목표 목록
    func fetchSharedGoals() async throws -> [SharedGoal]

    /// 공유 목표 수정
    func updateSharedGoal(_ goal: SharedGoal) async throws

    /// 공유 목표 삭제
    func deleteSharedGoal(goalId: String) async throws

    // MARK: 랭킹
    /// 이번 주 친구 랭킹
    func fetchWeeklyRanking() async throws -> [RankEntry]

    /// 특정 주 랭킹 (weekKey: "2025-W17")
    func fetchRanking(for weekKey: String) async throws -> [RankEntry]
}

// MARK: - Helper

extension SocialDataService {
    /// 현재 주의 weekKey 반환 (예: "2025-W17")
    func currentWeekKey() -> String {
        let calendar = Calendar.current
        let week = calendar.component(.weekOfYear, from: Date())
        let year = calendar.component(.yearForWeekOfYear, from: Date())
        return "\(year)-W\(String(format: "%02d", week))"
    }
}
