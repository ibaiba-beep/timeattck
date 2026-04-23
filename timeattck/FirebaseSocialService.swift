// FirebaseSocialService.swift
// timeattck
//
// SocialDataService의 Firebase 구현체
// 나중에 CloudKit으로 전환할 때는 이 파일을 CloudKitSocialService.swift로 교체하면 됩니다.

import Foundation
import FirebaseAuth
import FirebaseFirestore

// MARK: - Firebase Keys

private enum Collection {
    static let users = "users"
    static let timeRecords = "timeRecords"
    static let friendRequests = "friendRequests"
    static let sharedGoals = "sharedGoals"
    static let weeklyRankings = "weeklyRankings"
}

// MARK: - FirebaseSocialService

final class FirebaseSocialService: SocialDataService {

    private let db = Firestore.firestore()
    private let auth = Auth.auth()

    // MARK: 인증

    var currentUserUID: String? {
        auth.currentUser?.uid
    }

    func signInWithApple() async throws -> UserProfile {
        // Apple Sign-In은 AuthViewModel에서 처리 후 여기서 프로필 생성
        guard let uid = auth.currentUser?.uid,
              let displayName = auth.currentUser?.displayName else {
            throw SocialError.notAuthenticated
        }

        // Firestore에 유저 문서가 없으면 생성
        let ref = db.collection(Collection.users).document(uid)
        let snapshot = try await ref.getDocument()

        if !snapshot.exists {
            let profile = UserProfile(
                id: uid,
                displayName: displayName,
                friends: [],
                weeklyGoals: [:]
            )
            try ref.setData(from: profile)
            return profile
        }

        return try snapshot.data(as: UserProfile.self)
    }

    func signOut() throws {
        try auth.signOut()
    }

    // MARK: 프로필

    func fetchMyProfile() async throws -> UserProfile {
        guard let uid = currentUserUID else { throw SocialError.notAuthenticated }
        let snapshot = try await db.collection(Collection.users).document(uid).getDocument()
        return try snapshot.data(as: UserProfile.self)
    }

    func updateProfile(displayName: String) async throws {
        guard let uid = currentUserUID else { throw SocialError.notAuthenticated }
        try await db.collection(Collection.users).document(uid).updateData([
            "displayName": displayName
        ])
    }

    // MARK: 친구

    func sendFriendRequest(toDisplayName: String) async throws {
        guard let fromUID = currentUserUID else { throw SocialError.notAuthenticated }

        // displayName으로 유저 검색
        let snapshot = try await db.collection(Collection.users)
            .whereField("displayName", isEqualTo: toDisplayName)
            .limit(to: 1)
            .getDocuments()

        guard let toDoc = snapshot.documents.first else {
            throw SocialError.userNotFound
        }
        let toUID = toDoc.documentID

        guard toUID != fromUID else { throw SocialError.cannotAddSelf }

        // 내 프로필에서 displayName 가져오기
        let myProfile = try await fetchMyProfile()

        let request = FriendRequest(
            id: UUID().uuidString,
            fromUID: fromUID,
            fromDisplayName: myProfile.displayName,
            toUID: toUID,
            status: .pending,
            createdAt: Date()
        )
        try db.collection(Collection.friendRequests).document(request.id).setData(from: request)
    }

    func fetchFriendRequests() async throws -> [FriendRequest] {
        guard let uid = currentUserUID else { throw SocialError.notAuthenticated }
        let snapshot = try await db.collection(Collection.friendRequests)
            .whereField("toUID", isEqualTo: uid)
            .whereField("status", isEqualTo: FriendRequestStatus.pending.rawValue)
            .getDocuments()
        return try snapshot.documents.map { try $0.data(as: FriendRequest.self) }
    }

    func respondToFriendRequest(requestId: String, accept: Bool) async throws {
        guard let uid = currentUserUID else { throw SocialError.notAuthenticated }

        let ref = db.collection(Collection.friendRequests).document(requestId)
        let request = try await ref.getDocument().data(as: FriendRequest.self)

        if accept {
            // 양쪽 friends 배열에 추가
            let batch = db.batch()
            let myRef = db.collection(Collection.users).document(uid)
            let friendRef = db.collection(Collection.users).document(request.fromUID)

            batch.updateData(["friends": FieldValue.arrayUnion([request.fromUID])], forDocument: myRef)
            batch.updateData(["friends": FieldValue.arrayUnion([uid])], forDocument: friendRef)
            batch.updateData(["status": FriendRequestStatus.accepted.rawValue], forDocument: ref)

            try await batch.commit()
        } else {
            try await ref.updateData(["status": FriendRequestStatus.declined.rawValue])
        }
    }

    func fetchFriends() async throws -> [UserProfile] {
        let myProfile = try await fetchMyProfile()
        guard !myProfile.friends.isEmpty else { return [] }

        // Firestore는 한 번에 최대 10개 in 쿼리
        let chunks = myProfile.friends.chunked(into: 10)
        var profiles: [UserProfile] = []

        for chunk in chunks {
            let snapshot = try await db.collection(Collection.users)
                .whereField(FieldPath.documentID(), in: chunk)
                .getDocuments()
            let batch = try snapshot.documents.map { try $0.data(as: UserProfile.self) }
            profiles.append(contentsOf: batch)
        }
        return profiles
    }

    // MARK: 통계

    func fetchFriendStats(friendUID: String) async throws -> [FriendStat] {
        let weekStart = Calendar.current.startOfWeek(for: Date())

        let snapshot = try await db.collection(Collection.timeRecords)
            .whereField("uid", isEqualTo: friendUID)
            .whereField("isPublic", isEqualTo: true)
            .whereField("date", isGreaterThanOrEqualTo: weekStart)
            .getDocuments()

        // 날짜별로 합산
        var dailyTotals: [String: Int] = [:]
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"

        for doc in snapshot.documents {
            let data = doc.data()
            let duration = data["duration"] as? Int ?? 0
            if let timestamp = data["date"] as? Timestamp {
                let key = formatter.string(from: timestamp.dateValue())
                dailyTotals[key, default: 0] += duration
            }
        }

        // 친구 이름 가져오기
        let friendDoc = try await db.collection(Collection.users).document(friendUID).getDocument()
        let friendProfile = try friendDoc.data(as: UserProfile.self)

        return dailyTotals.map { key, seconds in
            FriendStat(
                id: "\(friendUID)-\(key)",
                displayName: friendProfile.displayName,
                totalSeconds: seconds,
                date: formatter.date(from: key) ?? Date()
            )
        }.sorted { $0.date < $1.date }
    }

    func fetchAllFriendsStats() async throws -> [FriendStat] {
        let friends = try await fetchFriends()
        var allStats: [FriendStat] = []

        for friend in friends {
            let stats = try await fetchFriendStats(friendUID: friend.id)
            let totalSeconds = stats.reduce(0) { $0 + $1.totalSeconds }
            let summary = FriendStat(
                id: friend.id,
                displayName: friend.displayName,
                totalSeconds: totalSeconds,
                date: Date()
            )
            allStats.append(summary)
        }

        return allStats.sorted { $0.totalSeconds > $1.totalSeconds }
    }

    // MARK: 공유 목표

    func createSharedGoal(_ goal: SharedGoal) async throws {
        try db.collection(Collection.sharedGoals).document(goal.id).setData(from: goal)
    }

    func fetchSharedGoals() async throws -> [SharedGoal] {
        guard let uid = currentUserUID else { throw SocialError.notAuthenticated }
        let snapshot = try await db.collection(Collection.sharedGoals)
            .whereField("participants", arrayContains: uid)
            .getDocuments()
        return try snapshot.documents.map { try $0.data(as: SharedGoal.self) }
    }

    func updateSharedGoal(_ goal: SharedGoal) async throws {
        try db.collection(Collection.sharedGoals).document(goal.id).setData(from: goal, merge: true)
    }

    func deleteSharedGoal(goalId: String) async throws {
        try await db.collection(Collection.sharedGoals).document(goalId).delete()
    }

    // MARK: 랭킹

    func fetchWeeklyRanking() async throws -> [RankEntry] {
        try await fetchRanking(for: currentWeekKey())
    }

    func fetchRanking(for weekKey: String) async throws -> [RankEntry] {
        let snapshot = try await db.collection(Collection.weeklyRankings)
            .document(weekKey)
            .getDocument()

        guard snapshot.exists,
              let rankings = snapshot.data()?["rankings"] as? [[String: Any]] else {
            return []
        }

        return rankings.enumerated().compactMap { index, dict in
            guard let uid = dict["uid"] as? String,
                  let name = dict["displayName"] as? String,
                  let seconds = dict["totalSeconds"] as? Int else { return nil }
            return RankEntry(id: uid, displayName: name, totalSeconds: seconds, rank: index + 1)
        }
    }
}

// MARK: - Errors

enum SocialError: LocalizedError {
    case notAuthenticated
    case userNotFound
    case cannotAddSelf

    var errorDescription: String? {
        switch self {
        case .notAuthenticated: return "로그인이 필요합니다."
        case .userNotFound: return "해당 사용자를 찾을 수 없습니다."
        case .cannotAddSelf: return "자기 자신은 추가할 수 없습니다."
        }
    }
}

// MARK: - Extensions

private extension Array {
    func chunked(into size: Int) -> [[Element]] {
        stride(from: 0, to: count, by: size).map {
            Array(self[$0..<Swift.min($0 + size, count)])
        }
    }
}

private extension Calendar {
    func startOfWeek(for date: Date) -> Date {
        let components = dateComponents([.yearForWeekOfYear, .weekOfYear], from: date)
        return self.date(from: components) ?? date
    }
}
